import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { BandSurvey } from '../../fieldwatch/domain/FieldwatchChannelAnalysis';
import {
  channelCrowded, DoctorLine, RoomCheck, RoomSignalGrade, ROOM_SCAN_DURATION_MS, WifiDoctorReport
} from '../../fieldwatch/domain/FieldwatchWifiDoctor';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const DOCTOR_UNDERLAY_HEIGHT: number = 168;

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
        this.buildChannelCard()
        this.buildRoomSection()
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
