import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { RadioKind, SignatureClass, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import { SECURITY_SCAN_DURATION_MS, SecurityClassCount, SecuritySummary, summaryHeadlineKey } from '../../fieldwatch/domain/FieldwatchSecurityScan';
import { ShareCardContent } from '../../fieldwatch/platform/FieldwatchShareCard';
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
  private timer: number = -1;

  aboutToAppear(): void {
    // 重进页面时恢复上一次结果：用户从分享卡返回不该丢掉刚扫完的东西。
    const previous: SecuritySummary | undefined = fieldwatchApplication.recentSecuritySummary();
    if (previous !== undefined) {
      this.summary = previous;
      this.phase = 2;
      this.headline = this.text(summaryHeadlineKey(previous));
    }
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
    }.width('100%').padding({ top: 40, bottom: 20 }).alignItems(HorizontalAlign.Center)
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
      }
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
