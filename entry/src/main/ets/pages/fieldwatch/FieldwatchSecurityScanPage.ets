import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { RadioKind, SignatureClass, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import { SECURITY_SCAN_DURATION_MS, SecurityClassCount, SecuritySummary, summaryHeadlineKey } from '../../fieldwatch/domain/FieldwatchSecurityScan';
import { ShareCardContent } from '../../fieldwatch/platform/FieldwatchShareCard';
import {
  capabilityBoundaryKeys, SecurityEvidence, SecurityEvidenceKind, SecurityVerdict, SuspectDevice
} from '../../fieldwatch/domain/FieldwatchSecurityPassive';
import { checkProgress, ManualCheckGroup, ManualCheckItem } from '../../fieldwatch/domain/FieldwatchSecurityChecklist';
import { SecurityScanRecord } from '../../fieldwatch/data/FieldwatchSecurityHistoryRepository';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const SECURITY_UNDERLAY_HEIGHT: number = 168;

/**
 * 一键安防扫描（P1-5）。
 *
 * 流程：点卡 → 60 秒扫描 → 一页汇总 → 分享卡。
 * 全部数字来自 `buildSecuritySummary`（纯逻辑，已单测），本页只负责呈现与倒计时。
 *
 * **文案红线**（落地文档 P1-5）：只说「正在广播的设备」，
 * 不出现「防偷拍」「查摄像头」；脚注必须写明「不广播的设备发现不了」。
 */
@Component
export struct FieldwatchSecurityScanPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  /** 0 = 未开始，1 = 扫描中，2 = 出结果。 */
  @State private phase: number = 0;
  @State private remainingSec: number = Math.floor(SECURITY_SCAN_DURATION_MS / 1000);
  @State private summary: SecuritySummary | undefined = undefined;
  @State private sharing: boolean = false;
  @State private headline: string = '';
  /** 人工排查清单的已勾项（P3-2）。 */
  @State private checked: string[] = [];
  /** 历史扫描记录（新→旧，P3-2）。 */
  @State private history: SecurityScanRecord[] = [];
  private timer: number = -1;

  aboutToAppear(): void {
    // 重进页面时恢复上一次结果：用户从分享卡返回不该丢掉刚扫完的东西。
    const previous: SecuritySummary | undefined = fieldwatchApplication.recentSecuritySummary();
    if (previous !== undefined) {
      this.summary = previous;
      this.phase = 2;
      this.headline = this.text(summaryHeadlineKey(previous));
    }
    // 排查清单的勾选状态是持久化的，进页先读回来。
    this.checked = fieldwatchApplication.checklistDone();
    void this.loadHistory();
  }

  /** 读历史扫描记录；失败不影响主流程。 */
  private async loadHistory(): Promise<void> {
    this.history = await fieldwatchApplication.securityHistoryRecords(10);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(SECURITY_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  /**
   * 开始 60 秒扫描。
   *
   * **不新建扫描器**：应用层本来就在持续扫描，这里只是记下基线时刻与设备集合，
   * 到点后做一次汇总。这样「点卡到出卡」的时间就是 60 秒 + 绘制时间，
   * 远小于验收要求的 90 秒。
   */
  private startScan(): void {
    fieldwatchApplication.beginSecurityScan();
    this.phase = 1;
    this.remainingSec = Math.floor(SECURITY_SCAN_DURATION_MS / 1000);
    this.summary = undefined;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = setInterval((): void => {
      this.remainingSec -= 1;
      if (this.remainingSec <= 0) {
        clearInterval(this.timer);
        this.timer = -1;
        this.finishScan();
      }
    }, 1000);
  }

  private finishScan(): void {
    const result: SecuritySummary = fieldwatchApplication.finishSecurityScan();
    this.summary = result;
    this.headline = this.text(summaryHeadlineKey(result));
    this.phase = 2;
    // 本次结果已落库（应用层 save），刷新历史列表让它立刻出现。
    void this.loadHistory();
  }

  /** 组装分享卡内容：**所有文案都在这里从资源取**，绘制层不接受裸文案。 */
  private buildCardContent(): ShareCardContent {
    const content: ShareCardContent = new ShareCardContent();
    content.title = this.text('app.string.fieldwatch_security_summary_title');
    content.headline = this.headline;
    const summary: SecuritySummary | undefined = this.summary;
    content.totalText = summary === undefined ? '0' : summary.total.toString();
    content.totalLabel = this.text('app.string.fieldwatch_security_total_label');
    const classes: string[] = [];
    const counts: string[] = [];
    if (summary !== undefined) {
      summary.topClasses.forEach((item: SecurityClassCount): void => {
        classes.push(resolveResourceString(this.getUIContext().getHostContext(), signatureClassLabel(item.category)));
        counts.push(item.count.toString());
      });
      const extra: string[] = [];
      if (summary.newFaces > 0) extra.push(this.text('app.string.fieldwatch_security_newfaces').replace('%1', summary.newFaces.toString()));
      if (summary.showsFollow()) extra.push(this.text('app.string.fieldwatch_security_follow').replace('%1', summary.followScore.toString()));
      content.extraLines = extra;
    }
    content.classLabels = classes;
    content.classCounts = counts;
    // 脚注**强制存在**：这是文案红线的一部分，不是可选装饰。
    content.footnote = this.text('app.string.fieldwatch_security_footnote');
    content.brand = 'Fieldwatch · 电波足迹';
    return content;
  }

  private async share(): Promise<void> {
    if (this.sharing) return;
    this.sharing = true;
    const ok: boolean = await fieldwatchApplication.shareSecurityCard(this.buildCardContent());
    this.sharing = false;
    if (ok) {
      // 成功时刻之二（P1-10）：分享卡已经拉起来之后再问，不打断分享。
      this.maybeAskRating();
    }
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_security_share_failed'),
        duration: 2500
      });
    }
  }

  /** 成功后问一次评分（与找东西页同一套频次规则，全局 30 天一次）。 */
  private maybeAskRating(): void {
    if (!fieldwatchApplication.shouldPromptRating()) return;
    fieldwatchApplication.noteRatingShown();
    this.getUIContext().showAlertDialog({
      title: this.text('app.string.fieldwatch_rating_title'),
      message: this.text('app.string.fieldwatch_rating_body'),
      primaryButton: {
        value: this.text('app.string.fieldwatch_rating_go'),
        action: (): void => {
          fieldwatchApplication.noteRatingRated();
          this.openStore();
        }
      },
      secondaryButton: {
        value: this.text('app.string.fieldwatch_rating_later'),
        action: (): void => { fieldwatchApplication.noteRatingDeclined(); }
      }
    });
  }

  /** 打开应用市场详情页；打不开就提示用户自己搜。 */
  private openStore(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) return;
    // Context 基类没有 startAbility；与本仓库其它页面一致，收窄成 UIAbilityContext。
    const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: fieldwatchApplication.storeUri()
    }).catch((): void => {
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_rating_open_failed'),
        duration: 2600
      });
    });
  }

  build() {
    // **单个根节点**：ArkTS 要求 `build()` 只有一个根容器，所以「带壳 / 不带壳」
    // 不能在 build 里用 if/else 分出两棵树 —— 那会报 10905210。
    // 这里统一套一层 `HdsNavDestination`，不带壳时再关掉标题栏即可。
    HdsNavDestination() {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.withShell) {
            NGFImmersiveTopChromeUnderlay({
              spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
                FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
                FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
                SECURITY_UNDERLAY_HEIGHT)
            })
          }
          this.buildBody()
        }.width('100%').height('100%')
    }
      .titleBar(NGFHdsTitleBarOptionsFactory.build(
        $r('app.string.fieldwatch_security_title'),
        $r('app.string.fieldwatch_security_subtitle'),
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
        if (this.phase === 0) this.buildIdle()
        else if (this.phase === 1) this.buildScanning()
        else this.buildResult()
      }
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildIdle() {
    Column({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(56)
        .fontColor([FieldwatchPaletteHolder.get().accent])
      Text($r('app.string.fieldwatch_security_subtitle')).fontSize(15)
        .fontColor(FieldwatchPaletteHolder.get().text).textAlign(TextAlign.Center)
      // 脚注在**开始之前**就要说明，不能让用户以为能查出所有东西。
      Text($r('app.string.fieldwatch_security_footnote')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().warn).textAlign(TextAlign.Center)
      FieldwatchButton({ label: $r('app.string.fieldwatch_security_start'),
        tone: FieldwatchButtonTone.PRIMARY, onTap: (): void => { this.startScan(); } })
      // 排查清单与历史是**常驻能力**，不该逼用户先等 60 秒扫描才能看到：
      // 真机上从别处返回时会回到这个 idle 页，清单就找不到了。
      this.buildChecklist()
      this.buildHistory()
    }.width('100%').padding({ top: 40, bottom: 20 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildScanning() {
    Column({ space: 12 }) {
      Text(this.text('app.string.fieldwatch_security_remaining').replace('%1', Math.max(0, this.remainingSec).toString()))
        .fontSize(48).fontWeight(FontWeight.Bold).fontColor(FieldwatchPaletteHolder.get().accent)
      Text($r('app.string.fieldwatch_security_scanning')).fontSize(15)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Progress({ value: Math.floor(SECURITY_SCAN_DURATION_MS / 1000) - this.remainingSec,
        total: Math.floor(SECURITY_SCAN_DURATION_MS / 1000), type: ProgressType.Linear })
        .width('100%').color(FieldwatchPaletteHolder.get().accent)
    }.width('100%').padding({ top: 60, bottom: 20 }).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildResult() {
    Column({ space: 14 }) {
      Text(this.headline).fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().headerText).width('100%')
      if (this.summary !== undefined && this.summary.hasDevices()) {
        Row({ space: 6 }) {
          Text((this.summary as SecuritySummary).total.toString()).fontSize(56).fontWeight(FontWeight.Bold)
            .fontColor(FieldwatchPaletteHolder.get().accent)
          Text($r('app.string.fieldwatch_security_total_label')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim).margin({ top: 24 })
        }.width('100%')
        Text(this.kindsText()).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        this.buildClasses()
        if (this.summary !== undefined && (this.summary as SecuritySummary).newFaces > 0) {
          Text(this.text('app.string.fieldwatch_security_newfaces').replace('%1', (this.summary as SecuritySummary).newFaces.toString()))
            .fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
        }
        if (this.summary !== undefined && (this.summary as SecuritySummary).showsFollow()) {
          Text(this.text('app.string.fieldwatch_security_follow').replace('%1', (this.summary as SecuritySummary).followScore.toString()))
            .fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
        }
      } else {
        Text($r('app.string.fieldwatch_security_empty')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        // 空状态必须给动作，不能只有一句话（文档第 1 项「通用」要求）。
        FieldwatchButton({ label: $r('app.string.fieldwatch_empty_scan_now'),
          tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.startScan(); } })
      }
      // ── 可疑设备清单（P3-1 被动层）──
      this.buildSuspects()
      // ── 能力边界（文档 3.3 强制要求：写清扫不到什么）──
      this.buildCapabilityLimits()
      // ── 人工排查清单（P3-2：扫不出来的部分由它补）──
      this.buildChecklist()
      // ── 历史扫描记录（P3-2：汇总之下要能回看）──
      this.buildHistory()
      // 脚注：**每一屏都要有**，包括结果屏。
      Text($r('app.string.fieldwatch_security_footnote')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().warn).width('100%').padding({ top: 4 })
      FieldwatchButton({ label: $r('app.string.fieldwatch_security_share'),
        tone: FieldwatchButtonTone.PRIMARY, disabled: this.sharing,
        onTap: (): void => { void this.share(); } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_security_again'),
        tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.startScan(); } })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /**
   * 可疑设备清单：每台显示档位（确认 / 可疑）与命中的证据分项。
   *
   * **档位只有三档**（确认 / 可疑 / 未发现），绝不出现「安全 / 已排除」——
   * 这是文档 3.3 的硬口径，扫描到的东西有限，说「安全」就是在骗人。
   */
  @Builder
  private buildSuspects() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_security_suspects_title')).fontSize(15)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText)
      if (this.suspectRows().length === 0) {
        Text($r('app.string.fieldwatch_security_suspects_empty')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      } else {
        ForEach(this.suspectRows(), (item: SuspectDevice): void => {
          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Text(item.label.length > 0 ? item.label : item.address).fontSize(15)
                .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
              Text(this.verdictText(item))
                .fontSize(12).fontWeight(FontWeight.Medium)
                .fontColor(item.verdict === SecurityVerdict.CONFIRMED
                  ? FieldwatchPaletteHolder.get().signalRed : FieldwatchPaletteHolder.get().warn)
            }.width('100%')
            // 证据分项：让用户看到「为什么判定成可疑」，而不是一个黑箱结论。
            ForEach(item.evidence, (ev: SecurityEvidence): void => {
              Text('· ' + this.evidenceText(ev)).fontSize(11)
                .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
            }, (ev: SecurityEvidence): string => String(ev.kind) + ev.detailKey)
          }.width('100%').padding(10).borderRadius(10).alignItems(HorizontalAlign.Start)
          .backgroundColor(FieldwatchPaletteHolder.get().panel2)
        }, (item: SuspectDevice): string => item.key)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private suspectRows(): SuspectDevice[] {
    const summary: SecuritySummary | undefined = this.summary;
    return summary === undefined ? [] : summary.suspects;
  }

  private verdictText(item: SuspectDevice): string {
    if (item.verdict === SecurityVerdict.CONFIRMED) return this.text('app.string.fieldwatch_security_verdict_confirmed');
    if (item.verdict === SecurityVerdict.SUSPICIOUS) return this.text('app.string.fieldwatch_security_verdict_suspicious');
    return this.text('app.string.fieldwatch_security_verdict_none');
  }

  private evidenceText(ev: SecurityEvidence): string {
    if (ev.kind === SecurityEvidenceKind.VENDOR_OUI) return this.text('app.string.fieldwatch_security_evidence_vendor');
    if (ev.kind === SecurityEvidenceKind.NAME_PATTERN) return this.text('app.string.fieldwatch_security_evidence_name');
    if (ev.kind === SecurityEvidenceKind.MEDIA_SERVICE) return this.text('app.string.fieldwatch_security_evidence_service');
    return this.text('app.string.fieldwatch_security_evidence_catalog');
  }

  /** 能力边界：四条逐条列出，外加「当前只做被动扫描」的说明。 */
  @Builder
  private buildCapabilityLimits() {
    Column({ space: 4 }) {
      Text($r('app.string.fieldwatch_security_limits_title')).fontSize(13)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text($r('app.string.fieldwatch_security_passive_only')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      ForEach(capabilityBoundaryKeys(), (key: string): void => {
        Text('· ' + this.text(key)).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }, (key: string): string => key)
    }.width('100%').padding(12).borderRadius(10).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  /**
   * 人工排查清单（P3-2 第 3 项）。
   *
   * 逐项打勾、状态落设置存储（换页/重启后仍在）。
   * 为什么放在安防结果页：用户看完「未发现」最需要的就是下一步做什么 ——
   * 只给免责声明等于把问题丢回给用户。
   */
  @Builder
  private buildChecklist() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text($r('app.string.fieldwatch_check_title')).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).layoutWeight(1)
        Text(this.checkProgressText()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      }.width('100%')
      Text($r('app.string.fieldwatch_check_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      ForEach(this.checkGroups(), (group: ManualCheckGroup): void => {
        Column({ space: 4 }) {
          Text(this.text(group.titleKey)).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
          ForEach(group.items, (item: ManualCheckItem): void => {
            Row({ space: 8 }) {
              SymbolGlyph($r(this.isChecked(item.id) ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.circle'))
                .fontSize(16)
                .fontColor([this.isChecked(item.id) ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline])
              Column({ space: 2 }) {
                Text(this.text(item.labelKey)).fontSize(12)
                  .fontColor(this.isChecked(item.id) ? FieldwatchPaletteHolder.get().textDim : FieldwatchPaletteHolder.get().text)
                  .width('100%')
                if (item.howKey.length > 0) {
                  Text(this.text(item.howKey)).fontSize(10)
                    .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').padding({ top: 4, bottom: 4 })
            .onClick((): void => { this.toggleCheck(item.id); })
          }, (item: ManualCheckItem): string => item.id)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4 })
      }, (group: ManualCheckGroup): string => group.id)
    }.width('100%').padding(12).borderRadius(10).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  private checkGroups(): ManualCheckGroup[] { return fieldwatchApplication.checklistGroups(); }

  private isChecked(id: string): boolean { return this.checked.indexOf(id) >= 0; }

  private checkProgressText(): string {
    const progress: number[] = checkProgress(this.checked);
    return this.text('app.string.fieldwatch_check_done_count')
      .replace('%1', progress[0].toString()).replace('%2', progress[1].toString());
  }

  private toggleCheck(id: string): void {
    this.checked = fieldwatchApplication.toggleChecklistItem(id);
  }

  /**
   * 历史扫描记录（P3-2）。
   *
   * 只列汇总级数据：时间、总数、可疑数。逐台明细属于当次实时会话，不回放。
   */
  @Builder
  private buildHistory() {
    Column({ space: 6 }) {
      Text($r('app.string.fieldwatch_security_history_title')).fontSize(13)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().textDim)
      if (this.history.length === 0) {
        Text($r('app.string.fieldwatch_security_history_empty')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      } else {
        ForEach(this.history, (record: SecurityScanRecord): void => {
          Row({ space: 6 }) {
            Text(this.historyTime(record)).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
            Text(this.historySummary(record)).fontSize(12)
              .fontColor(record.confirmedCount + record.suspiciousCount > 0
                ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().textDim)
          }.width('100%')
        }, (record: SecurityScanRecord): string => record.id)
      }
    }.width('100%').padding(12).borderRadius(10).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  private historyTime(record: SecurityScanRecord): string {
    const date: Date = new Date(record.endedAt);
    const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    const day: string = date.getDate().toString().padStart(2, '0');
    const hour: string = date.getHours().toString().padStart(2, '0');
    const minute: string = date.getMinutes().toString().padStart(2, '0');
    return month + '-' + day + ' ' + hour + ':' + minute;
  }

  private historySummary(record: SecurityScanRecord): string {
    return this.text('app.string.fieldwatch_security_history_line')
      .replace('%1', record.total.toString())
      .replace('%2', (record.confirmedCount + record.suspiciousCount).toString());
  }

  private kindsText(): string {
    const summary: SecuritySummary | undefined = this.summary;
    if (summary === undefined) return '';
    return this.text('app.string.fieldwatch_security_kinds')
      .replace('%1', summary.ble.toString())
      .replace('%2', summary.wifi.toString())
      .replace('%3', summary.nearLink.toString());
  }

  @Builder
  private buildClasses() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_security_classes_title')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.classRows(), (item: SecurityClassCount): void => {
        Row({ space: 8 }) {
          Text(resolveResourceString(this.getUIContext().getHostContext(), signatureClassLabel(item.category)))
            .fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
          Text(item.count.toString()).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(FieldwatchPaletteHolder.get().accent)
        }.width('100%')
      }, (item: SecurityClassCount): string => String(item.category))
    }.width('100%')
  }

  private classRows(): SecurityClassCount[] {
    const summary: SecuritySummary | undefined = this.summary;
    return summary === undefined ? [] : summary.topClasses;
  }
}
