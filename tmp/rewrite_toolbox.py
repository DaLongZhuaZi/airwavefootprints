# -*- coding: utf-8 -*-
import re
path = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets\pages\fieldwatch\FieldwatchToolboxPage.ets"
src = open(path, encoding="utf-8").read()
lines = src.split("\n")
pat = re.compile(r"\$r\('app\.string\.([A-Za-z0-9_]+)'\)")
n = 0
out = []
for ln in lines:
    s = ln.lstrip()
    if s.startswith("*") or s.startswith("//") or s.startswith("/*") or "resolveResourceString(" in ln:
        out.append(ln); continue
    new = pat.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), ln)
    if new != ln:
        n += len(pat.findall(ln)); out.append(new)
    else:
        out.append(ln)
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))
print("toolbox rewritten:", n, "remaining:", len(pat.findall("\n".join(out))))
