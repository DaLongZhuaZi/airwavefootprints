# -*- coding: utf-8 -*-
import re

p = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\ets\fieldwatch\domain\FieldwatchParsers.ets"
src = open(p, encoding="utf-8").read()
orig = src

# 1) remove the two local hex helpers (index-based, robust to whitespace)
for fn in ("hexOfBytes", "bytesOfHex"):
    m = re.search(r"\nfunction " + fn + r"\([^)]*\)[^{]*\{", src)
    if not m:
        print("WARN: helper not found:", fn); continue
    start = m.start()
    # find the matching closing brace at column 0
    end = src.find("\n}\n", m.end())
    if end < 0:
        print("WARN: helper end not found:", fn); continue
    src = src[:start] + src[end + 3:]
print("helpers removed:", "function hexOfBytes" not in src, "function bytesOfHex" not in src)

# 2) slice-based hex calls -> range version (no sub-array allocation)
src = re.sub(r"hexOfBytes\(([A-Za-z_][A-Za-z0-9_]*)\.slice\(([^,]+),\s*([^)]+)\)\)", r"bytesRangeToHex(\1, \2, \3)", src)

# 3) remaining hexOfBytes -> bytesToHex, bytesOfHex -> hexToBytes
src = re.sub(r"\bhexOfBytes\(", "bytesToHex(", src)
src = re.sub(r"\bbytesOfHex\(", "hexToBytes(", src)

# 4) import the shared helpers
if "from './FieldwatchHex'" not in src:
    lines = src.split("\n")
    last = 0
    for i, ln in enumerate(lines[:40]):
        if ln.startswith("import ") and ln.rstrip().endswith(";"):
            last = i
    lines.insert(last + 1, "import { bytesRangeToHex, bytesToHex, hexToBytes } from './FieldwatchHex';")
    src = "\n".join(lines)

# 5) split decode() into hex entry + byte core (index-based)
anchor = "  decode(rawHex: string): BleAdvertisementFacts {"
idx = src.find(anchor)
assert idx > 0, "decode anchor missing"
tail_anchor = "    facts.byteLength = bytes.length;"
tidx = src.find(tail_anchor, idx)
assert tidx > 0, "tail anchor missing"
end = tidx + len(tail_anchor)

new_head = "  /** 十六进制入口：先校验再转字节。**热路径不走这里**（见 decodeBytes）。 */\n" \
    "  decode(rawHex: string): BleAdvertisementFacts {\n" \
    "    const normalized: string = rawHex.replace(/:/g, '');\n" \
    "    if (normalized.length === 0 || normalized.length % 2 !== 0 || !/^[0-9A-Fa-f]+$/.test(normalized)) {\n" \
    "      const invalid: BleAdvertisementFacts = new BleAdvertisementFacts();\n" \
    "      invalid.error = 'invalid_hex';\n" \
    "      return invalid;\n" \
    "    }\n" \
    "    return this.decodeFromBytes(hexToBytes(normalized));\n" \
    "  }\n" \
    "\n" \
    "  /**\n" \
    "   * 字节入口：**直接按字节解析，不再绕一趟十六进制**。\n" \
    "   *\n" \
    "   * 原实现是 decode(hexOfBytes(raw))：字节 → 十六进制串 → 去冒号 → 正则校验 → 再转回字节，\n" \
    "   * 四个步骤对每条广播都要走一遍。这里直接进 AD 循环。\n" \
    "   */\n" \
    "  decodeBytes(raw: Uint8Array): BleAdvertisementFacts {\n" \
    "    return this.decodeFromBytes(raw);\n" \
    "  }\n" \
    "\n" \
    "  private decodeFromBytes(bytes: Uint8Array): BleAdvertisementFacts {\n" \
    "    const facts: BleAdvertisementFacts = new BleAdvertisementFacts();\n" \
    "    facts.byteLength = bytes.length;"
src = src[:idx] + new_head + src[end:]

# 6) drop the old decodeBytes wrapper
old_wrap_start = src.find("  decodeBytes(raw: Uint8Array): BleAdvertisementFacts {\n    return this.decode(")
if old_wrap_start > 0:
    old_wrap_end = src.find("\n  }\n", old_wrap_start)
    src = src[:old_wrap_start] + src[old_wrap_end + len("\n  }\n"):]
    print("old wrapper removed")

open(p, "w", encoding="utf-8", newline="\n").write(src)
print("changed:", src != orig)
print("remaining hexOfBytes:", src.count("hexOfBytes"), "bytesOfHex:", src.count("bytesOfHex"))
print("bytesRangeToHex uses:", src.count("bytesRangeToHex"), "bytesToHex uses:", src.count("bytesToHex"))
print("decodeFromBytes defs:", src.count("private decodeFromBytes"), "decodeBytes defs:", src.count("decodeBytes(raw"))
