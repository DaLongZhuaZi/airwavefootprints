import { window } from '@kit.ArkUI';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import {
  NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay
} from 'ngf_framework';
import { FIELDWATCH_TAB_BAR_RESERVE } from '../../fieldwatch/ui/FieldwatchLayout';
import { ngfImmersiveContentTop, resolveResourceString } from 'ngf_framework';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { RadioKind, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import {
  BandSurvey, bandRange, ChannelArc, ChannelLoad, channelFrequency, loadLevel, occupiedWidthMhz,
  standardChannels, surveyBand, WifiBand, wifiBandOf, wifiChannelOf
} from '../../fieldwatch/domain/FieldwatchChannelAnalysis';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/** 顶部沉浸底板的估算高度（与其它子页一致）。 */
const CHANNEL_UNDERLAY_HEIGHT: number = 168;

/**
 * Wi-Fi 信道分析（从工具箱拆出的独立子页面）。
 *
 * 拆出来的理由（改版设计第 3 节）：三件现场工具原本挤在一个页面的标签里，
 * 别的页面跳进来还得靠 pendingTool 指定第几个标签；拆成独立页后，
 * 每个工具各有标题与返回，跳转目标明确，也不再共享标签状态。
 *
 * 内容与拆分前完全一致（图表、缩放、泳道排版、推荐信道），
 * 只是外层从「标签之一」变成「一整页」。
 */

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

@Component
export struct FieldwatchChannelAnalysisPage {
  /** 顶部安全区高度。 */
  topInset: number = 0;
  /** 底部安全区高度；与 FIELDWATCH_TAB_BAR_RESERVE 叠加。 */
  @Prop bottomInset: number = 0;
  /** 本页当前是否可见；不可见时定时刷新直接返回。 */
  @Prop @Watch('onPageVisibleChanged') pageVisible: boolean = true;
  /** 返回上一页（由根页面注入）。 */
  onClose: () => void = (): void => {};
  /**
   * 初始频段（改版设计第 3 节：体检页跳进来要落在当前连接的频段上）。
   * 传 0 表示未指定，按 2.4G 起。
   */
  initialBand: number = 0;
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

  /** 切到本页时立刻刷一次，不等 2 秒定时器（@Watch 回调不能是 private）。 */
  onPageVisibleChanged(): void {
    if (this.pageVisible) this.refresh();
  }

  aboutToAppear(): void {
    // 初始频段：由调用方指定（体检页会带当前连接 AP 的频段）。
    if (this.initialBand === 2400) this.band = WifiBand.BAND_24;
    else if (this.initialBand === 5000) this.band = WifiBand.BAND_5;
    else if (this.initialBand === 6000) this.band = WifiBand.BAND_6;
    this.readChartHeight();
    this.refreshTimer = setInterval((): void => {
      if (!this.pageVisible || !fieldwatchApplication.isAppForeground()) return;
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
    this.tick += 1;
    // 数据变了要重画：Canvas 不会因为状态变化自己刷新。
    setTimeout((): void => {
      this.drawChart();
    }, 0);
  }

  private zoomText(): string {
    const template: string = this.text('app.string.fieldwatch_toolbox_zoom');
    return template.replace('%1', (Math.round(this.zoomX * 10) / 10).toString());
  }

  /** 内容顶部避让：沉浸式标题栏会盖住内容，必须按底板高度 + 安全区让开。 */
  private contentTop(): number {
    return ngfImmersiveContentTop(CHANNEL_UNDERLAY_HEIGHT, this.topInset);
  }

  private text(key: string): string {
    return fieldwatchText(key);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({
          spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
            CHANNEL_UNDERLAY_HEIGHT)
        })
        Column() {
          this.buildChannelTab()
        }.width('100%').height('100%')
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_toolbox_tab_channel'),
      '',
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .onBackPressed((): boolean => { this.onClose(); return true; })
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildChannelTab() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          this.buildBandChip(fieldwatchText('app.string.fieldwatch_toolbox_band_24'), WifiBand.BAND_24)
          this.buildBandChip(fieldwatchText('app.string.fieldwatch_toolbox_band_5'), WifiBand.BAND_5)
          this.buildBandChip(fieldwatchText('app.string.fieldwatch_toolbox_band_6'), WifiBand.BAND_6)
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
          Text(fieldwatchText('app.string.fieldwatch_toolbox_zoom_reset')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().accent)
            .onClick((): void => {
              this.zoomX = 1;
              setTimeout((): void => { this.drawChart(); }, 0);
            })
        }.width('100%')
        Text(fieldwatchText('app.string.fieldwatch_toolbox_chart_legend')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        this.buildChannelSummary()
        this.buildChannelRanking()
      }.width('100%').padding({ left: 16, right: 16, top: this.contentTop(), bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })
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
        Text(fieldwatchText('app.string.fieldwatch_toolbox_channel_empty')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').padding(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildChannelRanking() {
    Column({ space: 6 }) {
      Text(fieldwatchText('app.string.fieldwatch_toolbox_channel_ranking')).fontSize(14)
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


  // ── ② 反追踪安全 ──（原「信号追踪」内联面板已删除：追踪统一由独立「寻踪」页面承担）

  /** 指标格：标签 + 数值。信道页与反追踪页共用（删「信号追踪」时误删过一次，勿再删）。 */
  @Builder
  private buildMetricCell(label: ResourceStr, value: string) {
    Column({ space: 2 }) {
      Text(label).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text(value).fontSize(16).fontColor(FieldwatchPaletteHolder.get().text)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

}
