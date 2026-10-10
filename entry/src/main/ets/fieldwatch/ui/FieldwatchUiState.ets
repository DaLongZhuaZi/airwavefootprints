import { DecodedFieldValue, FilterLogic, FilterDefinition, PresenceSpan, RadioKind, Sighting, WifiScanPhase } from '../domain/FieldwatchModels';
import { SignatureFleet } from '../domain/signatures/FieldwatchSignatureModels';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';
import { deviceClassSymbol, nearLinkClassSymbol } from './FieldwatchDeviceTypeIcon';

export enum FieldwatchLiveMode { RADAR = 'radar', STRENGTH = 'strength', TIMELINE = 'timeline', CLASS = 'class', TRAIL = 'trail' }
export enum FieldwatchNavigationTab { LIVE = 0, FILTERS = 1, SIGNATURES = 2, REPORTS = 3, TOOLBOX = 4, SETTINGS = 5 }
export enum FieldwatchUiStatus { SCANNING = 'scanning', UPDATED = 'updated', CACHED = 'cached', WAITING = 'waiting', LOCATION_DISABLED = 'location_disabled', WIFI_DISABLED = 'wifi_disabled', PERMISSION_DENIED = 'permission_denied', UNSUPPORTED = 'unsupported', EMPTY = 'empty', ERROR = 'error' }

/** 签名 colorIndex 0..8 的调色板；无命中签名时退回无线电类型颜色。 */
export function signatureColorAt(index: number): string {
  if (index < 0) return '';
  const ramp: string[] = FieldwatchPaletteHolder.get().signatureRamp;
  return ramp[index % ramp.length];
}

/** 命中签名的 colorIndex；多个命中时取第一个非 0 的签名，无命中返回 -1。 */
export function signatureColorIndex(sighting: Sighting, fleets: SignatureFleet[]): number {
  let result: number = -1;
  sighting.signatureIds.forEach((id: string): void => {
    if (result >= 0) return;
    const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
    if (fleet !== undefined && fleet.colorIndex > 0) result = fleet.colorIndex;
  });
  return result;
}

export class FieldwatchRadarPoint {
  public key: string;
  public x: number;
  public y: number;
  public radius: number;
  public kind: RadioKind;
  public label: string;
  public rssi: number;
  public frequencyMhz: number;
  public colorIndex: number;
  /** 设备类型对应的系统符号（雷达上直接画图标而不是圆点）。 */
  public symbol: string;
  /** 设备地址（MAC / BSSID），标签可选显示。 */
  public address: string;
  constructor(key: string, x: number, y: number, radius: number, kind: RadioKind, label: string = '', rssi: number = -100, frequencyMhz: number = 0, colorIndex: number = -1, symbol: string = '', address: string = '') { this.key = key; this.x = x; this.y = y; this.radius = radius; this.kind = kind; this.label = label; this.rssi = rssi; this.frequencyMhz = frequencyMhz; this.colorIndex = colorIndex; this.symbol = symbol; this.address = address; }
}

export class FieldwatchUiState {
  public tab: FieldwatchNavigationTab = FieldwatchNavigationTab.LIVE;
  public liveMode: FieldwatchLiveMode = FieldwatchLiveMode.RADAR;
  public filter: FilterDefinition = new FilterDefinition();
  public selectedKey: string = '';
  public errorMessage: string = '';

  setLiveMode(mode: FieldwatchLiveMode): void { this.liveMode = mode; }
  clearFilter(): void { this.filter = new FilterDefinition(); }
  setRadioKind(kind: RadioKind | undefined): void { this.filter.radioKind = kind; }
  setMinimumRssi(value: number | undefined): void { this.filter.minimumRssi = value; }
  setLogic(logic: FilterLogic): void { this.filter.logic = logic; }
  setWatchedOnly(enabled: boolean): void { this.filter.watchedOnly = enabled; }
  setAttentionOnly(enabled: boolean): void { this.filter.attentionOnly = enabled; }
  setFreshOnly(enabled: boolean): void { this.filter.freshOnly = enabled; if (enabled) this.filter.cachedOnly = false; }
  setCachedOnly(enabled: boolean): void { this.filter.cachedOnly = enabled; if (enabled) this.filter.freshOnly = false; }
}

