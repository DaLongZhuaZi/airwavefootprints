/**
 * 自有设备身份档案（找东西 P0-2）。
 *
 * 为什么不把这些字段直接挂到 `WatchTarget` 上：
 * `WatchTarget` 是「关注列表」的一行，语义是「这个设备键/这个签名要不要提醒」，
 * 随关注列表增删；自有设备是一份**跨配对、跨扫描、跨重启都要认得出**的身份，
 * 生命周期更长、字段更多（持久锚、配对地址、指纹快照、纠错黑名单）。
 * 混在一起会让关注列表的导出/备份格式被动变脏，所以新建模型，
 * `WatchTarget` 只留一个 profileId 引用。
 *
 * 本模块是纯领域逻辑：不 import 任何系统 Kit 包，不产生用户可见文案
 * （「未命名设备」一类默认名由 UI 通过资源键解析，不要塞进 label()）。
 */

export enum OwnDeviceKind {
  HEADPHONES = 'headphones',
  WATCH = 'watch',
  SPEAKER = 'speaker',
  CAR = 'car',
  TRACKER = 'tracker',
  OTHER = 'other'
}

/** 十六进制字符表。用它判断「这一段像不像 MAC」，比每次现编译正则便宜。 */
const HEX_CHARS: string = '0123456789ABCDEF';

/**
 * 主类别取值来源：Bluetooth SIG Assigned Numbers「Baseband」表的 Major Device Class，
 * 即 Class of Device 第 8–12 位。鸿蒙没有公开这套枚举
 * （`connection.getRemoteDeviceClass` 只给一个 number），所以这里以字面常量复刻。
 *
 * 表里还有 Phone(0x02) / LAN(0x03) / Peripheral(0x05) / Imaging(0x06) /
 * Toy(0x08) / Health(0x09) / Uncategorized(0x1F)，它们都不对应找东西的六种目标，
 * 一律落到 OTHER，因此不单独立常量。
 */
const COD_MAJOR_COMPUTER: number = 0x01;
const COD_MAJOR_AUDIO_VIDEO: number = 0x04;
const COD_MAJOR_WEARABLE: number = 0x07;

/**
 * 次类别取值来源：同一张表的 Minor Device Class，即 CoD 第 2–7 位（6 位）。
 * 0x01 可穿戴耳机、0x02 免提、0x04 扬声器、0x05 头戴耳机、
 * 0x06 便携音频、0x07 车载音响、0x09 HiFi 音频，均出自「音频/视频」大类。
 */
const COD_MINOR_WEARABLE_HEADSET: number = 0x01;
const COD_MINOR_HANDS_FREE: number = 0x02;
const COD_MINOR_LOUDSPEAKER: number = 0x04;
const COD_MINOR_HEADPHONES: number = 0x05;
const COD_MINOR_PORTABLE_AUDIO: number = 0x06;
const COD_MINOR_CAR_AUDIO: number = 0x07;
const COD_MINOR_HIFI_AUDIO: number = 0x09;
const COD_MINOR_WRISTWATCH: number = 0x01;
const COD_MINOR_COMPUTER_WEARABLE: number = 0x06;

function isHexText(text: string): boolean {
  if (text.length === 0) return false;
  for (let index = 0; index < text.length; index += 1) {
    if (HEX_CHARS.indexOf(text.charAt(index)) < 0) return false;
  }
  return true;
}

/** UUID 统一大写去重：同一个 UUID 会同时出现在 serviceUuids 与 serviceData 里。 */
function normalizeUuidList(values: string[]): string[] {
  const out: string[] = [];
  values.forEach((item: string): void => {
    const text: string = item.trim().toUpperCase();
    if (text.length > 0 && out.indexOf(text) < 0) out.push(text);
  });
  return out;
}

/** 签名 id 去空去重；大小写由比对方统一，快照这边只管别留空串。 */
function normalizeIdList(values: string[]): string[] {
  const out: string[] = [];
  values.forEach((item: string): void => {
    const text: string = item.trim();
    if (text.length > 0 && out.indexOf(text) < 0) out.push(text);
  });
  return out;
}

