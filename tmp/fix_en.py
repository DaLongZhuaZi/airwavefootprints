# -*- coding: utf-8 -*-
import json, io, os
ROOT = 'F:/DevEcoStudioProject/airwavefootprints'
BASE = ROOT + '/entry/src/main/resources/base/element/string.json'
EN = ROOT + '/entry/src/main/resources/en_US/element/string.json'
def load(p):
    return json.load(io.open(p, encoding='utf-8'))
def save(p, d):
    tmp = p + '.new'
    io.open(tmp, 'w', encoding='utf-8', newline='').write(json.dumps(d, ensure_ascii=False, indent=2))
    os.replace(tmp, p)
spec = load(ROOT + '/tmp/fix_en.json')
b = load(BASE); e = load(EN)
bmap = {x['name']: x for x in b['string']}
emap = {x['name']: x for x in e['string']}
nb = ne = 0
for item in spec['rt'] + spec['priv']:
    k = item['key']
    if k in bmap and bmap[k]['value'] != item['zh']:
        bmap[k]['value'] = item['zh']; nb += 1
    if k in emap and emap[k]['value'] != item['en']:
        emap[k]['value'] = item['en']; ne += 1
save(BASE, b); save(EN, e)
print('base updated', nb, 'en updated', ne)
# re-audit
import re
cjk = re.compile(u'[\u4e00-\u9fff]')
left = [(k, v) for k, v in ((x['name'], x['value']) for x in load(EN)['string']) if cjk.search(v)]
print('en still CJK:', len(left))
for k, v in left[:10]:
    print('  ', k, '=', v[:40])