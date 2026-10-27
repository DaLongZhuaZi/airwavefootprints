/**
 * 目标范围硬约束（《主动扫描授权与隐私体系设计》v2 第 5 节）。纯逻辑 + 可单测。
 *
 * 文档原文要求：**代码级，不是文案**。所以这里的每条约束都必须能被单测断言，
 * 而不是写在弹窗里让用户自己保证。
 *
 * 允许的目标集合 = 当前已连 WiFi 网段内的主机，扣除：
 *   · 本机地址、网关地址（探测路由器无分类收益且更敏感）
 *   · 公网地址（含除 RFC1918 之外的任何地址段）
 *   · 历史 SSID 网络（无法保证还在同一网络）
 *   · 蜂窝网络（无 WiFi 网段可推）
 */

import { LocalNetworkInfo } from '../platform/FieldwatchAclTransport';

/**
 * 网段推导的降级策略（设计文档第 5 节「二选一，实施时定死」）。
 *
 * **本实现选定 (b) 拒绝执行**：拿不到前缀长就不扫。
 *
 * 为什么不用 (a)「本机 IP + /24 假设」：
 * 假设一旦错，我们会去扫**别人的网段**——这在酒店/租房场景是法律风险，
 * 不是体验问题。宁可不扫并如实告知，也不静默按猜测网段发包。
 * 代价是极少数设备上主动层不可用，这是可接受的降级。
 */
export enum SubnetSource {
  /** 由 linkAddresses 的前缀长推导（唯一可信来源）。 */
  LINK_ADDRESSES = 'link_addresses',
  /** 推导失败：不允许扫。 */
  UNKNOWN = 'unknown'
}

/** 目标范围。 */
export class AclScope {
  /** 是否允许真的发包。false 时调用方必须直接返回，不得探测。 */
  public usable: boolean = false;
  /** 来源（用于 UI 如实说明与审计）。 */
  public source: SubnetSource = SubnetSource.UNKNOWN;
  /** 本机 IP。 */
  public localIp: string = '';
  /** 前缀长；0 表示未知。 */
  public prefixLength: number = 0;
  /** 网关 IP（排除项，不探测）。 */
  public gateway: string = '';
  /** 网段字符串（如 `192.168.5.0/24`），仅用于展示与审计。 */
  public subnetText: string = '';
  constructor() {}
}

/** IPv4 点分十进制 → 32 位无符号整数；非法返回 0。 */
export function ipv4ToInt(ip: string): number {
  const parts: string[] = ip.trim().split('.');
  if (parts.length !== 4) return 0;
  let value: number = 0;
  for (let i: number = 0; i < 4; i += 1) {
    const part: number = Number(parts[i]);
    if (!Number.isInteger(part) || part < 0 || part > 255) return 0;
    value = ((value << 8) | part) >>> 0;
  }
  return value;
}

/** 32 位整数 → 点分十进制。 */
export function intToIpv4(value: number): string {
  return ((value >>> 24) & 0xFF).toString() + '.' + ((value >>> 16) & 0xFF).toString() + '.'
    + ((value >>> 8) & 0xFF).toString() + '.' + (value & 0xFF).toString();
}

/**
 * 是否**私网**地址（RFC1918 + 链路本地）。
 *
 * 公网目标被设计文档列为排除项（第 3 节末、第 5 节）。这里用白名单方式判定：
 * 只认 10/8、172.16/12、192.168/16、169.254/16；其余一律视为公网并拒绝。
 */
export function isPrivateIpv4(ip: string): boolean {
  const value: number = ipv4ToInt(ip);
  if (value === 0) return false;
  const a: number = (value >>> 24) & 0xFF;
  const b: number = (value >>> 16) & 0xFF;
  if (a === 10) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 169 && b === 254) return true;
  // 环回与 0.0.0.0 不算可用目标。
  return false;
}

/**
 * 由本机网络信息构建目标范围。
 *
 * **推导失败即不可用**（降级方案 b）：`fromLinkAddresses` 为 false 时说明前缀长是猜的，
 * 直接返回 `usable=false`，调用方必须放弃扫描并如实告知用户。
 */
