export enum RadioKind { WIFI = 'wifi', BLE = 'ble', NEARLINK = 'nearlink' }
/**
 * 签名类别，对齐 Android Fieldwatch 的 21 类。
 * BODYWORN 与 ROUTER 是历史值：保留以兼容旧配置与旧签名包，展示时折叠到 WEARABLE / ISP。
 */
export enum SignatureClass {
  FINDER = 'finder',
  BEACON = 'beacon',
  SIGNAGE = 'signage',
  WEARABLE = 'wearable',
  SURVEILLANCE = 'surveillance',
  DRONE = 'drone',
  HACKING = 'hacking',
  BODYWORN = 'bodyworn',
  LAW_ENFORCEMENT = 'law_enforcement',
  VEHICLE = 'vehicle',
  GLASSES = 'glasses',
  AUDIO = 'audio',
  CAMERA = 'camera',
  THERMOSTAT = 'thermostat',
  LOCK = 'lock',
  HEALTH = 'health',
  HOME = 'home',
  ISP = 'isp',
  ROUTER = 'router',
  MESH = 'mesh',
  PHONE = 'phone',
  OTHER = 'other'
}

/** 折叠历史类别，保证 Filters / 分组只出现一个类别。 */
/**
 * 把「应用层的无线电错误」与「Wi-Fi 快照错误」合成一条给用户看的提示（§12.1）。
 *
 * 抽成纯函数是为了可测：这段逻辑内联在页面刷新里时，改错了不会有任何测试报警
 * （与 `FieldwatchWifiScanner.backoffDelayFor` 的抽取同理）。
 *
 * 两者都空时返回空串 —— 调用方据此决定是否渲染提示条。
 * Wi-Fi 的排在后面：它多半是系统临时节流，BLE 的错误更根本。
 */
export function mergeScanError(bleError: string, wifiError: string): string {
  const ble: string = bleError.trim();
  const wifi: string = wifiError.trim();
  if (ble.length > 0 && wifi.length > 0) return ble + ' · ' + wifi;
  return ble.length > 0 ? ble : wifi;
}

export function foldedSignatureClass(value: SignatureClass): SignatureClass {
  if (value === SignatureClass.BODYWORN) return SignatureClass.WEARABLE;
  if (value === SignatureClass.ROUTER) return SignatureClass.ISP;
  return value;
}

/** 可供 UI 展示的类别列表（不含折叠别名）。 */
export function visibleSignatureClasses(): SignatureClass[] {
  return [
    SignatureClass.FINDER, SignatureClass.BEACON, SignatureClass.SIGNAGE, SignatureClass.WEARABLE,
    SignatureClass.SURVEILLANCE, SignatureClass.DRONE, SignatureClass.HACKING, SignatureClass.LAW_ENFORCEMENT,
    SignatureClass.VEHICLE, SignatureClass.GLASSES, SignatureClass.AUDIO, SignatureClass.CAMERA,
    SignatureClass.THERMOSTAT, SignatureClass.LOCK, SignatureClass.HEALTH, SignatureClass.HOME,
    SignatureClass.ISP, SignatureClass.MESH, SignatureClass.PHONE, SignatureClass.OTHER
  ];
}
export enum FilterLogic { AND = 'and', OR = 'or' }
export enum ScanState { IDLE = 'idle', SCANNING = 'scanning', PAUSED = 'paused', ERROR = 'error' }
export enum WifiScanPhase { IDLE = 'idle', PRECHECK = 'precheck', WAITING_FOR_RETRY = 'waiting_for_retry', SCANNING = 'scanning', READY = 'ready', STALE = 'stale', LOCATION_DISABLED = 'location_disabled', WIFI_DISABLED = 'wifi_disabled', PERMISSION_DENIED = 'permission_denied', UNSUPPORTED = 'unsupported', SYSTEM_REJECTED = 'system_rejected', ERROR = 'error' }

/**
 * 某路无线电此刻是否**真的在工作**（供实时页显示「当前工作模式」）。
 *
 * 三路扫描器报告的 phase 取值不同：
 *   BLE / 星闪 -> `ScanState`（idle / scanning / paused / error）
 *   Wi-Fi     -> `WifiScanPhase`（12 个值：scanning / ready / waiting_for_retry / stale …）
 * 但「不可用」这一类是共通的，统一排除即可；其余都算在工作 ——
 * Wi-Fi 的 ready / stale / waiting_for_retry 都表示扫描器活着，只是当前没在扫。
 *
 * **抽成模块级纯函数是为了可测**：此前这段判断内联在页面结构体里，单测够不着。
 */
