# -*- coding: utf-8 -*-
import json, re, os
bp = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\base\\element\\string.json'
ep = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\en_US\\element\\string.json'
b = {x['name']: x['value'] for x in json.load(open(bp, encoding='utf-8'))['string']}
e = {x['name']: x['value'] for x in json.load(open(ep, encoding='utf-8'))['string']}
probe = [u'已选特征', u'精细筛选', u'刚出现的', u'信道分析', u'类别', u'特征目录', u'对比观测', u'会话小结']
out = []
for p in probe:
    hitb = [k for k, v in b.items() if p in v]
    hite = [k for k, v in e.items() if p in v]
    out.append('%s -> base=%s en=%s' % (p, hitb[:3], hite[:3]))
print(); print('\n'.join(out))
print('--- sample en values ---')
for k in ['fieldwatch_filters_selected_title', 'fieldwatch_filters_fine_title']:
    print(k, '=', b.get(k), '|', e.get(k))