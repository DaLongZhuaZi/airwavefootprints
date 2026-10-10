import { AppSettings, FilterDefinition, FilterLogic, GpsSample, RadioKind, ScanObservation, SignatureClass, Sighting, WatchTarget, foldedSignatureClass } from './FieldwatchModels';
import { FieldwatchRadioDb } from './FieldwatchRadioDb';
import { SignatureFleet } from './signatures/FieldwatchSignatureModels';
import { FilterPreset, ServiceDataRecord } from './FieldwatchModels';

/** RSSI 统计辅助；签名匹配已迁移到 domain/signatures 下的完整特征库引擎。 */
export class FieldwatchSignatureEngine {
  rssiAverage(sighting: Sighting): number {
    if (sighting.rssiSamples.length === 0) return sighting.rssi;
    let total: number = 0;
    sighting.rssiSamples.forEach((value: number): void => { total += value; });
    return total / sighting.rssiSamples.length;
  }

  rssiTrend(sighting: Sighting): number {
    if (sighting.rssiSamples.length < 2) return 0;
    return sighting.rssiSamples[sighting.rssiSamples.length - 1] - sighting.rssiSamples[0];
  }
}

export class FieldwatchFilterEngine {
  /** 名称库（应用启动时注入）；未注入时厂商匹配退化为只匹配 MAC。 */
  private static radioDb: FieldwatchRadioDb | undefined = undefined;
  static setRadioDb(db: FieldwatchRadioDb): void { FieldwatchFilterEngine.radioDb = db; }
  /**
   * 与原版 domain/FilterEngine.kt 的 pass() 逐条对齐。
   * AND：全部硬条件与可选条件都要满足；
   * OR：硬条件仍必须满足，可选条件（签名包含 / 仅显示类别 / 名称 / OUI / RSSI / 本 App 的细化条件）取任一。
   */
  pass(sighting: Sighting, filter: FilterDefinition, signatures: SignatureFleet[], watched: WatchTarget[], namedKeys: string[], now: number): boolean {
    const fleetIds: string[] = sighting.signatureIds;
    const classes: SignatureClass[] = [];
    fleetIds.forEach((id: string): void => {
      const fleet: SignatureFleet | undefined = signatures.find((item: SignatureFleet): boolean => item.id === id);
      if (fleet !== undefined) {
        const folded: SignatureClass = foldedSignatureClass(fleet.category);
        if (classes.indexOf(folded) < 0) classes.push(folded);
      }
    });
    // 兼容桥接：旧的单选字段映射到原版的双开关 / 三态集合，UI 重做后可移除。
    const wifiOn: boolean = filter.radioKind === undefined ? filter.showWifi : filter.radioKind === RadioKind.WIFI;
    const bleOn: boolean = filter.radioKind === undefined ? filter.showBle : filter.radioKind === RadioKind.BLE;
    const nearLinkOn: boolean = filter.radioKind === undefined ? filter.showNearLink : filter.radioKind === RadioKind.NEARLINK;
    const classGateOn: boolean = filter.useClassFilter || filter.signatureClass !== undefined;
    const classList: SignatureClass[] = filter.signatureClass === undefined ? filter.classes : [filter.signatureClass];
    const hasAny = (source: string[], wanted: string[]): boolean => source.some((value: string): boolean => wanted.indexOf(value) >= 0);
    const noneOf = (source: string[], unwanted: string[]): boolean => !source.some((value: string): boolean => unwanted.indexOf(value) >= 0);
    const anyClass = (wanted: SignatureClass[]): boolean => classes.some((value: SignatureClass): boolean => wanted.indexOf(value) >= 0);
    // ── 硬条件 ──
    const namedOk: boolean = !filter.namedOnly || fleetIds.length > 0;
    const customNamedOk: boolean = !filter.customNamesOnly || namedKeys.indexOf(sighting.key) >= 0;
    const watchedOk: boolean = !filter.watchedOnly || watched.some((target: WatchTarget): boolean =>
      target.alert && (target.deviceKey === sighting.key || (target.signatureId.length > 0 && fleetIds.indexOf(target.signatureId) >= 0)));
    // 三种无线电种类各有开关，星闪不能落进 BLE 的分支（否则「仅 BLE」会连星闪一起放行）。
    const typeOk: boolean = sighting.kind === RadioKind.WIFI ? wifiOn
      : (sighting.kind === RadioKind.NEARLINK ? nearLinkOn : bleOn);
    const hideOk: boolean = !(filter.excludeSignatures && filter.fleetIds.length > 0) || noneOf(fleetIds, filter.fleetIds);
    const hideClassOk: boolean = !(filter.excludeClasses && classList.length > 0) || !anyClass(classList);
    const attentionOk: boolean = !filter.attentionOnly || fleetIds.some((id: string): boolean =>
      signatures.some((fleet: SignatureFleet): boolean => fleet.id === id && fleet.attentionNote.length > 0));
    const freshOk: boolean = !filter.freshOnly || sighting.fresh;
    const cachedOk: boolean = !filter.cachedOnly || !sighting.fresh;
    const decodedOk: boolean = !filter.decodedOnly || sighting.decodedFields.length > 0;
    const locatedOk: boolean = !filter.locatedOnly || sighting.location !== undefined;
    // ── 可选条件 ──
    const includeOk: boolean = !filter.includeSignatures || filter.includeFleetIds.length === 0 || hasAny(fleetIds, filter.includeFleetIds);
    const includeClassOk: boolean = !classGateOn || filter.excludeClasses || classList.length === 0 || anyClass(classList);
    const rssiOk: boolean = sighting.rssi >= filter.rssiMin;
    const query: string = filter.nameQuery.trim().toLowerCase();
    const nameOk: boolean = query.length === 0 || sighting.name.toLowerCase().indexOf(query) >= 0 || sighting.key.toLowerCase().indexOf(query) >= 0;
    const ouiQuery: string = filter.ouiQuery.trim().toLowerCase();
    // 与原版 domain/FilterEngine.kt 一致：ouiQuery 同时匹配 MAC 与厂商名。
    // 厂商名来自 OUI 名称库（radiodb.bin，MA-L 39995 条 / 34781 个名称），由应用启动时注入。
    const ouiOk: boolean = ouiQuery.length === 0
      || sighting.key.toLowerCase().indexOf(ouiQuery) >= 0
      || this.vendorOf(sighting).toLowerCase().indexOf(ouiQuery) >= 0;
    let gates: boolean;
    if (filter.logic === FilterLogic.AND) {
      gates = namedOk && customNamedOk && watchedOk && typeOk && hideOk && includeOk && hideClassOk && includeClassOk
        && attentionOk && freshOk && cachedOk && decodedOk && locatedOk && rssiOk && nameOk && ouiOk;
    } else {
      const optional: boolean[] = [];
      if (filter.includeSignatures) optional.push(includeOk);
      if (classGateOn && !filter.excludeClasses) optional.push(includeClassOk);
      if (filter.nameQuery.trim().length > 0) optional.push(nameOk);
      if (filter.ouiQuery.trim().length > 0) optional.push(ouiOk);
      if (filter.rssiMin > -100) optional.push(rssiOk);
      if (filter.attentionOnly) optional.push(attentionOk);
      if (filter.freshOnly) optional.push(freshOk);
      if (filter.cachedOnly) optional.push(cachedOk);
      if (filter.decodedOnly) optional.push(decodedOk);
      if (filter.locatedOnly) optional.push(locatedOk);
      const any: boolean = optional.length === 0 ? true : optional.some((value: boolean): boolean => value);
      gates = namedOk && customNamedOk && watchedOk && typeOk && hideOk && hideClassOk && any;
    }
    if (!gates) return false;
    if (filter.hideFastPairAccountKey && this.isFastPairAccountKeyOnly(sighting)) return false;
    if (!filter.movingWithYou) return true;
    return this.movingWithYou(sighting, now);
  }
  /**
   * 该信号源的厂商名；名称库未载入时返回空串。
   * 名称库由应用启动时注入，引擎本身不持有 IO。
   *
   * 走 `RadioDb.vendorFor` 这条**唯一**的解析链：筛选要匹配的正是列表里
   * 显示的那个品牌，否则会出现「界面写着 Apple, Inc.，按 apple 却筛不出来」。
   * 此前这里只有 OUI 一级，注释虽写着「与 facts 同源」，实际比 facts 少一级。
   */
  private vendorOf(sighting: Sighting): string {
    const db: FieldwatchRadioDb | undefined = FieldwatchFilterEngine.radioDb;
    if (db === undefined) return '';
    return db.vendorFor(sighting.facts.manufacturer, sighting.address, sighting.facts.manufacturerId);
  }
  /** 原版 FastPair.FLEET_ID：目录里的 Fast Pair 特征 id。 */
  private static readonly FAST_PAIR_FLEET_ID: string = 'fleet-fast-pair';
  /** 原版 FastPair.isFastPairUuid：短写 FE2C 或 128 位 UUID 的第 5-8 位。 */
  private isFastPairUuid(uuid: string): boolean {
    const hex: string = uuid.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    return hex === 'FE2C' || (hex.length >= 8 && hex.substring(4, 8) === 'FE2C');
  }
  /** 原版 FastPair.pairingAdvertised：service data 恰为 3 字节即配对模式（可点按配对）。 */
  private isFastPairPairing(sighting: Sighting): boolean {
    return sighting.facts.serviceData.some((record: ServiceDataRecord): boolean =>
      this.isFastPairUuid(record.uuid) && this.hexLength(record.dataHex) === 6);
  }
  private hexLength(raw: string): number { return raw.replace(/[^A-Za-z0-9]/g, '').length; }
  /**
   * 原版 FastPair.isAccountKeyOnly：
   *   不在配对模式，且命中了 Fast Pair 特征，且**只**命中这一个特征 —— 广场噪声。
   * 注意必须同时满足三条：只看 service data 的形状会误伤已配对但另有特征可识别的设备。
   */
  private isFastPairAccountKeyOnly(sighting: Sighting): boolean {
    if (this.isFastPairPairing(sighting)) return false;
    if (sighting.signatureIds.indexOf(FieldwatchFilterEngine.FAST_PAIR_FLEET_ID) < 0) return false;
    return sighting.signatureIds.length === 1;
  }
  /**
   * 与你同行：该设备在本机 GPS 轨迹附近持续出现（原版 CoTravel.withYou 的简化等价实现）。
   * 没有定位样本或轨迹太短时一律返回 false，避免把静止设备误判成同行。
   */
  private movingWithYou(sighting: Sighting, now: number): boolean {
    const samples: GpsSample[] = this.travelSamples;
    if (samples.length < 2) return false;
    const path: number = this.geo.pathLengthMeters(samples);
    if (path < 50) return false;
    if (sighting.location === undefined) return false;
    return now - sighting.lastSeen <= 45000;
  }
  /** 由应用层在每次定位更新时喂入本机轨迹。 */
  setTravelSamples(samples: GpsSample[]): void { this.travelSamples = samples; }
  private travelSamples: GpsSample[] = [];
  private readonly geo: FieldwatchGeoService = new FieldwatchGeoService();

