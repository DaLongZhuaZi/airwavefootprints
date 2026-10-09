#!/usr/bin/env python3
"""把外部来源富化进 Fieldwatch 特征库目录（构建期，离线可复现）。

背景：目录只有一个来源 —— 上游 Fieldwatch 仓库的 dist JSON（内置 rawfile 与在线更新同一份）。
上游停更就断供，且目录构成严重失衡（OUI 占 87%，MANUFACTURER_DATA 只有 30 条）。

本脚本把 Theengs Decoder 的设备定义转成我们的规则，合并进目录。

来源：theengs/decoder src/devices/*.h（每个文件内嵌一段 JSON）
  形态："condition":["manufacturerdata","=",50,"index",0,"4c000215..."]

**只有一部分能表达**（实测 117 个设备）：
  可用前缀规则表达（单条件 + index 0）: 26
  含布尔组合（& / |）不可表达:          82
  index > 0 定位不可表达:                4
  name / uuid 等其它:                    5
**限制不在来源，在规则表达力** —— 我们的 MANUFACTURER_DATA / SERVICE_DATA 只支持「位置 0 前缀」。
要吃到那 82 条，需要给引擎加「任意偏移匹配」和「布尔组合」。

关键约定（踩过坑）：
  1. 制造商数据里公司 ID 是**前 2 字节、小端**。`4c0010` -> 公司 ID 0x004C、前缀 `10`。
     写成 int('4C00',16) 会得到 0x4C00，与目录里的 companyId=76 对不上，去重会全部失效。
  2. `manufacturerDataHex` **不含**公司 ID（见 FieldwatchParsers: payload.slice(2)），
     所以前缀只取公司 ID 之后的部分。
  3. 前缀为空时必须用 MANUFACTURER_ID；若连公司 ID 都是 0，规则永远匹配不上，**必须丢弃**。
"""
import argparse, json, os, re, sys, urllib.request

THEENGS_API = 'https://api.github.com/repos/theengs/decoder/contents/src/devices'
THEENGS_RAW = 'https://raw.githubusercontent.com/theengs/decoder/development/src/devices/'
NL = chr(10)


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    request = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        'Accept': '*/*',
    })
    with urllib.request.urlopen(request, timeout=120) as resp:
        data = resp.read()
    with open(path, 'wb') as fh:
        fh.write(data)
    return path


def list_theengs(cache):
    listing = os.path.join(cache, 'listing.json')
    fetch(THEENGS_API, listing)
    return json.load(open(listing, encoding='utf-8'))


def load_theengs_devices(cache):
    devices = []
    for entry in list_theengs(cache):
        name = entry.get('name') or ''
        if not name.endswith('.h'):
            continue
        path = os.path.join(cache, 'devices', name)
        try:
            fetch(THEENGS_RAW + name, path)
            text = open(path, encoding='utf-8', errors='replace').read()
        except Exception:
            continue
        m = re.search(r'const char\*\s+_\w+_json\s*=\s*"(.*?)";', text, re.S)
        if not m:
            continue
        try:
            devices.append(json.loads(m.group(1).replace(chr(92) + chr(34), chr(34))))
        except Exception:
            continue
    return devices


def company_id_of(hex_upper):
    """制造商数据的前 2 字节是小端公司 ID：4C0010 -> 0x004C。"""
    if len(hex_upper) < 4:
        return 0
    return int(hex_upper[2:4] + hex_upper[0:2], 16)


# 引擎支持「任意偏移匹配」与「或的与」之后，条件可以完整翻译。
# 头部 2 字节（公司 ID / UUID）在解析阶段已被剥掉，所以外部库的下标 N 要映射成 N - 2。
HEADER_BYTES = 2
# 这些 token 表达不了（需要 MAC 比较、子串包含、数据源缺失判定），整台设备跳过。
UNSUPPORTED_TOKENS = ('mac@index', 'contain', 'no-mfgdata', 'not_')


