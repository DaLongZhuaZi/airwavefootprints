import { AppSettings, FilterDefinition, FilterLogic, GpsSample, RadioKind, ScanObservation, SignatureDefinition, Sighting, WatchTarget } from './FieldwatchModels';

export class FieldwatchSignatureEngine {
  match(observation: ScanObservation, signatures: SignatureDefinition[]): string[] {
    const haystack: string = (observation.name + ' ' + observation.address + ' ' + observation.facts.ssid + ' ' + observation.facts.manufacturer + ' ' + observation.facts.manufacturerDataHex).toLowerCase();
    const result: string[] = [];
    signatures.forEach((signature: SignatureDefinition): void => {
      if (signature.kind === observation.kind && (signature.matchText.length === 0 || haystack.indexOf(signature.matchText.toLowerCase()) >= 0)) result.push(signature.id);
    });
    return result;
  }
}

export class FieldwatchFilterEngine {
  pass(sighting: Sighting, filter: FilterDefinition, signatures: SignatureDefinition[], watched: WatchTarget[]): boolean {
    const checks: boolean[] = [];
    if (filter.radioKind !== undefined) checks.push(sighting.kind === filter.radioKind);
    if (filter.minimumRssi !== undefined) checks.push(sighting.rssi >= filter.minimumRssi);
    if (filter.signatureId.length > 0) checks.push(sighting.signatureIds.indexOf(filter.signatureId) >= 0);
    if (filter.watchedOnly) checks.push(watched.some((target: WatchTarget): boolean => target.alert && target.deviceKey === sighting.key));
    if (filter.attentionOnly) checks.push(sighting.signatureIds.some((id: string): boolean => signatures.some((signature: SignatureDefinition): boolean => signature.id === id && signature.extraAttention)));
    if (checks.length === 0) return true;
    return filter.logic === FilterLogic.OR ? checks.some((value: boolean): boolean => value) : checks.every((value: boolean): boolean => value);
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
    if (location === undefined) return 'Unavailable';
    const digits: number = enabled ? 2 : 6;
    return location.latitude.toFixed(digits) + ', ' + location.longitude.toFixed(digits);
  }

  describe(sighting: Sighting, settings: AppSettings): string {
    return sighting.name + ' · ' + this.maskAddress(sighting.address, settings.privacyMode) + ' · ' + this.maskLocation(sighting.location, settings.privacyMode);
  }
}

export function radioKindLabel(kind: RadioKind): string {
  return kind === RadioKind.BLE ? 'BLE' : 'Wi-Fi';
}
