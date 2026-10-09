import { describe, it, expect } from '@ohos/hypium';
import { AppSettings, DecodedFieldValue, FilterDefinition, GpsSample, RadioFacts, RadioKind, ScanObservation, ServiceDataRecord, Sighting, SignatureClass, WatchTarget } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { FieldwatchFilterEngine } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';
import { BleAdvertisementFacts, FieldwatchBleAdvertisementDecoder } from '../main/ets/fieldwatch/domain/FieldwatchParsers';
import { FieldwatchExportSerializer } from '../main/ets/fieldwatch/domain/FieldwatchExportSerializer';
import { buildRadarPoints, FieldwatchRadarPoint, liveDecodeLabels, matchedSignatureNames, signatureColorAt, signatureColorIndex, signatureHitCounts, SignatureSortMode, sortSignatureFleets } from '../main/ets/fieldwatch/ui/FieldwatchUiState';
import {
  SIGNATURE_PACK_FORMAT, SignatureDecodeEndian, SignatureDecodeField, SignatureDecodeSource, SignatureDecodeType,
  SignatureDecodeWhen, SignatureDecodeWhenOp, SignatureFleet, SignatureFleetDecode, SignaturePack, SignatureRule, SignatureRuleKind,
  signatureClassOf, signatureHexOnly, signatureUuidAliases, cloneSignatureFleet, signatureRadioKindOf
} from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels';
import {
  SignaturePackError, encodeSignaturePack, mergeSignatureFleets, overlayStockFleets, parseSignaturePack, signatureRuleKey
} from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureCatalog';
import {
  FieldwatchSignatureEngine, FieldwatchSignatureFieldDecoder, SignatureMatchContext, SignatureMatchExplanation
} from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine';

function contextOf(kind: RadioKind, address: string, name: string): SignatureMatchContext {
  const context: SignatureMatchContext = new SignatureMatchContext();
  context.key = kind + ':' + address;
  context.kind = kind;
  context.address = address;
  context.name = name;
  context.lastSeen = 1000;
  return context;
}

function samplePack(): string {
  return '{\n' +
    '  "format": "fieldwatch-signatures",\n' +
    '  "formatVersion": 1,\n' +
    '  "catalogVersion": 88,\n' +
    '  "unknownTopLevelKey": {"ignored": true},\n' +
    '  "fleets": [\n' +
    '    {\n' +
    '      "id": "fleet-finder",\n' +
    '      "name": "Find Hub",\n' +
    '      "kind": "FINDER",\n' +
    '      "builtIn": true,\n' +
    '      "matchAny": true,\n' +
    '      "colorIndex": 3,\n' +
    '      "rules": [\n' +
    '        {"kind": "SERVICE_UUID", "text": "FE2C", "companyId": 0, "dataPrefixHex": "", "radio": "BLE", "enabled": true}\n' +
    '      ],\n' +
    '      "decode": {\n' +
    '        "source": "manufacturerData",\n' +
    '        "companyId": 76,\n' +
    '        "fields": [\n' +
    '          {"id": "state", "label": "State", "offset": 0, "length": 1, "type": "u8", "endian": "le", "enum": {"0": "Idle", "1": "Pairing"}, "live": true, "liveEmphasis": ["1"]}\n' +
    '        ]\n' +
    '      }\n' +
    '    },\n' +
    '    {\n' +
    '      "id": "fleet-future",\n' +
    '      "name": "Future source",\n' +
    '      "kind": "OTHER",\n' +
    '      "rules": [{"kind": "OUI", "text": "00:11:22", "radio": "WIFI", "enabled": true}],\n' +
    '      "decode": {"source": "someFutureSource", "fields": []}\n' +
    '    }\n' +
    '  ]\n' +
    '}';
}

