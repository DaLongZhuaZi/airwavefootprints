import { RadioKind, SignatureClass } from '../FieldwatchModels';

/** 与 Android Fieldwatch MatchRule.kind 一一对应的规则类型。 */
export enum SignatureRuleKind {
  OUI = 'OUI',
  MAC_PREFIX = 'MAC_PREFIX',
  NAME_CONTAINS = 'NAME_CONTAINS',
  NAME_GLOB = 'NAME_GLOB',
  SERVICE_UUID = 'SERVICE_UUID',
  SERVICE_DATA = 'SERVICE_DATA',
  MANUFACTURER_ID = 'MANUFACTURER_ID',
  MANUFACTURER_DATA = 'MANUFACTURER_DATA',
  RADIO_KIND = 'RADIO_KIND',
  HIDDEN_SSID = 'HIDDEN_SSID',
  VENDOR_IE_OUI = 'VENDOR_IE_OUI'
}

/** 解码数据来源。UNSUPPORTED 只用于读取旧包：本实现不解析该来源。 */
export enum SignatureDecodeSource {
  MANUFACTURER_DATA = 'manufacturerData',
  SERVICE_DATA = 'serviceData',
  UNSUPPORTED = 'unsupported'
}

export enum SignatureDecodeType {
  U8 = 'u8',
  I8 = 'i8',
  U16 = 'u16',
  I16 = 'i16',
  U24 = 'u24',
  U32 = 'u32',
  I32 = 'i32',
  F32 = 'f32',
  BITS = 'bits',
  UTF8 = 'utf8',
  HEX = 'hex',
  MAC = 'mac',
  BOOL = 'bool'
}

export enum SignatureDecodeEndian { LE = 'le', BE = 'be' }

export enum SignatureDecodeWhenOp { EQ = 'eq', NEQ = 'neq', MASK = 'mask', NMASK = 'nmask', LEN = 'len' }

/** Wi-Fi 协议类 IE OUI（WPA / RSN），不是厂商品牌，不参与 VENDOR_IE_OUI 匹配。 */
export const SIGNATURE_WIFI_PROTOCOL_IE_OUIS: string[] = ['0050F2', '000FAC'];

export const SIGNATURE_PACK_FORMAT: string = 'fieldwatch-signatures';
export const SIGNATURE_PACK_LEGACY_FORMAT: string = 'spectre-signatures';
export const SIGNATURE_PACK_FORMAT_VERSION: number = 1;

/** 只保留十六进制字符并转大写；用于 OUI、MAC、前缀比较。 */
export function signatureHexOnly(raw: string): string {
  if (raw.length === 0) return raw;
  let result: string = '';
  for (let index = 0; index < raw.length; index += 1) {
    const code: number = raw.charCodeAt(index);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isUpper: boolean = code >= 65 && code <= 70;
    const isLower: boolean = code >= 97 && code <= 102;
    if (isDigit || isUpper || isLower) result += raw.charAt(index).toUpperCase();
  }
  return result;
}

/** 字节序反转，用于 SERVICE_DATA 的“包含”匹配。 */
export function signatureReverseHexBytes(hex: string): string {
  const value: string = signatureHexOnly(hex);
  if (value.length < 2 || value.length % 2 !== 0) return '';
  let result: string = '';
  let index: number = value.length;
  while (index >= 2) {
    index -= 2;
    result += value.substring(index, index + 2);
  }
  return result;
}

/**
 * UUID 别名：同时给出完整首段与 16 位短形式，兼容 4 位、8 位和 128 位写法。
 * 例：`0000FD44-0000-1000-8000-00805F9B34FB` → [`0000FD4400001000800000805F9B34FB`, `0000FD44`, `FD44`]。
 */
export function signatureUuidAliases(raw: string): string[] {
  const hex: string = signatureHexOnly(raw);
  const result: string[] = [];
  if (hex.length === 0) return result;
  result.push(hex);
  if (hex.length >= 8) {
    const head: string = hex.substring(0, 8);
    if (result.indexOf(head) < 0) result.push(head);
    const short: string = hex.substring(4, 8);
    if (short.length === 4 && result.indexOf(short) < 0) result.push(short);
  }
  return result;
}

