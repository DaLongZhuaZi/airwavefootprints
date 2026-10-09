import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchRadioDb';

/**
 * IEEE / 蓝牙 名称库的只读访问器。
 *
 * 原版 `domain/RadioDb.kt` 读取 assets 里的 `lookups/radiodb.bin`（magic SPLK，六段索引 + 名称池）。
 * 这里复用同一个二进制文件与同一套格式，因此厂商名与蓝牙公司名和原版完全一致。
 * 格式（小端）：
 *   'SPLK' | version:u16 | reserved:u16 | builtYmd:i32 | nsec:i32
 *   nsec × ( tag:char[4] | offset:i32 )
 *   各段：n:i32 后跟 n × (key, idx)
 *   noff 段：n:i32 后跟 (n+1) × i32 名称偏移
 *   nstr 段：名称字节池
 */
/** 取十六进制串（容忍 `AA:BB:CC` 与 `AABBCC` 两种写法）。 */
function normalizedHex(value: string): string {
  return value.replace(/[^A-Fa-f0-9]/g, '').toUpperCase();
}

/**
 * 是否本地管理地址（随机 / 虚拟 MAC）。对齐原版 `MacUtil.isRandomized`。
 *
 * 判据：本地管理位（0x02）已置 **且** 多播位（0x01）未置。
 * 多播地址不是设备地址，单独排除。
 */
export function isLocallyAdministered(mac: string): boolean {
  const hex: string = normalizedHex(mac);
  if (hex.length < 2) return false;
  const first: number = parseInt(hex.substring(0, 2), 16);
  if (isNaN(first)) return false;
  return (first & 0x02) !== 0 && (first & 0x01) === 0;
}

/**
 * 清掉本地管理位，还原**烧录的厂商前缀**。对齐原版 `MacUtil.wifiOui24Universal`。
 *
 * 原版注释说得很清楚：**访客 / Mesh / 附加 SSID 的虚拟 BSSID 常常就是
 * 「厂商前缀 + 本地管理位置 1」** —— 直接拿原地址查 OUI 必然落空，
 * 清掉那一位就能查回真实厂商。
 *
 * 地址本身不是本地管理（或长度不足）时返回原串，调用方无需分支。
 */
export function clearLocallyAdministered(mac: string): string {
  const hex: string = normalizedHex(mac);
  if (hex.length < 2) return hex;
  const first: number = parseInt(hex.substring(0, 2), 16);
  if (isNaN(first)) return hex;
  if ((first & 0x02) === 0) return hex;
  if ((first & 0x01) !== 0) return hex;
  const cleared: string = (first & 0xFD).toString(16).toUpperCase().padStart(2, '0');
  return cleared + hex.substring(2);
}

/**
 * 「手机大厂」OUI —— 这些厂商的地址段太泛，显示成品牌反而误导。
 * 对齐原版 `RadioDb.PHONE_HOUSE_VENDOR`。
 *
 * 一台 Apple OUI 的设备可能是手机、手表、耳机、笔电；
 * 标成「Apple」并不比不标更有信息量，而签名匹配（AirTag / AirPods 等）才是有效识别。
 */
const PHONE_HOUSE_VENDOR: string[] = ['apple', 'google', 'samsung electronics', 'microsoft'];

export function isPhoneHouseVendor(vendor: string): boolean {
  const lowered: string = vendor.toLowerCase();
  if (lowered.length === 0) return false;
  for (let index: number = 0; index < PHONE_HOUSE_VENDOR.length; index += 1) {
    if (lowered.indexOf(PHONE_HOUSE_VENDOR[index]) >= 0) return true;
  }
  return false;
}

