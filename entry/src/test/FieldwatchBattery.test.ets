import { describe, it, expect } from '@ohos/hypium';
import { ServiceDataRecord } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { BleAdvertisementFacts, FieldwatchBatteryDecoder, FieldwatchBleAdvertisementDecoder } from '../main/ets/fieldwatch/domain/FieldwatchParsers';

/** 拼一段 AD：length + type + payload。 */
function ad(type: number, payload: number[]): string {
  const length: number = payload.length + 1;
  let hex: string = length.toString(16).padStart(2, '0') + type.toString(16).padStart(2, '0');
  payload.forEach((value: number): void => { hex += value.toString(16).padStart(2, '0'); });
  return hex;
}

export default function fieldwatchBatteryTest() {
  describe('FieldwatchBattery', () => {
    // P2-12 红线：解不到就不显示，绝不拿 RSSI 冒充电量。
    // 这里钉住「没有 Battery Service 就是 -1」这条底线。
    it('reports -1 when no battery service is present', 0, () => {
      expect(FieldwatchBatteryDecoder.fromServiceData([])[0]).assertEqual(-1);
      const other: ServiceDataRecord[] = [new ServiceDataRecord('0000FE2C-0000-1000-8000-00805F9B34FB', '64')];
      expect(FieldwatchBatteryDecoder.fromServiceData(other)[0]).assertEqual(-1);
    });

    it('reads the percentage from Battery Service service-data', 0, () => {
      const full: ServiceDataRecord[] = [
        new ServiceDataRecord('0000180F-0000-1000-8000-00805F9B34FB', '64')
      ];
      const result: number[] = FieldwatchBatteryDecoder.fromServiceData(full);
      expect(result[0]).assertEqual(100);
      expect(result[1]).assertEqual(0x16);
      // 16 位短串写法也要认（平台两种都给过）。
      expect(FieldwatchBatteryDecoder.fromServiceData([new ServiceDataRecord('180F', '37')])[0]).assertEqual(55);
    });

    it('rejects out-of-range percentages instead of clamping', 0, () => {
      // 0x80 = 128，超出 0..100，说明载荷不是电量，宁可不报。
      expect(FieldwatchBatteryDecoder.fromServiceData([new ServiceDataRecord('180F', '80')])[0]).assertEqual(-1);
      expect(FieldwatchBatteryDecoder.fromServiceData([new ServiceDataRecord('180F', '')])[0]).assertEqual(-1);
    });

    // 整包解码：电量必须在 Service Data 之后取，且解不出时为 -1。
    it('decodes battery through the full advertisement path', 0, () => {
      const batteryAd: string = ad(0x16, [0x0F, 0x18, 0x37]);
      const facts: BleAdvertisementFacts = new FieldwatchBleAdvertisementDecoder().decode(batteryAd);
      expect(facts.valid).assertTrue();
      expect(facts.batteryPercent).assertEqual(55);
      const plain: string = ad(0x09, [0x41, 0x42]);
      const noBattery: BleAdvertisementFacts = new FieldwatchBleAdvertisementDecoder().decode(plain);
      expect(noBattery.batteryPercent).assertEqual(-1);
    });
  });
}
