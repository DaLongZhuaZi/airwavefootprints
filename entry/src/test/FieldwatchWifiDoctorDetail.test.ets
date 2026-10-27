import { describe, it, expect } from '@ohos/hypium';
import {
  apDetailRows, ApDetailRow, bandLabelKey, channelOfBand, gradeOrder, isCrowdedChannel,
  roomTrends, RoomTrend, shouldPromptRetest
, ApSnapshot
} from '../main/ets/fieldwatch/domain/FieldwatchWifiDoctorDetail';
import { RoomCheck, RoomSignalGrade } from '../main/ets/fieldwatch/domain/FieldwatchWifiDoctor';

function room(label: string, median: number, samples: number, endedAt: number): RoomCheck {
  const check: RoomCheck = new RoomCheck(label);
  check.medianRssi = median;
  check.sampleCount = samples;
  check.endedAt = endedAt;
  return check;
}


class ApSnapshotImpl implements ApSnapshot {
  ssid: string = '';
  bssid: string = '';
  rssi: number = 0;
  band: number = 0;
}

function ap(ssid: string, bssid: string, rssi: number, band: number): ApSnapshot {
  const snap: ApSnapshot = new ApSnapshotImpl();
  snap.ssid = ssid;
  snap.bssid = bssid;
  snap.rssi = rssi;
  snap.band = band;
  return snap;
}

export default function fieldwatchWifiDoctorDetailTest() {
  describe('FieldwatchWifiDoctorDetail', () => {
    // 频段 → 信道：2.4G 与 5G 各自公式，未知频段返回 0。
    it('derives the channel from the band', 0, () => {
      expect(channelOfBand(2412)).assertEqual(1);
      expect(channelOfBand(2437)).assertEqual(6);
      expect(channelOfBand(2462)).assertEqual(11);
      expect(channelOfBand(5180)).assertEqual(36);
      expect(channelOfBand(5745)).assertEqual(149);
      // 无法推断的一律 0，不猜。
      expect(channelOfBand(0)).assertEqual(0);
      expect(channelOfBand(-1)).assertEqual(0);
      expect(channelOfBand(900)).assertEqual(0);
    });

    it('maps the band to a display key', 0, () => {
      expect(bandLabelKey(2412).indexOf('band_24') > 0).assertTrue();
      expect(bandLabelKey(5180).indexOf('band_5') > 0).assertTrue();
      expect(bandLabelKey(5955).indexOf('band_6') > 0).assertTrue();
      expect(bandLabelKey(0).indexOf('unknown') > 0).assertTrue();
    });

    // 2.4G 只有 1/6/11 互不重叠；5G 不做拥挤判断。
    it('flags crowded 2.4G channels only', 0, () => {
      expect(isCrowdedChannel(1, 2412)).assertFalse();
      expect(isCrowdedChannel(6, 2437)).assertFalse();
      expect(isCrowdedChannel(11, 2462)).assertFalse();
      expect(isCrowdedChannel(3, 2422)).assertTrue();
      expect(isCrowdedChannel(9, 2452)).assertTrue();
      // 5G 不算拥挤。
      expect(isCrowdedChannel(36, 5180)).assertFalse();
      expect(isCrowdedChannel(0, 2412)).assertFalse();
    });

    // 详情 5 行齐全，且 BSSID 缺省不崩。
    it('builds the AP detail rows', 0, () => {
      const rows: ApDetailRow[] = apDetailRows(ap('MyHome', 'AA:BB:CC:DD:EE:FF', -55, 2437));
      expect(rows.length).assertEqual(5);
      expect(rows[0].value).assertEqual('MyHome');
      expect(rows[1].value).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(rows[3].value).assertEqual('6');
      expect(rows[4].value).assertEqual('-55 dBm');
      // 拥挤信道标红。
      const crowded: ApDetailRow[] = apDetailRows(ap('X', 'AA:BB:CC:DD:EE:FF', -70, 2452));
      expect(crowded[3].warn).assertTrue();
      // 空值降级成 '-'，不显示空白。
      const empty: ApDetailRow[] = apDetailRows(ap('', '', 0, 0));
      expect(empty[0].value).assertEqual('-');
      expect(empty[1].value).assertEqual('-');
      expect(empty[3].value).assertEqual('-');
      expect(empty[4].value).assertEqual('-');
    });

    // 趋势：按房间聚合、时间正序、最新在末尾。
    it('aggregates room trends in time order', 0, () => {
      // 阈值（取自 FieldwatchWifiDoctor）：≥-55 STRONG / ≥-67 OK / ≥-75 WEAK / 其余 BAD。
      // 所以 -70（WEAK）→ -50（STRONG）才是「变好」。
      const records: RoomCheck[] = [
        room('客厅', -70, 20, 2000),
        room('客厅', -50, 20, 3000),
        room('主卧', -72, 20, 1000)
      ];
      const trends: RoomTrend[] = roomTrends(records);
      expect(trends.length).assertEqual(2);
      // 客厅最近测过（3000），排前面。
      expect(trends[0].label).assertEqual('客厅');
      expect(trends[0].count()).assertEqual(2);
      // 时间正序：2000 的在前。
      expect(trends[0].times[0]).assertEqual(2000);
      expect(trends[0].times[1]).assertEqual(3000);
      // 从 WEAK 变 STRONG → 趋势为正。
      expect(trends[0].trend() > 0).assertTrue();
      expect(trends[1].label).assertEqual('主卧');
    });

    // 样本不足的 UNKNOWN 不参与趋势比较（不能算「变差」）。
    it('ignores unknown grades in the trend', 0, () => {
      const records: RoomCheck[] = [
        room('书房', -30, 0, 1000),
        room('书房', -50, 20, 2000)
      ];
      const trends: RoomTrend[] = roomTrends(records);
      expect(trends[0].trend()).assertEqual(0);
      expect(gradeOrder(trends[0].first())).assertEqual(-1);
      // 单次记录没有趋势。
      const single: RoomTrend[] = roomTrends([room('阳台', -60, 20, 1000)]);
      expect(single[0].trend()).assertEqual(0);
      // 空集合不崩。
      expect(roomTrends([]).length).assertEqual(0);
    });

    it('orders grades from bad to strong', 0, () => {
      expect(gradeOrder(RoomSignalGrade.BAD)).assertEqual(0);
      expect(gradeOrder(RoomSignalGrade.WEAK)).assertEqual(1);
      expect(gradeOrder(RoomSignalGrade.OK)).assertEqual(2);
      expect(gradeOrder(RoomSignalGrade.STRONG)).assertEqual(3);
      expect(gradeOrder(RoomSignalGrade.UNKNOWN)).assertEqual(-1);
    });

    // 复测提醒：待提示 **且** 用户没关掉才展示。
    it('prompts a retest only when pending and not dismissed', 0, () => {
      expect(shouldPromptRetest(true, false)).assertTrue();
      expect(shouldPromptRetest(true, true)).assertFalse();
      expect(shouldPromptRetest(false, false)).assertFalse();
    });
  });
}
