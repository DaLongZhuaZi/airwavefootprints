# -*- coding: utf-8 -*-
import re, sys, io

path = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets\pages\fieldwatch\FieldwatchPage.ets"
src = open(path, encoding="utf-8").read()
lines = src.split("\n")

pat = re.compile(r"\$r\('app\.string\.([A-Za-z0-9_]+)'\)")
changed = 0
out = []
for ln in lines:
    stripped = ln.lstrip()
    if stripped.startswith("*") or stripped.startswith("//") or stripped.startswith("/*"):
        out.append(ln)
        continue
    if "resolveResourceString(" in ln:
        out.append(ln)
        continue
    new = pat.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), ln)
    if new != ln:
        changed += len(pat.findall(ln))
        out.append(new)
    else:
        out.append(ln)

result = "\n".join(out)

# add import after the FieldwatchPalette import line
imp = "import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';\n"
anchor = "import { FieldwatchPalette, FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';"
if imp.strip() not in result:
    result = result.replace(anchor, anchor + "\n" + imp.strip(), 1)

open(path, "w", encoding="utf-8", newline="\n").write(result)
print("rewritten call sites:", changed)
print("import present:", imp.strip() in result)
print("remaining direct app.string sites:", len(pat.findall(result)))
