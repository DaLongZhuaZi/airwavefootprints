import { describe, expect, it } from '@ohos/hypium';
import { FilterDefinition, RadioFacts, RadioKind, ServiceDataRecord, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { FieldwatchFilterEngine } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';

/** 造一台 BLE 广播源，serviceData 由调用方给定。 */
function ble(key: string, uuid: string, dataHex: string, signatureIds: string[]): Sighting {
  const facts: RadioFacts = new RadioFacts();
  const record: ServiceDataRecord = new ServiceDataRecord(uuid, dataHex);
  facts.serviceData = [record];
  const item: Sighting = new Sighting(key, RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', -60, 1700000000, facts);
  item.signatureIds = signatureIds;
  return item;
}

function filter(): FilterDefinition {
  const value: FilterDefinition = new FilterDefinition();
  value.hideFastPairAccountKey = true;
  return value;
}

const engine: FieldwatchFilterEngine = new FieldwatchFilterEngine();
const now: number = 1700000000000;

function passes(item: Sighting): boolean {
  return engine.pass(item, filter(), [], [], [], now);
}

export default function fieldwatchFastPairTest() {
  describe('Fast Pair 账号密钥过滤', () => {
    it('配对模式（3 字节 service data）不被隐藏', 0, () => {
      // 0xFE2C + 3 字节 model ID = 可点按配对，原版 FastPair.pairingAdvertised 为真。
      const item: Sighting = ble('ble:pair', '0000FE2C-0000-1000-8000-00805F9B34FB', '012345', ['fleet-fast-pair']);
      expect(passes(item)).assertTrue();
    });

    it('账号密钥且只命中 Fast Pair 时被隐藏', 0, () => {
      const item: Sighting = ble('ble:acct', '0000FE2C-0000-1000-8000-00805F9B34FB', '0201020304050607', ['fleet-fast-pair']);
      expect(passes(item)).assertFalse();
    });

    it('账号密钥但另有特征可识别时不隐藏', 0, () => {
      const item: Sighting = ble('ble:acct2', '0000FE2C-0000-1000-8000-00805F9B34FB', '0201020304050607',
        ['fleet-fast-pair', 'fleet-some-other']);
      expect(passes(item)).assertTrue();
    });

    it('没有命中 Fast Pair 特征时不隐藏', 0, () => {
      const item: Sighting = ble('ble:other', '0000FE2C-0000-1000-8000-00805F9B34FB', '0201020304050607', ['fleet-other']);
      expect(passes(item)).assertTrue();
    });

    it('短写 UUID FE2C 同样识别', 0, () => {
      const item: Sighting = ble('ble:short', 'FE2C', '0201020304050607', ['fleet-fast-pair']);
      expect(passes(item)).assertFalse();
    });

    it('判定只依赖特征命中，不依赖 service data 的 UUID', 0, () => {
      // 原版 isAccountKeyOnly 只检查「非配对模式 + 命中 fleet-fast-pair + 仅此一个」。
      // service data 的 UUID 只参与「是否配对模式」的判断，不参与本判定的其余部分。
      const item: Sighting = ble('ble:no', '0000FD6F-0000-1000-8000-00805F9B34FB', '0201020304050607', ['fleet-fast-pair']);
      expect(passes(item)).assertFalse();
    });

    it('关掉开关后账号密钥恢复显示', 0, () => {
      const item: Sighting = ble('ble:acct3', '0000FE2C-0000-1000-8000-00805F9B34FB', '0201020304050607', ['fleet-fast-pair']);
      const off: FilterDefinition = new FilterDefinition();
      expect(engine.pass(item, off, [], [], [], now)).assertTrue();
    });
  });
}