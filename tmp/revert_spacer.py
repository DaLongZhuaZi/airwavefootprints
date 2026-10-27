# -*- coding: utf-8 -*-
import io
p = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets'
s = io.open(p, encoding='utf-8').read()
pairs = [
 ("}.width('100%').height('100%').padding({ left: 16, right: 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })",
  "}.width('100%').height('100%').padding({ left: 16, right: 16 })"),
 ("\n    .padding({ left: 16, right: 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })\n",
  "\n    .padding({ left: 16, right: 16 })\n"),
 ("\n      .padding({ left: 16, right: 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })\n",
  "\n      .padding({ left: 16, right: 16 })\n"),
 ("\n      .padding({ left: 14, right: 14, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })\n",
  "\n      .padding({ left: 14, right: 14 })\n"),
]
for bad, good in pairs:
    if bad in s:
        s = s.replace(bad, good)
        print('reverted:', bad.strip()[:60])
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('remaining dynamic pads:', s.count('bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE'))