export default function fieldwatchSignatureTest() {
  describe('FieldwatchSignature', () => {
    // 回归：星闪规则此前无法在「保存 → 加载」中存活 ——
    // 序列化把它写成 'BLE'，解析器又不认 'NEARLINK'，
    // 结果一条星闪规则要么变成 BLE 规则，要么变成「任意种类」。
    it('round-trips a NEARLINK signature rule without changing its radio', 0, () => {
      expect(signatureRadioKindOf('NEARLINK')).assertEqual(RadioKind.NEARLINK);
      expect(signatureRadioKindOf('nearlink')).assertEqual(RadioKind.NEARLINK);
      const nl: SignatureRule = new SignatureRule(SignatureRuleKind.RADIO_KIND, '', 0, '', RadioKind.NEARLINK, true);
      const wifi: SignatureRule = new SignatureRule(SignatureRuleKind.RADIO_KIND, '', 0, '', RadioKind.WIFI, true);
      const ble: SignatureRule = new SignatureRule(SignatureRuleKind.RADIO_KIND, '', 0, '', RadioKind.BLE, true);
      const any: SignatureRule = new SignatureRule(SignatureRuleKind.RADIO_KIND, '', 0, '', undefined, true);
      expect(nl.radioTag()).assertEqual('NEARLINK');
      expect(wifi.radioTag()).assertEqual('WIFI');
      expect(ble.radioTag()).assertEqual('BLE');
      expect(any.radioTag()).assertEqual('');
      // 三种种类必须产生三个不同的身份键，否则去重会把它们当成同一条规则。
      const keys: string[] = [signatureRuleKey(nl), signatureRuleKey(wifi), signatureRuleKey(ble)];
      expect(keys[0] === keys[1]).assertFalse();
      expect(keys[0] === keys[2]).assertFalse();
      expect(keys[1] === keys[2]).assertFalse();
    });

    // 星闪规则只能命中星闪信号源，不能连 BLE 一起命中。
    it('does not let a NEARLINK rule match a BLE radio', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const rule: SignatureRule = new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'nl-device', 0, '', RadioKind.NEARLINK, true);
      const fleet: SignatureFleet = new SignatureFleet('sig-nl', 'nl', SignatureClass.OTHER, [rule]);
      const bleContext: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'nl-device');
      const nlContext: SignatureMatchContext = contextOf(RadioKind.NEARLINK, '11:22:33:44:55:66', 'nl-device');
      // explain() 返回命中列表；星闪规则只应在星闪上下文里出现。
      const bleHits: SignatureMatchExplanation[] = engine.explain(bleContext, [fleet]);
      const nlHits: SignatureMatchExplanation[] = engine.explain(nlContext, [fleet]);
      expect(bleHits.length).assertEqual(0);
      expect(nlHits.length).assertEqual(1);
      expect(nlHits[0].fleetId).assertEqual('sig-nl');
    });
    it('parses a signature pack and ignores unknown keys', 0, () => {
      const parsed = parseSignaturePack(samplePack());
      expect(parsed.error).assertEqual(SignaturePackError.NONE);
      expect(parsed.pack.catalogVersion).assertEqual(88);
      expect(parsed.pack.fleets.length).assertEqual(2);
      const finder: SignatureFleet = parsed.pack.fleets[0];
      expect(finder.id).assertEqual('fleet-finder');
      expect(finder.category).assertEqual(SignatureClass.FINDER);
      expect(finder.builtIn).assertTrue();
      expect(finder.rules.length).assertEqual(1);
      expect(finder.rules[0].kind).assertEqual(SignatureRuleKind.SERVICE_UUID);
      expect(finder.rules[0].radio).assertEqual(RadioKind.BLE);
      const decode: SignatureFleetDecode = finder.decode as SignatureFleetDecode;
      expect(decode.source).assertEqual(SignatureDecodeSource.MANUFACTURER_DATA);
      expect(decode.companyId).assertEqual(76);
      expect(decode.fields[0].type).assertEqual(SignatureDecodeType.U8);
      expect(decode.fields[0].live).assertTrue();
      expect((decode.fields[0].enumLabels as Map<string, string>).get('1')).assertEqual('Pairing');
    });

    it('parses a pack that uses explicit nulls like the Kotlin serializer', 0, () => {
      // stock 目录里有 437 个 "radio": null 和上千个 length/scale/unit/when: null；
      // 只判 undefined 会让整包解析抛异常并让特征库为空。
      const text: string = '{\n' +
        '  "format": "fieldwatch-signatures",\n' +
        '  "formatVersion": 1,\n' +
        '  "exportedAt": null,\n' +
        '  "appVersion": null,\n' +
        '  "catalogVersion": 88,\n' +
        '  "fleets": [{\n' +
        '    "id": "fleet-null",\n' +
        '    "name": "Null shaped",\n' +
        '    "enabled": true,\n' +
        '    "matchAny": true,\n' +
        '    "colorIndex": 3,\n' +
        '    "rules": [\n' +
        '      {"kind": "OUI", "text": "00:11:22", "companyId": 0, "dataPrefixHex": "", "radio": "WIFI", "enabled": true},\n' +
        '      {"kind": "MANUFACTURER_DATA", "text": "", "companyId": null, "dataPrefixHex": "0215", "radio": null, "enabled": true}\n' +
        '    ],\n' +
        '    "minPeers": 0,\n' +
        '    "peerWindowSec": null,\n' +
        '    "clusterByOui": null,\n' +
        '    "sequentialMac": null,\n' +
        '    "notes": null,\n' +
        '    "attentionNote": null,\n' +
        '    "builtIn": true,\n' +
        '    "kind": "CAMERA",\n' +
        '    "decode": {\n' +
        '      "source": "manufacturerData",\n' +
        '      "serviceUuid": null,\n' +
        '      "companyId": null,\n' +
        '      "includeCompanyId": null,\n' +
        '      "fields": [\n' +
        '        {"id": "state", "label": "State", "offset": 0, "length": null, "type": "u8", "endian": null,\n' +
        '         "bitOffset": null, "bitWidth": null, "scale": null, "offsetAdd": null, "modulo": null,\n' +
        '         "unit": null, "enum": {"1": "Pairing"}, "live": true, "liveEmphasis": null, "enumNotes": null,\n' +
        '         "when": {"offset": 0, "length": null, "op": "eq", "valueHex": "01", "and": null}},\n' +
        '        {"id": "battery", "label": "Battery", "offset": 1, "length": null, "type": "u8", "endian": null,\n' +
        '         "bitOffset": null, "bitWidth": null, "scale": 2, "offsetAdd": null, "modulo": null, "unit": "%",\n' +
        '         "enum": null, "live": null, "liveEmphasis": null, "enumNotes": null, "when": null}\n' +
        '      ]\n' +
        '    }\n' +
        '  }]\n' +
        '}';
      const parsed = parseSignaturePack(text);
      expect(parsed.error).assertEqual(SignaturePackError.NONE);
      expect(parsed.pack.fleets.length).assertEqual(1);
      const fleet: SignatureFleet = parsed.pack.fleets[0];
      expect(fleet.category).assertEqual(SignatureClass.CAMERA);
      expect(fleet.peerWindowSec).assertEqual(60);
      expect(fleet.attentionNote).assertEqual('');
      expect(fleet.rules[1].radio === undefined).assertTrue();
      expect(fleet.rules[1].companyId).assertEqual(0);
      const decode: SignatureFleetDecode = fleet.decode as SignatureFleetDecode;
      expect(decode.companyId).assertEqual(0);
      expect(decode.includeCompanyId).assertFalse();
      expect(decode.fields[0].length).assertEqual(0);
      expect(decode.fields[0].endian).assertEqual(SignatureDecodeEndian.LE);
      expect(decode.fields[0].bitOffset).assertEqual(-1);
      expect(decode.fields[0].scale === undefined).assertTrue();
      expect(decode.fields[0].unit).assertEqual('');
      expect((decode.fields[0].enumLabels as Map<string, string>).get('1')).assertEqual('Pairing');
      const gate = decode.fields[0].gate as SignatureDecodeWhen;
      expect(gate.op).assertEqual(SignatureDecodeWhenOp.EQ);
      expect(gate.length).assertEqual(1);
      expect(gate.and === undefined).assertTrue();
      expect(decode.fields[1].scale).assertEqual(2);
      expect(decode.fields[1].unit).assertEqual('%');

      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Null shaped');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '0107';
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(2);
      expect(values[0].text).assertEqual('Pairing');
      expect(values[1].text).assertEqual('14 %');
    });

    it('drops unknown decode sources but keeps the signature', 0, () => {
      const parsed = parseSignaturePack(samplePack());
      expect(parsed.skippedDecode).assertEqual(1);
      const future: SignatureFleet = parsed.pack.fleets[1];
      expect(future.decode === undefined).assertTrue();
      expect(future.rules.length).assertEqual(1);
    });

    it('rejects empty, malformed and wrong-format packs', 0, () => {
      expect(parseSignaturePack('   ').error).assertEqual(SignaturePackError.EMPTY);
      expect(parseSignaturePack('{ not json').error).assertEqual(SignaturePackError.MALFORMED);
      expect(parseSignaturePack('{"format":"other","fleets":[{"id":"a","rules":[]}]}').error).assertEqual(SignaturePackError.WRONG_FORMAT);
      expect(parseSignaturePack('{"format":"fieldwatch-signatures","fleets":[]}').error).assertEqual(SignaturePackError.NO_SIGNATURES);
    });

    it('round trips a pack through encode and parse', 0, () => {
      const parsed = parseSignaturePack(samplePack());
      const encoded: string = encodeSignaturePack(parsed.pack);
      const again = parseSignaturePack(encoded);
      expect(again.error).assertEqual(SignaturePackError.NONE);
      expect(again.pack.fleets.length).assertEqual(2);
      expect(again.pack.fleets[0].id).assertEqual('fleet-finder');
      const decode: SignatureFleetDecode = again.pack.fleets[0].decode as SignatureFleetDecode;
      expect(decode.fields[0].enumLabels === undefined).assertFalse();
      expect((decode.fields[0].enumLabels as Map<string, string>).get('0')).assertEqual('Idle');
    });

    it('matches every rule kind against device facts', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const wifi: SignatureMatchContext = contextOf(RadioKind.WIFI, 'AA:BB:CC:DD:EE:FF', 'Actiontec-Guest');
      wifi.ssid = 'Actiontec-Guest';
      wifi.vendorIeOuis = ['00:11:22'];
      const ble: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Find Hub tag');
      ble.manufacturerId = 76;
      ble.manufacturerDataHex = '0215AABB';
      ble.serviceUuids = ['0000FE2C-0000-1000-8000-00805F9B34FB'];
      ble.serviceData = [new ServiceDataRecord('0000FD44-0000-1000-8000-00805F9B34FB', '0A0B')];

      const rules: SignatureRule[] = [
        new SignatureRule(SignatureRuleKind.OUI, 'AA:BB:CC', 0, '', RadioKind.WIFI),
        new SignatureRule(SignatureRuleKind.MAC_PREFIX, '11:22:33:44', 0, '', RadioKind.BLE),
        new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'actiontec', 0, '', RadioKind.WIFI),
        new SignatureRule(SignatureRuleKind.NAME_GLOB, 'Actiontec*', 0, '', RadioKind.WIFI),
        new SignatureRule(SignatureRuleKind.VENDOR_IE_OUI, '001122', 0, '', RadioKind.WIFI),
        new SignatureRule(SignatureRuleKind.SERVICE_UUID, 'FE2C', 0, '', RadioKind.BLE)
      ];
      const serviceDataRule: SignatureRule = new SignatureRule(SignatureRuleKind.SERVICE_DATA, 'FD44', 0, '0A0B', RadioKind.BLE);
      const manufacturerIdRule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_ID, '', 76, '', RadioKind.BLE);
      const manufacturerDataRule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 76, '0215', RadioKind.BLE);
      const hiddenRule: SignatureRule = new SignatureRule(SignatureRuleKind.HIDDEN_SSID, '', 0, '', RadioKind.WIFI);
      const radioRule: SignatureRule = new SignatureRule(SignatureRuleKind.RADIO_KIND, '', 0, '', RadioKind.BLE);

      const wifiFleet: SignatureFleet = new SignatureFleet('f-wifi', 'Wifi fleet', SignatureClass.ISP, [rules[0], rules[2], rules[3], rules[4]]);
      const bleFleet: SignatureFleet = new SignatureFleet('f-ble', 'Ble fleet', SignatureClass.FINDER, [rules[1], rules[5], serviceDataRule, manufacturerIdRule, manufacturerDataRule, radioRule]);
      const hiddenFleet: SignatureFleet = new SignatureFleet('f-hidden', 'Hidden', SignatureClass.OTHER, [hiddenRule]);
      const fleets: SignatureFleet[] = [wifiFleet, bleFleet, hiddenFleet];

      const wifiHits: string[] = engine.matchContext(wifi, fleets);
      expect(wifiHits.indexOf('f-wifi') >= 0).assertTrue();
      expect(wifiHits.indexOf('f-ble') < 0).assertTrue();
      const bleHits: string[] = engine.matchContext(ble, fleets);
      expect(bleHits.indexOf('f-ble') >= 0).assertTrue();
      expect(bleHits.indexOf('f-wifi') < 0).assertTrue();
      wifi.hiddenSsid = true;
      expect(engine.matchContext(wifi, fleets).indexOf('f-hidden') >= 0).assertTrue();
    });

    it('honours matchAny=false by requiring every rule', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Tracker');
      device.manufacturerId = 76;
      const strict: SignatureFleet = new SignatureFleet('f-all', 'Strict', SignatureClass.OTHER, [
        new SignatureRule(SignatureRuleKind.MANUFACTURER_ID, '', 76, '', RadioKind.BLE),
        new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'missing', 0, '', RadioKind.BLE)
      ]);
      strict.matchAny = false;
      expect(engine.matchContext(device, [strict]).length).assertEqual(0);
      strict.rules[1] = new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'track', 0, '', RadioKind.BLE);
      expect(engine.matchContext(device, [strict]).length).assertEqual(1);
    });

    it('decodes fields with named values, emphasis and gates', 0, () => {
      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Sensor');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '0107';
      const state: SignatureDecodeField = new SignatureDecodeField();
      state.id = 'state'; state.label = 'State'; state.offset = 0; state.length = 1; state.type = SignatureDecodeType.U8;
      state.enumLabels = new Map<string, string>();
      state.enumLabels.set('0', 'Idle');
      state.enumLabels.set('1', 'Pairing');
      state.liveEmphasis = ['1'];
      const battery: SignatureDecodeField = new SignatureDecodeField();
      battery.id = 'battery'; battery.label = 'Battery'; battery.offset = 1; battery.length = 1; battery.type = SignatureDecodeType.U8; battery.unit = 'V';
      const gated: SignatureDecodeField = new SignatureDecodeField();
      gated.id = 'gated'; gated.label = 'Gated'; gated.offset = 1; gated.length = 1; gated.type = SignatureDecodeType.U8;
      gated.gate = new SignatureDecodeWhen(0, SignatureDecodeWhenOp.EQ, '02');
      const fleet: SignatureFleet = new SignatureFleet('f', 'Decoded', SignatureClass.FINDER, []);
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [state, battery, gated], '', 76);
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(2);
      expect(values[0].text).assertEqual('Pairing');
      expect(values[0].emphasized).assertTrue();
      expect(values[0].live).assertFalse();
      expect(values[1].text).assertEqual('7 V');
    });

    it('applies byte order and bit extraction', 0, () => {
      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Sensor');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '3412F0';
      const little: SignatureDecodeField = new SignatureDecodeField();
      little.id = 'le16'; little.label = 'LE16'; little.offset = 0; little.length = 2; little.type = SignatureDecodeType.U16;
      little.endian = SignatureDecodeEndian.LE;
      const big: SignatureDecodeField = new SignatureDecodeField();
      big.id = 'be16'; big.label = 'BE16'; big.offset = 0; big.length = 2; big.type = SignatureDecodeType.U16;
      big.endian = SignatureDecodeEndian.BE;
      const bits: SignatureDecodeField = new SignatureDecodeField();
      bits.id = 'bits'; bits.label = 'Bits'; bits.offset = 2; bits.length = 1; bits.type = SignatureDecodeType.BITS;
      bits.bitOffset = 4; bits.bitWidth = 4;
      const fleet: SignatureFleet = new SignatureFleet('f', 'Numeric', SignatureClass.OTHER, []);
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [little, big, bits], '', 76);
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(3);
      expect(values[0].text).assertEqual('4660');
      expect(values[1].text).assertEqual('13330');
      expect(values[2].text).assertEqual('15');
    });

    it('merges an import without deleting or duplicating', 0, () => {
      const existing: SignatureFleet[] = [new SignatureFleet('fleet-a', 'A', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.OUI, '001122')], true)];
      const sameContentDifferentId: SignatureFleet = new SignatureFleet('other-id', 'A copy', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.OUI, '001122')]);
      const extraRule: SignatureFleet = new SignatureFleet('fleet-a', 'A', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'newrule')]);
      const fresh: SignatureFleet = new SignatureFleet('fleet-b', 'B', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.OUI, '445566')]);
      const merged: SignatureFleet[] = mergeSignatureFleets(existing, [sameContentDifferentId, extraRule, fresh], new Set<string>());
      expect(merged.length).assertEqual(2);
      const a: SignatureFleet = merged.find((item: SignatureFleet): boolean => item.id === 'fleet-a') as SignatureFleet;
      expect(a.rules.length).assertEqual(2);
      expect(a.builtIn).assertTrue();
    });

    it('overlays stock while keeping user state and extra rules', 0, () => {
      const local: SignatureFleet = new SignatureFleet('fleet-x', 'Old name', SignatureClass.OTHER, [
        new SignatureRule(SignatureRuleKind.OUI, '001122'),
        new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'user-added')
      ], true);
      local.enabled = false;
      const custom: SignatureFleet = new SignatureFleet('sig-custom', 'Mine', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.OUI, 'AABBCC')], false);
      const stock: SignatureFleet = new SignatureFleet('fleet-x', 'New name', SignatureClass.CAMERA, [new SignatureRule(SignatureRuleKind.OUI, '001122'), new SignatureRule(SignatureRuleKind.OUI, '00AA00')], true);
      const stockNew: SignatureFleet = new SignatureFleet('fleet-y', 'Added', SignatureClass.OTHER, [new SignatureRule(SignatureRuleKind.OUI, '123456')], true);
      const result: SignatureFleet[] = overlayStockFleets([local, custom], [stock, stockNew]);
      expect(result.length).assertEqual(3);
      const x: SignatureFleet = result.find((item: SignatureFleet): boolean => item.id === 'fleet-x') as SignatureFleet;
      expect(x.name).assertEqual('New name');
      expect(x.category).assertEqual(SignatureClass.CAMERA);
      expect(x.enabled).assertFalse();
      expect(x.rules.length).assertEqual(3);
      expect(result.some((item: SignatureFleet): boolean => item.id === 'sig-custom')).assertTrue();
      expect(result.some((item: SignatureFleet): boolean => item.id === 'fleet-y')).assertTrue();
    });

    it('keeps helper contracts for hex, uuid aliases and class names', 0, () => {
      expect(signatureHexOnly('00:11:22:AA:bb')).assertEqual('001122AABB');
      expect(signatureUuidAliases('0000FD44-0000-1000-8000-00805F9B34FB').indexOf('FD44') >= 0).assertTrue();
      expect(signatureClassOf('LAW_ENFORCEMENT')).assertEqual(SignatureClass.LAW_ENFORCEMENT);
      expect(signatureClassOf('law-enforcement')).assertEqual(SignatureClass.LAW_ENFORCEMENT);
      expect(signatureClassOf('drone')).assertEqual(SignatureClass.DRONE);
      expect(signatureClassOf('something else')).assertEqual(SignatureClass.OTHER);
    });

    it('decodes a full BLE advertisement into signature facts', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const hex: string = '020106' + '03032CFE' + '050954616731' + '07FF4C000215AABB' + '06162CFE0A0B0C';
      const facts: BleAdvertisementFacts = decoder.decode(hex);
      expect(facts.valid).assertTrue();
      expect(facts.adCount).assertEqual(5);
      expect(facts.flags).assertEqual(6);
      expect(facts.localName).assertEqual('Tag1');
      expect(facts.serviceUuids.indexOf('FE2C') >= 0).assertTrue();
      expect(facts.manufacturerId).assertEqual(76);
      expect(facts.manufacturerDataHex).assertEqual('0215AABB');
      expect(facts.serviceData.length).assertEqual(1);
      expect(facts.serviceData[0].uuid).assertEqual('FE2C');
      expect(facts.serviceData[0].dataHex).assertEqual('0A0B0C');
    });

    it('reports truncated and malformed advertisements', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      expect(decoder.decode('02010').valid).assertFalse();
      const truncated: BleAdvertisementFacts = decoder.decode('05095461');
      expect(truncated.valid).assertFalse();
      expect(truncated.error).assertEqual('truncated_ad');
      expect(decoder.decode('').error).assertEqual('invalid_hex');
    });

    it('suggests a signature from an observed device', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Sensor A');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '0215AABB';
      const fleet: SignatureFleet = engine.suggestFleet(device);
      expect(fleet.rules.length >= 2).assertTrue();
      expect(fleet.rules[0].kind).assertEqual(SignatureRuleKind.MAC_PREFIX);
      expect(fleet.rules.some((rule: SignatureRule): boolean => rule.kind === SignatureRuleKind.MANUFACTURER_DATA)).assertTrue();
      const hits: string[] = engine.matchContext(device, [fleet]);
      expect(hits.length).assertEqual(1);
    });

    it('surfaces live decode chips, signature names and debrief counts', 0, () => {
      const observation: ScanObservation = new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['fleet-a', 'fleet-b'];
      sighting.decodedFields = [
        new DecodedFieldValue('state', 'State', 'Pairing', '1', '', true, true, ''),
        new DecodedFieldValue('battery', 'Battery', '87 %', '87', '%', false, false, '')
      ];
      const chips: string[] = liveDecodeLabels(sighting.decodedFields);
      expect(chips.length).assertEqual(1);
      expect(chips[0]).assertEqual('State: Pairing');
      const fleets: SignatureFleet[] = [
        new SignatureFleet('fleet-a', 'Alpha', SignatureClass.FINDER, []),
        new SignatureFleet('fleet-b', 'Beta', SignatureClass.CAMERA, [])
      ];
      const names: string[] = matchedSignatureNames(sighting.signatureIds, fleets);
      expect(names.length).assertEqual(2);
      expect(names[0]).assertEqual('Alpha');
      const unknown: string[] = matchedSignatureNames(['missing-id'], fleets);
      expect(unknown[0]).assertEqual('missing-id');
      const counts: string[] = signatureHitCounts([sighting, sighting], fleets);
      expect(counts.length).assertEqual(2);
      expect(counts[0].indexOf('2') >= 0).assertTrue();
    });

    it('exports signature and decoded columns in CSV and JSONL', 0, () => {
      const observation: ScanObservation = new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['fleet-a'];
      sighting.decodedFields = [new DecodedFieldValue('state', 'State', 'Pairing', '1', '', true, false, '')];
      const settings: AppSettings = new AppSettings();
      const serializer: FieldwatchExportSerializer = new FieldwatchExportSerializer();
      const csv: string = serializer.serializeCsv([sighting], settings);
      expect(csv.indexOf('signatures,decoded') >= 0).assertTrue();
      expect(csv.indexOf('fleet-a') >= 0).assertTrue();
      expect(csv.indexOf('State=Pairing') >= 0).assertTrue();
      const jsonl: string = serializer.serializeJsonl([sighting], settings);
      expect(jsonl.indexOf('"signatures":["fleet-a"]') >= 0).assertTrue();
      expect(jsonl.indexOf('"label":"State"') >= 0).assertTrue();
      expect(jsonl.indexOf('"text":"Pairing"') >= 0).assertTrue();
    });

    it('keeps later fields when an earlier field gate fails', 0, () => {
      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Sensor');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '0107';
      const gatedFirst: SignatureDecodeField = new SignatureDecodeField();
      gatedFirst.id = 'gated'; gatedFirst.label = 'Gated'; gatedFirst.offset = 0; gatedFirst.length = 1; gatedFirst.type = SignatureDecodeType.U8;
      gatedFirst.gate = new SignatureDecodeWhen(0, SignatureDecodeWhenOp.EQ, '02');
      const always: SignatureDecodeField = new SignatureDecodeField();
      always.id = 'always'; always.label = 'Always'; always.offset = 1; always.length = 1; always.type = SignatureDecodeType.U8;
      const fleet: SignatureFleet = new SignatureFleet('f', 'Gated', SignatureClass.OTHER, []);
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [gatedFirst, always], '', 76);
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(1);
      expect(values[0].fieldId).assertEqual('always');
      expect(values[0].text).assertEqual('7');
    });

    it('prepends the device company id when the decode asks for it', 0, () => {
      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'TPMS');
      device.manufacturerId = 2504;
      device.manufacturerDataHex = '0107';
      const first: SignatureDecodeField = new SignatureDecodeField();
      first.id = 'alarm'; first.label = 'Alarm'; first.offset = 0; first.length = 2; first.type = SignatureDecodeType.U16;
      const fleet: SignatureFleet = new SignatureFleet('f', 'TPMS', SignatureClass.OTHER, []);
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [first], '', 0, true);
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(1);
      expect(values[0].text).assertEqual('2504');
    });

    it('colors radar points from the matched signature', 0, () => {
      const observation: ScanObservation = new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      const colored: SignatureFleet = new SignatureFleet('fleet-c', 'Colored', SignatureClass.CAMERA, []);
      colored.colorIndex = 4;
      const plain: SignatureFleet = new SignatureFleet('fleet-p', 'Plain', SignatureClass.OTHER, []);
      const fleets: SignatureFleet[] = [colored, plain];
      sighting.signatureIds = ['fleet-p', 'fleet-c'];
      expect(signatureColorIndex(sighting, fleets)).assertEqual(4);
      expect(signatureColorAt(4)).assertEqual('#B388FF');
      expect(signatureColorAt(-1)).assertEqual('');
      expect(signatureColorAt(9)).assertEqual('#4FC3F7');
      const points: FieldwatchRadarPoint[] = buildRadarPoints([sighting], fleets);
      expect(points[0].colorIndex).assertEqual(4);
      sighting.signatureIds = [];
      expect(signatureColorIndex(sighting, fleets)).assertEqual(-1);
      expect(buildRadarPoints([sighting], fleets)[0].colorIndex).assertEqual(-1);
    });

    it('filters by matched signature, decoded value and location', 0, () => {
      const observation: ScanObservation = new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      const engine = new FieldwatchFilterEngine();
      const filter = new FilterDefinition();
      filter.namedOnly = true;
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertFalse();
      sighting.signatureIds = ['x'];
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertTrue();
      filter.namedOnly = false;
      filter.decodedOnly = true;
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertFalse();
      sighting.decodedFields = [new DecodedFieldValue('a', 'A', '1', '1', '', false, false, '')];
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertTrue();
      filter.decodedOnly = false;
      filter.locatedOnly = true;
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertFalse();
      sighting.location = new GpsSample(22.3, 114.1, 1);
      expect(engine.pass(sighting, filter, [], [], [], Date.now())).assertTrue();
    });

    it('filters watched targets by device key and by signature', 0, () => {
      const observation: ScanObservation = new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      const engine = new FieldwatchFilterEngine();
      const filter = new FilterDefinition();
      filter.watchedOnly = true;
      expect(engine.pass(sighting, filter, [], [new WatchTarget('ble:x', '', 'device', true)], [], Date.now())).assertTrue();
      expect(engine.pass(sighting, filter, [], [new WatchTarget('ble:other', '', 'device', true)], [], Date.now())).assertFalse();
      expect(engine.pass(sighting, filter, [], [new WatchTarget('', 'fleet-a', 'family', true)], [], Date.now())).assertFalse();
      sighting.signatureIds = ['fleet-a'];
      expect(engine.pass(sighting, filter, [], [new WatchTarget('', 'fleet-a', 'family', true)], [], Date.now())).assertTrue();
      expect(engine.pass(sighting, filter, [], [new WatchTarget('', 'fleet-a', 'family', false)], [], Date.now())).assertFalse();
    });

    it('mirrors the real stock shapes: bits+scale, len gate, includeCompanyId', 0, () => {
      const decoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Ruuvi');
      device.manufacturerId = 1177;
      device.manufacturerDataHex = '0512ABFF';
      const battery: SignatureDecodeField = new SignatureDecodeField();
      battery.id = 'battery'; battery.label = 'Battery'; battery.offset = 0; battery.length = 2;
      battery.type = SignatureDecodeType.BITS; battery.bitOffset = 5; battery.bitWidth = 11; battery.scale = 1;
      const txPower: SignatureDecodeField = new SignatureDecodeField();
      txPower.id = 'tx_power'; txPower.label = 'TX power'; txPower.offset = 0; txPower.length = 2;
      txPower.type = SignatureDecodeType.BITS; txPower.bitOffset = 0; txPower.bitWidth = 5; txPower.scale = 2;
      const gated: SignatureDecodeField = new SignatureDecodeField();
      gated.id = 'payload_len'; gated.label = 'Payload len'; gated.offset = 0; gated.length = 1; gated.type = SignatureDecodeType.U8;
      gated.gate = new SignatureDecodeWhen(0, SignatureDecodeWhenOp.LEN, '', 4);
      const fleet: SignatureFleet = new SignatureFleet('f', 'Ruuvi', SignatureClass.OTHER, []);
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [battery, txPower, gated], '', 1177);
      const values: DecodedFieldValue[] = decoder.decode(fleet, device);
      expect(values.length).assertEqual(3);
      // LE u16 @0 = 0x1205 = 4613；battery = (4613 >> 5) & 0x7FF = 144，tx_power = (4613 & 0x1F) * 2 = 10
      expect(values[0].text).assertEqual('144');
      expect(values[1].text).assertEqual('10');
      expect(values[2].text).assertEqual('5');
      const short: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', 'Ruuvi');
      short.manufacturerId = 1177;
      short.manufacturerDataHex = '0512AB';
      expect(decoder.decode(fleet, short).length).assertEqual(2);
    });

    it('sorts the catalog by name and by class', 0, () => {
      const zebra: SignatureFleet = new SignatureFleet('f1', 'zebra', SignatureClass.CAMERA, []);
      const alpha: SignatureFleet = new SignatureFleet('f2', 'Alpha', SignatureClass.DRONE, []);
      const beta: SignatureFleet = new SignatureFleet('f3', 'beta', SignatureClass.CAMERA, []);
      const fleets: SignatureFleet[] = [zebra, alpha, beta];
      const byName: SignatureFleet[] = sortSignatureFleets(fleets, SignatureSortMode.NAME);
      expect(byName[0].id).assertEqual('f2');
      expect(byName[1].id).assertEqual('f3');
      expect(byName[2].id).assertEqual('f1');
      const byClass: SignatureFleet[] = sortSignatureFleets(fleets, SignatureSortMode.CLASS);
      expect(byClass[0].id).assertEqual('f3');
      expect(byClass[1].id).assertEqual('f1');
      expect(byClass[2].id).assertEqual('f2');
      expect(fleets[0].id).assertEqual('f1');
    });

    it('filters unnamed radios and keeps named ones', 0, () => {
      const engine = new FieldwatchFilterEngine();
      const filter = new FilterDefinition();
      filter.namedOnly = true;
      const anonymous: Sighting = Sighting.fromObservation(new ScanObservation('ble:x', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -40, 1));
      expect(engine.pass(anonymous, filter, [], [], [], Date.now())).assertFalse();
      const named: Sighting = Sighting.fromObservation(new ScanObservation('ble:y', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1));
      // 原版语义：namedOnly = 有命中签名，不是「有名字」
      named.signatureIds = ['fleet-x'];
      expect(engine.pass(named, filter, [], [], [], Date.now())).assertTrue();
      const ssidOnly: Sighting = Sighting.fromObservation(new ScanObservation('wifi:z', RadioKind.WIFI, '11:22:33:44:55:66', '', -40, 1, new RadioFacts('Lab-AP')));
      // 原版语义下，只有 SSID、没有命中签名的设备不满足 namedOnly
      expect(engine.pass(ssidOnly, filter, [], [], [], Date.now())).assertFalse();
      // 但「用户自定义命名」是另一条通道，应放行它
      const byName: FilterDefinition = new FilterDefinition();
      byName.customNamesOnly = true;
      expect(engine.pass(ssidOnly, byName, [], [], ['wifi:z'], Date.now())).assertTrue();
    });

    it('clones a fleet deeply for the editor', 0, () => {
      const fleet: SignatureFleet = new SignatureFleet('f', 'Original', SignatureClass.CAMERA, [new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'alpha')]);
      fleet.attentionNote = 'note';
      const field: SignatureDecodeField = new SignatureDecodeField();
      field.id = 'state'; field.label = 'State'; field.offset = 0; field.length = 1; field.type = SignatureDecodeType.U8;
      fleet.decode = new SignatureFleetDecode(SignatureDecodeSource.MANUFACTURER_DATA, [field], '', 76);
      const copy: SignatureFleet = cloneSignatureFleet(fleet);
      copy.name = 'Changed';
      copy.rules[0].text = 'changed';
      (copy.decode as SignatureFleetDecode).fields[0].label = 'Changed';
      copy.rules.push(new SignatureRule(SignatureRuleKind.OUI, '001122'));
      expect(fleet.name).assertEqual('Original');
      expect(fleet.rules.length).assertEqual(1);
      expect(fleet.rules[0].text).assertEqual('alpha');
      expect((fleet.decode as SignatureFleetDecode).fields[0].label).assertEqual('State');
    });

    it('drops the generic iBeacon label when a real product matched', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const device: SignatureMatchContext = contextOf(RadioKind.BLE, '11:22:33:44:55:66', '');
      device.manufacturerId = 76;
      device.manufacturerDataHex = '0215AABB';
      const ibeacon: SignatureFleet = new SignatureFleet('fleet-ibeacon', 'iBeacon', SignatureClass.BEACON, [new SignatureRule(SignatureRuleKind.MANUFACTURER_ID, '', 76, '', RadioKind.BLE)]);
      const product: SignatureFleet = new SignatureFleet('fleet-product', 'Product', SignatureClass.CAMERA, [new SignatureRule(SignatureRuleKind.MANUFACTURER_ID, '', 76, '', RadioKind.BLE)]);
      const hits: string[] = engine.matchContext(device, [ibeacon, product]);
      expect(hits.indexOf('fleet-product') >= 0).assertTrue();
      expect(hits.indexOf('fleet-ibeacon') < 0).assertTrue();
    });

    // ── 规则表达力扩展：offset / 长度约束 / 分组 ──
    // 起因：Theengs 等外部设备库大量用「第 N 字节是 X」和「A | B & C」，
    // 而此前只能匹配位置 0、且整体只能全 OR 或全 AND ——
    // 117 个设备定义里只有 26 个能表达。

    it('offset：前缀在指定字节偏移处匹配，且不再匹配位置 0', 0, () => {
      const fleet: SignatureFleet = new SignatureFleet('fleet-offset', 'Offset', SignatureClass.BEACON);
      const rule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, '5D');
      rule.offset = 2;
      fleet.rules.push(rule);
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      // 偏移 2 处是 5D -> 命中
      const hit: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      hit.manufacturerId = 0x004C;
      hit.manufacturerDataHex = 'AABB5DCC';
      expect(engine.matchContext(hit, [fleet]).length).assertEqual(1);
      // 同一个 5D 但在位置 0 -> 不该命中（这条专门防「offset 被忽略」）
      const miss: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      miss.manufacturerId = 0x004C;
      miss.manufacturerDataHex = '5DAABBCC';
      expect(engine.matchContext(miss, [fleet]).length).assertEqual(0);
      // 偏移越界不该崩，也不该命中
      const short: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      short.manufacturerId = 0x004C;
      short.manufacturerDataHex = 'AA';
      expect(engine.matchContext(short, [fleet]).length).assertEqual(0);
    });

    it('长度约束：minLen 与 maxLen 都生效', 0, () => {
      const minFleet: SignatureFleet = new SignatureFleet('fleet-min', 'MinLen', SignatureClass.BEACON);
      const minRule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      minRule.minLen = 4;
      minFleet.rules.push(minRule);
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const short: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      short.manufacturerId = 0x004C;
      short.manufacturerDataHex = 'AABB';
      expect(engine.matchContext(short, [minFleet]).length).assertEqual(0);
      const long: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      long.manufacturerId = 0x004C;
      long.manufacturerDataHex = 'AABBCCDD';
      expect(engine.matchContext(long, [minFleet]).length).assertEqual(1);
      // maxLen：精确长度用 minLen = maxLen 表达（对应外部库的 `=`）
      const exactFleet: SignatureFleet = new SignatureFleet('fleet-exact', 'Exact', SignatureClass.BEACON);
      const exactRule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      exactRule.minLen = 2; exactRule.maxLen = 2;
      exactFleet.rules.push(exactRule);
      expect(engine.matchContext(short, [exactFleet]).length).assertEqual(1);
      expect(engine.matchContext(long, [exactFleet]).length).assertEqual(0);
    });

    it('分组：同组内 AND、组间 OR', 0, () => {
      const fleet: SignatureFleet = new SignatureFleet('fleet-group', 'Grouped', SignatureClass.OTHER);
      // 组 1：byte@0 == AA 且 byte@1 == BB
      const a: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      a.group = 1;
      const b: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'BB');
      b.group = 1; b.offset = 1;
      // 组 2：byte@0 == CC
      const c: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'CC');
      c.group = 2;
      fleet.rules.push(a); fleet.rules.push(b); fleet.rules.push(c);
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const g1: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      g1.manufacturerId = 0x004C; g1.manufacturerDataHex = 'AABB';
      expect(engine.matchContext(g1, [fleet]).length).assertEqual(1);   // 组 1 整体命中
      const g2: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      g2.manufacturerId = 0x004C; g2.manufacturerDataHex = 'CC';
      expect(engine.matchContext(g2, [fleet]).length).assertEqual(1);   // 组 2 命中
      // 只有组 1 的一半 -> 两个组都不成立（这条防「组内退化成 OR」）
      const half: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      half.manufacturerId = 0x004C; half.manufacturerDataHex = 'AA';
      expect(engine.matchContext(half, [fleet]).length).assertEqual(0);
    });

    it('分组规则不污染基础集合语义（严格超集）', 0, () => {
      // 基础规则 matchAny=false 要求全部命中；再加一个不成立的分组，不应把整体拉成命中。
      const fleet: SignatureFleet = new SignatureFleet('fleet-superset', 'Superset', SignatureClass.OTHER);
      const base1: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      const base2: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'ZZ');
      base2.dataPrefixHex = 'FFFF';
      const grouped: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'CC');
      grouped.group = 1;
      fleet.rules.push(base1); fleet.rules.push(base2); fleet.rules.push(grouped);
      fleet.matchAny = false;
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const ctx: SignatureMatchContext = contextOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '');
      ctx.manufacturerId = 0x004C; ctx.manufacturerDataHex = 'CC';
      // 分组命中 -> 整体命中（分组是额外的 OR 分支）
      expect(engine.matchContext(ctx, [fleet]).length).assertEqual(1);
      // 去掉分组后，基础集合要求 AA 与 FFFF 同时命中 -> 不成立
      fleet.rules = [base1, base2];
      expect(engine.matchContext(ctx, [fleet]).length).assertEqual(0);
    });

    it('规则身份键包含 offset / 分组 / 长度，避免去重误折叠', 0, () => {
      const plain: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      const shifted: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      shifted.offset = 2;
      expect(signatureRuleKey(plain) === signatureRuleKey(shifted)).assertFalse();
      const bounded: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA');
      bounded.minLen = 4;
      expect(signatureRuleKey(plain) === signatureRuleKey(bounded)).assertFalse();
    });

    it('offset / 分组 / 长度 能往返序列化', 0, () => {
      const fleet: SignatureFleet = new SignatureFleet('fleet-roundtrip', 'RoundTrip', SignatureClass.OTHER);
      const rule: SignatureRule = new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AABB');
      rule.offset = 3; rule.group = 2; rule.minLen = 5; rule.maxLen = 9;
      fleet.rules.push(rule);
      const encoded: string = encodeSignaturePack(new SignaturePack([fleet], 99));
      expect(encoded.indexOf('"offset": 3') >= 0).assertTrue();
      expect(encoded.indexOf('"group": 2') >= 0).assertTrue();
      const parsed = parseSignaturePack(encoded);
      expect(parsed.error).assertEqual(SignaturePackError.NONE);
      const back: SignatureRule = parsed.pack.fleets[0].rules[0];
      expect(back.offset).assertEqual(3);
      expect(back.group).assertEqual(2);
      expect(back.minLen).assertEqual(5);
      expect(back.maxLen).assertEqual(9);
    });

    it('默认值为 0 的规则不写出新字段（旧条目保持字节不变）', 0, () => {
      const fleet: SignatureFleet = new SignatureFleet('fleet-plain', 'Plain', SignatureClass.OTHER);
      fleet.rules.push(new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0x004C, 'AA'));
      const encoded: string = encodeSignaturePack(new SignaturePack([fleet], 99));
      expect(encoded.indexOf('"offset"') < 0).assertTrue();
      expect(encoded.indexOf('"group"') < 0).assertTrue();
      expect(encoded.indexOf('"minLen"') < 0).assertTrue();
      expect(encoded.indexOf('"maxLen"') < 0).assertTrue();
    });
  });
}
