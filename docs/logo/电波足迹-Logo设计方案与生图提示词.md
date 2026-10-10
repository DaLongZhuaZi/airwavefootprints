# 电波足迹 App Logo 设计方案与生图提示词

> 目标：在**不改动 NGF 图标家族语言**的前提下，为「电波足迹 / Airwave Footprints」设计
> **上层透明前景层（foreground）**，背景层（background）本次不动。
>
> 交付物：① 设计判断与取舍 ② 5 个完整概念的**可直接粘贴的生图提示词** ③ 通用提示词积木
> ④ 模型选择 ⑤ 落地到本工程的步骤。
>
> 配套图：[`docs/logo/safe-area-guide.png`](safe-area-guide.png) —— 蒙版 / 安全区 / 实测内容框参考。

---

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| 家族基因保留什么 | 玻璃质感「窗口」剪影、标题栏三颗圆角方块、右上交叉高光、冰蓝 aqua 材质、`#D9F9FF` 边缘光、透明留白比例 |
| 替换什么 | 窗口里的 `>_ NGF` → 「电波 + 足迹」图形；可选把 `NGF` 字标换成 `AWF` |
| 最推荐 | **概念 B「波纹足迹」**（产品表达最强） + **概念 A「同频窗」**（家族对齐最稳）各出一版，再挑 |
| 最稳 | **概念 D「脚印入波」**，缩到 48px 仍清楚 |
| 一句话提示词骨架 | 冰蓝 aqua 玻璃 + 同心弧「收进来」+ 弧上踩出脚印 + 1024 方形 + 纯绿幕背景待抠图 |

---

## 1. 现状取证：现有 NGF 图标到底是什么

实测（非目测）结果：

| 项 | 值 |
|---|---|
| 前景层 | `AppScope/resources/base/media/foreground.png`，1024×1024，**RGBA，含透明通道** |
| 背景层 | `AppScope/resources/base/media/background.png`，1024×1024，RGB，**不透明纯色 `#0962F2`** |
| 分层描述 | `AppScope/resources/base/media/layered_image.json` → `background` + `foreground` |
| 引用位置 | `AppScope/app.json5` 的 `icon: $media:layered_image`；`entry/src/main/module.json5` 第 130 / 198 行同款 |
| 启动图标 | `startIcon.png`（256×256，已合成的成品图）、`icon.png`（64×64） |
| 重要事实 | `entry/` 与 `ngf_framework/` 的 `icon.png`、`startIcon.png` **哈希完全相同** —— 当前 App 直接复用了框架图标，还没有自己的身份 |

**前景层实测内容框：x 159–868，y 211–787 → 709 × 576 px，居中（占画布 69% × 56%）。**
新 logo 建议不超过这个范围。

**配色采样（前景层真实像素）：**

| 用途 | 取值 |
|---|---|
| 玻璃主体深底 | `#295796` → `#466EA4` → `#4676AF` |
| 中间调 | `#5B8FD0` / `#88B3E0` / `#95C2F7` |
| 大面积高光扫掠 | `#C1E4FF` → `#E6F7FF` → `#FDFFFF` |
| 边缘光（rim） | `#D9F9FF` / `#C5E7FF` |
| 浮雕字面 | `#CEEBFF` → `#F9FBFF`，暗边 `#3B70B2` |
| 背景层纯色 | `#0962F2` |

---

## 2. 从 NGF 图标里要继承的 6 条「家族 DNA」

写提示词时这 6 条就是**必须出现的词**，缺一条就会「不像一家人」：

1. **玻璃窗口剪影** —— 圆角方形面板 + 顶部一条窄标题栏 + 栏下一条亮分隔线。
2. **三颗圆角方块** —— 标题栏左侧并排三个小圆角**方块**（不是圆点，现有图标是方的）。
3. **右上交叉高光** —— 标题栏右上角一个「X」形双斜线镜面反光。
4. **aqua 玻璃材质** —— 深钢蓝底 + 大面积白冰色斜向扫掠高光 + 淡青边缘光 + 内斜面。
5. **浮雕元素** —— 所有凸起物都是浅冰色（`#CEEBFF`~`#F9FBFF`）浮雕，带 `#3B70B2` 暗边和柔和投影。
6. **透明留白比例** —— 图形居中、内容控制在 68% 内、四周 100% 透明。