export function signatureRuleKindOf(value: string): SignatureRuleKind {
  const name: string = value.toUpperCase();
  if (name === 'OUI') return SignatureRuleKind.OUI;
  if (name === 'MAC_PREFIX') return SignatureRuleKind.MAC_PREFIX;
  if (name === 'NAME_CONTAINS') return SignatureRuleKind.NAME_CONTAINS;
  if (name === 'NAME_GLOB') return SignatureRuleKind.NAME_GLOB;
  if (name === 'SERVICE_UUID') return SignatureRuleKind.SERVICE_UUID;
  if (name === 'SERVICE_DATA') return SignatureRuleKind.SERVICE_DATA;
  if (name === 'MANUFACTURER_ID') return SignatureRuleKind.MANUFACTURER_ID;
  if (name === 'MANUFACTURER_DATA') return SignatureRuleKind.MANUFACTURER_DATA;
  if (name === 'RADIO_KIND') return SignatureRuleKind.RADIO_KIND;
  if (name === 'HIDDEN_SSID') return SignatureRuleKind.HIDDEN_SSID;
  if (name === 'VENDOR_IE_OUI') return SignatureRuleKind.VENDOR_IE_OUI;
  return SignatureRuleKind.NAME_CONTAINS;
}

export function signatureDecodeSourceOf(value: string): SignatureDecodeSource {
  if (value === 'manufacturerData') return SignatureDecodeSource.MANUFACTURER_DATA;
  if (value === 'serviceData') return SignatureDecodeSource.SERVICE_DATA;
  return SignatureDecodeSource.UNSUPPORTED;
}

export function signatureDecodeTypeOf(value: string): SignatureDecodeType {
  const name: string = value.toLowerCase();
  if (name === 'u8') return SignatureDecodeType.U8;
  if (name === 'i8') return SignatureDecodeType.I8;
  if (name === 'u16') return SignatureDecodeType.U16;
  if (name === 'i16') return SignatureDecodeType.I16;
  if (name === 'u24') return SignatureDecodeType.U24;
  if (name === 'u32') return SignatureDecodeType.U32;
  if (name === 'i32') return SignatureDecodeType.I32;
  if (name === 'f32') return SignatureDecodeType.F32;
  if (name === 'bits') return SignatureDecodeType.BITS;
  if (name === 'utf8') return SignatureDecodeType.UTF8;
  if (name === 'hex') return SignatureDecodeType.HEX;
  if (name === 'mac') return SignatureDecodeType.MAC;
  if (name === 'bool') return SignatureDecodeType.BOOL;
  return SignatureDecodeType.HEX;
}

export function signatureDecodeEndianOf(value: string): SignatureDecodeEndian {
  return value.toLowerCase() === 'be' ? SignatureDecodeEndian.BE : SignatureDecodeEndian.LE;
}

export function signatureDecodeWhenOpOf(value: string): SignatureDecodeWhenOp {
  const name: string = value.toLowerCase();
  if (name === 'neq') return SignatureDecodeWhenOp.NEQ;
  if (name === 'mask') return SignatureDecodeWhenOp.MASK;
  if (name === 'nmask') return SignatureDecodeWhenOp.NMASK;
  if (name === 'len') return SignatureDecodeWhenOp.LEN;
  return SignatureDecodeWhenOp.EQ;
}

export function signatureRadioKindOf(value: string): RadioKind | undefined {
  const name: string = value.toUpperCase();
  if (name === 'WIFI' || name === 'WI-FI') return RadioKind.WIFI;
  if (name === 'BLE') return RadioKind.BLE;
  // 必须识别星闪：漏掉它会让「星闪规则」在重新加载后静默变成「任意种类」。
  if (name === 'NEARLINK' || name === 'NEAR_LINK') return RadioKind.NEARLINK;
  return undefined;
}

