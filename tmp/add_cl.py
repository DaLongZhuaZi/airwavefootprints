# -*- coding: utf-8 -*-
import json, io, os
ROOT = 'F:/DevEcoStudioProject/airwavefootprints'
BASE = ROOT + '/entry/src/main/resources/base/element/string.json'
EN = ROOT + '/entry/src/main/resources/en_US/element/string.json'
def load(p): return json.load(io.open(p, encoding='utf-8'))
def save(p, d):
    tmp = p + '.new'
    io.open(tmp, 'w', encoding='utf-8', newline='').write(json.dumps(d, ensure_ascii=False, indent=2))
    os.replace(tmp, p)
items = [
 ('fw_cl_110_1', u'新增「显示 → 语言」设置：跟随系统 / 中文 / English，切换后立即生效并记住选择',
  u'New Language setting under Display: Follow system / 中文 / English, applied immediately and remembered'),
 ('fw_cl_110_2', u'英文界面全面补全：设备解释、设备类型、候选特征、工具箱、报告与设置共 500 余条文案',
  u'Full English coverage: over 500 strings across device explanations, device types, candidate signatures, toolbox, reports and settings'),
 ('fw_cl_110_3', u'发热与掉帧治理：资源解析、广播解析、雷达绘制与隐藏页面重建四条热路径优化，翻页与滑动更跟手',
  u'Less heat and fewer dropped frames: resource lookup, advertisement parsing, radar drawing and hidden-page rebuilds reworked; paging and scrolling feel smoother'),
 ('fw_cl_110_4', u'设备详情与报告的说明文字改为本地化资源，英文模式下不再夹中文段落',
  u'Device detail and report explanations now come from localized resources instead of hardcoded text'),
 ('fw_cl_110_5', u'修复：英文模式下隐私声明与更新日志仍显示中文',
  u'Fixed: the privacy statement and changelog still showed Chinese in English mode'),
]
for p, is_en in ((BASE, False), (EN, True)):
    d = load(p)
    have = {x['name'] for x in d['string']}
    added = 0
    for k, zh, en in items:
        if k in have: continue
        d['string'].append({'name': k, 'value': en if is_en else zh})
        added += 1
    save(p, d)
    print(('en' if is_en else 'base'), '+%d' % added, 'total', len(d['string']))