/**
 * 雷达图标用的系统符号。
 *
 * 优先按命中签名的类别取图标；没有类别时按无线电种类兜底。
 * 类别映射复用 FieldwatchDeviceTypeIcon 的 classSymbol，**不在这里另写一份** ——
 * 两处各写一份必然会漂移，图标列表页和雷达上就会显示得不一样。
 */
export function radarSymbol(sighting: Sighting, fleets: SignatureFleet[]): string {
  let symbol: string = '';
  sighting.signatureIds.forEach((id: string): void => {
    if (symbol.length > 0) return;
    const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
    if (fleet !== undefined) symbol = deviceClassSymbol(fleet.category);
  });
  if (symbol.length > 0) return symbol;
  // 星闪广播自带设备类型，不需要特征库命中即可显示正确图标 ——
  // 这是星闪相对 BLE 的独有能力。放在特征库之后、通用兜底之前：
  // 特征库若能给出更具体的身份，优先用特征库的。
  if (sighting.kind === RadioKind.NEARLINK && sighting.facts.nearLinkDeviceClass >= 0) {
    return nearLinkClassSymbol(sighting.facts.nearLinkDeviceClass);
  }
  // 兜底：只有无线电种类、没有类别。
  return sighting.kind === RadioKind.WIFI ? 'sys.symbol.wifi' : 'sys.symbol.dot_radiowaves_left_and_right';
}

export function buildRadarPoints(sightings: Array<Sighting>, fleets: SignatureFleet[] = []): Array<FieldwatchRadarPoint> {
  const points: Array<FieldwatchRadarPoint> = [];
  const count: number = sightings.length;
  for (let index: number = 0; index < count; index += 1) {
    const sighting: Sighting = sightings[index];
    let hash: number = 0;
    for (let charIndex: number = 0; charIndex < sighting.key.length; charIndex += 1) hash = ((hash * 31) + sighting.key.charCodeAt(charIndex)) | 0;
    const angle: number = ((hash >>> 1) % 360) * Math.PI / 180;
    // **位置与半径都用平滑值，不用原始采样。**
    //
    // 原始 rssi 逐次波动可达十几 dBm，直接映射会让节点每帧都在挪、
    // 半径还在同步脉动 —— 观感就是「跳变 + 闪烁」（实测反馈）。
    // 平滑值只影响「画在哪里、画多大」，详情页显示的仍是真实读数。
    const shown: number = sighting.rssiDisplay === 0 ? sighting.rssi : sighting.rssiDisplay;
    const normalized: number = Math.max(0, Math.min(1, (-30 - shown) / 70));
    const distance: number = 0.12 + normalized * 0.88;
    const x: number = 0.5 + Math.cos(angle) * distance * 0.46;
    const y: number = 0.5 + Math.sin(angle) * distance * 0.46;
    const radius: number = 6 + Math.max(0, Math.min(1, (shown + 100) / 70)) * 7;
    let label: string = sighting.name.length > 0 ? sighting.name : sighting.facts.ssid;
    if (label.length === 0) {
      const names: string[] = matchedSignatureNames(sighting.signatureIds, fleets);
      label = names.length > 0 ? names[0] : sighting.address;
    }
    points.push(new FieldwatchRadarPoint(sighting.key, x, y, radius, sighting.kind, label, shown, sighting.facts.frequencyMhz, signatureColorIndex(sighting, fleets), radarSymbol(sighting, fleets), sighting.address));
  }
  return points;
}

