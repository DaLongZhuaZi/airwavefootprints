# -*- coding: utf-8 -*-
import io, re
ROOT = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets'

def rw(rel, fn):
    p = ROOT + '/' + rel
    s = io.open(p, encoding='utf-8').read()
    s2 = fn(s)
    if s2 != s:
        io.open(p, 'w', encoding='utf-8', newline='').write(s2)
        print('patched', rel)
    else:
        print('NO CHANGE', rel)

def page(s):
    s = s.replace('topInset: this.topInsetVp,', 'topInset: this.topInsetVp, bottomInset: this.bottomInsetVp,')
    s = s.replace('FieldwatchLivePage({ visible: this.selectedTab === 0,', 'FieldwatchLivePage({ bottomInset: this.bottomInsetVp, visible: this.selectedTab === 0,')
    s = s.replace('top: 14, bottom: 112 })', 'top: 14, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })')
    s = s.replace('top: this.topInset + 8, bottom: 48 })', 'top: this.topInset + 8, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })')
    s = s.replace('top: this.topInset + 16, bottom: 48 })', 'top: this.topInset + 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })')
    s = s.replace('.padding({ left: 16, right: 16 })\n', '.padding({ left: 16, right: 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })\n')
    s = s.replace('.padding({ left: 14, right: 14 })\n', '.padding({ left: 14, right: 14, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })\n')
    return s

rw('pages/fieldwatch/FieldwatchPage.ets', page)

def toolbox(s):
    s = s.replace('FieldwatchFindPage({ topInset: this.topInset })', 'FieldwatchFindPage({ topInset: this.topInset, bottomInset: this.bottomInset })')
    return s

rw('pages/fieldwatch/FieldwatchToolboxPage.ets', toolbox)

def find(s):
    s = s.replace("import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';", "import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';\nimport { FIELDWATCH_TAB_BAR_RESERVE } from '../../fieldwatch/ui/FieldwatchLayout';")
    s = s.replace('top: this.topInset + 12, bottom: 24 })', 'top: this.topInset + 12, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })')
    return s

rw('pages/fieldwatch/FieldwatchFindPage.ets', find)