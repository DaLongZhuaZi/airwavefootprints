import { describe, it, expect } from '@ohos/hypium';
import {
  buildWidgetCardData, FieldwatchWidgetKeys, FieldwatchWidgetState, parseWidgetState,
  WIDGET_HEARTBEAT_TIMEOUT_SEC, widgetHeartbeatFresh
} from '../main/ets/fieldwatch/domain/FieldwatchWidgetState';

function freshState(now: number): FieldwatchWidgetState {
  const state: FieldwatchWidgetState = new FieldwatchWidgetState();
  state.running = true;
  state.heartbeatAt = now - 1000;
  return state;
}

export default function fieldwatchWidgetUpgradeTest() {
  describe('FieldwatchWidgetUpgrade', () => {
    // P1-8：新增的两项只在「有」的时候出现。卡片是常驻的，
    // 天天摆在屏幕上的「0 台新设备」「评分 0」只会变成噪声。
    it('adds new-device and follow lines only when they carry information', 0, () => {
      const now: number = 1000000;
      const quiet: FieldwatchWidgetState = freshState(now);
      quiet.newToday = 0;
      quiet.followScore = 0;
      const quietData: Record<string, string> = buildWidgetCardData(quiet, '2*2', now);
      expect(quietData[FieldwatchWidgetKeys.DETAIL].indexOf('今天新认识') < 0).assertTrue();
      expect(quietData[FieldwatchWidgetKeys.DETAIL].indexOf('跟着你') < 0).assertTrue();

      const busy: FieldwatchWidgetState = freshState(now);
      busy.newToday = 3;
      busy.followScore = 82;
      const busyData: Record<string, string> = buildWidgetCardData(busy, '2*2', now);
      expect(busyData[FieldwatchWidgetKeys.DETAIL].indexOf('今天新认识了 3 种设备') >= 0).assertTrue();
      expect(busyData[FieldwatchWidgetKeys.DETAIL].indexOf('有设备可能跟着你') >= 0).assertTrue();
    });

    // 45–70 只算「关注」，绝不能说成「跟着你」—— 措辞重的代价是吓到用户。
    it('keeps the follow wording reserved for scores at or above 70', 0, () => {
      const now: number = 1000000;
      const watch: FieldwatchWidgetState = freshState(now);
      watch.followScore = 69;
      const watchData: Record<string, string> = buildWidgetCardData(watch, '2*2', now);
      expect(watchData[FieldwatchWidgetKeys.DETAIL].indexOf('跟着你') < 0).assertTrue();

      const suspect: FieldwatchWidgetState = freshState(now);
      suspect.followScore = 70;
      const suspectData: Record<string, string> = buildWidgetCardData(suspect, '2*2', now);
      expect(suspectData[FieldwatchWidgetKeys.DETAIL].indexOf('跟着你') >= 0).assertTrue();
    });

    // 旧数据（升级前写入的设置）里没有这两个字段，必须解析成 0 而不是崩或 NaN。
    it('parses legacy widget state without the new fields', 0, () => {
      const legacy: string = '{"running":true,"heartbeatAt":1000,"ble":5,"wifi":2,"nearLink":0}';
      const state: FieldwatchWidgetState = parseWidgetState(legacy);
      expect(state.newToday).assertEqual(0);
      expect(state.followScore).assertEqual(0);
      expect(state.ble).assertEqual(5);
    });

    // 沿用现有 updatedText 机制：应用不更新时卡片要能显示成「未运行」，
    // 不能被上一份快照里的旧数字继续撑着。
    it('falls back to the not-running text when the heartbeat is stale', 0, () => {
      const now: number = 10000000;
      const stale: FieldwatchWidgetState = new FieldwatchWidgetState();
      stale.running = true;
      stale.heartbeatAt = now - (WIDGET_HEARTBEAT_TIMEOUT_SEC + 10) * 1000;
      stale.newToday = 9;
      stale.followScore = 90;
      expect(widgetHeartbeatFresh(stale, now)).assertFalse();
      const data: Record<string, string> = buildWidgetCardData(stale, '2*2', now);
      expect(data[FieldwatchWidgetKeys.RUNNING]).assertEqual('false');
      // 过期快照里的新字段**不渲染** —— 那正是「不误报旧数据」的意思。
      expect(data[FieldwatchWidgetKeys.DETAIL].indexOf('今天新认识') < 0).assertTrue();
      expect(data[FieldwatchWidgetKeys.DETAIL].indexOf('跟着你') < 0).assertTrue();
    });
  });
}
