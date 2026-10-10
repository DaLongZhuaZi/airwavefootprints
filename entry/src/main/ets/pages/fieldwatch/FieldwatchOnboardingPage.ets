import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { logger, ngfSystemNotificationManager, resolveResourceString, uiContextManager } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import {
  buildPermissionSpecs,
  FIELDWATCH_BASELINE_FEATURE_KEYS,
  FIELDWATCH_BASELINE_SYMBOLS,
  FieldwatchCapabilitySnapshot,
  FieldwatchPermissionKind,
  FieldwatchPermissionSpec
} from '../../fieldwatch/domain/FieldwatchPermissions';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';
import { FieldwatchChip } from '../../fieldwatch/ui/FieldwatchChip';

const TAG: string = 'FieldwatchOnboarding';

/** 每一步的主视觉 symbol 与文案键。 */
class OnboardingStepHead {
  public symbol: string;
  public titleKey: string;
  public bodyKey: string;
  constructor(symbol: string, titleKey: string, bodyKey: string) {
    this.symbol = symbol;
    this.titleKey = titleKey;
    this.bodyKey = bodyKey;
  }
}
function buildStepHeads(): OnboardingStepHead[] {
  const heads: OnboardingStepHead[] = [];
  heads.push(new OnboardingStepHead('sys.symbol.dot_radiowaves', 'app.string.fieldwatch_onb_welcome_title', 'app.string.fieldwatch_onb_welcome_body'));
  heads.push(new OnboardingStepHead('sys.symbol.list_checkmark', 'app.string.fieldwatch_onb_baseline_title', 'app.string.fieldwatch_onb_baseline_body'));
  heads.push(new OnboardingStepHead('sys.symbol.checkmark_shield', 'app.string.fieldwatch_onb_perm_title', 'app.string.fieldwatch_onb_perm_body'));
  heads.push(new OnboardingStepHead('sys.symbol.gearshape', 'app.string.fieldwatch_onb_settings_title', 'app.string.fieldwatch_onb_settings_body'));
  return heads;
}

/**
 * 首次启动引导。
 *
 * 四步，顺序不可换：
 *   ① 这是什么（只接收 / 离线 / 无需权限也能用）
 *   ② 不授权也能用哪些功能（先把退路讲清楚）
 *   ③ 权限逐条说明与逐条申请（**在系统弹窗之前**讲用途）
 *   ④ 功能设置（扫描强度 / 后台运行 / 屏幕常亮）
 *
 * 第 ④ 步放在最后是**有意的**：后台运行会拉起长时任务与常驻通知，
 * 而通知权限在第 ③ 步才申请 —— 顺序反了会让用户看到一个「开了却弹不出通知」的开关。
 *
 * 每一步都有主视觉 symbol，切换时做淡出+位移的过渡，避免「静态换页」的单调感。
 */
@Component
export struct FieldwatchOnboardingPage {
  /** 引导结束（完成或跳过）后由外层切换主界面。 */
  onFinish: () => void = (): void => {};
  @State private step: number = 0;
  @State private snapshot: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
  @State private topInset: number = 0;
  /** 内容过渡：透明度 + 纵向位移，切换步骤时两段式动画。 */
  @State private contentOpacity: number = 1;
  @State private contentShift: number = 0;
  /** 主视觉 symbol 的入场缩放。 */
  @State private heroScale: number = 1;
  // 用应用层的**按能力过滤**目录：不支持星闪的设备不会列出星闪权限。
  private readonly specs: FieldwatchPermissionSpec[] = fieldwatchApplication.permissionCatalog();
  /** 通知是否已启用（与普通权限分开跟踪，API 不同）。 */
  @State private notificationEnabled: boolean = false;
  // ── 第 ④ 步「功能设置」的三项（与设置页共用同一套应用层 API）──
  @State private scanIntensity: string = 'balanced';
  @State private backgroundScanning: boolean = false;
  @State private keepScreenOn: boolean = false;
  private readonly heads: OnboardingStepHead[] = buildStepHeads();

