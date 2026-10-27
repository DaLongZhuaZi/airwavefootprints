# -*- coding: utf-8 -*-
import os, re, collections
root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
pat = re.compile(r"\$r\('app\.color\.([A-Za-z0-9_]+)'\)")
cnt = collections.Counter()
for dirpath, _, fs in os.walk(root):
    for fn in fs:
        if not fn.startswith("Fieldwatch") or not fn.endswith(".ets"):
            continue
        t = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        for h in pat.findall(t):
            cnt[h] += 1
print("Fieldwatch app color refs total:", sum(cnt.values()))
for k, n in cnt.most_common(30):
    print(f"  {n:4d}  {k}")
