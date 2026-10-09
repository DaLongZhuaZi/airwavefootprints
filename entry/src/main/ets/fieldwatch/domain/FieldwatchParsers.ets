import { RadioKind, ServiceDataRecord } from './FieldwatchModels';

export class FieldwatchParseResult {
  public protocol: string;
  public valid: boolean;
  public fields: Map<string, string>;
  constructor(protocol: string, valid: boolean = false) {
    this.protocol = protocol;
    this.valid = valid;
    this.fields = new Map<string, string>();
  }
}

export interface BleAdvertisementParser {
  parse(hex: string): FieldwatchParseResult;
}

export interface WifiInformationElementParser {
  parse(hex: string): FieldwatchParseResult;
}

export class FieldwatchBleAdvertisementParser implements BleAdvertisementParser {
  parse(hex: string): FieldwatchParseResult {
    const normalized: string = hex.replace(/:/g, '');
    const result: FieldwatchParseResult = new FieldwatchParseResult('ble_advertisement', this.isHex(normalized));
    if (!result.valid) return result;
    let cursor: number = 0;
    let adCount: number = 0;
    while (cursor < normalized.length) {
      if (normalized.length - cursor < 2) return this.invalid(result, 'truncated_length');
      const length: number = parseInt(normalized.substring(cursor, cursor + 2), 16);
      cursor += 2;
      if (length === 0) break;
      const recordEnd: number = cursor + length * 2;
      if (recordEnd > normalized.length || length < 1) return this.invalid(result, 'truncated_ad');
      const adType: number = parseInt(normalized.substring(cursor, cursor + 2), 16);
      const payload: string = normalized.substring(cursor + 2, recordEnd);
      result.fields.set('ad.' + adCount.toString() + '.type', adType.toString(16).toUpperCase());
      result.fields.set('ad.' + adCount.toString() + '.payloadLength', Math.floor(payload.length / 2).toString());
      if (adType === 0x08 || adType === 0x09) result.fields.set('localNameHex', payload);
      if (adType === 0x16 && payload.length >= 4) {
        const serviceUuid: string = payload.substring(2, 4) + payload.substring(0, 2);
        result.fields.set('serviceUuid', serviceUuid.toUpperCase());
      }
      if (adType === 0xFF && payload.length >= 4) result.fields.set('manufacturerCompanyId', (payload.substring(2, 4) + payload.substring(0, 2)).toUpperCase());
      adCount += 1;
      cursor = recordEnd;
    }
    result.fields.set('adCount', adCount.toString());
    result.fields.set('byteLength', Math.floor(normalized.length / 2).toString());
    result.fields.set('radio', RadioKind.BLE);
    return result;
  }

  private invalid(result: FieldwatchParseResult, reason: string): FieldwatchParseResult {
    result.valid = false;
    result.fields.set('error', reason);
    return result;
  }

  private isHex(value: string): boolean {
    return value.length > 0 && value.length % 2 === 0 && /^[0-9A-Fa-f]+$/.test(value);
  }
}

export class FieldwatchWifiInformationElementParser implements WifiInformationElementParser {
  parse(hex: string): FieldwatchParseResult {
    const normalized: string = hex.replace(/:/g, '');
    const result: FieldwatchParseResult = new FieldwatchParseResult('wifi_ie', this.isHex(normalized));
    if (!result.valid) return result;
    let cursor: number = 0;
    let ieCount: number = 0;
    while (cursor < normalized.length) {
      if (normalized.length - cursor < 4) { result.valid = false; return result; }
      const elementId: number = parseInt(normalized.substring(cursor, cursor + 2), 16);
      const elementLength: number = parseInt(normalized.substring(cursor + 2, cursor + 4), 16);
      const next: number = cursor + 4 + elementLength * 2;
      if (next > normalized.length) { result.valid = false; return result; }
      result.fields.set('ie.' + ieCount.toString() + '.id', elementId.toString());
      result.fields.set('ie.' + ieCount.toString() + '.length', elementLength.toString());
      ieCount += 1;
      cursor = next;
    }
    result.fields.set('ieCount', ieCount.toString());
    result.fields.set('byteLength', Math.floor(normalized.length / 2).toString());
    result.fields.set('radio', RadioKind.WIFI);
    return result;
  }

  private isHex(value: string): boolean {
    return value.length === 0 || value.length % 2 === 0 && /^[0-9A-Fa-f]+$/.test(value);
  }
}

export class FieldwatchFastPairParser implements BleAdvertisementParser {
  parse(hex: string): FieldwatchParseResult {
    const advertisement: FieldwatchParseResult = new FieldwatchBleAdvertisementParser().parse(hex);
    const result: FieldwatchParseResult = new FieldwatchParseResult('fast_pair', advertisement.valid && advertisement.fields.get('serviceUuid') === 'FE2C');
    if (!result.valid && this.isFastPair(hex)) result.valid = true;
    if (result.valid) result.fields.set('service', '0xFE2C');
    return result;
  }

