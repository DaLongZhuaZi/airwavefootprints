# -*- coding: utf-8 -*-
"""生成 HarmonyOS 分层图标前景层：安全区 / 蒙版 / 实测内容框 参考图。"""
from PIL import Image, ImageDraw, ImageFont

SRC = 'AppScope/resources/base/media/foreground.png'
BG  = 'AppScope/resources/base/media/background.png'
OUT = 'docs/logo/safe-area-guide.png'

S      = 900                 # 画布渲染边长
PAD    = 60
LEGW   = 620
W, H   = PAD*2 + S + LEGW, PAD*2 + S
SS     = S / 1024.0          # 1024 -> 900 缩放
def p(v): return PAD + v * SS

canvas = Image.new('RGB', (W, H), '#141821')
d = ImageDraw.Draw(canvas)

def font(sz, bold=False):
    try:
        return ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc' if bold else 'C:/Windows/Fonts/msyh.ttc', sz)
    except Exception:
        return ImageFont.load_default()

F_T  = font(34, True)
F_H  = font(23, True)
F_B  = font(19)
F_S  = font(16)

# ---- 透明棋盘格 ----
sq = 30
for y in range(0, S, sq):
    for x in range(0, S, sq):
        c = '#2B3240' if ((x//sq + y//sq) % 2 == 0) else '#232A36'
        d.rectangle([PAD+x, PAD+y, PAD+x+sq-1, PAD+y+sq-1], fill=c)

# ---- 背景层示意（下层，用户说不做）----
bg = Image.open(BG).convert('RGB').resize((S, S), Image.LANCZOS)
canvas.paste(Image.blend(Image.new('RGB', (S, S), '#232A36'), bg, 0.35), (PAD, PAD))

# ---- 前景层内容（45% 不透明）----
fg = Image.open(SRC).convert('RGBA').resize((S, S), Image.LANCZOS)
a = fg.getchannel('A').point(lambda v: int(v * 0.45))
fg.putalpha(a)
canvas.paste(fg, (PAD, PAD), fg)
d = ImageDraw.Draw(canvas)

def dash_box(x0, y0, x1, y1, color, dash=18, gap=12, width=3):
    def line(p0, p1):
        import math
        L = math.hypot(p1[0]-p0[0], p1[1]-p0[1]); n = max(1, int(L // (dash+gap)))
        for i in range(n+1):
            t0 = i*(dash+gap)/L; t1 = min(1.0, (i*(dash+gap)+dash)/L)
            if t0 >= 1: break
            d.line([p0[0]+(p1[0]-p0[0])*t0, p0[1]+(p1[1]-p0[1])*t0,
                    p0[0]+(p1[0]-p0[0])*t1, p0[1]+(p1[1]-p0[1])*t1], fill=color, width=width)
    line((x0,y0),(x1,y0)); line((x1,y0),(x1,y1)); line((x1,y1),(x0,y1)); line((x0,y1),(x0,y0))

# ---- 方形蒙版（squircle）----
d.rounded_rectangle([p(0), p(0), p(1024), p(1024)], radius=int(1024*0.24*SS), outline='#FFFFFF', width=3)
# ---- 圆形蒙版 ----
d.ellipse([p(0), p(0), p(1024), p(1024)], outline='#4FC3F7', width=2)
# ---- 安全区 700x700 ----
safe0, safe1 = (1024-700)/2, (1024+700)/2
dash_box(p(safe0), p(safe0), p(safe1), p(safe1), '#3DFF9A', width=3)
# ---- 实测内容框 159,211 - 868,787 ----
dash_box(p(159), p(211), p(868), p(787), '#FFB020', width=3)

def tag(x, y, text, color, anchor='lt'):
    bb = d.textbbox((0,0), text, font=F_S)
    tw, th = bb[2]-bb[0], bb[3]-bb[1]
    x0 = x if anchor[0]=='l' else (x-tw if anchor[0]=='r' else x-tw/2)
    y0 = y if anchor[1]=='t' else (y-th if anchor[1]=='b' else y-th/2)
    d.rectangle([x0-6, y0-4, x0+tw+6, y0+th+8], fill='#0C1017')
    d.text((x0, y0), text, font=F_S, fill=color)

tag(p(512), p(1024)+8,  '1024 x 1024 px 正方形（前景层 PNG / RGBA）', '#FFFFFF', 'ct')
tag(p(safe0)+8, p(safe0)-24, '安全区 700 x 700（居中 68%）', '#3DFF9A')
tag(p(159), p(211)-24, '当前 NGF 前景实测内容框 709 x 576', '#FFB020')
tag(p(1024)-10, p(1024)-14, '圆形蒙版（部分设备）', '#4FC3F7', 'rb')
tag(p(1024)-10, p(1024)-44, '圆角方形蒙版（手机/平板）', '#FFFFFF', 'rb')

# ================= 图例 =================
lx = PAD + S + 46
ly = PAD + 6
d.text((lx, ly), 'HarmonyOS 分层图标 · 前景层交付参考', font=F_T, fill='#FFFFFF'); ly += 52
d.text((lx, ly), 'AppScope/resources/base/media/foreground.png', font=F_B, fill='#9AA6B2'); ly += 44

rows = [
 ('#FFFFFF', '圆角方形蒙版', '系统按场景自动裁切；图标无需自带圆角、内边距或外框'),
 ('#4FC3F7', '圆形蒙版',     '部分设备/场景使用；内容必须同时适配圆形与方形'),
 ('#3DFF9A', '安全区 700px', '关键图形控制在居中 700x700 内（占 68%），边缘 162px 留空'),
 ('#FFB020', '实测内容框',   '现有 NGF 前景内容 709x576，居中；新 logo 建议不超过它'),
]
for color, name, desc in rows:
    d.rectangle([lx, ly+6, lx+16, ly+22], fill=color)
    d.text((lx+28, ly), name, font=F_H, fill=color); ly += 30
    d.text((lx+28, ly), desc, font=F_S, fill='#C6D0DA'); ly += 40
    ly += 6

ly += 10
d.text((lx, ly), '硬性要求', font=F_H, fill='#FFFFFF'); ly += 34
reqs = [
 '前景层 1024x1024 PNG，必须保留透明通道',
 '非核心区域 100% 透明（alpha = 0）',
 '不要手动加圆角、内边距、外框或投影出血',
 '背景层为不透明纯色 #0962F2（本次不改）',
 '同一资源需同时放入 AppScope 与 entry 两个 media 目录',
 '启动图标 startIcon.png（256）与 icon.png（64）需另行合成',
]
for r in reqs:
    d.text((lx, ly), '· ' + r, font=F_S, fill='#C6D0DA'); ly += 30

ly += 10
d.text((lx, ly), '自检', font=F_H, fill='#FFFFFF'); ly += 34
for r in ['缩到 48px 仍可辨认', '叠在 #0962F2 上对比清晰', '放大 1.5 倍（启动缩放）不露边']:
    d.text((lx, ly), '· ' + r, font=F_S, fill='#C6D0DA'); ly += 30

import os
os.makedirs('docs/logo', exist_ok=True)
canvas.save(OUT)
print('saved', OUT, canvas.size)
