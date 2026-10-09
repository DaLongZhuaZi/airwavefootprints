import { describe, expect, it } from '@ohos/hypium';
import { FieldwatchPalette, FieldwatchPaletteHolder } from '../main/ets/fieldwatch/ui/FieldwatchPalette';

export default function fieldwatchUiThemeTest() {
  describe('FieldwatchUiTheme', () => {
    it('exposes the original Fieldwatch dark tokens', 0, () => {
      const dark: FieldwatchPalette = FieldwatchPalette.dark();
      expect(dark.night).assertEqual('#0B0F14');
      expect(dark.panel).assertEqual('#141A22');
      expect(dark.panel2).assertEqual('#1B232D');
      expect(dark.accent).assertEqual('#3DFF9A');
      expect(dark.accentActive).assertEqual('#35D683');
      expect(dark.onAccent).assertEqual('#003820');
      expect(dark.amber).assertEqual('#FFB020');
      expect(dark.signalRed).assertEqual('#FF3D5A');
      expect(dark.cyan).assertEqual('#4FC3F7');
      expect(dark.text).assertEqual('#D5DCE3');
      expect(dark.textDim).assertEqual('#9AA6B2');
    });

    it('keeps a designed light counterpart for every token', 0, () => {
      const light: FieldwatchPalette = FieldwatchPalette.light();
      expect(light.night).assertEqual('#F4F6F8');
      expect(light.panel).assertEqual('#FFFFFF');
      expect(light.accent).assertEqual('#0B7A48');
      expect(light.onAccent).assertEqual('#FFFFFF');
      // 浅色不能复用深色的近黑底，否则文字对比度会失效
      expect(light.night === FieldwatchPalette.dark().night).assertFalse();
      expect(light.text === FieldwatchPalette.dark().text).assertFalse();
    });

    it('selects the palette by darkness and defaults to dark', 0, () => {
      expect(FieldwatchPalette.of(true).night).assertEqual('#0B0F14');
      expect(FieldwatchPalette.of(false).night).assertEqual('#F4F6F8');
      // 未写入 AppStorage 时必须是深色（Fieldwatch 是夜战风格，默认不跟随系统）
      expect(FieldwatchPaletteHolder.get().accent).assertEqual('#3DFF9A');
    });

  });
}
