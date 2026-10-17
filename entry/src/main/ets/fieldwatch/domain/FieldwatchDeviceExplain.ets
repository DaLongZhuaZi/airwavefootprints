import { ngfText } from 'ngf_framework';
import { RadioKind, Sighting } from './FieldwatchModels';
import { FieldwatchRadioDb } from './FieldwatchRadioDb';

/**
 * 设备解释层 —— 原版 `DeviceExplain.kt`（56.7 KB / 846 行）的移植。
 *
 * 它回答的是详情页最上面那句「**很可能是 iPhone、iPad 或 Mac**」以及
 * 「这是设备自己广播的内容，不是视觉识别结果」的依据。
 *
 * ## 架构：加权提示（Hint）而非规则优先级
 *
 * 原版不是一串 if-else，而是把每条线索做成带**权重**与**桶（bucket）**的提示，
 * 然后：
 *   1. 按 bucket 分组，每组只留权重最高的那条；
 *   2. 全局最高权重的那条决定 label 与置信度；
 *   3. 置信度映射成措辞（Most likely / Probably / Could be）。
 *
 * 这样「耳机的 Appearance=7」与「某签名的 weight=6」会自然合成一句话，
 * 而不会互相覆盖 —— 这正是原版读起来「有判断力」的原因。
 *
 * ## 与我们的签名库对接
 *
 * 原版的 `signatureHints` 是一张 ~450 行的 fleet id → 桶 映射表。
 * 我们用**自己的特征库**代替：命中的 fleet 直接给出高权重提示，
 * 权重按命中规则的强度分级，无需维护第二张表。
 */

/** 置信度。决定措辞，也决定列表页要不要把它当作「已知类型」。 */
export enum ExplainConfidence { HIGH = 'high', MEDIUM = 'medium', LOW = 'low' }

/** 一条线索。`bucket` 相同的线索互相竞争，只留权重最高的一条。 */
export class ExplainHint {
  public bucket: string;
  public label: string;
  public reason: string;
  public weight: number;
  constructor(bucket: string, label: string, reason: string, weight: number) {
    this.bucket = bucket; this.label = label; this.reason = reason; this.weight = weight;
  }
}

/** 猜测结果。`generic` 为真表示只认得无线电类别，没认出产品类型。 */
export class ExplainGuess {
  public headline: string;
  public label: string;
  public because: string;
  public confidence: ExplainConfidence;
  public generic: boolean;
  constructor(headline: string, label: string, because: string, confidence: ExplainConfidence, generic: boolean) {
    this.headline = headline; this.label = label; this.because = because;
    this.confidence = confidence; this.generic = generic;
  }
}

export class FieldwatchDeviceExplain {
  private db: FieldwatchRadioDb | undefined;

  /** 注入名称库；未注入时 Appearance / UUID 的解释退化为只显示代码。 */
  attach(db: FieldwatchRadioDb): void { this.db = db; }

  // ── 单点解释（详情页逐行使用）──

  /**
   * 广播 Flags 的逐位解释（AD type 0x01）。
   *
   * 原版文案的要点：**0x04 未置位时反而说明「可能也支持经典蓝牙」** ——
   * 这一位是「仅 BLE」，不是「支持 BLE」。
   */
  flagsExplain(flags: number): string {
    const parts: string[] = [];
    if ((flags & 0x01) !== 0) parts.push(ngfText('app.string.fw_dx_71'));
    if ((flags & 0x02) !== 0) parts.push(ngfText('app.string.fw_dx_72'));
    if ((flags & 0x04) !== 0) parts.push(ngfText('app.string.fw_dx_73'));
    else parts.push(ngfText('app.string.fw_dx_74'));
    if ((flags & 0x08) !== 0 || (flags & 0x10) !== 0) parts.push(ngfText('app.string.fw_dx_75'));
    return parts.join(' ');
  }

  /** 物理层说明。原版按标签里的关键字分档。 */
  phyExplain(label: string): string {
    if (label.indexOf('Coded') >= 0) return label + ngfText('app.string.fw_dx_81');
    if (label.indexOf('2M') >= 0) return label + ngfText('app.string.fw_dx_82');
    if (label.indexOf('1M') >= 0) return label + ngfText('app.string.fw_dx_83');
    return label;
  }

