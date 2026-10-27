# -*- coding: utf-8 -*-
import io, re
ROOT = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets'

def ensure_import(s, names, rel):
    if 'FieldwatchLayout' in s:
        return s
    imp = "import { %s } from '%s';" % (names, rel)
    lines = s.split('\n')
    last = -1
    for i, ln in enumerate(lines[:60]):
        if ln.startswith('import ') and ln.rstrip().endswith(';'):
            last = i
    lines.insert(last + 1, imp)
    return '\n'.join(lines)

def patch(rel, fn, imports=None, imp_rel=None):
    p = ROOT + '/' + rel
    s = io.open(p, encoding='utf-8').read()
    s2 = fn(s)
    if imports:
        s2 = ensure_import(s2, imports, imp_rel)
    if s2 != s:
        io.open(p, 'w', encoding='utf-8', newline='').write(s2)
        print('patched', rel)
    else:
        print('NO CHANGE', rel)

TAB = 'FIELDWATCH_TAB_BAR_RESERVE'
SAFE = 'FIELDWATCH_SAFE_BOTTOM_GAP'

# toolbox
patch('pages/fieldwatch/FieldwatchToolboxPage.ets',
      lambda s: s.replace('top: 12, bottom: 48 })', 'top: 12, bottom: this.bottomInset + %s })' % TAB),
      TAB, '../../fieldwatch/ui/FieldwatchLayout')

# hunt
patch('pages/fieldwatch/FieldwatchHuntPage.ets',
      lambda s: s.replace('top: this.contentTop(), bottom: 48 })', 'top: this.contentTop(), bottom: this.bottomInset + %s })' % SAFE),
      SAFE, '../../fieldwatch/ui/FieldwatchLayout')

# editor
patch('pages/fieldwatch/FieldwatchSignatureEditorPage.ets',
      lambda s: s.replace('top: this.contentTop(), bottom: 48 })', 'top: this.contentTop(), bottom: this.bottomInset + %s })' % SAFE),
      SAFE, '../../fieldwatch/ui/FieldwatchLayout')

# feedback
patch('pages/fieldwatch/FieldwatchFeedbackPage.ets',
      lambda s: s.replace('bottom: 48 })', 'bottom: this.bottomInset + %s })' % SAFE),
      SAFE, '../../fieldwatch/ui/FieldwatchLayout')

# watchlist
patch('fieldwatch/ui/FieldwatchWatchlistPage.ets',
      lambda s: s.replace('top: this.withShell ? this.contentTop() : 20, bottom: 20 })', 'top: this.withShell ? this.contentTop() : 20, bottom: this.bottomInset + %s })' % SAFE),
      SAFE, './FieldwatchLayout')

# signature detail
patch('fieldwatch/ui/FieldwatchSignatureDetail.ets',
      lambda s: s.replace('top: this.withShell ? this.contentTop() : 20, bottom: 20 })', 'top: this.withShell ? this.contentTop() : 20, bottom: this.bottomInset + %s })' % SAFE),
      SAFE, './FieldwatchLayout')

# signatures list padding
patch('pages/fieldwatch/FieldwatchSignaturesPage.ets',
      lambda s: s.replace('.lanes(this.twoColumn ? 2 : 1, 8)', '.lanes(this.twoColumn ? 2 : 1, 8)\n    .padding({ bottom: this.bottomInset + %s })' % TAB),
      TAB, '../../fieldwatch/ui/FieldwatchLayout')

# device detail: own bottom inset state + padding
def detail(s):
    s = s.replace('@State private topInsetVp: number = 28;', '@State private topInsetVp: number = 28;\n  /** 系统底部导航条高度；页面底部内容要与它拉开距离。 */\n  @State private bottomInsetVp: number = 0;')
    s = s.replace('this.topInsetVp = uiContext.px2vp(statusArea.topRect.height);', 'this.topInsetVp = uiContext.px2vp(statusArea.topRect.height);\n      this.bottomInsetVp = uiContext.px2vp(lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);')
    s = s.replace('top: detailContentTop(this.topInsetVp), bottom: 40 })', 'top: detailContentTop(this.topInsetVp), bottom: this.bottomInsetVp + %s })' % SAFE)
    return s
patch('pages/fieldwatch/FieldwatchDeviceDetailPage.ets', detail, SAFE, '../../fieldwatch/ui/FieldwatchLayout')