export class FieldwatchRadioDb {
  private ready: boolean = false;
  private bytes: Uint8Array = new Uint8Array(0);
  private view: DataView | undefined = undefined;
  private malKeys: Int32Array = new Int32Array(0);
  private malIdx: Int32Array = new Int32Array(0);
  private cidKeys: Int32Array = new Int32Array(0);
  private cidIdx: Int32Array = new Int32Array(0);
  private btKeys: Int32Array = new Int32Array(0);
  private btIdx: Int32Array = new Int32Array(0);
  /** GAP Appearance（AD type 0x19）-> 名称。原版 RadioDb 的 appKeys。 */
  private appKeys: Int32Array = new Int32Array(0);
  private appIdx: Int32Array = new Int32Array(0);
  /** 蓝牙服务 UUID（短形式 16 位）-> 名称。原版 RadioDb 的 uuidKeys。 */
  private uuidKeys: Int32Array = new Int32Array(0);
  private uuidIdx: Int32Array = new Int32Array(0);
  /**
   * MA-M（28 位）与 MA-S（36 位）前缀 -> 厂商名。
   *
   * **这两段此前从未被读取**：`long` 段在 bin 里一直存在（13713 条 = MA-M 6560 + MA-S 7153），
   * 而 `mal` 只覆盖 24 位 MA-L —— 于是 MA-M / MA-S 地址的设备解析不出厂商名。
   * （`app` / `uuid` 两段也曾长期未读、已修；`long` 是漏掉的第三个。）
   *
   * **为什么拆成两个数组而不是用一个 64 位键**：bin 里的键是 `(位宽 << 56) | 前缀值`，
   * 而 `36 << 56` ≈ 2.6e18，**远超 JS 安全整数上限 9e15**，无法精确表示。
   * 好在键按高字节天然分块（0x1c 块在前、0x24 块在后），**块内低 48 位仍然有序**；
   * 拆开后 36 位值最大仅 6.8e10，完全在精确范围内。
   */
  private mamKeys: Float64Array = new Float64Array(0);
  private mamIdx: Int32Array = new Int32Array(0);
  private masKeys: Float64Array = new Float64Array(0);
  private masIdx: Int32Array = new Int32Array(0);
  private nameOff: Int32Array = new Int32Array(0);
  private nameStart: number = 0;
  private nameEnd: number = 0;

  /** 载入并解析。失败时保持 ready=false，所有查询返回空串。 */
  load(raw: Uint8Array): boolean {
    try {
      this.bytes = raw;
      const view: DataView = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
      this.view = view;
      if (raw.byteLength < 16) return false;
      if (String.fromCharCode(raw[0], raw[1], raw[2], raw[3]) !== 'SPLK') {
        logger.warn(TAG, 'radiodb magic 不匹配');
        return false;
      }
      const version: number = view.getUint16(4, true);
      if (version !== 1) {
        logger.warn(TAG, 'radiodb 版本不支持: ' + version.toString());
        return false;
      }
      const sectionCount: number = view.getInt32(12, true);
      const offsets: Map<string, number> = new Map<string, number>();
      for (let index: number = 0; index < sectionCount; index += 1) {
        const at: number = 16 + index * 8;
        const tag: string = String.fromCharCode(raw[at], raw[at + 1], raw[at + 2], raw[at + 3]).replace(/\u0000+$/, '');
        offsets.set(tag, view.getInt32(at + 4, true));
      }
      const mal: number = offsets.get('mal') ?? -1;
      const cid: number = offsets.get('cid') ?? -1;
      const btc: number = offsets.get('btc') ?? -1;
      const noff: number = offsets.get('noff') ?? -1;
      const nstr: number = offsets.get('nstr') ?? -1;
      if (mal < 0 || noff < 0 || nstr < 0) {
        logger.warn(TAG, 'radiodb 缺少必需段');
        return false;
      }
      const malData: IndexSection = this.readIndex(mal, 4);
      this.malKeys = malData.keys;
      this.malIdx = malData.idx;
      if (cid >= 0) { const data: IndexSection = this.readIndex(cid, 4); this.cidKeys = data.keys; this.cidIdx = data.idx; }
      if (btc >= 0) { const data: IndexSection = this.readIndex(btc, 2); this.btKeys = data.keys; this.btIdx = data.idx; }
      // app 与 uuid 两段此前**从未被读取**，因此设备详情里既显示不出
      // 「它自称是什么」（Appearance），也显示不出服务 UUID 的名字。
      // 这两段在 bin 里一直存在（342 条外观 / 76 条服务），只是没用。
      const app: number = offsets.get('app') ?? -1;
      const uuid: number = offsets.get('uuid') ?? -1;
      if (app >= 0) { const data: IndexSection = this.readIndex(app, 2); this.appKeys = data.keys; this.appIdx = data.idx; }
      if (uuid >= 0) { const data: IndexSection = this.readIndex(uuid, 2); this.uuidKeys = data.keys; this.uuidIdx = data.idx; }
      const lng: number = offsets.get('long') ?? -1;
      if (lng >= 0) this.readLongSection(lng);
      const nameCount: number = view.getInt32(noff, true);
      const off: Int32Array = new Int32Array(nameCount + 1);
      for (let index: number = 0; index <= nameCount; index += 1) off[index] = view.getInt32(noff + 4 + index * 4, true);
      this.nameOff = off;
      this.nameStart = nstr;
      this.nameEnd = nstr + off[nameCount];
      this.ready = true;
      logger.info(TAG, 'radiodb 已载入: MA-L ' + this.malKeys.length.toString() + ' 条, MA-M ' + this.mamKeys.length.toString()
        + ' 条, MA-S ' + this.masKeys.length.toString() + ' 条, 名称 ' + nameCount.toString() + ' 个');
      return true;
    } catch (error) {
      logger.warn(TAG, 'radiodb 解析失败: ' + (error instanceof Error ? error.message : String(error)));
      return false;
    }
  }