---

## 3. 电波足迹要表达什么：产品事实 → 设计约束

这一节决定了「什么该画、什么绝对不能画」。依据是 `README.md` 的**设计底线**四条。

| 产品事实 | 对 logo 的约束 |
|---|---|
| **只接收，不连接**（BLE / 星闪 / Wi-Fi 三条链路全被动） | 同心弧必须**朝内收敛**、能量在源点最亮向外衰减；**禁止**发射箭头、禁止天线塔、禁止雷达向外打波的观感 |
| **严格离线**（无任何后台网络行为） | 不画云、地球、上传箭头、Wi-Fi 路由器 |
| **数据只在本机** | 不画云端、同步、共享符号 |
| **三类电波** | 三条弧 / 三色小点 正好对应 BLE、星闪、Wi-Fi |
| **足迹 = 信号轨迹** | 「足迹」在代码里有实据：雷达按强度映射**圈层**（`FieldwatchRadarCluster.ets` 的 `ringOf()`），列表里有「信号轨迹」视图 —— 弧线 + 脚印正好是这两个东西的合体 |
| **观测强度随距离衰减** | 脚印**越远越小越淡**，这不是装饰，是把 RSSI 衰减画进了 logo |

### ⚠️ 一个必须知道的真实取舍

官方《应用图标规范》对**手机 / 平板**前景层的要求是：
「扁平风，图形简洁、色彩鲜明；**无复杂装饰、无渐变底色**，聚焦单一核心图形」；
只有**电脑 / 智慧屏**才建议「微立体风格，可加轻微纹理」。

而现有 NGF 图标是**微立体玻璃风**，工程 `deviceTypes` 又是 `phone / tablet / 2in1 / car` 全都要。

也就是说：

- 想**保住家族一致性** → 沿用玻璃微立体（本方案默认），但要接受它偏离手机端「扁平风」建议；
- 想**严格贴规范** → 用本文第 6 节的「扁平合规版」风格开关，但那会和 NGF 图标不像一家人。

**建议：两版都出，桌面图标用玻璃版保持家族感，需要过审/极简场景用扁平版。** 这个决定权在你。

---

## 4. 通用提示词积木（先拼这三块，再套概念）

### 4.1 STYLE CORE —— NGF aqua 玻璃（家族版）

```
STYLE CORE:
Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s Aqua /
Windows-Vista gel era, high-key, clean and polished, not cartoonish, not a
plastic 3D toy, not photorealistic.
Base body: deep steel-blue gradient from #295796 to #466EA4.
Over it, two or three broad soft white-ice specular sweeps running diagonally,
peaking at #E6F7FF and #FDFFFF.
Rim light: a 3-4 px pale cyan highlight edge #D9F9FF following the whole
silhouette, with a slightly darker 1 px line just inside it.
Every raised shape has a soft inner bevel and is embossed in pale ice
(#CEEBFF to #F9FBFF) with a subtle darker blue edge (#3B70B2) and a soft shadow.
One crisp crossing lens flare made of two thin diagonal light streaks sits in
the upper right.
Gentle wide low-opacity glow hugging the silhouette; no hard cast shadow.
Soft even studio lighting from the upper left.
```

### 4.2 TECH BLOCK —— HarmonyOS 分层图标前景层交付约束

```
TECH BLOCK:
Square 1:1 canvas, 1024 x 1024 px.
Exactly one centered graphic, drawn straight-on and flat to the viewer, no
perspective, no tilt.
All essential artwork stays inside a centered 700 x 700 px area (68% of the
canvas); the outer 162 px ring on every side stays completely empty.
Do NOT draw any rounded-corner mask, frame, border, plate, plaque, pedestal or
background shape.
Do NOT draw any background. Fill the entire empty area with flat pure chroma-key
green #00FF00, perfectly even, no gradient, no texture, no vignette, no shadow -
it will be keyed out to full transparency afterwards.
High resolution, crisp anti-aliased edges, clean readable silhouette,
centered composition, generous negative space.
```

> 用磷光配色（第 6.2 节）时，把 `#00FF00` 换成 `#FF00FF` 洋红幕，避免和荧光绿打架。