export function isRadioPhaseActive(phase: string): boolean {
  if (phase === ScanState.IDLE) return false;
  if (phase === 'unsupported' || phase === 'permission_denied') return false;
  if (phase === 'wifi_disabled' || phase === 'location_disabled') return false;
  return true;
}

/**
 * 按无线电种类统计信号源数量，返回 `[BLE, Wi-Fi, 星闪]`。
 *
 * **抽出来是因为这里踩过坑**：原实现写成 `if (BLE) ble++; else wifi++;`，
 * 二分法只有两支，**星闪落进 `else` 被算成了 Wi-Fi** ——
 * 于是头部显示的 Wi-Fi 数量实际是「Wi-Fi + 星闪」，而星闪自己一个数都没有。
 */
export function countSightingsByKind(sightings: Sighting[]): number[] {
  let ble: number = 0;
  let wifi: number = 0;
  let nearLink: number = 0;
  sightings.forEach((item: Sighting): void => {
    if (item.kind === RadioKind.BLE) ble += 1;
    else if (item.kind === RadioKind.NEARLINK) nearLink += 1;
    else wifi += 1;
  });
  return [ble, wifi, nearLink];
}

export class RadioSourceSnapshot {
  public kind: RadioKind; public phase: string; public lastSuccessAt: number; public nextAttemptAt: number; public fresh: boolean; public errorCode: number; public errorMessage: string; public resultCount: number;
  constructor(kind: RadioKind, phase: string = ScanState.IDLE, lastSuccessAt: number = 0, nextAttemptAt: number = 0, fresh: boolean = false, errorCode: number = 0, errorMessage: string = '', resultCount: number = 0) {
    this.kind = kind; this.phase = phase; this.lastSuccessAt = lastSuccessAt; this.nextAttemptAt = nextAttemptAt; this.fresh = fresh; this.errorCode = errorCode; this.errorMessage = errorMessage; this.resultCount = resultCount;
  }
}

export class GpsSample {
  public latitude: number;
  public longitude: number;
  public at: number;
  constructor(latitude: number, longitude: number, at: number) { this.latitude = latitude; this.longitude = longitude; this.at = at; }
}

/** BLE Service Data（AD 类型 0x16）：UUID 与随载荷。 */
export class ServiceDataRecord {
  public uuid: string;
  public dataHex: string;
  constructor(uuid: string = '', dataHex: string = '') { this.uuid = uuid; this.dataHex = dataHex; }
}

/** 签名解码字段的结果；Live 行、详情、Debrief 和 Compare 共用同一结果。 */
export class DecodedFieldValue {
  public fieldId: string;
  public label: string;
  public text: string;
  /** 命名值的原始键，用于匹配 liveEmphasis 与 enumNotes。 */
  public rawKey: string;
  public unit: string;
  public live: boolean;
  public emphasized: boolean;
  public note: string;
  constructor(fieldId: string, label: string, text: string, rawKey: string = '', unit: string = '', live: boolean = false, emphasized: boolean = false, note: string = '') {
    this.fieldId = fieldId; this.label = label; this.text = text; this.rawKey = rawKey; this.unit = unit; this.live = live; this.emphasized = emphasized; this.note = note;
  }
}

export class RadioFacts {
  public ssid: string;
  public manufacturer: string;
  public frequencyMhz: number;
  public serviceUuids: string[];
  /**
   * 制造商数据，**不含**前两字节 Company ID，与 BLE 规范及 Android 基线一致。
   * Company ID 单独保存在 manufacturerId。
   */
  public manufacturerDataHex: string;
  public band: number;
  public channelWidth: number;
  public securityType: number;
  public hiddenSsid: boolean;
  /** BLE 制造商 Company ID（小端 u16）；0 表示未知。 */
  public manufacturerId: number;
  /** BLE Service Data 记录。 */
  public serviceData: ServiceDataRecord[];
  /** Wi-Fi 厂商 IE（element 221）的 3 字节 OUI 列表。 */
  public vendorIeOuis: string[];
  /**
   * 星闪广播携带的设备类型（nearlink.DeviceClass 枚举值）。
   *
   * -1 表示未携带 / 无效。有了它就不必依赖特征库命中即可显示正确的设备类型图标，
   * 这是星闪相对 BLE 的一项独有能力。
   */
  public nearLinkDeviceClass: number;
  /**
   * 星闪广播是否声明可连接。
   *
   * 我们**不会去连接**，但这是设备自己广播出来的事实，对判断设备性质有用
   * （例如可连接的多为配件，不可连接的多为信标）。BLE 侧没有等价字段。
   */
  public nearLinkConnectable: boolean;
  // ── 以下字段来自 **原始广播包**（ble.ScanResult.data）或 ScanResult 的直给字段 ──
  //
  // 这些此前完全没被采集：扫描器只用了鸿蒙**预解析好的 map**
  // （manufacturerDataMap / serviceDataMap / serviceUuids），
  // 而原始 `data` 只在 map 全空时才当兜底解析一次。
  // 结果就是 AD 结构里大量标准字段（Appearance、Tx Power、Flags…）被整包丢掉。

