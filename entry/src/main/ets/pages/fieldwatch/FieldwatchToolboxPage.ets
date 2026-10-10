import { window } from '@kit.ArkUI';
import { resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { RadioKind, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import {
  BandSurvey, bandRange, ChannelArc, ChannelLoad, channelFrequency, loadLevel, occupiedWidthMhz,
  standardChannels, surveyBand, WifiBand, wifiBandOf, wifiChannelOf
} from '../../fieldwatch/domain/FieldwatchChannelAnalysis';
import {
  AntiTrackEvent, AntiTrackStats, EVIDENCE_MAX, evidenceBreakdown, FollowRisk, formatMeters, formatMinutes,
  SUSPECT_SCORE, TrackSuspect, TravelSummary, WATCH_SCORE
} from '../../fieldwatch/domain/FieldwatchAntiTracking';
import {
  HuntCue, HuntRecord, HuntSample, HuntSession, HuntStats, huntCueKey, huntRssiMeasured
} from '../../fieldwatch/domain/FieldwatchHunt';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';

/**
 * 横轴的一段连续频率区间。
 *
 * 段与段之间的**空档会被压扁**成固定宽度 ——
 * 这是 5G 可读性的关键：整段 745MHz 里通常只有两个簇（约 36-64 与 100-144），
 * 中间 200 多兆没有任何信号。线性铺满时两个簇各占一半宽，
 * 簇内十几个 AP 依旧挤在一起（实测反馈）。
 */
class ChartSegment {
  public low: number = 0;
  public high: number = 0;
  public xStart: number = 0;
  public xEnd: number = 0;
}

/** 空档压缩后的宽度（vp）。 */
const SEGMENT_GAP_PX: number = 30;

/** 图表纵向占比：用户要求「最少半个屏幕」。 */
const CHART_SCREEN_RATIO: number = 0.54;
/** 图表最少高度，避免小屏上被压扁。 */
const CHART_MIN_HEIGHT: number = 300;
/** 一条标签泳道的高度（含名称与 dBm 两行）。 */
const LABEL_ROW_H: number = 32;
/** 标签带与弧区之间的间隔。 */
const LABEL_BAND_GAP: number = 12;
/** 弧区最小高度：再挤也要能看出弧的高低差别。 */
const ARC_AREA_MIN: number = 190;
/** 同一泳道内两个标签之间至少留出的横向间隙。 */
const LABEL_H_GAP: number = 8;

/** 一个标签的排版槽位。 */
class LabelSlot {
  public index: number = 0;
  public x: number = 0;
  public width: number = 0;
  public lane: number = 0;
}
/**
 * 曲线配色。
 *
 * 12 个色相而不是「强/中/弱」三色：三色只能表达强弱，
 * 而相邻的弧是不是同一台设备、哪条压在哪条上，都需要**可分辨的颜色**。
 * 强弱改由**弧高**与标注里的 dBm 表达（本来就更准确）。
 */
const ARC_PALETTE: string[] = [
  '#4DD0E1', '#7C4DFF', '#FFD24A', '#3DFF9A', '#FF6B7A', '#64B5F6',
  '#FF9F43', '#C77DFF', '#00E5A0', '#FF7BC5', '#9AE66E', '#FFE066'
];

/**
 * 按 key 稳定取色。
 *
 * **必须稳定**：如果按「第几个」取色，列表顺序一变颜色就整体重排，
 * 图表每 2 秒重画一次，用户看到的是满屏颜色在闪。
 */
function arcColorOf(key: string): string {
  let hash: number = 0;
  for (let i: number = 0; i < key.length; i += 1) hash = (hash * 31 + key.charCodeAt(i)) % 1000003;
  return ARC_PALETTE[hash % ARC_PALETTE.length];
}

/** 图表里的字号。canvas 的 px 比 vp 小，需要放大才看得清（实测 10px 约 7vp）。 */
const AXIS_FONT: string = '22px sans-serif';
const LABEL_FONT: string = '24px sans-serif';

/**
 * 工具箱。
 *
 * 三件现场工具，用**标签页**切换（与其它标签页一致：自带大标题 + 描述）。
 *
 * 每一页各自持有 `Scroll`，而不是把整个页面塞进一个外层 `Scroll` ——
 * 嵌套滚动会让内层列表滚不动、外层抢手势（实测过）。
 */
@Component
export struct FieldwatchToolboxPage {
  topInset: number = 0;
  twoColumn: boolean = false;
  /** 对一个设备启动 Hunt（应用层会同时压栈到 Hunt 页）。 */
  onStartHunt: (deviceKey: string) => void = (deviceKey: string): void => {};
  /** 继续当前 Hunt（不重启会话，保留已有样本）。 */
  onOpenHunt: () => void = (): void => {};
  /** 当前工具页：0 信道分析 / 1 信号追踪 / 2 反追踪。 */
  @State private tool: number = 0;
  @State private band: WifiBand = WifiBand.BAND_24;
  @State private tick: number = 0;
  /** 图表高度：按屏幕高度算，保证「最少半个屏幕」。 */
  @State private chartHeight: number = CHART_MIN_HEIGHT;
  /** 可用视口宽度（vp）。画布宽度 = 视口 × 缩放。 */
  @State private viewportW: number = 360;
  /** 横向缩放倍数：双指捏合调整，0.6× ~ 6×。 */
  @State private zoomX: number = 1;
  /** 捏合开始时的倍数，用于按手势的 scale 增量计算。 */
  private zoomBase: number = 1;
  private refreshTimer: number = -1;
  private readonly chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly chartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private readonly huntTrendSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly huntTrendCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.huntTrendSettings);

  aboutToAppear(): void {
    this.readChartHeight();
    this.refreshTimer = setInterval((): void => {
      if (!fieldwatchApplication.isAppForeground()) return;
      this.refresh();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer < 0) return;
    clearInterval(this.refreshTimer);
    this.refreshTimer = -1;
  }

  private readChartHeight(): void {
    const uiContext = this.getUIContext();
    if (uiContext === undefined) return;
    window.getLastWindow(uiContext.getHostContext()).then((lastWindow: window.Window): void => {
      const rect = lastWindow.getWindowProperties().windowRect;
      const height: number = uiContext.px2vp(rect.height);
      this.chartHeight = Math.max(CHART_MIN_HEIGHT, Math.round(height * CHART_SCREEN_RATIO));
      // 视口宽度要扣掉两侧 16vp 的内边距，画布至少和它一样宽。
      this.viewportW = Math.max(280, uiContext.px2vp(rect.width) - 32);
    }).catch((): void => {});
  }

  private refresh(): void {
    // 外部深链进来的工具页（快捷方式 / 卡片 / `aa start --ps`）。
    const pendingTool: number = fieldwatchApplication.consumePendingTool();
    if (pendingTool >= 0 && pendingTool !== this.tool) this.tool = pendingTool;
    this.tick += 1;
    // 数据变了要重画：Canvas 不会因为状态变化自己刷新。
    setTimeout((): void => {
      this.drawChart();
      this.drawHuntTrend();
    }, 0);
  }

  private zoomText(): string {
    const template: string = this.text('app.string.fieldwatch_toolbox_zoom');
    return template.replace('%1', (Math.round(this.zoomX * 10) / 10).toString());
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  build() {
    Column() {
      this.buildTitle()
      this.buildToolTabs()
      if (this.tool === 0) this.buildChannelTab()
      else if (this.tool === 1) this.buildHuntTab()
      else this.buildAntiTrackTab()
    }.width('100%').height('100%')
  }

  /**
   * 顶部标题：**只有「工具箱」三个字，居中**，与其它标签页同一种头部。
   *
   * 原来下面还挂了一句说明，且整块左对齐 —— 与其它页面放在一起看就是「不齐」。
   * 说明本身也不是必要信息（三个标签页的名字已经说清了这页有什么）。
   */
  @Builder
  private buildTitle() {
    Column() {
      Text($r('app.string.fieldwatch_toolbox_title')).fontSize(26).fontWeight(FontWeight.Bold)
    }.width('100%').alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: this.topInset + 16, bottom: 10 })
  }

  /** 标签页条：等宽三段 + 选中下划线。 */
  @Builder
  private buildToolTabs() {
    Row() {
      this.buildToolTab($r('app.string.fieldwatch_toolbox_tab_channel'), 0)
      this.buildToolTab($r('app.string.fieldwatch_toolbox_tab_hunt'), 1)
      this.buildToolTab($r('app.string.fieldwatch_toolbox_tab_antitrack'), 2)
    }.width('100%').padding({ left: 8, right: 8 })
  }

  @Builder
  private buildToolTab(label: ResourceStr, index: number) {
    Column({ space: 6 }) {
      Text(label).fontSize(14).maxLines(1)
        .fontColor(index === this.tool ? FieldwatchPaletteHolder.get().accent
          : FieldwatchPaletteHolder.get().textDim)
        .fontWeight(index === this.tool ? FontWeight.Medium : FontWeight.Normal)
      // 下划线只在选中项出现，位置固定，切换时不跳动。
      Row().height(2).width('70%').borderRadius(1)
        .backgroundColor(index === this.tool ? FieldwatchPaletteHolder.get().accent : Color.Transparent)
    }.layoutWeight(1).height(42).justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (index === this.tool) return;
      this.tool = index;
      // 切到信道页时补画一次：Canvas 首次布局完成前尺寸为 0，onReady 之外要再画。
      if (index === 0) setTimeout((): void => { this.drawChart(); }, 0);
    })
  }

  // ── ① Wi-Fi 信道拥堵 ──
  @Builder
  private buildChannelTab() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          this.buildBandChip($r('app.string.fieldwatch_toolbox_band_24'), WifiBand.BAND_24)
          this.buildBandChip($r('app.string.fieldwatch_toolbox_band_5'), WifiBand.BAND_5)
          this.buildBandChip($r('app.string.fieldwatch_toolbox_band_6'), WifiBand.BAND_6)
        }.width('100%')
        // 图表：高度按「半屏」与「泳道需求」取大者；宽度 = 视口 × 缩放，
        // 放不下就横向滚动。双指捏合直接调缩放。
        Scroll() {
          Canvas(this.chartCtx)
            .width(this.viewportW * this.zoomX)
            .height(this.neededChartHeight())
            .backgroundColor(FieldwatchPaletteHolder.get().panel)
            .borderRadius(12)
            .onReady((): void => { this.drawChart(); })
            .gesture(
              PinchGesture({ fingers: 2 })
                .onActionStart((): void => { this.zoomBase = this.zoomX; })
                .onActionUpdate((event: GestureEvent): void => {
                  if (event.scale <= 0) return;
                  const next: number = Math.max(0.6, Math.min(6, this.zoomBase * event.scale));
                  if (Math.abs(next - this.zoomX) < 0.02) return;
                  this.zoomX = next;
                  // 画布宽度变了，重画一次才能按新宽度重排。
                  setTimeout((): void => { this.drawChart(); }, 0);
                })
            )
        }
        .width('100%').height(this.neededChartHeight())
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(this.zoomX > 1.02 ? BarState.Auto : BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
        Row({ space: 8 }) {
          Text(this.zoomText()).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
          Text($r('app.string.fieldwatch_toolbox_zoom_reset')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().accent)
            .onClick((): void => {
              this.zoomX = 1;
              setTimeout((): void => { this.drawChart(); }, 0);
            })
        }.width('100%')
        Text($r('app.string.fieldwatch_toolbox_chart_legend')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        this.buildChannelSummary()
        this.buildChannelRanking()
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 48 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildBandChip(label: ResourceStr, band: WifiBand) {
    Text(label).fontSize(13).layoutWeight(1).height(34).textAlign(TextAlign.Center)
      .borderRadius(17)
      .backgroundColor(this.band === band ? FieldwatchPaletteHolder.get().accent + '26' : FieldwatchPaletteHolder.get().panel)
      .fontColor(this.band === band ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().text)
      .onClick((): void => {
        this.band = band;
        this.refresh();
      })
  }

  /** 当前频段的全部 AP，转成待画的弧。 */
  private arcs(): ChannelArc[] {
    const bump: number = this.tick;
    const band: WifiBand = this.band;
    const result: ChannelArc[] = [];
    fieldwatchApplication.getState().sightings.forEach((item: Sighting): void => {
      if (item.kind !== RadioKind.WIFI) return;
      const frequency: number = item.facts.frequencyMhz;
      if (wifiBandOf(frequency) !== band) return;
      const width: number = occupiedWidthMhz(band, item.facts.channelWidth);
      const label: string = item.name.length > 0 ? item.name : this.text('app.string.fieldwatch_toolbox_hidden_ssid');
      result.push(new ChannelArc(item.key, label, frequency, width, item.rssi));
    });
    return bump >= 0 ? result : result;
  }

  private survey(): BandSurvey { return surveyBand(this.band, this.arcs()); }

  /**
   * 画布宽度：**信号越多越宽**，保证每个标签都有落脚点。
   *
   * 固定宽度时，2.4G 上 24 个 AP 的标签会挤成一团；
   * 5G 更糟 —— 十几个 AP 全落在 36/40/44 三个信道上，
   * 频率轴上它们几乎重合，标签只能一层层往上叠（实测反馈）。
   *
   * 每台设备给 130vp 的横向预算，超过视口就横向滚动。上限 4500 是为了
   * 极端情况（几十个 AP）下画布不至于大到拖慢绘制。
   */
  // 画布宽度固定为视口宽：拥挤由 `chartRange` 的自动缩放与 `neededChartHeight` 解决。

  /**
   * 图表的**实际横轴范围**：贴着「有信号的频率」而不是整段频段。
   *
   * **这是解决拥挤的关键，而不是把画布拉宽。**
   *
   * 拉宽画布只是把频率轴整体放大 —— 同信道的设备在频率轴上本来就重合，
   * 拉多宽都还是重合（实测：24 个 AP 全在信道 1-3，画布拉宽 6 倍后
   * 它们仍挤在同一小段里，只是弧被拉成了巨椭圆）。
   *
   * 而 5G 的典型情况是：整段 745MHz 里信号只占 60MHz 左右。
   * 把横轴缩到那 60MHz，信号之间才真正拉开距离。
   */
  private chartRangeLegacy(): number[] {
    const full: number[] = bandRange(this.band);
    const arcs: ChannelArc[] = this.arcs();
    if (arcs.length === 0) return full;
    let low: number = 1e9;
    let high: number = -1e9;
    arcs.forEach((arc: ChannelArc): void => {
      const half: number = arc.widthMhz / 2;
      if (arc.centerMhz - half < low) low = arc.centerMhz - half;
      if (arc.centerMhz + half > high) high = arc.centerMhz + half;
    });
    // 两侧各留 5% 余量，并夹在频段之内。
    const pad: number = Math.max((high - low) * 0.05, 4);
    low = Math.max(full[0], low - pad);
    high = Math.min(full[1], high + pad);
    // 只有一个 AP 时别把它放大到整屏：给一个 60MHz 的下限。
    const minSpan: number = 60;
    if (high - low < minSpan) {
      const mid: number = (high + low) / 2;
      low = Math.max(full[0], mid - minSpan / 2);
      high = Math.min(full[1], mid + minSpan / 2);
    }
    return [low, high];
  }

  /** 合并阈值：间隔小于它就算同一段（同簇）。2.4G 更密，阈值取小。 */
  private mergeGapMhz(): number {
    return this.band === WifiBand.BAND_24 ? 12 : 40;
  }

  /**
   * 把有信号的频率区间切成若干段，并算好每段的像素位置。
   *
   * 步骤：收集各 AP 的占用区间 -> 排序 -> 合并相近的 -> 按跨度分配宽度
   * （每段有保底宽度，避免单信道的小簇被压没）-> 空档给固定宽度。
   */
  private chartSegments(usableW: number, padLeft: number): ChartSegment[] {
    const full: number[] = bandRange(this.band);
    const arcs: ChannelArc[] = this.arcs();
    const spans: number[][] = [];
    arcs.forEach((arc: ChannelArc): void => {
      const half: number = arc.widthMhz / 2;
      spans.push([Math.max(full[0], arc.centerMhz - half), Math.min(full[1], arc.centerMhz + half)]);
    });
    spans.sort((a: number[], b: number[]): number => a[0] - b[0]);
    const merged: number[][] = [];
    const gapMhz: number = this.mergeGapMhz();
    spans.forEach((span: number[]): void => {
      const last: number[] | undefined = merged.length > 0 ? merged[merged.length - 1] : undefined;
      if (last !== undefined && span[0] <= last[1] + gapMhz) {
        if (span[1] > last[1]) last[1] = span[1];
      } else {
        merged.push([span[0], span[1]]);
      }
    });
    // 没有信号时退化成整段频段。
    if (merged.length === 0) merged.push([full[0], full[1]]);
    // 两端各留一点余量。
    merged[0][0] = Math.max(full[0], merged[0][0] - gapMhz / 2);
    merged[merged.length - 1][1] = Math.min(full[1], merged[merged.length - 1][1] + gapMhz / 2);
    // 像素分配：先按跨度分，再给保底，最后归一化。
    const gapTotal: number = SEGMENT_GAP_PX * (merged.length - 1);
    const available: number = Math.max(120, usableW - gapTotal);
    const spansTotal: number = merged.reduce((sum: number, span: number[]): number => sum + (span[1] - span[0]), 0);
    const floorPx: number = available / (merged.length * 1.8);
    const widths: number[] = merged.map((span: number[]): number =>
      Math.max(floorPx, (span[1] - span[0]) / Math.max(1, spansTotal) * available));
    const widthTotal: number = widths.reduce((sum: number, value: number): number => sum + value, 0);
    const result: ChartSegment[] = [];
    let cursor: number = padLeft;
    for (let i: number = 0; i < merged.length; i += 1) {
      const segment: ChartSegment = new ChartSegment();
      segment.low = merged[i][0];
      segment.high = merged[i][1];
      segment.xStart = cursor;
      segment.xEnd = cursor + widths[i] / Math.max(1, widthTotal) * available;
      cursor = segment.xEnd + SEGMENT_GAP_PX;
      result.push(segment);
    }
    return result;
  }

  /** 频率 -> 像素。落在空档里的频率夹到最近一段的边缘（不该出现，但要有兜底）。 */
  private xOfFrequency(segments: ChartSegment[], frequency: number): number {
    for (let i: number = 0; i < segments.length; i += 1) {
      const segment: ChartSegment = segments[i];
      if (frequency < segment.low) return segment.xStart;
      if (frequency <= segment.high) {
        const span: number = Math.max(0.001, segment.high - segment.low);
        return segment.xStart + (frequency - segment.low) / span * (segment.xEnd - segment.xStart);
      }
    }
    return segments[segments.length - 1].xEnd;
  }

  /** 该频率所属的段；找不到时返回最后一段。 */
  private segmentOf(segments: ChartSegment[], frequency: number): ChartSegment {
    for (let i: number = 0; i < segments.length; i += 1) {
      if (frequency >= segments[i].low && frequency <= segments[i].high) return segments[i];
    }
    return segments[segments.length - 1];
  }

  /** 该频率是否落在某一段内（用于决定要不要画刻度）。 */
  private inSegment(segments: ChartSegment[], frequency: number): boolean {
    for (let i: number = 0; i < segments.length; i += 1) {
      if (frequency >= segments[i].low && frequency <= segments[i].high) return true;
    }
    return false;
  }

  /**
   * 图表高度：**信号越多越高**，给标签留出足够泳道。
   *
   * 横向解决不了同信道拥挤，纵向可以：每多一条泳道就多一行能放下的标签。
   * 取「半屏」与「泳道需求」的较大者。
   */
  private neededChartHeight(): number {
    const count: number = this.arcs().length;
    // **高度必须按实际泳道数给足，否则标签就会被挤到重叠。**
    //
    // 曾经为了「让信道轴留在屏幕内」给高度设了上限，结果是泳道不够、
    // 标签互相压 —— 那是拿可读性换高度，方向错了。
    // 现在的取舍是：图表该多高就多高，页面滚动即可。
    const lanes: number = this.laneCount();
    const needed: number = 56 /*轴区*/ + 10 /*顶部*/ + lanes * LABEL_ROW_H + LABEL_BAND_GAP + ARC_AREA_MIN;
    return Math.max(Math.round(this.chartHeight), Math.round(needed));
  }

  @Builder
  private buildChannelSummary() {
    Column({ space: 4 }) {
      Text(this.summaryText()).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text)
      if (this.survey().totalAps > 0) {
        Text(this.recommendText()).fontSize(13)
          .fontColor(loadLevel(this.survey().recommendedScore) === 0
            ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().warn)
      } else {
        Text($r('app.string.fieldwatch_toolbox_channel_empty')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').padding(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildChannelRanking() {
    Column({ space: 6 }) {
      Text($r('app.string.fieldwatch_toolbox_channel_ranking')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      ForEach(this.ranking(), (load: ChannelLoad): void => {
        Row({ space: 8 }) {
          Text(this.channelLabel(load)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).width(96)
          Row() {
            Row().height(8).borderRadius(4).width(load.loadScore.toString() + '%')
              .backgroundColor(this.loadColor(load.loadScore))
          }.layoutWeight(1).height(8).borderRadius(4)
          .backgroundColor(FieldwatchPaletteHolder.get().outline)
          Text(load.loadScore.toString()).fontSize(12).width(34)
            .fontColor(FieldwatchPaletteHolder.get().textDim).textAlign(TextAlign.End)
        }.width('100%')
      }, (load: ChannelLoad): string => load.frequencyMhz.toString())
    }.width('100%').padding(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  private ranking(): ChannelLoad[] {
    const sorted: ChannelLoad[] = this.survey().loads.slice()
      .sort((a: ChannelLoad, b: ChannelLoad): number => b.loadScore - a.loadScore);
    return sorted.slice(0, 6);
  }

  private channelLabel(load: ChannelLoad): string {
    const prefix: string = this.text('app.string.fieldwatch_toolbox_channel_short');
    const channel: string = load.channel > 0 ? load.channel.toString() : load.frequencyMhz.toString();
    return prefix + ' ' + channel + ' · ' + load.overlappingAps.toString();
  }

  private loadColor(score: number): ResourceColor {
    const level: number = loadLevel(score);
    if (level === 2) return FieldwatchPaletteHolder.get().warn;
    if (level === 1) return FieldwatchPaletteHolder.get().accent;
    return FieldwatchPaletteHolder.get().outline;
  }

  private summaryText(): string {
    const survey: BandSurvey = this.survey();
    const template: string = this.text('app.string.fieldwatch_toolbox_channel_summary');
    const busiest: string = survey.busiestChannel > 0 ? survey.busiestChannel.toString() : '—';
    return template.replace('%1', survey.totalAps.toString())
      .replace('%2', busiest).replace('%3', survey.busiestScore.toString());
  }

  private recommendText(): string {
    const survey: BandSurvey = this.survey();
    const template: string = this.text('app.string.fieldwatch_toolbox_channel_recommend');
    const channel: string = survey.recommendedChannel > 0 ? survey.recommendedChannel.toString() : '—';
    return template.replace('%1', channel).replace('%2', survey.recommendedScore.toString());
  }

  // 强弱不再用颜色表达：颜色改用于区分设备（见 `arcColorOf`），
  // 强弱由弧高与标注里的 dBm 表达 —— 那本来就更准确。

  /**
   * 把当前频段的**全部信息**画进图表。
   *
   * 画五层，自下而上：
   *   ① 频率网格与频段标注；
   *   ② 拥堵包络（各采样点的功率叠加，填充）；
   *   ③ 每个 AP 一条**半椭圆**：横向半径 = 占用宽度的一半（几何真实，重叠可见），
   *      纵向半径 = 信号强度（否则 20MHz 的弧在整屏图上只有几十像素高，看不出强弱）；
   *   ④ 每个 AP 的 SSID 与 dBm，分泳道错开并连线到弧顶；
   *   ⑤ 频率轴与信道刻度。
   */
  private drawChart(): void {
    const ctx: CanvasRenderingContext2D = this.chartCtx;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0) return;
    ctx.clearRect(0, 0, width, height);
    const padLeft: number = 10;
    const padRight: number = 10;
    const usableW: number = width - padLeft - padRight;
    // 轴区要留够：字号放大后，「信道号 + MHz」两行需要约 56px。
    const axisY: number = height - 56;
    const topPad: number = 10;
    const usableH: number = axisY - topPad;
    const arcs: ChannelArc[] = this.arcs();
    // **分段横轴**：有信号的区间给足宽度，空档压扁（见 `chartSegments`）。
    const segments: ChartSegment[] = this.chartSegments(usableW, padLeft);
    const xOf = (frequency: number): number => this.xOfFrequency(segments, frequency);
    ctx.font = AXIS_FONT;
    ctx.textAlign = 'center';
    ctx.strokeStyle = FieldwatchPaletteHolder.get().outline;
    ctx.lineWidth = 1;
    // ① 频率网格：只画在段内，空档里画网格会让人以为那里有信号。
    const gridStep: number = 20;
    segments.forEach((segment: ChartSegment): void => {
      for (let f: number = Math.ceil(segment.low / gridStep) * gridStep; f <= segment.high; f += gridStep) {
        const x: number = xOf(f);
        ctx.globalAlpha = 0.35;
        ctx.beginPath();
        ctx.moveTo(x, topPad);
        ctx.lineTo(x, axisY);
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
      // 段底色：让「哪一段有信号」一眼可见。
      ctx.globalAlpha = 0.06;
      ctx.fillStyle = FieldwatchPaletteHolder.get().accent;
      ctx.fillRect(segment.xStart, topPad, segment.xEnd - segment.xStart, axisY - topPad);
      ctx.globalAlpha = 1;
    });
    // ② 空档标记：轴被压缩过必须**明确画出来**，否则图表在骗人。
    for (let i: number = 1; i < segments.length; i += 1) {
      const gapX: number = (segments[i - 1].xEnd + segments[i].xStart) / 2;
      const gapY: number = (topPad + axisY) / 2;
      ctx.strokeStyle = FieldwatchPaletteHolder.get().textDim;
      ctx.globalAlpha = 0.7;
      ctx.beginPath();
      ctx.moveTo(gapX - 6, gapY - 10);
      ctx.lineTo(gapX - 2, gapY);
      ctx.lineTo(gapX + 2, gapY - 10);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(gapX - 6, gapY + 10);
      ctx.lineTo(gapX - 2, gapY);
      ctx.lineTo(gapX + 2, gapY + 10);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = FieldwatchPaletteHolder.get().textDim;
      ctx.font = AXIS_FONT;
      ctx.fillText((segments[i].low - segments[i - 1].high).toFixed(0) + ' MHz', gapX, axisY + 32);
    }
    // 首尾标频率：中间的信道号已经说明位置了。
    ctx.fillStyle = FieldwatchPaletteHolder.get().textDim;
    ctx.textAlign = 'left';
    ctx.fillText(segments[0].low.toFixed(0) + ' MHz', segments[0].xStart, height - 6);
    ctx.textAlign = 'right';
    ctx.fillText(segments[segments.length - 1].high.toFixed(0) + ' MHz', segments[segments.length - 1].xEnd, height - 6);
    ctx.textAlign = 'center';
    // ② 拥堵包络：把每个采样点的拥堵度画成填充面积。
    const loads: ChannelLoad[] = this.survey().loads;
    if (loads.length >= 2) {
      ctx.beginPath();
      ctx.moveTo(xOf(loads[0].frequencyMhz), axisY);
      loads.forEach((load: ChannelLoad): void => {
        ctx.lineTo(xOf(load.frequencyMhz), axisY - load.loadScore / 100 * usableH * 0.42);
      });
      ctx.lineTo(xOf(loads[loads.length - 1].frequencyMhz), axisY);
      ctx.closePath();
      ctx.fillStyle = FieldwatchPaletteHolder.get().accent;
      ctx.globalAlpha = 0.16;
      ctx.fill();
      ctx.globalAlpha = 1;
    }
    // ③ 先排版：标签只占顶部一条**专用标签带**，弧区在其下方。
    //
    // 「避免重叠」由此退化成「给够泳道」—— 泳道数没有上限，
    // 图表高度再按它补足（见 `neededChartHeight`），于是**不可能重叠**。
    // 引线从标签一直拉到弧顶，**弧本身的高度不受影响**（这是用户要的语义：只拉高标签）。
    const sorted: ChannelArc[] = arcs.slice().sort((a: ChannelArc, b: ChannelArc): number => a.centerMhz - b.centerMhz);
    // 标签先整体去重，再逐条绘制（见 `uniqueLabels`）。
    const uniqueNames: string[] = this.uniqueLabels(sorted);
    const slots: LabelSlot[] = this.buildLabelSlots(width, padLeft, padRight, segments, sorted, uniqueNames);
    const lanes: number = this.packLanes(slots);
    const bandH: number = lanes * LABEL_ROW_H;
    const arcTop: number = topPad + bandH + LABEL_BAND_GAP;
    const arcArea: number = Math.max(60, axisY - arcTop);
    // ④ 半椭圆：高度只用**弧区**（标签带已经单独占好了）。
    const apexY: number[] = [];
    for (let i: number = 0; i < sorted.length; i += 1) {
      const arc: ChannelArc = sorted[i];
      const centerX: number = xOf(arc.centerMhz);
      // **横向半径必须用「本段」的比例尺**：分段后每段的 MHz->px 比例不同，
      // 用全局比例会把窄簇里的弧画得过大（或过小），重叠关系就失真了。
      const segment: ChartSegment = this.segmentOf(segments, arc.centerMhz);
      const localSpan: number = Math.max(0.001, segment.high - segment.low);
      const pxPerMhz: number = (segment.xEnd - segment.xStart) / localSpan;
      const radiusX: number = Math.max((arc.widthMhz / 2) * pxPerMhz, 6);
      // -95..-30 dBm 映射到 0..1。
      const ratio: number = Math.max(0, Math.min(1, (arc.rssi + 95) / 65));
      // 弧高占弧区的 18%..100%：太矮看不出强弱。
      const radiusY: number = arcArea * (0.18 + ratio * 0.82);
      apexY.push(axisY - radiusY);
      ctx.beginPath();
      ctx.ellipse(centerX, axisY, radiusX, radiusY, 0, Math.PI, 2 * Math.PI);
      // 每台设备一个稳定色相，便于分辨交叠的弧。
      ctx.strokeStyle = arcColorOf(arc.key);
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }
    // ⑤ 引线 + 标签。引线把标签和弧连起来，**拉多长都不影响弧的形状**。
    ctx.font = LABEL_FONT;
    for (let i: number = 0; i < slots.length; i += 1) {
      const slot: LabelSlot = slots[i];
      const rowTop: number = topPad + slot.lane * LABEL_ROW_H;
      const color: string = arcColorOf(sorted[slot.index].key);
      const anchorY: number = apexY[slot.index];
      // 引线：从弧顶竖直拉到标签行下方。
      ctx.beginPath();
      ctx.moveTo(slot.x, anchorY);
      ctx.lineTo(slot.x, rowTop + LABEL_ROW_H - 6);
      ctx.strokeStyle = color;
      ctx.globalAlpha = 0.55;
      ctx.lineWidth = 1.5;
      ctx.stroke();
      ctx.globalAlpha = 1;
      const textX: number = Math.max(4, Math.min(width - slot.width, slot.x - slot.width / 2 + 8));
      // 底衬：标签带本身是空的，但底衬让整块区域更整齐、也便于扫读。
      ctx.beginPath();
      ctx.roundRect(textX - 6, rowTop - 2, slot.width, LABEL_ROW_H - 4, 6);
      ctx.fillStyle = FieldwatchPaletteHolder.get().night;
      ctx.globalAlpha = 0.88;
      ctx.fill();
      ctx.globalAlpha = 1;
      // 左侧色条：与弧线同色，一眼对应。
      ctx.beginPath();
      ctx.roundRect(textX - 6, rowTop - 2, 3, LABEL_ROW_H - 4, 1.5);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.textAlign = 'left';
      ctx.fillStyle = FieldwatchPaletteHolder.get().text;
      ctx.fillText(uniqueNames[slot.index], textX, rowTop + 13);
      ctx.fillStyle = color;
      ctx.fillText(sorted[slot.index].rssi.toString() + ' dBm', textX, rowTop + 27);
      ctx.textAlign = 'center';
    }
    // （标签绘制已在 ⑤ 完成。）
    // ⑤ 频率轴与信道刻度。
    ctx.beginPath();
    ctx.moveTo(0, axisY);
    ctx.lineTo(width, axisY);
    ctx.strokeStyle = FieldwatchPaletteHolder.get().outline;
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.fillStyle = FieldwatchPaletteHolder.get().accent;
    // **每个分段各自算间距**：跨段共用 `lastTickX` 会让「下一段的第一个信道」
    // 因为与上一段末尾离得近而被抑制 —— 表现为某一段完全没有刻度。
    segments.forEach((segment: ChartSegment): void => {
      let lastTickX: number = -9999;
      standardChannels(this.band).forEach((channel: number): void => {
        const frequency: number = channelFrequency(this.band, channel);
        // 空档里的信道不画：那段没有信号，画刻度只会误导。
        if (frequency < segment.low || frequency > segment.high) return;
        const x: number = xOf(frequency);
        ctx.beginPath();
        ctx.moveTo(x, axisY);
        ctx.lineTo(x, axisY + 6);
        ctx.stroke();
        ctx.font = AXIS_FONT;
        ctx.fillStyle = FieldwatchPaletteHolder.get().accent;
        // **按实际像素间距**决定要不要写数字，而不是按奇偶。
        //
        // 原来写的是「信道多于 16 个就只标偶数」—— 而 5G 高频段
        // 149/153/157/161/165 **全是奇数**，整段刻度被丢光，
        // 右侧那一段看起来就像「没有信道」（实测反馈）。
        if (x - lastTickX < 46) return;
        lastTickX = x;
        ctx.fillText(channel.toString(), x, axisY + 32);
      });
    });
  }

  /**
   * 生成**互不重复**的标签。
   *
   * 同名的 AP 在真实环境里很常见（Mesh / 中继会广播同一个 SSID），
   * 截断之后不同 SSID 也可能长得一样（`ChinaNet-1045` 与 `ChinaNet-1042`
   * 都截成 `ChinaNet-104…`）—— 用户看到的就是「重复的标签」，
   * 而且**分不清哪个是哪个**。
   *
   * 处置：重名时补信道号；仍然重（同信道同名）再补设备键后四位。
   * 每一条都保持唯一，且补的信息本身是有意义的（信道/设备）。
   */
  private uniqueLabels(sorted: ChannelArc[]): string[] {
    const names: string[] = [];
    sorted.forEach((arc: ChannelArc): void => {
      // 先按字符数截断名称，再补后缀 —— 否则后缀会被截掉。
      names.push(arc.label.length > 12 ? arc.label.substring(0, 12) + '…' : arc.label);
    });
    const counts: Map<string, number> = new Map<string, number>();
    names.forEach((name: string): void => {
      const current: number | undefined = counts.get(name);
      counts.set(name, current === undefined ? 1 : current + 1);
    });
    const used: Map<string, number> = new Map<string, number>();
    const result: string[] = [];
    for (let i: number = 0; i < sorted.length; i += 1) {
      const name: string = names[i];
      const total: number | undefined = counts.get(name);
      if (total === undefined || total <= 1) { result.push(name); continue; }
      const channel: number = wifiChannelOf(sorted[i].centerMhz);
      const tag: string = channel > 0 ? channel.toString() : sorted[i].centerMhz.toFixed(0);
      let candidate: string = name + ' ·' + tag;
      const seen: number | undefined = used.get(candidate);
      if (seen !== undefined) {
        const key: string = sorted[i].key;
        const tail: string = key.length >= 4 ? key.substring(key.length - 4) : key;
        candidate = candidate + ' ·' + tail;
      }
      used.set(candidate, 1);
      result.push(candidate);
    }
    return result;
  }

  /**
   * 造出所有标签的排版槽位。
   *
   * **只依赖横向信息**（频率映射 + 文字实测宽度），与图表高度无关 ——
   * 所以可以在决定高度之前先算一遍，这就是「先排版、再定高、最后画」的可行性来源。
   */
  private buildLabelSlots(width: number, padLeft: number, padRight: number,
    segments: ChartSegment[], sorted: ChannelArc[], names: string[]): LabelSlot[] {
    this.chartCtx.font = LABEL_FONT;
    const slots: LabelSlot[] = [];
    for (let i: number = 0; i < sorted.length; i += 1) {
      const centerX: number = this.xOfFrequency(segments, sorted[i].centerMhz);
      // 同信道的设备在频率轴上几乎重合，给一点横向错开，
      // 否则它们的标签会永远叠在同一列上（5G 的 36/40/44 就是这种情形）。
      const jitter: number = (i % 3 - 1) * 16;
      const slot: LabelSlot = new LabelSlot();
      slot.index = i;
      slot.x = Math.max(padLeft, Math.min(width - padRight, centerX + jitter));
      slot.width = this.chartCtx.measureText(names[i]).width + 18;
      slots.push(slot);
    }
    return slots;
  }

  /**
   * 泳道打包：按 x 排序后逐个放进「第一条放得下的泳道」。
   *
   * **没有泳道上限** —— 放不下就新开一条。
   * 这正是「标签不重叠」的保证：上限一旦存在，超出的标签就只能叠在一起
   * （之前正是被 `Math.max(topPad+22, ...)` 夹到顶部互相压，实测反馈）。
   * 代价是图表会变高，而高度由 `neededChartHeight` 按泳道数补足。
   */
  private packLanes(slots: LabelSlot[]): number {
    const ordered: LabelSlot[] = slots.slice().sort((a: LabelSlot, b: LabelSlot): number => a.x - b.x);
    const laneEnd: number[] = [];
    ordered.forEach((slot: LabelSlot): void => {
      let lane: number = 0;
      while (lane < laneEnd.length && slot.x - slot.width / 2 < laneEnd[lane] + LABEL_H_GAP) lane += 1;
      if (lane >= laneEnd.length) laneEnd.push(-99999);
      laneEnd[lane] = slot.x + slot.width / 2;
      slot.lane = lane;
    });
    return Math.max(1, laneEnd.length);
  }

  /**
   * 当前数据需要多少条标签泳道。
   *
   * 宽度用 `viewportW * zoomX`（就是画布宽度），不读 `ctx.width` ——
   * 这个值在首帧布局时还没定下来，读它会得到 0，高度就算错了。
   */
  private laneCount(): number {
    const arcs: ChannelArc[] = this.arcs();
    if (arcs.length === 0) return 1;
    const width: number = Math.max(200, this.viewportW * this.zoomX);
    const padLeft: number = 10;
    const padRight: number = 10;
    const segments: ChartSegment[] = this.chartSegments(width - padLeft - padRight, padLeft);
    const sorted: ChannelArc[] = arcs.slice().sort((a: ChannelArc, b: ChannelArc): number => a.centerMhz - b.centerMhz);
    const names: string[] = this.uniqueLabels(sorted);
    return this.packLanes(this.buildLabelSlots(width, padLeft, padRight, segments, sorted, names));
  }

  private rssiOf(sorted: ChannelArc[], index: number): number {
    return index >= 0 && index < sorted.length ? sorted[index].rssi : -127;
  }

  // ── ② 信号追踪（Hunt）──
  @Builder
  private buildHuntTab() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 面板 1：当前会话 / 候选目标 ──
        if (this.huntSession() !== undefined) this.buildHuntLivePanel()
        else this.buildHuntPickerPanel()
        // ── 面板 2：历史汇总 ──
        this.buildHuntStatsPanel()
        // ── 面板 3：搜寻记录 ──
        this.buildHuntHistoryPanel()
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 48 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    // **必须顶对齐**：`Scroll` 默认会把内容垂直居中，
    // 结果是标签页条与内容之间空出一大段（实测截图）。
    .align(Alignment.TopStart)
  }

  /** 正在搜寻时的分析面板：状态、指标、趋势。 */
  @Builder
  private buildHuntLivePanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Circle().width(10).height(10).fill(this.huntCueColor())
        Text($r('app.string.fieldwatch_toolbox_hunt_active')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        Blank()
        Text(this.huntLabel()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
      }.width('100%')
      Text(this.huntCueText()).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.huntCueColor())
      // 指标网格：两列三行。
      Row({ space: 10 }) {
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_current'), this.huntRssiText(this.huntCurrent()))
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_peak'), this.huntRssiText(this.huntPeak()))
      }.width('100%')
      Row({ space: 10 }) {
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_range'), this.huntRange())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_average'), this.huntRssiText(this.huntAverage()))
      }.width('100%')
      Row({ space: 10 }) {
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_samples'), this.huntSamples())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_elapsed'), this.huntElapsed())
      }.width('100%')
      // 迷你趋势：与 Hunt 页同一种读法（横轴样本先后、参考线为峰值）。
      Canvas(this.huntTrendCtx)
        .width('100%').height(96)
        .backgroundColor(FieldwatchPaletteHolder.get().panel)
        .borderRadius(10)
        .onReady((): void => { this.drawHuntTrend(); })
      Button($r('app.string.fieldwatch_toolbox_hunt_resume')).height(40).width('100%')
        .onClick((): void => { this.onOpenHunt(); })
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildMetricCell(label: ResourceStr, value: string) {
    Column({ space: 2 }) {
      Text(label).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text(value).fontSize(16).fontColor(FieldwatchPaletteHolder.get().text)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  /** 未在搜寻时的候选面板。 */
  @Builder
  private buildHuntPickerPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_hunt_pick')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.huntCandidates(), (item: Sighting): void => {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(item.name.length > 0 ? item.name : item.key).fontSize(15)
              .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
            Text(this.kindLabel(item)).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          // 强度条：比一个数字更快看出谁最强。
          Row() {
            Row().height(6).borderRadius(3).width(this.rssiBarPercent(item.rssi).toString() + '%')
              .backgroundColor(FieldwatchPaletteHolder.get().accent)
          }.width(70).height(6).borderRadius(3)
          .backgroundColor(FieldwatchPaletteHolder.get().outline)
          Text(item.rssi.toString() + ' dBm').fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().accent).width(62).textAlign(TextAlign.End)
        }.width('100%').padding(12)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
        .onClick((): void => { this.onStartHunt(item.key); })
      }, (item: Sighting): string => item.key)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 历史汇总：次数、总时长、最佳峰值。 */
  @Builder
  private buildHuntStatsPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_hunt_stats')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Row({ space: 10 }) {
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_sessions'), this.huntStats().sessions.toString())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_total_time'), this.huntTotalTime())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_hunt_best_peak'), this.huntRssiText(this.huntStats().bestPeak))
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  /** 搜寻记录列表。 */
  @Builder
  private buildHuntHistoryPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_hunt_history')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.huntHistory().length === 0) {
        Text($r('app.string.fieldwatch_toolbox_hunt_no_history')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.huntHistory(), (record: HuntRecord): void => {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(record.label.length > 0 ? record.label : record.targetKey).fontSize(14)
              .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
            Text(this.durationText(record.durationMs())).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
          }.width('100%')
          Text(this.huntRecordDetail(record)).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%').padding(12)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
        .alignItems(HorizontalAlign.Start)
      }, (record: HuntRecord): string => record.targetKey + record.endedAt.toString())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private huntCurrent(): number {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? 127 : session.lastRssi;
  }

  private huntPeak(): number {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? -127 : session.peak();
  }

  private huntAverage(): number {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? 0 : session.average();
  }

  private huntSamples(): string {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? '0' : session.samples.length.toString();
  }

  private huntRange(): string {
    const session: HuntSession | undefined = this.huntSession();
    if (session === undefined) return '—';
    const range: string = session.rangeText();
    return range.length > 0 ? range + ' dBm' : '—';
  }

  private huntElapsed(): string {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? '—' : this.durationText(Date.now() - session.startedAt);
  }

  private huntRssiText(value: number): string {
    return value >= -127 && value <= 126 ? value.toString() + ' dBm' : '—';
  }

  /** 提示状态的文案键后缀与颜色。 */
  private huntCueText(): string {
    const session: HuntSession | undefined = this.huntSession();
    const cue: HuntCue = session === undefined ? HuntCue.GONE : fieldwatchApplication.huntCueNow();
    return this.text('app.string.fieldwatch_hunt_cue_' + huntCueKey(cue));
  }

  /** 返回 `string` 而不是 `ResourceColor`：canvas 的 `strokeStyle` 不收 ResourceColor。 */
  private huntCueColor(): string {
    const session: HuntSession | undefined = this.huntSession();
    const cue: HuntCue = session === undefined ? HuntCue.GONE : fieldwatchApplication.huntCueNow();
    if (cue === HuntCue.VERY_CLOSE || cue === HuntCue.CLOSER) return '#3DFF9A';
    if (cue === HuntCue.FURTHER) return '#FF6B7A';
    if (cue === HuntCue.SAME) return FieldwatchPaletteHolder.get().accent;
    return FieldwatchPaletteHolder.get().textDim;
  }

  private huntStats(): HuntStats {
    const bump: number = this.tick;
    const stats: HuntStats = fieldwatchApplication.huntStats();
    return bump >= 0 ? stats : stats;
  }

  private huntHistory(): HuntRecord[] {
    const bump: number = this.tick;
    const list: HuntRecord[] = fieldwatchApplication.getHuntHistory();
    return bump >= 0 ? list : list;
  }

  private huntTotalTime(): string { return this.durationText(this.huntStats().totalMs); }

  private huntRecordDetail(record: HuntRecord): string {
    const template: string = this.text('app.string.fieldwatch_toolbox_hunt_record_detail');
    return template.replace('%1', record.samples.toString())
      .replace('%2', this.huntRssiText(record.peak))
      .replace('%3', this.huntRssiText(Math.round(record.average)));
  }

  /** 毫秒 -> 「N 秒 / N 分 M 秒 / N 小时 M 分」。 */
  private durationText(ms: number): string {
    if (ms <= 0) return '0 秒';
    const totalSeconds: number = Math.round(ms / 1000);
    if (totalSeconds < 60) return totalSeconds.toString() + ' 秒';
    const minutes: number = Math.floor(totalSeconds / 60);
    if (minutes < 60) return minutes.toString() + ' 分 ' + (totalSeconds % 60).toString() + ' 秒';
    return Math.floor(minutes / 60).toString() + ' 小时 ' + (minutes % 60).toString() + ' 分';
  }

  /** RSSI -> 强度条百分比（-95..-30 dBm）。 */
  private rssiBarPercent(rssi: number): number {
    const ratio: number = (rssi + 95) / 65;
    return Math.round(Math.max(4, Math.min(100, ratio * 100)));
  }

  /** 工具箱里的迷你趋势图：与 Hunt 页同一套读法。 */
  private drawHuntTrend(): void {
    const ctx: CanvasRenderingContext2D = this.huntTrendCtx;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0) return;
    ctx.clearRect(0, 0, width, height);
    const session: HuntSession | undefined = this.huntSession();
    if (session === undefined || session.samples.length < 2) return;
    const samples: HuntSample[] = session.samples.filter((sample: HuntSample): boolean => huntRssiMeasured(sample.rssi));
    if (samples.length < 2) return;
    let low: number = 127;
    let high: number = -127;
    samples.forEach((sample: HuntSample): void => {
      if (sample.rssi < low) low = sample.rssi;
      if (sample.rssi > high) high = sample.rssi;
    });
    const top: number = high + 4;
    const span: number = Math.max(1, top - (low - 4));
    const pad: number = 8;
    const usableH: number = height - pad * 2;
    const xOf = (index: number): number => pad + index / (samples.length - 1) * (width - pad * 2);
    const yOf = (rssi: number): number => pad + (top - rssi) / span * usableH;
    ctx.beginPath();
    ctx.moveTo(pad, yOf(high));
    ctx.lineTo(width - pad, yOf(high));
    ctx.strokeStyle = FieldwatchPaletteHolder.get().outline;
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(xOf(0), yOf(samples[0].rssi));
    for (let i: number = 1; i < samples.length; i += 1) ctx.lineTo(xOf(i), yOf(samples[i].rssi));
    ctx.strokeStyle = this.huntCueColor();
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  private huntSession(): HuntSession | undefined {
    const bump: number = this.tick;
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    return bump >= 0 ? session : session;
  }

  private huntLabel(): string {
    const session: HuntSession | undefined = this.huntSession();
    return session === undefined ? '' : (session.label.length > 0 ? session.label : session.targetKey);
  }

  private huntCandidates(): Sighting[] {
    const bump: number = this.tick;
    const list: Sighting[] = fieldwatchApplication.getState().sightings.slice()
      .sort((a: Sighting, b: Sighting): number => b.rssi - a.rssi)
      .slice(0, 8);
    return bump >= 0 ? list : list;
  }

  private kindLabel(item: Sighting): string {
    if (item.kind === RadioKind.WIFI) return this.text('app.string.fieldwatch_toolbox_kind_wifi');
    if (item.kind === RadioKind.NEARLINK) return this.text('app.string.fieldwatch_toolbox_kind_nearlink');
    return this.text('app.string.fieldwatch_toolbox_kind_ble');
  }

  // ── ③ 反追踪安全 ──
  @Builder
  private buildAntiTrackTab() {
    Scroll() {
      Column({ space: 12 }) {
        this.buildAntiTrackOverview()
        this.buildTravelPanel()
        this.buildSuspectPanel()
        this.buildEvaluatedPanel()
        this.buildAntiTrackLogPanel()
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 48 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
  }

  /** 面板 1：总览计数。 */
  @Builder
  private buildAntiTrackOverview() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_evaluated'), this.antiStats().evaluated.toString())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_suspect'), this.antiStats().suspect.toString())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_watch'), this.antiStats().watch.toString())
        this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_top'), this.antiStats().topScore.toString())
      }.width('100%')
      // 判定线：告诉用户「多少分才会报」，否则数字没有参照。
      Text(this.thresholdText()).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  /** 面板 2：我自己的移动情况 —— 地理维度的输入，必须让用户看到。 */
  @Builder
  private buildTravelPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_at_travel')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (!fieldwatchApplication.antiTrackingHasGeo()) {
        Text($r('app.string.fieldwatch_toolbox_antitrack_nogeo')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().warn)
      } else {
        Row({ space: 10 }) {
          this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_path'), formatMeters(this.travel().pathMeters))
          this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_displacement'), formatMeters(this.travel().displacementMeters))
          this.buildMetricCell($r('app.string.fieldwatch_toolbox_at_ratio'), (Math.round(this.travel().pathRatio * 10) / 10).toString())
        }.width('100%')
        Text(this.travelNote()).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  /** 面板 3：疑似设备卡片（含三维度分解条）。 */
  @Builder
  private buildSuspectPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_at_suspects')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.suspects().length === 0) {
        Text($r('app.string.fieldwatch_toolbox_antitrack_none')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.suspects(), (suspect: TrackSuspect): void => {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r(suspect.risk === FollowRisk.SUSPECT ? 'sys.symbol.exclamationmark_triangle' : 'sys.symbol.eye'))
              .fontSize(16)
              .fontColor([suspect.risk === FollowRisk.SUSPECT
                ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().accent])
            Text(suspect.label).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
            Text(this.riskLabel(suspect.risk)).fontSize(12)
              .fontColor(suspect.risk === FollowRisk.SUSPECT
                ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().accent)
          }.width('100%')
          // 总分条 + 三维度分解：回答「为什么是这个分数」。
          this.buildScoreBar(this.text('app.string.fieldwatch_toolbox_at_score'), suspect.evidence.score, 100,
            suspect.risk === FollowRisk.SUSPECT ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().accent)
          this.buildScoreBar(this.text('app.string.fieldwatch_toolbox_at_dim_time'), this.breakdown(suspect)[0], EVIDENCE_MAX[0],
            FieldwatchPaletteHolder.get().accent)
          this.buildScoreBar(this.text('app.string.fieldwatch_toolbox_at_dim_geo'), this.breakdown(suspect)[1], EVIDENCE_MAX[1],
            '#7C4DFF')
          this.buildScoreBar(this.text('app.string.fieldwatch_toolbox_at_dim_signal'), this.breakdown(suspect)[2], EVIDENCE_MAX[2],
            '#3DFF9A')
          Text(this.spanText(suspect)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
          if (suspect.evidence.hasGeo) Text(this.pathText(suspect)).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(this.slopeText(suspect)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%').padding(12)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      }, (suspect: TrackSuspect): string => suspect.key)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildScoreBar(label: string, value: number, max: number, color: ResourceColor) {
    Row({ space: 8 }) {
      Text(label).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).width(52)
      Row() {
        Row().height(6).borderRadius(3).width(Math.round(value / max * 100).toString() + '%')
          .backgroundColor(color)
      }.layoutWeight(1).height(6).borderRadius(3).backgroundColor(FieldwatchPaletteHolder.get().outline)
      Text(value.toString() + '/' + max.toString()).fontSize(11).width(44)
        .fontColor(FieldwatchPaletteHolder.get().textDim).textAlign(TextAlign.End)
    }.width('100%')
  }

  /** 面板 4：全部参与评估的设备 —— 回答「为什么这台没报」。 */
  @Builder
  private buildEvaluatedPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_at_evaluated_list')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text($r('app.string.fieldwatch_toolbox_at_evaluated_note')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.evaluatedTop(), (suspect: TrackSuspect): void => {
        Row({ space: 8 }) {
          Text(suspect.label).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
          // 跨度用「分钟」，分数用「分」—— 两个单位必须区分开，
          // 否则一行里出现两个「0 分」，读起来像是重复了。
          Text(formatMinutes(suspect.evidence.spanMs) + ' 分钟').fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(suspect.evidence.score.toString() + ' 分').fontSize(13)
            .fontColor(suspect.risk === FollowRisk.NONE ? FieldwatchPaletteHolder.get().textDim
              : FieldwatchPaletteHolder.get().accent).width(46).textAlign(TextAlign.End)
        }.width('100%').padding(10)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
      }, (suspect: TrackSuspect): string => suspect.key)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 面板 5：判定记录。 */
  @Builder
  private buildAntiTrackLogPanel() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_toolbox_at_log')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.antiEvents().length === 0) {
        Text($r('app.string.fieldwatch_toolbox_at_no_log')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.antiEvents(), (event: AntiTrackEvent): void => {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(13)
            .fontColor([FieldwatchPaletteHolder.get().warn])
          Text(event.label).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
          Text(event.score.toString() + ' 分').fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().warn)
          Text(this.clockOf(event.at)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%').padding(10)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
      }, (event: AntiTrackEvent): string => event.key + event.at.toString())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private antiStats(): AntiTrackStats {
    const bump: number = this.tick;
    const stats: AntiTrackStats = fieldwatchApplication.antiTrackStats();
    return bump >= 0 ? stats : stats;
  }

  private travel(): TravelSummary {
    const bump: number = this.tick;
    const summary: TravelSummary = fieldwatchApplication.travelSummary();
    return bump >= 0 ? summary : summary;
  }

  private evaluatedTop(): TrackSuspect[] {
    const bump: number = this.tick;
    const list: TrackSuspect[] = fieldwatchApplication.antiTrackingAll().slice(0, 10);
    return bump >= 0 ? list : list;
  }

  private antiEvents(): AntiTrackEvent[] {
    const bump: number = this.tick;
    const list: AntiTrackEvent[] = fieldwatchApplication.antiTrackEvents();
    return bump >= 0 ? list : list;
  }

  private breakdown(suspect: TrackSuspect): number[] { return evidenceBreakdown(suspect.evidence); }

  private thresholdText(): string {
    const template: string = this.text('app.string.fieldwatch_toolbox_at_threshold');
    return template.replace('%1', WATCH_SCORE.toString()).replace('%2', SUSPECT_SCORE.toString());
  }

  private travelNote(): string {
    const template: string = this.text('app.string.fieldwatch_toolbox_at_travel_note');
    return template.replace('%1', this.travel().fixes.toString())
      .replace('%2', formatMinutes(this.travel().spanMs));
  }

  private clockOf(at: number): string {
    const date: Date = new Date(at);
    const hh: string = date.getHours().toString().padStart(2, '0');
    const mm: string = date.getMinutes().toString().padStart(2, '0');
    return hh + ':' + mm;
  }

  private suspects(): TrackSuspect[] {
    const bump: number = this.tick;
    const list: TrackSuspect[] = fieldwatchApplication.antiTrackingReport();
    return bump >= 0 ? list : list;
  }

  private riskLabel(risk: FollowRisk): string {
    return risk === FollowRisk.SUSPECT
      ? this.text('app.string.fieldwatch_toolbox_antitrack_risk_suspect')
      : this.text('app.string.fieldwatch_toolbox_antitrack_risk_watch');
  }

  private scoreText(suspect: TrackSuspect): string {
    return this.text('app.string.fieldwatch_toolbox_antitrack_score').replace('%1', suspect.evidence.score.toString());
  }

  private spanText(suspect: TrackSuspect): string {
    return this.text('app.string.fieldwatch_toolbox_antitrack_span')
      .replace('%1', formatMinutes(suspect.evidence.spanMs));
  }

  private pathText(suspect: TrackSuspect): string {
    return this.text('app.string.fieldwatch_toolbox_antitrack_path')
      .replace('%1', formatMeters(suspect.evidence.pathMeters))
      .replace('%2', formatMeters(suspect.evidence.displacementMeters))
      .replace('%3', (Math.round(suspect.evidence.pathRatio * 10) / 10).toString());
  }

  private slopeText(suspect: TrackSuspect): string {
    return this.text('app.string.fieldwatch_toolbox_antitrack_slope')
      .replace('%1', (Math.round(suspect.evidence.rssiSlopePerMin * 100) / 100).toString())
      .replace('%2', (Math.round(suspect.evidence.rssiResidualDb * 10) / 10).toString());
  }
}
