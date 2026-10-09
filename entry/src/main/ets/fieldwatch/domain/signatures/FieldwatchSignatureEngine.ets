import { DecodedFieldValue, RadioFacts, RadioKind, ScanObservation, ServiceDataRecord, Sighting, SignatureClass } from '../FieldwatchModels';
import {
  SIGNATURE_WIFI_PROTOCOL_IE_OUIS, SignatureDecodeEndian, SignatureDecodeField, SignatureDecodeSource,
  SignatureDecodeType, SignatureDecodeWhen, SignatureDecodeWhenOp, SignatureFleet, SignatureFleetDecode,
  SignatureRule, SignatureRuleKind, signatureHexOnly, signatureReverseHexBytes, signatureUuidAliases
} from './FieldwatchSignatureModels';

/** Tesla 手机钥匙用 Apple iBeacon 承载；命中该前缀时标签应是 Tesla 而不是 iBeacon。 */
const TESLA_IBEACON_MFG_PREFIX: string = '021574278BDAB64445208F0C720EAF059935';
/** Apple Continuity / 配对类型（不含 Offline Finding 0x12）：是手机/电脑/耳机，不是标签。 */
const APPLE_CONTINUITY_PREFIXES: string[] = ['05', '07', '08', '09', '0A', '0B', '0C', '0D', '0E', '0F', '10'];
const APPLE_COMPANY_ID: number = 0x004C;

const FLEET_IBEACON: string = 'fleet-ibeacon';
const FLEET_OSMO: string = 'fleet-osmo';
const FLEET_DJI: string = 'fleet-dji';
const FLEET_CISCO: string = 'fleet-cisco';
const FLEET_MERAKI: string = 'fleet-meraki';
const FLEET_AIRTAG: string = 'fleet-airtag';
const FLEET_APPLE_DEVICE: string = 'fleet-apple-device';
const FLEET_APPLE_AUDIO: string = 'fleet-apple-audio';

/** 一次匹配所需的设备事实快照，避免规则层直接依赖 Sighting。 */
export class SignatureMatchContext {
  public key: string = '';
  public kind: RadioKind = RadioKind.BLE;
  public address: string = '';
  public name: string = '';
  public ssid: string = '';
  public hiddenSsid: boolean = false;
  public manufacturerId: number = 0;
  public manufacturerDataHex: string = '';
  public serviceUuids: string[] = [];
  public serviceData: ServiceDataRecord[] = [];
  public vendorIeOuis: string[] = [];
  public lastSeen: number = 0;

  addressHex(): string { return signatureHexOnly(this.address); }
  oui(): string { const hex: string = this.addressHex(); return hex.length >= 6 ? hex.substring(0, 6) : hex; }
}

export function signatureContextOfObservation(observation: ScanObservation): SignatureMatchContext {
  const context: SignatureMatchContext = new SignatureMatchContext();
  context.key = observation.key;
  context.kind = observation.kind;
  context.address = observation.address;
  context.name = observation.name;
  context.ssid = observation.facts.ssid;
  context.hiddenSsid = observation.facts.hiddenSsid;
  context.manufacturerId = observation.facts.manufacturerId;
  context.manufacturerDataHex = observation.facts.manufacturerDataHex;
  context.serviceUuids = observation.facts.serviceUuids;
  context.serviceData = observation.facts.serviceData;
  context.vendorIeOuis = observation.facts.vendorIeOuis;
  context.lastSeen = observation.seenAt;
  return context;
}

export function signatureContextOfSighting(sighting: Sighting): SignatureMatchContext {
  const context: SignatureMatchContext = new SignatureMatchContext();
  context.key = sighting.key;
  context.kind = sighting.kind;
  context.address = sighting.address;
  context.name = sighting.name;
  context.ssid = sighting.facts.ssid;
  context.hiddenSsid = sighting.facts.hiddenSsid;
  context.manufacturerId = sighting.facts.manufacturerId;
  context.manufacturerDataHex = sighting.facts.manufacturerDataHex;
  context.serviceUuids = sighting.facts.serviceUuids;
  context.serviceData = sighting.facts.serviceData;
  context.vendorIeOuis = sighting.facts.vendorIeOuis;
  context.lastSeen = sighting.lastSeen;
  return context;
}

function escapeRegexChar(ch: string): string {
  const specials: string = '.+?^$()[]{}|\\';
  return specials.indexOf(ch) >= 0 ? '\\' + ch : ch;
}

function globToRegExp(pattern: string): RegExp {
  let body: string = '^';
  for (let index = 0; index < pattern.length; index += 1) {
    const ch: string = pattern.charAt(index);
    if (ch === '*') body += '.*';
    else if (ch === '?') body += '.';
    else body += escapeRegexChar(ch);
  }
  body += '$';
  return new RegExp(body, 'i');
}

function containsIgnoreCase(haystack: string, needle: string): boolean {
  if (needle.length === 0) return false;
  return haystack.toLowerCase().indexOf(needle.toLowerCase()) >= 0;
}

function matchesPrefix(address: string, prefix: string): boolean {
  const hex: string = signatureHexOnly(address);
  const want: string = signatureHexOnly(prefix);
  if (want.length === 0 || hex.length < want.length) return false;
  return hex.substring(0, want.length) === want;
}

function uuidHits(context: SignatureMatchContext, text: string): boolean {
  const want: string[] = signatureUuidAliases(text);
  if (want.length === 0) return false;
  for (let index = 0; index < context.serviceUuids.length; index += 1) {
    const aliases: string[] = signatureUuidAliases(context.serviceUuids[index]);
    for (let inner = 0; inner < aliases.length; inner += 1) if (want.indexOf(aliases[inner]) >= 0) return true;
  }
  for (let index = 0; index < context.serviceData.length; index += 1) {
    const aliases: string[] = signatureUuidAliases(context.serviceData[index].uuid);
    for (let inner = 0; inner < aliases.length; inner += 1) if (want.indexOf(aliases[inner]) >= 0) return true;
  }
  return false;
}