  /**
   * 广播地址类型：'public' / 'random' / ''（未知）。
   *
   * 来自 `ScanResult.address.addressType`（API 23+）。
   * **决定能不能给设备起自定义名** —— 随机地址会轮换，
   * 名字会绑死在一个再也听不到的键上。
   */
  public addressType: string;
  /** 广播自己声明的外观（GAP Appearance，AD type 0x19 的低 16 位）；-1 表示未携带。 */
  public appearance: number;
  /** 广播声明的发射功率 dBm（AD type 0x0A）；-128 表示未携带。 */
  public txPower: number;
  /** 广播 Flags 原始字节（AD type 0x01）；-1 表示未携带。 */
  public advertiseFlags: number;
  /** AD type 0x02/0x03 的 16 位服务 UUID（补足 0000xxxx-0000-1000-8000-00805F9B34FB 形式）。 */
  public serviceUuids16: string[];
  /** AD type 0x06/0x07 的 128 位服务 UUID。 */
  public serviceUuids128: string[];
  /** 原始广播包十六进制（不含分隔符）；空串表示平台没给。 */
  public rawAdHex: string;
  /** 本设备是否由系统标记为可连接（ScanResult.connectable）。 */
  public connectable: boolean;
  // ── 详情页需要、此前完全没采集的字段（对齐原版 RadioFacts）──

  /**
   * BLE 物理层。`ScanResult.primaryPhy` / `secondaryPhy`，取值为 `ble.BlePhy` 枚举。
   * -1 表示平台未给。**这是扫描器直给字段，不在广播包里**，
   * 所以只能从 ScanResult 拿，解析 AD 结构拿不到。
   */
  public primaryPhy: number;
  public secondaryPhy: number;
  /** 广播间隔（毫秒，`ScanResult.interval`）；-1 表示未给。越小越吵。 */
  public advertisingIntervalMs: number;
  /**
   * 经典蓝牙 Class of Device（AD type 0x0D 的三字节，小端）。
   * -1 表示未携带。双模芯片会在 BLE 广播里捎带它。
   */
  public deviceClass: number;
  /**
   * 全部厂商数据记录。
   *
   * 此前只留了**一条**（`manufacturerId` + `manufacturerDataHex`），
   * 而广播里可以有多条（不同 Company ID）；原版按记录逐条展示。
   */
  public mfgRecords: ServiceDataRecord[];
  /** Wi-Fi 厂商 IE：OUI + element type + 数据。原版带 type 一起展示。 */
  public vendorIeRecords: ServiceDataRecord[];
  /** Wi-Fi 支持的速率串（原版 `supportedRates`）。 */
  public supportedRates: string;
  /** Wi-Fi capability 串。 */
  public capabilities: string;
  /** Wi-Fi 代际（如 `Wi-Fi 5`）；空串表示未知。 */
  public wifiStandard: string;
  /** Wi-Fi 中心频率（MHz）；0 表示未给。 */
  public centerFreq0: number;
  public centerFreq1: number;
  constructor(ssid: string = '', manufacturer: string = '', frequencyMhz: number = 0, serviceUuids: string[] = [], manufacturerDataHex: string = '', band: number = 0, channelWidth: number = 0, securityType: number = 0, hiddenSsid: boolean = false, manufacturerId: number = 0, serviceData: ServiceDataRecord[] = [], vendorIeOuis: string[] = []) {
    this.ssid = ssid; this.manufacturer = manufacturer; this.frequencyMhz = frequencyMhz; this.serviceUuids = serviceUuids; this.manufacturerDataHex = manufacturerDataHex; this.band = band; this.channelWidth = channelWidth; this.securityType = securityType; this.hiddenSsid = hiddenSsid;
    this.manufacturerId = manufacturerId; this.serviceData = serviceData; this.vendorIeOuis = vendorIeOuis;
    this.nearLinkDeviceClass = -1;
    this.nearLinkConnectable = false;
    this.addressType = '';
    this.appearance = -1;
    this.txPower = -128;
    this.advertiseFlags = -1;
    this.serviceUuids16 = [];
    this.serviceUuids128 = [];
    this.rawAdHex = '';
    this.connectable = false;
    this.primaryPhy = -1;
    this.secondaryPhy = -1;
    this.advertisingIntervalMs = -1;
    this.deviceClass = -1;
    this.mfgRecords = [];
    this.vendorIeRecords = [];
    this.supportedRates = '';
    this.capabilities = '';
    this.wifiStandard = '';
    this.centerFreq0 = 0;
    this.centerFreq1 = 0;
  }
}