def split_condition(cond):
    """把中缀条件切成 [(operator, segment)]；operator 是段**之前**的连接符，首段为 None。"""
    out = []
    current = []
    operator = None
    for token in cond:
        if token in ('&', '|'):
            out.append((operator, current))
            operator = token
            current = []
        else:
            current.append(token)
    out.append((operator, current))
    return out


def segment_to_rule(segment):
    """一个条件段 -> (kind, companyId, prefix, uuidText, offset, minLen, maxLen)。"""
    if not segment:
        return None
    for token in segment:
        text = str(token)
        for bad in UNSUPPORTED_TOKENS:
            if bad in text:
                return None
    head = str(segment[0])
    index = None
    length_op = None
    length_value = 0
    for position, token in enumerate(segment):
        text = str(token)
        if text == 'index' and position + 1 < len(segment):
            index = int(segment[position + 1])
        elif text in ('=', '>=', '<=') and position + 1 < len(segment):
            length_op = text
            length_value = int(segment[position + 1])
    value = str(segment[-1]).upper()
    if not re.fullmatch(r'[0-9A-F]+', value):
        return None
    # 外部库的 servicedata 含 2 字节 UUID、manufacturerdata 含 2 字节公司 ID。
    offset = max(0, (index or HEADER_BYTES) - HEADER_BYTES)
    min_len = length_value if length_op in ('=', '>=') else 0
    max_len = length_value if length_op == '=' else 0
    if head == 'manufacturerdata':
        cid = company_id_of(value)
        rest = value[4:]
        if not rest:
            # 没有前缀：只能退化成「只看公司 ID」，且公司 ID 为 0 时永远匹配不上。
            return None if cid == 0 else ('MANUFACTURER_ID', cid, '', '', 0, 0, 0)
        return ('MANUFACTURER_DATA', cid, rest, '', offset, min_len, max_len)
    if head == 'servicedata':
        return ('SERVICE_DATA', 0, value, '', offset, min_len, max_len)
    if head == 'uuid':
        return ('SERVICE_UUID', 0, '', value, 0, 0, 0)
    if head == 'name':
        return ('NAME_CONTAINS', 0, '', value, 0, 0, 0)
    return None


def expressible(device):
    """把设备条件翻译成规则列表；返回 [(kind, cid, prefix, uuidText, offset, minLen, maxLen, group)] 或 None。

    `|` 分段、`&` 组内相连：**同组 AND、组间 OR**。只有一段的表达式仍用 group 0，
    保持与既有目录一致的「基础集合」语义。
    """
    cond = device.get('condition') or []
    if not cond:
        return None
    pieces = split_condition(cond)
    # 按 | 归组：连续被 & 连接的段同属一组。
    groups = []
    current = []
    for operator, segment in pieces:
        if operator == '|' and current:
            groups.append(current)
            current = []
        current.append(segment)
    if current:
        groups.append(current)
    translated = []
    for group_index, segments in enumerate(groups):
        if len(segments) == 0:
            continue
        for segment in segments:
            parsed = segment_to_rule(segment)
            if parsed is None:
                return None
            translated.append(parsed)
    if not translated:
        return None
    # **丢弃「单条 SERVICE_UUID」的条件**：服务 UUID 单独不构成设备身份，它只是能力。
    # 最典型的反例是 `0x180F`（标准电池服务）—— 几乎所有带电池的设备都会广播它，
    # 按它打标签会给大量无关设备贴上「Service data」。
    # 只有当 UUID 与其它条件（服务数据 / 厂商数据）**同时成立**时才有辨识力。
    if len(translated) == 1 and translated[0][0] == 'SERVICE_UUID':
        return None
    # 单一分组且只有一条规则时用 group 0（走既有 matchAny 语义）；
    # 其余情况统一编号，保证「组内 AND、组间 OR」。
    multi_group = len(groups) > 1 or (len(groups) == 1 and len(groups[0]) > 1)
    out = []
    position = 0
    for group_index, segments in enumerate(groups):
        for _segment in segments:
            parsed = translated[position]
            position += 1
            group = (group_index + 1) if multi_group else 0
            out.append(parsed + (group,))
    return out