### 4.3 NEGATIVE —— 通用负向提示词

```
NEGATIVE:
photorealistic, 3D render, octane render, clay render, mockup, product shot,
device frame, phone body, tablet, screen bezel, glossy photo,
rounded-corner mask applied to the image, background gradient, any colored
background other than the chroma key, drop shadow bleeding to the canvas edge,
cropped or clipped elements, off-center composition, busy cluttered detail,
more than one object, extra letters, gibberish text, caption, watermark,
signature, another brand's logo,
antenna mast, radio tower, satellite dish, transmission waves with outward
arrows, radiation trefoil, wifi router with antennas, cloud icon, upload arrow,
globe, radar gun,
human foot photograph, bare foot, realistic anatomy, skin texture, toenails,
sandal, shoe, sneaker, muddy footprint, ink stamp, animal paw print, dog paw,
bear claw, tiger paw
```

> **这条负向很关键**：只写 "footprint" 时，模型极易产出**狗爪印**或**写实的人脚照片**。
> 必须显式写 `small crisp footprint sole, rounded heel, narrow arched waist,
> rounded ball, four to five tiny toe dots`，并同时排除 `animal paw print` 和
> `realistic anatomy / skin texture`。

---

## 5. 五个完整概念（每个都是可直接粘贴的整段提示词）

### 概念 A｜「同频窗」Twin Window —— 家族对齐最强 · 最稳

**一句话**：把 NGF 那扇窗户原样留下，只把 `>_` 换成电波图形、把 `NGF` 换成 `AWF`。
**为什么成立**：NGF ↔ AWF 都是三字母拉丁字标、同一种浮雕处理，两个 App 摆在一起就是亲兄弟。
**风险**：最保守，产品辨识度靠图形而非字标，所以图形必须写清楚。

```
A single app-icon foreground graphic on a 1024x1024 px square canvas.

Subject: one glossy translucent "aqua glass" application-window panel, seen
straight on, centered, occupying about 700 x 560 px of the canvas. The panel is
a rounded square with a generous corner radius and a slim horizontal title bar
across the top. Inside the title bar, three small rounded-square buttons sit in
a row at the left. A thin bright divider line separates the title bar from the
body. One crisp crossing lens flare made of two thin diagonal light streaks sits
at the upper right of the title bar.

Inside the panel body, in the upper-left quadrant, a compact radio-wave glyph:
a small solid rounded-square "sensor" dot with three concentric arcs opening
toward the upper right, the middle arc interrupted by a tiny footprint-sole
notch, all embossed in pale ice with a soft blue inner shadow.

Below the glyph, filling the lower half of the body, the three capital letters
"AWF" in a heavy geometric sans-serif with tight letter-spacing, embossed and
beveled in pale ice-white, with a subtle darker blue edge and a soft shadow,
as if moulded into the glass. Exactly three letters, spelled A-W-F.

STYLE: Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s
Aqua / Windows-Vista gel era, high-key, clean and polished. Base body: deep
steel-blue gradient from #295796 to #466EA4. Over it, two or three broad soft
white-ice specular sweeps running diagonally, peaking at #E6F7FF and #FDFFFF.
Rim light: a 3-4 px pale cyan highlight edge #D9F9FF following the whole
silhouette, with a slightly darker 1 px line just inside it. Every raised shape
has a soft inner bevel and is embossed in pale ice (#CEEBFF to #F9FBFF) with a
subtle darker blue edge (#3B70B2) and a soft shadow. Gentle wide low-opacity
glow hugging the silhouette, no hard cast shadow. Soft even studio lighting
from the upper left.

TECH: Square 1:1 canvas, 1024 x 1024 px. Exactly one centered graphic, drawn
straight-on and flat to the viewer, no perspective, no tilt. All essential
artwork stays inside a centered 700 x 700 px area; the outer 162 px ring on
every side stays completely empty. Do NOT draw any rounded-corner mask, frame,
border, plate or background shape. Do NOT draw any background. Fill the entire
empty area with flat pure chroma-key green #00FF00, perfectly even, no gradient,
no texture, no vignette, no shadow. High resolution, crisp anti-aliased edges,
clean readable silhouette, centered composition.

NEGATIVE: photorealistic, 3D render, mockup, device frame, phone body, screen
bezel, rounded-corner mask applied to the image, background gradient, any
colored background other than the chroma key, drop shadow bleeding to the canvas
edge, cropped elements, off-center composition, extra letters, misspelled text,
watermark, signature, antenna mast, radio tower, satellite dish, radiation
trefoil, wifi router, cloud icon, upload arrow, globe, human foot photograph,
bare foot, realistic anatomy, skin texture, sandal, shoe, animal paw print,
dog paw, muddy footprint.
```

