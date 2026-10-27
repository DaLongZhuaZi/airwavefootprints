# -*- coding: utf-8 -*-
import json, io
base = r'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/resources/base/element/string.json'
en = r'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/resources/en_US/element/string.json'
b = {x['name']: x['value'] for x in json.load(io.open(base, encoding='utf-8'))['string']}
e = {x['name']: x['value'] for x in json.load(io.open(en, encoding='utf-8'))['string']}
out = []
for i in range(1092, 1105):
    k = 'auto_str_%d' % i
    out.append('%s | base=%s | en=%s' % (k, b.get(k), e.get(k)))
io.open(r'F:/DevEcoStudioProject/airwavefootprints/tmp/rt2.txt', 'w', encoding='utf-8').write('\n'.join(out))