export function sortSightingsForLiveMode(sightings: Array<Sighting>, mode: FieldwatchLiveMode): Array<Sighting> {
  const ordered: Array<Sighting> = sightings.slice();
  if (mode === FieldwatchLiveMode.STRENGTH) {
    ordered.sort((first: Sighting, second: Sighting): number => second.rssi - first.rssi || first.key.localeCompare(second.key));
  } else if (mode === FieldwatchLiveMode.TIMELINE) {
    ordered.sort((first: Sighting, second: Sighting): number => second.lastSeen - first.lastSeen || first.key.localeCompare(second.key));
  } else {
    ordered.sort((first: Sighting, second: Sighting): number => first.key.localeCompare(second.key));
  }
  return ordered;
}

/** Live 列表行只展示标记了 live 的解码值。 */
export function liveDecodeLabels(fields: DecodedFieldValue[]): string[] {
  const labels: string[] = [];
  fields.forEach((value: DecodedFieldValue): void => {
    if (!value.live) return;
    labels.push(value.label + ': ' + value.text);
  });
  return labels;
}

/**
 * 在场时段 → 时间轴的 `Path` commands 串（详情页「在场情况」）。
 *
 * 逐字对齐原版 `PresenceTrack`（`ui/component/Widgets.kt:154`）：
 *   - 窗口是 `now - windowMs` 到 `now`，横轴按比例映射；
 *   - 每段一条**居中窄条**：纵向 `top = h*0.25`、高 `h*0.5`；
 *   - **最小宽度 2px** —— 一次极短的在场也要看得见，否则用户以为没记录；
 *   - 仍在场的段（`end` 为空）画到 `now`。
 *
 * 抽成纯函数是为了可测：时间段映射错位时图上只是「条画歪了」，
 * 肉眼很难判断是数据问题还是映射问题。
 */
/**
 * 按品牌分组，返回按设备数降序的品牌名（数量相同按名称排，保证顺序稳定）。
 *
 * 抽成纯函数是为了可测：排序不稳定时分组标题会**每次刷新都换位置**，
 * 那是最容易被当成「界面在抖」而查错方向的一类问题。
 */
export function groupByBrand<T>(items: T[], brandOf: (item: T) => string): string[] {
  const counts: Map<string, number> = new Map<string, number>();
  items.forEach((item: T): void => {
    const brand: string = brandOf(item);
    const now: number | undefined = counts.get(brand);
    counts.set(brand, now === undefined ? 1 : now + 1);
  });
  const names: string[] = [];
  counts.forEach((_value: number, key: string): void => { names.push(key); });
  names.sort((a: string, b: string): number => {
    const ca: number | undefined = counts.get(a);
    const cb: number | undefined = counts.get(b);
    const va: number = ca === undefined ? 0 : ca;
    const vb: number = cb === undefined ? 0 : cb;
    if (va !== vb) return vb - va;
    return a < b ? -1 : 1;
  });
  return names;
}

/** 雷达标签排布的结果。 */
export class RadarLabelPlan {
  /** 拿到完整图标 + 标签的点（竖线包裹的键串）。 */
  public labeledKeys: string = '|';
  /** **放不下标签**的点：改为只画一个小圆点。 */
  public dotKeys: string = '|';
  /** 每个点的标签左上角，键 -> [left, top]。 */
  public lefts: number[] = [];
  public tops: number[] = [];
  public keys: string[] = [];
}

/** 标签相对锚点的八个候选方向。 */
export class RadarLabelOffset {
  public dx: number; public dy: number;
  constructor(dx: number, dy: number) { this.dx = dx; this.dy = dy; }
}

/**
 * 雷达标签排布（纯函数）。
 *
 * **为什么抽出来**：原来它只活在画布绘制里，放不下就 `return` ——
 * 图标层完全不知道这件事，于是照旧渲染大图标，
 * 挤的时候就是一堆图标互相压着（实测反馈）。
 * 抽成共用函数后，图标层能拿到 `dotKeys`，把这些点降级成小圆点。
 *
 * 排布策略与原实现一致：八个方向依次试，取第一个不越界、不与已放置标签相交的位置；
 * 都放不下就进 `dotKeys`。
 */
