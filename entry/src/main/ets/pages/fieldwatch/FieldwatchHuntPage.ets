import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { NGFHdsTitleBarOptionsFactory, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { HuntCue, HuntSample, HuntSession, huntCueKey, huntCueLevel, huntRssiMeasured, huntTickIntervalMs } from '../../fieldwatch/domain/FieldwatchHunt';
import { FieldwatchHuntCombinedFeedback, IFieldwatchHuntFeedback } from '../../fieldwatch/platform/FieldwatchHuntFeedback';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';

@Component
export struct FieldwatchHuntPage {
  onClose: () => void = (): void => {};
  @State private targetLabel: string = '';
  @State private cue: HuntCue = HuntCue.WAITING;
  @State private currentRssi: number = 127;
  @State private peakRssi: number = -127;
  @State private rangeText: string = '';
  @State private sampleCount: number = 0;
  @State private averageRssi: number = 0;
  @State private pulseScale: number = 1;
  /**
   * Hunt 的 geiger tick 开关。
   *
   * **改为读持久化设置**（§12.3「Hunt 声音反馈开关」）：
   * 此前是页面局部 `@State = true`，进一次页面就重置，用户根本关不掉；
   * 而且默认是开的，与原版 `huntBeep/huntVibrate` 默认 false 相反。
   * 现在拆成「声音」与「触感」两个独立开关，与原版一致（可只振动不出声）。
   */
  @State private huntBeep: boolean = false;
  @State private huntVibrate: boolean = false;
  @State private tickSupported: boolean = false;
  @State private soundSupported: boolean = false;
  private readonly feedback: IFieldwatchHuntFeedback = new FieldwatchHuntCombinedFeedback();
  private readonly trendSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly trendCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.trendSettings);
  private refreshTimer: number = -1;
  private tickTimer: number = -1;

  aboutToAppear(): void {
    this.tickSupported = this.feedback.hapticAvailable();
    this.refresh();
    this.refreshTimer = setInterval((): void => { this.refresh(); }, 1000);
    void this.feedback.prepare().then((): void => { this.soundSupported = this.feedback.soundAvailable(); });
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    this.clearTick();
    this.feedback.release();
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private refresh(): void {
    // 每秒把持久化设置同步进来：在设置页改完，回到 Hunt 页最多 1 秒生效。
    const settings = fieldwatchApplication.getState().settings;
    this.huntBeep = settings.huntBeep;
    this.huntVibrate = settings.huntVibrate;
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) {
      this.targetLabel = '';
      this.cue = HuntCue.GONE;
      return;
    }
    this.targetLabel = session.label.length > 0 ? session.label : session.targetKey;
    this.cue = fieldwatchApplication.huntCueNow();
    this.currentRssi = session.lastRssi;
    this.peakRssi = session.peak();
    this.rangeText = session.rangeText();
    this.sampleCount = session.samples.length;
    this.averageRssi = session.average();
    // 趋势图不会因为状态变化自己重画，每秒主动重绘一次。
    setTimeout((): void => { this.drawTrend(); }, 0);
    this.armTick();
  }

  private clearTick(): void {
    if (this.tickTimer >= 0) { clearTimeout(this.tickTimer); this.tickTimer = -1; }
  }

  /** 按当前响度重新安排下一次节拍；安静或消失时不排程。 */
  private armTick(): void {
    this.clearTick();
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) return;
    const interval: number = huntTickIntervalMs(session.lastRssi, this.cue);
    if (interval < 0) return;
    this.tickTimer = setTimeout((): void => { this.fireTick(); }, interval);
  }

  private fireTick(): void {
    this.tickTimer = -1;
    if ((this.huntBeep || this.huntVibrate) && this.tickSupported) this.feedback.tick(22);
    this.getUIContext().animateTo({ duration: 80, curve: Curve.EaseOut }, (): void => { this.pulseScale = 1.28; });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseIn }, (): void => { this.pulseScale = 1; });
    }, 80);
    this.armTick();
  }

  private stop(): void {
    fieldwatchApplication.stopHunt();
    this.clearTick();
    this.feedback.release();
    this.onClose();
  }

  private cueColor(): string {
    const level: number = huntCueLevel(this.cue);
    if (level >= 3) return FieldwatchPaletteHolder.get().huntVeryClose;
    if (level === 2) return FieldwatchPaletteHolder.get().huntCloser;
    if (level === 1) return FieldwatchPaletteHolder.get().warn;
    return FieldwatchPaletteHolder.get().huntFar;
  }

  /**
   * 最近样本与信号趋势。
   *
   * 原版 §6 要求「显示当前 RSSI、峰值 RSSI、最近样本和信号趋势」，
   * 此前只显示了**样本条数**，样本本身与趋势都看不到 ——
   * 用户只能看到一个数字在跳，判断不了「是在靠近还是只是噪声」。
   *
   * 用折线而不是柱状：趋势是**连续量**，折线的斜率本身就是答案。
   */
  @Builder
  private buildTrend() {
    Column({ space: 6 }) {
      Text($r('app.string.fieldwatch_hunt_trend')).fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Canvas(this.trendCtx)
        .width('100%').height(120)
        .backgroundColor(FieldwatchPaletteHolder.get().panel)
        .borderRadius(12)
        .onReady((): void => { this.drawTrend(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 画折线：横轴是样本序号（时间等距），纵轴是 RSSI，另画一条峰值参考线。 */
  private drawTrend(): void {
    const ctx: CanvasRenderingContext2D = this.trendCtx;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0) return;
    ctx.clearRect(0, 0, width, height);
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined || session.samples.length < 2) return;
    const samples: HuntSample[] = session.samples.filter((sample: HuntSample): boolean => huntRssiMeasured(sample.rssi));
    if (samples.length < 2) return;
    // 纵轴范围：取样本的实际区间，上下各留 4dB，避免满量程时折线贴边。
    let low: number = 127;
    let high: number = -127;
    samples.forEach((sample: HuntSample): void => {
      if (sample.rssi < low) low = sample.rssi;
      if (sample.rssi > high) high = sample.rssi;
    });
    const top: number = high + 4;
    const bottom: number = low - 4;
    const span: number = Math.max(1, top - bottom);
    const pad: number = 6;
    const usableH: number = height - pad * 2;
    const xOf = (index: number): number => pad + index / (samples.length - 1) * (width - pad * 2);
    const yOf = (rssi: number): number => pad + (top - rssi) / span * usableH;
    // 峰值参考线：一眼看出「离最好状态还差多少」。
    ctx.beginPath();
    ctx.moveTo(pad, yOf(high));
    ctx.lineTo(width - pad, yOf(high));
    ctx.strokeStyle = FieldwatchPaletteHolder.get().outline;
    ctx.lineWidth = 1;
    ctx.stroke();
    // 折线
    ctx.beginPath();
    ctx.moveTo(xOf(0), yOf(samples[0].rssi));
    for (let i: number = 1; i < samples.length; i += 1) ctx.lineTo(xOf(i), yOf(samples[i].rssi));
    ctx.strokeStyle = this.cueColor();
    ctx.lineWidth = 2;
    ctx.stroke();
    // 最近一点标出来：这是「当前响度」的视觉锚点。
    ctx.beginPath();
    ctx.arc(xOf(samples.length - 1), yOf(samples[samples.length - 1].rssi), 3, 0, 2 * Math.PI);
    ctx.fillStyle = this.cueColor();
    ctx.fill();
  }

  private rssiText(value: number): string {
    return value >= -127 && value <= 126 ? value.toString() + ' dBm' : this.text('app.string.fieldwatch_hunt_na');
  }

  build() {
    HdsNavDestination() {
      Scroll() {
        Column({ space: 14 }) {
        Text($r('app.string.fieldwatch_hunt_title')).fontSize(26).fontWeight(FontWeight.Bold)
        Text(this.targetLabel.length > 0 ? this.targetLabel : this.text('app.string.fieldwatch_hunt_none')).fontSize(15).fontColor($r('app.color.text_secondary'))
        Stack() {
          Circle().width(220).height(220).fillOpacity(0.12).fill(this.cueColor()).scale({ x: this.pulseScale, y: this.pulseScale })
          Circle().width(160).height(160).fillOpacity(0.22).fill(this.cueColor())
          Column({ space: 4 }) {
            Text(this.text('app.string.fieldwatch_hunt_cue_' + huntCueKey(this.cue))).fontSize(22).fontWeight(FontWeight.Bold).fontColor(FieldwatchPaletteHolder.get().headerText)
            Text(this.rssiText(this.currentRssi)).fontSize(18).fontColor(this.cueColor())
          }
        }.width('100%').height(240)
        Text(this.text('app.string.fieldwatch_hunt_hint_' + huntCueKey(this.cue))).fontSize(14).fontColor($r('app.color.text_primary'))
        this.buildMetric($r('app.string.fieldwatch_hunt_peak'), this.rssiText(this.peakRssi))
        this.buildMetric($r('app.string.fieldwatch_hunt_range'), this.rangeText.length > 0 ? this.rangeText + ' dBm' : this.text('app.string.fieldwatch_hunt_na'))
        this.buildMetric($r('app.string.fieldwatch_hunt_average'), this.sampleCount > 0 ? Math.round(this.averageRssi).toString() + ' dBm' : this.text('app.string.fieldwatch_hunt_na'))
        this.buildMetric($r('app.string.fieldwatch_hunt_samples'), this.sampleCount.toString())
        this.buildTrend()
        Row() {
          Text($r('app.string.fieldwatch_hunt_tick_beep')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.huntBeep })
            .enabled(this.soundSupported)
            .onChange((value: boolean): void => {
              this.huntBeep = value;
              fieldwatchApplication.setHuntBeep(value);
              if (value) void this.feedback.prepare();
            })
        }
        Row() {
          Text($r('app.string.fieldwatch_hunt_tick_vibrate')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.huntVibrate })
            .enabled(this.tickSupported)
            .onChange((value: boolean): void => {
              this.huntVibrate = value;
              fieldwatchApplication.setHuntVibrate(value);
            })
        }.width('100%')
        if (!this.tickSupported && !this.soundSupported) Text($r('app.string.fieldwatch_hunt_tick_unavailable')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Text($r('app.string.fieldwatch_hunt_disclaimer')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Button($r('app.string.fieldwatch_hunt_stop')).height(44).width('100%').onClick((): void => { this.stop(); })
        }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 48 })
      }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_hunt_title'),
      $r('app.string.fieldwatch_hunt_disclaimer'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildMetric(label: ResourceStr, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(120)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
    }.width('100%')
  }
}
