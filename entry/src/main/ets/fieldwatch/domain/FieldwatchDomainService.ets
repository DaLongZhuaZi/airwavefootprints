import { AppSettings, FieldwatchRssiTrend, FilterDefinition, FilterLogic, GpsSample, isMeasuredRssi, RadioGpsSample, RadioKind, RadioRssiSample, ScanObservation, SignatureClass, Sighting, WatchTarget, foldedSignatureClass } from './FieldwatchModels';
import { FieldwatchRadioDb } from './FieldwatchRadioDb';
import { SignatureFleet } from './signatures/FieldwatchSignatureModels';
import { FilterPreset, ServiceDataRecord } from './FieldwatchModels';

/** RSSI 统计辅助；签名匹配已迁移到 domain/signatures 下的完整特征库引擎。 */
export class FieldwatchSignatureEngine {
  rssiAverage(sighting: Sighting, windowMs: number = 0, now: number = Date.now()): number {
    const cutoff: number = windowMs > 0 ? now - windowMs : 0;
    let total: number = 0;
    let count: number = 0;
    sighting.rssiHistory.forEach((sample: RadioRssiSample): void => {
      if (sample.at >= cutoff && isMeasuredRssi(sample.rssi)) {
        total += sample.rssi;
        count += 1;
      }
    });
    if (count > 0) return total / count;
    if (isMeasuredRssi(sighting.rssi)) return sighting.rssi;
    return -100;
  }

  rssiTrend(sighting: Sighting, count: number = 12): FieldwatchRssiTrend {
    const measured: RadioRssiSample[] = sighting.rssiHistory.filter((sample: RadioRssiSample): boolean =>
      isMeasuredRssi(sample.rssi));
    if (measured.length < 4) return FieldwatchRssiTrend.UNKNOWN;
    const sampleLimit: number = Math.max(4, Math.floor(count));
    const start: number = Math.max(0, measured.length - sampleLimit);
    const middle: number = start + Math.floor((measured.length - start) / 2);
    let olderTotal: number = 0;
    let olderCount: number = 0;
    let newerTotal: number = 0;
    let newerCount: number = 0;
    for (let index: number = start; index < measured.length; index += 1) {
      if (index < middle) {
        olderTotal += measured[index].rssi;
        olderCount += 1;
      } else {
        newerTotal += measured[index].rssi;
        newerCount += 1;
      }
    }
    const delta: number = newerTotal / newerCount - olderTotal / olderCount;
    if (delta >= 8) return FieldwatchRssiTrend.UP_FAST;
    if (delta >= 3) return FieldwatchRssiTrend.UP;
    if (delta <= -8) return FieldwatchRssiTrend.DOWN_FAST;
    if (delta <= -3) return FieldwatchRssiTrend.DOWN;
    return FieldwatchRssiTrend.FLAT;
  }
}

