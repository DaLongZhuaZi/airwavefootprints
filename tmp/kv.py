# -*- coding: utf-8 -*-
import json
bp = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\base\\element\\string.json'
ep = r'F:\\DevEcoStudioProject\\airwavefootprints\\entry\\src\\main\\resources\\en_US\\element\\string.json'
b = {x['name']: x['value'] for x in json.load(open(bp, encoding='utf-8'))['string']}
e = {x['name']: x['value'] for x in json.load(open(ep, encoding='utf-8'))['string']}
keys = ['fieldwatch_filter_selected_signatures','fieldwatch_filter_fine','fieldwatch_filter_show_selected','fieldwatch_toolbox_tab_channel','fieldwatch_reports_compare','fieldwatch_signatures_category_all']
lines = []
for k in keys:
    lines.append('%s' % k)
    lines.append('  base: %s' % b.get(k))
    lines.append('  en  : %s' % e.get(k))
open(r'F:\\DevEcoStudioProject\\airwavefootprints\\tmp\\kv.txt','w',encoding='utf-8').write('\n'.join(lines))