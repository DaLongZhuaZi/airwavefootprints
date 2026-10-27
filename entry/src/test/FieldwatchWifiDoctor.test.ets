import { describe, it, expect } from '@ohos/hypium';
import {
  buildWifiDoctor, channelCrowded, doctorLines, gradeOf, medianOf, ROOM_BAD_DBM, ROOM_DUAL_BAND_MIN_APS,
  ROOM_MIN_SAMPLES, ROOM_OK_DBM, ROOM_STRONG_DBM, ROOM_WEAK_DBM, RoomCheck, RoomSignalGrade,
  WifiDoctorReport, worstRoomIndex
} from '../main/ets/fieldwatch/domain/FieldwatchWifiDoctor';
import { BandSurvey, WifiBand } from '../main/ets/fieldwatch/domain/FieldwatchChannelAnalysis';

function room(label: string, median: number, samples: number): RoomCheck {
  const check: RoomCheck = new RoomCheck(label);
  check.medianRssi = median;
  check.sampleCount = samples;
  return check;
}

export default function fieldwatchWifiDoctorTest() {
  describe('FieldwatchWifiDoctor', () => {
    // 阈值是「按实测调」的那几个数，改成别的就等于改验收标准，钉在单测里。
    it('keeps the grade thresholds explicit', 0, () => {
      expect(ROOM_STRONG_DBM).assertEqual(-55);
      expect(ROOM_OK_DBM).assertEqual(-67);
      expect(ROOM_WEAK_DBM).assertEqual(-75);
      expect(ROOM_BAD_DBM).assertEqual(-80);
      expect(ROOM_MIN_SAMPLES).assertEqual(5);
    });

    it('grades signal by threshold and refuses to grade thin samples', 0, () => {
      expect(gradeOf(-50, 10)).assertEqual(RoomSignalGrade.STRONG);
      expect(gradeOf(-60, 10)).assertEqual(RoomSignalGrade.OK);
      expect(gradeOf(-70, 10)).assertEqual(RoomSignalGrade.WEAK);
      expect(gradeOf(-85, 10)).assertEqual(RoomSignalGrade.BAD);
      // 边界是「大于等于」：-55 算强，-56 算够用。
      expect(gradeOf(ROOM_STRONG_DBM, 10)).assertEqual(RoomSignalGrade.STRONG);
      expect(gradeOf(ROOM_STRONG_DBM - 1, 10)).assertEqual(RoomSignalGrade.OK);
      // 样本不足一律「还没测」，不拿单次读数冒充房间信号。
      expect(gradeOf(-50, ROOM_MIN_SAMPLES - 1)).assertEqual(RoomSignalGrade.UNKNOWN);
    });

    // 中位数而不是平均：一个房间静置 20 秒里必然夹着几个野值。
    it('uses the median so a few outliers cannot sink a room', 0, () => {
      expect(medianOf([-60, -61, -59])).assertEqual(-60);
      // 偶数个取中间两个的平均。
      expect(medianOf([-60, -70])).assertEqual(-65);
      // 一个 -95 的野值不会把 -60 拉到 -70 以下。
      const withOutlier: number[] = [-60, -60, -60, -95];
      expect(medianOf(withOutlier)).assertEqual(-60);
      expect(medianOf([])).assertEqual(0);
    });

    it('names the worst measured room and ignores unmeasured ones', 0, () => {
      const rooms: RoomCheck[] = [room('客厅', -50, 20), room('主卧', -78, 20), room('次卧', 0, 0)];
      expect(worstRoomIndex(rooms)).assertEqual(1);
      // 没测过的房间 medianRssi 是 0，若参与比较会永远被当成「最差」。
      const onlyUnmeasured: RoomCheck[] = [room('书房', 0, 2)];
      expect(worstRoomIndex(onlyUnmeasured)).assertEqual(-1);
    });

    it('flags a dual-band gap only when 5G exists but was not heard', 0, () => {
      const rooms: RoomCheck[] = [room('客厅', -50, 20)];
      // 有 5G 但只听到 2.4G：缺口成立。
      expect(buildWifiDoctor(rooms, 12, 0, undefined).dualBandGap).assertTrue();
      // 5G 也听到了：不缺。
      expect(buildWifiDoctor(rooms, 12, ROOM_DUAL_BAND_MIN_APS, undefined).dualBandGap).assertFalse();
      // 家里根本没有 2.4G（异常环境）不报缺口，因为那不是用户能修的问题。
      expect(buildWifiDoctor(rooms, 0, 0, undefined).dualBandGap).assertFalse();
    });

    it('reports crowded channels from the shared survey', 0, () => {
      expect(channelCrowded(4)).assertTrue();
      expect(channelCrowded(3)).assertFalse();
      const survey: BandSurvey = new BandSurvey();
      survey.band = WifiBand.BAND_24;
      survey.totalAps = 9;
      survey.busiestChannel = 6;
      survey.busiestScore = 5;
      const report: WifiDoctorReport = buildWifiDoctor([room('客厅', -50, 20)], 9, 0, survey);
      expect(report.crowdedChannel).assertEqual(6);
      expect(report.crowdedCount).assertEqual(5);
      const lines: string[] = [];
      doctorLines(report).forEach((line): void => { lines.push(line.key); });
      // 只有一个房间时**不说「最弱」**，所以是：档位 + 拥挤信道 + 双频缺口 = 3 条。
      expect(lines.length).assertEqual(3);
      // 两个房间时才会多出「最弱的房间：X」那一条。
      const two: RoomCheck[] = [room('客厅', -45, 20), room('主卧', -80, 20)];
      const twoLines: number = doctorLines(buildWifiDoctor(two, 9, 0, survey)).length;
      expect(twoLines).assertEqual(4);
    });

    it('reports no room rows when nothing was measured', 0, () => {
      const report: WifiDoctorReport = buildWifiDoctor([room('客厅', 0, 0)], 5, 0, undefined);
      expect(report.hasMeasuredRoom()).assertFalse();
      expect(report.worstRoom() === undefined).assertTrue();
    });
  });
}
