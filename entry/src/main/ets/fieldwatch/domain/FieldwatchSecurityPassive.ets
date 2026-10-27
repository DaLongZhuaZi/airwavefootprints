/**
 * 安防被动层的可疑设备判定（P3-1 第 3 项）。纯逻辑 + 可单测。
 *
 * **只做被动层**：只看已经收到的广播（SSID / BLE 名 / 厂商 / service data / 特征库命中）。
 * 局域网主动探测（ARP 扫网段 / 端口探针 / ONVIF 探针）**未获用户批准**，
 * 本模块不含任何相关调用，也不提供入口 —— 见文档 3.2 与附录 B。
 *
 * 结论口径（文档 3.3，不可改）：只有三档
 *   · 确认  —— 多信号印证（≥2 条**独立**强证据）
 *   · 可疑  —— 单条强证据
 *   · 未发现 —— 本次无命中**不等于安全**，结果页必须配人工排查清单
 * 绝不出现「安全 / 已排除」这类措辞。
 */

import { RadioKind, SignatureClass, Sighting } from './FieldwatchModels';

/** 判定档位。 */
export enum SecurityVerdict {
  /** 多信号印证。 */
  CONFIRMED = 'confirmed',
  /** 单强信号。 */
  SUSPICIOUS = 'suspicious',
  /** 本次无命中。 */
  NONE = 'none'
}

/**
 * 证据类别。
 *
 * 分开枚举而不是只记一个字符串：档位判定要求「**独立**证据」——
 * 同一条规则在不同设备上重复命中不算多信号印证，只有不同类别的证据才算。
 */
export enum SecurityEvidenceKind {
  /** 厂商 OUI / companyId 命中已知摄像头厂商。 */
  VENDOR_OUI = 'vendor_oui',
  /** 设备名 / SSID / 主机名含摄像头特征词（ipcam / cam / nvr 等）。 */
  NAME_PATTERN = 'name_pattern',
  /** 视频/媒体服务宣告（service data 里出现 RTSP/ONVIF 类特征）。 */
  MEDIA_SERVICE = 'media_service',
  /** 特征库命中「疑似摄像头」类 fleet。 */
  SIGNATURE = 'signature'
}

/** 一条证据。 */
export class SecurityEvidence {
  public kind: SecurityEvidenceKind;
  /** 证据说明键（UI 翻成文案），如 'vendor_hikvision'。 */
  public detailKey: string;
  constructor(kind: SecurityEvidenceKind = SecurityEvidenceKind.SIGNATURE, detailKey: string = '') {
    this.kind = kind;
    this.detailKey = detailKey;
  }
}

/** 一台可疑设备。 */
export class SuspectDevice {
  public key: string = '';
  public label: string = '';
  public address: string = '';
  public kind: RadioKind = RadioKind.BLE;
  public verdict: SecurityVerdict = SecurityVerdict.NONE;
  public evidence: SecurityEvidence[] = [];
  public firstSeen: number = 0;
  public lastSeen: number = 0;
  public rssi: number = -127;
  constructor() {}
  /** 命中的独立证据类别数（用于「多信号印证」判定与 UI 展示）。 */
  distinctKinds(): number {
    const kinds: string[] = [];
    this.evidence.forEach((item: SecurityEvidence): void => {
      if (kinds.indexOf(String(item.kind)) < 0) kinds.push(String(item.kind));
    });
    return kinds.length;
  }
}

/**
 * 判定档位：**独立证据类别 ≥2 → 确认，1 → 可疑，0 → 未发现**。
 *
 * 为什么按「独立类别」而不是按「证据条数」：
 * 一台设备可能同时命中 3 条名称规则（IPCAM / cam / nvr），那仍然只是「名字像摄像头」
 * 这一件事；把它算成多信号印证会系统性地高估置信度。
 */
export function verdictOf(evidence: SecurityEvidence[]): SecurityVerdict {
  const kinds: string[] = [];
  evidence.forEach((item: SecurityEvidence): void => {
    if (kinds.indexOf(String(item.kind)) < 0) kinds.push(String(item.kind));
  });
  if (kinds.length >= 2) return SecurityVerdict.CONFIRMED;
  if (kinds.length === 1) return SecurityVerdict.SUSPICIOUS;
  return SecurityVerdict.NONE;
}

/**
 * 名称特征词表（SSID / 广播名 / 主机名共用）。
 *
 * 全部小写比较。**刻意保守**：`cam` 单独一个词会误伤 `Camry`（丰田车型）这类名字，
 * 所以用「词边界包含」而不是裸子串匹配 —— 见 `nameLooksLikeCamera`。
 */
export const CAMERA_NAME_TOKENS: string[] = [
  'ipcam', 'ip_cam', 'ip-cam', 'ipcamera', 'ip_camera', 'ip-camera',
  'ipc-', 'nvr', 'dvr', 'webcam', 'netcam', 'eyecam',
  'foscam', 'vstarcam', 'reolink', 'wyzecam', 'blinkcam'
];