function vendorIeHitsOui(context: SignatureMatchContext, prefix: string): boolean {
  if (context.kind !== RadioKind.WIFI) return false;
  const want: string = signatureHexOnly(prefix);
  if (want.length === 0) return false;
  for (let index = 0; index < context.vendorIeOuis.length; index += 1) {
    const hex: string = signatureHexOnly(context.vendorIeOuis[index]);
    if (hex.length < 6) continue;
    if (SIGNATURE_WIFI_PROTOCOL_IE_OUIS.indexOf(hex.substring(0, 6)) >= 0) continue;
    if (hex.indexOf(want) === 0) return true;
  }
  return false;
}

/** 虚拟机 BSSID：guest/mesh 会在烧录 OUI 上置本地位，按还原后的 24 位 OUI 再试一次。 */
function recoveredWifiOuiHits(context: SignatureMatchContext, prefix: string): boolean {
  if (context.kind !== RadioKind.WIFI) return false;
  const hex: string = context.addressHex();
  if (hex.length < 6) return false;
  const firstByte: number = parseInt(hex.substring(0, 2), 16);
  if (Number.isNaN(firstByte) || (firstByte & 0x02) === 0) return false;
  const universal: string = ((firstByte & 0xFD) | 0x00).toString(16).toUpperCase().padStart(2, '0') + hex.substring(2, 6);
  const want: string = signatureHexOnly(prefix);
  return want.length === 6 && universal === want;
}

/**
 * 负载前缀匹配（支持偏移与长度约束）。
 *
 * `hex` 与 `prefix` 都是十六进制串，`offset` 以**字节**计，内部乘 2 转成字符下标。
 * `minLen`/`maxLen` 为 0 表示不约束；`maxLen` 只在非 0 时生效（`=` 的精确长度用 minLen = maxLen 表达）。
 */
function payloadPrefixHits(hex: string, prefix: string, offset: number, minLen: number, maxLen: number): boolean {
  const bytes: number = Math.floor(hex.length / 2);
  if (minLen > 0 && bytes < minLen) return false;
  if (maxLen > 0 && bytes > maxLen) return false;
  const at: number = offset * 2;
  if (at < 0 || at + prefix.length > hex.length) return false;
  return hex.substring(at, at + prefix.length) === prefix;
}

function serviceDataHits(context: SignatureMatchContext, aliases: string[], prefix: string, contains: boolean,
  offset: number = 0, minLen: number = 0, maxLen: number = 0): boolean {
  const needles: string[] = [];
  if (contains) {
    const reversed: string = signatureReverseHexBytes(prefix);
    needles.push(prefix);
    if (reversed.length > 0 && reversed !== prefix) needles.push(reversed);
  } else {
    needles.push(prefix);
  }
  for (let index = 0; index < context.serviceData.length; index += 1) {
    const record: ServiceDataRecord = context.serviceData[index];
    if (aliases.length > 0) {
      const recordAliases: string[] = signatureUuidAliases(record.uuid);
      let uuidOk: boolean = false;
      for (let inner = 0; inner < recordAliases.length; inner += 1) if (aliases.indexOf(recordAliases[inner]) >= 0) uuidOk = true;
      if (!uuidOk) continue;
    }
    const data: string = signatureHexOnly(record.dataHex);
    // 长度约束按字节算，且对 contains 与 offset 两种模式都生效。
    const bytes: number = Math.floor(data.length / 2);
    if (minLen > 0 && bytes < minLen) continue;
    if (maxLen > 0 && bytes > maxLen) continue;
    for (let needle = 0; needle < needles.length; needle += 1) {
      if (needles[needle].length === 0) continue;
      // contains 模式忽略偏移（语义就是「任意位置」）；否则按 offset 精确比对。
      if (contains) {
        if (data.indexOf(needles[needle]) >= 0) return true;
      } else if (payloadPrefixHits(data, needles[needle], offset, 0, 0)) {
        return true;
      }
    }
  }
  return false;
}

abstract class SignatureFastRule {
  public radio: RadioKind | undefined = undefined;
  constructor(radio: RadioKind | undefined) { this.radio = radio; }
  protected radioOk(context: SignatureMatchContext): boolean { return this.radio === undefined || context.kind === this.radio; }
  abstract hits(context: SignatureMatchContext): boolean;
}

class SignatureContainsRule extends SignatureFastRule {
  private readonly needle: string;
  constructor(needle: string, radio: RadioKind | undefined) { super(radio); this.needle = needle; }
  hits(context: SignatureMatchContext): boolean { return this.radioOk(context) && context.name.length > 0 && containsIgnoreCase(context.name, this.needle); }
}

class SignatureGlobRule extends SignatureFastRule {
  private readonly pattern: RegExp;
  constructor(pattern: RegExp, radio: RadioKind | undefined) { super(radio); this.pattern = pattern; }
  hits(context: SignatureMatchContext): boolean { return this.radioOk(context) && context.name.length > 0 && this.pattern.test(context.name); }
}

class SignatureUuidRule extends SignatureFastRule {
  private readonly aliases: string[];
  constructor(aliases: string[], radio: RadioKind | undefined) { super(radio); this.aliases = aliases; }
  hits(context: SignatureMatchContext): boolean { return this.radioOk(context) && uuidHits(context, this.aliases.length > 0 ? this.aliases[0] : ''); }
}

class SignatureManufacturerIdRule extends SignatureFastRule {
  private readonly companyId: number;
  constructor(companyId: number, radio: RadioKind | undefined) { super(radio); this.companyId = companyId; }
  hits(context: SignatureMatchContext): boolean { return this.radioOk(context) && context.manufacturerId === this.companyId; }
}

