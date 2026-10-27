import { describe, it, expect } from '@ohos/hypium';
import {
  addressTail, fallbackHasTail, fallbackLabel, fallbackTail, NAME_TAIL_LENGTH, NameInputs,
  NamedDevice, NameSource, resolveDeviceName
} from '../main/ets/fieldwatch/domain/FieldwatchDeviceNaming';
import { RadioKind } from '../main/ets/fieldwatch/domain/FieldwatchModels';

function inputs(): NameInputs {
  const it: NameInputs = new NameInputs();
  it.kind = RadioKind.BLE;
  it.address = 'AA:BB:CC:DD:EE:FF';
  return it;
}

export default function fieldwatchDeviceNamingTest() {
  describe('FieldwatchDeviceNaming', () => {
    // 回退链每一级都要覆盖：文档要求「单测覆盖每一级」。
    it('prefers the custom name above everything', 0, () => {
      const i: NameInputs = inputs();
      i.customName = '我的耳机';
      i.pairedName = 'FreeBuds';
      i.broadcastName = 'Bud';
      i.fleetName = 'Huawei FreeBuds';
      i.deviceClassLabel = '蓝牙耳机';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('我的耳机');
      expect(named.source).assertEqual(NameSource.CUSTOM);
    });

    it('falls back to the paired name next', 0, () => {
      const i: NameInputs = inputs();
      i.pairedName = 'FreeBuds';
      i.broadcastName = 'Bud';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('FreeBuds');
      expect(named.source).assertEqual(NameSource.PAIRED);
    });

    it('uses the broadcast name or SSID third', 0, () => {
      const i: NameInputs = inputs();
      i.broadcastName = 'ChinaNet-202';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('ChinaNet-202');
      expect(named.source).assertEqual(NameSource.BROADCAST);
    });

    it('uses the matched fleet name fourth', 0, () => {
      const i: NameInputs = inputs();
      i.fleetName = 'Apple AirTags';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('Apple AirTags');
      expect(named.source).assertEqual(NameSource.SIGNATURE);
    });

    it('uses the class-of-device label fifth', 0, () => {
      const i: NameInputs = inputs();
      i.deviceClassLabel = '蓝牙耳机';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('蓝牙耳机');
      expect(named.source).assertEqual(NameSource.DEVICE_CLASS);
    });

    // 厂商 + 类别：两者都有才拼成「华为 · 蓝牙耳机」。
    it('joins vendor and category when both exist', 0, () => {
      const i: NameInputs = inputs();
      i.vendorName = '华为';
      i.categoryLabel = '蓝牙耳机';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('华为 · 蓝牙耳机');
      expect(named.source).assertEqual(NameSource.VENDOR);
    });

    // 只有厂商名时仍然采用 —— 比「未命名设备」有用。
    it('accepts a vendor-only name', 0, () => {
      const i: NameInputs = inputs();
      i.vendorName = '小米';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual('小米');
      expect(named.source).assertEqual(NameSource.VENDOR);
    });

    // 兜底：带地址尾号，保证多台无名设备可区分。
    it('falls back to a numbered placeholder', 0, () => {
      const i: NameInputs = inputs();
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.source).assertEqual(NameSource.FALLBACK);
      expect(named.isFallback()).assertTrue();
      expect(fallbackHasTail(named.label)).assertTrue();
      expect(fallbackTail(named.label)).assertEqual('EEFF');
    });

    // 空串与纯空白都算「没有」—— 只判 length>0 会把 ' ' 当成有效名字。
    it('treats whitespace-only names as absent', 0, () => {
      const i: NameInputs = inputs();
      i.customName = '   ';
      i.pairedName = '';
      i.broadcastName = ' ';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.source).assertEqual(NameSource.FALLBACK);
    });

    // 地址尾号：三种来源写法要归一化到同一口径。
    it('normalises address tails across formats', 0, () => {
      expect(addressTail('AA:BB:CC:DD:EE:FF')).assertEqual('EEFF');
      expect(addressTail('ble:AA:BB:CC:DD:EE:FF')).assertEqual('EEFF');
      expect(addressTail('aa-bb-cc-dd-ee-ff')).assertEqual('EEFF');
      expect(addressTail('')).assertEqual('');
      // 短地址原样返回。
      expect(addressTail('AB')).assertEqual('AB');
      expect(NAME_TAIL_LENGTH).assertEqual(4);
    });

    // 两台无名设备必须得到不同兜底名（否则用户区分不了）。
    it('gives different placeholders to different devices', 0, () => {
      const first: NameInputs = inputs();
      first.address = 'AA:BB:CC:DD:EE:01';
      const second: NameInputs = inputs();
      second.address = 'AA:BB:CC:DD:EE:02';
      expect(resolveDeviceName(first).label === resolveDeviceName(second).label).assertFalse();
    });

    it('drops the tail when the address is unknown', 0, () => {
      const i: NameInputs = inputs();
      i.address = '';
      const named: NamedDevice = resolveDeviceName(i);
      expect(named.label).assertEqual(fallbackLabel(''));
      expect(fallbackHasTail(named.label)).assertFalse();
    });
  });
}
