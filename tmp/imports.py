# -*- coding: utf-8 -*-
import io, re
ROOT = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets'
jobs = [
 ('pages/fieldwatch/FieldwatchToolboxPage.ets', 'FIELDWATCH_TAB_BAR_RESERVE', '../../fieldwatch/ui/FieldwatchLayout'),
 ('pages/fieldwatch/FieldwatchHuntPage.ets', 'FIELDWATCH_SAFE_BOTTOM_GAP', '../../fieldwatch/ui/FieldwatchLayout'),
 ('pages/fieldwatch/FieldwatchSignatureEditorPage.ets', 'FIELDWATCH_SAFE_BOTTOM_GAP', '../../fieldwatch/ui/FieldwatchLayout'),
 ('pages/fieldwatch/FieldwatchFeedbackPage.ets', 'FIELDWATCH_SAFE_BOTTOM_GAP', '../../fieldwatch/ui/FieldwatchLayout'),
 ('pages/fieldwatch/FieldwatchSignaturesPage.ets', 'FIELDWATCH_TAB_BAR_RESERVE', '../../fieldwatch/ui/FieldwatchLayout'),
 ('fieldwatch/ui/FieldwatchWatchlistPage.ets', 'FIELDWATCH_SAFE_BOTTOM_GAP', './FieldwatchLayout'),
 ('fieldwatch/ui/FieldwatchSignatureDetail.ets', 'FIELDWATCH_SAFE_BOTTOM_GAP', './FieldwatchLayout'),
]
for rel, name, mod in jobs:
    p = ROOT + '/' + rel
    s = io.open(p, encoding='utf-8').read()
    if ('from %s' % repr(mod).replace(chr(39), chr(39))) in s or ("from '" + mod + "'") in s:
        print('has import', rel); continue
    lines = s.split('\n')
    idx = next(i for i, ln in enumerate(lines) if re.match(r'^import .*;$', ln))
    lines.insert(idx + 1, "import { %s } from '%s';" % (name, mod))
    io.open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
    print('import added', rel)