  /** 原版 FilterEngine.defaultPresets 的等价实现。 */
  defaultPresets(): FilterPreset[] {
    const all: FilterDefinition = new FilterDefinition();
    const wifi: FilterDefinition = new FilterDefinition();
    wifi.showBle = false;
    wifi.showNearLink = false;
    const ble: FilterDefinition = new FilterDefinition();
    ble.showWifi = false;
    ble.showNearLink = false;
    const nearLink: FilterDefinition = new FilterDefinition();
    nearLink.showWifi = false;
    nearLink.showBle = false;
    const strong: FilterDefinition = new FilterDefinition();
    strong.rssiMin = -70;
    const withYou: FilterDefinition = new FilterDefinition();
    withYou.movingWithYou = true;
    withYou.showWifi = false;
    withYou.showNearLink = false;
    const watchedOnly: FilterDefinition = new FilterDefinition();
    watchedOnly.watchedOnly = true;
    const presets: FilterPreset[] = [];
    presets.push(new FilterPreset('all', all));
    presets.push(new FilterPreset('wifi', wifi));
    presets.push(new FilterPreset('ble', ble));
    presets.push(new FilterPreset('nearlink', nearLink));
    presets.push(new FilterPreset('strong', strong));
    presets.push(new FilterPreset('with-you', withYou));
    presets.push(new FilterPreset('watched', watchedOnly));
    return presets;
  }
  private hasSignatureClass(sighting: Sighting, category: SignatureClass, signatures: SignatureFleet[]): boolean {
    return sighting.signatureIds.some((id: string): boolean => signatures.some((signature: SignatureFleet): boolean => signature.id === id && foldedSignatureClass(signature.category) === category));
  }
}

