import { describe, it, expect } from '@ohos/hypium';
import {
  HuntCue, HuntSample, HuntSession, HUNT_MAX_SAMPLES, huntAverage, huntCue, huntCueKey, huntCueLevel, huntLastMeasured,
  huntPeak, huntRssiMeasured, huntSessionRange, huntTickIntervalMs
} from '../main/ets/fieldwatch/domain/FieldwatchHunt';

function samplesAt(base: number, offsets: number[], rssi: number): HuntSample[] {
  return offsets.map((offset: number): HuntSample => new HuntSample(rssi, base + offset));
}

export default function fieldwatchHuntTest() {
  describe('FieldwatchHunt', () => {
    it('treats 127 as not measured', 0, () => {
      expect(huntRssiMeasured(127)).assertFalse();
      expect(huntRssiMeasured(-127)).assertTrue();
      expect(huntRssiMeasured(-40)).assertTrue();
      expect(huntLastMeasured(127, [new HuntSample(-60, 1), new HuntSample(-50, 2)])).assertEqual(-50);
      expect(huntLastMeasured(-30, [])).assertEqual(-30);
    });

    it('reports gone, waiting and quiet before any trend', 0, () => {
      const now: number = 100000;
      expect(huntCue([], now, 0, true)).assertEqual(HuntCue.GONE);
      expect(huntCue([], now, 0, false)).assertEqual(HuntCue.WAITING);
      const stale: HuntSample[] = samplesAt(now - 20000, [0, 1000], -60);
      expect(huntCue(stale, now, now - 20000, false)).assertEqual(HuntCue.QUIET);
    });

    it('flags very close from a loud recent window', 0, () => {
      const now: number = 100000;
      const recent: HuntSample[] = samplesAt(now - 1000, [0, 500], -42);
      expect(huntCue(recent, now, now - 200, false)).assertEqual(HuntCue.VERY_CLOSE);
    });

    it('compares the recent window against the earlier window', 0, () => {
      const now: number = 100000;
      const earlier: HuntSample[] = samplesAt(now, [-7000, -6000], -80);
      const recentUp: HuntSample[] = samplesAt(now, [-1500, -500], -60);
      expect(huntCue(earlier.concat(recentUp), now, now - 100, false)).assertEqual(HuntCue.CLOSER);
      const recentDown: HuntSample[] = samplesAt(now, [-1500, -500], -95);
      expect(huntCue(earlier.concat(recentDown), now, now - 100, false)).assertEqual(HuntCue.FURTHER);
      const recentFlat: HuntSample[] = samplesAt(now, [-1500, -500], -81);
      expect(huntCue(earlier.concat(recentFlat), now, now - 100, false)).assertEqual(HuntCue.SAME);
      const recentThin: HuntSample[] = samplesAt(now, [-500], -60);
      expect(huntCue(earlier.concat(recentThin), now, now - 100, false)).assertEqual(HuntCue.WAITING);
    });

    it('maps loudness to a geiger tick interval', 0, () => {
      expect(huntTickIntervalMs(-40, HuntCue.CLOSER)).assertEqual(90);
      expect(huntTickIntervalMs(-90, HuntCue.CLOSER)).assertEqual(1400);
      expect(huntTickIntervalMs(-65, HuntCue.CLOSER)).assertEqual(745);
      expect(huntTickIntervalMs(-40, HuntCue.QUIET)).assertEqual(-1);
      expect(huntTickIntervalMs(-40, HuntCue.GONE)).assertEqual(-1);
      expect(huntTickIntervalMs(127, HuntCue.CLOSER)).assertEqual(-1);
      expect(huntTickIntervalMs(-200, HuntCue.CLOSER)).assertEqual(-1);
      expect(huntTickIntervalMs(-120, HuntCue.CLOSER)).assertEqual(1400);
    });

    it('summarises the session range, peak and level', 0, () => {
      const samples: HuntSample[] = [new HuntSample(-80, 1), new HuntSample(-52, 2), new HuntSample(-66, 3)];
      expect(huntPeak(samples)).assertEqual(-52);
      expect(huntSessionRange(samples)).assertEqual('-80..-52');
      expect(huntSessionRange([new HuntSample(-60, 1)])).assertEqual('-60');
      expect(huntSessionRange([])).assertEqual('');
      expect(huntAverage(samples)).assertEqual(-66);
      expect(huntCueLevel(HuntCue.VERY_CLOSE)).assertEqual(3);
      expect(huntCueLevel(HuntCue.WAITING)).assertEqual(0);
      expect(huntCueKey(HuntCue.VERY_CLOSE)).assertEqual('very_close');
      expect(huntCueKey(HuntCue.QUIET)).assertEqual('quiet');
    });

    it('keeps a bounded sample history on the session', 0, () => {
      const session: HuntSession = new HuntSession('ble:aa', 'Target', 1000);
      for (let index = 0; index < HUNT_MAX_SAMPLES + 20; index += 1) session.addSample(-50 - (index % 10), 1000 + index);
      expect(session.samples.length).assertEqual(HUNT_MAX_SAMPLES);
      expect(session.targetKey).assertEqual('ble:aa');
      expect(session.lastSeen).assertEqual(1000 + HUNT_MAX_SAMPLES + 19);
      expect(session.peak() >= -60).assertTrue();
      expect(session.missing).assertFalse();
    });
  });
}