export function planRadarLabels(
  points: FieldwatchRadarPoint[], width: number, height: number,
  canvasXOf: (nx: number) => number, canvasYOf: (ny: number) => number,
  radiusOf: (p: FieldwatchRadarPoint) => number,
  titleOf: (p: FieldwatchRadarPoint) => string,
  detailOf: (p: FieldwatchRadarPoint) => string,
  fontPx: number, topLimit: number, bottomLimit: number): RadarLabelPlan {
  const plan: RadarLabelPlan = new RadarLabelPlan();
  const offsets: RadarLabelOffset[] = [
    new RadarLabelOffset(0.7, -0.7), new RadarLabelOffset(0.7, 0.7),
    new RadarLabelOffset(-0.7, -0.7), new RadarLabelOffset(-0.7, 0.7),
    new RadarLabelOffset(1, 0), new RadarLabelOffset(-1, 0),
    new RadarLabelOffset(0, -1), new RadarLabelOffset(0, 1)
  ];
  const lineHeight: number = fontPx + 6;
  const lefts: number[] = [];
  const tops: number[] = [];
  const rights: number[] = [];
  const bottoms: number[] = [];
  points.forEach((point: FieldwatchRadarPoint): void => {
    const title: string = titleOf(point);
    const detail: string = detailOf(point);
    if (title.length === 0 && detail.length === 0) {
      // 用户把标签字段全关了：没有标签可放，但图标仍应显示，不算放不下。
      plan.labeledKeys += point.key + '|';
      return;
    }
    const x: number = canvasXOf(point.x);
    const y: number = canvasYOf(point.y);
    const lineCount: number = (title.length > 0 ? 1 : 0) + (detail.length > 0 ? 1 : 0);
    const labelWidth: number = Math.max(title.length * fontPx * 0.55, detail.length * fontPx * 0.5) + 8;
    const labelHeight: number = lineHeight * lineCount;
    const radius: number = radiusOf(point);
    let placedLeft: number = 0;
    let placedTop: number = 0;
    let ok: boolean = false;
    for (let index: number = 0; index < offsets.length; index += 1) {
      const offset: RadarLabelOffset = offsets[index];
      const baseX: number = x + offset.dx * (radius + 8);
      const baseY: number = y + offset.dy * (radius + 10);
      const left: number = offset.dx < 0 ? baseX - labelWidth : baseX;
      const top: number = offset.dy < 0 ? baseY - labelHeight : baseY;
      const right: number = left + labelWidth;
      const bottom: number = top + labelHeight;
      if (left < 4 || right > width - 4 || top < topLimit || bottom > height - bottomLimit) continue;
      let collision: boolean = false;
      for (let i: number = 0; i < lefts.length; i += 1) {
        if (left < rights[i] && right > lefts[i] && top < bottoms[i] && bottom > tops[i]) {
          collision = true; break;
        }
      }
      if (!collision) { placedLeft = left; placedTop = top; ok = true; break; }
    }
    if (!ok) { plan.dotKeys += point.key + '|'; return; }
    lefts.push(placedLeft); tops.push(placedTop);
    rights.push(placedLeft + labelWidth); bottoms.push(placedTop + labelHeight);
    plan.labeledKeys += point.key + '|';
    plan.keys.push(point.key); plan.lefts.push(placedLeft); plan.tops.push(placedTop);
  });
  return plan;
}

/** 刻度标签（dBm）在画布上的位置。 */
export class TrendTickLabel {
  public text: string = '';
  public y: number = 0;
  constructor(text: string, y: number) { this.text = text; this.y = y; }
}

/**
 * 信号趋势图的几何量（对齐原版 `Sparkline`，`ui/component/Widgets.kt:62`）。
 *
 * 原版不是一根折线，而是**带完整坐标系的图**：
 *   - 8 条水平刻度线（标注的 4 条实线、其余虚线）、
 *   - 纵轴主线 + 4 列纵向虚线网格、
 *   - 左侧 dBm 标签、
 *   - 折线（3.2 圆头）+ **末点圆点**；只有一个样本时只画圆点。
 *
 * 抽成纯函数是因为：坐标映射错位时图上只是「线画歪了」，
 * 肉眼很难判断是数据问题还是映射问题。
 */