/**
 * 地址归一化：去空白、统一大写、分隔符统一成 ':'。
 *
 * 三个来源写法互不相同：系统配对名单给 'AA:BB:CC:DD:EE:FF'，
 * 部分扫描回调给连字符或小写，车载/星闪侧偶尔带空格。
 * 只要有一处漏了归一化，「地址直配」这条最强证据就会静默失效，
 * 退化成指纹猜测 —— 所以比较的两侧都必须过这一道。
 *
 * 非十六进制串（持久 ID 一类）只做「去首尾空白 + 大写」：
 * 它们可能是任意文本，按字节重排会把要跨重启比对的锚改坏。
 */
export function normalizeDeviceAddress(value: string): string {
  const upper: string = value.trim().toUpperCase();
  if (upper.length === 0) return '';
  const parts: string[] = upper.split(/[\s:\-\._]+/).filter((item: string): boolean => item.length > 0);
  if (parts.length === 0) return '';
  let hex: string = '';
  let allHex: boolean = true;
  parts.forEach((part: string): void => {
    if (!isHexText(part)) allHex = false;
    hex += part;
  });
  if (!allHex || hex.length % 2 !== 0) return upper;
  let grouped: string = '';
  for (let index = 0; index < hex.length; index += 2) {
    if (grouped.length > 0) grouped += ':';
    grouped += hex.substring(index, index + 2);
  }
  return grouped;
}

/**
 * 从扫描键里取出地址：'ble:AA:BB' → 'AA:BB'。
 *
 * 扫描器统一用 'ble:' / 'wifi:' / 'nearlink:' + 地址 生成 `Sighting.key`，
 * 而配对名单只给地址、不给键，两边要能对上就必须剥掉前缀。
 * 剥之前先判「首段是不是十六进制」：裸地址 'AA:BB:CC' 的首段是 'AA'，
 * 若按「第一个冒号前都是前缀」去切，会把地址切残。
 */
export function deviceAddressOfKey(deviceKey: string): string {
  const text: string = deviceKey.trim();
  const colon: number = text.indexOf(':');
  if (colon < 0) return text;
  const head: string = text.substring(0, colon);
  if (head.length === 0 || isHexText(head)) return text;
  return text.substring(colon + 1);
}

/**
 * Class of Device → 自有设备种类。
 *
 * 参数口径与 `FieldwatchDeviceExplain.codHint` 保持一致：
 * `majorClass` 是 CoD 第 8–12 位（5 位主类别）；
 * `majorMinorClass` 是第 2–7 位（6 位次类别）。
 * **手上只有完整 24 位 CoD 时，必须先自行 `(cod >> 8) & 0x1F` 与 `(cod >> 2) & 0x3F`** ——
 * 直接传整包进来会把次类别的低位当成主类别，得到的种类静默错掉。
 * 函数内部仍做一次掩码：调用方拿到的是系统枚举时常见 0x01/0x04 这类值，
 * 但也不乏带了更高位脏位的写法，掩掉比在六处调用点各写一遍更稳。
 *
 * 这里永远不会返回 TRACKER —— CoD 表里没有「追踪器」这个类别，
 * 防丢标签几乎只发 BLE 广播、不声明 CoD。它只能由特征库签名推出。
 */