---

### 概念 B｜「波纹足迹」Ripple Trail —— 产品表达最强 · 主推

**一句话**：同心弧从「传感器」向外铺开，弧上踩出一串脚印，**越远越小越淡**。
**为什么成立**：弧 = 电波，脚印 = 足迹，衰减 = RSSI，弧朝内最亮 = 只接收。一个图形讲完整个产品。
**风险**：元素偏多，必须靠「三条弧 + 三个脚印」的克制版，别加成一片。

```
A single app-icon foreground graphic on a 1024x1024 px square canvas.

Subject: a radio-ripple emblem that leaves footprints - one centered mark, no
text, no window frame, no panel, occupying about 700 x 620 px of the canvas.

At the lower-left of the emblem sits a small solid rounded-square "sensor" node.
From that node, three concentric arcs sweep outward toward the upper right,
evenly spaced and parallel, like ripples spreading from a single point.

The arcs are brightest and thickest at the node and become progressively
thinner, paler and more transparent outward, so the emblem clearly reads as
RECEIVING energy from the surrounding field - never as a beacon emitting it.
No arrows, no outward rays.

Pressed into the middle arc, a small crisp footprint sole: a rounded heel, a
narrow arched waist, a rounded ball, and four tiny separated toe dots. It reads
as one step taken along the wave. A second, smaller footprint sole sits further
out on the third arc, and a third, tiny one near the outermost arc - each one
smaller and fainter than the last, so the trail visibly fades with distance.

Three tiny glowing blip dots of different sizes are scattered in the gaps
between the arcs. All elements share the same ice-glass material, with the
footprint soles raised slightly above the arcs.

STYLE: Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s
Aqua / Windows-Vista gel era, high-key, clean and polished, not cartoonish, not
photorealistic. Base: deep steel-blue gradient from #295796 to #466EA4. Over it,
two or three broad soft white-ice specular sweeps running diagonally, peaking at
#E6F7FF and #FDFFFF. Rim light: a 3-4 px pale cyan highlight edge #D9F9FF
following the whole silhouette, with a slightly darker 1 px line just inside it.
Every raised shape has a soft inner bevel and is embossed in pale ice (#CEEBFF
to #F9FBFF) with a subtle darker blue edge (#3B70B2) and a soft shadow. Gentle
wide low-opacity glow hugging the silhouette, no hard cast shadow. Soft even
studio lighting from the upper left.

TECH: Square 1:1 canvas, 1024 x 1024 px. Exactly one centered graphic, drawn
straight-on and flat to the viewer, no perspective, no tilt. All essential
artwork stays inside a centered 700 x 700 px area; the outer 162 px ring on
every side stays completely empty. Do NOT draw any rounded-corner mask, frame,
border, plate or background shape. Do NOT draw any background. Fill the entire
empty area with flat pure chroma-key green #00FF00, perfectly even, no gradient,
no texture, no vignette, no shadow. High resolution, crisp anti-aliased edges,
clean readable silhouette, centered composition.

NEGATIVE: photorealistic, 3D render, mockup, device frame, phone body, screen
bezel, rounded-corner mask applied to the image, background gradient, any
colored background other than the chroma key, drop shadow bleeding to the canvas
edge, cropped elements, off-center composition, text, caption, watermark,
signature, antenna mast, radio tower, satellite dish, transmission waves with
outward arrows, radiation trefoil, wifi router, cloud icon, upload arrow, globe,
human foot photograph, bare foot, realistic anatomy, skin texture, sandal, shoe,
animal paw print, dog paw, bear claw, muddy footprint, ink stamp, too many
elements, cluttered.
```