export class TrendGeometry {
  public vertical: string = '';
  public horizontalSolid: string = '';
  public horizontalDashed: string = '';
  public series: string = '';
  public dotX: number = 0;
  public dotY: number = 0;
  public dotRadius: number = 0;
  public hasDot: boolean = false;
  public labels: TrendTickLabel[] = [];
  public gutter: number = 0;
}

/** 趋势图的刻度与原版一致。 */
const TREND_TICKS: number[] = [-30, -40, -50, -60, -70, -80, -90, -100];
const TREND_LABELED: number[] = [-30, -50, -70, -100];
/** 标签槽宽：原版按 `-100` 的文本宽度 + 6 预留。这里用固定值保持一致。 */
const TREND_GUTTER: number = 26;

/** 计算趋势图几何量。`samples` 是 RSSI 样本（已按时间排序）。 */
export function trendGeometry(samples: number[], width: number, height: number): TrendGeometry {
  const out: TrendGeometry = new TrendGeometry();
  const left: number = TREND_GUTTER;
  const right: number = width;
  const plotW: number = right - left > 1 ? right - left : 1;
  out.gutter = left;
  const yOf = (rssi: number): number => {
    const clamped: number = Math.min(Math.max(rssi + 100, 0), 70);
    return height * (1 - clamped / 70);
  };
  // ① 水平刻度线：标注的实线、其余虚线
  let solid: string = '';
  let dashed: string = '';
  TREND_TICKS.forEach((dbm: number): void => {
    const y: number = yOf(dbm);
    const isLabeled: boolean = TREND_LABELED.indexOf(dbm) >= 0;
    const x1: number = isLabeled ? left : left;
    const line: string = 'M' + x1.toFixed(1) + ' ' + y.toFixed(1) + ' H' + right.toFixed(1);
    if (isLabeled) solid += line + ' '; else dashed += line + ' ';
  });
  out.horizontalSolid = solid;
  out.horizontalDashed = dashed;
  // ② 纵轴主线 + 4 列纵向虚线网格（合在同一 path：两者都是纵向线）
  let vert: string = 'M' + left.toFixed(1) + ' ' + yOf(-30).toFixed(1)
    + ' V' + yOf(-100).toFixed(1) + ' ';
  for (let c: number = 1; c < 4; c += 1) {
    const x: number = left + plotW * c / 4;
    vert += 'M' + x.toFixed(1) + ' ' + yOf(-30).toFixed(1)
      + ' V' + yOf(-100).toFixed(1) + ' ';
  }
  out.vertical = vert;
  // ③ 标签：纵向位置让文本大致居中于刻度线
  TREND_LABELED.forEach((dbm: number): void => {
    out.labels.push(new TrendTickLabel(dbm.toString(), yOf(dbm) - 5));
  });
  // ④ 序列：原版只画**有效测量**的样本
  const valid: number[] = samples.filter((value: number): boolean => value < 0);
  if (valid.length === 0) return out;
  if (valid.length === 1) {
    out.hasDot = true; out.dotX = right; out.dotY = yOf(valid[0]); out.dotRadius = 5;
    return out;
  }
  let path: string = '';
  const last: number = valid.length - 1;
  for (let i: number = 0; i <= last; i += 1) {
    const x: number = left + plotW * i / last;
    const y: number = yOf(valid[i]);
    path += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ' ' + y.toFixed(1) + ' ';
  }
  out.series = path;
  out.hasDot = true;
  out.dotX = right;
  out.dotY = yOf(valid[last]);
  out.dotRadius = 4.6;
  return out;
}

/**
 * 该 Wi-Fi 相位是否**需要用户处理**（决定要不要进「扫描异常」横幅）。
 *
 * 关键区分：
 *   - `SYSTEM_REJECTED`（系统限频）与 `WAITING_FOR_RETRY`（正在退避重试）
 *     是扫描的**正常节律**，系统本身就限制每应用几十秒一次，应用会自己重试成功；
 *   - `IDLE`/`PRECHECK`/`SCANNING`/`READY`/`STALE` 是正常工作状态。
 *
 * 把这些报成「异常」会让用户以为程序坏了。抽成纯函数是为了可测：
 * 判断写错时界面上只是多一条或漏一条横幅，肉眼很难发现。
 */