  /** 诊断摘要：确认索引与名称池真的可用（自检用）。 */
  describe(): string {
    if (!this.ready) return '未载入';
    const firstKey: number = this.malKeys.length > 0 ? this.malKeys[0] : -1;
    const lastKey: number = this.malKeys.length > 0 ? this.malKeys[this.malKeys.length - 1] : -1;
    return 'mal=' + this.malKeys.length.toString()
      + ' 首键=' + firstKey.toString(16) + ' 末键=' + lastKey.toString(16)
      + ' app=' + this.appKeys.length.toString()
      + ' uuid=' + this.uuidKeys.length.toString()
      + ' 名称数=' + (this.nameOff.length - 1).toString()
      + ' 名0=[' + this.nameAt(0) + ']'
      + ' 名1=[' + this.nameAt(1) + ']'
      + ' nstr=' + this.nameStart.toString() + ' 池长=' + (this.nameEnd - this.nameStart).toString();
  }
  isReady(): boolean { return this.ready; }

  /**
   * 厂商名（对齐原版 `RadioDb.vendorForMac`）。**界面与 facts 都应走这条。**
   *
   * 与 `vendorForOui24` 的两点关键区别：
   *
   * ① **随机 / 虚拟 MAC 先还原真实 OUI。** 访客 / Mesh / 附加 SSID 的 BSSID
   *    常常是「厂商前缀 + 本地管理位置 1」，直接查必然落空 ——
   *    这正是「我们识别不出品牌、原版能」的主要原因。
   *    签名引擎早已做了这一步（`FieldwatchSignatureEngine` 里清 0x02），
   *    但**厂商名这条路一直没做**，于是品牌列对随机 MAC 永远空白。
   *
   * ② **过滤手机大厂。** apple / google / samsung / microsoft 的 OUI 太泛，
   *    标出来反而误导；有效识别应交给签名匹配。
   *
   * 注意 ② 只作用于**还原出来**的那条路径（与原版一致）：
   * 真实（非随机）地址上的 Apple 依然照常显示。
   */
  vendorForMac(mac: string): string {
    if (!this.ready) return '';
    const hex: string = normalizedHex(mac);
    if (hex.length < 6) return '';
    if (isLocallyAdministered(hex)) {
      const name: string = this.vendorForOui24(clearLocallyAdministered(hex));
      return isPhoneHouseVendor(name) ? '' : name;
    }
    return this.vendorForOui24(hex);
  }

