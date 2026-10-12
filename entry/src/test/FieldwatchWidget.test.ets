import { describe, expect, it } from '@ohos/hypium';
import {
  buildWidgetCardData, dimensionOfWidgetForm, encodeWidgetForms, FieldwatchWidgetForm, FieldwatchWidgetState,
  parseWidgetForms, parseWidgetState, removeWidgetForm, upsertWidgetForm, widgetHeartbeatFresh
} from '../main/ets/fieldwatch/domain/FieldwatchWidgetState';

export default function fieldwatchWidgetTest() {
  describe('FieldwatchWidget', () => {
    it('preserves a registered form dimension when an extension re-registers it', 0, () => {
      const existing: FieldwatchWidgetForm[] = [
        new FieldwatchWidgetForm('form-small', '2*2'),
        new FieldwatchWidgetForm('form-large', '2*4')
      ];
      const reloaded: FieldwatchWidgetForm[] = parseWidgetForms(encodeWidgetForms(existing));
      const updated: FieldwatchWidgetForm[] = upsertWidgetForm(reloaded,
        new FieldwatchWidgetForm('form-large', '2*4'));
      expect(updated.length).assertEqual(2);
      expect(dimensionOfWidgetForm(updated, 'form-large')).assertEqual('2*4');
    });

    it('removes only the uninstalled widget registration', 0, () => {
      const forms: FieldwatchWidgetForm[] = [
        new FieldwatchWidgetForm('form-a', '2*2'),
        new FieldwatchWidgetForm('form-b', '2*4')
      ];
      const remaining: FieldwatchWidgetForm[] = removeWidgetForm(forms, 'form-a');
      expect(remaining.length).assertEqual(1);
      expect(remaining[0].id).assertEqual('form-b');
      expect(dimensionOfWidgetForm(remaining, 'form-a') === undefined).assertTrue();
    });

    it('expires stale heartbeat data and reports fresh local radio counts', 0, () => {
      const state: FieldwatchWidgetState = new FieldwatchWidgetState();
      state.running = true;
      state.heartbeatAt = 100000;
      state.ble = 12;
      state.wifi = 4;
      state.nearLink = 2;
      state.familyLabel = 'Beacon family';
      state.familyAgeSec = 3;
      expect(widgetHeartbeatFresh(state, 110000)).assertTrue();
      expect(widgetHeartbeatFresh(state, 200000)).assertFalse();
      const fresh: Record<string, string> = buildWidgetCardData(state, '2*4', 110000);
      const freshJson: string = JSON.stringify(fresh);
      expect(freshJson).assertContain('BLE 12');
      expect(freshJson).assertContain('Wi-Fi 4');
      expect(freshJson).assertContain('Beacon family');
      const stale: Record<string, string> = buildWidgetCardData(state, '2*4', 200000);
      const staleJson: string = JSON.stringify(stale);
      expect(staleJson).assertContain('"running":"false"');
      expect(staleJson).assertContain('app 未运行');
    });

    it('handles malformed snapshots without breaking the card', 0, () => {
      const state: FieldwatchWidgetState = parseWidgetState('{broken');
      expect(state.running).assertFalse();
      expect(state.ble).assertEqual(0);
    });
  });
}