def rule_identity(rule):
    """规则级身份键。必须包含 offset / group / 长度 —— 否则「同前缀不同偏移」会被误判为重复。"""
    return (str(rule.get('kind') or ''),
            (rule.get('text') or '').upper(),
            int(rule.get('companyId') or 0),
            (rule.get('dataPrefixHex') or '').upper(),
            int(rule.get('offset') or 0),
            int(rule.get('group') or 0),
            int(rule.get('minLen') or 0),
            int(rule.get('maxLen') or 0))


def core_identity(rule):
    """规则的核心模式（不含 offset / 长度）—— 用于判断「是否已被覆盖」。"""
    return (str(rule.get('kind') or ''),
            (rule.get('text') or '').upper(),
            int(rule.get('companyId') or 0),
            (rule.get('dataPrefixHex') or '').upper())


def covered_by(candidate, existing_list):
    """candidate 是否被某条既有规则**覆盖**（即既有规则至少同样宽泛）。

    判据：核心模式相同，且既有规则在三个维度上都不更窄 ——
      offset 相同（不同偏移是真正不同的条件，不算覆盖）
      既有 minLen == 0（无下界）或 <= candidate 的 minLen
      既有 maxLen == 0（无上界）或 >= candidate 的 maxLen
    覆盖成立时，新规则匹配到的设备既有规则也会匹配，加进去只会产生重复标签。
    """
    core = core_identity(candidate)
    for rule in existing_list:
        if core_identity(rule) != core:
            continue
        if int(rule.get('offset') or 0) != int(candidate.get('offset') or 0):
            continue
        old_min = int(rule.get('minLen') or 0)
        old_max = int(rule.get('maxLen') or 0)
        new_min = int(candidate.get('minLen') or 0)
        new_max = int(candidate.get('maxLen') or 0)
        if old_min != 0 and old_min > new_min:
            continue
        if old_max != 0 and (new_max == 0 or old_max < new_max):
            continue
        return True
    return False


def existing_keys(catalog):
    keys = set()
    rules = []
    ids = set()
    for fleet in catalog.get('fleets', []):
        ids.add(fleet.get('id'))
        for rule in fleet.get('rules', []):
            keys.add(rule_identity(rule))
            rules.append(rule)
    return keys, rules, ids


def slug(text):
    out = re.sub(r'[^a-z0-9]+', '-', (text or '').lower()).strip('-')
    return out or 'unknown'


def build_fleet(device, rules):
    """把一台设备的多条已翻译规则组装成 fleet。"""
    model_id = device.get('model_id') or 'UNKNOWN'
    brand = (device.get('brand') or '').strip()
    model = (device.get('model') or '').strip() or model_id
    if brand and brand.upper() != 'GENERIC' and brand.lower() not in model.lower():
        name = brand + ' ' + model
    else:
        name = model
    out_rules = []
    for kind, cid, prefix, uuid_text, offset, min_len, max_len, group in rules:
        rule = {
            'kind': kind,
            'text': uuid_text,
            'companyId': cid,
            'dataPrefixHex': prefix,
            'radio': 'BLE',
            'enabled': True,
        }
        # 只在非默认值时写出，与引擎序列化保持一致的紧凑风格。
        if offset > 0:
            rule['offset'] = offset
        if group > 0:
            rule['group'] = group
        if min_len > 0:
            rule['minLen'] = min_len
        if max_len > 0:
            rule['maxLen'] = max_len
        out_rules.append(rule)
    return {
        'id': 'fleet-theengs-' + slug(model_id),
        'name': name,
        'enabled': True,
        'matchAny': True,
        'colorIndex': 4,
        'rules': out_rules,
        'minPeers': 0,
        'peerWindowSec': 60,
        'clusterByOui': False,
        'sequentialMac': False,
        'notes': 'Theengs Decoder 设备定义（构建期生成）',
        'attentionNote': '',
        'builtIn': True,
    }