class FieldwatchCoTravelContext {
  public pathLengthMeters: number;
  public durationMs: number;
  public here: GpsSample | undefined;
  public ready: boolean;
  constructor(pathLengthMeters: number = 0, durationMs: number = 0, here: GpsSample | undefined = undefined, ready: boolean = false) {
    this.pathLengthMeters = pathLengthMeters; this.durationMs = durationMs; this.here = here; this.ready = ready;
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
   * 可能同行：该 BLE 设备在本机 GPS 轨迹附近持续出现；这是启发式筛选，不是跟踪确认。
   * 没有新鲜定位样本或轨迹不足时返回 false。
   */
  private movingWithYou(sighting: Sighting, now: number): boolean {
    if (sighting.kind !== RadioKind.BLE) return false;
    const context: FieldwatchCoTravelContext = this.coTravelContext;
    if (!context.ready || context.here === undefined) return false;
    if (now - context.here.at > 90000) return false;
    if (now - sighting.lastSeen > 90000 || sighting.rssi < -75) return false;
    const trail: RadioGpsSample[] = sighting.gpsTrail;
    if (trail.length < 2) return false;
    if (this.geo.radioTrailSpanMeters(trail) < 27 || this.geo.radioTrailLengthMeters(trail) < 27) return false;
    let loudCount: number = 0;
    trail.forEach((sample: RadioGpsSample): void => { if (sample.rssi >= -75) loudCount += 1; });
    if (loudCount < Math.floor((trail.length * 2 + 2) / 3)) return false;
    const last: RadioGpsSample = trail[trail.length - 1];
    const moved: number = this.geo.distanceCoordinates(context.here.latitude, context.here.longitude,
      last.latitude, last.longitude);
    const durationSeconds: number = Math.max(context.durationMs / 1000, 1);
    const speed: number = Math.min(context.pathLengthMeters / durationSeconds, 40);
    const allowedMeters: number = Math.max(50, speed * 15) + 25;
    return moved <= allowedMeters;
  }
  /** 由应用层在每次定位更新时喂入本机轨迹。 */
  setTravelSamples(samples: GpsSample[]): void {
    this.travelSamples = samples.slice();
    if (this.travelSamples.length < 2) {
      this.coTravelContext = new FieldwatchCoTravelContext();
      return;
    }
    const first: GpsSample = this.travelSamples[0];
    const last: GpsSample = this.travelSamples[this.travelSamples.length - 1];
    const pathLengthMeters: number = this.geo.pathLengthMeters(this.travelSamples);
    const durationMs: number = Math.max(last.at - first.at, 0);
    this.coTravelContext = new FieldwatchCoTravelContext(pathLengthMeters, durationMs, last, pathLengthMeters >= 45);
  }
  private travelSamples: GpsSample[] = [];
  private readonly geo: FieldwatchGeoService = new FieldwatchGeoService();
  private coTravelContext: FieldwatchCoTravelContext = new FieldwatchCoTravelContext();

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
  distanceCoordinates(firstLatitude: number, firstLongitude: number, secondLatitude: number, secondLongitude: number): number {
    const radius: number = 6371000;
    const latitudeDelta: number = (secondLatitude - firstLatitude) * Math.PI / 180;
    const longitudeDelta: number = (secondLongitude - firstLongitude) * Math.PI / 180;
    const firstLatitudeRadians: number = firstLatitude * Math.PI / 180;
    const secondLatitudeRadians: number = secondLatitude * Math.PI / 180;
    const halfChord: number = Math.sin(latitudeDelta / 2) * Math.sin(latitudeDelta / 2)
      + Math.cos(firstLatitudeRadians) * Math.cos(secondLatitudeRadians)
      * Math.sin(longitudeDelta / 2) * Math.sin(longitudeDelta / 2);
    return radius * 2 * Math.atan2(Math.sqrt(halfChord), Math.sqrt(1 - halfChord));
  }

  distanceMeters(first: GpsSample, second: GpsSample): number {
    return this.distanceCoordinates(first.latitude, first.longitude, second.latitude, second.longitude);
  }

  pathLengthMeters(samples: GpsSample[]): number {
    let total: number = 0;
    for (let index: number = 1; index < samples.length; index += 1) total += this.distanceMeters(samples[index - 1], samples[index]);
    return total;
  }

  radioTrailLengthMeters(samples: RadioGpsSample[]): number {
    let total: number = 0;
    for (let index: number = 1; index < samples.length; index += 1) {
      total += this.distanceCoordinates(samples[index - 1].latitude, samples[index - 1].longitude,
        samples[index].latitude, samples[index].longitude);
    }
    return total;
  }

  radioTrailSpanMeters(samples: RadioGpsSample[]): number {
    if (samples.length < 2) return 0;
    let minLatitude: number = samples[0].latitude;
    let maxLatitude: number = minLatitude;
    let minLongitude: number = samples[0].longitude;
    let maxLongitude: number = minLongitude;
    for (let index: number = 1; index < samples.length; index += 1) {
      const sample: RadioGpsSample = samples[index];
      minLatitude = Math.min(minLatitude, sample.latitude);
      maxLatitude = Math.max(maxLatitude, sample.latitude);
      minLongitude = Math.min(minLongitude, sample.longitude);
      maxLongitude = Math.max(maxLongitude, sample.longitude);
    }
    return this.distanceCoordinates(minLatitude, minLongitude, maxLatitude, maxLongitude);
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