class SignatureManufacturerDataRule extends SignatureFastRule {
  private readonly companyId: number;
  private readonly prefix: string;
  private readonly offset: number;
  private readonly minLen: number;
  private readonly maxLen: number;
  constructor(companyId: number, prefix: string, radio: RadioKind | undefined,
    offset: number = 0, minLen: number = 0, maxLen: number = 0) {
    super(radio);
    this.companyId = companyId; this.prefix = prefix;
    this.offset = offset; this.minLen = minLen; this.maxLen = maxLen;
  }
  hits(context: SignatureMatchContext): boolean {
    if (!this.radioOk(context)) return false;
    if (this.prefix.length === 0) return false;
    if (this.companyId !== 0 && context.manufacturerId !== this.companyId) return false;
    // 数据已剥掉公司 ID 那 2 字节，offset 直接作用在剩余负载上。
    return payloadPrefixHits(signatureHexOnly(context.manufacturerDataHex), this.prefix, this.offset, this.minLen, this.maxLen);
  }
}

class SignatureServiceDataRule extends SignatureFastRule {
  private readonly aliases: string[];
  private readonly prefix: string;
  private readonly contains: boolean;
  private readonly offset: number;
  private readonly minLen: number;
  private readonly maxLen: number;
  constructor(aliases: string[], prefix: string, contains: boolean, radio: RadioKind | undefined,
    offset: number = 0, minLen: number = 0, maxLen: number = 0) {
    super(radio);
    this.aliases = aliases; this.prefix = prefix; this.contains = contains;
    this.offset = offset; this.minLen = minLen; this.maxLen = maxLen;
  }
  hits(context: SignatureMatchContext): boolean {
    return this.radioOk(context)
      && serviceDataHits(context, this.aliases, this.prefix, this.contains, this.offset, this.minLen, this.maxLen);
  }
}

class SignatureRadioRule extends SignatureFastRule {
  hits(context: SignatureMatchContext): boolean { return this.radio === undefined || context.kind === this.radio; }
}

class SignatureHiddenSsidRule extends SignatureFastRule {
  constructor() { super(RadioKind.WIFI); }
  hits(context: SignatureMatchContext): boolean { return context.hiddenSsid; }
}

class SignatureOuiRule {
  public hex: string = '';
  public radio: RadioKind | undefined = undefined;
  public bssid: boolean = true;
  public vendor: boolean = true;
  public planIndex: number = -1;
  constructor(hex: string, radio: RadioKind | undefined, bssid: boolean, vendor: boolean, planIndex: number) {
    this.hex = hex; this.radio = radio; this.bssid = bssid; this.vendor = vendor; this.planIndex = planIndex;
  }
}

class SignatureFleetPlan {
  public id: string = '';
  public fleet: SignatureFleet;
  public matchAny: boolean = true;
  public cluster: boolean = false;
  public rules: SignatureRule[] = [];
  public fastRules: SignatureFastRule[] = [];
  /**
   * 分组规则（`rule.group > 0`）：每组内 AND，组间 OR。
   *
   * **这些规则不进 `rules` / `fastRules`** —— 它们只作为额外的 OR 分支参与，
   * 这样 `matchAny` 那套基础语义完全不受影响（严格超集）。
   * 外层数组下标即组号顺序，内层是编译好的规则。
   */
  public groups: SignatureFastRule[][] = [];
  constructor(fleet: SignatureFleet) { this.fleet = fleet; this.id = fleet.id; }
}

class CompiledSignatureIndex {
  public plans: SignatureFleetPlan[] = [];
  public wifiPlans: number[] = [];
  public blePlans: number[] = [];
  public bssidWifi: Map<string, number[]> = new Map<string, number[]>();
  public bssidBle: Map<string, number[]> = new Map<string, number[]>();
  public vendorIe: Map<string, number[]> = new Map<string, number[]>();
  public longOui: SignatureOuiRule[] = [];

  plansFor(kind: RadioKind): number[] { return kind === RadioKind.WIFI ? this.wifiPlans : this.blePlans; }

  ouiHits(context: SignatureMatchContext): boolean[] {
    const hits: boolean[] = [];
    for (let index = 0; index < this.plans.length; index += 1) hits.push(false);
    const addressHex: string = context.addressHex();
    const oui: string = addressHex.length >= 6 ? addressHex.substring(0, 6) : addressHex;
    const map: Map<string, number[]> = context.kind === RadioKind.WIFI ? this.bssidWifi : this.bssidBle;
    this.mark(hits, map.get(oui));
    if (context.kind === RadioKind.WIFI) {
      if (addressHex.length >= 6) {
        const firstByte: number = parseInt(addressHex.substring(0, 2), 16);
        if (!Number.isNaN(firstByte) && (firstByte & 0x02) !== 0) {
          const universal: string = ((firstByte & 0xFD) | 0x00).toString(16).toUpperCase().padStart(2, '0') + addressHex.substring(2, 6);
          this.mark(hits, map.get(universal));
        }
      }
      for (let index = 0; index < context.vendorIeOuis.length; index += 1) {
        const hex: string = signatureHexOnly(context.vendorIeOuis[index]);
        if (hex.length < 6) continue;
        const ie6: string = hex.substring(0, 6);
        if (SIGNATURE_WIFI_PROTOCOL_IE_OUIS.indexOf(ie6) >= 0) continue;
        this.mark(hits, this.vendorIe.get(ie6));
      }
    }
    for (let index = 0; index < this.longOui.length; index += 1) {
      const rule: SignatureOuiRule = this.longOui[index];
      if (rule.radio !== undefined && rule.radio !== context.kind) continue;
      if (rule.bssid && addressHex.length > 0 && addressHex.indexOf(rule.hex) === 0) hits[rule.planIndex] = true;
      if (rule.vendor && context.kind === RadioKind.WIFI) {
        for (let inner = 0; inner < context.vendorIeOuis.length; inner += 1) {
          const hex: string = signatureHexOnly(context.vendorIeOuis[inner]);
          if (hex.length < 6) continue;
          if (SIGNATURE_WIFI_PROTOCOL_IE_OUIS.indexOf(hex.substring(0, 6)) >= 0) continue;
          if (hex.indexOf(rule.hex) === 0) hits[rule.planIndex] = true;
        }
      }
    }
    return hits;
  }