export function wifiPhaseNeedsAction(phase: string): boolean {
  return phase === WifiScanPhase.WIFI_DISABLED
    || phase === WifiScanPhase.LOCATION_DISABLED
    || phase === WifiScanPhase.PERMISSION_DENIED
    || phase === WifiScanPhase.UNSUPPORTED
    || phase === WifiScanPhase.ERROR;
}

export function presenceTrackCommands(spans: PresenceSpan[], now: number, windowMs: number,
  width: number, height: number, gone: boolean = false): string {
  const start: number = now - windowMs;
  const last: number = spans.length - 1;
  let commands: string = '';
  for (let index: number = 0; index <= last; index += 1) {
    const span: PresenceSpan = spans[index];
    // 与原版 `PresenceTrack` 同一判据：末段只要设备**还没走开**就算仍在场，
    // 即使它的 `end` 有值（那是上一轮走开时写的，回来时会被清掉）。
    const open: boolean = span.end === undefined || (!gone && index === last);
    const a: number = span.start > start ? span.start : start;
    const rawEnd: number = open ? now : (span.end === undefined ? now : span.end);
    const b: number = rawEnd < now ? rawEnd : now;
    if (b <= a) continue;
    const x1: number = ((a - start) / windowMs) * width;
    const x2: number = ((b - start) / windowMs) * width;
    const barWidth: number = Math.abs(x2 - x1) > 2 ? Math.abs(x2 - x1) : 2;
    const y1: number = height * 0.25;
    const y2: number = height * 0.75;
    const right: number = x1 + barWidth;
    commands += 'M' + x1.toFixed(1) + ' ' + y1.toFixed(1)
      + ' H' + right.toFixed(1) + ' V' + y2.toFixed(1) + ' H' + x1.toFixed(1) + ' Z ';
  }
  return commands;
}

/**
 * RSSI 样本序列 → sparkline 的 `Path` commands 串（信号轨迹视图用）。
 *
 * 纵轴口径与实时页的 RSSI 条一致：**-100 dBm ~ -35 dBm 映射到整框高度**，
 * 于是同一条轨迹在「条」和「折线」上读出来的强弱一致。
 *
 * **抽成模块级纯函数是为了可测**：`commands` 串拼错时 `Path` 会静默什么都不画，
 * 界面上只看到一片空白，很难定位。样本少于 2 个返回空串，由调用方给文字提示 ——
 * 不画一条假的直线，那会让人以为信号是平的。
 */
/** 折线图的纵轴范围（dBm）。 */
export class SparkRange {
  public minDb: number = -100;
  public maxDb: number = -35;
  constructor(minDb: number, maxDb: number) { this.minDb = minDb; this.maxDb = maxDb; }
}

/**
 * 按样本的实际极值取纵轴范围，供图表与图例共用。
 *
 * **为什么不能用固定范围**：原来固定映射 -100 ~ -35，
 * 而近距离 Wi-Fi AP 的读数常在 -25 ~ -43 ——
 * 高于 -35 的值全部被 clamp 到顶部，折线变成一条贴顶的直线，
 * 与旁边显示的数值完全对不上（实测反馈「图表和图例没有对应」）。
 *
 * 两端各留 3 dB 余量，并保证**最小跨度 10 dB** ——
 * 否则一台稳定的设备（±1 dB 抖动）会被放大成剧烈起伏，同样是误导。
 */