/** 解析 catalog 的 kind 字段；兼容大小写、下划线和历史别名。 */
export function signatureClassOf(value: string): SignatureClass {
  const name: string = value.trim().toUpperCase().replace(/-/g, '_').replace(/ /g, '_');
  if (name === 'FINDER' || name.indexOf('FINDER') >= 0) return SignatureClass.FINDER;
  if (name === 'BEACON') return SignatureClass.BEACON;
  if (name === 'SIGNAGE') return SignatureClass.SIGNAGE;
  if (name === 'WEARABLE' || name === 'WEARABLES') return SignatureClass.WEARABLE;
  if (name === 'BODYWORN' || name === 'BODY_WORN') return SignatureClass.BODYWORN;
  if (name === 'SURVEILLANCE') return SignatureClass.SURVEILLANCE;
  if (name === 'DRONE' || name === 'DRONES') return SignatureClass.DRONE;
  if (name === 'HACKING' || name === 'PENTEST') return SignatureClass.HACKING;
  if (name === 'LAW_ENFORCEMENT' || name === 'PUBLIC_SAFETY') return SignatureClass.LAW_ENFORCEMENT;
  if (name === 'VEHICLE') return SignatureClass.VEHICLE;
  if (name === 'GLASSES') return SignatureClass.GLASSES;
  if (name === 'AUDIO') return SignatureClass.AUDIO;
  if (name === 'CAMERA' || name === 'CAMERAS') return SignatureClass.CAMERA;
  if (name === 'THERMOSTAT' || name === 'THERMOSTATS') return SignatureClass.THERMOSTAT;
  if (name === 'LOCK' || name === 'ACCESS_CONTROL') return SignatureClass.LOCK;
  if (name === 'HEALTH') return SignatureClass.HEALTH;
  if (name === 'HOME' || name === 'HOME_IOT') return SignatureClass.HOME;
  if (name === 'ISP' || name === 'ISP_ROUTERS') return SignatureClass.ISP;
  if (name === 'ROUTER' || name === 'ROUTERS') return SignatureClass.ROUTER;
  if (name === 'MESH') return SignatureClass.MESH;
  if (name === 'PHONE' || name === 'PHONES_PCS') return SignatureClass.PHONE;
  return SignatureClass.OTHER;
}

export class SignatureRule {
  public kind: SignatureRuleKind = SignatureRuleKind.NAME_CONTAINS;
  public text: string = '';
  public companyId: number = 0;
  public dataPrefixHex: string = '';
  public radio: RadioKind | undefined = undefined;
  public enabled: boolean = true;
  /**
   * 前缀匹配的**字节偏移**（0 = 数据开头）。
   *
   * 起因：Theengs 等外部设备库大量用「第 N 字节是 X」来区分型号
   * （如 `servicedata index 2 == 0x5d`），而此前只能匹配位置 0，
   * 导致 117 个设备定义里只有 26 个能表达。
   *
   * **基准是已剥离头部的数据**：`manufacturerDataHex` 不含公司 ID、
   * `ServiceDataRecord.dataHex` 不含 UUID，两者都已在解析阶段切掉开头 2 字节。
   * 因此外部库里「含头部」的下标 N 要映射成 N - 2。
   */
  public offset: number = 0;
  /**
   * 分组号：**同组内 AND，组间 OR**（或的与）。0 表示不分组。
   *
   * 语义是严格超集 —— 全部规则都是 0 时行为与从前完全一致
   * （仍由 `fleet.matchAny` 决定整体是 OR 还是 AND）。
   * 非 0 分组作为**额外的 OR 分支**：舰队命中 = 基础集合命中 或 任一分组命中。
   *
   * 对应外部库的 `A | B & C`（`&` 比 `|` 紧，即 A 或 (B 且 C)）。
   */
  public group: number = 0;
  /** 数据长度的下界（字节）；0 = 不约束。外部库的 `>=` 与 `=` 都映射到这里。 */
  public minLen: number = 0;
  /** 数据长度的上界（字节）；0 = 不约束。外部库的 `=` 是精确长度，用 minLen = maxLen 表达。 */
  public maxLen: number = 0;

  constructor(kind: SignatureRuleKind, text: string = '', companyId: number = 0, dataPrefixHex: string = '', radio: RadioKind | undefined = undefined, enabled: boolean = true) {
    this.kind = kind; this.text = text; this.companyId = companyId; this.dataPrefixHex = dataPrefixHex; this.radio = radio; this.enabled = enabled;
  }

