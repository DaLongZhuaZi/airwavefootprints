import { FIELDWATCH_TAB_BAR_RESERVE } from '../../fieldwatch/ui/FieldwatchLayout';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import {
  NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay
} from 'ngf_framework';
import { ngfImmersiveContentTop, ngfText, resolveResourceString } from 'ngf_framework';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import {
  AntiTrackEvent, AntiTrackStats, EVIDENCE_MAX, evidenceBreakdown, FollowRisk, formatMeters, formatMinutes,
  SUSPECT_SCORE, TrackSuspect, TravelSummary, WATCH_SCORE
} from '../../fieldwatch/domain/FieldwatchAntiTracking';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/** 顶部沉浸底板的估算高度（与其它子页一致）。 */
const ANTITRACK_UNDERLAY_HEIGHT: number = 168;

/**
 * 反追踪（从工具箱拆出的独立子页面）。
 *
 * 内容与拆分前完全一致（总览、移动情况、可疑清单、已评估、事件日志），
 * 只是外层从「标签之一」变成「一整页」，不再共享工具箱的标签状态。
 */

@Component
export struct FieldwatchAntiTrackPage {
  /** 顶部安全区高度。 */
  topInset: number = 0;
  /** 底部安全区高度；与 FIELDWATCH_TAB_BAR_RESERVE 叠加。 */
  @Prop bottomInset: number = 0;
  /** 本页当前是否可见；不可见时定时刷新直接返回。 */
  @Prop @Watch('onPageVisibleChanged') pageVisible: boolean = true;
  /** 返回上一页（由根页面注入）。 */
  onClose: () => void = (): void => {};
  @State private tick: number = 0;
  private refreshTimer: number = -1;

  /** 切到本页时立刻刷一次（@Watch 回调不能是 private）。 */
  onPageVisibleChanged(): void {
    if (this.pageVisible) this.tick += 1;
  }

  aboutToAppear(): void {
    this.refreshTimer = setInterval((): void => {
      if (!this.pageVisible || !fieldwatchApplication.isAppForeground()) return;
      this.tick += 1;
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer < 0) return;
    clearInterval(this.refreshTimer);
    this.refreshTimer = -1;
  }

  /** 内容顶部避让：沉浸式标题栏会盖住内容，必须按底板高度 + 安全区让开。 */
  private contentTop(): number {
    return ngfImmersiveContentTop(ANTITRACK_UNDERLAY_HEIGHT, this.topInset);
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
            ANTITRACK_UNDERLAY_HEIGHT)
        })
        Column() {
          this.buildAntiTrackTab()
        }.width('100%').height('100%')
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_toolbox_tab_antitrack'),
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

  /** 一行指标（反追踪总览与移动情况都用它）。 */
  @Builder
  private buildMetricCell(label: ResourceStr, value: string) {
    Column({ space: 2 }) {
      Text(label).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text(value).fontSize(16).fontColor(FieldwatchPaletteHolder.get().text)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

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
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
  }

  /** 面板 1：总览计数。 */
  @Builder
  private buildAntiTrackOverview() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_evaluated'), this.antiStats().evaluated.toString())
        this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_suspect'), this.antiStats().suspect.toString())
        this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_watch'), this.antiStats().watch.toString())
        this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_top'), this.antiStats().topScore.toString())
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
      Text(fieldwatchText('app.string.fieldwatch_toolbox_at_travel')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (!fieldwatchApplication.antiTrackingHasGeo()) {
        Text(fieldwatchText('app.string.fieldwatch_toolbox_antitrack_nogeo')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().warn)
      } else {
        Row({ space: 10 }) {
          this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_path'), formatMeters(this.travel().pathMeters))
          this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_displacement'), formatMeters(this.travel().displacementMeters))
          this.buildMetricCell(fieldwatchText('app.string.fieldwatch_toolbox_at_ratio'), (Math.round(this.travel().pathRatio * 10) / 10).toString())
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
      Text(fieldwatchText('app.string.fieldwatch_toolbox_at_suspects')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.suspects().length === 0) {
        Text(fieldwatchText('app.string.fieldwatch_toolbox_antitrack_none')).fontSize(13)
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
    }.width('100%').padding(14).borderRadius(12).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
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
      Text(fieldwatchText('app.string.fieldwatch_toolbox_at_evaluated_list')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text(fieldwatchText('app.string.fieldwatch_toolbox_at_evaluated_note')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.evaluatedTop(), (suspect: TrackSuspect): void => {
        Row({ space: 8 }) {
          Text(suspect.label).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
          // 跨度用「分钟」，分数用「分」—— 两个单位必须区分开，
          // 否则一行里出现两个「0 分」，读起来像是重复了。
          Text(formatMinutes(suspect.evidence.spanMs) + ngfText('app.string.fw_tb_1041')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(suspect.evidence.score.toString() + ngfText('app.string.fw_tb_1043')).fontSize(13)
            .fontColor(suspect.risk === FollowRisk.NONE ? FieldwatchPaletteHolder.get().textDim
              : FieldwatchPaletteHolder.get().accent).width(46).textAlign(TextAlign.End)
        }.width('100%').padding(10)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
      }, (suspect: TrackSuspect): string => suspect.key)
    }.width('100%').padding(14).borderRadius(12).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 面板 5：判定记录。 */
  @Builder
  private buildAntiTrackLogPanel() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_toolbox_at_log')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.antiEvents().length === 0) {
        Text(fieldwatchText('app.string.fieldwatch_toolbox_at_no_log')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.antiEvents(), (event: AntiTrackEvent): void => {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle')).fontSize(13)
            .fontColor([FieldwatchPaletteHolder.get().warn])
          Text(event.label).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
          Text(event.score.toString() + ngfText('app.string.fw_tb_1043')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().warn)
          Text(this.clockOf(event.at)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%').padding(10)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
      }, (event: AntiTrackEvent): string => event.key + event.at.toString())
    }.width('100%').padding(14).borderRadius(12).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
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