export function sparkRangeOf(samples: number[]): SparkRange {
  const valid: number[] = samples.filter((value: number): boolean => value < 0);
  if (valid.length === 0) return new SparkRange(-100, -35);
  let lowest: number = valid[0];
  let highest: number = valid[0];
  valid.forEach((value: number): void => {
    if (value < lowest) lowest = value;
    if (value > highest) highest = value;
  });
  let span: number = highest - lowest;
  if (span < 10) {
    const middle: number = (lowest + highest) / 2;
    lowest = middle - 5;
    highest = middle + 5;
    span = 10;
  }
  return new SparkRange(Math.floor(lowest - 3), Math.ceil(highest + 3));
}

export function sparklineCommands(samples: number[], width: number, height: number,
  range: SparkRange = new SparkRange(-100, -35)): string {
  const last: number = samples.length - 1;
  if (last < 1) return '';
  const span: number = range.maxDb - range.minDb > 0.001 ? range.maxDb - range.minDb : 1;
  let commands: string = '';
  for (let index: number = 0; index <= last; index += 1) {
    const x: number = (index / last) * width;
    const ratio: number = (samples[index] - range.minDb) / span;
    const clamped: number = ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
    const y: number = (1 - clamped) * height;
    commands += (index === 0 ? 'M' : 'L') + x.toFixed(1) + ' ' + y.toFixed(1) + ' ';
  }
  return commands;
}

/** 把签名 id 解析成展示名；找不到时回退为 id，便于发现目录漂移。 */
export function matchedSignatureNames(ids: string[], fleets: SignatureFleet[]): string[] {
  const names: string[] = [];
  ids.forEach((id: string): void => {
    const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
    const label: string = fleet === undefined ? id : fleet.name;
    if (names.indexOf(label) < 0) names.push(label);
  });
  return names;
}

/** 统计签名命中次数，按次数降序；用于 Debrief 的签名段。 */
export function signatureHitCounts(sightings: Sighting[], fleets: SignatureFleet[]): string[] {
  const counts: Map<string, number> = new Map<string, number>();
  sightings.forEach((sighting: Sighting): void => {
    sighting.signatureIds.forEach((id: string): void => {
      const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
      const label: string = fleet === undefined ? id : fleet.name;
      const current: number | undefined = counts.get(label);
      counts.set(label, current === undefined ? 1 : current + 1);
    });
  });
  const entries: string[] = [];
  counts.forEach((value: number, key: string): void => { entries.push(value.toString().padStart(4, ' ') + '  ' + key); });
  entries.sort((first: string, second: string): number => second.localeCompare(first));
  return entries;
}

export enum SignatureSortMode { NAME = 'name', CLASS = 'class' }

/** 目录排序：名称按显示名，类别按类别标签再按名称；两者都忽略大小写。 */
export function sortSignatureFleets(fleets: SignatureFleet[], mode: SignatureSortMode): SignatureFleet[] {
  const ordered: SignatureFleet[] = fleets.slice();
  if (mode === SignatureSortMode.CLASS) {
    ordered.sort((first: SignatureFleet, second: SignatureFleet): number => {
      const byClass: number = first.category.localeCompare(second.category);
      if (byClass !== 0) return byClass;
      return first.name.toLowerCase().localeCompare(second.name.toLowerCase());
    });
  } else {
    ordered.sort((first: SignatureFleet, second: SignatureFleet): number => first.name.toLowerCase().localeCompare(second.name.toLowerCase()));
  }
  return ordered;
}

function padTwo(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

export function formatClockTime(value: number): string {
  if (value <= 0) return '';
  const date: Date = new Date(value);
  return padTwo(date.getHours()) + ':' + padTwo(date.getMinutes()) + ':' + padTwo(date.getSeconds());
}

export function wifiFactValue(kind: RadioKind, value: number, suffix: string, notApplicable: string): string {
  return kind === RadioKind.WIFI ? value.toString() + suffix : notApplicable;
}

export function remainingAttemptSeconds(nextAttemptAt: number, now: number = Date.now()): number {
  if (nextAttemptAt <= now) return 0;
  return Math.ceil((nextAttemptAt - now) / 1000);
}

export function visibleSightingsAfterPause(paused: boolean, current: Array<Sighting>, latest: Array<Sighting>): Array<Sighting> {
  return paused ? current.slice() : latest.slice();
}