  /**
   * 厂商名查询。接受 OUI（`AA:BB:CC`）或**完整 MAC**；查不到返回空串。
   *
   * 传入完整 MAC 时依次尝试 **MA-S(36) → MA-M(28) → MA-L(24)**，越具体越优先 ——
   * IEEE 把 MA-M / MA-S 子块从 MA-L 块里划出，**子块所有者常与父块所有者不同**
   * （例：`00:55:DA` 是 OUI，其下 `00:55:DA:0`~`00:55:DA:F` 是 16 个 MA-M 子块，各有公司）。
   * 只传 6 位 OUI 时自然退化为纯 MA-L 查询，行为与从前一致。
   */
  vendorForOui24(oui: string): string {
    if (!this.ready) return '';
    const hex: string = oui.replace(/[^A-Fa-f0-9]/g, '').toUpperCase();
    if (hex.length < 6) return '';
    // MA-S：36 位 = 前 9 个十六进制位
    if (hex.length >= 9 && this.masKeys.length > 0) {
      const mas: string = this.lookupNum(this.masKeys, this.masIdx, parseInt(hex.substring(0, 9), 16));
      if (mas.length > 0) return mas;
    }
    // MA-M：28 位 = 前 7 个十六进制位
    if (hex.length >= 7 && this.mamKeys.length > 0) {
      const mam: string = this.lookupNum(this.mamKeys, this.mamIdx, parseInt(hex.substring(0, 7), 16));
      if (mam.length > 0) return mam;
    }
    // MA-L：24 位 = 前 6 个十六进制位
    const key: number = parseInt(hex.substring(0, 6), 16);
    if (isNaN(key)) return '';
    const mal: string = this.lookup(this.malKeys, this.malIdx, key);
    return mal.length > 0 ? mal : this.lookup(this.cidKeys, this.cidIdx, key);
  }

  /** 蓝牙公司 ID -> 名称。 */
  company(id: number): string {
    if (!this.ready) return '';
    return this.lookup(this.btKeys, this.btIdx, id & 0xFFFF);
  }

  /**
   * GAP Appearance -> 名称。对应原版 `RadioDb.appearance`。
   *
   * **两级查询**：先按完整值查，查不到再用类别位（`value & 0xFFC0`）查。
   * 蓝牙规范只给类别定义了名称，具体型号往往是类别内的细分，
   * 因此退一级能让「未知型号」也显示出「心率传感器」这类有用信息。
   */
  appearance(value: number): string {
    if (!this.ready || value < 0) return '';
    const v: number = value & 0xFFFF;
    const direct: string = this.lookup(this.appKeys, this.appIdx, v);
    if (direct.length > 0) return direct;
    const category: number = v & 0xFFC0;
    if (category !== v) return this.lookup(this.appKeys, this.appIdx, category);
    return '';
  }
  /**
   * 服务 UUID -> 名称。对应原版 `RadioDb.serviceUuid`。
   *
   * 接受三种输入：4 位十六进制（16 位 UUID）、8 位（32 位 UUID，取末 4 位）、
   * 以及带蓝牙基准 UUID 的完整 128 位形式。其余一律返回空串。
   */
  serviceUuid(uuid: string): string {
    if (!this.ready) return '';
    const hex: string = uuid.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
    let short: number = -1;
    if (hex.length === 4) short = parseInt(hex, 16);
    else if (hex.length === 8) short = parseInt(hex.substring(4, 8), 16);
    else if (hex.length === 32 && hex.startsWith('0000') && hex.endsWith('00001000800000805F9B34FB')) {
      short = parseInt(hex.substring(4, 8), 16);
    } else return '';
    if (isNaN(short) || short < 0) return '';
    return this.lookup(this.uuidKeys, this.uuidIdx, short);
  }
  /**
   * 读取 `long` 段（**8 字节键**，`readIndex` 只支持 2/4 字节，故单独实现）。
   *
   * 键布局 `(位宽 << 56) | 前缀值`：位宽 28 = MA-M、36 = MA-S。
   * 用两个 32 位半字拼出低 48 位、**只取高字的高 8 位当位宽** ——
   * 这样既避开 BigInt，也避开 `36 << 56` 超出安全整数的问题。
   * 与 `readIndex` 一样，格式是「先连续读完 n 个 key，再连续读 n 个 idx」。
   */
  private readLongSection(offset: number): void {
    const view: DataView = this.view as DataView;
    const count: number = view.getInt32(offset, true);
    if (count <= 0) return;
    const mamKey: Array<number> = [];
    const mamName: Array<number> = [];
    const masKey: Array<number> = [];
    const masName: Array<number> = [];
    const keyAt: number = offset + 4;
    const idxAt: number = keyAt + count * 8;
    for (let index: number = 0; index < count; index += 1) {
      const lo: number = view.getInt32(keyAt + index * 8, true) >>> 0;
      const hi: number = view.getInt32(keyAt + index * 8 + 4, true) >>> 0;
      const width: number = (hi >>> 24) & 0xFF;
      const value: number = lo + (hi & 0xFFFFFF) * 4294967296;
      const nameIndex: number = view.getInt16(idxAt + index * 2, true) & 0xFFFF;
      if (width === 28) { mamKey.push(value); mamName.push(nameIndex); }
      else if (width === 36) { masKey.push(value); masName.push(nameIndex); }
    }
    this.mamKeys = this.toFloat64(mamKey);
    this.mamIdx = this.toInt32(mamName);
    this.masKeys = this.toFloat64(masKey);
    this.masIdx = this.toInt32(masName);
  }

