# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/i18n_literals.json', encoding='utf-8'))
out = []
for rel in ['fieldwatch/radio/FieldwatchNearLinkScanner.ets','fieldwatch/data/FieldwatchSettingsRepository.ets','fieldwatch/domain/FieldwatchWidgetState.ets','fieldwatch/platform/FieldwatchFeedbackService.ets']:
    for it in d.get(rel, []):
        out.append('%s:%d | %s' % (rel.split('/')[-1], it['line'], it['ctx']))
open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/ctx2.txt','w',encoding='utf-8').write('\n'.join(out))