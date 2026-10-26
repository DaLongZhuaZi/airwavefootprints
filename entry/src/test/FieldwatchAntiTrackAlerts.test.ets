import { describe, it, expect } from '@ohos/hypium';
import {
  ANTI_TRACK_DEDUP_MS, ANTI_TRACK_EVAL_INTERVAL_MS, ANTI_TRACK_PUSH_SCORE, ANTI_TRACK_WATCH_SCORE,
  AntiTrackDecision, AntiTrackPushRecord, decideAntiTrackPush, pushLabelOf, recentlyPushed,
  recordPushes, shouldEvaluate
} from '../main/ets/fieldwatch/domain/FieldwatchAntiTrackAlerts';
import { FollowRisk, TrackEvidence, TrackSuspect } from '../main/ets/fieldwatch/domain/FieldwatchAntiTracking';

function suspectOf(key: string, score: number, label: string = ''): TrackSuspect {
  const suspect: TrackSuspect = new TrackSuspect();
  suspect.key = key;
  suspect.label = label;
  suspect.risk = score >= 70 ? FollowRisk.SUSPECT : (score >= 45 ? FollowRisk.WATCH : FollowRisk.NONE);
  const evidence: TrackEvidence = new TrackEvidence();
  evidence.score = score;
  suspect.evidence = evidence;
  return suspect;
}

export default function fieldwatchAntiTrackAlertsTest() {
  describe('FieldwatchAntiTrackAlerts', () => {
    // 文档口径：≥70 才推送，45–70 只进清单。这条线必须与评分引擎同值，
    // 否则会出现「面板说是嫌疑、通知却不说」或反过来。
    it('pushes only at the suspect threshold and keeps watch entries listed', 0, () => {
      expect(ANTI_TRACK_PUSH_SCORE).assertEqual(70);
      expect(ANTI_TRACK_WATCH_SCORE).assertEqual(45);
      const suspects: TrackSuspect[] = [
        suspectOf('a', 85), suspectOf('b', 70), suspectOf('c', 69), suspectOf('d', 45), suspectOf('e', 44)
      ];
      const decision: AntiTrackDecision = decideAntiTrackPush(suspects, [], 1000);
      // 85 与 70 都推；69/45/44 不推。
      expect(decision.pushKeys.length).assertEqual(2);
      expect(decision.pushKeys[0]).assertEqual('a');
      expect(decision.pushKeys[1]).assertEqual('b');
      // 清单里保留 45 分以上（含 69、45），44 分不进清单。
      expect(decision.watchKeys.length).assertEqual(4);
      expect(decision.shouldNotify()).assertTrue();
    });

    // 24 小时去重：这是「不骚扰」的唯一保障。15 分钟一轮，没有它一小时就报 4 次。
    it('deduplicates the same target within 24 hours', 0, () => {
      const now: number = 1000000;
      const history: AntiTrackPushRecord[] = [new AntiTrackPushRecord('a', now - 1000)];
      const decision: AntiTrackDecision = decideAntiTrackPush([suspectOf('a', 90), suspectOf('b', 90)], history, now);
      expect(decision.pushKeys.length).assertEqual(1);
      expect(decision.pushKeys[0]).assertEqual('b');
      expect(decision.dedupedCount).assertEqual(1);
      // 刚过 24 小时就允许再推。
      const expired: AntiTrackPushRecord[] = [new AntiTrackPushRecord('a', now - ANTI_TRACK_DEDUP_MS)];
      expect(recentlyPushed('a', expired, now)).assertFalse();
      // 差一毫秒仍算「刚推过」。
      const justInside: AntiTrackPushRecord[] = [new AntiTrackPushRecord('a', now - ANTI_TRACK_DEDUP_MS + 1)];
      expect(recentlyPushed('a', justInside, now)).assertTrue();
    });

    it('records pushes and drops expired history entries', 0, () => {
      const now: number = 5000000;
      const history: AntiTrackPushRecord[] = [
        new AntiTrackPushRecord('old', now - ANTI_TRACK_DEDUP_MS - 1),
        new AntiTrackPushRecord('fresh', now - 1000)
      ];
      const next: AntiTrackPushRecord[] = recordPushes(history, ['new-a'], now);
      // 过期的那条被清掉，未过期的保留，新的追加。
      expect(next.length).assertEqual(2);
      expect(next[0].key).assertEqual('fresh');
      expect(next[1].key).assertEqual('new-a');
    });

    // 15 分钟节流：应用被切后台再回来要能立刻补一次，而不是再等满一轮。
    it('evaluates immediately on first run and then every 15 minutes', 0, () => {
      expect(shouldEvaluate(0, 1000)).assertTrue();
      expect(shouldEvaluate(1000, 1000 + ANTI_TRACK_EVAL_INTERVAL_MS - 1)).assertFalse();
      expect(shouldEvaluate(1000, 1000 + ANTI_TRACK_EVAL_INTERVAL_MS)).assertTrue();
    });

    it('falls back to the device key when there is no display name', 0, () => {
      expect(pushLabelOf(suspectOf('ble:AA:BB', 80))).assertEqual('ble:AA:BB');
      expect(pushLabelOf(suspectOf('ble:AA:BB', 80, '我的耳机'))).assertEqual('我的耳机');
    });
  });
}
