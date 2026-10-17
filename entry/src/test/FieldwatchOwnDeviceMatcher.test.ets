import { describe, it, expect } from '@ohos/hypium';
import {
  ADDRESS_MATCH_SCORE, FieldwatchOwnDeviceMatcher, FINGERPRINT_MATCH_THRESHOLD,
  fingerprintScore, OwnDeviceMatch, OwnDeviceMatchReason, OwnDeviceProbe, probeOf
} from '../main/ets/fieldwatch/domain/FieldwatchOwnDeviceMatcher';
import { OwnDevice, OwnDeviceFingerprint } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';
import { RadioFacts, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';

/** 造一台自有设备。 */
function device(id: string, address: string, name: string, vendorData: string): OwnDevice {
  const entry: OwnDevice = new OwnDevice();
  entry.id = id;
  entry.virtualAddress = address;
  entry.displayName = name;
  entry.addressStable = true;
  entry.fingerprint.name = name;
  entry.fingerprint.manufacturerDataHex = vendorData;
  return entry;
}

/** 造一条观测视图。 */
function probe(address: string, name: string, vendorData: string): OwnDeviceProbe {
  const item: OwnDeviceProbe = new OwnDeviceProbe();
  item.kind = RadioKind.BLE;
  item.address = address;
  item.name = name;
  item.manufacturerDataHex = vendorData;
  return item;
}

export default function fieldwatchOwnDeviceMatcherTest() {
  describe('FieldwatchOwnDeviceMatcher', () => {
    it('scores each fingerprint dimension and requires cross-confirmation', 0, () => {
      const target: OwnDeviceFingerprint = new OwnDeviceFingerprint();
      target.name = '我的耳机';
      target.manufacturerDataHex = 'AABB';
      target.serviceUuids = ['fd6f'];
      target.signatureIds = ['govee'];

      // 只有名字：3 分，未过阈值 5 —— 单一维度不足以认亲（同名设备满街都是）。
      expect(fingerprintScore(target, probe('AA:BB:CC:00:00:01', '我的耳机', ''))).assertEqual(3);
      // 名字 + 厂商数据：5 分，正好过线。
      expect(fingerprintScore(target, probe('AA:BB:CC:00:00:01', '我的耳机', 'AABB'))).assertEqual(5);
      // 四维全中：3+2+2+2 = 9。
      const full: OwnDeviceProbe = probe('AA:BB:CC:00:00:01', '我的耳机', 'AABB');
      full.serviceUuids = ['fd6f', 'fff0'];
      full.signatureIds = ['govee'];
      expect(fingerprintScore(target, full)).assertEqual(9);
    });

    it('does not score empty target fields', 0, () => {
      // 认领时没拿到的信息不能凭空加分：否则「空档案」会与任何空观测互相命中。
      const empty: OwnDeviceFingerprint = new OwnDeviceFingerprint();
      expect(fingerprintScore(empty, probe('', '', ''))).assertEqual(0);
      expect(fingerprintScore(empty, probe('AA:BB:CC:00:00:01', '谁的设备', 'FFFF'))).assertEqual(0);
    });

    it('prefers address match over any fingerprint', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const devices: OwnDevice[] = [
        device('a', 'AA:BB:CC:00:00:01', '音箱', '1111'),
        device('b', 'AA:BB:CC:00:00:02', '耳机', '2222')
      ];
      // 地址指向 b，但指纹（名字+厂商数据）指向 a：地址直配优先。
      const result: OwnDeviceMatch = matcher.match(probe('AA:BB:CC:00:00:02', '音箱', '1111'), devices);
      expect(result.deviceId).assertEqual('b');
      expect(result.reason).assertEqual(OwnDeviceMatchReason.ADDRESS);
      expect(result.score).assertEqual(ADDRESS_MATCH_SCORE);
    });

    it('matches by fingerprint when the address changed', 0, () => {
      // 这就是 V1 证伪时的主路径：地址变了（或本就不同源），靠指纹仍然认得出。
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const devices: OwnDevice[] = [device('a', 'AA:BB:CC:00:00:01', '我的耳机', 'AABB')];
      const result: OwnDeviceMatch = matcher.match(probe('11:22:33:44:55:66', '我的耳机', 'AABB'), devices);
      expect(result.deviceId).assertEqual('a');
      expect(result.reason).assertEqual(OwnDeviceMatchReason.FINGERPRINT);
      expect(result.score >= FINGERPRINT_MATCH_THRESHOLD).assertTrue();
    });

    it('picks the highest fingerprint score and stays deterministic on ties', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const weak: OwnDevice = device('weak', '', '我的耳机', 'AABB');
      weak.fingerprint.serviceUuids = [];
      const strong: OwnDevice = device('strong', '', '我的耳机', 'AABB');
      strong.fingerprint.signatureIds = ['govee'];
      const devices: OwnDevice[] = [weak, strong];
      const probeItem: OwnDeviceProbe = probe('', '我的耳机', 'AABB');
      probeItem.signatureIds = ['govee'];
      // strong 多拿 2 分（签名）→ 名 3 + 厂商 2 + 签名 2 = 7 分；weak 只有名 + 厂商 = 5 分。
      const result: OwnDeviceMatch = matcher.match(probeItem, devices);
      expect(result.deviceId).assertEqual('strong');
      expect(result.score).assertEqual(7);
    });

    it('lets a denied fingerprint block fingerprint matches but not the address', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const mine: OwnDevice = device('mine', 'AA:BB:CC:00:00:01', '我的耳机', 'AABB');
      // 用户按过「这不是我的」：同款设备（同名字同厂商数据）被拉黑。
      const denied: OwnDeviceFingerprint = new OwnDeviceFingerprint();
      denied.name = '别人的耳机';
      denied.manufacturerDataHex = 'CCDD';
      mine.denyFingerprints.push(denied);

      // 邻居那台同款：指纹与拉黑条目一致 → 不认。
      const neighbor: OwnDeviceMatch = matcher.match(probe('11:22:33:44:55:66', '别人的耳机', 'CCDD'), [mine]);
      expect(neighbor.isMatch()).assertFalse();

      // 但地址相等就是我这台本身 → 拉黑不能把地址直配也挡掉。
      const itself: OwnDeviceMatch = matcher.match(probe('AA:BB:CC:00:00:01', '我的耳机', 'AABB'), [mine]);
      expect(itself.reason).assertEqual(OwnDeviceMatchReason.ADDRESS);
    });

    it('returns no match when nothing is close enough', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const devices: OwnDevice[] = [device('a', 'AA:BB:CC:00:00:01', '我的耳机', 'AABB')];
      const result: OwnDeviceMatch = matcher.match(probe('11:22:33:44:55:66', '别的耳机', 'EEFF'), devices);
      expect(result.isMatch()).assertFalse();
      expect(result.reason).assertEqual(OwnDeviceMatchReason.NONE);
    });

    it('builds a probe from a real sighting including vendor IE fallback', 0, () => {
      const facts: RadioFacts = new RadioFacts();
      facts.manufacturerDataHex = 'AABB';
      const observation: ScanObservation = new ScanObservation(
        'ble:AA:BB:CC:DD:EE:FF', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '我的耳机', -55, 1000, facts);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['find'];
      const probeItem: OwnDeviceProbe = probeOf(sighting);
      expect(probeItem.address).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(probeItem.name).assertEqual('我的耳机');
      expect(probeItem.manufacturerDataHex).assertEqual('AABB');
      expect(probeItem.signatureIds.length).assertEqual(1);

      // Wi-Fi 没有服务 UUID，用厂商 IE OUI 顶上：两者都是「这台设备的特征集合」。
      const wifiFacts: RadioFacts = new RadioFacts();
      wifiFacts.vendorIeOuis = ['001122'];
      const wifiObservation: ScanObservation = new ScanObservation(
        'wifi:AA:BB:CC:DD:EE:01', RadioKind.WIFI, 'AA:BB:CC:DD:EE:01', '客厅-5G', -40, 1000, wifiFacts);
      const wifiProbe: OwnDeviceProbe = probeOf(Sighting.fromObservation(wifiObservation));
      expect(wifiProbe.serviceUuids.length).assertEqual(1);
      expect(wifiProbe.serviceUuids[0]).assertEqual('001122');
    });
  });
}
