# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/i18n_literals.json', encoding='utf-8'))
files = ['pages/fieldwatch/FieldwatchPage.ets','pages/fieldwatch/FieldwatchToolboxPage.ets','pages/fieldwatch/FieldwatchFeedbackPage.ets','pages/fieldwatch/FieldwatchSignatureEditorPage.ets','fieldwatch/ui/FieldwatchFindWizard.ets','pages/fieldwatch/FieldwatchDeviceDetailPage.ets','fieldwatch/domain/FieldwatchChangelog.ets','fieldwatch/domain/FieldwatchWidgetState.ets','fieldwatch/domain/FieldwatchRadioDb.ets','fieldwatch/platform/FieldwatchFeedbackService.ets','fieldwatch/radio/FieldwatchWifiScanner.ets','fieldwatch/radio/FieldwatchBleScanner.ets','fieldwatch/radio/FieldwatchNearLinkScanner.ets','fieldwatch/data/FieldwatchSettingsRepository.ets']
out = []
for rel in files:
    items = d.get(rel, [])
    if not items: continue
    out.append('## ' + rel)
    for it in items:
        out.append('%d|%s' % (it['line'], it['lit'][1:-1]))
open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/zh_rest.txt','w',encoding='utf-8').write('\n'.join(out))
print('lines', len(out))