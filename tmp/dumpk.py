# -*- coding: utf-8 -*-
import json, io
p = r'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/resources/base/element/string.json'
d = json.load(io.open(p, encoding='utf-8'))
for x in d['string']:
    if x['name'].startswith('auto_str_10'):
        print(x['name'], '=', x['value'])