# -*- coding: utf-8 -*-
import io, re
p = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets'
s = io.open(p, encoding='utf-8').read()
# 1) dedupe accidental double insertion
s = s.replace('bottomInset: this.bottomInsetVp, bottomInset: this.bottomInsetVp,', 'bottomInset: this.bottomInsetVp,')
s = s.replace('bottomInset: this.bottomInsetVp, bottomInset: this.bottomInsetVp })', 'bottomInset: this.bottomInsetVp })')
# 2) revert the accidental padding on the fixed 48-vp row
s = s.replace("}.width('100%').height(48).padding({ left: 14, right: 14, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })", "}.width('100%').height(48).padding({ left: 14, right: 14 })")
# 3) add the prop to the three structs that missed it
lines = s.split('\n')
targets = ['struct FieldwatchLivePage {', 'struct FieldwatchReportsPage {', 'struct FieldwatchSettingsPage {', 'struct FieldwatchFiltersPage {']
out = []
i = 0
pending = list(targets)
while i < len(lines):
    out.append(lines[i])
    if any(t in lines[i] for t in pending):
        name = [t for t in pending if t in lines[i]][0]
        pending.remove(name)
        # find next @Prop line
        j = i + 1
        while j < len(lines) and '@Prop ' not in lines[j]:
            out.append(lines[j]); j += 1
        if j < len(lines):
            out.append(lines[j])
            out.append('  /** 底部安全区高度（系统导航条）；与 FieldwatchLayout 的预留常量叠加使用。 */')
            out.append('  @Prop bottomInset: number = 0;')
            i = j
    i += 1
s2 = '\n'.join(out)
# Filters already had one - 去掉重复声明
first = s2.find('@Prop bottomInset: number = 0;')
second = s2.find('@Prop bottomInset: number = 0;', first + 10)
while second > 0:
    # remove the duplicate declaration together with its preceding comment line
    start = s2.rfind('  /** 底部安全区高度', first, second)
    if start > 0:
        end = second + len('@Prop bottomInset: number = 0;')
        s2 = s2[:start] + s2[end:].lstrip('\n')
    first = s2.find('@Prop bottomInset: number = 0;')
    second = s2.find('@Prop bottomInset: number = 0;', first + 10)
io.open(p, 'w', encoding='utf-8', newline='').write(s2)
print('props:', s2.count('@Prop bottomInset: number = 0;'))
print('dedupe ok:', 'bottomInset: this.bottomInsetVp, bottomInset' not in s2)