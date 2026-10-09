import { AppSettings, DecodedFieldValue, GpsSample, Sighting } from './FieldwatchModels';
import { FieldwatchPrivacyService } from './FieldwatchDomainService';

export class FieldwatchExportSerializer {
  private readonly privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();

  serializeCsv(sightings: Array<Sighting>, settings: AppSettings): string {
    // manufacturer 来自 OUI 名称库；与 MAPS/原版导出保持同一列序（紧随 name）。
    const lines: string[] = ['key,kind,address,name,manufacturer,rssi,seen_at,ssid,frequency_mhz,fresh,signatures,decoded'];
    sightings.forEach((sighting: Sighting): void => {
      lines.push(this.csvRow([
        sighting.key,
        sighting.kind,
        this.privacy.maskAddress(sighting.address, settings.privacyMode),
        sighting.name,
        sighting.facts.manufacturer,
        sighting.rssi.toString(),
        sighting.lastSeen.toString(),
        sighting.facts.ssid,
        sighting.facts.frequencyMhz.toString(),
        sighting.fresh ? 'true' : 'false',
        sighting.signatureIds.join('|'),
        this.decodedText(sighting)
      ]));
    });
    return lines.join('\n');
  }

  serializeJsonl(sightings: Array<Sighting>, settings: AppSettings): string {
    const lines: string[] = [];
    sightings.forEach((sighting: Sighting): void => {
      const address: string = this.privacy.maskAddress(sighting.address, settings.privacyMode);
      lines.push('{"key":"' + this.json(sighting.key) + '","kind":"' + sighting.kind + '","address":"' + this.json(address) + '","name":"' + this.json(sighting.name) + '","manufacturer":"' + this.json(sighting.facts.manufacturer) + '","rssi":' + sighting.rssi.toString() + ',"seenAt":' + sighting.lastSeen.toString() + ',"fresh":' + sighting.fresh.toString() + ',"signatures":' + this.jsonArray(sighting.signatureIds) + ',"decoded":' + this.jsonDecoded(sighting) + '}');
    });
    return lines.join('\n');
  }

  serializeGpx(sightings: Array<Sighting>, settings: AppSettings): string {
    const points: string[] = [];
    sightings.forEach((sighting: Sighting): void => {
      if (sighting.location !== undefined) points.push(this.gpxPoint(sighting.location, sighting, settings));
    });
    return '<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="Airwave Footprints"><trk><name>Airwave Footprints observations</name><trkseg>' + points.join('') + '</trkseg></trk></gpx>';
  }

  serializeKml(sightings: Array<Sighting>, settings: AppSettings): string {
    const points: string[] = [];
    sightings.forEach((sighting: Sighting): void => {
      if (sighting.location !== undefined) points.push(this.kmlPoint(sighting.location, sighting, settings));
    });
    return '<?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document>' + points.join('') + '</Document></kml>';
  }

  serializeWigle(sightings: Array<Sighting>, settings: AppSettings): string {
    const lines: string[] = ['WigleWifi-1.4,appRelease=Airwave Footprints'];
    sightings.forEach((sighting: Sighting): void => {
      if (sighting.kind === 'wifi') lines.push(this.csvRow(['WIFI', sighting.facts.ssid, this.privacy.maskAddress(sighting.address, settings.privacyMode), sighting.facts.frequencyMhz.toString(), sighting.rssi.toString()]));
    });
    return lines.join('\n');
  }

  private csvRow(values: Array<string>): string {
    return values.map((value: string): string => '"' + value.replace(/"/g, '""') + '"').join(',');
  }

  /** 解码字段与签名共用同一结果：详情、Live、Debrief 和导出不会各自再算一遍。 */
  private decodedText(sighting: Sighting): string {
    const parts: string[] = [];
    sighting.decodedFields.forEach((value: DecodedFieldValue): void => { parts.push(value.label + '=' + value.text); });
    return parts.join('|');
  }

  private jsonArray(values: string[]): string {
    const parts: string[] = [];
    values.forEach((value: string): void => { parts.push('"' + this.json(value) + '"'); });
    return '[' + parts.join(',') + ']';
  }

  private jsonDecoded(sighting: Sighting): string {
    const parts: string[] = [];
    sighting.decodedFields.forEach((value: DecodedFieldValue): void => {
      parts.push('{"field":"' + this.json(value.fieldId) + '","label":"' + this.json(value.label) + '","text":"' + this.json(value.text) + '","unit":"' + this.json(value.unit) + '"}');
    });
    return '[' + parts.join(',') + ']';
  }

  private json(value: string): string { return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n'); }
  private gpxPoint(location: GpsSample, sighting: Sighting, settings: AppSettings): string { return '<trkpt lat="' + location.latitude.toFixed(settings.privacyMode ? 2 : 6) + '" lon="' + location.longitude.toFixed(settings.privacyMode ? 2 : 6) + '"><name>' + this.xml(sighting.name) + '</name></trkpt>'; }
  private kmlPoint(location: GpsSample, sighting: Sighting, settings: AppSettings): string { return '<Placemark><name>' + this.xml(sighting.name) + '</name><Point><coordinates>' + location.longitude.toFixed(settings.privacyMode ? 2 : 6) + ',' + location.latitude.toFixed(settings.privacyMode ? 2 : 6) + ',0</coordinates></Point></Placemark>'; }
  private xml(value: string): string { return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
}
