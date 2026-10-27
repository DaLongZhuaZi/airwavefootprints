# -*- coding: utf-8 -*-
import os, re, json

root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
cjk = re.compile(r'[\u4e00-\u9fff]')
str_lit = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")

per_file = {}
samples = []
for dirpath, _, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".ets"):
            continue
        p = os.path.join(dirpath, fn)
        lines = open(p, encoding="utf-8").read().split("\n")
        in_block = False
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if in_block:
                if "*/" in s:
                    in_block = False
                continue
            if s.startswith("/*"):
                if "*/" not in s:
                    in_block = True
                continue
            if s.startswith("//") or s.startswith("*"):
                continue
            code = line.split("//")[0] if "//" in line and not ("'" in line or '"' in line) else line
            for m in str_lit.finditer(code):
                lit = m.group(0)
                if cjk.search(lit):
                    if "logger." in line or "TAG =" in line:
                        continue
                    per_file[fn] = per_file.get(fn, 0) + 1
                    if len(samples) < 400:
                        samples.append((fn, i, lit[:70]))
                    break
print("=== CJK literals per file (excluding comments & logger) ===")
for fn, n in sorted(per_file.items(), key=lambda x: -x[1]):
    print(f"  {n:4d}  {fn}")
print("TOTAL:", sum(per_file.values()))

# en_US still Chinese?
base = json.load(open(r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\resources\base\element\string.json", encoding="utf-8"))
en = json.load(open(r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\resources\en_US\element\string.json", encoding="utf-8"))
b = {x["name"]: x["value"] for x in base["string"]}
e = {x["name"]: x["value"] for x in en["string"]}
zh_in_en = [(k, v) for k, v in e.items() if cjk.search(v)]
print("\n=== en_US entries still containing CJK ===  count:", len(zh_in_en))
for k, v in zh_in_en[:25]:
    print(f"  {k} = {v[:60]}")
same = [(k, v) for k, v in e.items() if b.get(k) == v and cjk.search(v)]
print("\nidentical-to-base (same Chinese text):", len(same))