---

### 概念 C｜「雷达盘」Radar Scope —— 仪器感 / 观测感最强

**一句话**：NGF 的窗户变成一台雷达仪，盘面上是环格 + 十字准星 + 扫掠扇区 + 光点，
其中最近的两个光点是小脚印，之间连着一条虚线轨迹。
**为什么成立**：直接对应 App 里的「实时雷达」标签页，和代码里的强度圈层一一对应。
**风险**：细节最多，缩到 48px 会糊；适合做**应用内**的 logo / 关于页大图，桌面上要慎用。

```
A single app-icon foreground graphic on a 1024x1024 px square canvas.

Subject: a glossy translucent "aqua glass" instrument panel whose face is a
radar scope, seen straight on, centered, occupying about 700 x 620 px of the
canvas.

The panel is a rounded square with a slim horizontal title bar across the top.
Inside the title bar, three small rounded-square buttons sit in a row at the
left. A thin bright divider line separates the title bar from the body. One
crisp crossing lens flare made of two thin diagonal light streaks sits at the
upper right of the title bar.

The panel face is a radar scope: four fine concentric rings, a thin crosshair
with small tick marks around the outer ring, and a soft wedge-shaped sweep
highlight in the lower-left quadrant. The scope face is slightly recessed into
the panel with a soft inner shadow.

On the rings sit five small blips. The two nearest blips are tiny footprint
soles; the other three are simple round dots of varying size. A faint dotted
trail of six dots connects the two nearest blips, curving gently - the path a
device took across the field. The rings, crosshair and blips are all embossed
in pale ice.

STYLE: Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s
Aqua / Windows-Vista gel era, high-key, clean and polished. Base body: deep
steel-blue gradient from #295796 to #466EA4. Over it, two or three broad soft
white-ice specular sweeps running diagonally, peaking at #E6F7FF and #FDFFFF.
Rim light: a 3-4 px pale cyan highlight edge #D9F9FF following the whole
silhouette, with a slightly darker 1 px line just inside it. Every raised shape
has a soft inner bevel and is embossed in pale ice (#CEEBFF to #F9FBFF) with a
subtle darker blue edge (#3B70B2) and a soft shadow. Gentle wide low-opacity
glow hugging the silhouette, no hard cast shadow. Soft even studio lighting
from the upper left.

TECH: Square 1:1 canvas, 1024 x 1024 px. Exactly one centered graphic, drawn
straight-on and flat to the viewer, no perspective, no tilt. All essential
artwork stays inside a centered 700 x 700 px area; the outer 162 px ring on
every side stays completely empty. Do NOT draw any rounded-corner mask, frame,
border, plate or background shape. Do NOT draw any background. Fill the entire
empty area with flat pure chroma-key green #00FF00, perfectly even, no gradient,
no texture, no vignette, no shadow. High resolution, crisp anti-aliased edges,
clean readable silhouette, centered composition.

NEGATIVE: photorealistic, 3D render, mockup, device frame, phone body, screen
bezel, rounded-corner mask applied to the image, background gradient, any
colored background other than the chroma key, drop shadow bleeding to the canvas
edge, cropped elements, off-center composition, text, caption, watermark,
signature, antenna mast, radio tower, satellite dish, outward transmission
arrows, radiation trefoil, wifi router, cloud icon, globe, human foot
photograph, bare foot, realistic anatomy, skin texture, sandal, shoe, animal paw
print, dog paw, muddy footprint, cluttered, noisy.
```

---

### 概念 D｜「脚印入波」Footprint in the Ripple —— 最简洁 · 小尺寸最稳

**一句话**：一个干净的脚印踩在静水上，涟漪从脚下荡开；脚印里刻着一道三峰信号波。
**为什么成立**：只有一个主体，48px 下依然是一个明确剪影；「电波」交给涟漪，「足迹」交给脚印。
**风险**：最不「NGF」，家族感最弱 —— 适合作为**独立品牌**方向，或配合概念 A 一起用。

