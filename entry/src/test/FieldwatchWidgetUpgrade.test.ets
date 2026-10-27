import { describe, it, expect } from '@ohos/hypium';
import {
  buildWidgetCardData, FieldwatchWidgetKeys, FieldwatchWidgetState, parseWidgetState,
  WIDGET_HEARTBEAT_TIMEOUT_SEC, widgetHeartbeatFresh
} from '../main/ets/fieldwatch/domain/FieldwatchWidgetState';

/**
 * 卡片内容升级（P1-8）。
 *
 * **断言口径说明**：卡片文案走 `ngfText(...)` 资源解析，而本地单测环境没有
 * 资源上下文，`ngfText` 返回空串。因此这里**不断言中文文案**，只断言
 * 「哪一项被计入 detailText」——判据是详情里是否出现了数字，
 * 这已经足以验证 P1-8 的两条规则（只在有内容时出现 / ≥70 才说跟随）。
 */

function freshState(now: number): FieldwatchWidgetState {
  const state: FieldwatchWidgetState = new FieldwatchWidgetState();
  state.running = true;
  state.heartbeatAt = now - 1000;
  return state;
}

export default function fieldwatchWidgetUpgradeTest() {
  describe('FieldwatchWidgetUpgrade', () => {
    // P1-8：两项只在「有」的时候出现。卡片常驻，天天摆「0 台/评分 0」只是噪声。
    it('adds new-device and follow lines only when they carry information', 0, () => {
      const now: number = 1000000;
      const quiet: FieldwatchWidgetState = freshState(now);
      quiet.newToday = 0;
      quiet.followScore = 0;
      const quietData: Record<string, string> = buildWidgetCardData(quiet, '2*2', now);
      // 没有任何计数 → 详情为空串（fallback 文案也依赖资源，单测里同样是空）。
      expect(quietData[FieldwatchWidgetKeys.DETAIL].length).assertEqual(0);

      const busy: FieldwatchWidgetState = freshState(now);
      busy.newToday = 3;
      busy.followScore = 82;
      const busyData: Record<string, string> = buildWidgetCardData(busy, '2*2', now);
      // 新增的两项各自带出数字：3（新设备数）与 82（跟随评分）。
      expect(busyData[FieldwatchWidgetKeys.DETAIL].indexOf('3') >= 0).assertTrue();
      expect(busyData[FieldwatchWidgetKeys.DETAIL].indexOf('82') >= 0).assertTrue();
    });

    // 45–70 只算「关注」，不写跟随：判据是详情里不出现该分数。
    it('keeps the follow line reserved for scores at or above 70', 0, () => {
      const now: number = 1000000;
      const watch: FieldwatchWidgetState = freshState(now);
      watch.followScore = 69;
      const watchData: Record<string, string> = buildWidgetCardData(watch, '2*2', now);
      expect(watchData[FieldwatchWidgetKeys.DETAIL].indexOf('69') < 0).assertTrue();

      const suspect: FieldwatchWidgetState = freshState(now);
      suspect.followScore = 70;
      const suspectData: Record<string, string> = buildWidgetCardData(suspect, '2*2', now);
      expect(suspectData[FieldwatchWidgetKeys.DETAIL].indexOf('70') >= 0).assertTrue();
    });

    // 旧数据里没有这两个字段，必须解析成 0 而不是崩或 NaN。
    it('parses legacy widget state without the new fields', 0, () => {
      const legacy: string = '{"running":true,"heartbeatAt":1000,"ble":5,"wifi":2,"nearLink":0}';
      const state: FieldwatchWidgetState = parseWidgetState(legacy);
      expect(state.newToday).assertEqual(0);
      expect(state.followScore).assertEqual(0);
      expect(state.ble).assertEqual(5);
    });

    // 沿用 updatedText 机制：应用不更新时卡片要能显示成「未运行」，
    // 不能被上一份快照里的旧数字继续撑着。
    it('falls back to the not-running text when the heartbeat is stale', 0, () => {
      const now: number = 10000000;
      const stale: FieldwatchWidgetState = new FieldwatchWidgetState();
      stale.running = true;
      stale.heartbeatAt = now - (WIDGET_HEARTBEAT_TIMEOUT_SEC + 10) * 1000;
      stale.newToday = 9;
      stale.followScore = 90;
      expect(widgetHeartbeatFresh(stale, now)).assertFalse();
      const data: Record<string, string> = buildWidgetCardData(stale, '2*4', now);
      expect(data[FieldwatchWidgetKeys.RUNNING]).assertEqual('false');
      // 过期快照的新字段**不渲染** —— 那正是「不误报旧数据」的意思。
      expect(data[FieldwatchWidgetKeys.DETAIL].indexOf('9') < 0).assertTrue();
      expect(data[FieldwatchWidgetKeys.DETAIL].indexOf('90') < 0).assertTrue();
    });
  });
}