  aboutToAppear(): void {
    this.readTopInset();
    this.snapshot = fieldwatchApplication.permissionSnapshot();
    // 第 ④ 步的三项**不在这里缓存副本**。
    //
    // 曾经缓存在 @State 里，于是出现「引导页显示的与设置页不一致」：
    // 引导页只在 aboutToAppear 读一次，而那一刻应用层可能还没把设置读进来；
    // 设置页每秒重读，自然就与引导页对不上了。
    // 改为在 builder 里直接读应用层当前值（进入该步会重建，值就是最新的）。
    this.syncFeatureSettings();
    // 读一次真实的通知开关状态，避免卡片显示与系统实际状态不一致。
    void ngfSystemNotificationManager.isEnabled().then((enabled: boolean): void => {
      this.notificationEnabled = enabled;
    });
  }
  /** 把第 ④ 步三项的当前值从应用层同步进来。 */
  private syncFeatureSettings(): void {
    const settings = fieldwatchApplication.getState().settings;
    this.scanIntensity = settings.scanIntensity;
    this.backgroundScanning = settings.backgroundScanning;
    this.keepScreenOn = settings.keepScreenOn;
  }

  private readTopInset(): void {
    const uiContext = this.getUIContext();
    if (uiContext === undefined) return;
    window.getLastWindow(uiContext.getHostContext()).then((lastWindow: window.Window): void => {
      const area: window.AvoidArea = lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = uiContext.px2vp(area.topRect.height);
    }).catch((): void => { this.topInset = 0; });
  }
  private label(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }
  private finish(): void {
    fieldwatchApplication.markOnboardingSeen();
    this.onFinish();
  }
  /** 稍后再说：记住用户的选择，之后不再自动弹权限说明。 */
  private finishWithoutPermissions(): void {
    fieldwatchApplication.markPermissionPromptDismissed();
    this.finish();
  }
  /**
   * 申请单条权限。
   * 若系统不再弹窗（用户此前拒绝过，或在系统设置里手动关闭过），
   * 必须明确告知并给出系统设置入口 —— 否则按钮看起来「点了没反应」。
   */
  private async allow(kind: FieldwatchPermissionKind): Promise<void> {
    const granted: boolean = await fieldwatchApplication.requestPermission(kind);
    this.snapshot = fieldwatchApplication.permissionSnapshot();
    if (granted || this.granted(kind)) return;
    this.showManualGrantDialog(kind);
  }
  /** 系统不再弹窗时的兜底说明 + 跳系统设置。 */
  /**
   * 「系统不会再弹出授权窗口」说明框。
   * **权限名称与系统设置路径都取自该权限自己的 spec** —— 写死文案会让两条权限显示同一个名字。
   */
  private showManualGrantDialog(kind: FieldwatchPermissionKind): void {
    const spec: FieldwatchPermissionSpec | undefined = fieldwatchApplication.permissionSpec(kind);
    if (spec === undefined) return;
    const name: string = this.label(spec.titleKey);
    const where: string = this.label(spec.whereKey);
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_manual_title'),
      message: this.label('app.string.fieldwatch_manual_body').replace('%s', name).replace('%p', where),
      primaryButton: { value: this.label('app.string.fieldwatch_manual_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_manual_open'), action: (): void => { this.openAppSettings(); } }
    });
  }
  /** 跳系统设置：统一走应用层的共享实现（内部已处理对话框调用点的时序问题）。 */
  private openAppSettings(): void {
    fieldwatchApplication.openAppPermissionSettings((): void => {
      this.getUIContext().getPromptAction().showToast({
        message: this.label('app.string.fieldwatch_manual_toast'),
        duration: 3000
      });
    });
  }



  /**
   * 切到指定步骤。
   * 两段式：先把当前内容淡出并轻微位移，换页后再淡入 —— 单段动画会看到内容「跳变」。
   */
  private goTo(next: number): void {
    if (next === this.step) return;
    const ui = this.getUIContext();
    const forward: boolean = next > this.step;
    ui.animateTo({ duration: 160, curve: Curve.EaseIn }, (): void => {
      this.contentOpacity = 0;
      this.contentShift = forward ? -18 : 18;
      this.heroScale = 0.9;
    });
    setTimeout((): void => {
      this.step = next;
    // 进入第 ④ 步时把三项的当前值同步进来（它们不在本页缓存）。
    if (next === 3) this.syncFeatureSettings();
      this.contentShift = forward ? 18 : -18;
      ui.animateTo({ duration: 260, curve: Curve.Friction }, (): void => {
        this.contentOpacity = 1;
        this.contentShift = 0;
        this.heroScale = 1;
      });
    }, 165);
  }

  build() {
    Column() {
      this.buildProgress()
      Scroll() {
        Column({ space: 14 }) {
          this.buildHero()
          if (this.step === 0) this.buildWelcome()
          else if (this.step === 1) this.buildBaseline()
          else if (this.step === 2) this.buildPermissions()
          else this.buildFeatureSettings()
        }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      this.buildActions()
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset + 20, bottom: 20 })
    .backgroundColor(FieldwatchPaletteHolder.get().night)
  }

  /** 每步的主视觉：大号 symbol + 柔光底。 */
  @Builder private buildHero() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(96).height(96).fill(FieldwatchPaletteHolder.get().badgeBg)
        SymbolGlyph($r(this.heads[this.step].symbol))
          .fontSize(46)
          .fontColor([FieldwatchPaletteHolder.get().accent])
      }
      .width(96).height(96)
      .scale({ x: this.heroScale, y: this.heroScale })
      Text($r(this.heads[this.step].titleKey))
        .fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().headerText)
        .textAlign(TextAlign.Center)
      Text($r(this.heads[this.step].bodyKey))
        .fontSize(14).fontColor(FieldwatchPaletteHolder.get().text)
        .textAlign(TextAlign.Center)
    }
    .width('100%').padding({ top: 8, bottom: 6 })
    .opacity(this.contentOpacity)
    .translate({ y: this.contentShift })
  }

  /** 四步进度：当前步是拉长的胶囊，其余是圆点。 */
  @Builder private buildProgress() {
    Row({ space: 8 }) {
      ForEach([0, 1, 2, 3], (index: number): void => {
        Row()
          .width(index === this.step ? 26 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(index <= this.step ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
          .animation({ duration: 220, curve: Curve.EaseOut })
      }, (index: number): string => index.toString())
      Blank()
      // 总数取自 heads，避免以后再加一步时又漏改这一处（这里曾经写死 3）。
      Text((this.step + 1).toString() + ' / ' + this.heads.length.toString()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding({ left: 20, right: 20, bottom: 12 })
  }

  // ── ① 这是什么 ──
  @Builder private buildWelcome() {
    this.buildPrinciple('sys.symbol.dot_radiowaves', $r('app.string.fieldwatch_onb_p1_title'), $r('app.string.fieldwatch_onb_p1_body'))
    this.buildPrinciple('sys.symbol.wifi_slash', $r('app.string.fieldwatch_onb_p2_title'), $r('app.string.fieldwatch_onb_p2_body'))
    this.buildPrinciple('sys.symbol.checkmark_shield', $r('app.string.fieldwatch_onb_p3_title'), $r('app.string.fieldwatch_onb_p3_body'))
  }
  @Builder private buildPrinciple(symbol: string, title: ResourceStr, body: ResourceStr) {
    Row({ space: 12 }) {
      Stack() { SymbolGlyph($r(symbol)).fontSize(20).fontColor([FieldwatchPaletteHolder.get().accent]) }
        .width(40).height(40).borderRadius(20).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
        Text(body).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    .opacity(this.contentOpacity).translate({ y: this.contentShift })
  }

  // ── ② 不授权也能用 ──
  @Builder private buildBaseline() {
    Column({ space: 10 }) {
      ForEach(FIELDWATCH_BASELINE_FEATURE_KEYS, (key: string, index: number): void => {
        Row({ space: 12 }) {
          Stack() {
            SymbolGlyph($r(FIELDWATCH_BASELINE_SYMBOLS[index]))
              .fontSize(18).fontColor([FieldwatchPaletteHolder.get().accent])
          }.width(36).height(36).borderRadius(18).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
          Text($r(key)).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        }.width('100%')
      }, (key: string): string => key)
    }
    .width('100%').padding(16).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    .opacity(this.contentOpacity).translate({ y: this.contentShift })
    Text($r('app.string.fieldwatch_onb_baseline_hint'))
      .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      .opacity(this.contentOpacity).translate({ y: this.contentShift })
  }

  // ── ③ 权限逐条说明 ──
  @Builder private buildPermissions() {
    ForEach(this.specs, (spec: FieldwatchPermissionSpec): void => {
      this.buildPermissionCard(spec)
    }, (spec: FieldwatchPermissionSpec): string => spec.kind)
    // 通知权限与普通权限不同：它不走 requestPermissionsFromUser，
    // 而是 notificationManager.requestEnableNotification，因此单独成卡。
    // 用户要求「通知权限申请要正确出现在启动引导里面」，这里就是它的位置。
    this.buildNotificationCard()
  }
  /** 通知权限卡片：说明用途后再申请，与其它权限同一套「先说明再申请」原则。 */
  @Builder private buildNotificationCard() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(18).fontColor([FieldwatchPaletteHolder.get().accent])
        }.width(36).height(36).borderRadius(18).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
        Text($r('app.string.fieldwatch_perm_notif_title')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        if (this.notificationEnabled) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor([FieldwatchPaletteHolder.get().accent])
            Text($r('app.string.fieldwatch_onb_allowed')).fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent)
          }
        } else {
          FieldwatchButton({ label: $r('app.string.fieldwatch_onb_allow'), tone: FieldwatchButtonTone.PRIMARY,
            compact: true, fillWidth: false, onTap: (): void => { void this.requestNotification(); } })
        }
      }.width('100%')
      Text($r('app.string.fieldwatch_notification_permission_reason'))
        .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
      .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }
  private async requestNotification(): Promise<void> {
    await ngfSystemNotificationManager.requestPermission();
    this.notificationEnabled = await ngfSystemNotificationManager.isEnabled();
  }
  @Builder private buildPermissionCard(spec: FieldwatchPermissionSpec) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r(this.permissionSymbol(spec.kind)))
            .fontSize(18).fontColor([FieldwatchPaletteHolder.get().accent])
        }.width(36).height(36).borderRadius(18).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
        Text($r(spec.titleKey)).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        if (this.granted(spec.kind)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor([FieldwatchPaletteHolder.get().accent])
            Text($r('app.string.fieldwatch_onb_allowed')).fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent)
          }
        } else {
          FieldwatchButton({ label: $r('app.string.fieldwatch_onb_allow'), tone: FieldwatchButtonTone.PRIMARY,
            compact: true, fillWidth: false, onTap: (): void => { void this.allow(spec.kind); } })
        }
      }.width('100%')
      Text($r(spec.whyKey)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_checkmark')).fontSize(12).fontColor([FieldwatchPaletteHolder.get().textDim])
        Text($r(spec.featureKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
      }.width('100%')
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(12).fontColor([FieldwatchPaletteHolder.get().warn])
        Text($r(spec.deniedKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().warn).layoutWeight(1)
      }.width('100%')
    }
    .width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .opacity(this.contentOpacity).translate({ y: this.contentShift })
  }
  /** 每条权限一个可辨识的图标，避免四张卡片看起来一样。 */
  private permissionSymbol(kind: FieldwatchPermissionKind): string {
    if (kind === FieldwatchPermissionKind.BLUETOOTH) return 'sys.symbol.dot_radiowaves';
    if (kind === FieldwatchPermissionKind.LOCATION) return 'sys.symbol.location_up_fill';
    // globe 不在系统符号库里；下载目录用「云 + 向下箭头」语义更贴切。
    return 'sys.symbol.location_up_fill';
  }
  private granted(kind: FieldwatchPermissionKind): boolean {
    if (kind === FieldwatchPermissionKind.BLUETOOTH) {
      // 同一条目覆盖蓝牙与星闪，两者都拿到才算已授权。
      const nlOk: boolean = !fieldwatchApplication.nearLinkAvailable() || this.snapshot.nearlink;
      return this.snapshot.bluetooth && nlOk;
    }
    if (kind === FieldwatchPermissionKind.LOCATION) return this.snapshot.location;
    return this.snapshot.location;
  }

  /**
  * 第 ④ 步：功能设置。
  *
  * 三项都**立即生效并落盘**（走与设置页完全相同的那套应用层 API），
  * 不是「先记下来、进主界面再应用」—— 那样一旦用户中途退出就会丢设置。
  *
  * 页面内不重复实现任何逻辑：文案、取值、副作用都复用设置页那一套，
  * 否则「引导里改的」与「设置页改的」迟早会不一致（陷阱 16）。
  */
  @Builder private buildFeatureSettings() {
    Column({ space: 14 }) {
      // ① 扫描强度
      Column({ space: 8 }) {
        Text($r('app.string.fieldwatch_settings_scan')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().headerText)
        Row({ space: 8 }) {
          FieldwatchChip({ label: $r('app.string.wifi_scan_basic'), active: this.scanIntensity === 'basic',
            onTap: (): void => { this.scanIntensity = 'basic'; fieldwatchApplication.setScanIntensity('basic'); } })
          FieldwatchChip({ label: $r('app.string.wifi_scan_balanced'), active: this.scanIntensity === 'balanced',
            onTap: (): void => { this.scanIntensity = 'balanced'; fieldwatchApplication.setScanIntensity('balanced'); } })
          FieldwatchChip({ label: $r('app.string.wifi_scan_saver'), active: this.scanIntensity === 'saver',
            onTap: (): void => { this.scanIntensity = 'saver'; fieldwatchApplication.setScanIntensity('saver'); } })
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)

      // ② 后台运行（开关状态以应用层返回值为准：申请失败时不能显示成「已开启」）
      Column({ space: 4 }) {
        Row() {
          Text($r('app.string.fieldwatch_settings_background_scanning')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.backgroundScanning })
            .onChange((value: boolean): void => {
              void fieldwatchApplication.setBackgroundScanning(value).then((enabled: boolean): void => {
                this.backgroundScanning = enabled;
              });
            })
        }.width('100%')
        Text($r('app.string.fieldwatch_settings_background_hint')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%').alignItems(HorizontalAlign.Start)

      // ③ 屏幕常亮
      Row() {
        Text($r('app.string.fieldwatch_settings_keep_screen_on')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn })
          .onChange((value: boolean): void => {
            void fieldwatchApplication.setKeepScreenOn(value).then((): void => { this.keepScreenOn = value; });
          })
      }.width('100%')
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  // ── 底部动作 ──
  @Builder private buildActions() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (this.step > 0) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(15).fontColor([FieldwatchPaletteHolder.get().text])
              Text($r('app.string.fieldwatch_onb_back')).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
            }
          }
          .height(46).layoutWeight(1).borderRadius(23)
          .backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline)
          .onClick((): void => { this.goTo(this.step - 1); })
        }
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            Text(this.step < this.heads.length - 1 ? $r('app.string.fieldwatch_onb_next') : $r('app.string.fieldwatch_onb_enter'))
              .fontSize(15).fontColor(FieldwatchPaletteHolder.get().onAccent)
            SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(15).fontColor([FieldwatchPaletteHolder.get().onAccent])
          }
        }
        .height(46).layoutWeight(1).borderRadius(23)
        .fontColor($r('app.color.fw_on_accent'))
        .backgroundColor($r('app.color.button_primary'))
        .onClick((): void => {
          if (this.step < this.heads.length - 1) this.goTo(this.step + 1);
          else this.finish();
        })
      }.width('100%')
      if (this.step === 2) {
        Button($r('app.string.fieldwatch_onb_later')).height(44).width('100%')
          .backgroundColor(Color.Transparent).fontColor(FieldwatchPaletteHolder.get().textDim)
          .onClick((): void => { this.finishWithoutPermissions(); })
      }
    }.width('100%').padding({ left: 20, right: 20 })
  }
}