```
A single app-icon foreground graphic on a 1024x1024 px square canvas.

Subject: one large clean footprint sole pressed into still water, centered,
occupying about 620 x 700 px of the canvas. No text, no window frame, no panel.

The sole is one single confident silhouette: a rounded heel at the bottom, a
narrow arched waist, a broad rounded ball, and five separated toe dots above it
with the biggest toe on the inside. It is drawn as a smooth solid shape in pale
ice-white glass with a soft inner bevel - not an outline, not a wireframe.

From beneath and around the sole, four concentric ripple arcs spread outward,
evenly spaced, tilted slightly so the ripples open toward the upper right. Each
ripple is thinner and fainter than the one inside it. A very subtle three-crest
signal waveform is engraved into the sole as a thin darker groove line running
across the heel and the ball.

Two or three tiny glowing blip dots float in the gaps between the outer
ripples.

STYLE: Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s
Aqua / Windows-Vista gel era, high-key, clean and polished, minimal and iconic.
Base: deep steel-blue gradient from #295796 to #466EA4. Over it, two or three
broad soft white-ice specular sweeps running diagonally, peaking at #E6F7FF and
#FDFFFF. Rim light: a 3-4 px pale cyan highlight edge #D9F9FF following the
whole silhouette, with a slightly darker 1 px line just inside it. Every raised
shape has a soft inner bevel and is embossed in pale ice (#CEEBFF to #F9FBFF)
with a subtle darker blue edge (#3B70B2) and a soft shadow. Gentle wide
low-opacity glow hugging the silhouette, no hard cast shadow. Soft even studio
lighting from the upper left.

TECH: Square 1:1 canvas, 1024 x 1024 px. Exactly one centered graphic, drawn
straight-on and flat to the viewer, no perspective, no tilt. All essential
artwork stays inside a centered 700 x 700 px area; the outer 162 px ring on
every side stays completely empty. Do NOT draw any rounded-corner mask, frame,
border, plate or background shape. Do NOT draw any background. Fill the entire
empty area with flat pure chroma-key green #00FF00, perfectly even, no gradient,
no texture, no vignette, no shadow. High resolution, crisp anti-aliased edges,
clean readable silhouette, centered composition, generous negative space.

NEGATIVE: photorealistic, 3D render, mockup, device frame, phone body, screen
bezel, rounded-corner mask applied to the image, background gradient, any
colored background other than the chroma key, drop shadow bleeding to the canvas
edge, cropped elements, off-center composition, text, caption, watermark,
signature, antenna mast, radio tower, satellite dish, outward transmission
arrows, radiation trefoil, wifi router, cloud icon, globe, water splash, water
droplets, ocean, lake photograph, human foot photograph, bare foot, realistic
anatomy, skin texture, toenails, sandal, shoe, sneaker, muddy footprint, ink
stamp, animal paw print, dog paw, bear claw, tiger paw, cluttered.
```

---

### 概念 E｜「三步三波」Three Traces —— 「足迹」本义最强 · 讲「很多设备」

**一句话**：三个脚印从左上走到右下，每个脚印周围各有一小段**不同大小**的弧。
**为什么成立**：弧大小不同 → 不是单一发射源，而是**一片被读取的电波场**；
脚印数量 → 「谁在广播、叫什么、属于哪一类」的复数感。这是最贴合「观测工具」而非「发射器」的构图。
**风险**：三个脚印 + 三段弧，需要严格控制数量，多了就乱。

