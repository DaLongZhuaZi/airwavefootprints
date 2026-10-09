import { describe, expect, it } from '@ohos/hypium';
import { FieldwatchBleAdvertisementDecoder } from '../main/ets/fieldwatch/domain/FieldwatchParsers';

/** 把若干 (type, payload) 组装成一个合法的 AD 结构串。 */
function ad(records: Array<[number, number[]]>): string {
  let out: string = '';
  records.forEach((record: [number, number[]]): void => {
    const length: number = record[1].length + 1;
    const push = (value: number): void => {
      const hex: string = value.toString(16).toUpperCase();
      out += hex.length === 1 ? '0' + hex : hex;
    };
    push(length);
    push(record[0]);
    record[1].forEach(push);
  });
  return out;
}

export default function fieldwatchAdvertisementTest() {
  describe('FieldwatchAdvertisement', () => {
    it('reads GAP Appearance from AD type 0x19', 0, () => {
      // 0x19 此前**完全没被解析** —— 详情页因此从来显示不出「它自称是什么」。
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      // Appearance 0x0341 = 833 = HID 键盘
      const facts = decoder.decode(ad([[0x19, [0x41, 0x03]]]));
      expect(facts.valid).assertTrue();
      expect(facts.appearance).assertEqual(0x0341);
    });

    it('reads the category when the exact appearance is absent', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      // 0x03C0 是「HID 设备」类别值本身
      const facts = decoder.decode(ad([[0x19, [0xC0, 0x03]]]));
      expect(facts.appearance).assertEqual(0x03C0);
    });

    it('leaves appearance unset when the advertisement omits it', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const facts = decoder.decode(ad([[0x01, [0x06]]]));
      expect(facts.appearance).assertEqual(-1);
    });

    it('keeps appearance, flags and tx power apart', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      // 同时带 Flags(0x01)、TxPower(0x0A)、Appearance(0x19)
      const facts = decoder.decode(ad([[0x01, [0x1A]], [0x0A, [0x00]], [0x19, [0x40, 0x02]]]));
      expect(facts.flags).assertEqual(0x1A);
      expect(facts.txPower).assertEqual(0);
      expect(facts.appearance).assertEqual(0x0240);
    });

    it('treats a missing tx power as unset rather than 0 dBm', 0, () => {
      // 0 dBm 是合法的发射功率值，不能拿它当「没有」的默认值 ——
      // 否则每个不带该字段的设备都会显示成「声明的发射功率 0 dBm」。
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const facts = decoder.decode(ad([[0x01, [0x06]]]));
      expect(facts.txPower).assertEqual(-128);
    });

    it('decodes a negative tx power in two-s complement', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      // 0xF4 = -12 dBm
      const facts = decoder.decode(ad([[0x0A, [0xF4]]]));
      expect(facts.txPower).assertEqual(-12);
    });

    it('collects 16-bit service UUIDs in little-endian order', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const facts = decoder.decode(ad([[0x03, [0xEE, 0xFD]]]));
      expect(facts.serviceUuids.length).assertEqual(1);
      expect(facts.serviceUuids[0]).assertEqual('FDEE');
    });

    it('reads manufacturer id little-endian and drops it from the payload', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const facts = decoder.decode(ad([[0xFF, [0x4C, 0x00, 0xAA, 0xBB]]]));
      expect(facts.manufacturerId).assertEqual(0x004C);
      expect(facts.manufacturerDataHex).assertEqual('AABB');
    });

    it('rejects a truncated AD record instead of guessing', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      // 声明 8 字节，实际只有 1 字节负载
      const facts = decoder.decode('0819FF');
      expect(facts.valid).assertFalse();
    });

    it('counts every AD structure it walked through', 0, () => {
      const decoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();
      const facts = decoder.decode(ad([[0x01, [0x06]], [0x19, [0x41, 0x03]], [0x0A, [0xF4]]]));
      expect(facts.adCount).assertEqual(3);
    });
  });
}