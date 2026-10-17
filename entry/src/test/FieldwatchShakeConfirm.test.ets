import { describe, it, expect } from '@ohos/hypium';
import {
  decideShaken, ShakeCandidate, ShakeDecision, ShakeSample, scoreShake, shakeSpread, SHAKE_MIN_SAMPLES,
  staticStrongSuspect, STATIC_SUSPECT_MIN_SAMPLES, STATIC_SUSPECT_WINDOW_MS
} from '../main/ets/fieldwatch/domain/FieldwatchShakeConfirm';

const NOW: number = 100000;

/** 造一串采样：每 stepMs 一个点，强度按 values 给。 */
function samples(values: number[], stepMs: number = 500): ShakeSample[] {
  const out: ShakeSample[] = [];
  values.forEach((value: number, index: number): void => {
    out.push(new ShakeSample(value, NOW - (values.length - 1 - index) * stepMs));
  });
  return out;
}

/** 造一台候选：直接给极差，便于只测决策规则。 */
function candidate(key: string, spread: number): ShakeCandidate {
  const item: ShakeCandidate = new ShakeCandidate();
  item.key = key;
  item.spread = spread;
  item.moving = spread >= 8;
  return item;
}

export default function fieldwatchShakeConfirmTest() {
  describe('FieldwatchShakeConfirm', () => {
    it('refuses to judge when there are too few samples', 0, () => {
      // 2 个点随便都能拉出 6 dB，样本不足时必须返回 -1（「还不知道」），而不是 0。
      expect(shakeSpread(samples([-50, -44]), NOW)).assertEqual(-1);
      expect(scoreShake('a', samples([-50, -44, -40]), NOW).moving).assertFalse();
      expect(SHAKE_MIN_SAMPLES).assertEqual(4);
    });

    it('ignores samples older than the window', 0, () => {
      const mixed: ShakeSample[] = [
        new ShakeSample(-30, NOW - 9000),
        new ShakeSample(-80, NOW - 8500),
        new ShakeSample(-60, NOW - 1000),
        new ShakeSample(-60, NOW - 800),
        new ShakeSample(-60, NOW - 600),
        new ShakeSample(-60, NOW - 400)
      ];
      // 窗口外的 -30/-80（极差 50）不能影响判定：窗内是平的 → 极差 0。
      expect(shakeSpread(mixed, NOW)).assertEqual(0);
    });

    it('measures spread and flags a moving device', 0, () => {
      const still: ShakeCandidate = scoreShake('still', samples([-50, -51, -49, -50]), NOW);
      expect(still.spread).assertEqual(2);
      expect(still.moving).assertFalse();
      const shaken: ShakeCandidate = scoreShake('shaken', samples([-50, -62, -48, -58]), NOW);
      expect(shaken.spread).assertEqual(14);
      expect(shaken.moving).assertTrue();
    });

    it('picks the only moving device', 0, () => {
      const decision: ShakeDecision = decideShaken([candidate('still', 2), candidate('shaken', 14)]);
      expect(decision.decided).assertTrue();
      expect(decision.key).assertEqual('shaken');
    });

    it('never picks a rock-steady strong signal', 0, () => {
      // 文档 §7.3 的「贴在墙上、纹丝不动的最强信号」：强度最高但在动的是另一台。
      const decision: ShakeDecision = decideShaken([candidate('wall', 1), candidate('mine', 9)]);
      expect(decision.decided).assertTrue();
      expect(decision.key).assertEqual('mine');
      // 两台都不动时：不猜。
      expect(decideShaken([candidate('wall', 1), candidate('other', 3)]).decided).assertFalse();
    });

    it('requires a clear lead when several candidates move', 0, () => {
      // 两台都在动：领先不够多就不选（差 3 dB < 领先阈值 4 dB）。
      const close: ShakeDecision = decideShaken([candidate('a', 12), candidate('b', 9)]);
      expect(close.decided).assertFalse();
      // 领先足够（差 6 dB）才选。
      const clear: ShakeDecision = decideShaken([candidate('a', 15), candidate('b', 9)]);
      expect(clear.decided).assertTrue();
      expect(clear.key).assertEqual('a');
    });

    it('flags a strong-but-frozen signal as suspicious', 0, () => {
      // 文档 §7.3：纹丝不动的最强信号可能是别的同款设备 —— 只提示，不断言。
      const frozen: ShakeSample[] = samples([-40, -41, -40, -39, -41, -40], 1500);
      expect(staticStrongSuspect(frozen, NOW)).assertTrue();
      // 有起伏就不算「一直没变化」。
      const lively: ShakeSample[] = samples([-40, -52, -44, -60, -41, -55], 1500);
      expect(staticStrongSuspect(lively, NOW)).assertFalse();
    });

    it('refuses to judge a frozen signal on too few or stale samples', 0, () => {
      // 样本不足：刚进来两三个包就说「它没动」会误伤正在靠近的用户。
      expect(staticStrongSuspect(samples([-40, -40, -41]), NOW)).assertFalse();
      expect(STATIC_SUSPECT_MIN_SAMPLES).assertEqual(6);
      // 窗口外的高方差与窗内的平稳混在一起时，只按窗内判。
      const mixed: ShakeSample[] = [
        new ShakeSample(-90, NOW - STATIC_SUSPECT_WINDOW_MS - 5000),
        new ShakeSample(-30, NOW - STATIC_SUSPECT_WINDOW_MS - 4000)
      ];
      for (let i: number = 0; i < 6; i += 1) mixed.push(new ShakeSample(-40, NOW - 1000 - i * 500));
      expect(staticStrongSuspect(mixed, NOW)).assertTrue();
    });

    it('keeps every candidate in the decision for the UI to draw', 0, () => {
      const decision: ShakeDecision = decideShaken([candidate('a', 15), candidate('b', 2), candidate('c', 9)]);
      expect(decision.candidates.length).assertEqual(3);
      // UI 按这个顺序画「附近第 N 台」：顺序必须稳定（就是传入顺序）。
      expect(decision.candidates[0].key).assertEqual('a');
      expect(decision.candidates[2].key).assertEqual('c');
    });
  });
}
