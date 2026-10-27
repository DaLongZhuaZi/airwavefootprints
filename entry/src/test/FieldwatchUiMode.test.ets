import { describe, it, expect } from '@ohos/hypium';
import { AppSettings, FieldwatchUiMode } from '../main/ets/fieldwatch/domain/FieldwatchModels';

export default function fieldwatchUiModeTest() {
  describe('FieldwatchUiMode', () => {
    // 模式只决定首屏，不参与采集/匹配/导出。这里钉住两件容易改坏的事：
    //   ① 非法值必须回落 pro，而不是 daily —— 宁可多给能力，不要少给；
    //   ② AppSettings 的兜底值必须是 pro，否则「读不到存储」会被误当成「用户选了日常」。
    it('normalises unknown values to pro', 0, () => {
      expect(FieldwatchUiMode.normalize(FieldwatchUiMode.DAILY)).assertEqual(FieldwatchUiMode.DAILY);
      expect(FieldwatchUiMode.normalize(FieldwatchUiMode.PRO)).assertEqual(FieldwatchUiMode.PRO);
      // 备份文件被手改、旧版本写了个别的串、空串…… 一律回落到 pro。
      expect(FieldwatchUiMode.normalize('DAILY')).assertEqual(FieldwatchUiMode.PRO);
      expect(FieldwatchUiMode.normalize('daily ')).assertEqual(FieldwatchUiMode.PRO);
      expect(FieldwatchUiMode.normalize('')).assertEqual(FieldwatchUiMode.PRO);
      expect(FieldwatchUiMode.normalize('expert')).assertEqual(FieldwatchUiMode.PRO);
    });

    it('defaults AppSettings to pro so an unread store never means daily', 0, () => {
      // 构造期的 load() 早于存储就绪，读到的全是默认值。若默认是 daily，
      // 老用户每次冷启动都会先闪一下日常首屏。
      expect(new AppSettings().uiMode).assertEqual(FieldwatchUiMode.PRO);
    });

    it('keeps the two mode literals stable', 0, () => {
      // 这两个串会写进本地设置与备份文件，改字面量等于让所有存量用户的模式失效。
      expect(FieldwatchUiMode.DAILY).assertEqual('daily');
      expect(FieldwatchUiMode.PRO).assertEqual('pro');
    });
  });
}