  private mark(hits: boolean[], indexes: number[] | undefined): void {
    if (indexes === undefined) return;
    for (let index = 0; index < indexes.length; index += 1) hits[indexes[index]] = true;
  }
}

function addPlanIndex(map: Map<string, number[]>, key: string, planIndex: number): void {
  let list: number[] | undefined = map.get(key);
  if (list === undefined) { list = []; map.set(key, list); }
  if (list.indexOf(planIndex) < 0) list.push(planIndex);
}

function ruleScope(rule: SignatureRule): RadioKind | undefined {
  if (rule.kind === SignatureRuleKind.VENDOR_IE_OUI || rule.kind === SignatureRuleKind.HIDDEN_SSID) return RadioKind.WIFI;
  if (rule.kind === SignatureRuleKind.RADIO_KIND) return rule.radio;
  if (rule.kind === SignatureRuleKind.SERVICE_UUID || rule.kind === SignatureRuleKind.SERVICE_DATA) return rule.radio === undefined ? RadioKind.BLE : rule.radio;
  if (rule.kind === SignatureRuleKind.MANUFACTURER_ID || rule.kind === SignatureRuleKind.MANUFACTURER_DATA) return rule.radio === undefined ? RadioKind.BLE : rule.radio;
  return rule.radio;
}

function radioScopeOf(rules: SignatureRule[]): RadioKind | undefined {
  let wifi: boolean = false;
  let ble: boolean = false;
  let both: boolean = false;
  rules.forEach((rule: SignatureRule): void => {
    const scope: RadioKind | undefined = ruleScope(rule);
    if (scope === RadioKind.WIFI) wifi = true;
    else if (scope === RadioKind.BLE) ble = true;
    else both = true;
  });
  if (both || (wifi && ble)) return undefined;
  if (wifi) return RadioKind.WIFI;
  if (ble) return RadioKind.BLE;
  return undefined;
}

/**
 * 该特征是否需要走「同族聚类」这条判定路径。
 *
 * 三个开关任一为真都要走 —— 它们各自改变聚类阶段的判据，
 * 但都需要先把同族设备聚起来才能算。**导出是为了让用例能锁住这条契约**：
 * 界面上有开关、引擎里却不读，就是占位。
 */
export function needsCluster(fleet: SignatureFleet): boolean {
  return fleet.minPeers > 0 || fleet.clusterByOui || fleet.sequentialMac;
}

/**
 * 同族时间窗（秒）。**0 或负数一律退回 60**，与目录里的默认口径一致。
 *
 * 抽成函数是因为判定散在两处：聚类时算窗口、用例里核对默认值。
 * 两处各写一遍 `<= 0 ? 60 : x` 迟早会漂移。
 */
export function effectivePeerWindowSec(fleet: SignatureFleet): number {
  return fleet.peerWindowSec <= 0 ? 60 : fleet.peerWindowSec;
}

function compileFastRule(rule: SignatureRule): SignatureFastRule | undefined {
  if (rule.kind === SignatureRuleKind.NAME_CONTAINS) return rule.text.length === 0 ? undefined : new SignatureContainsRule(rule.text, rule.radio);
  if (rule.kind === SignatureRuleKind.NAME_GLOB) return rule.text.length === 0 ? undefined : new SignatureGlobRule(globToRegExp(rule.text), rule.radio);
  if (rule.kind === SignatureRuleKind.SERVICE_UUID) return rule.text.length === 0 ? undefined : new SignatureUuidRule(signatureUuidAliases(rule.text), rule.radio);
  if (rule.kind === SignatureRuleKind.MANUFACTURER_ID) return new SignatureManufacturerIdRule(rule.companyId, rule.radio);
  if (rule.kind === SignatureRuleKind.MANUFACTURER_DATA) {
    const prefix: string = signatureHexOnly(rule.dataPrefixHex);
    if (prefix.length === 0) return undefined;
    return new SignatureManufacturerDataRule(rule.companyId, prefix, rule.radio, rule.offset, rule.minLen, rule.maxLen);
  }
  if (rule.kind === SignatureRuleKind.SERVICE_DATA) {
    const prefix: string = signatureHexOnly(rule.dataPrefixHex);
    const aliases: string[] = signatureUuidAliases(rule.text);
    if (prefix.length === 0 && aliases.length === 0) return undefined;
    return new SignatureServiceDataRule(aliases, prefix, rule.text.length === 0 && prefix.length > 0,
      rule.radio, rule.offset, rule.minLen, rule.maxLen);
  }
  if (rule.kind === SignatureRuleKind.RADIO_KIND) return new SignatureRadioRule(rule.radio);
  if (rule.kind === SignatureRuleKind.HIDDEN_SSID) return new SignatureHiddenSsidRule();
  return undefined;
}

function ruleHits(context: SignatureMatchContext, rule: SignatureRule): boolean {
  if (rule.kind !== SignatureRuleKind.RADIO_KIND && rule.radio !== undefined && context.kind !== rule.radio) return false;
  if (rule.kind === SignatureRuleKind.OUI || rule.kind === SignatureRuleKind.MAC_PREFIX) {
    if (matchesPrefix(context.address, rule.text)) return true;
    if (rule.kind === SignatureRuleKind.OUI && vendorIeHitsOui(context, rule.text)) return true;
    if (rule.kind === SignatureRuleKind.OUI && recoveredWifiOuiHits(context, rule.text)) return true;
    return false;
  }
  const fast: SignatureFastRule | undefined = compileFastRule(rule);
  return fast === undefined ? false : fast.hits(context);
}

function mfgPrefixOf(dataHex: string): string {
  const hex: string = signatureHexOnly(dataHex);
  return hex.length >= 2 ? hex.substring(0, 2) : hex;
}