  private isFastPair(value: string): boolean {
    return value.toUpperCase().indexOf('FE2C') >= 0;
  }
}

export class FieldwatchDultParser implements BleAdvertisementParser {
  parse(hex: string): FieldwatchParseResult {
    const advertisement: FieldwatchParseResult = new FieldwatchBleAdvertisementParser().parse(hex);
    const result: FieldwatchParseResult = new FieldwatchParseResult('dult', advertisement.valid && advertisement.fields.get('serviceUuid') === 'FCD2');
    if (!result.valid) result.valid = hex.toUpperCase().indexOf('FCD2') >= 0 || hex.toUpperCase().indexOf('D2FC') >= 0;
    if (result.valid) result.fields.set('service', 'DULT');
    return result;
  }
}



/** 结构化 BLE 广播事实：直接服务签名规则的 MANUFACTURER_DATA / SERVICE_DATA / SERVICE_UUID / NAME 匹配。 */
export class BleAdvertisementFacts {
  public valid: boolean = false;
  public error: string = '';
  public adCount: number = 0;
  public byteLength: number = 0;
  public localName: string = '';
  public serviceUuids: string[] = [];
  public manufacturerId: number = 0;
  public manufacturerDataHex: string = '';
  public serviceData: ServiceDataRecord[] = [];
  public flags: number = -1;
  /** 声明的发射功率；-128 表示广播里未携带这一项（不要用 0 当默认，0 dBm 是合法值）。 */
  public txPower: number = -128;
  /** GAP Appearance（AD type 0x19）；-1 表示未携带。设备用它声明「我是什么」。 */
  public appearance: number = -1;
  /**
   * 经典蓝牙 Class of Device（AD type 0x0D 的三字节，小端）；-1 表示未携带。
   *
   * 双模芯片会在 BLE 广播里捎带它，用来声明「我同时是哪种经典蓝牙设备」
   * （耳机 / 音箱 / 电脑…）。原版详情页据此显示「经典蓝牙类别」。
   */
  public deviceClass: number = -1;
  /**
   * **全部**厂商数据记录。
   *
   * 广播里可以出现多条 AD 0xFF（不同 Company ID），此前只保留最后一条 ——
   * 原版按记录逐条展示（「广播中的厂商数据」段可以有多块）。
   */
  public mfgRecords: ServiceDataRecord[] = [];
}

function hexOfBytes(bytes: Uint8Array): string {
  let result: string = '';
  for (let index = 0; index < bytes.length; index += 1) {
    const value: string = bytes[index].toString(16).toUpperCase();
    result += value.length === 1 ? '0' + value : value;
  }
  return result;
}

function bytesOfHex(hex: string): Uint8Array {
  const normalized: string = hex.replace(/:/g, '');
  const length: number = Math.floor(normalized.length / 2);
  const bytes: Uint8Array = new Uint8Array(length);
  for (let index = 0; index < length; index += 1) {
    const parsed: number = parseInt(normalized.substring(index * 2, index * 2 + 2), 16);
    bytes[index] = Number.isNaN(parsed) ? 0 : parsed;
  }
  return bytes;
}

/**
 * 按蓝牙 Core Spec 的 AD 结构（length + type + payload）解码广播包。
 * 覆盖 Flags、16/32/128 位 Service UUID、Local Name、TX Power、Service Data 和 Manufacturer Specific Data。
 */
export class FieldwatchBleAdvertisementDecoder {
  decode(rawHex: string): BleAdvertisementFacts {
    const facts: BleAdvertisementFacts = new BleAdvertisementFacts();
    const normalized: string = rawHex.replace(/:/g, '');
    if (normalized.length === 0 || normalized.length % 2 !== 0 || !/^[0-9A-Fa-f]+$/.test(normalized)) {
      facts.error = 'invalid_hex';
      return facts;
    }
    const bytes: Uint8Array = bytesOfHex(normalized);
    facts.byteLength = bytes.length;
    let cursor: number = 0;
    while (cursor < bytes.length) {
      const length: number = bytes[cursor];
      cursor += 1;
      if (length === 0) break;
      if (cursor + length > bytes.length) {
        facts.error = 'truncated_ad';
        return facts;
      }
      const adType: number = bytes[cursor];
      const payload: Uint8Array = bytes.slice(cursor + 1, cursor + length);
      this.applyAd(facts, adType, payload);
      facts.adCount += 1;
      cursor += length;
    }
    facts.valid = true;
    return facts;
  }

  decodeBytes(raw: Uint8Array): BleAdvertisementFacts {
    return this.decode(hexOfBytes(raw));
  }

