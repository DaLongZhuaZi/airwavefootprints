import { describe, it, expect } from '@ohos/hypium';
import {
  batteryText, boardCardOf, carLastSeenParts, CarLastSeenParts, clockOf, DeviceBoardCard,
  hasUsableLocation, mapUri, sameDay, sortBoardCards
} from '../main/ets/fieldwatch/domain/FieldwatchDeviceBoard';
import { OwnDeviceFingerprint, OwnDeviceKind, OwnDeviceProfile } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';

function profile(id: string, kind: OwnDeviceKind = OwnDeviceKind.OTHER, name: string = 'dev'): OwnDeviceProfile {
  return new OwnDeviceProfile(id, '', 'AA:BB:CC:DD:EE:FF', 'ble:AA:BB:CC:DD:EE:FF', name, kind, -1,
    OwnDeviceFingerprint.empty(), 'scan');
}

export default function fieldwatchDeviceBoardTest() {
  describe('FieldwatchDeviceBoard', () => {
    // P2-12 红线：电量解不到就不显示，绝不拿 RSSI 冒充电量。
    it('never renders a battery line when the value is unknown', 0, () => {
      expect(batteryText(-1)).assertEqual('');
      expect(batteryText(101)).assertEqual('');
      expect(batteryText(0)).assertEqual('0%');
      expect(batteryText(87)).assertEqual('87%');
      const card: DeviceBoardCard = boardCardOf(profile('p1'), '', 0, -1, 1000);
      expect(card.hasBattery()).assertFalse();
    });

    // 「在附近」看实时键是否命中，不看时间差 —— 否则刚离开 30 秒也会显示在附近。
    it('treats nearby as a live key hit, not a time window', 0, () => {
      const now: number = 1000000;
      const live: DeviceBoardCard = boardCardOf(profile('p1'), 'ble:AA:BB:CC:DD:EE:FF', now - 5000, 55, now);
      expect(live.nearby).assertTrue();
      const gone: DeviceBoardCard = boardCardOf(profile('p2'), '', now - 30000, 55, now);
      expect(gone.nearby).assertFalse();
      // 电量与是否在附近无关：离开后仍保留最后一次解出的值。
      expect(gone.batteryPercent).assertEqual(55);
    });

    it('sorts nearby first then by recency', 0, () => {
      const now: number = 1000000;
      const a: DeviceBoardCard = boardCardOf(profile('a'), '', now - 100, -1, now);
      const b: DeviceBoardCard = boardCardOf(profile('b'), 'ble:B', now - 9000, -1, now);
      const c: DeviceBoardCard = boardCardOf(profile('c'), '', now - 500, -1, now);
      const sorted: DeviceBoardCard[] = sortBoardCards([a, b, c]);
      expect(sorted[0].profileId).assertEqual('b');
      expect(sorted[1].profileId).assertEqual('a');
      expect(sorted[2].profileId).assertEqual('c');
    });

    it('marks a car profile and keeps the flag on the card', 0, () => {
      const card: DeviceBoardCard = boardCardOf(profile('car', OwnDeviceKind.CAR, '我的车'), '', 1000, -1, 2000);
      expect(card.isCar).assertTrue();
      expect(card.label).assertEqual('我的车');
      const other: DeviceBoardCard = boardCardOf(profile('e', OwnDeviceKind.HEADPHONES), '', 1000, -1, 2000);
      expect(other.isCar).assertFalse();
    });

    // P2-13：最后听到它。没有定位时**不编造楼层**。
    it('omits the location fragment when there is no fix', 0, () => {
      const withFix: CarLastSeenParts = carLastSeenParts(1793043000000, 31.2, 121.4, 'B2 层附近');
      expect(withFix.where).assertEqual('B2 层附近');
      const noFix: CarLastSeenParts = carLastSeenParts(1793043000000, 0, 0, 'B2 层附近');
      expect(noFix.where).assertEqual('');
      // 时间片段仍然有（用户至少知道什么时候听到过）。
      expect(noFix.when.length > 0).assertTrue();
    });

    it('only offers the map when the coordinates are usable', 0, () => {
      expect(hasUsableLocation(0, 0)).assertFalse();
      expect(hasUsableLocation(31.2, 121.4)).assertTrue();
      expect(hasUsableLocation(100, 121)).assertFalse();
      expect(hasUsableLocation(31.2, 200)).assertFalse();
      const uri: string = mapUri(31.2, 121.4, '我的车');
      expect(uri.indexOf('geo:31.2,121.4') === 0).assertTrue();
    });

    it('formats clocks and compares days in local time', 0, () => {
      expect(clockOf(0)).assertEqual('');
      const at: number = new Date(2026, 9, 27, 18, 2).getTime();
      expect(clockOf(at)).assertEqual('18:02');
      expect(sameDay(at, at + 1000)).assertTrue();
      expect(sameDay(at, at + 86400000)).assertFalse();
    });
  });
}