```
A single app-icon foreground graphic on a 1024x1024 px square canvas.

Subject: three footprint soles stepping diagonally from the lower left to the
upper right across the emblem, centered, occupying about 700 x 600 px of the
canvas. No text, no window frame, no panel.

Each footprint sole is a small crisp shape with a rounded heel, a narrow arched
waist, a rounded ball and four tiny separated toe dots. The three soles step in
a gentle curve, evenly spaced, each one slightly smaller and fainter than the
previous one, so the trail fades as it travels.

Around each sole, a short fragment of a concentric arc curves past it - the
edge of the ripple ring that sole belongs to. The three arcs are all of
different radii and different curvatures, and they are not concentric with each
other, so the emblem reads as a whole field of radio waves being observed rather
than one single transmitter. Each arc is thinnest and faintest at its ends.

Two or three tiny glowing blip dots sit in the empty space between the arcs.
All elements share the same ice-glass material, with the footprint soles raised
slightly above the arcs.

STYLE: Glossy translucent "aqua glass" skeuomorphic app-icon style, early-2000s
Aqua / Windows-Vista gel era, high-key, clean and polished. Base: deep
steel-blue gradient from #295796 to #466EA4. Over it, two or three broad soft
white-ice specular sweeps running diagonally, peaking at #E6F7FF and #FDFFFF.
Rim light: a 3-4 px pale cyan highlight edge #D9F9FF following the whole
silhouette, with a slightly darker 1 px line just inside it. Every raised shape
has a soft inner bevel and is embossed in pale ice (#CEEBFF to #F9FBFF) with a
subtle darker blue edge (#3B70B2) and a soft shadow. Gentle wide low-opacity
glow hugging the silhouette, no hard cast shadow. Soft even studio lighting
from the upper left.

TECH: Square 1:1 canvas, 1024 x 1024 px. Exactly one centered graphic, drawn
straight-on and flat to the viewer, no perspective, no tilt. All essential
artwork stays inside a centered 700 x 700 px area; the outer 162 px ring on
every side stays completely empty. Do NOT draw any rounded-corner mask, frame,
border, plate or background shape. Do NOT draw any background. Fill the entire
empty area with flat pure chroma-key green #00FF00, perfectly even, no gradient,
no texture, no vignette, no shadow. High resolution, crisp anti-aliased edges,
clean readable silhouette, centered composition.

NEGATIVE: photorealistic, 3D render, mockup, device frame, phone body, screen
bezel, rounded-corner mask applied to the image, background gradient, any
colored background other than the chroma key, drop shadow bleeding to the canvas
edge, cropped elements, off-center composition, text, caption, watermark,
signature, antenna mast, radio tower, satellite dish, outward transmission
arrows, radiation trefoil, wifi router, cloud icon, globe, more than three
footprints, walking track photo, human foot photograph, bare foot, realistic
anatomy, skin texture, toenails, sandal, shoe, sneaker, muddy footprint, ink
stamp, animal paw print, dog paw, bear claw, tiger paw, cluttered, noisy.
```

---

## 6. 两个可叠加的「风格开关」

任选一个概念，把它的 STYLE 段整段替换即可。

### 6.1 扁平合规版 —— 手机 / 平板规范最安全

```
STYLE (flat, spec-safe):
Flat vector style. No gradients, no gloss, no bevel, no inner shadow, no
texture, no glow, no 3D. Exactly one color: pure white #FFFFFF for every stroke
and every fill, on nothing. Uniform 60 px stroke weight on the 1024 px canvas,
round caps and round joins, geometric and precise, generous spacing.
Silhouette must stay readable as a single-color mark.
```
> 配上：`Flat minimal line-art logo, single color, no shading.`
> 负向额外加：`gradient, gloss, reflection, bevel, emboss, drop shadow, 3D, texture, chrome, metallic`。

### 6.2 磷光产品版 —— 和 App 内界面配色对齐

App 内真实配色（`FieldwatchPalette.ets` 深色档）：底色 `#0B0F14`、面板 `#141A22`、
强调荧光绿 `#3DFF9A`、琥珀 `#FFB020`、青 `#4FC3F7`、星闪紫 `#7C6BFF` —— 辐射 4 / Pip-Boy 终端风。

```
STYLE (Pip-Boy phosphor):
Matte near-black anodised glass field instrument, retro-futuristic terminal
aesthetic, rendered clean and modern, not grungy, not dirty.
Body and panel: #0B0F14 and #141A22 with a #2A3340 hairline edge.
Emissive elements glow with a soft phosphor bloom: primary #3DFF9A, secondary
amber #FFB020, cyan #4FC3F7, violet #7C6BFF.
A very subtle horizontal CRT scanline texture at 4% opacity over the dark
surfaces only. A soft green ambient glow spills onto the surrounding dark glass.
No white specular sweeps, no chrome, no gloss.
```
> **⚠️ 用这一版必须同时改背景层**：黑玻璃压在 `#0962F2` 亮蓝底上会发脏。
> 背景层要一起换成 `#0B0F14`（或极深蓝黑）。你说了本次不做背景层，所以这一版留作备选。
> 另外：色键要改用洋红 `#FF00FF`，否则荧光绿和绿幕会互相干扰。