/**
 * **专用摄像头厂商**的 OUI（强信号：命中即为「可疑」）。
 *
 * 判据：这些厂商**只做**安防/摄像头产品（海康、大华、Axis、Reolink…），
 * 一台设备的前 6 位落在这里，基本可以确定是摄像头。
 */
export const CAMERA_OUI_PREFIXES: string[] = [
  'B0:C5:54', // Hikvision
  '4C:BD:8F', // Hikvision
  'C0:56:E3', // Hikvision
  'BC:AD:28', // Hikvision
  '3C:EF:8C', // Dahua
  '90:02:A9', // Dahua
  'E0:50:8B', // Dahua
  '00:1A:07', // Axis
  'AC:CC:8E', // Axis
  'EC:71:DB', // Reolink
  'B0:BE:76', // Wyze
  'D0:3F:27', // Wyze
  '54:E0:19', // Ring
  '0C:47:C9', // Ring
  '18:B4:30', // Nest
  '64:16:66', // Nest
  '50:C7:BF', // TP-Link（也做路由，但摄像头产品线占比高，保留为强信号）
  'F4:F2:6D', // TP-Link
  '78:8A:20', // Ubiquiti
  '74:AC:B9', // Ubiquiti
  '5C:AA:FD', // Sonoff/Wyze
];

/**
 * **通用芯片/方案商**的 OUI（弱信号，只能辅助）。
 *
 * 真机实测教训：把这些放进强信号表后，一次扫描报出 6 台「可疑」，
 * 全部只是因为在用 Espressif / Tuya 芯片 —— 而这两家的芯片同样被用在插座、灯、
 * 体重秤上，绝大多数不是摄像头。把它们当强信号等于把误报当功能。
 *
 * 现在它们**只做辅助**：必须已有另一类证据时才并入，单凭自己不产生任何结论。
 */
export const CAMERA_CHIPSET_OUI_PREFIXES: string[] = [
  'A0:02:DC', '24:0A:C4', '30:AE:A4', '3C:71:BF', '80:64:6F', 'CC:50:E3',
  '54:5A:A6', '4C:EB:D6', 'A4:CF:12', '7C:9E:BD', '8C:4F:00', 'C4:4F:33',
  'DC:4F:22', 'E8:68:E7', 'F0:08:D1', '24:62:AB', '84:F3:EB', 'A0:20:A6',
  '00:12:16', '38:AF:29',
  'B4:5D:50', 'D8:F1:5B', '10:D5:61', '18:69:D8'
];

/** 已知摄像头厂商的 BLE companyId（仅收录明确对应摄像头/安防的）。 */
export const CAMERA_COMPANY_IDS: number[] = [
  0x0075, // Samsung (SmartThings/built-in cam 生态)
  0x0157, // Wyze
  0x027D, // Tuya
  0x0A0C, // Xiaomi 生态
];

/**
 * 名称是否像摄像头。
 *
 * 规则：命中词表里的任一词（子串匹配，但词都是**足够长且有区分度**的形态），
 * 或者用词边界匹配裸 `cam`（避免 Camry / camp 之类误伤）。
 */
export function nameLooksLikeCamera(name: string): boolean {
  const lower: string = name.trim().toLowerCase();
  if (lower.length === 0) return false;
  for (let i: number = 0; i < CAMERA_NAME_TOKENS.length; i += 1) {
    if (lower.indexOf(CAMERA_NAME_TOKENS[i]) >= 0) return true;
  }
  // 裸 `cam`：要求是独立词（前后是非字母数字），否则 `camry` 会被误判。
  const bare: RegExp = /(^|[^a-z0-9])cam([^a-z0-9]|$)/;
  return bare.test(lower);
}

/**
 * 地址是否是**随机（本地管理）地址**。
 *
 * 判据：第一个字节的 bit1（0x02）为 1 —— 蓝牙与 Wi-Fi 的随机地址都用这一位标记「本地管理」。
 *
 * **真机教训**：初版把所有地址都拿去查 OUI，结果一次扫描报出 15 台「可疑」，
 * 全部是随机 MAC 恰好落在某厂商 OUI 段里。随机地址是系统现编的，
 * 它的前 6 位与厂商毫无关系 —— 拿它查 OUI 等于掷骰子。
 */
export function isRandomizedAddress(address: string): boolean {
  const hex: string = address.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
  if (hex.length < 2) return false;
  const firstByte: number = parseInt(hex.substring(0, 2), 16);
  if (isNaN(firstByte)) return false;
  return (firstByte & 0x02) !== 0;
}

/**
 * 地址前 6 位（OUI）是否命中摄像头厂商表。
 *
 * **随机地址直接返回 false**：见 `isRandomizedAddress` 的说明。
 */
export function ouiLooksLikeCamera(address: string): boolean {
  if (isRandomizedAddress(address)) return false;
  const hex: string = address.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
  if (hex.length < 6) return false;
  const oui: string = hex.substring(0, 2) + ':' + hex.substring(2, 4) + ':' + hex.substring(4, 6);
  return CAMERA_OUI_PREFIXES.indexOf(oui) >= 0;
}

