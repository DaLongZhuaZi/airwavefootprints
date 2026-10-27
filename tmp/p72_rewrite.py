# -*- coding: utf-8 -*-
import os, re

root = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets"
files = [
    ("pages/fieldwatch", "FieldwatchPage.ets"),
    ("pages/fieldwatch", "FieldwatchFeedbackPage.ets"),
    ("pages/fieldwatch", "FieldwatchSignatureEditorPage.ets"),
    ("pages/fieldwatch", "FieldwatchFindPage.ets"),
    ("pages/fieldwatch", "FieldwatchOnboardingPage.ets"),
    ("pages/fieldwatch", "FieldwatchSignaturesPage.ets"),
    ("pages/fieldwatch", "FieldwatchHuntPage.ets"),
    ("pages/fieldwatch", "FieldwatchDeviceDetailPage.ets"),
    ("fieldwatch/ui", "FieldwatchFindWizard.ets"),
    ("fieldwatch/ui", "FieldwatchSignatureDetail.ets"),
    ("fieldwatch/ui", "FieldwatchWatchlistPage.ets"),
    ("fieldwatch/ui", "FieldwatchIntensitySlider.ets"),
]

pat_direct = re.compile(r"\$r\('app\.string\.([A-Za-z0-9_]+)'\)")
pat_ctx1 = re.compile(r"resolveResourceString\(\s*this\.getUIContext\(\)\.getHostContext\(\)\s*,\s*\$r\('app\.string\.([A-Za-z0-9_]+)'\)\s*\)")
pat_ctx2 = re.compile(r"resolveResourceString\(\s*context\s*,\s*\$r\('app\.string\.([A-Za-z0-9_]+)'\)\s*\)")

for sub, fn in files:
    p = os.path.join(root, sub.replace("/", os.sep), fn)
    src = open(p, encoding="utf-8").read()
    orig = src
    # 1) ctx forms first (so the inner $r is consumed together with the wrapper)
    n_ctx = len(pat_ctx1.findall(src)) + len(pat_ctx2.findall(src))
    src = pat_ctx1.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), src)
    src = pat_ctx2.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), src)
    # 2) remaining direct sites, skipping comment lines and any leftover ctx wrapper
    out = []
    n_direct = 0
    for ln in src.split("\n"):
        s = ln.lstrip()
        if s.startswith("*") or s.startswith("//") or s.startswith("/*") or "resolveResourceString(" in ln:
            out.append(ln)
            continue
        new = pat_direct.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), ln)
        if new != ln:
            n_direct += len(pat_direct.findall(ln))
        out.append(new)
    src = "\n".join(out)
    # 3) import
    if "FieldwatchResText'" not in src:
        rel = "'../../fieldwatch/ui/FieldwatchResText'" if sub.startswith("pages/") else "'./FieldwatchResText'"
        imp = "import { fieldwatchText } from %s;" % rel
        lines = src.split("\n")
        last_import = -1
        for i, ln in enumerate(lines[:80]):
            if ln.startswith("import ") and ln.rstrip().endswith(";"):
                last_import = i
        lines.insert(last_import + 1, imp)
        src = "\n".join(lines)
    if src != orig:
        open(p, "w", encoding="utf-8", newline="\n").write(src)
    print(f"{fn:38s} ctx={n_ctx:3d} direct={n_direct:3d} remaining={len(pat_direct.findall(src))}")
