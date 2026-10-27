# -*- coding: utf-8 -*-
import re
path = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets\fieldwatch\ui\FieldwatchClassLabels.ets"
src = open(path, encoding="utf-8").read()
pat = re.compile(r"\$r\('app\.string\.([A-Za-z0-9_]+)'\)")
n = len(pat.findall(src))
src = pat.sub(lambda m: "fieldwatchText('app.string.%s')" % m.group(1), src)
src = src.replace("export function signatureClassLabel(category: SignatureClass): Resource {",
                  "export function signatureClassLabel(category: SignatureClass): string {")
src = src.replace("import { SignatureClass } from '../domain/FieldwatchModels';",
                  "import { SignatureClass } from '../domain/FieldwatchModels';\nimport { fieldwatchText } from './FieldwatchResText';")
open(path, "w", encoding="utf-8", newline="\n").write(src)
print("class labels converted:", n)
print("returns string:", "): string {" in src)
