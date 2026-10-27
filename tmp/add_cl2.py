# -*- coding: utf-8 -*-
import json, io, os
ROOT = 'F:/DevEcoStudioProject/airwavefootprints'
BASE = ROOT + '/entry/src/main/resources/base/element/string.json'
EN = ROOT + '/entry/src/main/resources/en_US/element/string.json'
def load(p): return json.load(io.open(p, encoding='utf-8'))
def save(p, d):
    tmp = p + '.new'
    io.open(tmp, 'w', encoding='utf-8', newline='').write(json.dumps(d, ensure_ascii=False, indent=2))
    os.replace(tmp, p)
items = [
 ('fw_cl_fix_1', u'统一页面底部留白：滚到底时最后一块内容不再被底栏遮住',
  u'Consistent bottom spacing: the last card is no longer hidden behind the tab bar'),
 ('fw_cl_fix_2', u'修复「找东西」页无法上下滑动的问题',
  u'Fixed: the Find things page could not be scrolled'),
]
for p, is_en in ((BASE, False), (EN, True)):
    d = load(p)
    have = {x['name'] for x in d['string']}
    added = 0
    for k, zh, en in items:
        if k in have: continue
        d['string'].append({'name': k, 'value': en if is_en else zh})
        added += 1
    save(p, d)
    print(('en' if is_en else 'base'), '+%d' % added, 'total', len(d['string']))