function isAppleContinuity(context: SignatureMatchContext): boolean {
  if (context.manufacturerId !== APPLE_COMPANY_ID) return false;
  return APPLE_CONTINUITY_PREFIXES.indexOf(mfgPrefixOf(context.manufacturerDataHex)) >= 0;
}

function hasFindMyAccessoryUuid(context: SignatureMatchContext): boolean {
  const want: string[] = signatureUuidAliases('FD44');
  const all: string[] = context.serviceUuids.slice();
  context.serviceData.forEach((record: ServiceDataRecord): void => { all.push(record.uuid); });
  for (let index = 0; index < all.length; index += 1) {
    const aliases: string[] = signatureUuidAliases(all[index]);
    for (let inner = 0; inner < aliases.length; inner += 1) if (want.indexOf(aliases[inner]) >= 0) return true;
  }
  return false;
}

function isTeslaPhoneKeyIBeacon(context: SignatureMatchContext): boolean {
  if (context.manufacturerId !== APPLE_COMPANY_ID) return false;
  return signatureHexOnly(context.manufacturerDataHex).indexOf(TESLA_IBEACON_MFG_PREFIX) === 0;
}

export class SignatureMatchExplanation {
  public fleetId: string = '';
  public fleetName: string = '';
  public category: SignatureClass = SignatureClass.OTHER;
  public matchedRules: string[] = [];
  public reason: string = '';
  constructor(fleetId: string, fleetName: string, category: SignatureClass, matchedRules: string[], reason: string) {
    this.fleetId = fleetId; this.fleetName = fleetName; this.category = category; this.matchedRules = matchedRules; this.reason = reason;
  }
}

/**
 * 签名匹配引擎：OUI 规则按十六进制索引，其余规则编译成快速规则，
 * 保证 240+ 签名 / 7000+ 规则下不会对每台设备做全量遍历。
 */
export class FieldwatchSignatureEngine {
  private cachedFleets: SignatureFleet[] | undefined = undefined;
  private cachedIndex: CompiledSignatureIndex | undefined = undefined;

  /** 单设备匹配，返回按签名 id 升序的命中列表。 */
  matchContext(context: SignatureMatchContext, fleets: SignatureFleet[]): string[] {
    const index: CompiledSignatureIndex = this.indexFor(fleets);
    return this.matchOne(context, index, fleets);
  }

  /** 批量匹配；同时处理需要多台设备才成立的 cluster 签名。 */
  matchContexts(contexts: SignatureMatchContext[], fleets: SignatureFleet[], now: number): Map<string, string[]> {
    const index: CompiledSignatureIndex = this.indexFor(fleets);
    const result: Map<string, string[]> = new Map<string, string[]>();
    contexts.forEach((context: SignatureMatchContext): void => {
      result.set(context.key, this.matchOne(context, index, fleets));
    });
    this.applyClusters(contexts, index, result, now);
    return result;
  }

  explain(context: SignatureMatchContext, fleets: SignatureFleet[]): SignatureMatchExplanation[] {
    const result: SignatureMatchExplanation[] = [];
    fleets.forEach((fleet: SignatureFleet): void => {
      if (!fleet.enabled) return;
      const active: SignatureRule[] = fleet.rules.filter((rule: SignatureRule): boolean => rule.enabled);
      if (active.length === 0) return;
      const hits: string[] = [];
      active.forEach((rule: SignatureRule): void => { if (ruleHits(context, rule)) hits.push(rule.kind + ':' + rule.text); });
      if (hits.length === 0) return;
      const matched: boolean = fleet.matchAny ? true : hits.length === active.length;
      if (!matched) return;
      result.push(new SignatureMatchExplanation(fleet.id, fleet.name, fleet.category, hits, hits.length.toString() + '/' + active.length.toString()));
    });
    result.sort((first: SignatureMatchExplanation, second: SignatureMatchExplanation): number => second.matchedRules.length - first.matchedRules.length);
    return result;
  }

