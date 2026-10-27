# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:\\DevEcoStudioProject\\airwavefootprints\\tmp\\i18n_literals.json', encoding='utf-8'))
files = ['fieldwatch/domain/FieldwatchDeviceExplain.ets','fieldwatch/domain/FieldwatchDeviceTypeIcon.ets','fieldwatch/domain/FieldwatchCandidateEngine.ets']
out = []
n = 0
for rel in files:
    for it in d.get(rel, []):
        n += 1
        out.append('%s:%d|%s' % (rel.split('/')[-1], it['line'], it['lit'][1:-1]))
open(r'F:\\DevEcoStudioProject\\airwavefootprints\\tmp\\zh_list.txt','w',encoding='utf-8').write('\n'.join(out))
print('items', n)