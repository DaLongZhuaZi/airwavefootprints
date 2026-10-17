import { describe, it, expect } from '@ohos/hypium';
import {
  deviceOf, FieldwatchOwnDeviceRepository, OwnDeviceRecord, recordOf
} from '../main/ets/fieldwatch/data/FieldwatchOwnDeviceRepository';
import { OwnDevice } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';
import { GpsSample, RadioKind } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';

/** 造一台完整档案。 */
function fullDevice(): OwnDevice {
  const device: OwnDevice = new OwnDevice();
  device.id = 'own-1';
  device.displayName = '我的耳机';
  device.kind = RadioKind.BLE;
  device.virtualAddress = 'AA:BB:CC:DD:EE:FF';
  device.addressStable = true;
  device.category = SignatureClass.AUDIO;
  device.fingerprint.name = 'WH-1000XM5';
  device.fingerprint.manufacturerDataHex = 'AABB';
  device.fingerprint.serviceUuids = ['fd6f', 'fff0'];
  device.fingerprint.signatureIds = ['sony'];
  device.lastSeenAt = 1700000000000;
  device.lastLocation = new GpsSample(31.23, 121.47, 1700000000000);
  device.createdAt = 1699999990000;
  device.claimSource = 'paired';
  return device;
}

export default function fieldwatchOwnDeviceRepositoryTest() {
  describe('FieldwatchOwnDeviceRepository', () => {
    it('round-trips a full archive through the row view', 0, () => {
      const original: OwnDevice = fullDevice();
      const restored: OwnDevice = deviceOf(recordOf(original));
      expect(restored.id).assertEqual('own-1');
      expect(restored.displayName).assertEqual('我的耳机');
      expect(restored.kind).assertEqual(RadioKind.BLE);
      expect(restored.virtualAddress).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(restored.addressStable).assertTrue();
      expect(restored.category).assertEqual(SignatureClass.AUDIO);
      expect(restored.createdAt).assertEqual(1699999990000);
      expect(restored.claimSource).assertEqual('paired');
      // 指纹四段都要活着回来（这是地址失效后的唯一识别手段）。
      expect(restored.fingerprint.name).assertEqual('WH-1000XM5');
      expect(restored.fingerprint.manufacturerDataHex).assertEqual('AABB');
      expect(restored.fingerprint.serviceUuids.length).assertEqual(2);
      expect(restored.fingerprint.signatureIds[0]).assertEqual('sony');
    });

    it('stores booleans as 0/1 and keeps location behind a flag', 0, () => {
      const device: OwnDevice = fullDevice();
      device.addressStable = false;
      device.lastLocation = undefined;
      const record: OwnDeviceRecord = recordOf(device);
      // RDB 里没有布尔，也没有 undefined：必须落到 0/1 与 has_location 标志。
      expect(record.addressStable).assertEqual(0);
      expect(record.hasLocation).assertEqual(0);
      const restored: OwnDevice = deviceOf(record);
      expect(restored.addressStable).assertFalse();
      expect(restored.lastLocation === undefined).assertTrue();
    });

    it('restores location coordinates when present', 0, () => {
      const restored: OwnDevice = deviceOf(recordOf(fullDevice()));
      expect(restored.lastLocation !== undefined).assertTrue();
      if (restored.lastLocation !== undefined) {
        expect(restored.lastLocation.latitude).assertEqual(31.23);
        expect(restored.lastLocation.longitude).assertEqual(121.47);
      }
    });

    it('tolerates an old archive that lacks newer fingerprint fields', 0, () => {
      // 老版本档案里没有 serviceUuids / signatureIds：解析必须给默认值，
      // 而不是 undefined —— 否则 Matcher 会在 `.length` 上炸掉。
      const record: OwnDeviceRecord = new OwnDeviceRecord();
      record.id = 'old-1';
      record.displayName = '旧档案';
      record.kind = 'ble';
      record.category = 'audio';
      record.fingerprint = '{"name":"旧耳机"}';
      record.denyFingerprints = '';
      const restored: OwnDevice = deviceOf(record);
      expect(restored.fingerprint.name).assertEqual('旧耳机');
      expect(restored.fingerprint.manufacturerDataHex).assertEqual('');
      expect(restored.fingerprint.serviceUuids.length).assertEqual(0);
      expect(restored.fingerprint.signatureIds.length).assertEqual(0);
      expect(restored.denyFingerprints.length).assertEqual(0);
    });

    it('falls back to safe defaults on corrupt JSON instead of throwing', 0, () => {
      const record: OwnDeviceRecord = new OwnDeviceRecord();
      record.id = 'bad-1';
      record.kind = '';
      record.category = 'nonsense';
      record.fingerprint = '{not json';
      record.denyFingerprints = '[broken';
      const restored: OwnDevice = deviceOf(record);
      expect(restored.fingerprint.name).assertEqual('');
      expect(restored.denyFingerprints.length).assertEqual(0);
      // 认不出的类别落 OTHER、认不出的种类落 BLE（默认值而非崩）。
      expect(restored.category).assertEqual(SignatureClass.OTHER);
      expect(restored.kind).assertEqual(RadioKind.BLE);
    });

    it('keeps near link and wifi kinds apart from ble', 0, () => {
      const wifiRecord: OwnDeviceRecord = new OwnDeviceRecord();
      wifiRecord.kind = 'wifi';
      wifiRecord.category = 'router';
      expect(deviceOf(wifiRecord).kind).assertEqual(RadioKind.WIFI);
      expect(deviceOf(wifiRecord).category).assertEqual(SignatureClass.ROUTER);
      const nearLinkRecord: OwnDeviceRecord = new OwnDeviceRecord();
      nearLinkRecord.kind = 'nearlink';
      expect(deviceOf(nearLinkRecord).kind).assertEqual(RadioKind.NEARLINK);
    });

    it('round-trips the deny list used by the correction path', 0, () => {
      const device: OwnDevice = fullDevice();
      const denied = device.fingerprint;
      denied.name = '别人的耳机';
      device.denyFingerprints.push(denied);
      const restored: OwnDevice = deviceOf(recordOf(device));
      expect(restored.denyFingerprints.length).assertEqual(1);
      expect(restored.denyFingerprints[0].name).assertEqual('别人的耳机');
    });

    it('exposes a repository that can be constructed without a device', 0, () => {
      // 仓储本身不做任何 I/O 直到 initialize()：构造不该有副作用，
      // 也不该在无 RDB 环境下抛错（页面可以放心在构造期 new 出来）。
      const repository: FieldwatchOwnDeviceRepository = new FieldwatchOwnDeviceRepository();
      expect(repository !== undefined).assertTrue();
    });
  });
}