  private applyAd(facts: BleAdvertisementFacts, adType: number, payload: Uint8Array): void {
    if (adType === 0x01 && payload.length >= 1) {
      facts.flags = payload[0];
      return;
    }
    if (adType === 0x08 || adType === 0x09) {
      let name: string = '';
      for (let index = 0; index < payload.length; index += 1) name += String.fromCharCode(payload[index]);
      if (name.length > 0) facts.localName = name;
      return;
    }
    // AD type 0x0D：Class of Device（3 字节，小端 24 位）。
    // 双模芯片用它声明经典蓝牙身份，BLE-only 设备不会带。
    if (adType === 0x0D && payload.length >= 3) {
      facts.deviceClass = payload[0] | (payload[1] << 8) | (payload[2] << 16);
      return;
    }
    if (adType === 0x0A && payload.length >= 1) {
      facts.txPower = payload[0] > 127 ? payload[0] - 256 : payload[0];
      return;
    }
    // AD type 0x19：GAP Appearance。设备自己声明的「我看起来是什么」，
    // 与 OUI/签名都无关 —— 是设备主动告诉世界的自我描述。
    if (adType === 0x19 && payload.length >= 2) {
      facts.appearance = payload[0] | (payload[1] << 8);
      return;
    }
    if (adType === 0x02 || adType === 0x03) {
      for (let index = 0; index + 1 < payload.length; index += 2) {
        const uuid: string = hexOfBytes(payload.slice(index, index + 2));
        facts.serviceUuids.push(uuid.substring(2, 4) + uuid.substring(0, 2));
      }
      return;
    }
    if (adType === 0x04 || adType === 0x05) {
      for (let index = 0; index + 3 < payload.length; index += 4) facts.serviceUuids.push(hexOfBytes(payload.slice(index, index + 4)).split('').reverse().join(''));
      return;
    }
    if (adType === 0x06 || adType === 0x07) {
      for (let index = 0; index + 15 < payload.length; index += 16) {
        let uuid: string = '';
        for (let inner = 15; inner >= 0; inner -= 1) {
          const value: string = payload[index + inner].toString(16).toUpperCase();
          uuid += value.length === 1 ? '0' + value : value;
        }
        facts.serviceUuids.push(uuid);
      }
      return;
    }
    if (adType === 0x16 && payload.length >= 3) {
      const uuid: string = hexOfBytes(payload.slice(0, 2));
      const serviceUuid: string = uuid.substring(2, 4) + uuid.substring(0, 2);
      facts.serviceData.push(new ServiceDataRecord(serviceUuid, hexOfBytes(payload.slice(2))));
      if (facts.serviceUuids.indexOf(serviceUuid) < 0) facts.serviceUuids.push(serviceUuid);
      return;
    }
    if (adType === 0x20 && payload.length >= 5) {
      const uuid: string = hexOfBytes(payload.slice(0, 4)).split('').reverse().join('');
      facts.serviceData.push(new ServiceDataRecord(uuid, hexOfBytes(payload.slice(4))));
      if (facts.serviceUuids.indexOf(uuid) < 0) facts.serviceUuids.push(uuid);
      return;
    }
    if (adType === 0x21 && payload.length >= 17) {
      let uuid: string = '';
      for (let inner = 15; inner >= 0; inner -= 1) {
        const value: string = payload[inner].toString(16).toUpperCase();
        uuid += value.length === 1 ? '0' + value : value;
      }
      facts.serviceData.push(new ServiceDataRecord(uuid, hexOfBytes(payload.slice(16))));
      if (facts.serviceUuids.indexOf(uuid) < 0) facts.serviceUuids.push(uuid);
      return;
    }
    if (adType === 0xFF && payload.length >= 3) {
      const companyId: number = payload[0] + payload[1] * 256;
      const body: string = hexOfBytes(payload.slice(2));
      // **每一条 0xFF 都收进 mfgRecords**：广播里可以有多条（不同 Company ID），
      // 原版按记录逐条展示。此前只留第一条，后面的直接被丢掉。
      // ServiceDataRecord 复用在这里只是「uuid 位放公司 ID、dataHex 放载荷」的载体。
      facts.mfgRecords.push(new ServiceDataRecord(companyId.toString(16).toUpperCase().padStart(4, '0'), body));
      if (facts.manufacturerId === 0) {
        facts.manufacturerId = companyId;
        facts.manufacturerDataHex = body;
      }
      return;
    }
  }
}

export class FieldwatchOpenDroneIdParser implements BleAdvertisementParser {
  parse(hex: string): FieldwatchParseResult {
    const advertisement: FieldwatchParseResult = new FieldwatchBleAdvertisementParser().parse(hex);
    const result: FieldwatchParseResult = new FieldwatchParseResult('open_drone_id', advertisement.valid && advertisement.fields.get('serviceUuid') === 'FFFA');
    if (!result.valid) result.valid = hex.toUpperCase().indexOf('FFFA') >= 0 || hex.toUpperCase().indexOf('FAFF') >= 0;
    if (result.valid) result.fields.set('service', 'OpenDroneID');
    return result;
  }
}
