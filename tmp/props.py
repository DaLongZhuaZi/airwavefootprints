# -*- coding: utf-8 -*-
import io, re
ROOT = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets'
files = [
 'pages/fieldwatch/FieldwatchPage.ets',
 'pages/fieldwatch/FieldwatchToolboxPage.ets',
 'pages/fieldwatch/FieldwatchFindPage.ets',
 'pages/fieldwatch/FieldwatchSignaturesPage.ets',
 'pages/fieldwatch/FieldwatchHuntPage.ets',
 'pages/fieldwatch/FieldwatchSignatureEditorPage.ets',
 'pages/fieldwatch/FieldwatchDeviceDetailPage.ets',
 'fieldwatch/ui/FieldwatchSignatureDetail.ets',
 'fieldwatch/ui/FieldwatchWatchlistPage.ets',
 'pages/fieldwatch/FieldwatchFeedbackPage.ets',
]
PROP = '  /** 底部安全区高度（系统导航条）；与 FieldwatchLayout 的预留常量叠加使用。 */\n  @Prop bottomInset: number = 0;'
for rel in files:
    p = ROOT + '/' + rel
    s = io.open(p, encoding='utf-8').read()
    if 'bottomInset: number' in s:
        print('skip (has prop)', rel); continue
    lines = s.split('\n')
    idx = -1
    for i, ln in enumerate(lines):
        if re.match(r'^\s*(@Prop\s+)?topInset: number\s*=', ln):
            idx = i; break
    if idx < 0:
        print('NO topInset anchor', rel); continue
    lines.insert(idx + 1, PROP)
    io.open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
    print('prop added', rel)