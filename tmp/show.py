# -*- coding: utf-8 -*-
import json, sys
d = json.load(open(r"F:\DevEcoStudioProject\airwavefootprints\tmp\i18n_literals.json", encoding="utf-8"))
key = sys.argv[1]
start = int(sys.argv[2]); end = int(sys.argv[3])
items = d[key]
print(f"### {key}  ({len(items)} literals) lines {start}-{end}")
for it in items[start:end]:
    print(f"{it['line']:5d} | {it['lit'][:110]}")