export function kindFromDeviceClass(majorClass: number, majorMinorClass: number): OwnDeviceKind {
  const major: number = majorClass & 0x1F;
  const minor: number = majorMinorClass & 0x3F;
  if (major === COD_MAJOR_AUDIO_VIDEO) {
    // 音频/视频大类：可穿戴耳机、免提、头戴耳机在形态上都是「耳机」；
    // 扬声器、便携音频、HiFi 都当「音箱」；车载音响单独认成「车」。
    if (minor === COD_MINOR_WEARABLE_HEADSET || minor === COD_MINOR_HANDS_FREE || minor === COD_MINOR_HEADPHONES) {
      return OwnDeviceKind.HEADPHONES;
    }
    if (minor === COD_MINOR_LOUDSPEAKER || minor === COD_MINOR_PORTABLE_AUDIO || minor === COD_MINOR_HIFI_AUDIO) {
      return OwnDeviceKind.SPEAKER;
    }
    if (minor === COD_MINOR_CAR_AUDIO) return OwnDeviceKind.CAR;
    // 机顶盒、录像机、摄像机、显示器、视频会议、游戏机等与「找东西」无关。
    return OwnDeviceKind.OTHER;
  }
  if (major === COD_MAJOR_WEARABLE) {
    // 可穿戴大类里只有腕表算「手表」；寻呼机、夹克、头盔、眼镜都不算。
    return minor === COD_MINOR_WRISTWATCH ? OwnDeviceKind.WATCH : OwnDeviceKind.OTHER;
  }
  if (major === COD_MAJOR_COMPUTER) {
    // 计算机大类下的「可穿戴计算机」形态上就是手表/手环一类。
    return minor === COD_MINOR_COMPUTER_WEARABLE ? OwnDeviceKind.WATCH : OwnDeviceKind.OTHER;
  }
  return OwnDeviceKind.OTHER;
}

/**
 * 认领那一刻的广播内容快照，锚（持久 ID / 地址）失效时用来兜底。
 *
 * 构造时统一做清洁：名称去首尾空白、UUID 大写去重、数组复制。
 * 复制不是为了防谁，而是因为调用方常把实时 `RadioFacts` 的数组直接递进来，
 * 后续扫描会就地改写它 —— 若不复制，档案里的「认领那一刻」会跟着一起变，
 * 指纹匹配就从「比对快照」退化成「比对同一份实时数据」，永远命中。
 */
export class OwnDeviceFingerprint {
  /** 广播名 / 配对名；空串表示当时没拿到名字。 */
  public name: string;
  /** BLE Company ID 列表（厂商标识，不是厂商数据内容）。 */
  public manufacturerIds: number[];
  /** 128 位服务 UUID 全串，统一大写、去重。 */
  public serviceUuids: string[];
  /** 认领当时命中的特征库 fleetId。 */
  public signatureIds: string[];
  constructor(name: string = '', manufacturerIds: number[] = [], serviceUuids: string[] = [], signatureIds: string[] = []) {
    this.name = name.trim();
    this.manufacturerIds = manufacturerIds.slice();
    this.serviceUuids = normalizeUuidList(serviceUuids);
    this.signatureIds = normalizeIdList(signatureIds);
  }
  /** 空指纹：档案刚建、或这次观测什么都没广播时占位。空指纹对任何观测的打分恒为 0。 */
  static empty(): OwnDeviceFingerprint {
    return new OwnDeviceFingerprint();
  }
}

/**
 * 一份「这台是我的」的身份档案。
 *
 * 为什么不能只存一个地址：`getPairedDevices()` 给的是系统分配的**虚拟地址**，
 * 配对关系存续期间稳定，但取消配对或蓝牙关闭后重新获取会变。
 * 所以身份由三根锚叠加而成 —— 持久 ID（最稳）、虚拟地址（配对期内稳）、
 * 指纹（锚都失效时的兜底），三者的判定顺序由 matcher 负责。
 */
