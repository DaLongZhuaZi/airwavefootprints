# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/i18n_literals.json', encoding='utf-8'))
out = []
for rel in ['fieldwatch/domain/FieldwatchCandidateEngine.ets','pages/fieldwatch/FieldwatchPage.ets','fieldwatch/radio/FieldwatchBleScanner.ets']:
    for it in d.get(rel, []):
        if it['line'] in (341, 2711, 212):
            out.append('%s:%d | %s' % (rel.split('/')[-1], it['line'], it['lit']))
open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/exact.txt','w',encoding='utf-8').write('\n'.join(out))