export class FieldwatchGeoService {
  distanceMeters(first: GpsSample, second: GpsSample): number {
    const radius: number = 6371000;
    const latitudeDelta: number = (second.latitude - first.latitude) * Math.PI / 180;
    const longitudeDelta: number = (second.longitude - first.longitude) * Math.PI / 180;
    const firstLatitude: number = first.latitude * Math.PI / 180;
    const secondLatitude: number = second.latitude * Math.PI / 180;
    const halfChord: number = Math.sin(latitudeDelta / 2) * Math.sin(latitudeDelta / 2) + Math.cos(firstLatitude) * Math.cos(secondLatitude) * Math.sin(longitudeDelta / 2) * Math.sin(longitudeDelta / 2);
    return radius * 2 * Math.atan2(Math.sqrt(halfChord), Math.sqrt(1 - halfChord));
  }

  pathLengthMeters(samples: GpsSample[]): number {
    let total: number = 0;
    for (let index: number = 1; index < samples.length; index += 1) total += this.distanceMeters(samples[index - 1], samples[index]);
    return total;
  }
}

export class FieldwatchCompareResult {
  public sharedKeys: string[];
  public addedKeys: string[];
  public removedKeys: string[];
  constructor(sharedKeys: string[] = [], addedKeys: string[] = [], removedKeys: string[] = []) {
    this.sharedKeys = sharedKeys;
    this.addedKeys = addedKeys;
    this.removedKeys = removedKeys;
  }
}

