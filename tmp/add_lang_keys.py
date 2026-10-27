# -*- coding: utf-8 -*-
import io, json

def add(path, pairs):
    s = open(path, encoding="utf-8").read()
    tail = "\n  ]\n}"
    idx = s.rfind(tail)
    assert idx > 0, path
    items = []
    for name, value in pairs:
        items.append('    {\n      "name": "%s",\n      "value": "%s"\n    }' % (name, value))
    insertion = ",\n" + ",\n".join(items) + tail
    s2 = s[:idx] + insertion + s[idx + len(tail):]
    json.loads(s2)
    open(path, "w", encoding="utf-8", newline="\n").write(s2)
    print(path, "keys now", s2.count('"name"'))

base = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\resources\base\element\string.json"
en = r"F:\DevEcoStudioProject\airwavefootprints\entry\src\main\resources\en_US\element\string.json"
add(base, [("fieldwatch_settings_language", "语言"), ("fieldwatch_settings_language_system", "跟随系统")])
add(en, [("fieldwatch_settings_language", "Language"), ("fieldwatch_settings_language_system", "Follow system")])