---

## 7. 模型选择与参数

| 模型 | 能否直接出透明 PNG | 建议 |
|---|---|---|
| **Recraft / Ideogram** | ✅ 支持透明导出，Recraft 还能出 **SVG 矢量** | **首选**，logo 场景最合适 |
| **GPT-Image / DALL·E** | ✅ 提示里明确要 transparent background 可出 | 好上手，但几何精度一般 |
| **Nano Banana（Gemini 图像）/ Seedream 4.0** | ⚠️ 部分模式支持 | 出图快，适合找灵感；Seedream 中文理解好 |
| **Midjourney** | ❌ 不支持透明 | 用绿幕法；`--ar 1:1 --style raw`；**不要**指望 `--no background` |
| **Flux (dev / Kontext)** | ❌ | 绿幕法 + 后期抠图 |

**实操建议（重要）**：

1. **一个概念一次出 4 张**，只挑「构图对了」的那张，不要指望一次到位。
2. 模型**做不准精确 hex 和精确几何**。提示词里的 `#295796` 这类值是**引导**，不是保证。
   最终稿建议：拿模型图当构图稿，在 **Figma / Illustrator / Inkscape** 里用第 1 节的精确取色重画一遍。
3. **字标（AWF）不要让模型写**。先生成不带字的图形，再用矢量工具加字，
   套用同一套浮雕（`#CEEBFF`~`#F9FBFF` 面 + `#3B70B2` 暗边）。
4. 绿幕抠图：PS「选择 → 色彩范围」吸取 `#00FF00`，容差 20–30，反选后加蒙版；
   边缘残留绿边时，用「去边 / 净化颜色」处理 1–2 px。
5. 出图分辨率尽量 ≥1024，最后统一缩到 **1024×1024**，再单独检查 48px 效果。

---

## 8. 落地到本工程

拿到最终 PNG 之后：

| 步骤 | 操作 |
|---|---|
| 1 | 覆盖 `AppScope/resources/base/media/foreground.png`（1024×1024，**RGBA 带透明**） |
| 2 | 覆盖 `entry/src/main/resources/base/media/foreground.png`（同上，当前两份文件哈希一致，要同步换） |
| 3 | `background.png` 与 `layered_image.json` **本次不动** |
| 4 | 另行合成 `entry/src/main/resources/base/media/startIcon.png`（256×256，前景 + 背景合成后的成品图，供启动页用） |
| 5 | 另行合成 `entry/src/main/resources/base/media/icon.png`（64×64） |
| 6 | `ngf_framework/src/main/resources/base/media/` 下的图标**保留 NGF 原样** —— 那是框架自己的身份，不要一起换掉 |
| 7 | 不需要改 `AppScope/app.json5` 与 `module.json5`，`icon: $media:layered_image` 引用关系不变 |

**自检清单**（配套图见 [safe-area-guide.png](safe-area-guide.png)）：

- [ ] 1024×1024 正方形，**PNG 且带 alpha 通道**
- [ ] 非核心区域 **alpha 严格为 0**（用工具查一下，半透明残影会导致系统渲染出灰边）
- [ ] 关键图形在居中 **700×700** 内，四周 162px 干净
- [ ] 没有自己画圆角、边框、底板、外投影
- [ ] 缩到 **48px** 仍能认出「波 + 脚印」
- [ ] 叠在 `#0962F2` 上对比清楚（这是真实合成效果，不要只在白底上看）
- [ ] 放大 **1.5 倍**（启动缩放动画）不露边、不糊
- [ ] 圆形蒙版裁切后主体不被切掉

---

## 9. 一句话选择建议

- 想**最快稳过、最像一家人** → **概念 A**（同频窗 + AWF）
- 想**最能讲清楚这个 App 是什么** → **概念 B**（波纹足迹），我的首选
- 想**最简洁、桌面小尺寸最清楚** → **概念 D**（脚印入波）
- 想**强调「观测到很多设备」** → **概念 E**（三步三波）
- 想**做应用内大图 / 关于页插画** → **概念 C**（雷达盘）

最终建议出 **A + B 两版**：A 保家族、B 保产品，摆在一起挑一次就能定。
