# -*- coding: utf-8 -*-
import re, io
p = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets\pages\fieldwatch\FieldwatchPage.ets"
lines = open(p, encoding="utf-8").read().split("\n")
pat = re.compile(r"\$r\('app\.string\.[A-Za-z0-9_]+'\)")
in_comment = 0
conv = 0
skipped_cmt = 0
skipped_resolve = 0
other = []
for i, ln in enumerate(lines, 1):
    if "resolveResourceString(" in ln and pat.search(ln):
        skipped_resolve += len(pat.findall(ln))
        continue
    stripped = ln.lstrip()
    if stripped.startswith("*") or stripped.startswith("//") or stripped.startswith("/*"):
        skipped_cmt += len(pat.findall(ln))
        continue
    conv += len(pat.findall(ln))
print("app.string sites in FieldwatchPage.ets")
print("  convertible:", conv)
print("  in comments (skipped):", skipped_cmt)
print("  inside resolveResourceString (skipped):", skipped_resolve)
# risky contexts
risky = []
for i, ln in enumerate(lines, 1):
    if ": Resource" in ln or "ResourceStr" in ln or "Resource[" in ln:
        risky.append((i, ln.strip()[:110]))
print("\nlines mentioning Resource types:", len(risky))
for i, t in risky[:15]:
    print(f"  {i}: {t}")