  /**
   * 该规则是否可能命中**广播型**信号源（BLE 与星闪）；用于决定是否显示解码字段编辑器。
   *
   * 星闪与 BLE 同属广播源，因此两者都返回 true —— 但**不表示它们互相匹配**，
   * 真正的匹配由引擎按 `radio` 精确比较（`rule.radio !== context.kind` 即跳过）。
   */
  couldMatchBle(): boolean {
    if (this.kind === SignatureRuleKind.HIDDEN_SSID || this.kind === SignatureRuleKind.VENDOR_IE_OUI) return false;
    if (this.kind === SignatureRuleKind.SERVICE_UUID || this.kind === SignatureRuleKind.SERVICE_DATA) return true;
    if (this.kind === SignatureRuleKind.MANUFACTURER_ID || this.kind === SignatureRuleKind.MANUFACTURER_DATA) return true;
    return this.radio !== RadioKind.WIFI;
  }
  /** 无线电种类 → 签名包里的标识；三态必须各自区分。 */
  radioTag(): string {
    if (this.radio === RadioKind.WIFI) return 'WIFI';
    if (this.radio === RadioKind.NEARLINK) return 'NEARLINK';
    return this.radio === RadioKind.BLE ? 'BLE' : '';
  }
}

export class SignatureDecodeWhen {
  public offset: number = 0;
  public length: number = 1;
  public op: SignatureDecodeWhenOp = SignatureDecodeWhenOp.EQ;
  public valueHex: string = '';
  public and: SignatureDecodeWhen | undefined = undefined;

  constructor(offset: number, op: SignatureDecodeWhenOp, valueHex: string, length: number = 1, and: SignatureDecodeWhen | undefined = undefined) {
    this.offset = offset; this.op = op; this.valueHex = valueHex; this.length = length; this.and = and;
  }
}

export class SignatureDecodeField {
  public id: string = '';
  public label: string = '';
  public offset: number = 0;
  public length: number = 0;
  public type: SignatureDecodeType = SignatureDecodeType.HEX;
  public endian: SignatureDecodeEndian = SignatureDecodeEndian.LE;
  public bitOffset: number = -1;
  public bitWidth: number = -1;
  public scale: number | undefined = undefined;
  public offsetAdd: number | undefined = undefined;
  public modulo: number | undefined = undefined;
  public unit: string = '';
  public enumLabels: Map<string, string> | undefined = undefined;
  public live: boolean = false;
  public liveEmphasis: string[] = [];
  public enumNotes: Map<string, string> | undefined = undefined;
  public gate: SignatureDecodeWhen | undefined = undefined;

  /** 未显式给出长度时按类型推断；BITS 按位区间向上取整到字节。 */
  resolvedLength(): number {
    if (this.length > 0) return this.length;
    if (this.type === SignatureDecodeType.BITS) {
      const start: number = this.bitOffset < 0 ? 0 : this.bitOffset;
      const width: number = this.bitWidth < 0 ? 1 : this.bitWidth;
      return Math.max(1, Math.ceil((start + width) / 8));
    }
    if (this.type === SignatureDecodeType.U8 || this.type === SignatureDecodeType.I8 || this.type === SignatureDecodeType.BOOL) return 1;
    if (this.type === SignatureDecodeType.U16 || this.type === SignatureDecodeType.I16) return 2;
    if (this.type === SignatureDecodeType.U24) return 3;
    if (this.type === SignatureDecodeType.U32 || this.type === SignatureDecodeType.I32 || this.type === SignatureDecodeType.F32) return 4;
    if (this.type === SignatureDecodeType.MAC) return 6;
    return 1;
  }
}

export class SignatureFleetDecode {
  public source: SignatureDecodeSource = SignatureDecodeSource.MANUFACTURER_DATA;
  public serviceUuid: string = '';
  public companyId: number = 0;
  public includeCompanyId: boolean = false;
  public fields: SignatureDecodeField[] = [];

  constructor(source: SignatureDecodeSource, fields: SignatureDecodeField[] = [], serviceUuid: string = '', companyId: number = 0, includeCompanyId: boolean = false) {
    this.source = source; this.fields = fields; this.serviceUuid = serviceUuid; this.companyId = companyId; this.includeCompanyId = includeCompanyId;
  }
}