export class ScanObservation {
  public key: string; public kind: RadioKind; public address: string; public name: string; public rssi: number; public seenAt: number; public facts: RadioFacts; public location: GpsSample | undefined; public fresh: boolean;
  constructor(key: string, kind: RadioKind, address: string, name: string, rssi: number, seenAt: number, facts: RadioFacts = new RadioFacts(), location: GpsSample | undefined = undefined, fresh: boolean = true) {
    this.key = key; this.kind = kind; this.address = address; this.name = name; this.rssi = rssi; this.seenAt = seenAt; this.facts = facts; this.location = location; this.fresh = fresh;
  }
}

/**
 * 一段「在场」区间：从出现到消失。
 *
 * `end` 为 undefined 表示**此刻仍在场**。原版用它画详情页的「在场情况（15 分钟）」条，
 * 也用来判断设备是不是走开了（`gone`）。
 */
export class PresenceSpan {
  public start: number;
  public end: number | undefined;
  constructor(start: number, end: number | undefined = undefined) { this.start = start; this.end = end; }
}

export class Sighting {
  /** 平滑系数：每次向新采样靠近四分之一。见 `rssiDisplay` 的说明。 */
  private static readonly RSSI_SMOOTH_ALPHA: number = 0.25;
  public key: string;
  public kind: RadioKind;
  public address: string;
  public name: string;
  public rssi: number;
  public facts: RadioFacts;
  public location: GpsSample | undefined;
  public firstSeen: number; public lastSeen: number; public count: number = 1; public signatureIds: string[] = [];
  /** 命中签名解码出的字段；与 signatureIds 同步更新。 */
  public decodedFields: DecodedFieldValue[] = [];
  public rssiSamples: number[] = [];
  /**
   * **用于显示**的强度：对原始采样做指数加权平滑（EWMA）。
   *
   * `rssi` 是最近一次原始采样，逐次波动可达十几 dBm。
   * 雷达的**位置、半径、分圈、显现排名、聚合成箱**全部由它派生 ——
   * 拿原始值去算，每来一帧信号这些量就一起动，表现就是节点跳变/闪烁。
   *
   * 为什么不直接用 32 条滑动窗口的平均：
   *   - 窗口在启动初期只有 1~2 条，均值等于原始值，照样跳；
   *   - 等窗口填满又要等 32 帧才稳定，反应太钝。
   * EWMA 从第一帧起就是平滑的，且 O(1)、无状态窗口，也更好测。
   *
   * **不要用它替换 `rssi`** —— 详情页要显示真实读数，
   * 平滑值只服务于「画在哪里、画多大、排第几」。
   */
  public rssiDisplay: number = 0;
  public fresh: boolean = true;
  /**
   * 本次会话听到的**强度范围**（原版 `Rssi.sessionRange`）。
   *
   * 初值等于首个样本；`ingest` 时取极值。原版详情页专门有一行
   * 「本次会话听到的强度范围: -83 to -82 dBm」，比单个当前值更能说明稳定性。
   */
  public rssiMin: number = 0;
  public rssiMax: number = 0;
  /**
   * 在场时段列表。
   *
   * 判定规则（与原版一致）：新观测到来时，若最后一段已经结束（`end` 有值）
   * 就开新的一段，否则延续当前段 —— 于是「走开又回来」会形成两段。
   */
  public presence: PresenceSpan[] = [];
  /**
   * 是否已经「走开」（超过 linger 窗口没再听到）。
   *
   * 原版 `DeviceStore` 用它驱动在场时段的开合：走开时关闭最后一段、
   * 回来时重开 —— **没有它，在场时间轴永远是一条从首次出现到现在的整条**，
   * 「断续出现」与「一直在线」就区分不出来。
   */
  public gone: boolean = false;
  constructor(key: string, kind: RadioKind, address: string, name: string, rssi: number, seenAt: number, facts: RadioFacts, location: GpsSample | undefined = undefined) {
    this.key = key; this.kind = kind; this.address = address; this.name = name; this.rssi = rssi; this.facts = facts; this.location = location; this.firstSeen = seenAt; this.lastSeen = seenAt; this.rssiSamples.push(rssi);
  }
  static fromObservation(observation: ScanObservation): Sighting {
    const sighting: Sighting = new Sighting(observation.key, observation.kind, observation.address, observation.name,
      observation.rssi, observation.seenAt, observation.facts, observation.location);
    sighting.fresh = observation.fresh;
    // 会话强度范围从首个样本起步；只在**已测量**的样本上更新。
    // 未测量的 RSSI 用 0 之类的哨兵值表示，混进来会把范围拉成「-100 ~ 0」。
    sighting.rssiMin = observation.rssi;
    sighting.rssiMax = observation.rssi;
    sighting.presence = [new PresenceSpan(observation.seenAt)];
    // 平滑值从首个样本起步，否则首个样本之后会从 0 慢慢爬上来，
    // 画面上表现为「新设备从圆心飞出去」。
    sighting.rssiDisplay = observation.rssi;
    return sighting;
  }