  private toFloat64(source: Array<number>): Float64Array {
    const out: Float64Array = new Float64Array(source.length);
    for (let index: number = 0; index < source.length; index += 1) out[index] = source[index];
    return out;
  }

  private toInt32(source: Array<number>): Int32Array {
    const out: Int32Array = new Int32Array(source.length);
    for (let index: number = 0; index < source.length; index += 1) out[index] = source[index];
    return out;
  }

  /** Float64 键上的二分查找（`lookup` 只接受 Int32Array，36 位键放不下）。 */
  private lookupNum(keys: Float64Array, idx: Int32Array, target: number): string {
    if (isNaN(target)) return '';
    let lo: number = 0;
    let hi: number = keys.length - 1;
    while (lo <= hi) {
      const mid: number = (lo + hi) >> 1;
      const value: number = keys[mid];
      if (value < target) lo = mid + 1;
      else if (value > target) hi = mid - 1;
      else return this.nameAt(idx[mid]);
    }
    return '';
  }

  private readIndex(offset: number, keyBytes: number): IndexSection {
    const view: DataView = this.view as DataView;
    const count: number = view.getInt32(offset, true);
    const keys: Int32Array = new Int32Array(count);
    const idx: Int32Array = new Int32Array(count);
    // 原版格式是「先连续读完 n 个 key，再连续读 n 个 idx」，不是交替存放。
    // 交替读取会让键值整体错位（症状：查询恒为空，但名称池看起来是对的）。
    let at: number = offset + 4;
    for (let index: number = 0; index < count; index += 1) {
      keys[index] = keyBytes === 2 ? view.getInt16(at, true) & 0xFFFF : view.getInt32(at, true);
      at += keyBytes;
    }
    for (let index: number = 0; index < count; index += 1) {
      idx[index] = view.getInt16(at, true) & 0xFFFF;
      at += 2;
    }
    const section: IndexSection = new IndexSection();
    section.keys = keys;
    section.idx = idx;
    return section;
  }
  private lookup(keys: Int32Array, idx: Int32Array, target: number): string {
    let lo: number = 0;
    let hi: number = keys.length - 1;
    while (lo <= hi) {
      const mid: number = (lo + hi) >> 1;
      const value: number = keys[mid];
      if (value < target) lo = mid + 1;
      else if (value > target) hi = mid - 1;
      else return this.nameAt(idx[mid]);
    }
    return '';
  }

  private nameAt(index: number): string {
    if (index < 0 || index + 1 >= this.nameOff.length) return '';
    const start: number = this.nameStart + this.nameOff[index];
    const end: number = this.nameStart + this.nameOff[index + 1];
    if (start < 0 || end > this.bytes.byteLength || end < start) return '';
    const slice: Uint8Array = this.bytes.subarray(start, end);
    let out: string = '';
    for (let position: number = 0; position < slice.length; position += 1) out += String.fromCharCode(slice[position]);
    return out;
  }
}

/** 一段索引：排序键 + 名称下标。 */
class IndexSection {
  public keys: Int32Array = new Int32Array(0);
  public idx: Int32Array = new Int32Array(0);
}