  /** 从一台设备反推一条新签名规则，供“为此设备新建签名”使用。 */
  suggestFleet(context: SignatureMatchContext): SignatureFleet {
    const rules: SignatureRule[] = [];
    if (context.address.length > 0) rules.push(new SignatureRule(SignatureRuleKind.MAC_PREFIX, context.address));
    if (context.name.length > 0 && !context.hiddenSsid) rules.push(new SignatureRule(SignatureRuleKind.NAME_CONTAINS, context.name.substring(0, 32)));
    context.serviceUuids.slice(0, 3).forEach((uuid: string): void => {
      const aliases: string[] = signatureUuidAliases(uuid);
      if (aliases.length > 1) rules.push(new SignatureRule(SignatureRuleKind.SERVICE_UUID, aliases[1]));
    });
    if (context.manufacturerId > 0) {
      const prefix: string = signatureHexOnly(context.manufacturerDataHex).substring(0, 2);
      if (prefix.length > 0) rules.push(new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', context.manufacturerId, prefix));
      else rules.push(new SignatureRule(SignatureRuleKind.MANUFACTURER_ID, '', context.manufacturerId));
    }
    const hasIdentity: boolean = rules.some((rule: SignatureRule): boolean => rule.kind !== SignatureRuleKind.MAC_PREFIX);
    if (!hasIdentity && context.oui().length > 0) rules.push(new SignatureRule(SignatureRuleKind.OUI, context.oui()));
    const label: string = context.name.length > 0 && !context.hiddenSsid ? context.name.substring(0, 22) : (context.ssid.length > 0 ? context.ssid : context.address);
    const fleet: SignatureFleet = new SignatureFleet('sig-' + Date.now().toString(), label, SignatureClass.OTHER, rules, false);
    // 星闪与 BLE 同属广播源，用同一档配色；只有 Wi-Fi 用 0 档。
    fleet.colorIndex = context.kind === RadioKind.WIFI ? 0 : 3;
    return fleet;
  }

  private indexFor(fleets: SignatureFleet[]): CompiledSignatureIndex {
    const cached: CompiledSignatureIndex | undefined = this.cachedIndex;
    if (cached !== undefined && this.cachedFleets === fleets) return cached;
    const index: CompiledSignatureIndex = this.compile(fleets);
    this.cachedIndex = index;
    this.cachedFleets = fleets;
    return index;
  }

  private compile(fleets: SignatureFleet[]): CompiledSignatureIndex {
    const index: CompiledSignatureIndex = new CompiledSignatureIndex();
    fleets.forEach((fleet: SignatureFleet): void => {
      const planIndex: number = index.plans.length;
      const plan: SignatureFleetPlan = new SignatureFleetPlan(fleet);
      plan.matchAny = fleet.matchAny;
      plan.cluster = needsCluster(fleet);
      const active: SignatureRule[] = fleet.enabled ? fleet.rules.filter((rule: SignatureRule): boolean => rule.enabled) : [];
      // 先把分组规则分出来：它们只走 groups，不参与下面的基础集合索引。
      const grouped: SignatureRule[] = [];
      const base: SignatureRule[] = [];
      active.forEach((rule: SignatureRule): void => {
        if (rule.group > 0) grouped.push(rule);
        else base.push(rule);
      });
      const groupBuckets: Map<number, SignatureFastRule[]> = new Map();
      grouped.forEach((rule: SignatureRule): void => {
        const compiled: SignatureFastRule | undefined = compileFastRule(rule);
        if (compiled === undefined) return;
        const bucket: SignatureFastRule[] = groupBuckets.get(rule.group) ?? [];
        bucket.push(compiled);
        groupBuckets.set(rule.group, bucket);
      });
      const groupIds: number[] = Array.from(groupBuckets.keys()).sort((a: number, b: number): number => a - b);
      groupIds.forEach((id: number): void => { plan.groups.push(groupBuckets.get(id) as SignatureFastRule[]); });
      active.forEach((rule: SignatureRule): void => {
        if (rule.group > 0) return;
        plan.rules.push(rule);
        if (rule.kind === SignatureRuleKind.OUI || rule.kind === SignatureRuleKind.MAC_PREFIX) {
          this.indexOui(rule, rule.kind === SignatureRuleKind.OUI, planIndex, index);
          return;
        }
        if (rule.kind === SignatureRuleKind.VENDOR_IE_OUI) {
          this.indexOui(rule, false, planIndex, index);
          return;
        }
        const fast: SignatureFastRule | undefined = compileFastRule(rule);
        if (fast !== undefined) plan.fastRules.push(fast);
      });
      index.plans.push(plan);
      const scope: RadioKind | undefined = radioScopeOf(base.length > 0 ? base : active);
      if (scope === RadioKind.WIFI) index.wifiPlans.push(planIndex);
      else if (scope === RadioKind.BLE) index.blePlans.push(planIndex);
      else { index.wifiPlans.push(planIndex); index.blePlans.push(planIndex); }
    });
    return index;
  }

  private indexOui(rule: SignatureRule, vendor: boolean, planIndex: number, index: CompiledSignatureIndex): void {
    const hex: string = signatureHexOnly(rule.text);
    if (hex.length === 0) return;
    if (hex.length !== 6) {
      index.longOui.push(new SignatureOuiRule(hex, rule.radio, true, vendor, planIndex));
      return;
    }
    if (rule.radio !== RadioKind.BLE) addPlanIndex(index.bssidWifi, hex, planIndex);
    if (rule.radio !== RadioKind.WIFI) addPlanIndex(index.bssidBle, hex, planIndex);
    if (vendor && rule.radio !== RadioKind.BLE && SIGNATURE_WIFI_PROTOCOL_IE_OUIS.indexOf(hex) < 0) addPlanIndex(index.vendorIe, hex, planIndex);
  }

  private matchOne(context: SignatureMatchContext, index: CompiledSignatureIndex, fleets: SignatureFleet[]): string[] {
    const hits: string[] = [];
    const ouiHits: boolean[] = index.ouiHits(context);
    const planIndexes: number[] = index.plansFor(context.kind);
    for (let position = 0; position < planIndexes.length; position += 1) {
      const planIndex: number = planIndexes[position];
      const plan: SignatureFleetPlan = index.plans[planIndex];
      if (plan.cluster) continue;
      if (this.fleetHits(context, plan, ouiHits[planIndex])) hits.push(plan.id);
    }
    this.arbitrate(hits, index, context);
    return hits;
  }

  private fleetHits(context: SignatureMatchContext, plan: SignatureFleetPlan, ouiHit: boolean): boolean {
    if (plan.rules.length === 0 && plan.groups.length === 0) return false;
    if (plan.id === FLEET_IBEACON && isTeslaPhoneKeyIBeacon(context)) return false;
    // 分组分支（组内 AND、组间 OR）先判；命中即整体命中。
    for (let group = 0; group < plan.groups.length; group += 1) {
      const bucket: SignatureFastRule[] = plan.groups[group];
      if (bucket.length === 0) continue;
      let all: boolean = true;
      for (let index: number = 0; index < bucket.length; index += 1) {
        if (!bucket[index].hits(context)) { all = false; break; }
      }
      if (all) return true;
    }
    if (plan.rules.length === 0) return false;
    if (!plan.matchAny) {
      for (let index = 0; index < plan.rules.length; index += 1) {
        if (!ruleHits(context, plan.rules[index])) return false;
      }
      return true;
    }
    if (ouiHit) return true;
    for (let index = 0; index < plan.fastRules.length; index += 1) {
      if (plan.fastRules[index].hits(context)) return true;
    }
    return false;
  }

  /** 目录级仲裁：同一设备命中多个签名时，按 Android 基线丢弃泛化度更高的标签。 */
  private arbitrate(hits: string[], index: CompiledSignatureIndex, context: SignatureMatchContext): void {
    if (hits.indexOf(FLEET_IBEACON) >= 0) {
      let otherProduct: boolean = false;
      for (let position = 0; position < hits.length; position += 1) {
        const id: string = hits[position];
        if (id === FLEET_IBEACON) continue;
        const plan: SignatureFleetPlan | undefined = index.plans.find((item: SignatureFleetPlan): boolean => item.id === id);
        if (plan !== undefined && plan.fleet.category !== SignatureClass.BEACON) otherProduct = true;
      }
      if (otherProduct) this.removeId(hits, FLEET_IBEACON);
    }
    if (hits.indexOf(FLEET_OSMO) >= 0) this.removeId(hits, FLEET_DJI);
    if (hits.indexOf(FLEET_MERAKI) >= 0) this.removeId(hits, FLEET_CISCO);
    if (hits.indexOf(FLEET_AIRTAG) >= 0) {
      const namedAirTag: boolean = context.name.toLowerCase().indexOf('airtag') >= 0;
      if (!namedAirTag && !hasFindMyAccessoryUuid(context)) {
        const appleProduct: boolean = hits.indexOf(FLEET_APPLE_DEVICE) >= 0 || hits.indexOf(FLEET_APPLE_AUDIO) >= 0;
        if (appleProduct || isAppleContinuity(context)) this.removeId(hits, FLEET_AIRTAG);
      }
    }
  }

  private removeId(hits: string[], id: string): void {
    const position: number = hits.indexOf(id);
    if (position >= 0) hits.splice(position, 1);
  }

  private applyClusters(contexts: SignatureMatchContext[], index: CompiledSignatureIndex, result: Map<string, string[]>, now: number): void {
    for (let planIndex = 0; planIndex < index.plans.length; planIndex += 1) {
      const plan: SignatureFleetPlan = index.plans[planIndex];
      if (!plan.cluster) continue;
      const fleet: SignatureFleet = plan.fleet;
      const windowMs: number = effectivePeerWindowSec(fleet) * 1000;
      const live: SignatureMatchContext[] = contexts.filter((item: SignatureMatchContext): boolean => now - item.lastSeen <= windowMs);
      for (let outer = 0; outer < live.length; outer += 1) {
        const candidate: SignatureMatchContext = live[outer];
        const candidateOui: boolean = index.ouiHits(candidate)[planIndex];
        let eligible: boolean = plan.rules.length === 0 || this.fleetHits(candidate, plan, candidateOui);
        if (!eligible && fleet.clusterByOui && (candidate.name.length === 0)) eligible = true;
        if (!eligible) continue;
        let peers: number = 1;
        for (let inner = 0; inner < live.length; inner += 1) {
          const peer: SignatureMatchContext = live[inner];
          if (peer.key === candidate.key) continue;
          if (fleet.clusterByOui && candidate.oui() !== peer.oui()) continue;
          if (fleet.sequentialMac) {
            const first: string = candidate.addressHex();
            const second: string = peer.addressHex();
            if (first.length < 12 || second.length < 12) continue;
            const delta: number = Math.abs(parseInt(first.substring(8, 12), 16) - parseInt(second.substring(8, 12), 16));
            if (Number.isNaN(delta) || delta > 64) continue;
          }
          if (plan.rules.length > 0 && !fleet.clusterByOui && !this.fleetHits(peer, plan, index.ouiHits(peer)[planIndex])) continue;
          peers += 1;
        }
        const need: number = fleet.minPeers <= 0 ? 3 : fleet.minPeers;
        if (peers >= need) {
          const hits: string[] | undefined = result.get(candidate.key);
          if (hits !== undefined && hits.indexOf(plan.id) < 0) hits.push(plan.id);
        }
      }
    }
  }
}

function hexToBytes(hex: string): number[] {
  const value: string = signatureHexOnly(hex);
  const bytes: number[] = [];
  for (let index = 0; index + 1 < value.length; index += 2) {
    const parsed: number = parseInt(value.substring(index, index + 2), 16);
    if (!Number.isNaN(parsed)) bytes.push(parsed);
  }
  return bytes;
}

function bytesToHex(bytes: number[]): string {
  let result: string = '';
  bytes.forEach((value: number): void => { result += value.toString(16).toUpperCase().padStart(2, '0'); });
  return result;
}

function readUnsigned(bytes: number[], start: number, length: number, bigEndian: boolean): number {
  let value: number = 0;
  for (let index = 0; index < length; index += 1) {
    const position: number = bigEndian ? start + index : start + length - 1 - index;
    value = value * 256 + bytes[position];
  }
  return value;
}

function readSigned(bytes: number[], start: number, length: number, bigEndian: boolean): number {
  const raw: number = readUnsigned(bytes, start, length, bigEndian);
  const limit: number = Math.pow(2, length * 8 - 1);
  return raw >= limit ? raw - limit * 2 : raw;
}

function gatePasses(gate: SignatureDecodeWhen | undefined, bytes: number[]): boolean {
  if (gate === undefined) return true;
  let passed: boolean = false;
  if (gate.op === SignatureDecodeWhenOp.LEN) {
    passed = bytes.length === gate.length;
  } else {
    const want: number[] = hexToBytes(gate.valueHex);
    const slice: number[] = bytes.slice(gate.offset, gate.offset + gate.length);
    if (slice.length !== gate.length) passed = false;
    else if (gate.op === SignatureDecodeWhenOp.EQ) passed = bytesToHex(slice) === bytesToHex(want);
    else if (gate.op === SignatureDecodeWhenOp.NEQ) passed = bytesToHex(slice) !== bytesToHex(want);
    else if (gate.op === SignatureDecodeWhenOp.MASK) {
      passed = true;
      for (let index = 0; index < slice.length; index += 1) { if ((slice[index] & want[index]) !== want[index]) passed = false; }
    } else {
      passed = true;
      for (let index = 0; index < slice.length; index += 1) { if ((slice[index] & want[index]) !== 0) passed = false; }
    }
  }
  if (!passed) return false;
  return gatePasses(gate.and, bytes);
}

/** 按偏移 / 长度 / 字节序 / 门控解码签名字段，输出 Live 行、详情、Debrief 共用的结果。 */
export class FieldwatchSignatureFieldDecoder {
  decode(fleet: SignatureFleet, context: SignatureMatchContext): DecodedFieldValue[] {
    const decode: SignatureFleetDecode | undefined = fleet.decode;
    if (decode === undefined || decode.fields.length === 0) return [];
    const payload: number[] | undefined = this.payloadFor(decode, context);
    if (payload === undefined) return [];
    const result: DecodedFieldValue[] = [];
    decode.fields.forEach((field: SignatureDecodeField): void => {
      if (!gatePasses(field.gate, payload)) return;
      const value: DecodedFieldValue | undefined = this.decodeField(field, payload);
      if (value !== undefined) result.push(value);
    });
    return result;
  }

