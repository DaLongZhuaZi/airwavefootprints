# -*- coding: utf-8 -*-
import os, re, collections
root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
pat = re.compile(r"\$r\('app\.color\.([A-Za-z0-9_]+)'\)")
cnt = collections.Counter()
per_file = collections.Counter()
for dirpath, _, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".ets"):
            continue
        t = open(os.path.join(dirpath, fn), encoding="utf-8").read()
        hits = pat.findall(t)
        if hits:
            per_file[fn] = len(hits)
            for h in hits:
                cnt[h] += 1
print("total app.color refs:", sum(cnt.values()))
print("\nby file:")
for f, n in per_file.most_common(12):
    print(f"  {n:4d}  {f}")
print("\ndistinct color keys:", len(cnt))
for k, n in cnt.most_common(40):
    print(f"  {n:4d}  {k}")