export class FieldwatchCompareService {
  compare(first: string[], second: string[]): FieldwatchCompareResult {
    const firstSet: Set<string> = new Set<string>(first);
    const secondSet: Set<string> = new Set<string>(second);
    const shared: string[] = [];
    const added: string[] = [];
    const removed: string[] = [];
    second.forEach((key: string): void => {
      if (firstSet.has(key)) shared.push(key);
      else if (key.length > 0) added.push(key);
    });
    first.forEach((key: string): void => {
      if (!secondSet.has(key) && key.length > 0) removed.push(key);
    });
    return new FieldwatchCompareResult(shared.sort(), added.sort(), removed.sort());
  }
}

export class FieldwatchPrivacyService {
  maskAddress(address: string, enabled: boolean): string {
    if (!enabled || address.length < 5) return address;
    const separator: string = address.indexOf(':') >= 0 ? ':' : '-';
    const parts: string[] = address.split(separator);
    if (parts.length < 3) return '***';
    const visible: string[] = parts.slice(0, Math.max(0, parts.length - 3));
    visible.push('**'); visible.push('**'); visible.push('**');
    return visible.join(separator);
  }

  maskLocation(location: GpsSample | undefined, enabled: boolean): string {
    if (location === undefined) return '';
    const digits: number = enabled ? 2 : 6;
    return location.latitude.toFixed(digits) + ', ' + location.longitude.toFixed(digits);
  }

  deviceName(sighting: Sighting): string {
    if (sighting.name.length > 0) return sighting.name;
    return sighting.facts.ssid;
  }

  displayName(sighting: Sighting, enabled: boolean): string {
    const name: string = this.deviceName(sighting);
    return name.length > 0 ? name : this.maskAddress(sighting.address, enabled);
  }

  describe(sighting: Sighting, settings: AppSettings): string {
    const parts: string[] = [this.displayName(sighting, settings.privacyMode), this.maskAddress(sighting.address, settings.privacyMode), this.maskLocation(sighting.location, settings.privacyMode)];
    const unique: string[] = [];
    parts.forEach((part: string): void => { if (part.length > 0 && unique.indexOf(part) < 0) unique.push(part); });
    return unique.join(' · ');
  }
}

export function radioKindLabel(kind: RadioKind): string {
  return kind === RadioKind.BLE ? 'BLE' : 'Wi-Fi';
}