  private payloadFor(decode: SignatureFleetDecode, context: SignatureMatchContext): number[] | undefined {
    if (decode.source === SignatureDecodeSource.SERVICE_DATA) {
      const aliases: string[] = signatureUuidAliases(decode.serviceUuid);
      for (let index = 0; index < context.serviceData.length; index += 1) {
        const record: ServiceDataRecord = context.serviceData[index];
        if (aliases.length > 0) {
          const recordAliases: string[] = signatureUuidAliases(record.uuid);
          let matched: boolean = false;
          for (let inner = 0; inner < recordAliases.length; inner += 1) if (aliases.indexOf(recordAliases[inner]) >= 0) matched = true;
          if (!matched) continue;
        }
        return hexToBytes(record.dataHex);
      }
      return undefined;
    }
    if (decode.companyId !== 0 && context.manufacturerId !== decode.companyId) return undefined;
    if (context.manufacturerId === 0 && context.manufacturerDataHex.length === 0) return undefined;
    const bytes: number[] = hexToBytes(context.manufacturerDataHex);
    if (!decode.includeCompanyId) return bytes;
    // 字段偏移按“含 Company ID 的原始载荷”计算；decode 未指定时用设备实际的 Company ID。
    const companyId: number = decode.companyId !== 0 ? decode.companyId : context.manufacturerId;
    return [companyId % 256, Math.floor(companyId / 256) % 256].concat(bytes);
  }

