# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/i18n_literals.json', encoding='utf-8'))
out = []
for rel in ['fieldwatch/domain/FieldwatchCandidateEngine.ets','fieldwatch/domain/FieldwatchDeviceExplain.ets','pages/fieldwatch/FieldwatchPage.ets','fieldwatch/radio/FieldwatchBleScanner.ets','fieldwatch/ui/FieldwatchFindWizard.ets']:
    for it in d.get(rel, []):
        out.append('%s:%d | %s' % (rel.split('/')[-1], it['line'], it['ctx']))
open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/ctx3.txt','w',encoding='utf-8').write('\n'.join(out))