export class OwnDeviceProfile {
  /** 本机主键（落库用）；不用地址做主键，因为地址会变。 */
  public id: string;
  /** 系统持久地址；空串 = 未取得（权限不可用时会一直是空串，空串绝不参与匹配）。 */
  public persistentId: string;
  /** 配对名单/扫描到的地址，已在构造时归一化。 */
  public virtualAddress: string;
  /** 扫描键，如 'ble:AA:BB:CC:DD:EE:FF'；与 `Sighting.key` 同一口径，Hunt/雷达直接用它。 */
  public deviceKey: string;
  /** 广播名或系统配对名（原始值，展示时走 label()）。 */
  public displayName: string;
  /** 用户改的名字；优先于 displayName。 */
  public customName: string;
  public kind: OwnDeviceKind;
  /** Class of Device；-1 = 未知。 */
  public deviceClass: number;
  /** 认领时的广播快照。 */
  public fingerprint: OwnDeviceFingerprint;
  /**
   * 「这不是我的设备」纠错留下的黑名单。
   *
   * 为什么是数组而不是一个布尔：用户点错一次不该让整台设备永久失去认领资格，
   * 也不能因为后来换了个房间就自动解除 —— 保存**被否掉的那些广播长相**，
   * 只在相似度达到阈值时否决，别的形态（比如固件升级后多了个 UUID）仍可认领。
   */
  public denyFingerprints: OwnDeviceFingerprint[];
  /** 观测管线回写的「上次见到」。 */
  public lastSeenAt: number;
  public lastLatitude: number;
  public lastLongitude: number;
  /** 认领时刻；0 = 未记录。领域层不自己取时间，否则单测与回放都不稳。 */
  public claimedAt: number;
  /** 'paired'（来自系统配对名单）| 'scan'（用户在扫描列表里认领）。 */
  public source: string;
  constructor(id: string = '', persistentId: string = '', virtualAddress: string = '', deviceKey: string = '',
    displayName: string = '', kind: OwnDeviceKind = OwnDeviceKind.OTHER, deviceClass: number = -1,
    fingerprint: OwnDeviceFingerprint = OwnDeviceFingerprint.empty(), source: string = '') {
    this.id = id;
    this.persistentId = persistentId.trim();
    // 构造时就归一化；matcher 那边还会再归一化一次 —— 档案可能来自旧版本落库，
    // 那一份的 virtualAddress 没经过这道处理，双保险代价极小。
    this.virtualAddress = normalizeDeviceAddress(virtualAddress);
    this.deviceKey = deviceKey;
    this.displayName = displayName.trim();
    this.customName = '';
    this.kind = kind;
    this.deviceClass = deviceClass;
    this.fingerprint = fingerprint;
    this.denyFingerprints = [];
    this.lastSeenAt = 0;
    this.lastLatitude = 0;
    this.lastLongitude = 0;
    this.claimedAt = 0;
    this.source = source;
  }
  /**
   * 展示名三级回退：自定义名 → 广播/配对名 → 空串。
   *
   * 空串交给 UI 决定怎么显示（资源文件里的「未命名设备」）。
   * 领域层写死中文的代价是 i18n 与「日常页禁术语」两条验收都要在这里返工。
   */
  label(): string {
    const custom: string = this.customName.trim();
    if (custom.length > 0) return custom;
    const display: string = this.displayName.trim();
    if (display.length > 0) return display;
    return '';
  }
}

/**
 * 一次实时观测里与「认身份」有关的那几项。
 *
 * 刻意保留原始写法（不在这里归一化）：归一化放在匹配时做，
 * 「地址大小写/分隔符不同也能命中」这件事才能在单测里被看见。
 */
export class OwnDeviceCandidate {
  public deviceKey: string;
  public address: string;
  public persistentId: string;
  public fingerprint: OwnDeviceFingerprint;
  constructor(deviceKey: string = '', address: string = '', persistentId: string = '',
    fingerprint: OwnDeviceFingerprint = OwnDeviceFingerprint.empty()) {
    this.deviceKey = deviceKey;
    this.address = address;
    this.persistentId = persistentId;
    this.fingerprint = fingerprint;
  }
}

/** 命中依据。DENIED 不是「命中」，是「本该按指纹认出、但被黑名单否决」。 */
export enum OwnMatchReason { PERSISTENT = 'persistent', ADDRESS = 'address', FINGERPRINT = 'fingerprint', DENIED = 'denied', NONE = 'none' }

/**
 * 匹配结果。
 *
 * `score` 只在 FINGERPRINT 下是有意义的置信分（见 matcher 的权重）；
 * 其余情形固定 0，避免把「100/90 这种档位分」或「被否决」误读成相似度。
 */
export class OwnMatchResult {
  public matched: boolean;
  public profileId: string;
  public reason: OwnMatchReason;
  public score: number;
  constructor(matched: boolean = false, profileId: string = '', reason: OwnMatchReason = OwnMatchReason.NONE, score: number = 0) {
    this.matched = matched;
    this.profileId = profileId;
    this.reason = reason;
    this.score = score;
  }
}