export class SignatureFleet {
  public id: string = '';
  public name: string = '';
  public enabled: boolean = true;
  public matchAny: boolean = true;
  public colorIndex: number = 0;
  public rules: SignatureRule[] = [];
  public minPeers: number = 0;
  public peerWindowSec: number = 60;
  public clusterByOui: boolean = false;
  public sequentialMac: boolean = false;
  public notes: string = '';
  public attentionNote: string = '';
  public builtIn: boolean = false;
  public category: SignatureClass = SignatureClass.OTHER;
  public decode: SignatureFleetDecode | undefined = undefined;

  constructor(id: string, name: string, category: SignatureClass = SignatureClass.OTHER, rules: SignatureRule[] = [], builtIn: boolean = false) {
    this.id = id; this.name = name; this.category = category; this.rules = rules; this.builtIn = builtIn;
  }

  canHaveBleDecode(): boolean {
    if (this.rules.length === 0) return true;
    return this.rules.some((rule: SignatureRule): boolean => rule.couldMatchBle());
  }
}

export function cloneSignatureRule(rule: SignatureRule): SignatureRule {
  const copy: SignatureRule = new SignatureRule(rule.kind, rule.text, rule.companyId, rule.dataPrefixHex, rule.radio, rule.enabled);
  copy.offset = rule.offset;
  copy.group = rule.group;
  copy.minLen = rule.minLen;
  copy.maxLen = rule.maxLen;
  return copy;
}

export function cloneSignatureDecodeField(field: SignatureDecodeField): SignatureDecodeField {
  const copy: SignatureDecodeField = new SignatureDecodeField();
  copy.id = field.id; copy.label = field.label; copy.offset = field.offset; copy.length = field.length;
  copy.type = field.type; copy.endian = field.endian; copy.bitOffset = field.bitOffset; copy.bitWidth = field.bitWidth;
  copy.scale = field.scale; copy.offsetAdd = field.offsetAdd; copy.modulo = field.modulo; copy.unit = field.unit;
  copy.enumLabels = field.enumLabels; copy.live = field.live; copy.liveEmphasis = field.liveEmphasis.slice();
  copy.enumNotes = field.enumNotes; copy.gate = field.gate;
  return copy;
}

/** 深拷贝一条签名；编辑器每次修改后整体替换，保证 ArkUI 能观察到变化。 */
export function cloneSignatureFleet(fleet: SignatureFleet): SignatureFleet {
  const copy: SignatureFleet = new SignatureFleet(fleet.id, fleet.name, fleet.category, [], fleet.builtIn);
  copy.enabled = fleet.enabled; copy.matchAny = fleet.matchAny; copy.colorIndex = fleet.colorIndex;
  copy.minPeers = fleet.minPeers; copy.peerWindowSec = fleet.peerWindowSec;
  copy.clusterByOui = fleet.clusterByOui; copy.sequentialMac = fleet.sequentialMac;
  copy.notes = fleet.notes; copy.attentionNote = fleet.attentionNote;
  fleet.rules.forEach((rule: SignatureRule): void => { copy.rules.push(cloneSignatureRule(rule)); });
  const decode: SignatureFleetDecode | undefined = fleet.decode;
  if (decode !== undefined) {
    const decodeCopy: SignatureFleetDecode = new SignatureFleetDecode(decode.source, [], decode.serviceUuid, decode.companyId, decode.includeCompanyId);
    decode.fields.forEach((field: SignatureDecodeField): void => { decodeCopy.fields.push(cloneSignatureDecodeField(field)); });
    copy.decode = decodeCopy;
  }
  return copy;
}

export class SignaturePack {
  public format: string = SIGNATURE_PACK_FORMAT;
  public formatVersion: number = SIGNATURE_PACK_FORMAT_VERSION;
  public exportedAt: string = '';
  public appVersion: string = '';
  public catalogVersion: number = 0;
  public fleets: SignatureFleet[] = [];

  constructor(fleets: SignatureFleet[] = [], catalogVersion: number = 0, appVersion: string = '', exportedAt: string = '') {
    this.fleets = fleets; this.catalogVersion = catalogVersion; this.appVersion = appVersion; this.exportedAt = exportedAt;
  }
}