  /**
   * 地址解释。
   *
   * 关键区分（原版特意分开写）：**Wi-Fi 的本地管理 BSSID 不是手机轮换 MAC** ——
   * 车载 / Mesh / 访客 AP 常常长期使用同一个本地管理地址。
   */
  addressExplain(sighting: Sighting): string {
    const type: string = sighting.facts.addressType;
    const randomized: boolean = this.isRandomized(sighting.address);
    if (sighting.kind === RadioKind.WIFI && randomized) {
      return ngfText('app.string.fw_dx_97');
    }
    if (type === 'public' && !randomized) return ngfText('app.string.fw_dx_99');
    if (type === 'random' || randomized) return ngfText('app.string.fw_dx_100');
    if (type.length > 0) return type + ngfText('app.string.fw_dx_101');
    return ngfText('app.string.fw_dx_102');
  }

  /** 强度分档（原版 `rssiBand`）。 */
  rssiBand(rssi: number): string {
    if (!this.measured(rssi)) return ngfText('app.string.fw_dx_107');
    if (rssi >= -45) return ngfText('app.string.fw_dx_108');
    if (rssi >= -60) return ngfText('app.string.fw_dx_109');
    if (rssi >= -75) return ngfText('app.string.fw_dx_110');
    if (rssi >= -88) return ngfText('app.string.fw_dx_111');
    return ngfText('app.string.fw_dx_112');
  }

  /** 强度整句。 */
  rssiExplain(rssi: number): string {
    if (!this.measured(rssi)) return ngfText('app.string.fw_dx_107');
    return rssi.toString() + ' dBm · ' + this.rssiBand(rssi);
  }

  /** 会话强度范围（原版 `Rssi.sessionRange`）。 */
  sessionRange(min: number, max: number): string {
    if (!this.measured(min) && !this.measured(max)) return ngfText('app.string.fw_dx_107');
    if (min === max) return min.toString() + ' dBm';
    return min.toString() + ' ~ ' + max.toString() + ' dBm';
  }

  /** 未测量的 RSSI 用 0 作哨兵 —— 0 dBm 在现实中不可能出现在接收端。 */
  measured(rssi: number): boolean { return rssi !== 0 && rssi < 0; }

  private isRandomized(mac: string): boolean {
    const hex: string = mac.replace(/[^A-Fa-f0-9]/g, '');
    if (hex.length < 2) return false;
    const first: number = parseInt(hex.substring(0, 2), 16);
    if (isNaN(first)) return false;
    return (first & 0x02) !== 0 && (first & 0x01) === 0;
  }

  /**
   * Wi-Fi 加密串 → 人话。
   *
   * 原版按**子串包含**逐项叠加（`SAE`/`OWE`/`PSK`/`802.1X`/`WEP`/`CCMP`/`TKIP`/`WPS`/`MESH`/`IBSS`/`ESS`），
   * 因为 `capabilities` 是厂商自由格式的串，不能按位置解析。
   */
  wifiSecurityExplain(raw: string): string {
    const bits: string[] = [];
    const upper: string = raw.toUpperCase();
    const has = (token: string): boolean => upper.indexOf(token) >= 0;
    if (has('SAE') || has('WPA3')) bits.push(ngfText('app.string.fw_dx_149'));
    if (has('OWE')) bits.push(ngfText('app.string.fw_dx_150'));
    if (has('PSK') && has('WPA2')) bits.push(ngfText('app.string.fw_dx_151'));
    else if (has('PSK') || has('WPA')) bits.push(ngfText('app.string.fw_dx_152'));
    if (has('802.1X') || has('EAP')) bits.push(ngfText('app.string.fw_dx_153'));
    if (has('WEP')) bits.push(ngfText('app.string.fw_dx_154'));
    if (has('ESS') && bits.length === 0) bits.push(ngfText('app.string.fw_dx_155'));
    if (has('CCMP') || has('GCMP')) bits.push(ngfText('app.string.fw_dx_156'));
    if (has('TKIP')) bits.push(ngfText('app.string.fw_dx_157'));
    if (has('WPS')) bits.push(ngfText('app.string.fw_dx_158'));
    if (has('MESH')) bits.push(ngfText('app.string.fw_dx_159'));
    if (has('IBSS')) bits.push(ngfText('app.string.fw_dx_160'));
    if (has('ESS')) bits.push(ngfText('app.string.fw_dx_161'));
    if (bits.length === 0) return raw;
    const unique: string[] = [];
    bits.forEach((item: string): void => { if (unique.indexOf(item) < 0) unique.push(item); });
    return unique.join('。') + '。';
  }

