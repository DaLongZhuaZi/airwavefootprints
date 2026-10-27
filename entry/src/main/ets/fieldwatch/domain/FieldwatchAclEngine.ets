/**
 * ACL 引擎（《主动扫描授权与隐私体系设计》v2 第 2.3 节）。
 *
 * **引擎是 App 内唯一的 socket 创建入口。**
 * 任务代码不得直接建 socket，一律向引擎申请（主体 + 能力 + 目标），
 * 引擎按设计文档 2.3 的五步顺序核对：
 *   1. 任务绑定 —— 该任务是否被允许用该能力
 *   2. 会话授权 —— 本次扫描会话是否已获用户确认
 *   3. 目标范围 —— 目标是否在允许集合内且不在排除项内
 *   4. 速率 / 并发 —— 是否超上限
 *   5. 审计记账 —— 放行与拒绝都记，拒绝本身也是一条可查记录
 *
 * 治理铁律（2.4）：
 *   · **默认拒绝**：未登记能力一律拒绝
 *   · **失败关闭**：授权状态不明 / 范围推导失败 / 审计写失败 → 拒绝放行，不得「先放行后补记」
 *
 * 本模块不做 IO，只做判定；真正的 socket 创建在 `FieldwatchAclTransport`，
 * 而那个文件是**唯一**允许出现 socket 构造调用的地方。
 */

import { logger } from 'ngf_framework';
import {
  aclEntryOf, AclCapability, AclSubject, ACL_TABLE_VERSION, aclLimits, AclLimits, portAllowed, taskAllows
} from './FieldwatchAcl';
import { AclScope, targetVerdict, TargetVerdict } from './FieldwatchAclScope';

const TAG: string = 'FieldwatchAclEngine';

/** 放行 / 拒绝的理由（审计与单测都靠它断言，不用字符串比对）。 */
export enum AclDenyReason {
  /** 未放行。 */
  NONE = 'none',
  /** 能力未在 ACL 表登记（默认拒绝）。 */
  UNREGISTERED_CAPABILITY = 'unregistered_capability',
  /** 该任务未被授权此能力。 */
  TASK_NOT_ALLOWED = 'task_not_allowed',
  /** 本次会话未获用户确认。 */
  NO_SESSION_GRANT = 'no_session_grant',
  /** 用户已在设置页关闭该能力。 */
  CAPABILITY_DISABLED = 'capability_disabled',
  /** 目标范围不可用（推导失败）。 */
  SCOPE_UNKNOWN = 'scope_unknown',
  /** 目标越界。 */
  TARGET_OUT_OF_SCOPE = 'target_out_of_scope',
  /** 端口不在白名单。 */
  PORT_NOT_ALLOWED = 'port_not_allowed',
  /** 超出并发上限。 */
  CONCURRENCY_EXCEEDED = 'concurrency_exceeded',
  /** 超出总时长上限。 */
  DURATION_EXCEEDED = 'duration_exceeded',
  /** 扫描已被取消。 */
  CANCELLED = 'cancelled'
}

/** 一次放行判定的结果。 */
export class AclDecision {
  public allowed: boolean = false;
  public reason: AclDenyReason = AclDenyReason.NONE;
  constructor(allowed: boolean = false, reason: AclDenyReason = AclDenyReason.NONE) {
    this.allowed = allowed;
    this.reason = reason;
  }
}

/** 审计记录（设计文档 7.2 限定的字段，一个不多）。 */
export class AclAuditRecord {
  public id: string = '';
  public at: number = 0;
  public subject: string = '';
  public capability: string = '';
  /** 目标范围（网段字符串，不是逐台地址）。 */
  public scope: string = '';
  /** 结果数（放行时 = 实际探测数；拒绝时 = 0）。 */
  public resultCount: number = 0;
  public success: boolean = false;
  /** 拒绝理由（放行时为空）。用 string 而不是枚举：审计要能跨版本读旧记录。 */
  public denyReason: string = '';
  /** ACL 表版本，事后可追溯当时按哪版规则放行。 */
  public tableVersion: number = ACL_TABLE_VERSION;
  constructor() {}
}

/**
 * 审计落库接口。
 *
 * 抽成接口而不是直接依赖仓储：
 * ① 让引擎可单测（假实现即可断言记账行为）；
 * ② 让「审计写失败 → 拒绝放行」这条规则可测（假实现返回 false 即可）。
 */
