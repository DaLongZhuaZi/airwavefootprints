/**
 * App 内 ACL：能力表与任务绑定（《主动扫描授权与隐私体系设计》v2 第 2–4 节）。
 *
 * **这不是鸿蒙系统的 ACL 流程**，本 App 也不申请系统 ACL。
 * 它借用 ACL 的思想——主体、客体、权限三元组，默认拒绝、显式授权、逐项可审计——
 * 在 App 内部给一切**主动**扫描行为设关卡。
 *
 * 为什么必须有这道关卡（设计文档 1.3）：主动发包走 `@ohos.net.socket`，所需
 * `ohos.permission.INTERNET` 是系统授予、安装即给、不弹窗；系统层面不区分「向固定服务器
 * 拉数据」与「向内网任意主机发探测包」，同一个权限两种行为全放行。所以关卡只能设在 App 内。
 *
 * 本模块只描述「规则」，不碰网络、不碰存储，因此可以完整单测。
 */

/**
 * 主动能力 id（设计文档第 3 节能力全表）。
 *
 * 只有这里登记的能力才可能被放行；**未登记的能力一律拒绝**（默认拒绝，见 2.4）。
 * 新增发送行为必须先在此登记、再实现，顺序不得颠倒。
 */
export enum AclCapability {
  /** A1 网段存活探测（ARP 无 API，用 TCP connect / UDP 探测替代）。 */
  SUBNET_SWEEP = 'A1',
  /** A2 端口探针（白名单端口，只记 open / closed）。 */
  PORT_PROBE = 'A2',
  /** A3 RTSP 探测（OPTIONS / DESCRIBE，只取 Server 标识类别与 SDP 编码类型）。 */
  RTSP_PROBE = 'A3',
  /** A4 ONVIF 探测（WS-Discovery Probe + GetServices / GetCapabilities）。 */
  ONVIF_PROBE = 'A4',
  /** A5 HTTP 横幅（只取 Server 头类别）。 */
  HTTP_BANNER = 'A5',
  /** A6 服务发现查询（mDNS / SSDP 的 M-SEARCH）。 */
  SERVICE_DISCOVERY = 'A6',
  /** A7 厂商二进制魔数（私有协议握手字节比对）。 */
  VENDOR_MAGIC = 'A7'
}

/**
 * 任务主体（设计文档第 4 节）。
 *
 * 主体是**任务**，不是用户也不是设备。未来新增任务默认没有任何主动权限，
 * 必须显式在 `taskAllows` 里新增条目，不得继承其他任务的授权。
 */
export enum AclSubject {
  /** 安防扫描：A1–A7 全部。 */
  SECURITY_SCAN = 'security_scan',
  /** WiFi 体检：仅 A1。 */
  WIFI_DOCTOR = 'wifi_doctor',
  /** 找东西：无（保持纯被动）。 */
  FIND = 'find'
}

/** 风险等级（设计文档 2.2）：高风险能力的弹窗文案须额外标明「将与目标设备建立协议交互」。 */
export enum AclRisk {
  LOW = 'low',
  HIGH = 'high'
}

/** 一条 ACL 记录（设计文档 2.2 的字段在代码里的落地形态）。 */
export class AclEntry {
  public capability: AclCapability = AclCapability.SUBNET_SWEEP;
  public risk: AclRisk = AclRisk.LOW;
  /** 告知文案键（弹窗四要素：能力 / 范围 / 暴露面 / 数据去向）。 */
  public titleKey: string = '';
  /** 高风险能力的额外说明键（「将与目标设备建立协议交互」）。 */
  public riskNoteKey: string = '';
  constructor(capability: AclCapability = AclCapability.SUBNET_SWEEP, risk: AclRisk = AclRisk.LOW,
    titleKey: string = '', riskNoteKey: string = '') {
    this.capability = capability;
    this.risk = risk;
    this.titleKey = titleKey;
    this.riskNoteKey = riskNoteKey;
  }
}

/**
 * ACL 表版本。
 *
 * 设计文档 2.4 要求「表结构变更须同步更新表版本」，审计记录要记这个值，
 * 事后可追溯「当时按哪一版规则放行」。改动能力表/任务绑定时必须 +1。
 */
export const ACL_TABLE_VERSION: number = 1;

/**
 * 能力全表。
 *
 * 顺序与设计文档第 3 节一致；`risk` 决定弹窗是否需要额外的协议交互提示。
 */
