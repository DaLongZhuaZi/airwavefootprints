# -*- coding: utf-8 -*-
import os, re, json, sys

root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
cjk = re.compile(r'[\u4e00-\u9fff]')
str_lit = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")
out = {}
order = []
for dirpath, _, files in os.walk(root):
    for fn in sorted(files):
        if not fn.endswith(".ets"):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, root).replace(os.sep, "/")
        lines = open(p, encoding="utf-8").read().split("\n")
        in_block = False
        items = []
        for i, line in enumerate(lines, 1):
            s = line.strip()
            if in_block:
                if "*/" in s: in_block = False
                continue
            if s.startswith("/*"):
                if "*/" not in s: in_block = True
                continue
            if s.startswith("//") or s.startswith("*"):
                continue
            if "logger." in line or "TAG =" in line:
                continue
            for m in str_lit.finditer(line):
                lit = m.group(0)
                if cjk.search(lit):
                    items.append({"line": i, "lit": lit, "ctx": line.strip()[:150]})
                    break
        if items:
            out[rel] = items
            order.append(rel)
json.dump(out, open(r"F:\DevEcoStudioProject\airwavefootprints\tmp\i18n_literals.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("files:", len(order), "total:", sum(len(v) for v in out.values()))
for rel in order[:12]:
    print(f"  {len(out[rel]):4d}  {rel}")
