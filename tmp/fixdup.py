# -*- coding: utf-8 -*-
import io
p = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets'
s = io.open(p, encoding='utf-8').read()
bad = 'FieldwatchReportsPage({ topInset: this.topInsetVp, bottomInset: this.bottomInsetVp, twoColumn: this.twoColumnTabs(), bottomInset: this.bottomInsetVp })'
good = 'FieldwatchReportsPage({ topInset: this.topInsetVp, bottomInset: this.bottomInsetVp, twoColumn: this.twoColumnTabs() })'
print('found dup:', bad in s)
s = s.replace(bad, good)
io.open(p, 'w', encoding='utf-8', newline='').write(s)