export interface IAclAuditSink {
  append(record: AclAuditRecord): Promise<boolean>;
}

/**
 * 会话授权状态。
 *
 * 设计文档第 6 节：授权**仅对本次扫描会话有效**，会话结束（完成 / 取消 / 切后台 / 断网）即失效。
 * 因此这里没有「长期授权」字段 —— 每次扫描都重新通报。
 */
export class AclSession {
  /** 是否已获本次会话授权。 */
  public granted: boolean = false;
  /** 本会话允许的能力（用户确认时定下，会话内不变）。 */
  public capabilities: AclCapability[] = [];
  /** 会话开始时刻。 */
  public startedAt: number = 0;
  /** 是否已取消（取消即关全部 socket）。 */
  public cancelled: boolean = false;
  /** 已发出的探测数（用于并发与总时长判定）。 */
  public issued: number = 0;
  /** 当前在途数。 */
  public inFlight: number = 0;
  constructor() {}
  allows(capability: AclCapability): boolean {
    if (!this.granted) return false;
    return this.capabilities.indexOf(capability) >= 0;
  }
}

/** 设置页里用户手动关闭的能力集合（关闭后需手动重开，设计文档第 6 节第 4 点）。 */
export class AclDisabledSet {
  private disabled: AclCapability[] = [];
  constructor() {}
  isDisabled(capability: AclCapability): boolean { return this.disabled.indexOf(capability) >= 0; }
  disable(capability: AclCapability): void {
    if (this.isDisabled(capability)) return;
    this.disabled.push(capability);
  }
  enable(capability: AclCapability): void {
    const index: number = this.disabled.indexOf(capability);
    if (index >= 0) this.disabled.splice(index, 1);
  }
  all(): AclCapability[] { return this.disabled.slice(); }
  /** 一键关闭全部（阶段三设置页用）。 */
  disableAll(all: AclCapability[]): void {
    all.forEach((capability: AclCapability): void => { this.disable(capability); });
  }
}

/**
 * ACL 引擎。
 *
 * 用法：先 `grantSession` 拿到会话，再用 `request` 逐次申请；每次申请都会记账。
 */
export class FieldwatchAclEngine {
  private audit: IAclAuditSink;
  private session: AclSession = new AclSession();
  private disabled: AclDisabledSet = new AclDisabledSet();
  private limits: AclLimits = aclLimits();
  private scope: AclScope = new AclScope();
  private seq: number = 0;

  constructor(audit: IAclAuditSink) { this.audit = audit; }

  /** 设置本次扫描的目标范围（由 `scopeFromLocal` 产出）。 */
  setScope(scope: AclScope): void { this.scope = scope; }

  /** 当前范围（只读用途，例如弹窗要展示网段）。 */
  currentScope(): AclScope { return this.scope; }

  /** 用户确认授权：开一个新会话。授权仅对本会话有效。 */
  grantSession(capabilities: AclCapability[]): AclSession {
    this.session = new AclSession();
    this.session.granted = true;
    this.session.capabilities = capabilities.slice();
    this.session.startedAt = Date.now();
    return this.session;
  }

  /** 结束会话（完成 / 取消 / 切后台 / 断网都调这里）。之后一切申请都会被拒。 */
  endSession(cancelled: boolean): void {
    this.session.granted = false;
    this.session.cancelled = cancelled;
    this.session.capabilities = [];
  }

  /** 当前会话引用（供 transport 更新在途数）。 */
  currentSession(): AclSession { return this.session; }

  /** 用户手动关闭 / 开启某项能力。 */
  setCapabilityDisabled(capability: AclCapability, disabled: boolean): void {
    if (disabled) this.disabled.disable(capability);
    else this.disabled.enable(capability);
  }

  /** 一键关闭全部主动能力。 */
  disableAll(capabilities: AclCapability[]): void { this.disabled.disableAll(capabilities); }

  /** 某项能力当前是否被用户关闭。 */
  isDisabled(capability: AclCapability): boolean { return this.disabled.isDisabled(capability); }