export function scopeFromLocal(info: LocalNetworkInfo): AclScope {
  const scope: AclScope = new AclScope();
  scope.localIp = info.ip;
  scope.gateway = info.gateway;
  scope.prefixLength = info.prefixLength;
  if (!info.fromLinkAddresses) {
    // 降级：拒绝执行。不静默按 /24 猜网段（见文件头说明）。
    scope.usable = false;
    scope.source = SubnetSource.UNKNOWN;
    return scope;
  }
  if (info.ip.length === 0 || info.prefixLength <= 0 || info.prefixLength > 32) {
    scope.usable = false;
    scope.source = SubnetSource.UNKNOWN;
    return scope;
  }
  if (!isPrivateIpv4(info.ip)) {
    // 本机都不是私网地址，说明没连 WiFi 或连的是蜂窝/异常网络。
    scope.usable = false;
    scope.source = SubnetSource.UNKNOWN;
    return scope;
  }
  scope.usable = true;
  scope.source = SubnetSource.LINK_ADDRESSES;
  const mask: number = info.prefixLength === 0 ? 0 : (0xFFFFFFFF << (32 - info.prefixLength)) >>> 0;
  scope.subnetText = intToIpv4((ipv4ToInt(info.ip) & mask) >>> 0) + '/' + info.prefixLength.toString();
  return scope;
}

/**
 * 某个目标是否在允许范围内。
 *
 * 检查顺序即设计文档 2.3 的「目标范围」一步：越界直接拒绝。
 * 拒绝的理由用枚举返回，便于审计记录与单测断言（不靠字符串比对）。
 */
export enum TargetVerdict {
  /** 允许。 */
  ALLOWED = 'allowed',
  /** 范围不可用（推导失败）。 */
  SCOPE_UNKNOWN = 'scope_unknown',
  /** 公网地址。 */
  PUBLIC_ADDRESS = 'public_address',
  /** 本机地址。 */
  LOCAL_ADDRESS = 'local_address',
  /** 网关地址。 */
  GATEWAY = 'gateway',
  /** 不在当前网段内。 */
  OUT_OF_SUBNET = 'out_of_subnet',
  /** 地址非法。 */
  INVALID = 'invalid'
}

/** 判定一个目标是否可以探测。 */
export function targetVerdict(scope: AclScope, target: string): TargetVerdict {
  if (!scope.usable) return TargetVerdict.SCOPE_UNKNOWN;
  const value: number = ipv4ToInt(target);
  if (value === 0) return TargetVerdict.INVALID;
  // 排除公网：**必须是私网**才可能放行。
  if (!isPrivateIpv4(target)) return TargetVerdict.PUBLIC_ADDRESS;
  if (target === scope.localIp) return TargetVerdict.LOCAL_ADDRESS;
  if (scope.gateway.length > 0 && target === scope.gateway) return TargetVerdict.GATEWAY;
  const mask: number = scope.prefixLength === 0 ? 0 : (0xFFFFFFFF << (32 - scope.prefixLength)) >>> 0;
  const localNet: number = (ipv4ToInt(scope.localIp) & mask) >>> 0;
  const targetNet: number = (value & mask) >>> 0;
  if (localNet !== targetNet) return TargetVerdict.OUT_OF_SUBNET;
  return TargetVerdict.ALLOWED;
}

/**
 * 生成候选目标列表（已过滤排除项）。
 *
 * @param limit 上限：网段可能是 /16，一次生成 6 万条会把内存吃满；
 *              设计文档要求总时长 60s，实际能探的数量远小于网段主机数。
 */
export function candidateTargets(scope: AclScope, limit: number): string[] {
  const out: string[] = [];
  if (!scope.usable) return out;
  const mask: number = scope.prefixLength === 0 ? 0 : (0xFFFFFFFF << (32 - scope.prefixLength)) >>> 0;
  const local: number = ipv4ToInt(scope.localIp);
  const network: number = (local & mask) >>> 0;
  const size: number = Math.pow(2, 32 - scope.prefixLength);
  const start: number = network + 1;
  const end: number = network + size - 1;
  for (let cursor: number = start; cursor < end && out.length < limit; cursor += 1) {
    const candidate: string = intToIpv4(cursor >>> 0);
    if (targetVerdict(scope, candidate) !== TargetVerdict.ALLOWED) continue;
    out.push(candidate);
  }
  return out;
}
