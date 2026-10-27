# -*- coding: utf-8 -*-
import os, re
root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
pat_direct = re.compile(r"\$r\('app\.string\.([A-Za-z0-9_]+)'\)")
pat_ctx1 = re.compile(r"resolveResourceString\(\s*this\.getUIContext\(\)\.getHostContext\(\)\s*,\s*\$r\('app\.string\.([A-Za-z0-9_]+)'\)\s*\)")
pat_ctx2 = re.compile(r"resolveResourceString\(\s*context\s*,\s*\$r\('app\.string\.([A-Za-z0-9_]+)'\)\s*\)")
pat_any_ctx = re.compile(r"resolveResourceString\(")
total_d = total_c = total_left = 0
files = []
for dirpath, _, fs in os.walk(root):
    for fn in fs:
        if not fn.endswith(".ets"):
            continue
        p = os.path.join(dirpath, fn)
        t = open(p, encoding="utf-8").read()
        d = len(pat_direct.findall(t))
        c1 = len(pat_ctx1.findall(t)); c2 = len(pat_ctx2.findall(t))
        if d or c1 or c2:
            files.append((d, c1 + c2, fn))
            total_d += d; total_c += c1 + c2
for d, c, fn in sorted(files, reverse=True):
    print(f"  direct={d:4d} ctx={c:3d}  {fn}")
print(f"TOTAL direct={total_d} ctx-convertible={total_c}")