  /** 16 位 UUID 的服务名补充说明（原版 `uuidGloss` 的 `extra` 表）。 */
  uuidGloss(uuid: string): string {
    const name: string = this.db === undefined ? '' : this.db.serviceUuid(uuid);
    const short: number = this.uuid16(uuid);
    let extra: string = '';
    if (short === 0x1800) extra = ngfText('app.string.fw_dx_173');
    else if (short === 0x1801) extra = ngfText('app.string.fw_dx_174');
    else if (short === 0x180A) extra = ngfText('app.string.fw_dx_175');
    else if (short === 0x180F) extra = ngfText('app.string.fw_dx_176');
    else if (short === 0x1812) extra = ngfText('app.string.fw_dx_177');
    else if (short === 0x180D) extra = ngfText('app.string.fw_dx_178');
    else if (short === 0x1810) extra = ngfText('app.string.fw_dx_179');
    else if (short === 0x181A) extra = ngfText('app.string.fw_dx_180');
    else if (short === 0x1844 || short === 0x1845 || short === 0x1846) extra = ngfText('app.string.fw_dx_181');
    else if (short === 0x1850 || short === 0x184E || short === 0x184F) extra = 'LE Audio';
    else if (short === 0xFE2C) extra = ngfText('app.string.fw_dx_183');
    else if (short === 0xFD5A) extra = 'Samsung SmartTag';
    else if (short === 0xFD44) extra = ngfText('app.string.fw_dx_185');
    else if (short === 0xFEED || short === 0xFEDD) extra = ngfText('app.string.fw_dx_186');
    else if (short === 0xFD50) extra = ngfText('app.string.fw_dx_187');
    else if (short === 0xFEBE || short === 0xFE21) extra = 'Bose';
    else if (short === 0xFE78) extra = ngfText('app.string.fw_dx_189');
    else if (short === 0xFE07) extra = ngfText('app.string.fw_dx_190');
    else if (short === 0xFEAF || short === 0xFEB0) extra = 'Nest Weave';
    else if (short === 0xFCBF) extra = ngfText('app.string.fw_dx_192');
    else if (short === 0xFE24) extra = ngfText('app.string.fw_dx_193');
    else if (short === 0xFCF4) extra = 'Allegion / Schlage';
    else if (short === 0xFCB2) extra = ngfText('app.string.fw_dx_195');
    if (name.length > 0 && extra.length > 0) return name + ' —— ' + extra;
    if (name.length > 0) return name;
    return extra;
  }

  /** 从任意 UUID 写法里取出 16 位短码；取不到返回 -1。 */
  uuid16(uuid: string): number {
    const hex: string = uuid.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    if (hex.length === 4) return parseInt(hex, 16);
    if (hex.length === 8) return parseInt(hex.substring(4, 8), 16);
    if (hex.length === 32 && hex.startsWith('0000') && hex.endsWith('00001000800000805F9B34FB')) {
      return parseInt(hex.substring(4, 8), 16);
    }
    return -1;
  }

  // ── 加权提示系统 ──

