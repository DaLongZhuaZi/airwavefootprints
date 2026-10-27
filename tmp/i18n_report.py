# -*- coding: utf-8 -*-
import json
d = json.load(open(r"F:\DevEcoStudioProject\airwavefootprints\tmp\i18n_literals.json", encoding="utf-8"))
lines = []
total = 0
for rel, items in d.items():
    lines.append(f"\n## {rel}  ({len(items)})")
    for it in items:
        total += 1
        lines.append(f"{it['line']:5d} | {it['lit']}")
        lines.append(f"      ctx: {it['ctx']}")
lines.append(f"\nTOTAL {total}")
open(r"F:\DevEcoStudioProject\airwavefootprints\tmp\i18n_report.md", "w", encoding="utf-8").write("\n".join(lines))
print("ok", total)
