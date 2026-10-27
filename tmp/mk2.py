# -*- coding: utf-8 -*-
import json
d = json.load(open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/i18n_literals.json', encoding='utf-8'))
rel = 'fieldwatch/ui/FieldwatchDeviceTypeIcon.ets'
out = []
for it in d.get(rel, []):
    out.append('%d|%s' % (it['line'], it['lit'][1:-1]))
open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/zh_dt.txt','w',encoding='utf-8').write('\n'.join(out))
print(len(out))