  /**
   * 合并一次新观测。
   *
   * 与原版 `DeviceStore` 对齐的三件事：
   *  ① **会话强度范围**取极值（详情页「本次会话听到的强度范围」）；
   *  ② **在场时段**：上一段已结束就开新段，否则延续 —— 「走开又回来」形成两段；
   *  ③ 样本窗口仍是 32 条滑动。
   */
  ingest(observation: ScanObservation): void {
    this.rssi = observation.rssi;
    this.lastSeen = observation.seenAt;
    this.count += 1;
    this.fresh = observation.fresh;
    if (observation.name.length > 0) this.name = observation.name;
    this.facts = observation.facts;
    if (observation.location !== undefined) this.location = observation.location;
    if (this.count <= 1) {
      this.rssiMin = observation.rssi;
      this.rssiMax = observation.rssi;
    } else {
      if (observation.rssi < this.rssiMin) this.rssiMin = observation.rssi;
      if (observation.rssi > this.rssiMax) this.rssiMax = observation.rssi;
    }
    const lastSpan: PresenceSpan | undefined = this.presence[this.presence.length - 1];
    if (lastSpan === undefined || lastSpan.end !== undefined) {
      this.presence.push(new PresenceSpan(observation.seenAt));
    }
    if (this.rssiSamples.length >= 32) this.rssiSamples.shift();
    this.rssiSamples.push(observation.rssi);
    // 平滑值：首帧直接落位，之后每次向新采样靠近四分之一。
    // 取 0.25 是权衡：太小则跟不上真实的接近/远离（用户会觉得迟钝），
    // 太大则压不住逐帧噪声（一个采样跳 10 dBm 会让节点挪动半圈）。
    if (this.count <= 1 || this.rssiDisplay === 0) this.rssiDisplay = observation.rssi;
    else this.rssiDisplay += (observation.rssi - this.rssiDisplay) * Sighting.RSSI_SMOOTH_ALPHA;
  }

  /**
   * 按「是否还在听到」刷新在场状态（对齐原版 `DeviceStore` 的 gone 扫描）。
   *
   * `lingerMs` 是容忍窗口：超过它没再听到才算走开。
   * 走开时把最后一段的 `end` 定在 `lastSeen`（不是 now）——
   * 最后听到的时刻才是真实的离场时刻，用 now 会把「走开后过了多久才被发现」也算成在场。
   */
  refreshPresence(now: number, lingerMs: number): void {
    const gone: boolean = now - this.lastSeen > lingerMs;
    const last: PresenceSpan | undefined = this.presence[this.presence.length - 1];
    if (last !== undefined) {
      if (gone && last.end === undefined) last.end = this.lastSeen;
      else if (!gone && last.end !== undefined) last.end = undefined;
    }
    this.gone = gone;
  }
}