  /**
   * 申请放行。按设计文档 2.3 的五步顺序核对，**每一步失败都立刻拒绝并记账**。
   *
   * @param subject    任务主体
   * @param capability 主动能力
   * @param target     目标地址（A6 的组播目标同样要过范围检查）
   * @param port       目标端口（0 表示该能力不涉及端口）
   */
  async request(subject: AclSubject, capability: AclCapability, target: string,
    port: number): Promise<AclDecision> {
    // ① 默认拒绝：能力未登记。
    if (aclEntryOf(capability) === undefined) {
      return await this.deny(subject, capability, AclDenyReason.UNREGISTERED_CAPABILITY);
    }
    // ② 任务绑定。
    if (!taskAllows(subject, capability)) {
      return await this.deny(subject, capability, AclDenyReason.TASK_NOT_ALLOWED);
    }
    // ③ 用户是否在设置页关掉了这一项。
    if (this.disabled.isDisabled(capability)) {
      return await this.deny(subject, capability, AclDenyReason.CAPABILITY_DISABLED);
    }
    // ④ 会话授权。
    if (!this.session.allows(capability)) {
      return await this.deny(subject, capability, AclDenyReason.NO_SESSION_GRANT);
    }
    // ⑤ 取消：取消即拒绝，且 transport 负责关全部 socket。
    if (this.session.cancelled) {
      return await this.deny(subject, capability, AclDenyReason.CANCELLED);
    }
    // ⑥ 目标范围（失败关闭：范围不可用即拒绝）。
    const verdict: TargetVerdict = targetVerdict(this.scope, target);
    if (verdict !== TargetVerdict.ALLOWED) {
      return await this.deny(subject, capability, AclDenyReason.TARGET_OUT_OF_SCOPE);
    }
    // ⑦ 端口白名单（A2 有端口语义；其他能力传 0 跳过）。
    if (port > 0 && !portAllowed(port)) {
      return await this.deny(subject, capability, AclDenyReason.PORT_NOT_ALLOWED);
    }
    // ⑧ 并发与总时长。
    if (this.session.inFlight >= this.limits.maxConcurrency) {
      return await this.deny(subject, capability, AclDenyReason.CONCURRENCY_EXCEEDED);
    }
    if (this.session.startedAt > 0 && Date.now() - this.session.startedAt > this.limits.totalDurationMs) {
      return await this.deny(subject, capability, AclDenyReason.DURATION_EXCEEDED);
    }
    // ⑨ 放行 + 记账。审计写失败时**失败关闭**（设计文档 2.4）。
    const record: AclAuditRecord = this.newRecord(subject, capability, true, AclDenyReason.NONE);
    const ok: boolean = await this.audit.append(record);
    if (!ok) {
      logger.warn(TAG, '审计写入失败，按失败关闭拒绝放行');
      return new AclDecision(false, AclDenyReason.NONE);
    }
    return new AclDecision(true, AclDenyReason.NONE);
  }

  /** 记一条拒绝并返回。 */
  private async deny(subject: AclSubject, capability: AclCapability,
    reason: AclDenyReason): Promise<AclDecision> {
    const record: AclAuditRecord = this.newRecord(subject, capability, false, reason);
    await this.audit.append(record);
    return new AclDecision(false, reason);
  }

  private newRecord(subject: AclSubject, capability: AclCapability, allowed: boolean,
    reason: AclDenyReason): AclAuditRecord {
    const record: AclAuditRecord = new AclAuditRecord();
    this.seq += 1;
    record.id = 'acl-' + Date.now().toString() + '-' + this.seq.toString();
    record.at = Date.now();
    record.subject = String(subject);
    record.capability = String(capability);
    // 审计只记网段，不记逐台目标地址（设计文档 7.2 数据最小化）。
    record.scope = this.scope.subnetText.length > 0 ? this.scope.subnetText : scopeTextOf(reason);
    record.resultCount = allowed ? 1 : 0;
    record.success = allowed;
    record.denyReason = allowed ? AclDenyReason.NONE : String(reason);
    record.tableVersion = ACL_TABLE_VERSION;
    return record;
  }
}

/** 范围不可用时审计里的占位文本（不猜网段）。 */
function scopeTextOf(reason: AclDenyReason): string {
  if (reason === AclDenyReason.SCOPE_UNKNOWN) return 'unknown';
  return '';
}
