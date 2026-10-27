import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { BandSurvey } from '../../fieldwatch/domain/FieldwatchChannelAnalysis';
import {
  channelCrowded, DoctorLine, RoomCheck, RoomSignalGrade, ROOM_SCAN_DURATION_MS, WifiDoctorReport
} from '../../fieldwatch/domain/FieldwatchWifiDoctor';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';
import {
  ApDetailRow, apDetailRows, ApSnapshot, bandLabelKey, channelOfBand, gradeOrder, roomTrends, RoomTrend,
  shouldPromptRetest
} from '../../fieldwatch/domain/FieldwatchWifiDoctorDetail';
import { WifiCurrentAp } from '../../fieldwatch/radio/FieldwatchWifiLink';
import { WifiBand } from '../../fieldwatch/domain/FieldwatchChannelAnalysis';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';

const DOCTOR_UNDERLAY_HEIGHT: number = 168;

/** 「其他频段」折叠区的一行。 */
class OtherBandRow {
  public bandText: string = '';
  public summary: string = '';
  public hasData: boolean = false;
  constructor() {}
}

/**
 * `ApSnapshot` 的可实现类。
 *
 * ArkTS 不允许对象字面量直接当类型用，接口必须有显式实现类。
 * 放在模块级而不是方法内：每个方法调用都 new 一次匿名类没有意义。
 */
class ApSnapshotValue implements ApSnapshot {
  ssid: string = '';
  bssid: string = '';
  rssi: number = 0;
  band: number = 0;
}

/**
 * Wi-Fi 体检（P1-7）。
 *
 * 两段结构：
 *   ① **信道结论卡**：直接复用 Toolbox 的 `surveyBand` 结果（应用层 `wifiSurvey24`），
 *      与工具箱页给出同一个「最挤信道」，不会自相矛盾；
 *   ② **房间版**：逐房间静置 20 秒采样，落 RDB，最后点名最弱房间。
 *
 * 阈值全在 `FieldwatchWifiDoctor` 的常量里，页面不判断「多少算弱」。
 */