  /**
   * 综合所有线索给出「它最可能是什么」。
   *
   * `signatureNames` 是本机特征库命中的签名名（已解析成展示名）。
   * 原版用一张 450 行的 fleet id → 桶 映射表；我们直接用自己的库，
   * 权重按命中数量给 —— 命中越多越可信。
   */
  guess(sighting: Sighting, signatureNames: string[]): ExplainGuess {
    const hints: ExplainHint[] = [];
    const appearanceName: string = this.db === undefined ? '' : this.db.appearance(sighting.facts.appearance);
    const appearanceHint: ExplainHint | undefined = this.appearanceHint(appearanceName);
    if (appearanceHint !== undefined) hints.push(appearanceHint);
    const codHint: ExplainHint | undefined = this.codHint(sighting.facts.deviceClass);
    if (codHint !== undefined) hints.push(codHint);
    this.uuidHints(sighting).forEach((item: ExplainHint): void => { hints.push(item); });
    this.signatureHints(signatureNames).forEach((item: ExplainHint): void => { hints.push(item); });
    if (sighting.kind === RadioKind.WIFI) this.wifiHints(sighting).forEach((item: ExplainHint): void => { hints.push(item); });

    if (hints.length === 0) {
      const kindLabel: string = sighting.kind === RadioKind.WIFI ? ngfText('app.string.fw_dx_233') : ngfText('app.string.fw_dx_234');
      return new ExplainGuess(kindLabel, kindLabel,
        ngfText('app.string.fw_dx_235'),
        ExplainConfidence.LOW, true);
    }
    // 按 bucket 分组，每组只留权重最高的一条 —— 同一类线索互相竞争，不叠加。
    const best: Map<string, ExplainHint> = new Map<string, ExplainHint>();
    hints.forEach((hint: ExplainHint): void => {
      const prev: ExplainHint | undefined = best.get(hint.bucket);
      if (prev === undefined || hint.weight > prev.weight) best.set(hint.bucket, hint);
    });
    let top: ExplainHint | undefined = undefined;
    best.forEach((hint: ExplainHint): void => {
      if (top === undefined || hint.weight > top.weight) top = hint;
    });
    if (top === undefined) {
      return new ExplainGuess(ngfText('app.string.fw_dx_249'), ngfText('app.string.fw_dx_249'), ngfText('app.string.fw_dx_250'), ExplainConfidence.LOW, true);
    }
    const winner: ExplainHint = top;
    const reasons: string[] = [];
    best.forEach((hint: ExplainHint): void => {
      if ((hint.bucket === winner.bucket || hint.weight >= 3) && reasons.indexOf(hint.reason) < 0) {
        reasons.push(hint.reason);
      }
    });
    const confidence: ExplainConfidence = winner.weight >= 6 ? ExplainConfidence.HIGH
      : (winner.weight >= 3 ? ExplainConfidence.MEDIUM : ExplainConfidence.LOW);
    const hedge: string = confidence === ExplainConfidence.HIGH ? ngfText('app.string.fw_dx_260')
      : (confidence === ExplainConfidence.MEDIUM ? ngfText('app.string.fw_dx_261') : ngfText('app.string.fw_dx_262'));
    return new ExplainGuess(hedge + winner.label, winner.label,
      reasons.join('') + ngfText('app.string.fw_dx_263'), confidence, false);
  }