/** companyId 是否在已知摄像头厂商列表里。 */
export function companyIdLooksLikeCamera(companyId: number): boolean {
  return CAMERA_COMPANY_IDS.indexOf(companyId) >= 0;
}

/** 地址前 6 位是否属于通用芯片/方案商（弱信号，只能辅助）。 */
export function ouiLooksLikeChipset(address: string): boolean {
  // 同理：随机地址的 OUI 段毫无意义。
  if (isRandomizedAddress(address)) return false;
  const hex: string = address.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
  if (hex.length < 6) return false;
  const oui: string = hex.substring(0, 2) + ':' + hex.substring(2, 4) + ':' + hex.substring(4, 6);
  return CAMERA_CHIPSET_OUI_PREFIXES.indexOf(oui) >= 0;
}

/**
 * 对一台设备做被动层判定。
 *
 * @param sighting     观测
 * @param signatureHit 是否命中「疑似摄像头」类特征库条目（由调用方查库得出）
 * @param mediaService 广播里是否宣告了视频/媒体类服务（由调用方判定）
 */
export function assessSighting(sighting: Sighting, signatureHit: boolean, mediaService: boolean): SuspectDevice {
  const suspect: SuspectDevice = new SuspectDevice();
  suspect.key = sighting.key;
  suspect.address = sighting.address;
  suspect.kind = sighting.kind;
  suspect.label = sighting.name;
  suspect.firstSeen = sighting.firstSeen;
  suspect.lastSeen = sighting.lastSeen;
  suspect.rssi = sighting.rssi;
  const evidence: SecurityEvidence[] = [];
  // ① 厂商：**专用摄像头厂商**的 OUI / companyId 才算强证据（同一类别，不重复计）。
  if (ouiLooksLikeCamera(sighting.address)) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.VENDOR_OUI, 'oui'));
  } else if (companyIdLooksLikeCamera(sighting.facts.manufacturerId)) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.VENDOR_OUI, 'company_id'));
  }
  // 通用芯片方案商单独命中**不产生结论**（真机上它们会命中大量插座/灯/体重秤）。
  const chipOnly: boolean = ouiLooksLikeChipset(sighting.address)
    && !ouiLooksLikeCamera(sighting.address)
    && !companyIdLooksLikeCamera(sighting.facts.manufacturerId);
  // ② 名称：SSID / 广播名。
  const displayName: string = sighting.kind === RadioKind.WIFI ? sighting.facts.ssid : sighting.name;
  if (nameLooksLikeCamera(displayName) || nameLooksLikeCamera(sighting.name)) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.NAME_PATTERN, 'name'));
  }
  // ③ 特征库命中。
  if (signatureHit) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.SIGNATURE, 'catalog'));
  }
  // ④ 媒体服务宣告。
  if (mediaService) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.MEDIA_SERVICE, 'service'));
  }
  // ⑤ 通用芯片方案商：**只能在已有其他证据时作为辅助**，单独命中不构成可疑。
  if (chipOnly && evidence.length > 0) {
    evidence.push(new SecurityEvidence(SecurityEvidenceKind.VENDOR_OUI, 'chipset'));
  }
  suspect.evidence = evidence;
  suspect.verdict = verdictOf(evidence);
  return suspect;
}

/** 只保留需要展示的（可疑 / 确认），按档位再按证据数降序。 */
export function suspectListOf(assessed: SuspectDevice[]): SuspectDevice[] {
  const out: SuspectDevice[] = [];
  assessed.forEach((item: SuspectDevice): void => {
    if (item.verdict === SecurityVerdict.NONE) return;
    out.push(item);
  });
  out.sort((a: SuspectDevice, b: SuspectDevice): number => {
    const rankA: number = a.verdict === SecurityVerdict.CONFIRMED ? 2 : 1;
    const rankB: number = b.verdict === SecurityVerdict.CONFIRMED ? 2 : 1;
    if (rankA !== rankB) return rankB - rankA;
    return b.distinctKinds() - a.distinctKinds();
  });
  return out;
}

/** 统计：确认数 / 可疑数。 */
export function countVerdicts(list: SuspectDevice[]): number[] {
  let confirmed: number = 0;
  let suspicious: number = 0;
  list.forEach((item: SuspectDevice): void => {
    if (item.verdict === SecurityVerdict.CONFIRMED) confirmed += 1;
    else if (item.verdict === SecurityVerdict.SUSPICIOUS) suspicious += 1;
  });
  return [confirmed, suspicious];
}

/**
 * 能力边界（文档 3.3 强制要求写进结果页）。
 *
 * 返回**资源键数组**而不是文案：i18n 走统一入口，且便于单测断言条数。
 */
export function capabilityBoundaryKeys(): string[] {
  return [
    'app.string.fieldwatch_security_limit_local_only',
    'app.string.fieldwatch_security_limit_powered_off',
    'app.string.fieldwatch_security_limit_client_isolation',
    'app.string.fieldwatch_security_limit_gsm'
];
}
