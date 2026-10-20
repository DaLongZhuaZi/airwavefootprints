import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { FIELDWATCH_SAFE_BOTTOM_GAP } from '../../fieldwatch/ui/FieldwatchLayout';
import {
  ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory,
  NGFImmersiveTopChromeUnderlay, resolveResourceString
} from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { HUNT_DIRECTION_SECTOR_COUNT, HuntCue, HuntDirectionMap, HuntSample, HuntSession, huntCueKey, huntCueLevel, huntDirectionSectorHeading, huntRssiMeasured, huntTickIntervalMs } from '../../fieldwatch/domain/FieldwatchHunt';
import { FieldwatchDirectionSensor, FieldwatchDirectionSensorListener } from '../../fieldwatch/platform/FieldwatchDirectionSensor';
import { ShakeSample, staticStrongSuspect } from '../../fieldwatch/domain/FieldwatchShakeConfirm';
import { FieldwatchHuntCombinedFeedback, IFieldwatchHuntFeedback } from '../../fieldwatch/platform/FieldwatchHuntFeedback';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';

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
  @State private directionAssist: boolean = true;
  @State private directionReady: boolean = false;
  @State private directionUnavailable: boolean = false;
  @State private directionHeading: number = 0;
  @State private directionDelta: number = 127;
  @State private directionCoverage: number = 0;
  private readonly feedback: IFieldwatchHuntFeedback = new FieldwatchHuntCombinedFeedback();
  private readonly directionSensor: FieldwatchDirectionSensor = new FieldwatchDirectionSensor();
  private readonly directionMap: HuntDirectionMap = new HuntDirectionMap();
  private readonly directionListener: FieldwatchDirectionSensorListener = new FieldwatchDirectionSensorListener(
    (heading: number): void => { this.onHeading(heading); },
    (rateRadiansPerSecond: number): void => { this.onRotation(rateRadiansPerSecond); },
    (message: string): void => { this.onSensorError(message); }
  );
  private readonly directionCanvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private readonly trendSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly trendCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.trendSettings);
  private refreshTimer: number = -1;
  /** 顶部安全区高度（由宿主传入；与设备详情页同一来源）。 */
  topInset: number = 0;
  /** 底部安全区高度（系统导航条）；与 FieldwatchLayout 的预留常量叠加使用。 */
  @Prop bottomInset: number = 0;
  /** 顶部玻璃底板高度；与设备详情页同值，见 `ngfImmersiveContentTop`。 */
  private readonly underlayHeight: number = 168;

  /** 内容首行应从哪里开始：底板覆盖带 + 顶部安全区（详见 `ngfImmersiveContentTop`）。 */
  private contentTop(): number { return ngfImmersiveContentTop(this.underlayHeight, this.topInset); }
  /** 信号又强又不动（可能是别的同款设备）—— 只提示。 */
  @State private staticSuspect: boolean = false;
  private tickTimer: number = -1;
  private directionSensorRunning: boolean = false;
  private rotationRate: number = 0;
  private lastDirectionSampleAt: number = 0;

  aboutToAppear(): void {
    this.directionAssist = fieldwatchApplication.getState().settings.huntDirectionAssist;
    this.syncDirectionSensor();
    this.tickSupported = this.feedback.hapticAvailable();
    this.refresh();
    this.refreshTimer = setInterval((): void => { this.refresh(); }, 1000);
    void this.feedback.prepare().then((): void => { this.soundSupported = this.feedback.soundAvailable(); });
  }

  aboutToDisappear(): void {
    this.directionSensor.stop();
    this.directionSensorRunning = false;
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    this.clearTick();
    this.feedback.release();
  }

  onHeading(heading: number): void {
    this.directionHeading = heading;
    const now: number = Date.now();
    if (this.rotationRate < 0.12 || now - this.lastDirectionSampleAt < 250) return;
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined || !huntRssiMeasured(session.lastRssi)) return;
    if (this.directionMap.addSample(heading, session.lastRssi)) {
      this.lastDirectionSampleAt = now;
      this.directionCoverage = this.directionMap.coverage();
      this.directionReady = this.directionMap.ready();
      this.directionDelta = this.directionMap.relativeDelta(heading);
      this.drawDirectionMap();
    }
  }

  onRotation(rateRadiansPerSecond: number): void { this.rotationRate = rateRadiansPerSecond; }

  onSensorError(_message: string): void { this.directionUnavailable = true; }

  private directionText(): string {
    if (this.directionUnavailable) return this.text('app.string.fieldwatch_hunt_direction_unavailable');
    if (!this.directionReady || this.directionDelta === 127) {
      const statusKey: string = this.directionCoverage >= HUNT_DIRECTION_SECTOR_COUNT
        ? 'app.string.fieldwatch_hunt_direction_weak_peak'
        : 'app.string.fieldwatch_hunt_direction_waiting';
      return this.text(statusKey);
    }
    if (Math.abs(this.directionDelta) <= 11.25) return this.text('app.string.fieldwatch_hunt_direction_align');
    const angle: string = Math.round(Math.abs(this.directionDelta)).toString();
    if (this.directionDelta < 0) return this.text('app.string.fieldwatch_hunt_direction_left').replace('%s', angle);
    return this.text('app.string.fieldwatch_hunt_direction_right').replace('%s', angle);
  }

  @Builder
  private buildDirectionMap() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_hunt_direction_title')).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text(this.directionAssist ? this.text('app.string.fieldwatch_hunt_direction_hint') : this.text('app.string.fieldwatch_hunt_direction_off'))
        .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      if (this.directionAssist) {
        Canvas(this.directionCanvas)
          .width('100%').height(150).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
          .onReady((): void => { this.drawDirectionMap(); })
        Text(this.directionText()).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(this.directionReady ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().text)
        Text(fieldwatchText('app.string.fieldwatch_hunt_direction_map_hint')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        // 原来是光秃秃一个「5/16」，看不出在说什么。
        Text(this.text('app.string.fieldwatch_hunt_direction_coverage')
          .replace('%d', this.directionCoverage.toString())
          .replace('16', HUNT_DIRECTION_SECTOR_COUNT.toString())).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
      .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
  }

  private drawDirectionMap(): void {
    const ctx: CanvasRenderingContext2D = this.directionCanvas;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0) return;
    ctx.clearRect(0, 0, width, height);
    const centerX: number = width / 2;
    const centerY: number = height / 2;
    const radius: number = Math.min(width, height) * 0.39;
    ctx.strokeStyle = FieldwatchPaletteHolder.get().outline;
    ctx.lineWidth = 1;
    for (let ring: number = 1; ring <= 3; ring += 1) {
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius * ring / 3, 0, Math.PI * 2);
      ctx.stroke();
    }
    for (let sector: number = 0; sector < 16; sector += 1) {
      const value: number = this.directionMap.sectorRssi(sector);
      if (value === 127) continue;
      const angle: number = (huntDirectionSectorHeading(sector) - 90) * Math.PI / 180;
      const strength: number = Math.max(0.12, Math.min(1, (value + 100) / 65));
      ctx.beginPath();
      ctx.moveTo(centerX, centerY);
      ctx.lineTo(centerX + Math.cos(angle) * radius * strength, centerY + Math.sin(angle) * radius * strength);
      ctx.strokeStyle = value >= -60 ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim;
      ctx.lineWidth = 5;
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.arc(centerX, centerY, 4, 0, Math.PI * 2);
    ctx.fillStyle = FieldwatchPaletteHolder.get().text;
    ctx.fill();
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private syncDirectionSensor(): void {
    const enabled: boolean = fieldwatchApplication.getState().settings.huntDirectionAssist;
    this.directionAssist = enabled;
    const shouldRun: boolean = enabled && fieldwatchApplication.isAppForeground();
    if (shouldRun && !this.directionSensorRunning && !this.directionUnavailable) {
      this.directionSensorRunning = this.directionSensor.start(this.directionListener);
      this.directionUnavailable = !this.directionSensorRunning;
    } else if (!shouldRun && this.directionSensorRunning) {
      this.directionSensor.stop();
      this.directionSensorRunning = false;
    }
    if (!enabled) this.directionUnavailable = false;
  }

  private refresh(): void {
    this.syncDirectionSensor();
    this.staticSuspect = this.judgeStaticSuspect();
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

  /**
   * 「很强但一直没变化」：文档要求只提示、不断言 —— 固定设备与口袋里的设备在这一项上一样，
   * 唯一能分开的是用户拿起来晃一晃。判据与常量都在领域层（`staticStrongSuspect`）。
   */
  private judgeStaticSuspect(): boolean {
    if (this.cue !== HuntCue.VERY_CLOSE) return false;
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) return false;
    const converted: ShakeSample[] = [];
    session.samples.forEach((sample: HuntSample): void => {
      converted.push(new ShakeSample(sample.rssi, sample.at));
    });
    return staticStrongSuspect(converted, Date.now());
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
      Text(fieldwatchText('app.string.fieldwatch_hunt_trend')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      Canvas(this.trendCtx)
        .width('100%').height(120)
        .backgroundColor(FieldwatchPaletteHolder.get().panel)
        .borderRadius(12)
        .onReady((): void => { this.drawTrend(); })
      // 折线本身没有说怎么读 —— 补一句大白话（用户要求：术语旁加必要说明）。
      Text(fieldwatchText('app.string.fieldwatch_hunt_trend_hint')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      // 「一直很强但完全不变」可能是别的同款设备：只提示，不断言。
      if (this.staticSuspect) {
        Text(fieldwatchText('app.string.fieldwatch_find_static_suspect')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
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
      // **与设备详情页同一套顶栏结构**：玻璃底板 + 滚动内容叠在同一 Stack 里。
      // 之前缺底板：内容从标题栏底下直接穿过，顶部区域看起来没有避让。
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({
          spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent, this.underlayHeight)
        })
        Scroll() {
        Column({ space: 14 }) {
        Text(fieldwatchText('app.string.fieldwatch_hunt_title')).fontSize(26).fontWeight(FontWeight.Bold)
        Text(this.targetLabel.length > 0 ? this.targetLabel : this.text('app.string.fieldwatch_hunt_none')).fontSize(15).fontColor(FieldwatchPaletteHolder.get().textDim)
        Stack() {
          Circle().width(220).height(220).fillOpacity(0.12).fill(this.cueColor()).scale({ x: this.pulseScale, y: this.pulseScale })
          Circle().width(160).height(160).fillOpacity(0.22).fill(this.cueColor())
          Column({ space: 4 }) {
            Text(this.text('app.string.fieldwatch_hunt_cue_' + huntCueKey(this.cue))).fontSize(22).fontWeight(FontWeight.Bold).fontColor(FieldwatchPaletteHolder.get().headerText)
            Text(this.rssiText(this.currentRssi)).fontSize(18).fontColor(this.cueColor())
          }
        }.width('100%').height(240)
        Text(this.text('app.string.fieldwatch_hunt_hint_' + huntCueKey(this.cue))).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text)
        this.buildMetric(fieldwatchText('app.string.fieldwatch_hunt_peak'), this.rssiText(this.peakRssi))
        this.buildMetric(fieldwatchText('app.string.fieldwatch_hunt_range'), this.rangeText.length > 0 ? this.rangeText + ' dBm' : this.text('app.string.fieldwatch_hunt_na'))
        this.buildMetric(fieldwatchText('app.string.fieldwatch_hunt_average'), this.sampleCount > 0 ? Math.round(this.averageRssi).toString() + ' dBm' : this.text('app.string.fieldwatch_hunt_na'))
        this.buildMetric(fieldwatchText('app.string.fieldwatch_hunt_samples'), this.sampleCount.toString())
      Text(fieldwatchText('app.string.fieldwatch_hunt_metric_hint')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
        this.buildTrend()
        this.buildDirectionMap()
        Row() {
          Text(fieldwatchText('app.string.fieldwatch_hunt_tick_beep')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.huntBeep })
            .enabled(this.soundSupported)
            .onChange((value: boolean): void => {
              this.huntBeep = value;
              fieldwatchApplication.setHuntBeep(value);
              if (value) void this.feedback.prepare();
            })
        }
        Row() {
          Text(fieldwatchText('app.string.fieldwatch_hunt_tick_vibrate')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.huntVibrate })
            .enabled(this.tickSupported)
            .onChange((value: boolean): void => {
              this.huntVibrate = value;
              fieldwatchApplication.setHuntVibrate(value);
            })
        }.width('100%')
        if (!this.tickSupported && !this.soundSupported) Text(fieldwatchText('app.string.fieldwatch_hunt_tick_unavailable')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
        Text(fieldwatchText('app.string.fieldwatch_hunt_disclaimer')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
        Button(fieldwatchText('app.string.fieldwatch_hunt_stop')).height(44).width('100%').onClick((): void => { this.stop(); })
        }.width('100%').padding({ left: 16, right: 16, top: this.contentTop(), bottom: this.bottomInset + FIELDWATCH_SAFE_BOTTOM_GAP })
      }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      fieldwatchText('app.string.fieldwatch_hunt_title'),
      fieldwatchText('app.string.fieldwatch_hunt_disclaimer'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    // 与设备详情页一致：只向顶部扩展（本页没有底部标签栏，向底部扩展没有意义，
    // 分屏/悬浮窗形态下反而会把按钮压到屏幕边缘外）。
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    // 工具箱中的「信号追踪」进入独立 Hunt 页时，整页跟随导航滑入；
    // 返回时淡出，避免内容瞬间替换造成页面跳变。
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ x: '24%' }))
        .animation({ duration: 260, curve: Curve.FastOutSlowIn }),
      TransitionEffect.opacity(0).animation({ duration: 170, curve: Curve.FastOutSlowIn })
    ))
  }

  @Builder
  private buildMetric(label: ResourceStr, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim).width(120)
      Text(value).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
    }.width('100%')
  }
}