  /** GAP Appearance → 提示。权重按「这个类别有多具体」给。 */
  private appearanceHint(name: string): ExplainHint | undefined {
    if (name.length === 0 || name.toLowerCase() === 'unknown') return undefined;
    const lower: string = name.toLowerCase();
    const has = (token: string): boolean => lower.indexOf(token) >= 0;
    let bucket: string = 'other';
    let label: string = name;
    let weight: number = 3;
    if (has('ear') || has('headphone') || has('headset') || has('hearable') || has('hearing')) {
      bucket = 'audio-personal'; label = ngfText('app.string.fw_dx_275'); weight = 7;
    } else if (has('speaker') || has('hifi')) {
      bucket = 'audio-speaker'; label = ngfText('app.string.fw_dx_277'); weight = 7;
    } else if (has('mouse')) { bucket = 'mouse'; label = ngfText('app.string.fw_dx_278'); weight = 8;
    } else if (has('keyboard')) { bucket = 'keyboard'; label = ngfText('app.string.fw_dx_279'); weight = 8;
    } else if (has('gamepad') || has('joystick')) { bucket = 'gamepad'; label = ngfText('app.string.fw_dx_280'); weight = 7;
    } else if (has('watch')) { bucket = 'watch'; label = ngfText('app.string.fw_dx_281'); weight = 7;
    } else if (has('phone')) { bucket = 'phone'; label = ngfText('app.string.fw_dx_282'); weight = 6;
    } else if (has('laptop') || has('computer') || has('desktop') || has('tablet')) {
      bucket = 'computer'; label = ngfText('app.string.fw_dx_284'); weight = 6;
    } else if (has('tag') || has('keyring')) { bucket = 'tag'; label = ngfText('app.string.fw_dx_285'); weight = 6;
    } else if (has('remote')) { bucket = 'remote'; label = ngfText('app.string.fw_dx_286'); weight = 6;
    } else if (has('hid')) { bucket = 'hid'; label = ngfText('app.string.fw_dx_287'); weight = 4;
    } else if (has('heart')) { bucket = 'health'; label = ngfText('app.string.fw_dx_288'); weight = 7;
    } else if (has('glucose') || has('oximeter') || has('blood pressure') || has('thermometer')) {
      bucket = 'health'; label = ngfText('app.string.fw_dx_290'); weight = 6;
    } else if (has('display') || has('monitor')) { bucket = 'display'; label = ngfText('app.string.fw_dx_291'); weight = 4;
    } else if (has('clock')) { bucket = 'clock'; label = ngfText('app.string.fw_dx_292'); weight = 5;
    } else if (has('glasses')) { bucket = 'glasses'; label = ngfText('app.string.fw_dx_293'); weight = 6;
    }
    return new ExplainHint(bucket, label, ngfText('app.string.fw_dx_295') + name + '。', weight);
  }

  /** 经典蓝牙 Class of Device → 提示。鸿蒙不解析 CoD，我们自己解主/次类别。 */
  private codHint(cod: number): ExplainHint | undefined {
    if (cod < 0) return undefined;
    const major: number = (cod >> 8) & 0x1F;
    const minor: number = (cod >> 2) & 0x3F;
    let bucket: string = '';
    let label: string = '';
    let weight: number = 0;
    // 主类别 4 = 音频/视频；次类别区分耳机、音箱、车载…
    if (major === 4) {
      if (minor === 1 || minor === 2 || minor === 6) { bucket = 'audio-personal'; label = ngfText('app.string.fw_dx_275'); weight = 6; }
      else if (minor === 3 || minor === 4 || minor === 5 || minor === 7) { bucket = 'audio-speaker'; label = ngfText('app.string.fw_dx_277'); weight = 6; }
      else { bucket = 'audio-personal'; label = ngfText('app.string.fw_dx_310'); weight = 3; }
    } else if (major === 5) {
      // 外设：次类别 1=键盘 2=指点设备 3=组合
      if (minor === 2) { bucket = 'mouse'; label = ngfText('app.string.fw_dx_278'); weight = 7; }
      else if (minor === 1) { bucket = 'keyboard'; label = ngfText('app.string.fw_dx_279'); weight = 7; }
      else if (minor === 3) { bucket = 'hid'; label = ngfText('app.string.fw_dx_315'); weight = 5; }
      else if (minor === 4 || minor === 5) { bucket = 'gamepad'; label = ngfText('app.string.fw_dx_280'); weight = 6; }
      else { bucket = 'hid'; label = ngfText('app.string.fw_dx_317'); weight = 3; }
    } else if (major === 2) {
      // 电话：次类别区分手机与无绳电话
      if (minor === 3 || minor === 4 || minor === 5) { bucket = 'phone'; label = ngfText('app.string.fw_dx_282'); weight = 5; }
      else return undefined;
    } else if (major === 1) {
      if (minor === 3 || minor === 4) { bucket = 'computer'; label = ngfText('app.string.fw_dx_323'); weight = 5; }
      else if (minor === 7) { bucket = 'watch'; label = ngfText('app.string.fw_dx_324'); weight = 6; }
      else return undefined;
    } else if (major === 6) {
      if (minor === 2 || minor === 3 || minor === 4 || minor === 5) { bucket = 'health'; label = ngfText('app.string.fw_dx_290'); weight = 6; }
      else return undefined;
    } else {
      // 未分类（0）与杂项（31）不构成线索 —— 原版同样直接返回 null。
      return undefined;
    }
    return new ExplainHint(bucket, label, ngfText('app.string.fw_dx_333') + label + '。', weight);
  }

