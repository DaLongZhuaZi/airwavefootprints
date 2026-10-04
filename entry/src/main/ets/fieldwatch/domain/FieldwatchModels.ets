export enum RadioKind { WIFI = 'wifi', BLE = 'ble' }
export enum SignatureClass { FINDER = 'finder', BEACON = 'beacon', DRONE = 'drone', ROUTER = 'router', OTHER = 'other' }
export enum FilterLogic { AND = 'and', OR = 'or' }
export enum ScanState { IDLE = 'idle', SCANNING = 'scanning', PAUSED = 'paused', ERROR = 'error' }

export class GpsSample {
  public latitude: number;
  public longitude: number;
  public at: number;
  constructor(latitude: number, longitude: number, at: number) { this.latitude = latitude; this.longitude = longitude; this.at = at; }
}

export class RadioFacts {
  public ssid: string;
  public manufacturer: string;
  public frequencyMhz: number;
  public serviceUuids: string[];
  public manufacturerDataHex: string;
  constructor(ssid: string = '', manufacturer: string = '', frequencyMhz: number = 0, serviceUuids: string[] = [], manufacturerDataHex: string = '') {
    this.ssid = ssid; this.manufacturer = manufacturer; this.frequencyMhz = frequencyMhz; this.serviceUuids = serviceUuids; this.manufacturerDataHex = manufacturerDataHex;
  }
}

export class ScanObservation {
  public key: string; public kind: RadioKind; public address: string; public name: string; public rssi: number; public seenAt: number; public facts: RadioFacts; public location: GpsSample | undefined;
  constructor(key: string, kind: RadioKind, address: string, name: string, rssi: number, seenAt: number, facts: RadioFacts = new RadioFacts(), location: GpsSample | undefined = undefined) {
    this.key = key; this.kind = kind; this.address = address; this.name = name; this.rssi = rssi; this.seenAt = seenAt; this.facts = facts; this.location = location;
  }
}

export class SignatureDefinition {
  public id: string; public name: string; public kind: RadioKind; public category: SignatureClass; public matchText: string; public extraAttention: boolean; public stock: boolean;
  constructor(id: string, name: string, kind: RadioKind, category: SignatureClass, matchText: string, extraAttention: boolean = false, stock: boolean = true) {
    this.id = id; this.name = name; this.kind = kind; this.category = category; this.matchText = matchText; this.extraAttention = extraAttention; this.stock = stock;
  }
}

export class Sighting {
  public key: string;
  public kind: RadioKind;
  public address: string;
  public name: string;
  public rssi: number;
  public facts: RadioFacts;
  public location: GpsSample | undefined;
  public firstSeen: number; public lastSeen: number; public count: number = 1; public signatureIds: string[] = [];
  constructor(key: string, kind: RadioKind, address: string, name: string, rssi: number, seenAt: number, facts: RadioFacts, location: GpsSample | undefined = undefined) {
    this.key = key; this.kind = kind; this.address = address; this.name = name; this.rssi = rssi; this.facts = facts; this.location = location; this.firstSeen = seenAt; this.lastSeen = seenAt;
  }
  static fromObservation(observation: ScanObservation): Sighting { return new Sighting(observation.key, observation.kind, observation.address, observation.name, observation.rssi, observation.seenAt, observation.facts, observation.location); }
  ingest(observation: ScanObservation): void { this.rssi = observation.rssi; this.lastSeen = observation.seenAt; this.count += 1; if (observation.name.length > 0) this.name = observation.name; this.facts = observation.facts; if (observation.location !== undefined) this.location = observation.location; }
}

export class WatchTarget { public deviceKey: string; public signatureId: string; public label: string; public alert: boolean; constructor(deviceKey: string = '', signatureId: string = '', label: string = '', alert: boolean = true) { this.deviceKey = deviceKey; this.signatureId = signatureId; this.label = label; this.alert = alert; } }
export class FilterDefinition { public logic: FilterLogic = FilterLogic.AND; public radioKind: RadioKind | undefined = undefined; public minimumRssi: number | undefined = undefined; public signatureId: string = ''; public watchedOnly: boolean = false; public attentionOnly: boolean = false; }
export class AppSettings { public displayPaused: boolean = false; public darkMode: boolean = true; public keepScreenOn: boolean = false; public locationTagging: boolean = false; public privacyMode: boolean = false; public scanIntensity: string = 'balanced'; }
export class LogEntry { public id: string; public observation: ScanObservation; public signatureIds: string[]; constructor(id: string, observation: ScanObservation, signatureIds: string[] = []) { this.id = id; this.observation = observation; this.signatureIds = signatureIds; } }
export class SitSummary { public id: string; public name: string; public startedAt: number; public endedAt: number; public radioCount: number; constructor(id: string, name: string, startedAt: number, endedAt: number = 0, radioCount: number = 0) { this.id = id; this.name = name; this.startedAt = startedAt; this.endedAt = endedAt; this.radioCount = radioCount; } }
export class SitFile { public summary: SitSummary; public radios: Sighting[]; public path: GpsSample[]; constructor(summary: SitSummary, radios: Sighting[] = [], path: GpsSample[] = []) { this.summary = summary; this.radios = radios; this.path = path; } }
