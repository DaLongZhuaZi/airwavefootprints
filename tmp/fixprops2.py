# -*- coding: utf-8 -*-
import io, re
p = 'F:/DevEcoStudioProject/airwavefootprints/entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets'
lines = io.open(p, encoding='utf-8').read().split('\n')
names = ['struct FieldwatchLivePage {', 'struct FieldwatchFiltersPage {', 'struct FieldwatchReportsPage {', 'struct FieldwatchSettingsPage {']
COMMENT = '  /** 底部安全区高度（系统导航条）；与 FieldwatchLayout 的预留常量叠加使用。 */'
PROP = '  @Prop bottomInset: number = 0;'
for name in names:
    start = next(i for i, ln in enumerate(lines) if name in ln)
    # end = next top-level closing brace
    end = start + 1
    while end < len(lines) and lines[end] != '}':
        end += 1
    body = lines[start:end]
    have = [i for i, ln in enumerate(body) if '@Prop bottomInset' in ln]
    if len(have) == 1:
        print(name, 'ok')
        continue
    if len(have) > 1:
        # 删除多余声明（从后往前），连同其上面的注释行
        for idx in reversed(have[1:]):
            del body[idx]
            if idx - 1 >= 0 and COMMENT in body[idx - 1]:
                del body[idx - 1]
        print(name, 'deduped')
    else:
        anchor = next(i for i, ln in enumerate(body) if ln.strip().startswith('@Prop '))
        body.insert(anchor + 1, PROP)
        body.insert(anchor + 1, COMMENT)
        print(name, 'inserted')
    lines = lines[:start] + body + lines[end:]
io.open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
print('total props:', '\n'.join(lines).count('@Prop bottomInset: number = 0;'))