export class WatchTarget {
  public deviceKey: string;
  public signatureId: string;
  public label: string;
  public alert: boolean;
  /** 观察者备注；只影响展示，不参与命中判定。 */
  public note: string;
  constructor(deviceKey: string = '', signatureId: string = '', label: string = '', alert: boolean = true, note: string = '') {
    this.deviceKey = deviceKey; this.signatureId = signatureId; this.label = label; this.alert = alert; this.note = note;
  }
  /** 设备级或签名级关注都算有效条目。 */
  valid(): boolean { return this.deviceKey.length > 0 || this.signatureId.length > 0; }
}
export class FilterDefinition {
  // ── 与原版 domain/FilterEngine.kt 的 FilterState 逐字段对齐 ──
  public logic: FilterLogic = FilterLogic.AND;
  /** 包含式双开关：两个都开表示 Wi-Fi 与 BLE 都看。 */
  public showWifi: boolean = true;
  public showBle: boolean = true;
  /** 星闪信号源开关；设备不支持星闪时该项无实际影响。 */
  public showNearLink: boolean = true;
  /** 只显示命中签名的设备（原版语义：fleetIds 非空）。 */
  public namedOnly: boolean = false;
  /** 只显示用户自定义命名过的信号源。 */
  public customNamesOnly: boolean = false;
  public watchedOnly: boolean = false;
  /** 命中任一 fleetIds 的设备不通过。 */
  public excludeSignatures: boolean = false;
  public fleetIds: string[] = [];
  /** 非空时要求命中其中之一。 */
  public includeSignatures: boolean = false;
  public includeFleetIds: string[] = [];
  /** 类别三态：不用 / 仅显示 classes / 隐藏 classes。 */
  public useClassFilter: boolean = false;
  public excludeClasses: boolean = false;
  public classes: SignatureClass[] = [];
  public rssiMin: number = -100;
  /** 模糊匹配 名称 或 MAC。 */
  public nameQuery: string = '';
  /** 模糊匹配 MAC 或 厂商。 */
  public ouiQuery: string = '';
  /** 隐藏只带 Fast Pair 账号密钥的广播。 */
  public hideFastPairAccountKey: boolean = false;
  /** 只显示与手机一起移动的设备（需要 GPS 轨迹）。 */
  public movingWithYou: boolean = false;
  // ── 本 App 额外保留的条件（原版无，但 Live/日志需要） ──
  public attentionOnly: boolean = false;
  public freshOnly: boolean = false;
  public cachedOnly: boolean = false;
  public decodedOnly: boolean = false;
  public locatedOnly: boolean = false;
  /** 兼容旧调用点。 */
  public radioKind: RadioKind | undefined = undefined;
  public signatureClass: SignatureClass | undefined = undefined;
  public signatureId: string = '';
  public minimumRssi: number | undefined = undefined;
}
/** 具名过滤预设；名称唯一，用于覆盖与删除。 */
export class FilterPreset {
  public name: string;
  public filter: FilterDefinition;
  constructor(name: string = '', filter: FilterDefinition = new FilterDefinition()) { this.name = name; this.filter = filter; }
}

