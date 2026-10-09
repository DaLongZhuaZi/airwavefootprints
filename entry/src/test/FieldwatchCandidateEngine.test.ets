import { describe, expect, it } from '@ohos/hypium';
import { RadioKind, RadioFacts, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { CandidateRuleKind, SignatureCandidateEngine } from '../main/ets/fieldwatch/domain/FieldwatchCandidateEngine';

function sighting(key: string, kind: RadioKind, address: string, name: string, facts: RadioFacts): Sighting {
  return new Sighting(key, kind, address, name, -60, 1700000000, facts);
}
function facts(): RadioFacts { return new RadioFacts(); }

export default function fieldwatchCandidateEngineTest() {
  describe('FieldwatchCandidateEngine', () => {
    const engine: SignatureCandidateEngine = new SignatureCandidateEngine();

    it('', 0, () => {
      expect(engine.isHouseLikeName('Guest')).assertTrue();
      expect(engine.isHouseLikeName('xfinitywifi')).assertTrue();
      expect(engine.isHouseLikeName('')).assertTrue();
      expect(engine.isHouseLikeName('HUAWEI-5G')).assertFalse();
    });

    it('', 0, () => {
      // 前缀 'Tesla' 是「无分隔符的纯字母单词」，原版 isHouseLikeName 判为家用形，因此这里必须返回空。
      expect(engine.nameGlobOf('Tesla_Model3_AB12CD')).assertEqual('');
      // 带数字的前缀不算家用形，才能提取出通配。
      expect(engine.nameGlobOf('TeslaModel3_AB12CD')).assertEqual('TeslaModel3_??????');
      expect(engine.nameGlobOf('[FLOCK] Camera 12')).assertEqual('[FLOCK]*');
      // DIRECT- 在 SKIP_PREFIX 里，必须被拒
      expect(engine.nameGlobOf('DIRECT-roku-1234')).assertEqual('');
    });

    it('', 0, () => {
      const left: RadioFacts = facts();
      left.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const right: RadioFacts = facts();
      right.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const report = engine.analyze([
        sighting('ble:aa', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', left),
        sighting('ble:bb', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', '', right)
      ], []);
      expect(report.families.length).assertEqual(1);
      expect(report.families[0].ruleKind).assertEqual(CandidateRuleKind.SERVICE_UUID);
      expect(report.families[0].distinctRadios).assertEqual(2);
    });

    it('', 0, () => {
      const only: RadioFacts = facts();
      only.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const report = engine.analyze([sighting('ble:aa', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', only)], []);
      expect(report.families.length).assertEqual(0);
    });

    it('', 0, () => {
      const left: RadioFacts = facts();
      left.serviceUuids = ['0000180f-0000-1000-8000-00805f9b34fb'];
      left.manufacturerId = 0x004c;
      const right: RadioFacts = facts();
      right.serviceUuids = ['0000180f-0000-1000-8000-00805f9b34fb'];
      right.manufacturerId = 0x004c;
      const report = engine.analyze([
        sighting('ble:aa', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', left),
        sighting('ble:bb', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', '', right)
      ], []);
      expect(report.families.length).assertEqual(0);
    });

    it('', 0, () => {
      const left: RadioFacts = facts();
      left.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const a: Sighting = sighting('ble:aa', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', left);
      a.signatureIds = ['fleet-1'];
      const report = engine.analyze([a], []);
      expect(report.unmatchedRadios).assertEqual(0);
      expect(report.families.length).assertEqual(0);
    });

    it('', 0, () => {
      const only: RadioFacts = facts();
      const report = engine.analyze([
        sighting('ble:aa', RadioKind.BLE, '02:11:22:33:44:55', 'RandomThing', only)
      ], []);
      expect(report.skippedRandomized).assertEqual(1);
    });

    it('', 0, () => {
      const left: RadioFacts = facts();
      left.vendorIeOuis = ['00:11:22'];
      const right: RadioFacts = facts();
      right.vendorIeOuis = ['00:11:22'];
      const report = engine.analyze([
        sighting('wifi:aa', RadioKind.WIFI, '10:20:30:40:50:01', 'Camera-A', left),
        sighting('wifi:bb', RadioKind.WIFI, '10:20:30:40:50:02', 'Camera-B', right)
      ], []);
      expect(report.families.length).assertEqual(1);
      expect(report.families[0].ruleKind).assertEqual(CandidateRuleKind.VENDOR_IE);
    });

    it('', 0, () => {
      const left: RadioFacts = facts();
      left.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const right: RadioFacts = facts();
      right.serviceUuids = ['0000fd6f-0000-1000-8000-00805f9b34fb'];
      const report = engine.analyze([
        sighting('ble:aa', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', left),
        sighting('ble:bb', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', '', right)
      ], []);
      const fleet = engine.toFleet(report.families[0], 'user-1');
      expect(fleet.id).assertEqual('user-1');
      expect(fleet.rules.length).assertEqual(1);
      expect(fleet.rules[0].text).assertEqual('FD6F');
      expect(fleet.builtIn).assertFalse();
    });
  });
}