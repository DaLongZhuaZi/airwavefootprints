# -*- coding: utf-8 -*-
import os, re
root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
pat_s = re.compile(r"\$r\('app\.string\.")
pat_c = re.compile(r"\$r\('app\.color\.")
pat_o = re.compile(r"\$r\('(?:app\.media|sys\.symbol|app\.plurals|app\.float)")
rows = []
for dirpath, _, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".ets"):
            continue
        p = os.path.join(dirpath, fn)
        t = open(p, encoding="utf-8").read()
        s = len(pat_s.findall(t)); c = len(pat_c.findall(t)); o = len(pat_o.findall(t))
        if s or c:
            rows.append((s + c, s, c, o, fn))
rows.sort(reverse=True)
print(f"{'file':40s} string color other")
for tot, s, c, o, fn in rows[:15]:
    print(f"{fn:40s} {s:6d} {c:5d} {o:5d}")
print("TOTAL string=%d color=%d" % (sum(r[1] for r in rows), sum(r[2] for r in rows)))
