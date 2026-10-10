import { describe, expect, it } from '@ohos/hypium';
import {
  bandRange, channelFrequency, loadLevel, NON_OVERLAPPING_24, occupiedWidthMhz, standardChannels,
  surveyBand, WifiBand, wifiBandOf, wifiChannelOf, wifiChannelWidthMhz, ChannelArc
} from '../main/ets/fieldwatch/domain/FieldwatchChannelAnalysis';
import {
  assessTrack, FollowRisk, GeoPoint, haversineMeters, riskOf, TrackPoint
} from '../main/ets/fieldwatch/domain/FieldwatchAntiTracking';

function arc(freq: number, rssi: number, width: number): ChannelArc {
  return new ChannelArc('k' + freq.toString(), 'ap', freq, width, rssi);
}

export default function fieldwatchToolboxTest() {
  describe('FieldwatchChannelAnalysis', () => {
    it('频段判定按频率边界', 0, () => {
      expect(wifiBandOf(2412)).assertEqual(WifiBand.BAND_24);
      expect(wifiBandOf(5180)).assertEqual(WifiBand.BAND_5);
      expect(wifiBandOf(5955)).assertEqual(WifiBand.BAND_6);
      expect(wifiBandOf(1000)).assertEqual(WifiBand.UNKNOWN);
    });

    it('信道号在三个频段各自的栅格上', 0, () => {
      expect(wifiChannelOf(2412)).assertEqual(1);
      expect(wifiChannelOf(2437)).assertEqual(6);
      expect(wifiChannelOf(2462)).assertEqual(11);
      expect(wifiChannelOf(5180)).assertEqual(36);
      expect(wifiChannelOf(5955)).assertEqual(1);
      // 落在栅格之外的一律 0，不能硬凑一个信道号出来。
      expect(wifiChannelOf(2413)).assertEqual(0);
      expect(wifiChannelOf(3000)).assertEqual(0);
    });

    it('信道宽度编码映射，未知按 20MHz 兜底', 0, () => {
      expect(wifiChannelWidthMhz(1)).assertEqual(20);
      expect(wifiChannelWidthMhz(2)).assertEqual(40);
      expect(wifiChannelWidthMhz(3)).assertEqual(80);
      expect(wifiChannelWidthMhz(4)).assertEqual(160);
      expect(wifiChannelWidthMhz(0)).assertEqual(20);
      expect(wifiChannelWidthMhz(99)).assertEqual(20);
    });

    it('2.4G 一律按 22MHz 占用算，这正是邻道重叠的来源', 0, () => {
      expect(occupiedWidthMhz(WifiBand.BAND_24, 1)).assertEqual(22);
      expect(occupiedWidthMhz(WifiBand.BAND_5, 3)).assertEqual(80);
    });

    it('1/6/11 互不重叠，而 1/2/3 连成一片', 0, () => {
      // 三个中心相隔 25MHz，各自 22MHz 宽 —— 相邻弧之间有 3MHz 空隙。
      const clean = surveyBand(WifiBand.BAND_24, [arc(2412, -50, 22), arc(2437, -50, 22), arc(2462, -50, 22)]);
      const cleanAt6 = clean.loads.filter((load) => load.channel === 6)[0];
      // 信道 6 的位置只被它自己覆盖。
      expect(cleanAt6.overlappingAps).assertEqual(1);
      const packed = surveyBand(WifiBand.BAND_24, [arc(2412, -50, 22), arc(2417, -50, 22), arc(2422, -50, 22)]);
      const packedAt2 = packed.loads.filter((load) => load.channel === 2)[0];
      // 1/2/3 的中心只隔 5MHz，信道 2 上三条弧全都覆盖到。
      expect(packedAt2.overlappingAps).assertEqual(3);
    });

    it('拥堵度按功率叠加，重叠处一定比单覆盖处更挤', 0, () => {
      // **归一化是「相对本频段最挤的点」**，不是绝对量；
      // 所以不能拿「一个 AP 应该得 50 分」这种绝对期望来断言。
      // 有意义的是**同一次统计内部**的相对关系：重叠 > 单覆盖。
      // 信道 1 与 2 只隔 5MHz，22MHz 的占用必然互相压上。
      const survey = surveyBand(WifiBand.BAND_24, [arc(2412, -50, 22), arc(2417, -50, 22)]);
      // 采样点落在信道栅格上（2412 / 2417 …），两点都被两条弧覆盖。
      const between = survey.loads.filter((load) => load.frequencyMhz === 2417)[0];
      const faraway = survey.loads.filter((load) => load.frequencyMhz === 2462)[0];
      expect(between.overlappingAps).assertEqual(2);
      expect(faraway.overlappingAps).assertEqual(0);
      expect(between.loadScore > faraway.loadScore).assertTrue();
      expect(survey.loads.filter((load) => load.loadScore === 100).length > 0).assertTrue();
      // **反例**：1 与 6 相隔 25MHz、各占 22MHz，全程不会出现「两条同时覆盖」——
      // 这正是 2.4G 只用 1/6/11 的原因，也是本图要让人看见的东西。
      const spaced = surveyBand(WifiBand.BAND_24, [arc(2412, -50, 22), arc(2437, -50, 22)]);
      expect(spaced.loads.filter((load) => load.overlappingAps === 2).length).assertEqual(0);
      // 且每个采样点的信道号都必须能算出来（采样栅格与信道栅格同源）。
      expect(spaced.loads.filter((load) => load.channel === 0).length).assertEqual(0);
    });

    it('2.4G 的推荐信道只从 1/6/11 里选', 0, () => {
      const survey = surveyBand(WifiBand.BAND_24, [arc(2412, -40, 22)]);
      expect(NON_OVERLAPPING_24.indexOf(survey.recommendedChannel) >= 0).assertTrue();
      // 1 被占着，最空的必然是 6 或 11。
      expect(survey.recommendedChannel === 6 || survey.recommendedChannel === 11).assertTrue();
    });

    it('空频段不崩且给出 0', 0, () => {
      const survey = surveyBand(WifiBand.BAND_6, []);
      expect(survey.totalAps).assertEqual(0);
      expect(survey.recommendedChannel).assertEqual(0);
      expect(survey.loads.length).assertEqual(0);
    });

    it('频率与信道号可互相还原，且刻度覆盖频段', 0, () => {
      expect(channelFrequency(WifiBand.BAND_24, 6)).assertEqual(2437);
      expect(channelFrequency(WifiBand.BAND_5, 36)).assertEqual(5180);
      const range = bandRange(WifiBand.BAND_5);
      expect(range[1] > range[0]).assertTrue();
      expect(standardChannels(WifiBand.BAND_24).length).assertEqual(13);
      expect(loadLevel(80)).assertEqual(2);
      expect(loadLevel(50)).assertEqual(1);
      expect(loadLevel(10)).assertEqual(0);
    });
  });

  describe('FieldwatchAntiTracking', () => {
    it('haversine 在已知距离上量级正确', 0, () => {
      // 纬度相差 0.001 度约 111 米。
      const meters = haversineMeters(30.0, 120.0, 30.001, 120.0);
      expect(meters > 100 && meters < 120).assertTrue();
      expect(haversineMeters(30.0, 120.0, 30.0, 120.0)).assertEqual(0);
    });

    it('样本太少或跨度太短一律 0 分', 0, () => {
      const now = 1000000;
      const few: TrackPoint[] = [new TrackPoint(now - 60000, -50), new TrackPoint(now, -50)];
      expect(assessTrack(few, [], now).score).assertEqual(0);
      // 样本够多但全挤在 1 分钟内。
      const brief: TrackPoint[] = [];
      for (let i = 0; i < 20; i += 1) brief.push(new TrackPoint(now - 60000 + i * 100, -50));
      expect(assessTrack(brief, [], now).score).assertEqual(0);
    });

    it('一路伴随且强度平稳的设备得高分', 0, () => {
      const now = 2000000;
      const samples: TrackPoint[] = [];
      const travel: GeoPoint[] = [];
      // 20 分钟、每分钟一个样本；用户沿一条弯路走了约 1km。
      for (let i = 0; i < 21; i += 1) {
        samples.push(new TrackPoint(now - (20 - i) * 60000, -55));
        const lat = 30.0 + i * 0.0002;
        const lon = 120.0 + (i % 2 === 0 ? 0.0002 : -0.0002);
        travel.push(new GeoPoint(now - (20 - i) * 60000, lat, lon));
      }
      const evidence = assessTrack(samples, travel, now);
      expect(evidence.hasGeo).assertTrue();
      expect(evidence.pathRatio > 1.5).assertTrue();
      expect(evidence.rssiResidualDb < 0.001).assertTrue();
      expect(riskOf(evidence.score)).assertEqual(FollowRisk.SUSPECT);
    });

    it('没有位置数据时地理维度为 0，但不会误判成可疑', 0, () => {
      const now = 3000000;
      const samples: TrackPoint[] = [];
      for (let i = 0; i < 21; i += 1) samples.push(new TrackPoint(now - (20 - i) * 60000, -70));
      const evidence = assessTrack(samples, [], now);
      expect(evidence.hasGeo).assertFalse();
      expect(evidence.pathMeters).assertEqual(0);
      // 缺了地理这一维（35 分上限）后不应达到「疑似跟踪」。
      expect(evidence.score < 70).assertTrue();
    });

    it('强度一路走低的设备不会被当成跟随', 0, () => {
      const now = 4000000;
      const samples: TrackPoint[] = [];
      const travel: GeoPoint[] = [];
      // 从 -40 单调掉到 -90：你在远离它，斜率很陡。
      for (let i = 0; i < 21; i += 1) {
        samples.push(new TrackPoint(now - (20 - i) * 60000, -40 - i * 2.5));
        travel.push(new GeoPoint(now - (20 - i) * 60000, 30.0 + i * 0.0002, 120.0));
      }
      const evidence = assessTrack(samples, travel, now);
      expect(Math.abs(evidence.rssiSlopePerMin) > 2).assertTrue();
      expect(evidence.score < 70).assertTrue();
    });

    it('窗口外的旧样本不参与判定', 0, () => {
      const now = 5000000;
      const samples: TrackPoint[] = [];
      // 全部落在 30 分钟窗口之外。
      for (let i = 0; i < 21; i += 1) samples.push(new TrackPoint(now - 40 * 60000 - i * 60000, -50));
      expect(assessTrack(samples, [], now).score).assertEqual(0);
    });
  });
}
