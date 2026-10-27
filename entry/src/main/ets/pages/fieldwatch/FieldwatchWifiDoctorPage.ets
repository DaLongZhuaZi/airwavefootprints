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
  ApDetailRow, apDetailRows, ApSnapshot, gradeOrder, roomTrends, RoomTrend, shouldPromptRetest
} from '../../fieldwatch/domain/FieldwatchWifiDoctorDetail';
import { WifiCurrentAp } from '../../fieldwatch/radio/FieldwatchWifiLink';

const DOCTOR_UNDERLAY_HEIGHT: number = 168;

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
    const recommended: number = fieldwatchApplication.wifiSurvey24().recommendedChannel;
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
        this.buildChannelCard()
        this.buildApDetail()
        this.buildRoomSection()
        this.buildRoomTrends()
        if (this.report !== undefined) this.buildReport()
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
    const survey: BandSurvey = fieldwatchApplication.wifiSurvey24();
    // 这里说的是**信道**调查，0 个 AP 才是真的没扫到；
    // 不能用「房间不够」的文案（那是另一件事，会在报告区单独说）。
    if (survey.totalAps === 0) return this.text('app.string.fieldwatch_wifi_doctor_no_aps');
    return this.text('app.string.fieldwatch_wifi_doctor_channel_summary')
      .replace('%1', survey.totalAps.toString())
      .replace('%2', survey.busiestChannel > 0 ? survey.busiestChannel.toString() : '—');
  }

  private recommendText(): string {
    const survey: BandSurvey = fieldwatchApplication.wifiSurvey24();
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