def main():
    parser = argparse.ArgumentParser(description='用外部来源富化 Fieldwatch 特征库目录')
    parser.add_argument('--catalog', required=True, help='上游目录 JSON（输入）')
    parser.add_argument('--out', required=True, help='富化后的目录 JSON（输出）')
    parser.add_argument('--cache-dir', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '.cache'))
    args = parser.parse_args()

    catalog = json.load(open(args.catalog, encoding='utf-8'))
    existing_rule_keys, existing_rules, ids = existing_keys(catalog)
    sys.stderr.write('  输入目录: %d fleets / %d 规则%s' % (
        len(catalog.get('fleets', [])),
        sum(len(f.get('rules', [])) for f in catalog.get('fleets', [])), NL))

    devices = load_theengs_devices(args.cache_dir)
    sys.stderr.write('  Theengs 设备解析成功: %d%s' % (len(devices), NL))

    added = []
    skipped_existing = 0
    skipped_unexpressible = 0
    for device in devices:
        parsed = expressible(device)
        if parsed is None:
            skipped_unexpressible += 1
            continue
        fleet = build_fleet(device, parsed)
        if fleet['id'] in ids:
            skipped_existing += 1
            continue
        # 整组规则都已存在 -> 这台设备没有带来新信息（例如 Apple iPhone/iPad 的
        # `cid=0x4C + prefix=10` 目录里早有）。只按 id 去重会漏掉这种重复。
        # 整组规则都已被既有目录覆盖（含「更宽泛的既有规则覆盖更窄的新规则」）
        # -> 这台设备带不来新信息。只比 id 或只比精确身份都会漏掉这类重复：
        # 例如 Apple iPhone/iPad 目录里早有 `cid=0x4C + prefix=10`（无长度约束），
        # 而 Theengs 那条多了 `>=8`，精确身份不同但完全被覆盖。
        if all(rule_identity(rule) in existing_rule_keys or covered_by(rule, existing_rules)
               for rule in fleet['rules']):
            skipped_existing += 1
            continue
        ids.add(fleet['id'])
        added.append(fleet)

    catalog['fleets'] = list(catalog.get('fleets', [])) + added
    catalog['catalogVersion'] = int(catalog.get('catalogVersion') or 0) + 1
    notes = catalog.get('enrichment')
    catalog['enrichment'] = {
        'source': 'theengs/decoder',
        'addedFleets': len(added),
        'skippedExisting': skipped_existing,
        'skippedUnexpressible': skipped_unexpressible,
        'note': '构建期富化；支持任意偏移匹配与「同组 AND / 组间 OR」',
    }
    with open(args.out, 'w', encoding='utf-8') as fh:
        # 缩进必须与上游目录一致（4 空格）—— 否则同样的内容写出后体积差 30%，
        # 会让人误以为「加了东西反而变小」，白查一轮。
        json.dump(catalog, fh, ensure_ascii=False, indent=4)

    kinds = {}
    for fleet in added:
        for rule in fleet['rules']:
            kinds[rule['kind']] = kinds.get(rule['kind'], 0) + 1
    sys.stderr.write('  新增 fleet: %d（已存在 %d / 无法表达 %d）%s' % (
        len(added), skipped_existing, skipped_unexpressible, NL))
    for kind, count in sorted(kinds.items()):
        sys.stderr.write('    %-20s %d%s' % (kind, count, NL))
    sys.stderr.write('  catalogVersion -> %d%s' % (catalog['catalogVersion'], NL))
    sys.stderr.write('  写出 %s%s' % (args.out, NL))


if __name__ == '__main__':
    main()