  /** modulo → scale → offsetAdd 对所有数值类型统一生效（bits 与 f32 同样适用）。 */
  private applyTransform(value: number, field: SignatureDecodeField): number {
    let result: number = value;
    if (field.modulo !== undefined && field.modulo !== 0) result = result % field.modulo;
    if (field.scale !== undefined && field.scale !== 0) result = result * field.scale;
    if (field.offsetAdd !== undefined) result = result + field.offsetAdd;
    return result;
  }

  private decodeField(field: SignatureDecodeField, payload: number[]): DecodedFieldValue | undefined {
    const length: number = field.resolvedLength();
    if (field.offset < 0 || field.offset + length > payload.length) return undefined;
    const bigEndian: boolean = field.endian === SignatureDecodeEndian.BE;
    const rawKey: string = '';
    let numeric: number = 0;
    let text: string = '';
    let key: string = '';
    if (field.type === SignatureDecodeType.UTF8) {
      let decoded: string = '';
      for (let index = 0; index < length; index += 1) decoded += String.fromCharCode(payload[field.offset + index]);
      text = decoded;
      key = decoded;
    } else if (field.type === SignatureDecodeType.HEX) {
      text = bytesToHex(payload.slice(field.offset, field.offset + length));
      key = text;
    } else if (field.type === SignatureDecodeType.MAC) {
      const parts: string[] = [];
      for (let index = 0; index < length; index += 1) parts.push(payload[field.offset + index].toString(16).toUpperCase().padStart(2, '0'));
      text = parts.join(':');
      key = text;
    } else if (field.type === SignatureDecodeType.BITS) {
      const start: number = field.bitOffset < 0 ? 0 : field.bitOffset;
      const width: number = field.bitWidth < 0 ? 1 : field.bitWidth;
      const raw: number = readUnsigned(payload, field.offset, length, bigEndian);
      numeric = this.applyTransform(Math.floor(raw / Math.pow(2, start)) % Math.pow(2, width), field);
      text = numeric.toString();
      key = text;
    } else if (field.type === SignatureDecodeType.F32) {
      const view: DataView = new DataView(new ArrayBuffer(4));
      for (let index = 0; index < 4; index += 1) view.setUint8(index, payload[field.offset + index]);
      numeric = this.applyTransform(view.getFloat32(0, !bigEndian), field);
      text = numeric.toString();
      key = text;
    } else if (field.type === SignatureDecodeType.BOOL) {
      numeric = readUnsigned(payload, field.offset, length, bigEndian) === 0 ? 0 : 1;
      text = numeric.toString();
      key = text;
    } else {
      const signed: boolean = field.type === SignatureDecodeType.I8 || field.type === SignatureDecodeType.I16 || field.type === SignatureDecodeType.I32;
      numeric = signed ? readSigned(payload, field.offset, length, bigEndian) : readUnsigned(payload, field.offset, length, bigEndian);
      numeric = this.applyTransform(numeric, field);
      text = numeric.toString();
      key = text;
    }
    const labels: Map<string, string> | undefined = field.enumLabels;
    if (labels !== undefined) {
      const named: string | undefined = labels.get(key);
      if (named !== undefined) text = named;
    }
    if (field.unit.length > 0 && (labels === undefined || labels.get(key) === undefined)) text = text + ' ' + field.unit;
    const emphasis: boolean = field.liveEmphasis.indexOf(key) >= 0;
    const notes: Map<string, string> | undefined = field.enumNotes;
    const note: string = notes === undefined ? '' : (notes.get(key) === undefined ? '' : notes.get(key) as string);
    return new DecodedFieldValue(field.id, field.label, text, key.length > 0 ? key : rawKey, field.unit, field.live, emphasis, note);
  }
}
