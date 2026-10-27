# -*- coding: utf-8 -*-
import json, re
cjk = re.compile(u'[\u4e00-\u9fff]')
bp = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\base\\element\\string.json'
ep = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\en_US\\element\\string.json'
b = {x['name']: x['value'] for x in json.load(open(bp, encoding='utf-8'))['string']}
e = {x['name']: x['value'] for x in json.load(open(ep, encoding='utf-8'))['string']}
missing = [k for k in b if k not in e]
extra = [k for k in e if k not in b]
zh = [(k, e[k]) for k in e if k in b and cjk.search(e[k])]
out = ['# en_US audit', '']
out.append('- base keys: %d, en_US keys: %d' % (len(b), len(e)))
out.append('- en_US missing: %d' % len(missing))
out.append('- en_US extra: %d' % len(extra))
out.append('- en_US values still Chinese: %d' % len(zh))
out.append('')
out.append('## values still Chinese')
for k, v in zh:
    out.append('- %s = %s' % (k, v))
if missing:
    out.append('')
    out.append('## missing keys')
    for k in missing[:120]:
        out.append('- %s = %s' % (k, b[k]))
open(r'F:\\DevEcoStudioProject\\airwavefootprints\\tmp\\i18n_audit.md', 'w', encoding='utf-8').write('\n'.join(out))
print('zh', len(zh), 'missing', len(missing), 'extra', len(extra))