export function aclEntries(): AclEntry[] {
  const out: AclEntry[] = [];
  out.push(new AclEntry(AclCapability.SUBNET_SWEEP, AclRisk.LOW,
    'app.string.fieldwatch_acl_cap_a1', ''));
  out.push(new AclEntry(AclCapability.PORT_PROBE, AclRisk.LOW,
    'app.string.fieldwatch_acl_cap_a2', ''));
  out.push(new AclEntry(AclCapability.RTSP_PROBE, AclRisk.HIGH,
    'app.string.fieldwatch_acl_cap_a3', 'app.string.fieldwatch_acl_risk_protocol'));
  out.push(new AclEntry(AclCapability.ONVIF_PROBE, AclRisk.HIGH,
    'app.string.fieldwatch_acl_cap_a4', 'app.string.fieldwatch_acl_risk_protocol'));
  out.push(new AclEntry(AclCapability.HTTP_BANNER, AclRisk.HIGH,
    'app.string.fieldwatch_acl_cap_a5', 'app.string.fieldwatch_acl_risk_protocol'));
  out.push(new AclEntry(AclCapability.SERVICE_DISCOVERY, AclRisk.LOW,
    'app.string.fieldwatch_acl_cap_a6', ''));
  out.push(new AclEntry(AclCapability.VENDOR_MAGIC, AclRisk.HIGH,
    'app.string.fieldwatch_acl_cap_a7', 'app.string.fieldwatch_acl_risk_protocol'));
  return out;
}

/** 按能力取 ACL 记录；未登记返回 undefined（调用方据此拒绝）。 */
export function aclEntryOf(capability: AclCapability): AclEntry | undefined {
  const all: AclEntry[] = aclEntries();
  for (let i: number = 0; i < all.length; i += 1) {
    if (all[i].capability === capability) return all[i];
  }
  return undefined;
}

/**
 * 任务绑定（设计文档第 4 节）。
 *
 * 这是「最小化」的核心：某个任务能用哪些能力，写死在这里，不靠调用方自觉。
 * 安防扫描拿全部；WiFi 体检只拿 A1（它只需要知道网里有几台机器，不需要协议分类）；
 * 找东西一条都没有（它是认领已发现的蓝牙/WiFi 设备，保持纯被动）。
 */
export function taskAllows(subject: AclSubject, capability: AclCapability): boolean {
  if (subject === AclSubject.SECURITY_SCAN) return true;
  if (subject === AclSubject.WIFI_DOCTOR) return capability === AclCapability.SUBNET_SWEEP;
  // FIND 及任何未登记任务：无主动权限。
  return false;
}

/**
 * 排除项（设计文档第 3 节末）：**任何任务不得申请**。
 *
 * 它们不是「ACL 表里没登记所以拒绝」，而是**永远不该存在**的能力。
 * 单独列出来是为了让代码里有一条可被单测断言的清单——
 * 将来若有人想加「试默认口令」，会先撞到这份清单。
 */
export const ACL_FORBIDDEN_ACTIONS: string[] = [
  '弱口令尝试', '默认口令尝试', 'RTSP 拉流', 'ONVIF GetStreamUri 拉流',
  'GATT 连接读名', '漏洞利用', '配置修改', '登录尝试',
  '公网目标', '历史网络', '后台常驻扫描', '目标拒连后重试爆破'
];

/**
 * 端口白名单（A2）。
 *
 * 只允许探这些端口；表外端口一律拒绝。构成设计文档第 3 节 A2 行「允许的操作」。
 * 取舍：覆盖常见摄像头/媒体/发现端口，但不含任何可被用来「登录」或「拉流」的端口语义——
 * 这里只做 connect 与 close，不做应用层交互。
 */
export const ACL_PORT_WHITELIST: number[] = [
  80, 443, 554, 8000, 8080, 8443, 8899, 1935, 3702, 37777, 34567, 9000, 1900, 5353
];

/** 端口是否在白名单内。 */
export function portAllowed(port: number): boolean {
  return ACL_PORT_WHITELIST.indexOf(port) >= 0;
}

/**
 * 速率 / 超时 / 并发上限（设计文档第 5 节 + 2.2「速率/并发/超时」字段）。
 *
 * 起点按文档建议：并发 16、单目标 800ms、总时长 60s。
 * 这些值同时是「不对目标造成拒绝服务」的法律边界保障（见 7.5），调大需谨慎。
 */
export class AclLimits {
  public maxConcurrency: number = 16;
  public perTargetTimeoutMs: number = 800;
  public totalDurationMs: number = 60000;
  /** 重试策略：**恒为 0**（设计文档明确「目标拒连/超时不重试」）。 */
  public retries: number = 0;
  constructor() {}
}

export function aclLimits(): AclLimits { return new AclLimits(); }
