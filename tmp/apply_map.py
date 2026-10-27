# -*- coding: utf-8 -*-
import json, io, os, re, sys

ROOT = 'F:/DevEcoStudioProject/airwavefootprints'
BASE = ROOT + '/entry/src/main/resources/base/element/string.json'
EN = ROOT + '/entry/src/main/resources/en_US/element/string.json'

def load(p):
    with io.open(p, 'r', encoding='utf-8') as f:
        return json.load(f)

def save(p, data):
    tmp = p + '.new'
    with io.open(tmp, 'w', encoding='utf-8', newline='') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, p)

# 0) re-add language keys to base (they exist in en_US already)
b = load(BASE)
have = {x['name'] for x in b['string']}
for name, val in [('fieldwatch_settings_language', u'\u8bed\u8a00'), ('fieldwatch_settings_language_system', u'\u8ddf\u968f\u7cfb\u7edf')]:
    if name not in have:
        b['string'].append({'name': name, 'value': val})
        print('re-added base key', name)
save(BASE, b)

# 1) merge translation map into both resource files
MAP = load(ROOT + '/tmp/' + sys.argv[1])
TARGETS = sys.argv[2:]
for p, is_en in ((BASE, False), (EN, True)):
    d = load(p)
    have = {x['name'] for x in d['string']}
    added = 0
    for item in MAP:
        if item['key'] in have:
            continue
        d['string'].append({'name': item['key'], 'value': item['en'] if is_en else item['zh']})
        have.add(item['key'])
        added += 1
    save(p, d)
    print(('en' if is_en else 'base'), 'keys +%d, total %d' % (added, len(d['string'])))

# 2) replace literals in code
for t in TARGETS:
    p = ROOT + '/' + t
    with io.open(p, 'r', encoding='utf-8') as f:
        src = f.read()
    n = 0
    for item in MAP:
        lit = "'" + item['zh'] + "'"
        if lit in src:
            n += src.count(lit)
            src = src.replace(lit, "ngfText('app.string." + item['key'] + "')")
    if n > 0:
        if 'ngfText }' not in src and 'ngfText,' not in src:
            if "from 'ngf_framework';" in src:
                src = re.sub(r"import \{([^}]*)\} from 'ngf_framework';", lambda m: 'import {' + m.group(1).rstrip().rstrip(',') + ', ngfText } from \'ngf_framework\';', src, count=1)
            else:
                src = "import { ngfText } from 'ngf_framework';\n" + src
        with io.open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(src)
    print('code', t, 'replacements', n)