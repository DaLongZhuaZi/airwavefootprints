# -*- coding: utf-8 -*-
import os, re

root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
MAP = {
    "text_secondary": "textDim",
    "text_primary": "text",
    "button_primary": "accent",
    "button_warning": "signalRed",
    "button_secondary": "amber",
    "fw_on_accent": "onAccent",
    "background_primary": "night",
}
pat = re.compile(r"\$r\('app\.color\.([A-Za-z0-9_]+)'\)")

def rel_import(sub):
    return "'../../fieldwatch/ui/FieldwatchPalette'" if sub.startswith("pages/") else "'./FieldwatchPalette'"

changed = []
for dirpath, _, fs in os.walk(root):
    for fn in fs:
        if not (fn.startswith("Fieldwatch") and fn.endswith(".ets")) or fn == "FieldwatchPalette.ets":
            continue
        p = os.path.join(dirpath, fn)
        src = open(p, encoding="utf-8").read()
        hits = [k for k in pat.findall(src) if k in MAP]
        if not hits:
            continue
        sub = os.path.relpath(dirpath, root).replace(os.sep, "/")
        out = []
        n = 0
        for ln in src.split("\n"):
            def rep(m):
                global n
                key = m.group(1)
                if key not in MAP:
                    return m.group(0)
                n += 1
                return "FieldwatchPaletteHolder.get()." + MAP[key]
            out.append(pat.sub(rep, ln))
        src = "\n".join(out)
        if "FieldwatchPaletteHolder" not in src:
            imp = "import { FieldwatchPaletteHolder } from %s;" % rel_import(sub)
            lines = src.split("\n")
            last = -1
            for i, ln in enumerate(lines[:80]):
                if ln.startswith("import ") and ln.rstrip().endswith(";"):
                    last = i
            lines.insert(last + 1, imp)
            src = "\n".join(lines)
        elif "FieldwatchPaletteHolder }" not in src and "import { FieldwatchPaletteHolder" not in src:
            # holder referenced but not imported (unlikely) -> add import
            if "import { FieldwatchPaletteHolder" not in src:
                imp = "import { FieldwatchPaletteHolder } from %s;" % rel_import(sub)
                lines = src.split("\n")
                last = -1
                for i, ln in enumerate(lines[:80]):
                    if ln.startswith("import ") and ln.rstrip().endswith(";"):
                        last = i
                lines.insert(last + 1, imp)
                src = "\n".join(lines)
        open(p, "w", encoding="utf-8", newline="\n").write(src)
        changed.append((fn, n))
for fn, n in sorted(changed, key=lambda x: -x[1]):
    print(f"  {n:3d}  {fn}")
print("total color refs converted:", sum(n for _, n in changed))