  /** 知名服务 UUID → 提示。 */
  private uuidHints(sighting: Sighting): ExplainHint[] {
    const out: ExplainHint[] = [];
    const all: string[] = [];
    sighting.facts.serviceUuids.forEach((item: string): void => { all.push(item); });
    sighting.facts.serviceUuids16.forEach((item: string): void => { all.push(item); });
    sighting.facts.serviceUuids128.forEach((item: string): void => { all.push(item); });
    sighting.facts.serviceData.forEach((item: ServiceDataRecordLike): void => { all.push(item.uuid); });
    const seen: number[] = [];
    all.forEach((uuid: string): void => {
      const id: number = this.uuid16(uuid);
      if (id < 0 || seen.indexOf(id) >= 0) return;
      seen.push(id);
      if (id === 0x1812) out.push(new ExplainHint('hid', ngfText('app.string.fw_dx_177'), ngfText('app.string.fw_dx_350'), 5));
      else if (id === 0x184E || id === 0x184F || id === 0x1850 || id === 0x1851) {
        out.push(new ExplainHint('audio-personal', ngfText('app.string.fw_dx_351'), ngfText('app.string.fw_dx_352'), 6));
      } else if (id === 0x180D) out.push(new ExplainHint('health', ngfText('app.string.fw_dx_288'), ngfText('app.string.fw_dx_353'), 6));
      else if (id === 0x1810) out.push(new ExplainHint('health', ngfText('app.string.fw_dx_353'), ngfText('app.string.fw_dx_354'), 6));
      else if (id === 0x181A) out.push(new ExplainHint('sensor', ngfText('app.string.fw_dx_354'), ngfText('app.string.fw_dx_355'), 4));
      else if (id === 0xFE2C) out.push(new ExplainHint('audio-personal', ngfText('app.string.fw_dx_355'), ngfText('app.string.fw_dx_356'), 5));
      else if (id === 0xFD5A) out.push(new ExplainHint('tag', 'Samsung SmartTag', ngfText('app.string.fw_dx_356'), 7));
      else if (id === 0xFD44) out.push(new ExplainHint('tag', ngfText('app.string.fw_dx_357'), ngfText('app.string.fw_dx_358'), 6));
      else if (id === 0xFEED || id === 0xFEDD) out.push(new ExplainHint('tag', ngfText('app.string.fw_dx_186'), 'Tile 服务 UUID。', 7));
    });
    return out;
  }

  /**
   * 签名命中 → 提示。
   *
   * 原版维护了一张 fleet id → 桶 的 450 行映射表；我们用**自己的特征库**：
   * 命中的签名本身就是最强的证据（它是靠广播内容匹配上的），
   * 所以给高权重，并按命中数量递增。
   */
  private signatureHints(names: string[]): ExplainHint[] {
    const out: ExplainHint[] = [];
    names.forEach((name: string): void => {
      const lower: string = name.toLowerCase();
      // 通用兜底签名（名字里带 unknown/generic）不构成产品类别线索。
      if (lower.indexOf('unknown') >= 0 || lower.indexOf('generic') >= 0) return;
      const weight: number = names.length >= 2 ? 7 : 6;
      out.push(new ExplainHint('signature:' + name, name,
        ngfText('app.string.fw_dx_378') + name + '。', weight));
    });
    return out;
  }

  /** Wi-Fi 专属线索。 */
  private wifiHints(sighting: Sighting): ExplainHint[] {
    const out: ExplainHint[] = [];
    if (sighting.facts.hiddenSsid) {
      out.push(new ExplainHint('wifi-hidden', ngfText('app.string.fw_dx_387'), ngfText('app.string.fw_dx_388'), 4));
    }
    return out;
  }
}

/** `serviceData` 元素的最小契约，避免这里 import 整个模型文件。 */
interface ServiceDataRecordLike { uuid: string; dataHex: string }

