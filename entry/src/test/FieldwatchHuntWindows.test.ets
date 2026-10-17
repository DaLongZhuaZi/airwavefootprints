import { describe, it, expect } from '@ohos/hypium';
import {
  HUNT_QUIET_MS, HUNT_WIFI_WINDOWS, HuntCue, HuntSample, HuntWindows, huntCue
} from '../main/ets/fieldwatch/domain/FieldwatchHunt';

const NOW: number = 1000000;

/** 造一串采样：at 由调用方给，便于构造「两次扫描」这种稀疏节奏。 */
function samples(pairs: number[][]): HuntSample[] {
  const out: HuntSample[] = [];
  pairs.forEach((pair: number[]): void => {
    out.push(new HuntSample(pair[1], pair[0]));
  });
  return out;
}

export default function fieldwatchHuntWindowsTest() {
  describe('FieldwatchHuntWindows', () => {
    it('keeps the BLE defaults unchanged', 0, () => {
      // 默认窗必须与既有常量完全一致：专业页与共享领域逻辑不能被这次改动动到。
      const defaults: HuntWindows = new HuntWindows();
      expect(defaults.recentMs).assertEqual(2000);
      expect(defaults.earlierToMs).assertEqual(3500);
      expect(defaults.earlierFromMs).assertEqual(8000);
      expect(defaults.quietMs).assertEqual(HUNT_QUIET_MS);
    });

    it('widens the windows for Wi-Fi scan rhythm', 0, () => {
      // Wi-Fi 扫描是几十秒一次的突发：静默窗必须大于扫描间隔，否则永远「安静」。
      expect(HUNT_WIFI_WINDOWS.quietMs > HUNT_WIFI_WINDOWS.recentMs).assertTrue();
      expect(HUNT_WIFI_WINDOWS.earlierFromMs > HUNT_WIFI_WINDOWS.earlierToMs).assertTrue();
      expect(HUNT_WIFI_WINDOWS.recentMs > 2000).assertTrue();
    });

    it('reports QUIET under BLE windows for a sparse Wi-Fi stream', 0, () => {
      // 上一次扫描在 20 秒前：BLE 窗（8 秒）判为安静 —— 这正是真机上看到的现象。
      const sparse: HuntSample[] = samples([[NOW - 40000, -50], [NOW - 20000, -48]]);
      expect(huntCue(sparse, NOW, NOW - 20000, false)).assertEqual(HuntCue.QUIET);
    });

    it('still compares direction under Wi-Fi windows for the same stream', 0, () => {
      // 同一串数据在 Wi-Fi 窗下是「比上次更强」→ CLOSER。
      // 近窗=最近一次扫描（20 秒前，均值 -48），远窗=再上一次（40 秒前，均值 -58）→ 差 +10 dB。
      const sparse: HuntSample[] = [
    new HuntSample(-58, NOW - 40000), new HuntSample(-59, NOW - 41000),
    new HuntSample(-48, NOW - 20000), new HuntSample(-47, NOW - 21000)
  ];
      expect(huntCue(sparse, NOW, NOW - 20000, false, HUNT_WIFI_WINDOWS)).assertEqual(HuntCue.CLOSER);
      // 反过来就是 FURTHER。
      const weaker: HuntSample[] = [
    new HuntSample(-40, NOW - 40000), new HuntSample(-41, NOW - 41000),
    new HuntSample(-55, NOW - 20000), new HuntSample(-56, NOW - 21000)
  ];
      expect(huntCue(weaker, NOW, NOW - 20000, false, HUNT_WIFI_WINDOWS)).assertEqual(HuntCue.FURTHER);
    });

    it('does not call a between-scans Wi-Fi target GONE', 0, () => {
      // missing 由「距上次样本超过静默窗」决定：20 秒前扫到过 → 不算不在。
      const sparse: HuntSample[] = samples([[NOW - 20000, -50]]);
      expect(huntCue(sparse, NOW, NOW - 20000, false, HUNT_WIFI_WINDOWS) !== HuntCue.GONE).assertTrue();
      // 但真的一整轮扫描都没扫到（> quietMs）→ 才算不在。
      expect(huntCue(sparse, NOW, NOW - 60000, true, HUNT_WIFI_WINDOWS)).assertEqual(HuntCue.GONE);
    });
  });
}