/** 日志占用：行数与磁盘字节数。 */
export class FieldwatchLogFootprint {
  public rows: number;
  public bytes: number;
  constructor(rows: number = 0, bytes: number = 0) { this.rows = rows; this.bytes = bytes; }
  /** 以 KB 显示，向上取整。 */
  kilobytes(): number { return Math.ceil(this.bytes / 1024); }
}
export class AppSettings { public displayPaused: boolean = false; public darkMode: boolean = true; public keepScreenOn: boolean = false; public locationTagging: boolean = false; public privacyMode: boolean = false; public watchNotifications: boolean = false;
  // ── 关注列表的可听告警（§12.3 关注与声音设置）──
  //
  // 此前只有 `watchNotifications`（系统通知），**没有任何声音与语音**：
  // 清单要求「Watchlist beep 开关」「Watchlist voice 开关」「语音内容选择」
  // 「测试声音/语音」，而原版 `alert/Alerter.kt` 是完整实现的。
  // 我们自己的 Hunt 反馈类里还写着「双响提示与 Hunt tick 是两套独立告警，本类只负责 Hunt」——
  // 即设计被认领了，另一半从没做。
  /** 关注设备出现时是否双响提示。 */
  public watchBeep: boolean = true;
  /** 关注设备出现时是否语音播报。 */
  public watchVoice: boolean = false;
  /** 语音内容：class / signature / classSignature，对应原版 AlertVoiceWhat。 */
  public watchVoiceWhat: string = 'class';
  // ── Hunt 页的声音与触感（§12.3「Hunt 声音反馈开关」）──
  //
  // 此前这两个开关**根本不存在**：Hunt 页用的是页面局部 `@State tickEnabled = true`，
  // 于是 (1) 每次进页面都重置，用户关不掉；(2) 默认是**开**的，
  // 而原版 `huntBeep` / `huntVibrate` 默认都是 **false**（注释原文：*Off by default*）。
  // 原版还是**两个独立开关**（可只振动不出声），我们只有一个合并开关。
  /** Hunt 页 geiger tick 声音。默认关，与原版一致。 */
  public huntBeep: boolean = false;
  /** Hunt 页 geiger tick 触感。默认关，与原版一致。 */
  public huntVibrate: boolean = false;
  // ── 列表显示的四个开关（§12.2 显示设置）──
  //
  // 原版这四个都是真实设置字段，界面是 `OptionSwitch(tr("Frequency"), showFrequency, ...)`：
  //   showRssiBar → 显示 RSSI 条
  //   showFleetName → 显示签名名称
  //   showFrequency → 显示频率/信道
  //   showSeenTimes → 显示 First seen / Last seen
  // **我们此前一个都没有**：列表行里这三项全部无条件渲染。
  // 注意 `radarLabelFields` 只管**雷达标签**，不覆盖列表视图，两者不是一回事。
  // 默认值与原版一致，均为 true。
  /** 列表行里的 RSSI 条。 */
  public showRssiBar: boolean = true;
  /** 列表行里的签名名称。 */
  public showFleetName: boolean = true;
  /** 列表行里的频率/信道。 */
  public showFrequency: boolean = true;
  /** 列表行里的 First seen / Last seen。 */
  public showSeenTimes: boolean = true;
  /**
   * 列表是否使用紧凑行。
   *
   * 四个视图（强度/时间线/信号轨迹/分类）共用同一套行样式，
   * 尺寸只在 `FieldwatchSignalRow` 里定义；这里只决定取哪一档。
   * 之前的行样式各写各的（图标 34/34/28、名称 17/16/15），
   * 同一台设备切视图看起来像换了个东西。
   */
  public listCompactRows: boolean = false;
  /**
   * 日志等级，取 `LogLevel` 的数值（OFF=-1 / DEBUG=0 / INFO=1 / WARN=2 / ERROR=3 / FATAL=4）。
   *
   * **默认 WARN**：DEBUG/INFO 在扫描期间每秒都在打，
   * 真机上既拖性能又淹没真正要看的那几条。
   * 需要排查时再临时调低。
   *
   * 用 number 而不是直接引用 `LogLevel`：这一层不该依赖 ngf 框架的日志实现。
   */
  public logLevel: number = 2;
  /** 雷达标签要显示的字段，逗号分隔（name,address,type,rssi,freq）。 */
  public radarLabelFields: string = 'name,rssi';
  /** 雷达标签字号（vp）。 */
  public radarLabelFontSize: number = 12;
  /** 雷达设备图标尺寸（vp）。 */
  public radarIconSize: number = 26;
  public backgroundScanning: boolean = false; public scanIntensity: string = 'balanced'; public liveMode: string = 'radar'; }
export class LogEntry { public id: string; public observation: ScanObservation; public signatureIds: string[]; constructor(id: string, observation: ScanObservation, signatureIds: string[] = []) { this.id = id; this.observation = observation; this.signatureIds = signatureIds; } }
export class SitSummary { public id: string; public name: string; public startedAt: number; public endedAt: number; public radioCount: number; public deviceKeys: string[]; constructor(id: string, name: string, startedAt: number, endedAt: number = 0, radioCount: number = 0, deviceKeys: string[] = []) { this.id = id; this.name = name; this.startedAt = startedAt; this.endedAt = endedAt; this.radioCount = radioCount; this.deviceKeys = deviceKeys; } }
export class SitFile { public summary: SitSummary; public radios: Sighting[]; public path: GpsSample[]; constructor(summary: SitSummary, radios: Sighting[] = [], path: GpsSample[] = []) { this.summary = summary; this.radios = radios; this.path = path; } }