@Component
export struct FieldwatchWifiDoctorPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  /**
   * 打开信道分析页（改版设计第 3 节：带当前频段参数）。
   *
   * @param bandMhz 2400 / 5000 / 6000，表示进去后落在哪个频段。
   */
  onOpenChannelAnalysis: (bandMhz: number) => void = (bandMhz: number): void => {};
  /** 已测过的房间（新→旧）。 */
  @State private rooms: RoomCheck[] = [];
  /** 0 = 空闲，1 = 正在测某个房间。 */
  @State private phase: number = 0;
  @State private remainingSec: number = Math.floor(ROOM_SCAN_DURATION_MS / 1000);
  @State private roomName: string = '';
  @State private report: WifiDoctorReport | undefined = undefined;
  @State private tick: number = 0;
  /** 当前连接的 AP（P3-3：详情区用，来自现有 WifiLink 能力，不新增权限）。 */
  @State private currentAp: WifiCurrentAp | undefined = undefined;
  /** 各房间历次分档趋势（P3-3，与 RoomCheckRepository 对账）。 */
  @State private trends: RoomTrend[] = [];
  /** 是否有待提示的复测（上次给了改信道建议）。 */
  @State private retestPending: boolean = false;
  /** 建议的信道。 */
  @State private retestChannel: number = 0;
  /** 用户是否关掉了复测提醒。 */
  @State private retestDismissed: boolean = false;
  /** 「其他频段」折叠区是否展开（改版设计 5.1：默认收起）。 */
  @State private otherBandsOpen: boolean = false;
  private timer: number = -1;
  private sampleTimer: number = -1;

  aboutToAppear(): void {
    void this.reload();
  }

  aboutToDisappear(): void {
    this.stopTimers();
  }

  private stopTimers(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.sampleTimer >= 0) { clearInterval(this.sampleTimer); this.sampleTimer = -1; }
  }

  private async reload(): Promise<void> {
    this.rooms = await fieldwatchApplication.loadRoomChecks();
    this.report = fieldwatchApplication.wifiDoctorReport(this.rooms);
    // P3-3：当前 AP + 房间趋势 + 复测提醒，全部来自已有能力。
    this.currentAp = fieldwatchApplication.currentAp();
    this.trends = roomTrends(this.rooms);
    this.retestDismissed = fieldwatchApplication.retestPromptDismissed();
    this.retestChannel = fieldwatchApplication.retestSuggestedChannel();
    this.retestPending = shouldPromptRetest(
      fieldwatchApplication.retestPromptPending(), this.retestDismissed);
    // **给出建议之后**才记「待复测」：没有建议就没有可复测的东西，
    // 无条件标记会让每个用户每次进页都看到一条无意义的提醒。
    // 只在「本次确有建议、且提醒未被关闭」时写标记，避免覆盖用户的关闭偏好。
    const recommended: number = fieldwatchApplication.wifiSurveyCurrentBand().recommendedChannel;
    if (recommended > 0 && !this.retestDismissed && !this.retestPending) {
      fieldwatchApplication.markRetestPending(recommended);
    }
    this.tick += 1;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(DOCTOR_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  /** 开始一个房间的 20 秒静置采样。 */
  private startRoom(): void {
    if (this.phase === 1) return;
    fieldwatchApplication.beginRoomCheck();
    this.phase = 1;
    this.stopTimers();
    this.remainingSec = Math.floor(ROOM_SCAN_DURATION_MS / 1000);
    // 每秒采一帧：20 秒得到 20 个样本，足够算中位数，也不会把内存撑起来。
    this.sampleTimer = setInterval((): void => { fieldwatchApplication.sampleRoomCheck(); }, 1000);
    this.timer = setInterval((): void => {
      this.remainingSec -= 1;
      if (this.remainingSec <= 0) {
        this.stopTimers();
        void this.finishRoom();
      }
    }, 1000);
  }

  private async finishRoom(): Promise<void> {
    const label: string = this.roomName.trim();
    const room: RoomCheck | undefined = await fieldwatchApplication.finishRoomCheck(
      label.length > 0 ? label : this.text('app.string.fieldwatch_wifi_doctor_room_name'));
    this.phase = 0;
    if (room === undefined) {
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_wifi_doctor_empty'),
        duration: 2200
      });
      return;
    }
    this.roomName = '';
    await this.reload();
    this.getUIContext().getPromptAction().showToast({
      message: this.text('app.string.fieldwatch_wifi_doctor_room_done').replace('%1', room.label),
      duration: 2000
    });
  }

  /** 档位配色：强/够用用强调色，弱用琥珀，很差用告警色。**不只靠颜色**传达，旁边还有文字。 */
  private gradeColor(grade: RoomSignalGrade): string {
    if (grade === RoomSignalGrade.STRONG || grade === RoomSignalGrade.OK) return FieldwatchPaletteHolder.get().accent;
    if (grade === RoomSignalGrade.WEAK) return FieldwatchPaletteHolder.get().warn;
    if (grade === RoomSignalGrade.BAD) return FieldwatchPaletteHolder.get().signalRed;
    return FieldwatchPaletteHolder.get().textDim;
  }

  private gradeText(grade: RoomSignalGrade): string {
    if (grade === RoomSignalGrade.STRONG) return this.text('app.string.fieldwatch_wifi_doctor_grade_strong');
    if (grade === RoomSignalGrade.OK) return this.text('app.string.fieldwatch_wifi_doctor_grade_ok');
    if (grade === RoomSignalGrade.WEAK) return this.text('app.string.fieldwatch_wifi_doctor_grade_weak');
    if (grade === RoomSignalGrade.BAD) return this.text('app.string.fieldwatch_wifi_doctor_grade_bad');
    return this.text('app.string.fieldwatch_wifi_doctor_grade_unknown');
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.withShell) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              DOCTOR_UNDERLAY_HEIGHT)
          })
        }
        this.buildBody()
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_wifi_doctor_title'),
      $r('app.string.fieldwatch_wifi_doctor_subtitle'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .hideTitleBar(!this.withShell)
    .onBackPressed((): boolean => { this.onClose(); return true; })
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 14 }) {
        // P3-3：复测提醒放在最上面 —— 用户上次被建议改信道，进来第一眼就该看到。
        this.buildRetestPrompt()
        this.buildHeroCard()
        this.buildChannelCard()
        this.buildApDetail()
        this.buildRoomSection()
        this.buildRoomTrends()
        this.buildOtherBands()
        if (this.report !== undefined) this.buildReport()
        this.buildChannelEntry()
        FieldwatchButton({ label: $r('app.string.fieldwatch_wifi_doctor_export'),
          tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.exportReport(); } })
      }
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 复测提醒（P3-3 第 1 项）。
   *
   * 只在「上次给过改信道建议、且用户没关掉」时出现；进页看一眼就走题，
   * **没有定时器、没有通知**（文档明确不许做后台常驻提醒）。
   */
  @Builder
  private buildRetestPrompt() {
    if (this.retestPending) {
      Column({ space: 8 }) {
        Text($r('app.string.fieldwatch_wifi_retest_title')).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).width('100%')
        Text(this.text('app.string.fieldwatch_wifi_retest_hint')
          .replace('%1', this.retestChannel.toString()))
          .fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
        Row({ space: 8 }) {
          Column() {
            FieldwatchButton({ label: $r('app.string.fieldwatch_wifi_retest_ok'),
              tone: FieldwatchButtonTone.PRIMARY, compact: true, fillWidth: true,
              onTap: (): void => { this.acceptRetest(); } })
          }.layoutWeight(1)
          Column() {
            FieldwatchButton({ label: $r('app.string.fieldwatch_wifi_retest_dismiss'),
              tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: true,
              onTap: (): void => { this.dismissRetest(); } })
          }.layoutWeight(1)
        }.width('100%')
      }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
    }
  }

  private acceptRetest(): void {
    fieldwatchApplication.clearRetestPrompt();
    this.retestPending = false;
  }

  private dismissRetest(): void {
    fieldwatchApplication.dismissRetestPrompt();
    this.retestPending = false;
    this.retestDismissed = true;
  }

  /**
   * 当前 AP 详情（P3-3 第 1 项）。
   *
   * 数据全部来自现有 `WifiLink` 能力，**不新增权限**；
   * 信道由频段推算（系统不给信道，见 `channelOfBand`）。
   */
  @Builder
  private buildApDetail() {
    if (this.currentAp !== undefined) {
      Column({ space: 6 }) {
        Text($r('app.string.fieldwatch_wifi_detail_title')).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).width('100%')
        ForEach(this.apRows(), (row: ApDetailRow): void => {
          Row({ space: 8 }) {
            Text(this.text(row.labelKey)).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width(96)
            Text(this.apValueText(row)).fontSize(12)
              .fontColor(row.warn ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().text)
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
        }, (row: ApDetailRow): string => row.labelKey)
        // BSSID 随机化说明：不让用户把它当长期标识。
        Text($r('app.string.fieldwatch_wifi_detail_bssid_hint')).fontSize(10)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
    }
  }

  private apRows(): ApDetailRow[] {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined) return [];
    const snapshot: ApSnapshot = new ApSnapshotValue();
    snapshot.ssid = ap.ssid;
    snapshot.bssid = ap.bssid;
    snapshot.rssi = ap.rssi;
    snapshot.band = ap.band;
    return apDetailRows(snapshot);
  }

  /** 详情值：频段与信道行是资源键，需要翻成文案。 */
  private apValueText(row: ApDetailRow): string {
    if (row.labelKey.indexOf('band') > 0) return this.text(row.value);
    return row.value;
  }

  /**
   * 各房间历次分档趋势（P3-3 第 1 项）。
   *
   * 与 `RoomCheckRepository` 的记录对账：趋势直接由仓储读出的记录聚合，
   * 不另存一份，避免两处数字打架。
   */
  @Builder
  private buildRoomTrends() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_wifi_trend_title')).fontSize(15)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).width('100%')
      if (this.trends.length === 0) {
        Text($r('app.string.fieldwatch_wifi_trend_empty')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      } else {
        ForEach(this.trends, (trend: RoomTrend): void => {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(trend.label).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
              Text(this.text('app.string.fieldwatch_wifi_trend_times')
                .replace('%1', trend.count().toString()))
                .fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
            }.width('100%')
            Text(this.trendDetail(trend)).fontSize(11)
              .fontColor(trend.trend() > 0 ? FieldwatchPaletteHolder.get().accent
                : (trend.trend() < 0 ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().textDim))
              .width('100%')
          }.width('100%').padding({ top: 4, bottom: 4 })
        }, (trend: RoomTrend): string => trend.label)
      }
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 趋势说明：档位序列 + 相比首次的变化。 */
  private trendDetail(trend: RoomTrend): string {
    const parts: string[] = [];
    trend.grades.forEach((grade: RoomSignalGrade): void => {
      parts.push(this.text(this.gradeKey(grade)));
    });
    const path: string = parts.join(' → ');
    const delta: number = trend.trend();
    let verdict: string = this.text('app.string.fieldwatch_wifi_trend_same');
    if (delta > 0) verdict = this.text('app.string.fieldwatch_wifi_trend_better');
    else if (delta < 0) verdict = this.text('app.string.fieldwatch_wifi_trend_worse');
    return path + ' · ' + verdict;
  }

  private gradeKey(grade: RoomSignalGrade): string {
    if (grade === RoomSignalGrade.STRONG) return 'app.string.fieldwatch_wifi_grade_strong';
    if (grade === RoomSignalGrade.OK) return 'app.string.fieldwatch_wifi_grade_ok';
    if (grade === RoomSignalGrade.WEAK) return 'app.string.fieldwatch_wifi_grade_weak';
    if (grade === RoomSignalGrade.BAD) return 'app.string.fieldwatch_wifi_grade_bad';
    return 'app.string.fieldwatch_wifi_grade_unknown';
  }

  /**
   * 顶部 hero 卡（改版设计 5.2）：大字 SSID + 频段/信道/信号三项 + 一句话状态。
   *
   * 为什么单独一张卡：用户进体检页第一眼要回答「我现在连的是什么、好不好」，
   * 而原来的信道结论卡只谈「最挤信道」，答的不是这个问题。
   */
  @Builder
  private buildHeroCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.wifi')).fontSize(20)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text(this.heroSsid()).fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().headerText).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
      // **动态值必须写在 Text 节点里**，不能经 @Builder 字符串参数传：
      // 那样只在首帧求值一次，currentAp 异步读到后不会重绘（真机踩到过：三项全是 -）。
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text($r('app.string.fieldwatch_wifi_detail_band')).fontSize(10)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(this.heroBandText()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text($r('app.string.fieldwatch_wifi_detail_channel')).fontSize(10)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(this.heroChannelText()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text($r('app.string.fieldwatch_wifi_detail_rssi')).fontSize(10)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(this.heroSignalText()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Text(this.heroStatusText()).fontSize(13)
        .fontColor(this.heroStatusColor()).width('100%')
    }.width('100%').padding(16).borderRadius(16).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 当前频段的文案键（供结论句使用）。 */
  private bandKeyOfCurrent(): string {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    return bandLabelKey(ap === undefined ? 0 : ap.band);
  }

  private heroSsid(): string {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined || ap.ssid.length === 0) {
      return this.text('app.string.fieldwatch_wifi_hero_no_wifi');
    }
    return ap.ssid;
  }

  private heroBandText(): string {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined) return '-';
    return this.text(bandLabelKey(ap.band));
  }

  private heroChannelText(): string {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined) return '-';
    const channel: number = channelOfBand(ap.band);
    return channel > 0 ? channel.toString() : '-';
  }

  private heroSignalText(): string {
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined || ap.rssi >= 0) return '-';
    return ap.rssi.toString() + ' dBm';
  }

  /** 一句话状态：优先说「建议换信道」，否则按信号强弱给结论。 */
  private heroStatusText(): string {
    const survey: BandSurvey = fieldwatchApplication.wifiSurveyCurrentBand();
    if (survey.recommendedChannel > 0) {
      return this.text('app.string.fieldwatch_wifi_hero_status_change')
        .replace('%1', survey.recommendedChannel.toString());
    }
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined || ap.rssi >= 0) return this.text('app.string.fieldwatch_wifi_hero_no_wifi');
    if (ap.rssi >= -55) return this.text('app.string.fieldwatch_wifi_signal_strong');
    if (ap.rssi >= -70) return this.text('app.string.fieldwatch_wifi_signal_ok');
    return this.text('app.string.fieldwatch_wifi_signal_weak');
  }

  private heroStatusColor(): ResourceColor {
    const survey: BandSurvey = fieldwatchApplication.wifiSurveyCurrentBand();
    if (survey.recommendedChannel > 0) return FieldwatchPaletteHolder.get().warn;
    const ap: WifiCurrentAp | undefined = this.currentAp;
    if (ap === undefined || ap.rssi >= 0) return FieldwatchPaletteHolder.get().textDim;
    if (ap.rssi >= -70) return FieldwatchPaletteHolder.get().accent;
    return FieldwatchPaletteHolder.get().warn;
  }

  /**
   * 其他频段（改版设计 5.1）：默认收起，点开看对应频段结论。
   *
   * 为什么不并进主卡：主卡只回答「我现在连的这个频段挤不挤」，
   * 其他频段是参考信息，抢位置反而让主结论失焦。
   */
  @Builder
  private buildOtherBands() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text($r('app.string.fieldwatch_wifi_other_bands')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
        SymbolGlyph($r(this.otherBandsOpen ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
          .fontSize(13).fontColor([FieldwatchPaletteHolder.get().textDim])
      }.width('100%')
      .onClick((): void => {
        this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
          this.otherBandsOpen = !this.otherBandsOpen;
        });
      })
      if (this.otherBandsOpen) {
        ForEach(this.otherBandRows(), (row: OtherBandRow): void => {
          Row({ space: 8 }) {
            Text(row.bandText).fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).width(56)
            Text(row.summary).fontSize(12)
              .fontColor(row.hasData ? FieldwatchPaletteHolder.get().text
                : FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
          }.width('100%').padding({ top: 3, bottom: 3 })
        }, (row: OtherBandRow): string => row.bandText)
      }
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  private otherBandRows(): OtherBandRow[] {
    const current: WifiBand = fieldwatchApplication.currentApBand();
    const rows: OtherBandRow[] = [];
    const all: WifiBand[] = [WifiBand.BAND_24, WifiBand.BAND_5, WifiBand.BAND_6];
    all.forEach((band: WifiBand): void => {
      if (band === current) return;
      const survey: BandSurvey = fieldwatchApplication.wifiSurveyFor(band);
      const row: OtherBandRow = new OtherBandRow();
      row.bandText = this.text(bandLabelKey(band === WifiBand.BAND_24 ? 2437
        : (band === WifiBand.BAND_5 ? 5180 : 5955)));
      row.hasData = survey.totalAps > 0;
      if (!row.hasData) {
        row.summary = this.text('app.string.fieldwatch_wifi_band_empty');
      } else {
        row.summary = this.text('app.string.fieldwatch_wifi_doctor_channel_summary')
          .replace('%1', row.bandText)
          .replace('%2', survey.totalAps.toString())
          .replace('%3', survey.busiestChannel > 0 ? survey.busiestChannel.toString() : '—');
      }
      rows.push(row);
    });
    return rows;
  }

  /** 底部「去信道分析」入口：带当前频段参数，进去就落在同一频段。 */
  @Builder
  private buildChannelEntry() {
    FieldwatchButton({ label: $r('app.string.fieldwatch_wifi_goto_channel'),
      tone: FieldwatchButtonTone.OUTLINE,
      onTap: (): void => { this.onOpenChannelAnalysis(this.currentBandMhz()); } })
  }

  /** 当前频段换成信道分析页认的 MHz 标识（2400/5000/6000）。 */
  private currentBandMhz(): number {
    const band: WifiBand = fieldwatchApplication.currentApBand();
    if (band === WifiBand.BAND_5) return 5000;
    if (band === WifiBand.BAND_6) return 6000;
    return 2400;
  }

  /** 信道结论卡：复用 Toolbox 的 surveyBand，与工具箱页同一口径。 */
  @Builder
  private buildChannelCard() {
    Column({ space: 8 }) {
      if (this.tick >= 0) this.buildChannelText()
    }
    .width('100%').padding(14).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  @Builder
  private buildChannelText() {
    Column({ space: 6 }) {
      Text(this.channelSummary()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
      if (this.recommendText().length > 0) {
        Text(this.recommendText()).fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private channelSummary(): string {
    const survey: BandSurvey = fieldwatchApplication.wifiSurveyCurrentBand();
    // 这里说的是**信道**调查，0 个 AP 才是真的没扫到；
    // 不能用「房间不够」的文案（那是另一件事，会在报告区单独说）。
    // 空态必须按**频段**说话：该频段没数据时明说，绝不回落到别的频段的数据。
    if (survey.totalAps === 0) return this.text('app.string.fieldwatch_wifi_band_empty');
    // 频段必须写进文案：原模板写死「2.4G」，5G 下就成了「2.4G 上听到 27 个，最挤的信道是 52」。
    return this.text('app.string.fieldwatch_wifi_band_summary')
      .replace('%1', this.text(this.bandKeyOfCurrent()))
      .replace('%2', survey.totalAps.toString())
      .replace('%3', survey.busiestChannel > 0 ? survey.busiestChannel.toString() : '—');
  }

  private recommendText(): string {
    const survey: BandSurvey = fieldwatchApplication.wifiSurveyCurrentBand();
    if (survey.recommendedChannel <= 0) return '';
    return this.text('app.string.fieldwatch_wifi_doctor_recommend').replace('%1', survey.recommendedChannel.toString());
  }

  @Builder
  private buildRoomSection() {
    Column({ space: 10 }) {
      Text($r('app.string.fieldwatch_wifi_doctor_room_title')).fontSize(16)
        .fontColor(FieldwatchPaletteHolder.get().headerText)
      Text($r('app.string.fieldwatch_wifi_doctor_room_hint')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      if (this.phase === 1) {
        Text(this.text('app.string.fieldwatch_wifi_doctor_room_scanning').replace('%1', Math.max(0, this.remainingSec).toString()))
          .fontSize(20).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().accent)
      } else {
        TextInput({ placeholder: this.text('app.string.fieldwatch_wifi_doctor_room_name'), text: this.roomName })
          .onChange((value: string): void => { this.roomName = value; })
        FieldwatchButton({ label: $r('app.string.fieldwatch_wifi_doctor_room_add'),
          tone: FieldwatchButtonTone.PRIMARY, onTap: (): void => { this.startRoom(); } })
      }
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  @Builder
  private buildReport() {
    Column({ space: 8 }) {
      ForEach(this.roomRows(), (room: RoomCheck): void => {
        Row({ space: 8 }) {
          Text(room.label).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
          Text(this.gradeText(room.grade())).fontSize(13)
            .fontColor(this.gradeColor(room.grade()))
        }.width('100%')
      }, (room: RoomCheck): string => room.label + room.endedAt.toString())
      ForEach(this.doctorLineKeys(), (line: DoctorLine): void => {
        Text(this.lineText(line)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
      }, (line: DoctorLine): string => line.key)
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  private roomRows(): RoomCheck[] { return this.rooms; }

  private doctorLineKeys(): DoctorLine[] {
    const report: WifiDoctorReport | undefined = this.report;
    if (report === undefined) return [];
    return fieldwatchApplication.wifiDoctorLines(report);
  }

  private lineText(line: DoctorLine): string {
    const template: string = this.text(line.key);
    if (line.arg.length === 0) return template;
    // 档位这一行传的是枚举值（strong/ok/weak/bad），必须在这里翻译成中文，
    // 否则界面会直接显示 `信号档位：strong`（真机踩到过）。
    if (line.key === 'app.string.fieldwatch_wifi_doctor_grade') {
      return template.replace('%1', this.gradeText(line.arg as RoomSignalGrade));
    }
    return template.replace('%1', line.arg);
  }

  private exportReport(): void {
    const ok: boolean = fieldwatchApplication.exportWifiDoctor(this.rooms);
    if (ok) {
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_wifi_doctor_exported'),
        duration: 2200
      });
    }
  }
}
