import { LengthMetrics } from '@kit.ArkUI';
import { hdsMaterial, HdsNavigation, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import window from '@ohos.window';
import { NGFThemeMode, ngfDeviceAdaptationFacade, NGFDeviceInfo, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, NGFMaterialSheetOptions, ngfThemeManagerFacade, ngfVisualEffectsFacade, resolveResourceString, uiContextManager } from 'ngf_framework';
import { FieldwatchApplication, FieldwatchApplicationState, fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FieldwatchRowMetrics, rowMetricsFor } from '../../fieldwatch/ui/FieldwatchSignalRow';
import { FieldwatchLiveMode, FieldwatchNavigationTab, FieldwatchRadarPoint, FieldwatchUiState, buildRadarPoints, groupByBrand, planRadarLabels, RadarLabelPlan, sparkRangeOf, SparkRange, formatClockTime, liveDecodeLabels, matchedSignatureNames, remainingAttemptSeconds, sparklineCommands, signatureColorAt, signatureColorIndex, sortSightingsForLiveMode, visibleSightingsAfterPause, wifiPhaseNeedsAction, wifiFactValue } from '../../fieldwatch/ui/FieldwatchUiState';
import { logger, ngfSystemNotificationManager } from 'ngf_framework';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { buildRadarNodes, FieldwatchRadarNode } from '../../fieldwatch/ui/FieldwatchRadarCluster';
import { nearLinkClassLabel } from '../../fieldwatch/ui/FieldwatchDeviceTypeIcon';
import { FieldwatchChip, FieldwatchPresetChip, FieldwatchSwitchRow } from '../../fieldwatch/ui/FieldwatchChip';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/**
 * 主题枚举 → 状态字符串。
 *
 * 放在模块级而不是某个 struct 里：根页面与设置页都需要它，
 * 而 ArkTS 的 struct 方法不能跨结构体调用。
 */
import { CandidateReport, SignatureCandidate } from '../../fieldwatch/domain/FieldwatchCandidateEngine';
import { countSightingsByKind, DecodedFieldValue, FieldwatchLogFootprint, FilterDefinition, FilterLogic, FilterPreset, GpsSample, isRadioPhaseActive, mergeScanError, RadioKind, RadioSourceSnapshot, ServiceDataRecord, SignatureClass, Sighting, SitSummary, WatchTarget, WifiScanPhase, foldedSignatureClass, visibleSignatureClasses } from '../../fieldwatch/domain/FieldwatchModels';
import { SignatureFleet } from '../../fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { SignatureMatchExplanation } from '../../fieldwatch/domain/signatures/FieldwatchSignatureEngine';
import { FieldwatchHuntParam, FieldwatchRouteName, FieldwatchSignatureEditorParam } from '../../fieldwatch/ui/FieldwatchRoutes';
import { FieldwatchHuntPage } from './FieldwatchHuntPage';
import { FieldwatchDeviceDetailPage } from './FieldwatchDeviceDetailPage';
import { FieldwatchSignatureEditorPage } from './FieldwatchSignatureEditorPage';
import { FieldwatchDeviceTypeIcon } from '../../fieldwatch/ui/FieldwatchDeviceTypeIcon';
import { FieldwatchSignaturesPage } from './FieldwatchSignaturesPage';
import { FieldwatchToolboxPage } from './FieldwatchToolboxPage';
import { FieldwatchWatchlistPage } from '../../fieldwatch/ui/FieldwatchWatchlistPage';
import { FieldwatchFeedbackPage } from './FieldwatchFeedbackPage';
import {
  FieldwatchDeepLink, fieldwatchDeepLinkBridge, FieldwatchDeepLinkKind
} from '../../fieldwatch/platform/FieldwatchDeepLink';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { FieldwatchSignatureDetail } from '../../fieldwatch/ui/FieldwatchSignatureDetail';
import { FieldwatchOnboardingPage } from './FieldwatchOnboardingPage';
import { buildPermissionSpecs, FieldwatchCapabilitySnapshot, FieldwatchPermissionKind, FieldwatchPermissionSpec } from '../../fieldwatch/domain/FieldwatchPermissions';

/**
 * 主题枚举 → 状态字符串。
 *
 * 放在模块级而不是某个 struct 里：根页面与设置页都需要它，
 * 而 ArkTS 的 struct 方法不能跨结构体调用。
 */
function themeModeName(mode: NGFThemeMode): string {
  if (mode === NGFThemeMode.LIGHT) return 'light';
  if (mode === NGFThemeMode.DARK) return 'dark';
  return 'auto';
}

/**
 * Wi-Fi 扫描相位的可读文案（§12.1）。
 *
 * **模块级函数而非页面方法**：Live 页与 Settings 页都要用（前者渲染扫描错误提示条，
 * 后者渲染状态行），放在任一页面类里另一处就调不到。
 *
 * **优先复用项目里早已存在的 `wifi_*` 词汇** —— 它们是为这些相位写好的成套文案，
 * 只是当时没接线。我第一版为此新造了一套 `fieldwatch_wifi_phase_*`，属于重复造词；
 * 现在只有确实没有对应词的两个状态（空闲、检查前置条件）用新键。
 *
 * 未知值原样返回，将来新增相位时至少不显示空白。
 */
function wifiPhaseLabel(context: Context | undefined, phase: string): string {
  if (phase === WifiScanPhase.IDLE) return resolveResourceString(context, $r('app.string.fieldwatch_wifi_phase_idle'));
  if (phase === WifiScanPhase.PRECHECK) return resolveResourceString(context, $r('app.string.fieldwatch_wifi_phase_precheck'));
  if (phase === WifiScanPhase.WAITING_FOR_RETRY) return resolveResourceString(context, $r('app.string.wifi_waiting_system'));
  if (phase === WifiScanPhase.SCANNING) return resolveResourceString(context, $r('app.string.wifi_scanning'));
  if (phase === WifiScanPhase.READY) return resolveResourceString(context, $r('app.string.wifi_updated'));
  if (phase === WifiScanPhase.STALE) return resolveResourceString(context, $r('app.string.wifi_cached'));
  if (phase === WifiScanPhase.LOCATION_DISABLED) return resolveResourceString(context, $r('app.string.wifi_location_disabled'));
  if (phase === WifiScanPhase.WIFI_DISABLED) return resolveResourceString(context, $r('app.string.wifi_disabled'));
  if (phase === WifiScanPhase.PERMISSION_DENIED) return resolveResourceString(context, $r('app.string.wifi_permission_denied'));
  if (phase === WifiScanPhase.UNSUPPORTED) return resolveResourceString(context, $r('app.string.wifi_unsupported'));
  if (phase === WifiScanPhase.SYSTEM_REJECTED) return resolveResourceString(context, $r('app.string.wifi_system_rejected'));
  if (phase === WifiScanPhase.ERROR) return resolveResourceString(context, $r('app.string.wifi_error'));
  return phase;
}

const TAG: string = 'FieldwatchRootPage';
const PAGE_UNDERLAY_HEIGHT: number = 96;

@Entry
@Component
struct FieldwatchRootPage {
  @State private selectedTab: number = FieldwatchNavigationTab.LIVE;
  /** 关注状态变化计数：转发给特征库列表，让它重建行内的「已关注」。 */
  @State private followTick: number = 0;
  /** 首次启动引导：未完成时先走引导，再进主界面。 */
  @State private showOnboarding: boolean = false;
  @StorageProp('ngf_is_dark_mode') @Watch('onDarkModeChanged') private isDarkMode: boolean = true;
  @State private isLandscape: boolean = false;
  /**
   * 横屏导航栏是否展开（仅图标 / 图标+文字）。
   *
   * **不用 `HdsSideBar`**：它只暴露 `$isShowSideBar` 回调，
   * 没有把 `SideBarContainer.showControlButton` 透出来，于是收起按钮根本不渲染
   * （实测确认）。`HdsSideMenu` 也不支持图标-only 态，收起后会裁切文字。
   * 收起是这个需求的核心，所以自建——但沿用 HDS 调色板与同样的动画曲线。
   */
  @State private railExpanded: boolean = true;
  /** 当前是否停在子页面。分栏必须由它驱动 —— 只看方向的话空态也会分栏。 */
  @State private subPageOpen: boolean = false;
  @State private deviceCount: number = 0;
  @State private logCount: number = 0;
  @State private wifiPhase: string = WifiScanPhase.IDLE;
  @State private wifiResultCount: number = 0;
  @State private wifiFresh: boolean = false;
  @State private wifiNextAttemptAt: number = 0;
  @State private wifiErrorMessage: string = '';
  @State private liveMode: FieldwatchLiveMode = FieldwatchLiveMode.RADAR;
  @State private visibleSightings: Sighting[] = [];
  @State private scanIntensity: string = 'balanced';
  /** 当前外观主题覆盖（auto / light / dark），用于给三个按钮显示选中态。 */
  @State private themeOverride: string = 'auto';
  @State private activeSitName: string = '';
  @State private savedSitCount: number = 0;
  @State private bottomInsetVp: number = 0;
  @State private topInsetVp: number = 0;
  /** 是否具备扫描能力（蓝牙或 Wi-Fi 任一授权）。 */
  /** BLE 不可用（系统设置里的「设备发现和连接」未开启）。 */
  @State private bleMissing: boolean = true;
  /** 星闪权限未授予（设备支持星闪时才可能为真）。 */
  @State private nearLinkMissing: boolean = false;
  @State private permissionBusy: boolean = false;
  @State private pathStack: NavPathStack = new NavPathStack();
  private readonly tabsController: HdsTabsController = new HdsTabsController();
  /**
   * 切换方向：1 = 往右切（新页面从右边进），-1 = 往左切。
   *
   * 只用于决定过渡的位移方向；切换完成后不需要复位 ——
   * 下一次切换会重新赋值。
   */
  @State private tabSlide: number = 1;
  /**
   * 主页面是否可以用两列排布。
   *
   * **横屏 且 右栏没开** —— 右栏一开，可用宽度只剩三分之一，
   * 两列会把每列压到放不下内容（实测要求：有侧边栏时恢复一列）。
   * 竖屏宽度本就不够，一律单列。
   */
  private twoColumnTabs(): boolean {
    const value: boolean = this.isLandscape && !this.subPageOpen;
    // 诊断：两列没生效时，必须能分清是「判定为 false」还是「布局没按两列排」。
    // 这两个原因的修法完全不同，靠肉眼看截图分不出来。
    logger.info('FieldwatchLayout', '两列判定: isLandscape=' + this.isLandscape.toString()
      + ' subPageOpen=' + this.subPageOpen.toString() + ' -> twoColumn=' + value.toString());
    return value;
  }
  private readonly uiState: FieldwatchUiState = new FieldwatchUiState();
  private refreshTimer: number = -1;
  /**
   * 横竖屏切换。
   *
   * **切回竖屏时必须把 Tabs 控制器拨回 `selectedTab`。**
   *
   * 竖屏与横屏是**两棵不同的布局树**（`HdsTabs` 与自绘侧栏），切换时竖屏那棵是**新建**的，
   * `HdsTabs` 的内部下标从 0 开始；而底栏的选中态读的是 `this.selectedTab`（见 `buildTabItem`）。
   * 两者当场错开：底栏高亮「特征库」，内容却是「实时-雷达」（实测反馈）。
   */
  private readonly deviceChangeListener = (info: NGFDeviceInfo): void => {
    const wasLandscape: boolean = this.isLandscape;
    this.isLandscape = info.isLandscape;
    // 只在「横 -> 竖」时补：反方向横屏读的就是 `selectedTab`，本来就一致。
    if (wasLandscape && !info.isLandscape) {
      // 延后一帧：此刻新的布局树还没挂上，立刻拨会被丢弃。
      setTimeout((): void => { this.syncTabsToSelected(); }, 0);
    }
  };

  /** 把 Tabs 的内部控制下标拨到 `selectedTab`，消除「底栏与内容不一致」。 */
  private syncTabsToSelected(): void {
    if (this.selectedTab === 0) return;
    this.tabsController.changeIndex(this.selectedTab);
  }

  /**
   * 拦截导航的显示事件，用来判断「当前是否还有子页面」。
   *
   * `NavPathStack` 只有 `size()`、没有变化回调，所以用 `didShow` 在每次跳转
   * 完成后同步一次。`size() === 0` 表示已回到根页面，此时收起分栏。
   */
  /**
   * 打开一个子页面（竖屏路由用；横屏详情走 `openDeviceDetail` 的面板分支）。
   */
  /**
   * 追随导航事件，维护 `subPageOpen`。
   *
   * `NavPathStack` 只有 `size()`、没有变化回调，所以用 `didShow` 在每次跳转
   * 完成后同步一次。
   *
   * **开启由 `openSubPage` 负责**（必须在压栈前，否则详情会先占满全屏再被推向右）；
   * 这里只负责**收尾**：回到根页面时把分栏收回去。
   */
  private watchNavigation(): void {
    this.pathStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, isAnimated: boolean): void => {
        this.subPageOpen = this.topRouteUsesSplit();
      }
    });
  }

  /**
   * 当前栈顶的路由是否应该走横屏分栏。
   *
   * **只有设备详情是「左列表 + 右详情」，其余都是整页**（特征编辑器、搜寻页…）。
   *
   * 原来这里写的是 `pathStack.size() > 0` —— 语义是「有页面开着」，
   * 于是**从特征库点新建特征时，横屏也被切成两栏**：
   * 左栏重新分栏、编辑器被塞进右栏，观感就是
   * 「先在左边闪现、再跑到右边」（实测反馈）。
   *
   * `subPageOpen` 的含义是「详情页开着」，不是「有页面开着」——
   * 两者混用会让每个新页面都继承详情页的分栏行为。
   */
  /** 深链带进来的 issue 号；0 表示只看列表。 */
  @State private feedbackIssueNumber: number = 0;
  /** 深链 `feedback/new`：直达新建表单。 */
  @State private feedbackCreateMode: boolean = false;

  /** 打开反馈中心。 */
  private openFeedback(): void { this.pathStack.pushPathByName(FieldwatchRouteName.FEEDBACK, ''); }

  private topRouteUsesSplit(): boolean {
    const names: string[] = this.pathStack.getAllPathName();
    if (names.length === 0) return false;
    const top: string = names[names.length - 1];
    // **凡是「从列表点进去看/改一条」的页面都走右栏**：
    // 详情、特征编辑器、搜寻。它们与左侧列表是主从关系，
    // 全屏会丢掉「我还在这一列里」的上下文（实测反馈）。
    return top === FieldwatchRouteName.DEVICE_DETAIL
      || top === FieldwatchRouteName.SIGNATURE_DETAIL
      || top === FieldwatchRouteName.SIGNATURE_EDITOR
      || top === FieldwatchRouteName.WATCHLIST
      || top === FieldwatchRouteName.HUNT
      || top === FieldwatchRouteName.FEEDBACK;
  }

  private openSubPage(name: string, param: string): void {
    // **先切分栏、再压栈。**
    //
    // 顺序反过来的话，详情会先以 Stack 占满全屏，随后左栏出现把它**推向右** ——
    // 那同样读作「详情从左往右跑」。
    // 先把分栏边界立好（模式切换动画已关闭，是瞬间的），再压栈，
    // 详情就只会在自己那一栏里从右滑入。
    this.subPageOpen = true;
    this.pathStack.pushPathByName(name, param);
  }

  /**
   * 打开设备详情。
   *
   * **横屏走右栏面板，竖屏走路由页。** 两条路都进同一个
   * `FieldwatchDeviceDetailPage`，只是 `asPanel` 不同 ——
   * 内容与行为（含返回）完全一致，不会出现两套实现漂移。
   */
  private openDeviceDetail(deviceKey: string): void {
    this.openSubPage(FieldwatchRouteName.DEVICE_DETAIL, deviceKey);
  }

  aboutToAppear(): void {
    this.watchNavigation();
    this.isLandscape = ngfDeviceAdaptationFacade.isLandscape();
    ngfDeviceAdaptationFacade.addListener(this.deviceChangeListener);
    this.applyImmersiveSystemBars(true);
    this.readBottomInset();
    // 首次启动先走引导（含权限说明）；引导完成前不申请任何权限。
    this.showOnboarding = !fieldwatchApplication.onboardingSeen();
    // 星闪能力探测必须**先于** startScan：探测结果决定协调器是否包含星闪扫描器，
    // 而协调器一旦开始扫描就不会重建。顺序反了会导致星闪永远不被接入。
    fieldwatchApplication.probeNearLinkCapability();
    void this.startScan();
    void fieldwatchApplication.ensureCatalogLoaded().then((): void => { this.refreshView(); });
    this.refreshView();
    this.refreshTimer = setInterval((): void => { this.refreshView(); }, 1000);
  }

  private readBottomInset(): void {
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (hostContext === undefined || hostContext === null) return;
    window.getLastWindow(hostContext).then((lastWindow: window.Window): void => {
      const avoidArea: window.AvoidArea = lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInsetVp = uiContext.px2vp(avoidArea.bottomRect.height);
      const statusArea: window.AvoidArea = lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInsetVp = uiContext.px2vp(statusArea.topRect.height);
    }).catch((): void => { this.bottomInsetVp = 0; });
  }

  aboutToDisappear(): void {
    ngfDeviceAdaptationFacade.removeListener(this.deviceChangeListener);
    this.applyImmersiveSystemBars(false);
    fieldwatchApplication.stopScan();
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
  }

  private applyImmersiveSystemBars(enabled: boolean): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) return;
    window.getLastWindow(hostContext).then((lastWindow: window.Window): void => {
      if (enabled) {
        void lastWindow.setWindowLayoutFullScreen(true);
        void lastWindow.setSpecificSystemBarEnabled('navigation', false, true);
        void lastWindow.setSpecificSystemBarEnabled('navigationIndicator', false, true);
        void lastWindow.setWindowSystemBarProperties({
          // 必须用透明：写不透明色等于给状态栏刷一块固定底色，浅色模式下顶部会是一条黑边。
          statusBarColor: FieldwatchPaletteHolder.get().transparent,
          navigationBarColor: FieldwatchPaletteHolder.get().transparent,
          statusBarContentColor: FieldwatchPaletteHolder.get().headerText,
          navigationBarContentColor: FieldwatchPaletteHolder.get().headerText,
          enableStatusBarAnimation: true,
          enableNavigationBarAnimation: true
        });
      } else {
        void lastWindow.setSpecificSystemBarEnabled('navigation', true, true);
        void lastWindow.setSpecificSystemBarEnabled('navigationIndicator', true, true);
        void lastWindow.setWindowLayoutFullScreen(false);
      }
    }).catch((): void => {});
  }

  /**
   * 启动扫描。
   * 已有扫描能力就直接启动；没有则**不自动弹系统权限窗**，
   * 由实时页的受限卡片引导用户主动开启（应用商店要求：请求前先说明用途）。
   */
  /**
   * 冷启动的缺失权限提醒（仅非首次启动）。
   * 权限齐全时不打扰；缺扫描能力时说明缺哪些，并让用户选择去授权还是先用受限模式。
   */
  private promptMissingPermissions(): void {
    const snapshot: FieldwatchCapabilitySnapshot = fieldwatchApplication.permissionSnapshot();
    const missing: string[] = [];
    // 任一条扫描权限缺失就提醒：只用 canScan() 会在「Wi-Fi 已给、蓝牙没给」时漏报，
    // 而那种状态下 BLE 扫描其实一直在失败（201 Permission denied），用户却看不到任何提示。
    if (!snapshot.bluetooth) missing.push(this.permissionLabel(FieldwatchPermissionKind.BLUETOOTH));
    if (missing.length === 0) return;
    this.getUIContext().showAlertDialog({
      title: this.labelOf('app.string.fieldwatch_missing_title'),
      message: this.labelOf('app.string.fieldwatch_missing_body').replace('%s', missing.join('、')),
      primaryButton: {
        value: this.labelOf('app.string.fieldwatch_missing_later'),
        action: (): void => { this.announceRestrictedMode(); }
      },
      secondaryButton: {
        value: this.labelOf('app.string.fieldwatch_missing_grant'),
        action: (): void => { void this.grantMissingPermissions(); }
      }
    });
  }
  /** 用户拒绝授权：toast 说明当前处于哪种工作模式。 */
  private announceRestrictedMode(): void {
    const snapshot: FieldwatchCapabilitySnapshot = fieldwatchApplication.permissionSnapshot();
    logger.info('FieldwatchMode', '受限模式提示: ' + this.modeName(snapshot));
    this.getUIContext().getPromptAction().showToast({
      message: this.labelOf('app.string.fieldwatch_mode_prefix') + this.modeName(snapshot),
      duration: 2600
    });
  }
  /** 当前工作模式的可读名称。 */
  private modeName(snapshot: FieldwatchCapabilitySnapshot): string {
    // Wi-Fi 信息由系统自动授予、始终可用，所以只有两个状态。
    if (snapshot.bluetooth) return this.labelOf('app.string.fieldwatch_mode_full');
    return this.labelOf('app.string.fieldwatch_mode_wifi');
  }
  /** 同意授权：逐条申请缺失的扫描权限；全部结束后按结果给反馈。 */
  private async grantMissingPermissions(): Promise<void> {
    if (fieldwatchApplication.permissionSnapshot().bluetooth) {
      this.bleMissing = false;
      return;
    }
    await fieldwatchApplication.requestPermission(FieldwatchPermissionKind.BLUETOOTH);
    const after: FieldwatchCapabilitySnapshot = fieldwatchApplication.permissionSnapshot();
    this.bleMissing = after.bleUnavailable();
    if (after.bluetooth) {
      fieldwatchApplication.startScan();
      this.refreshView();
      return;
    }
    // 系统已把权限标记为「用户已决定」，不会再弹窗，必须引导到系统设置手动开启。
    fieldwatchApplication.openAppPermissionSettings((): void => {
      this.announceRestrictedMode();
    });
  }
  private permissionLabel(kind: FieldwatchPermissionKind): string {
    const spec: FieldwatchPermissionSpec | undefined = fieldwatchApplication.permissionSpec(kind);
    return spec === undefined ? '' : this.labelOf(spec.titleKey);
  }
  private labelOf(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }
  private async startScan(): Promise<void> {
    // 无条件启动扫描：Wi-Fi 信息由系统自动授予、始终可用，
    // 扫描能力不受任何权限门控。BLE 被拒时只是少了 BLE 那一半，
    // 用权限去 gate 整个 startScan 会把本来可用的 Wi-Fi 扫描也一起掐掉。
    fieldwatchApplication.startScan();
    this.refreshView();
  }

  private refreshView(): void {
    // 快捷方式 / 卡片点击带进来的目标标签页。
    //
    // 放在 1 秒刷新里消费，而不是只在 `aboutToAppear`：
    // 应用**已经在前台**时再点快捷方式走的是 `onNewWant`，页面不会重建，
    // 只认 aboutToAppear 会「点了没反应」。
    const pendingTab: number = fieldwatchApplication.consumePendingTab();
    if (pendingTab >= 0 && pendingTab !== this.selectedTab) this.switchTab(pendingTab);
    // 卡片点击带进来的**路由**（关注列表是压栈页面，不是标签页）。
    const pendingRoute: string = fieldwatchApplication.consumePendingRoute();
    if (pendingRoute.length > 0) {
      const names: string[] = this.pathStack.getAllPathName();
      const alreadyOpen: boolean = names.length > 0 && names[names.length - 1] === pendingRoute;
      // 已经在栈顶就不再压一次：卡片连点两下会堆出两层同样的页面。
      if (!alreadyOpen && pendingRoute === FieldwatchRouteName.WATCHLIST) this.openWatchlist();
    }
    // 深度链接（`airwavefootprints://…`）。与上面同一个理由：
    // 应用在前台时点链接走 `onNewWant`，页面不重建，只认 aboutToAppear 会「点了没反应」。
    const deepLink: FieldwatchDeepLink | undefined = fieldwatchDeepLinkBridge.consumePending();
    if (deepLink !== undefined && deepLink.kind === FieldwatchDeepLinkKind.FEEDBACK) {
      const names2: string[] = this.pathStack.getAllPathName();
      const onTop: boolean = names2.length > 0 && names2[names2.length - 1] === FieldwatchRouteName.FEEDBACK;
      // 已经在反馈中心时只更新目标条目，不再压一层。
      this.feedbackIssueNumber = deepLink.issueNumber;
      this.feedbackCreateMode = deepLink.createMode;
      this.feedbackCreateMode = deepLink.createMode;
      if (!onTop) this.openFeedback();
    }
    const state = fieldwatchApplication.getState();
    this.deviceCount = state.sightings.length;
    this.logCount = state.logs.length;
    this.wifiPhase = state.wifiSnapshot.phase;
    this.wifiResultCount = state.wifiSnapshot.resultCount;
    this.wifiFresh = state.wifiSnapshot.fresh;
    this.wifiNextAttemptAt = state.wifiSnapshot.nextAttemptAt;
    this.wifiErrorMessage = state.wifiSnapshot.errorMessage;
    this.scanIntensity = state.settings.scanIntensity;
    // 主题由平台门面持有，必须主动读回来 —— 否则三个按钮永远显示不出选中态。
    this.themeOverride = themeModeName(ngfThemeManagerFacade.getCurrentTheme());
    this.activeSitName = state.activeSit === undefined ? '' : state.activeSit.name;
    this.savedSitCount = state.savedSits.length;
    this.liveMode = this.readLiveMode(state.settings.liveMode);
    this.bleMissing = fieldwatchApplication.permissionSnapshot().bleUnavailable();
    this.nearLinkMissing = fieldwatchApplication.nearLinkAvailable()
      && !fieldwatchApplication.permissionSnapshot().nearlink;
  }

  /** 从设备详情启动 Hunt：先建立会话，再进入搜寻页。 */
  private startHunt(deviceKey: string): void {
    const sighting: Sighting | undefined = fieldwatchApplication.getState().sightings.find((item: Sighting): boolean => item.key === deviceKey);
    if (sighting === undefined) return;
    fieldwatchApplication.startHunt(sighting);
    this.pathStack.pushPathByName(FieldwatchRouteName.HUNT, new FieldwatchHuntParam(deviceKey));
  }

  /**
   * 横屏下把特征详情压进右侧分栏。
   *
   * 与 `openSignatureEditor` 同一个道理：**先切分栏、再压栈**，
   * 否则右栏会先以 Stack 占满全屏再被推过去（读作「先闪一下再跑到右边」）。
   */
  private openSignatureDetail(fleetId: string): void {
    this.subPageOpen = true;
    this.pathStack.pushPathByName(FieldwatchRouteName.SIGNATURE_DETAIL, fleetId);
  }

  /**
   * 打开关注列表（横屏进右栏，竖屏整页）。
   *
   * 与 `openSignatureDetail` 同一个道理：**先切分栏、再压栈**，
   * 否则右栏会先以 Stack 占满全屏再被推过去。
   */
  /** 继续当前 Hunt：只压栈，**不重启会话**（重启会清空已有样本）。 */
  private openHunt(): void {
    this.subPageOpen = true;
    this.pathStack.pushPathByName(FieldwatchRouteName.HUNT, null);
  }

  private openWatchlist(): void {
    this.subPageOpen = true;
    this.pathStack.pushPathByName(FieldwatchRouteName.WATCHLIST, '');
  }

  private openSignatureEditor(fleetId: string, deviceKey: string): void {
    // 诊断：这条路径曾经「点了没反应」—— 因为调用方漏传 `onEditFleet`，
    // 默认的空函数把点击吃掉了，且**没有任何日志**，只能靠肉眼猜。
    // 打出「谁触发的、带什么参数、栈深变化」，下次一眼可判。
    const before: number = this.pathStack.size();
    // **先切分栏、再压栈**（与 `openSubPage` 同一个道理）。
    //
    // 顺序反过来的话，编辑器会先以 Stack 占满全屏，随后左栏出现把它推向右 ——
    // 那读作「先在左边闪现、再跑到右边」（实测反馈）。
    // 先把分栏边界立好（模式切换动画已关闭，是瞬间的），
    // 编辑器就只会在自己那一栏里滑入。
    // 竖屏下这个标志不参与模式判断，无副作用。
    this.subPageOpen = true;
    this.pathStack.pushPathByName(FieldwatchRouteName.SIGNATURE_EDITOR,
      new FieldwatchSignatureEditorParam(fleetId, deviceKey));
    logger.info('FieldwatchSignatures', '打开特征编辑器: fleetId=「' + fleetId + '」 deviceKey=「' + deviceKey
      + '」 栈深 ' + before.toString() + ' -> ' + this.pathStack.size().toString());
  }

  /** 深浅色翻转后系统栏内容色必须重算，否则浅色下仍是白色图标。 */
  onDarkModeChanged(): void { this.applyImmersiveSystemBars(true); }

  private readLiveMode(value: string): FieldwatchLiveMode {
    if (value === FieldwatchLiveMode.STRENGTH) return FieldwatchLiveMode.STRENGTH;
    if (value === FieldwatchLiveMode.TIMELINE) return FieldwatchLiveMode.TIMELINE;
    if (value === FieldwatchLiveMode.CLASS) return FieldwatchLiveMode.CLASS;
    return FieldwatchLiveMode.RADAR;
  }

  build() {
    HdsNavigation(this.pathStack) {
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({ spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night, FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().panel2, FieldwatchPaletteHolder.get().accentActive, FieldwatchPaletteHolder.get().accent, PAGE_UNDERLAY_HEIGHT) })
        if (this.isLandscape) {
          this.buildLandscapeLayout()
        } else {
          this.buildPhoneLayout()
        }
        if (this.showOnboarding) {
          FieldwatchOnboardingPage({
            onFinish: (): void => {
              this.showOnboarding = false;
                      void this.startScan();
            }
          })
        }
      }
      .width('100%').height('100%')
    }
    // **用系统 Split，不要自绘分栏。**
    //
    // 曾经为了控制「入场方向」和「雷达闪烁」自绘过一套 `Row` 分栏，
    // 结果连带丢掉了 Split **自带**的三项能力：拖拽调整比例、状态栏避让、
    // 以及返回手势。为了两个可控项丢三个自带项，是亏的。
    //
    // 真正该修的是那两处根因（见 `openDeviceDetail` 与 `syncRadarSize`），
    // 而不是换掉容器。
    .mode(this.isLandscape && this.subPageOpen ? NavigationMode.Split : NavigationMode.Stack)
    /**
     * **关掉模式切换时的栏宽重排动画。**
     *
     * 开着的时候，切 Split 会让左栏宽度从 100% 连到 67% ——
     * 边界一路扫过去，观感就是「详情从左边闪出来跑到右边」（两轮反馈都是这个）。
     * 关掉后边界瞬间落位，屏幕上只剩压栈本身那一次从右滑入。
     */
    .enableModeChangeAnimation(false)
    // 详情宽度 = 实时宽度的 50% -> 实时 2/3、详情 1/3（仍可拖拽）。
    .navBarWidth('67%')
    .navBarWidthRange({ minWidth: '40%', maxWidth: '80%' })
    .navDestination(this.buildNavDestination)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }

  @Builder
  private buildNavDestination(name: string, param: Object): void {
    if (name === FieldwatchRouteName.DEVICE_DETAIL) FieldwatchDeviceDetailPage({ detailKey: String(param), pathStack: this.pathStack });
    else if (name === FieldwatchRouteName.SIT_DETAIL) FieldwatchReportsPage();
    else if (name === FieldwatchRouteName.EXPORT) FieldwatchReportsPage();
    else if (name === FieldwatchRouteName.SIGNATURE_CATALOG) {
      FieldwatchSignaturesPage({ landscape: this.isLandscape, onEditFleet: (fleetId: string, deviceKey: string): void => { this.openSignatureEditor(fleetId, deviceKey); }, onOpenDetail: (fleetId: string): void => { this.openSignatureDetail(fleetId); }, followTick: this.followTick, onOpenWatchlist: (): void => { this.openWatchlist(); } });
    } else if (name === FieldwatchRouteName.HUNT) {
      FieldwatchHuntPage({ onClose: (): void => { this.pathStack.pop(); } });
    } else if (name === FieldwatchRouteName.SIGNATURE_DETAIL) {
      // 横屏右栏的特征详情：与竖屏 sheet 共用同一个内容组件。
      FieldwatchSignatureDetail({
        fleetId: String(param),
        withShell: true,
        topInset: this.topInsetVp,
        onEdit: (fleetId: string): void => { this.openSignatureEditor(fleetId, ''); },
        onClose: (): void => { this.pathStack.pop(); },
        // 横屏分栏时列表与详情是**两个组件实例**，关注变化必须经外层转发，
        // 否则左栏的「已关注」要等下次进页面才更新。
        onFollowChanged: (): void => { this.followTick += 1; }
      });
    } else if (name === FieldwatchRouteName.WATCHLIST) {
      // 横屏右栏的关注列表：与竖屏整页共用同一个内容组件。
      FieldwatchWatchlistPage({
        withShell: true,
        topInset: this.topInsetVp,
        onClose: (): void => { this.pathStack.pop(); }
      });
    } else if (name === FieldwatchRouteName.FEEDBACK) {
      FieldwatchFeedbackPage({
        withShell: true,
        topInset: this.topInsetVp,
        openIssueNumber: this.feedbackIssueNumber,
        openCreate: this.feedbackCreateMode,
        onClose: (): void => { this.pathStack.pop(); }
      });
    } else if (name === FieldwatchRouteName.SIGNATURE_EDITOR) {
      FieldwatchSignatureEditorPage({ fleetId: (param as FieldwatchSignatureEditorParam).fleetId, fromDeviceKey: (param as FieldwatchSignatureEditorParam).fromDeviceKey, topInset: this.topInsetVp, onClose: (): void => { this.pathStack.pop(); } });
    }
  }

  @Builder
  private buildPhoneLayout() {
    HdsTabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() { FieldwatchLivePage({ visible: this.selectedTab === 0, savedLiveMode: this.liveMode, onCreateSignature: (deviceKey: string): void => { this.openSignatureEditor('', deviceKey); }, onStartHunt: (deviceKey: string): void => { this.startHunt(deviceKey); }, onOpenDetail: (deviceKey: string): void => { this.openDeviceDetail(deviceKey); } }) }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_live'), 'sys.symbol.scope', 0))
      TabContent() { FieldwatchFiltersPage({ topInset: this.topInsetVp }) }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_filters'), 'sys.symbol.line_3_horizontal', 1))
            // `onEditFleet` 必须传：它的默认值是空函数，漏传就变成「点了没反应」。
      TabContent() { FieldwatchSignaturesPage({ embedded: true, landscape: this.isLandscape,
        onEditFleet: (fleetId: string, deviceKey: string): void => { this.openSignatureEditor(fleetId, deviceKey); },
        onOpenDetail: (fleetId: string): void => { this.openSignatureDetail(fleetId); }, onOpenWatchlist: (): void => { this.openWatchlist(); }, pageVisible: this.selectedTab === 2 })
      }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_signatures'), 'sys.symbol.dot_radiowaves_left_and_right', 2))
      TabContent() { FieldwatchReportsPage({ topInset: this.topInsetVp }) }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_reports'), 'sys.symbol.doc_text', 3))
      TabContent() { FieldwatchToolboxPage({ topInset: this.topInsetVp, onStartHunt: (deviceKey: string): void => { this.startHunt(deviceKey); }, onOpenHunt: (): void => { this.openHunt(); } }) }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_toolbox'), 'sys.symbol.wrench_and_screwdriver', 4))
      TabContent() { FieldwatchSettingsPage({ topInset: this.topInsetVp, onOpenSignatures: (): void => { this.pathStack.pushPathByName(FieldwatchRouteName.SIGNATURE_CATALOG, null); }, onOpenFeedback: (): void => { this.feedbackIssueNumber = 0; this.openFeedback(); }, onReplayOnboarding: (): void => { this.showOnboarding = true; } }) }.tabBar(this.buildTabItem($r('app.string.fieldwatch_tab_settings'), 'sys.symbol.gearshape', 5))
    }
    .width('100%').height('100%').backgroundColor(FieldwatchPaletteHolder.get().night).barMode(BarMode.Fixed).barOverlap(true).barFloatingStyle({ adaptToHandedness: true, systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.EXQUISITE }, thermoCtrl: true, barOpacity: 0.94, barBottomMargin: this.bottomInsetVp })
    .onChange((index: number): void => { this.selectedTab = index; })
    /** 再兜一次：布局树重建的时机由框架决定，`onAppear` 是最可靠的落点。 */
    .onAppear((): void => { this.syncTabsToSelected(); })
    // 实时页（tab 0）**禁用左右滑动切页**：把水平滑动让给雷达本身，
    // 于是单指拖动可以直接当作平移，不再需要和 Tabs 抢手势、也不用手势冲突计算。
    // 其它页仍保留滑动切页。切页统一走底栏。
    .scrollable(this.selectedTab !== 0)
  }

  /**
   * 横屏平板：HDS 侧栏容器。
   *
   * 此前是手写的 `Column` + 裸 `Button`，有三个问题：
   *  ① 选项**顶部对齐**，下方用 `Blank()` 把设备数顶到底部 —— 视觉重心偏上；
   *  ② **不能收起**，横屏下白白占掉 156vp；
   *  ③ 自己拼的样式拿不到 HDS 的收起动画、毛玻璃与拖拽阈值。
   * 改用 `HdsSideBar`：收起按钮、动画、材质都由组件提供，
   * 四个选项在 `sideBarPanelBuilder` 里**上下各留一个 Blank 实现垂直居中**。
   */
  /**
   * 横屏平板：紧凑导航栏 + 内容区。
   *
   * 设计要点（对照此前的实现）：
   *  ① **窄**：展开 164vp / 收起 64vp（此前是 HdsSideBar 的 168vp 起 + 笨重按钮）；
   *  ② **选中态用「左侧竖条 + 淡色药丸」**，而不是整块高饱和填充 ——
   *     整块填充在深色底上非常刺眼，且四个按钮一样重，看不出层级；
   *  ③ **收起按钮固定在底部**，用 chevron 朝向表达「会往哪边收」；
   *  ④ 图标 + 文字在收起时只留图标，宽度用 `animateTo` 过渡，不跳变。
   */
  @Builder
  private buildLandscapeLayout() {
    Row() {
      this.buildNavRail()
      Column() { this.buildSideContent() }.layoutWeight(1).height('100%')
    }.width('100%').height('100%')
  }

  /** 导航栏。四个选项在高度中央，设备数与收起按钮在底部。 */
  @Builder
  private buildNavRail() {
    Column({ space: 4 }) {
      Blank()
      // 顺序与竖屏底部标签栏一致（实时 / 筛选 / 特征库 / 记录 / 设置）。
      // **特征库原先只在竖屏标签栏里有，横屏侧栏漏了** ——
      // 横屏用户根本进不去（实测反馈）。两处顺序必须对齐，
      // 否则同一个人在两种握持下会看到两套导航。
      this.buildRailItem($r('app.string.fieldwatch_tab_live'), 'sys.symbol.scope', 0)
      this.buildRailItem($r('app.string.fieldwatch_tab_filters'), 'sys.symbol.line_3_horizontal', 1)
      // symbol 与竖屏底部标签栏用同一个（`dot_radiowaves_left_and_right`）——
      // 两种握持下同一个功能应当长得一样。
      this.buildRailItem($r('app.string.fieldwatch_tab_signatures'), 'sys.symbol.dot_radiowaves_left_and_right', 2)
      this.buildRailItem($r('app.string.fieldwatch_tab_reports'), 'sys.symbol.doc_text', 3)
      // 工具箱与设置同样**两处都要有**：本文件上方已经因为「特征库只在竖屏有」踩过一次，
      // 横屏用户进不去（实测反馈）。新增标签页时竖屏底栏与横屏侧栏必须同时改。
      this.buildRailItem($r('app.string.fieldwatch_tab_toolbox'), 'sys.symbol.wrench_and_screwdriver', 4)
      this.buildRailItem($r('app.string.fieldwatch_tab_settings'), 'sys.symbol.gearshape', 5)
      Blank()
      if (this.railExpanded) {
        Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.live_devices_label'))
          + ' ' + this.deviceCount.toString())
          .fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
          .width('100%').textAlign(TextAlign.Center).maxLines(1)
          .padding({ bottom: 4 })
      }
      this.buildRailToggle()
    }
    .width(this.railExpanded ? 164 : 64)
    .height('100%')
    .padding({ left: 8, right: 8, top: 20, bottom: 16 })
    .backgroundColor($r('app.color.background_secondary'))
  }

  /** 导航项：选中时左侧竖条 + 淡色药丸，未选中只有图标与暗色文字。 */
  @Builder
  private buildRailItem(label: ResourceStr, symbol: string, index: number) {
    Row({ space: 10 }) {
      // 选中竖条：3vp 宽，给出一眼可辨的锚点，又不用整块填充。
      // **收起时隐藏** —— 那时整行居中，一条贴左的竖条会破坏对称，
      // 而且此时「选中」已由图标与药丸底色表达，不需要再叠一层。
      if (this.railExpanded) {
        Column().width(3).height(18).borderRadius(2)
          .backgroundColor(index === this.selectedTab ? FieldwatchPaletteHolder.get().accent : Color.Transparent)
      }
      SymbolGlyph($r(symbol)).fontSize(21)
        .fontColor([index === this.selectedTab ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
      if (this.railExpanded) {
        Text(label).fontSize(14).maxLines(1).layoutWeight(1)
          .fontColor(index === this.selectedTab ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().text)
      }
    }
    .width('100%').height(46).borderRadius(11)
    // 收起时只有图标：整行居中，图标才会落在中轴上（展开时靠 padding 控左对齐）
    .justifyContent(this.railExpanded ? FlexAlign.Start : FlexAlign.Center)
    .padding({ left: this.railExpanded ? 6 : 0, right: this.railExpanded ? 10 : 0 })
    .backgroundColor(index === this.selectedTab ? FieldwatchPaletteHolder.get().accent + '1F' : Color.Transparent)
    .onClick((): void => { this.switchTab(index); })
  }

  /**
   * 切换主页面，**带方向感知的过渡**。
   *
   * 原先直接 `this.selectedTab = index`，内容「啪」地换掉。
   * 而且换向没有区别 —— 从左往右切和从右往左切看起来一样，
   * 用户会失去「我在这一排里往哪个方向移动」的感觉。
   *
   * 方向取**新旧索引之差**：往右切时新页面从右侧进入、旧页面向左退出，
   * 反之亦然。位移量取 24vp（小位移 + 淡入淡出比整屏平移更轻）。
   */
  private switchTab(index: number): void {
    if (index === this.selectedTab) return;
    // 前进为正：新页面从右边来。
    this.tabSlide = index > this.selectedTab ? 1 : -1;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.selectedTab = index;
    });
  }

  /**
   * 收起 / 展开。**纯图标，不带文字** ——
   * chevron 的朝向本身已经说明「会往哪边收」，再加一行字反而抢视线。
   * 图标用 `layoutWeight` 之外的方式居中：整行 `justifyContent` 居中，
   * 这样展开与收起两种宽度下图标都落在视觉中轴上。
   */
  @Builder
  private buildRailToggle() {
    Row() {
      SymbolGlyph($r(this.railExpanded ? 'sys.symbol.chevron_left' : 'sys.symbol.chevron_right'))
        .fontSize(20).fontColor([FieldwatchPaletteHolder.get().textDim])
    }
    .width('100%').height(42).borderRadius(10)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
        this.railExpanded = !this.railExpanded;
      });
    })
  }

  /** 内容区：按当前选中项切换页面。 */
  @Builder
  private buildSideContent() {
    Column() {
      // **索引必须与竖屏 `TabContent` 的顺序逐一对应**：
      // 0 实时 / 1 筛选 / 2 特征库 / 3 记录 / 4 设置。
      // 上一轮只加了侧栏入口、没加这里的分支 —— 于是点特征库看到的是记录、
      // 点记录看到的是设置（实测反馈）。**入口与内容必须同时改。**
      if (this.selectedTab === 0) FieldwatchLivePage({ savedLiveMode: this.liveMode, onCreateSignature: (deviceKey: string): void => { this.openSignatureEditor('', deviceKey); }, onStartHunt: (deviceKey: string): void => { this.startHunt(deviceKey); }, onOpenDetail: (deviceKey: string): void => { this.openDeviceDetail(deviceKey); } }).width('100%').height('100%')
      else if (this.selectedTab === 1) FieldwatchFiltersPage({ topInset: this.topInsetVp, twoColumn: this.twoColumnTabs() }).width('100%').height('100%')
      // 同上：`onEditFleet` 漏传会让「新建」「编辑」两个按钮都变成空操作。
      else if (this.selectedTab === 2) FieldwatchSignaturesPage({ embedded: true, twoColumn: this.twoColumnTabs(), landscape: this.isLandscape,
        onEditFleet: (fleetId: string, deviceKey: string): void => { this.openSignatureEditor(fleetId, deviceKey); },
        onOpenDetail: (fleetId: string): void => { this.openSignatureDetail(fleetId); },
        onOpenWatchlist: (): void => { this.openWatchlist(); },
        pageVisible: true
      }).width('100%').height('100%')
      else if (this.selectedTab === 3) FieldwatchReportsPage({ topInset: this.topInsetVp, twoColumn: this.twoColumnTabs() }).width('100%').height('100%')
      else if (this.selectedTab === 4) FieldwatchToolboxPage({ topInset: this.topInsetVp, twoColumn: this.twoColumnTabs(), onStartHunt: (deviceKey: string): void => { this.startHunt(deviceKey); }, onOpenHunt: (): void => { this.openHunt(); } }).width('100%').height('100%')
      else FieldwatchSettingsPage({ topInset: this.topInsetVp, twoColumn: this.twoColumnTabs(), onOpenSignatures: (): void => { this.pathStack.pushPathByName(FieldwatchRouteName.SIGNATURE_CATALOG, null); }, onOpenFeedback: (): void => { this.feedbackIssueNumber = 0; this.openFeedback(); }, onReplayOnboarding: (): void => { this.showOnboarding = true; } }).width('100%').height('100%')
    }.width('100%').height('100%')
    /**
     * **切换过渡（方向感知）。**
     *
     * 新页面按切换方向从侧边滑入、旧页面只淡出：
     * 进入带位移说明「从哪来」，退出不抢视线。
     * 位移方向由 `switchTab` 写入的 `tabSlide` 决定 ——
     * 往右切时新页面从右边进，反之亦然。
     */
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ x: this.tabSlide * 24 }))
        .animation({ duration: 220, curve: Curve.FastOutSlowIn }),
      TransitionEffect.opacity(0).animation({ duration: 140, curve: Curve.FastOutSlowIn })
    ))
  }



  @Builder
  private buildTabItem(title: ResourceStr, symbol: string, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph($r(symbol)).fontSize(index === this.selectedTab ? 23 : 21)
        .fontColor([index === this.selectedTab ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
      Text(title).fontSize(11)
        .fontColor(index === this.selectedTab ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
        .fontWeight(index === this.selectedTab ? FontWeight.Medium : FontWeight.Normal)
    }.width('100%').padding({ top: 6, bottom: 6 })
  }

}

@Component
struct FieldwatchLivePage {
  onCreateSignature: (deviceKey: string) => void = (): void => {};
  onStartHunt: (deviceKey: string) => void = (): void => {};
  /** 打开设备详情页；由根页面提供（Live 页自己没有 NavPathStack）。 */
  onOpenDetail: (deviceKey: string) => void = (deviceKey: string): void => {};
  @State private mode: FieldwatchLiveMode = FieldwatchLiveMode.RADAR;
  @State private sightings: Sighting[] = [];
  @State private radarAngle: number = 0;
  @State private displayPaused: boolean = false;
  @State private topInsetVp: number = 0;
  /** 是否具备扫描能力（蓝牙或 Wi-Fi 任一授权）。 */
  /** BLE 不可用（系统设置里的「设备发现和连接」未开启）。 */
  @State private bleMissing: boolean = true;
  /** 星闪权限未授予（设备支持星闪时才可能为真）。 */
  @State private nearLinkMissing: boolean = false;
  @State private permissionBusy: boolean = false;
  /**
   * §12.1「显示扫描错误、扫描器不可用和系统节流状态」。
   *
   * 此前**两条错误通道都采集了却从不显示**：
   *   - `state.errorMessage`（应用层，BLE 扫描回调写入）
   *   - `state.wifiSnapshot.errorMessage`（radio 快照）
   * 用户遇到扫描失败时页面上没有任何反馈，只能看到雷达静静地不动。
   */
  @State private scanErrorText: string = '';
  private timer: number = -1;
  private sweepTimer: number = -1;
  /** 雷达点位（供 ArkUI 图标层渲染设备类型图标）。 */
  @State private radarPoints: Array<FieldwatchRadarPoint> = [];
  /**
   * **雷达的动画尺寸** —— 全部几何与图标定位都用它，而不是容器的实时尺寸。
   *
   * 为什么需要它：雷达的圆心、半径、每个信号点的位置都是按 `min(w,h)` 算的。
   * 分栏开合时容器宽度突变，如果用实时尺寸，所有点位会**在同一帧跳到新位置** ——
   * 看起来就是「整个雷达被平移了一下」，没有任何过渡。
   *
   * 改成让这一对值**逐帧缓动**追上真实尺寸，画布与图标就作为一体平滑变化，
   * 并且缓动结束时正好等于真实尺寸，不留偏差。
   */
  @State private animW: number = 0;
  @State private animH: number = 0;
  /** 尺寸缓动的帧定时器；-1 表示当前没有在动。 */
  private sizeTimer: number = -1;
  /** 图标尺寸（vp），可在设置里调整。 */
  @State private radarIconSize: number = 26;
  /** 标签字号（vp）与要显示的字段，可在设置里调整。 */
  @State private radarLabelFontSize: number = 12;
  @State private radarLabelFields: string = 'name,rssi';
  // ── 列表显示的四个开关（§12.2 显示设置）──
  // 与上面的 `radarLabelFields` 不是一回事：那只管**雷达标签**，
  // 这四个管**列表行**（强度/时间线/分类视图）里的元素。
  @State private showRssiBar: boolean = true;
  @State private showFleetName: boolean = true;
  @State private showFrequency: boolean = true;
  @State private showSeenTimes: boolean = true;
  /** 列表行是否紧凑（四个视图共用同一套行样式，这里只切换尺寸档）。 */
  @State private compactRows: boolean = false;
  /** 雷达容器实测尺寸（vp）—— 图标定位必须用同一套坐标系，否则会漂移。 */
  @State private radarW: number = 0;
  @State private radarH: number = 0;
  /** 雷达缩放；放大后才显示更多信号。 */
  @State private radarZoom: number = 1;
  /** 视图平移（vp）—— 像地图一样可以整体移动。 */
  @State private radarOffsetX: number = 0;
  @State private radarOffsetY: number = 0;
  /** 手势基准值。 */
  private radarZoomBase: number = 1;
  private radarOffsetXBase: number = 0;
  private radarOffsetYBase: number = 0;
  /** 平移手势是否进行中，用于忽略抬手后的迟到 update。 */
  private radarPanActive: boolean = false;
  /** 捏合焦点（vp），缩放围绕它进行。 */
  private radarFocalX: number = 0;
  private radarFocalY: number = 0;
  /** 信号 → 强度排名，决定各自的显现阈值。 */
  private radarRank: Map<string, number> = new Map();
  /** 本页当前是否可见；不可见时停掉全部定时器。 */
  @Prop @Watch('onVisibilityChanged') visible: boolean = true;
  /**
   * 上次退出时使用的实时模式。
   *
   * 模式切换一直会持久化（`updateLiveMode`），但**此前没人把它读回来** ——
   * 根页面读进了自己的 `liveMode` 字段，实时页却用自己的 `mode`，两者互不相通，
   * 结果就是「设置了实时模式，重启后总是回到雷达」。
   */
  @Prop savedLiveMode: FieldwatchLiveMode = FieldwatchLiveMode.RADAR;
  /** 力导向聚类后的显示节点（单点或聚合气泡）。 */
  @State private radarNodes: Array<FieldwatchRadarNode> = [];
  /** 当前展开成员列表的气泡 key。 */
  @State private clusterKey: string = '';
  /** 分类视图中已展开的类别（存显示名，类别是枚举，直接用字符串键更简单）。 */
  @State private expandedClasses: string[] = [];
  /**
   * 分类视图的筛选：false = 显示全部类别，true = 仅显示有结果的类别。
   *
   * 默认**关闭**（显示全部）—— 默认就把空类别藏起来会让用户以为
   * 某些类别不存在；先看到全集，再自己决定要不要折叠。
   */
  @State private classOnlyHits: boolean = false;
  /** 详情页「自定义名称」输入的草稿。 */
  @State private detailNameDraft: string = '';
  /** 详情页「观察者备注」输入的草稿。 */
  @State private detailNotesDraft: string = '';
  /** 备注编辑区是否展开；默认收起，避免详情页被两个输入框占满。 */
  @State private detailEditOpen: boolean = false;
  /** 已被聚合的成员 key（竖线分隔），用于单点层过滤。 */
  @State private clusteredKeys: string = '|';
  /**
   * **放不下标签、降级为小圆点**的点（竖线包裹的键串）。
   *
   * 拥挤时标签本来就放不下 —— 原来只是不画标签，图标照旧，
   * 结果是一堆大图标互相压着。降级成小圆点后同样的空间能显示多得多，
   * 而且每个点仍然保留自己的颜色（种类与强度语义不丢）。
   */
  @State private dotKeys: string = '|';
  /** 顶部浮层的实测高度（vp）：五个视图据此避让，不遮挡。 */
  @State private liveHeaderH: number = 0;
  /** 聚合气泡相对普通图标的额外尺寸（vp）。 */
  private readonly clusterExtraSize: number = 20;
  /** 标签排布结果，`drawRadar` 与图标层共用同一份，避免两处判断不一致。 */
  private labelPlan: RadarLabelPlan = new RadarLabelPlan();
  private canvasReady: boolean = false;
  private readonly context: CanvasRenderingContext2D = new CanvasRenderingContext2D();

  aboutToAppear(): void {
    this.readTopInset();
    // 恢复上次的实时模式，再开始刷新，避免先渲染一帧雷达再跳走。
    this.mode = this.savedLiveMode;
    this.refresh();
    this.startTimers();
  }
  /**
   * 启动本页的两个定时器。
   *
   * **必须在页面不可见时停掉**：Tabs 的所有 TabContent 都会构建，
   * 定时器不会因为「切到别的页」而自动停 —— 之前 16ms 的扫描线动画和 1s 数据刷新
   * 在任何页面都一直跑，是滑动卡顿的主要原因之一。
   */
  private startTimers(): void {
    if (!this.visible) return;
    // 1 秒的数据刷新保留：它同时充当「回到前台」的探测器。
    // 16ms 的重绘则必须同时满足「标签页可见」与「应用在前台」——
    // 退到后台仍按 60fps 重绘会让 CPU 占到 106%、堆每分钟涨 14 MB。
    if (this.timer < 0) this.timer = setInterval((): void => { this.refresh(); }, 1000);
    if (!fieldwatchApplication.isAppForeground()) { this.stopSweepTimer(); return; }
    // 扫描动画走独立的 60fps 计时器：
    // 原来角度挂在 1 秒的数据刷新上，等于每秒跳一格，看起来是机械扫描。
    if (this.sweepTimer < 0) this.sweepTimer = setInterval((): void => { this.advanceSweep(); }, 16);
  }
  private stopTimers(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.sizeTimer >= 0) { clearInterval(this.sizeTimer); this.sizeTimer = -1; }
    this.stopSweepTimer();
  }
  /** 只停重绘定时器，保留 1 秒数据刷新。 */
  private stopSweepTimer(): void {
    if (this.sweepTimer >= 0) { clearInterval(this.sweepTimer); this.sweepTimer = -1; }
  }
  /** @Watch 回调不能是 private。 */
  onVisibilityChanged(): void {
    if (this.visible) { this.refresh(); this.startTimers(); } else { this.stopTimers(); }
  }
  /** 每帧推进扫描角并重绘；用固定步长，转速与刷新率无关。 */
  private advanceSweep(): void {
    if (!this.canvasReady || this.mode !== FieldwatchLiveMode.RADAR) return;
    this.radarAngle = (this.radarAngle + 0.012) % (Math.PI * 2);
    this.drawRadar();
  }
  private readTopInset(): void {
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (hostContext === undefined || hostContext === null) return;
    window.getLastWindow(hostContext).then((lastWindow: window.Window): void => {
      const area: window.AvoidArea = lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInsetVp = uiContext.px2vp(area.topRect.height);
    }).catch((): void => { this.topInsetVp = 0; });
  }

  aboutToDisappear(): void { this.stopTimers(); }
  private refresh(): void {
    // ── 前台/后台判定必须放在最前面，且后台要**在任何 @State 赋值之前**返回 ──
    //
    // 之前把早退放在「赋值之后」，看起来省掉了雷达几何计算，实际上没挡住真正的开销：
    // 每秒都会执行 `this.sightings = <新数组>`，而 ArkUI 只看「引用变没变」——
    // 新数组一定被判定为脏，于是对全部条目重新 diff。
    // 实测后台状态下日志被 `AceForEach: ForEachNode skip mark dirty` 刷屏，
    // 伴生 `OS_GC_Thread` 约 14% 的持续 GC —— 每秒重建几百个元素的对象图，
    // 这些元素在后台根本没人看。
    //
    // 因此后台的正确做法是：除了「回到前台的探测」之外，什么都不做。
    if (!fieldwatchApplication.isAppForeground()) {
      this.stopSweepTimer();
      return;
    }
    // 回到前台：恢复 60fps 重绘（被停掉的定时器自己发现不了状态变化）。
    if (this.visible) {
      if (this.sweepTimer < 0) this.sweepTimer = setInterval((): void => { this.advanceSweep(); }, 16);
    } else if (this.sweepTimer >= 0) {
      this.stopSweepTimer();
    }
    const state = fieldwatchApplication.getState();
    const latest: Array<Sighting> = fieldwatchApplication.filteredSightings().slice();
    this.sightings = visibleSightingsAfterPause(state.settings.displayPaused, this.sightings, latest);
    this.displayPaused = state.settings.displayPaused;
    // **应用不在前台时不做雷达几何计算。**
    //
    // 这一段的成本随观测条数增长：`buildRadarPoints` + 逐环排序 +
    // `buildRadarNodes` 的力导向聚类，在几千条观测下每秒跑一次就能吃掉一整个核心。
    // 而应用在后台时这些节点根本不会被绘制 —— 纯属白烧 CPU 与电量。
    // 实测：只停扫描不停这段，后台 CPU 仍是 107%。
    //
    // 数据本身的刷新不能跳过（`sightings` 要跟上），只是不做几何重建；
    // 回到前台后的第一个 tick 会自动重算。
    // 到这里一定是前台（后台已在函数开头返回），几何计算无条件执行。
    {
      this.radarPoints = buildRadarPoints(this.sightings, state.signatures);
      this.rebuildRadarRank();
      // 力导向聚类：把「同一信号区间内聚集的同类设备」聚合成气泡，
      // 再对剩余单点做去重叠。
      //
      // 聚类的输入是**当前可见点集**（随缩放变化），所以缩放手势里
      // 也要通过 `rebuildRadarGeometry()` 重算，不能只在数据 tick 里做 ——
      // 否则放大后气泡与实际可见范围对不上。
      this.rebuildRadarGeometry();
    }
    // 权限状态每秒重新读一次：在系统设置里授予/撤销后，
    // 顶部的「设备发现和连接」提示必须自己更新，而不是停在启动时的快照。
    this.bleMissing = fieldwatchApplication.permissionSnapshot().bleUnavailable();
    this.nearLinkMissing = fieldwatchApplication.nearLinkAvailable()
      && !fieldwatchApplication.permissionSnapshot().nearlink;
    // §12.1：把两条错误通道合成一句可读提示（合并规则见 mergeScanError，有单测）。
    //
    // **Wi-Fi 侧优先用相位文案而不是扫描器的原始消息**：扫描器在 radio 层，
    // 拿不到 UI 上下文，它的消息是硬编码中文（`FieldwatchWifiScanner:169` 等），
    // 在 en_US 下不会翻译。而相位已经携带同样的条件，且 12 个相位现在都有
    // 本地化文案。只有相位无法解释（例如纯 API 报错落到 ERROR 以外的情形）时，
    // 才回退到原始消息，保证信息不丢。
    // **只有「需要用户处理」的相位才进异常横幅。**
    //
    // 横幅前面挂着「扫描异常：」，所以它必须只说**真的出了问题**的情况。
    // `SYSTEM_REJECTED`（系统限频）与 `WAITING_FOR_RETRY`（正在退避重试）是
    // 扫描的**正常节律** —— 系统本身就限制每应用几十秒一次，应用自己会重试成功。
    // 把它们报成「异常」，用户会以为程序坏了（实测就是这个反馈）。
    // 它们的真实状态在设置页的限频提示与倒计时里看得到，信息不丢。
    const wifiPhaseNow: string = state.wifiSnapshot.phase;
    const wifiPart: string = wifiPhaseNeedsAction(wifiPhaseNow)
      ? wifiPhaseLabel(this.getUIContext().getHostContext(), wifiPhaseNow)
      : '';
    this.scanErrorText = mergeScanError(state.errorMessage, wifiPart);
    // **应用不在前台时到此为止。**
    //
    // 下面这段每秒重建一个包含所有聚类成员键的大字符串（几千台设备约 250 KB）。
    // 后台时 `radarNodes` 不再重建、内容完全不变，于是每秒把同一个大字符串
    // 重新拼一遍 —— 实测后台 ark ts heap 以 17.7 MB/分单调增长（12 分钟 267→480 MB，
    // 无 GC 回落、无平台期），停扫与跳过几何之后依然如此。
    // 这个字符串只在雷达命中判定里用，后台既不绘制也不点击，纯属白分配。
    if (!fieldwatchApplication.isAppForeground()) return;
    let grouped: string = '|';
    this.radarNodes.forEach((node: FieldwatchRadarNode): void => {
      if (node.isCluster()) node.memberKeys.forEach((key: string): void => { grouped += key + '|'; });
    });
    this.clusteredKeys = grouped;
    // 每秒从设置同步一次：在设置页改完立刻生效，不需要重启 App。
    this.showRssiBar = state.settings.showRssiBar;
    this.showFleetName = state.settings.showFleetName;
    this.showFrequency = state.settings.showFrequency;
    this.showSeenTimes = state.settings.showSeenTimes;
    this.radarLabelFields = state.settings.radarLabelFields;
    this.radarLabelFontSize = state.settings.radarLabelFontSize;
    this.radarIconSize = state.settings.radarIconSize;
    this.compactRows = state.settings.listCompactRows;
    // 后台不重绘：画布不可见，绘制纯属浪费。
    if (this.canvasReady && fieldwatchApplication.isAppForeground()) this.drawRadar();
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      /**
       * 五个视图共用同一个避让容器。
       *
       * **顶部浮层的高度是可变的**：标题、统计行、权限卡、扫描异常横幅、
       * 视图切换条，任意一项出现/消失都会改变它。
       * 各视图原来都铺满整高，于是浮层直接压住内容（实测反馈）。
       * 这里让容器按**实测的浮层高度**留出内边距，五个视图一次性都对。
       */
      Column() {
        if (this.mode === FieldwatchLiveMode.RADAR) this.buildRadar()
        else if (this.mode === FieldwatchLiveMode.CLASS) this.buildClassList()
        else if (this.mode === FieldwatchLiveMode.TRAIL) this.buildTrailList()
        else this.buildList()
      }
      .width('100%').height('100%')
      .padding({ top: this.liveHeaderH })
      this.buildLiveOverlay()
    }.width('100%').height('100%').backgroundColor(FieldwatchPaletteHolder.get().night)
    }
  @Builder private buildRadar() {
    Stack() {
      Canvas(this.context).width('100%').height('100%')
        .backgroundColor(FieldwatchPaletteHolder.get().night)
        // `onReady` 在**尺寸变化时也会触发**，所以这里不能直接画：
        // 当帧的 `context.width/height` 还是旧的，会画出一张尺寸不对的雷达。
        // 推到下一帧，等布局完成再画。
        .onReady((): void => {
          this.canvasReady = true;
          setTimeout((): void => { this.drawRadar(); }, 0);
        })
      this.buildRadarIcons()
      this.buildRadarClusters()
      Row().width('100%').height('100%').backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent): void => { this.handleRadarTouch(event); })
        .onHover((isHover: boolean, event: HoverEvent): void => { this.handleRadarHover(isHover, event); })
      if (this.sightings.length === 0) Text($r('app.string.fieldwatch_no_observations')).fontSize(14).fontColor($r('app.color.text_secondary'))
    }.width('100%').height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area): void => { this.syncRadarSize(newValue); })
      // 地图式交互：单指拖动平移、双指捏合围绕手指焦点缩放。
      // PanGesture 有 distance 阈值，纯点击不会触发平移，因此「点选信号」不受影响。
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart((event: GestureEvent): void => {
              this.radarZoomBase = this.radarZoom;
              this.radarOffsetXBase = this.radarOffsetX;
              this.radarOffsetYBase = this.radarOffsetY;
              this.radarFocalX = event.pinchCenterX;
              this.radarFocalY = event.pinchCenterY;
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.applyPinchAt(event.scale, this.radarFocalX, this.radarFocalY);
            })
            .onActionEnd((): void => {
              this.radarZoomBase = this.radarZoom;
              this.radarOffsetXBase = this.radarOffsetX;
              this.radarOffsetYBase = this.radarOffsetY;
              // 手指抬起才算「谁带名称、谁降级成圆点」。
              // 放在这里而不是 update 里：那是每帧都跑的重计算。
              this.rebuildRadarGeometry();
            }),
          // 单指拖动平移：实时页已禁用 Tabs 滑动，水平手势不再冲突。
          PanGesture({ fingers: 1, distance: 8 })
            .onActionStart((): void => {
              this.radarPanActive = true;
              this.radarOffsetXBase = this.radarOffsetX;
              this.radarOffsetYBase = this.radarOffsetY;
            })
            .onActionUpdate((event: GestureEvent): void => {
              // 只在手势进行中应用：抬起后如果还有迟到的 update，
              // `base + offsetX` 会把同一段位移重复叠加一次，表现就是「抬手后抽动一下」。
              if (!this.radarPanActive) return;
              this.applyPan(event.offsetX, event.offsetY);
            })
            .onActionEnd((): void => {
              this.radarPanActive = false;
              this.radarOffsetXBase = this.radarOffsetX;
              this.radarOffsetYBase = this.radarOffsetY;
              this.rebuildRadarGeometry();
            })
            .onActionCancel((): void => { this.radarPanActive = false; })
        )
      )
  }
  /**
   * 设备类型图标层。
   *
   * 雷达上不再画圆点，而是按信号识别出的设备类型显示对应图标；
   * 颜色沿用原来的规则（命中签名用签名色，否则按无线电种类），因此类型与颜色都保留。
   * Canvas 无法绘制系统符号，所以图标走 ArkUI 层叠加在 Canvas 之上。
   */
  /** 聚类节点位置（与 Canvas 同一变换）。 */
  private nodeX(node: FieldwatchRadarNode): number {
    return this.canvasX(node.x, this.animW, this.animH) - this.radarIconSize / 2;
  }
  private nodeY(node: FieldwatchRadarNode): number {
    return this.canvasY(node.y, this.animW, this.animH) - this.radarIconSize / 2;
  }
  /**
   * 聚合气泡层。
   *
   * 同一信号区间内密集的同类设备聚合成一个带数字的气泡（如「+5 台 / 5GHz Wi-Fi」），
   * 点击展开成员列表。颜色取成员的代表色，因此类型区分仍然保留。
   */
  @Builder private buildRadarClusters() {
    ForEach(this.radarNodes.filter((node: FieldwatchRadarNode): boolean => node.isCluster()), (node: FieldwatchRadarNode): void => {
      Column({ space: 1 }) {
        Text('+' + node.count.toString()).fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().onAccent)
        Text(node.clusterLabel).fontSize(9)
          .fontColor(FieldwatchPaletteHolder.get().onAccent).maxLines(1)
      }
      // 聚合气泡比单点图标大一圈：它是「这里有一簇设备」的入口，
      // 太小的话既不好点、也压不住旁边的单点图标。
      .width(this.clusterSize() + 16).height(this.clusterSize() + 16)
      .justifyContent(FlexAlign.Center)
      .borderRadius((this.clusterSize() + 16) / 2)
      .backgroundColor(this.radarPointColor(node.sample))
      .opacity(this.radarPointOpacity(node.sample))
      .position({ x: this.nodeX(node), y: this.nodeY(node) })
      .onClick((): void => { this.clusterKey = this.clusterKey === node.key ? '' : node.key; })
      .bindPopup(this.clusterKey === node.key, {
        builder: this.buildClusterPopup(node),
        placement: Placement.Top,
        popupColor: FieldwatchPaletteHolder.get().panel,
        /**
         * **必须接这个回调，否则弹窗关不掉。**
         *
         * 用户点空白处时系统会把弹窗收起来，但 `clusterKey` 还留着 ——
         * 绑定条件是 `clusterKey === node.key`，仍然为真，
         * 于是「点过哪个聚合点，就一直在显示它的内容」（实测反馈）。
         * 这里把状态同步回来，才真正关得掉。
         */
        onStateChange: (event: PopupStateChangeParam): void => {
          // **只清「自己这个」气泡的状态。**
          //
          // 无条件清空会连累另一个刚被点开的气泡：关闭 A 时把 B 的 key 也抹了，
          // 表现就是「点了聚合点没有任何效果」（实测反馈）。
          // 另外绑定的初始可见性是 false，也会在挂载当帧把状态抹掉。
          if (!event.isVisible && this.clusterKey === node.key) this.clusterKey = '';
        }
      })
    }, (node: FieldwatchRadarNode): string => node.key)
  }
  /** 聚合气泡尺寸：随成员数略微放大，但设上限避免挡住别的信号。 */
  private clusterSize(): number {
    return this.radarIconSize + (this.clusterExtraSize);
  }

  /**
   * 气泡展开内容：列出成员设备，**每一项都可点开详情**。
   *
   * 之前只画了文字、没有点击处理 ——
   * 用户看到列表却点不进去（实测反馈）。
   */
  @Builder private buildClusterPopup(node: FieldwatchRadarNode) {
    Column({ space: 4 }) {
      Text('+' + node.count.toString() + ' 台 · ' + node.clusterLabel)
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
        .padding({ bottom: 2 })
      ForEach(node.memberKeys.slice(0, 8), (key: string): void => {
        Row({ space: 6 }) {
          Text(this.memberLabel(key))
            .fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
        }
        .width('100%')
        .padding({ left: 8, right: 6, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(FieldwatchPaletteHolder.get().panel2)
        .onClick((): void => {
          // 先收起弹窗再跳转：否则回来时它还挂在屏幕上。
          this.clusterKey = '';
          this.onOpenDetail(key);
        })
      }, (key: string): string => key)
      if (node.memberKeys.length > 8) {
        Text('…共 ' + node.memberKeys.length.toString() + ' 台')
          .fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.padding(10).alignItems(HorizontalAlign.Start).width(220)
  }
  private memberLabel(key: string): string {
    const sighting: Sighting | undefined = this.findSighting(key);
    if (sighting === undefined) return key;
    const name: string = sighting.name.length > 0 ? sighting.name : sighting.facts.ssid;
    return (name.length > 0 ? name : sighting.address) + '  ' + sighting.rssi.toString() + ' dBm';
  }
  @Builder private buildRadarIcons() {
    ForEach(this.visibleRadarPoints().filter((point: FieldwatchRadarPoint): boolean => this.clusteredKeys.indexOf('|' + point.key + '|') < 0 && this.dotKeys.indexOf('|' + point.key + '|') < 0), (point: FieldwatchRadarPoint): void => {
      Row({ space: 6 }) {
        // 图标是主体：它精确落在该信号的真实强度半径上，也是唯一可点击的区域。
        SymbolGlyph($r(point.symbol))
          .fontSize(this.radarIconSize)
          .fontColor([this.radarPointColor(point)])
          .onClick((): void => { this.selectPoint(point); })
        // 文字是图标的附属说明，紧贴图标右侧；它本身不响应点击，
        // 避免用户点到文字却不知道命中了哪个信号。
        Column({ space: 1 }) {
          if (this.showField('name')) Text(point.label.substring(0, 18))
            .fontSize(this.radarLabelFontSize).fontColor(FieldwatchPaletteHolder.get().headerText)
          if (this.labelDetail(point).length > 0) Text(this.labelDetail(point))
            .fontSize(this.radarLabelFontSize - 1).fontColor(FieldwatchPaletteHolder.get().textDim)
        }.alignItems(HorizontalAlign.Start).hitTestBehavior(HitTestMode.None)
      }
      .alignItems(VerticalAlign.Center)
      .position({ x: this.iconX(point), y: this.iconY(point) })
      // 淡入淡出：越过自身阈值时逐渐显形，而不是突然出现/消失。
      .opacity(this.radarPointOpacity(point))
    }, (point: FieldwatchRadarPoint): string => point.key)
  }
  private showField(field: string): boolean {
    return this.radarLabelFields.indexOf(field) >= 0;
  }
  /** 附属说明行：按设置拼装类型 / 强度 / 频段 / 地址。 */
  private labelDetail(point: FieldwatchRadarPoint): string {
    const parts: string[] = [];
    if (this.showField('type')) parts.push(point.kind.toUpperCase());
    if (this.showField('rssi')) parts.push(point.rssi.toString() + ' dBm');
    if (this.showField('freq') && point.kind === RadioKind.WIFI && point.frequencyMhz > 0) parts.push(point.frequencyMhz.toString() + ' MHz');
    if (this.showField('address')) parts.push(point.address.substring(0, 17));
    return parts.join('  ');
  }
  /**
   * 当前该显示的信号。
   *
   * **动态加载**：只显示落在当前视野内的点，并按缩放级别限制数量 ——
   * 缩小时只给最近的少量信号（避免几十个图标糊成一片、也省渲染），
   * 放大后才逐步显示更多。这样既不遮挡显示，也不影响点击操作。
   */
  /**
   * 当前该显示的信号。
   *
   * **渐进式显现，不做整体重排**。
   *
   * 之前的做法是「按角度等步长抽样、数量随缩放变化」——`limit` 一变，
   * 整个抽样集合全部重排，表现就是「刚显示过的信号突然消失、另一个突然出现」。
   *
   * 现在改成地图 App 的模型：**每个点有自己固定的显现阈值**（按重要性排名一次性算定），
   * 是否可见只取决于「当前缩放是否越过它自己的阈值」，与其他点无关。
   * 放大时逐个显现、缩小时逐个隐去，顺序稳定，不会互相挤掉。
   */
  /**
   * 重算聚类与标签排布。
   *
   * 两者的输入都是**当前可见点集**，而可见点集随缩放/平移变化 ——
   * 所以缩放、平移、以及每秒的数据刷新都要走这一条路径，
   * 保证「气泡范围」与「哪些点降级为圆点」始终和眼前的画面一致。
   */
  private rebuildRadarGeometry(): void {
    this.radarNodes = buildRadarNodes(this.visibleRadarPoints());
    let grouped: string = '|';
    this.radarNodes.forEach((node: FieldwatchRadarNode): void => {
      if (node.isCluster()) node.memberKeys.forEach((key: string): void => { grouped += key + '|'; });
    });
    this.clusteredKeys = grouped;
    this.replanRadarLabels();
  }

  /**
   * 重算标签排布，得出「哪些点放得下、哪些点降级为小圆点」。
   *
   * 只在可见点集变化时算（与 `radarNodes` 同一处），不放进逐帧绘制里 ——
   * 排布是 O(n²) 的相交检测，每秒跑一次可以，每帧跑不行。
   */
  private replanRadarLabels(): void {
    // 字体与下面绘制保持一致：画布用的是 fontSize * 2（px）。
    // 两处不一致的话，算出来的标签宽度与实际不符，圆点判断就是错的。
    // **必须与图标层实际渲染的字号一致。**
    // 图标层的 `Text` 用的是 `radarLabelFontSize`，这里曾按 `* 2` 估算 ——
    // 框宽被算大一倍，本来放得下的位置被判成碰撞，
    // 结果大量本可显示名称的点被降级成圆点（实测反馈）。
    const fontPx: number = this.radarLabelFontSize;
    const showName: boolean = this.radarLabelFields.indexOf('name') >= 0;
    const showType: boolean = this.radarLabelFields.indexOf('type') >= 0;
    const showRssi: boolean = this.radarLabelFields.indexOf('rssi') >= 0;
    const showAddress: boolean = this.radarLabelFields.indexOf('address') >= 0;
    const showFreq: boolean = this.radarLabelFields.indexOf('freq') >= 0;
    // **必须排除已被聚合的成员。**
    //
    // 否则同一个信号会既算进气泡、又进 `dotKeys`，在画布上多画一个圆点 ——
    // 用户看到的就是「聚合气泡的覆盖范围里还有信号源，这个气泡是个摆设」。
    const plan: RadarLabelPlan = planRadarLabels(
      this.visibleRadarPoints().filter((point: FieldwatchRadarPoint): boolean =>
        this.clusteredKeys.indexOf('|' + point.key + '|') < 0),
      this.animW, this.animH,
      (nx: number): number => this.canvasX(nx, this.animW, this.animH),
      (ny: number): number => this.canvasY(ny, this.animW, this.animH),
      (p: FieldwatchRadarPoint): number => p.radius,
      (p: FieldwatchRadarPoint): string => showName ? p.label.substring(0, 18) : '',
      (p: FieldwatchRadarPoint): string => {
        const parts: string[] = [];
        if (showType) parts.push(p.kind.toUpperCase());
        if (showRssi) parts.push(p.rssi.toString() + ' dBm');
        if (showFreq && p.kind === RadioKind.WIFI && p.frequencyMhz > 0) parts.push(p.frequencyMhz.toString() + ' MHz');
        if (showAddress) parts.push(p.address.substring(0, 17));
        return parts.join('  ');
      },
      fontPx, 78, 92);
    this.labelPlan = plan;
    this.dotKeys = plan.dotKeys;
  }

  private visibleRadarPoints(): Array<FieldwatchRadarPoint> {
    if (this.radarW <= 0 || this.radarH <= 0) return [];
    return this.radarPoints.filter((point: FieldwatchRadarPoint): boolean => {
      return this.radarZoom >= this.revealZoom(point) && this.pointInView(point);
    });
  }
  /**
   * 单个点的显现阈值（缩放值）。
   *
   * 按**强度排名**一次性算定：最强的先显现（阈值最低），最弱的最后显现。
   * 排名只随数据变化，不随缩放变化 —— 这是「不跳变」的关键。
   */
  private revealZoom(point: FieldwatchRadarPoint): number {
    const rank: number = this.radarRank.get(point.key) ?? 0;
    const total: number = Math.max(1, this.radarPoints.length);
    // 阈值落在 0.4 ~ 2.4：
    //   - 0.4 倍时每圈各留一个；
    //   - 1.0 倍（默认）时约可见四成，每圈都有若干个；
    //   - 2.4 倍以上全部可见。
    return 0.4 + (rank / total) * 2.0;
  }
  /**
   * 显现/隐去的淡入淡出透明度。
   *
   * 在阈值前后留一段过渡带（0.35），越过时逐渐显形，而不是「啪」地出现或消失。
   */
  private radarPointOpacity(point: FieldwatchRadarPoint): number {
    const delta: number = this.radarZoom - this.revealZoom(point);
    if (delta <= 0) return 0;
    return Math.min(1, delta / 0.35);
  }
  /**
   * 重算显现排名（强度降序）。
   *
   * 只在数据刷新时算一次：排名稳定，缩放手势过程中不会变，
   * 因此每个点的显现阈值是固定的，不会出现互相挤掉导致的跳变。
   */
  /**
   * 重算显现顺序：**先按环分桶，再逐环轮流显现**。
   *
   * 如果只按全局强度排名，缩小时留下的全是最强的点 ——
   * 而强度决定半径，最强必然都挤在圆心附近，外圈一个信号都没有。
   *
   * 改成先把信号按所属圆环分桶（环内按强度降序），再**轮流从每个桶取一个**：
   * 于是任何缩放级别下，每一圈都有信号；放大则是「每圈再多一个」，
   * 逐层加密，而不是先填满圆心。
   */
  private rebuildRadarRank(): void {
    const ringCount: number = 8;
    const buckets: Array<Array<FieldwatchRadarPoint>> = [];
    for (let index: number = 0; index < ringCount; index += 1) buckets.push([]);
    this.radarPoints.forEach((point: FieldwatchRadarPoint): void => {
      const ring: number = this.ringIndexOf(point);
      buckets[ring].push(point);
    });
    buckets.forEach((bucket: Array<FieldwatchRadarPoint>): void => {
      bucket.sort((a: FieldwatchRadarPoint, b: FieldwatchRadarPoint): number => b.rssi - a.rssi);
    });
    // 轮流取样：第 1 轮各环最强的一个，第 2 轮各环第二强的，依此类推。
    this.radarRank.clear();
    let order: number = 0;
    const deepest: number = buckets.reduce((max: number, bucket: Array<FieldwatchRadarPoint>): number => Math.max(max, bucket.length), 0);
    for (let round: number = 0; round < deepest; round += 1) {
      for (let ring: number = 0; ring < ringCount; ring += 1) {
        if (round < buckets[ring].length) {
          this.radarRank.set(buckets[ring][round].key, order);
          order += 1;
        }
      }
    }
  }
  /** 信号落在第几圈（与 buildRadarPoints 的半径映射保持一致）。 */
  private ringIndexOf(point: FieldwatchRadarPoint): number {
    const normalized: number = Math.max(0, Math.min(1, (-30 - point.rssi) / 70));
    const distance: number = 0.12 + normalized * 0.88;
    const ring: number = Math.floor(distance / 0.125);
    return Math.max(0, Math.min(7, ring));
  }
  /** 点位相对圆心的方位角。 */
  private pointAngle(point: FieldwatchRadarPoint): number {
    return Math.atan2(point.y - 0.5, point.x - 0.5);
  }
  private pointInView(point: FieldwatchRadarPoint): boolean {
    const x: number = this.iconX(point);
    const y: number = this.iconY(point);
    return x >= 0 && x <= this.radarW && y >= 0 && y <= this.radarH;
  }
  /** 图标横坐标（vp）：与 Canvas 用同一个归一化公式，再按缩放围绕中心展开。 */
  /** 图标横坐标（vp）：与 Canvas 完全同一个公式（含短边跨度与缩放）。 */
  /**
   * 图标位置（vp）：**直接从 Canvas 的同一变换推导**（px → vp）。
   *
   * 之前图标用自己的 `radarW/radarH` 算，圆环用 `context.width/height` 算，
   * 两套尺寸来源一旦不一致（比例、取 min 的轴不同），平移时图标就会相对圆环漂移。
   * 现在只有一个变换函数，图标与圆环在任何缩放下都严格同源。
   */
  private iconX(point: FieldwatchRadarPoint): number {
    return this.canvasX(point.x, this.animW, this.animH) - this.radarIconSize / 2;
  }
  private iconY(point: FieldwatchRadarPoint): number {
    return this.canvasY(point.y, this.animW, this.animH) - this.radarIconSize / 2;
  }
  /** 图标中心，命中判定与悬浮卡定位共用（与 Canvas 同一单位，不做换算）。 */
  private iconCenterX(point: FieldwatchRadarPoint): number {
    return this.canvasX(point.x, this.animW, this.animH);
  }
  private iconCenterY(point: FieldwatchRadarPoint): number {
    return this.canvasY(point.y, this.animW, this.animH);
  }
  private radarPointColor(point: FieldwatchRadarPoint): string {
    const signatureColor: string = signatureColorAt(point.colorIndex);
    if (signatureColor.length > 0) return signatureColor;
    if (point.kind === RadioKind.WIFI) return FieldwatchPaletteHolder.get().cyan;
    if (point.kind === RadioKind.NEARLINK) return FieldwatchPaletteHolder.get().nearLink;
    return FieldwatchPaletteHolder.get().accent;
  }
  /**
   * 容器尺寸变化。真实尺寸立即记录，**动画尺寸缓动追上去**。
   *
   * 首次（`animW === 0`）直接落位，不要从 0 长大。
   */
  private syncRadarSize(area: Area): void {
    const w: number = area.width as number;
    const h: number = area.height as number;
    const first: boolean = this.animW <= 0 || this.animH <= 0;
    this.radarW = w;
    this.radarH = h;
    if (first) {
      this.animW = w;
      this.animH = h;
      setTimeout((): void => {
        if (this.canvasReady && fieldwatchApplication.isAppForeground()) this.drawRadar();
      }, 0);
      return;
    }
    if (Math.abs(w - this.animW) < 0.5 && Math.abs(h - this.animH) < 0.5) return;
    this.startSizeEase();
  }

  /**
   * 逐帧把动画尺寸缓动到真实尺寸。
   *
   * 缓动期间每帧重画画布；图标位置由 `animW/animH` 参与计算，
   * 是 `@State`，会随每帧自动跟随 —— 两者用同一对值，所以**必然同步**，
   * 不会出现「圆环到位了、图标还在半路」这种错位。
   */
  private startSizeEase(): void {
    if (this.sizeTimer !== -1) return;
    const step = (): void => {
      const dw: number = this.radarW - this.animW;
      const dh: number = this.radarH - this.animH;
      if (Math.abs(dw) < 0.5 && Math.abs(dh) < 0.5) {
        // 收尾精确落位，避免长期残留零点几的偏差
        this.animW = this.radarW;
        this.animH = this.radarH;
        clearInterval(this.sizeTimer);
        this.sizeTimer = -1;
      } else {
        // 指数逼近：每帧走剩余距离的 30%。约 8 帧到位（16ms 一帧 ≈ 130ms），
        // 且天然是「快进慢出」的缓动，不需要额外的曲线函数。
        this.animW += dw * 0.3;
        this.animH += dh * 0.3;
      }
      if (this.canvasReady && fieldwatchApplication.isAppForeground()) this.drawRadar();
    };
    this.sizeTimer = setInterval(step, 16);
  }
  /** 双指缩放：放大后才显示更多信号（配合 visibleRadarPoints 的动态加载）。 */
  /**
   * 焦点锚定缩放：像地图一样，**围绕手指所在位置**缩放，而不是固定围绕圆心。
   *
   * 做法是先算出焦点下对应的世界坐标（用基准状态），缩放后反解偏移，
   * 让同一个世界点仍然停在手指下 —— 这样在任何位置捏合都符合直觉。
   */
  private applyPinchAt(scale: number, focalX: number, focalY: number): void {
    if (scale <= 0) return;
    const span: number = Math.min(this.radarW, this.radarH);
    if (span <= 0) return;
    const baseZoom: number = this.radarZoomBase;
    const worldX: number = (focalX - this.radarW / 2 - this.radarOffsetXBase) / (span * baseZoom) + 0.5;
    const worldY: number = (focalY - this.radarH / 2 - this.radarOffsetYBase) / (span * baseZoom) + 0.5;
    const nextZoom: number = Math.max(0.5, Math.min(4, baseZoom * scale));
    this.radarZoom = nextZoom;
    // **缩放过程中不要重算。**
    //
    // `rebuildRadarGeometry` 是 O(n²) 的标签相交检测加 28 轮力导向，
    // 每帧调用会直接卡死手势。手势结束时（`onActionEnd`）统一算一次即可 ——
    // 期间画面上的点仍然实时跟随缩放，只是「谁带名称」的判定晚到一步。
    this.radarOffsetX = focalX - this.radarW / 2 - (worldX - 0.5) * span * nextZoom;
    this.radarOffsetY = focalY - this.radarH / 2 - (worldY - 0.5) * span * nextZoom;
  }
  /** 双指平移：整体移动雷达。 */
  private applyPan(dx: number, dy: number): void {
    this.radarOffsetX = this.radarOffsetXBase + dx;
    this.radarOffsetY = this.radarOffsetYBase + dy;
    // 平移同理：重算留给 `onActionEnd`（理由见 `applyPinchAt`）。
  }
  /**
   * 归一化坐标 → Canvas px。
   *
   * **两个轴都用短边做跨度**：圆环的半径是按 min(宽,高) 算的内切圆，
   * 而点位原本按整矩形归一化 —— 两套几何不一致，点就会跑到圆环外面（漂移）。
   * 改用同一个 span 后，点云与圆环同几何，图标才落得准。
   */
  /**
   * 视图平移量（vp → px）。
   *
   * **不要硬编码 px/vp 比例**：Canvas 用 px、ArkUI 用 vp，
   * 写死 `* 2` 在比例不是 2 的设备上会让圆环和图标以不同速率移动 ——
   * 表现就是「平移时图标相对圆环漂移」。必须用 vp2px 实际换算。
   */
  /**
   * 视图平移量。
   *
   * **不要做 vp/px 换算**：实测 `Canvas.context.width/height` 与 `onAreaChange` 的
   * `Area.width/height` 返回的是同一个单位（日志里两者完全相同）。
   * 之前用 vp2px 换算，等于把圆环的平移量凭空放大一倍，
   * 而图标用的是未换算的值 —— 两者速率不同，表现就是「平移时图标相对圆环漂移」。
   */
  private panPxX(): number { return this.radarOffsetX; }
  private panPxY(): number { return this.radarOffsetY; }
  private canvasX(nx: number, width: number, height: number): number {
    const span: number = Math.min(width, height);
    return width / 2 + (nx - 0.5) * span * this.radarZoom + this.panPxX();
  }
  private canvasY(ny: number, width: number, height: number): number {
    const span: number = Math.min(width, height);
    return height / 2 + (ny - 0.5) * span * this.radarZoom + this.panPxY();
  }
  private drawRadar(): void {
    const width: number = this.animW;
    const height: number = this.animH;
    // 尺寸还没量到时不画：否则会以 0 为半径画出一堆退化图形，
    // 在首帧表现为画布角落的一个点。
    if (width <= 0 || height <= 0) return;
    // 整个雷达是一个整体：圆心随平移移动，半径随缩放变化。
    const centerX: number = width / 2 + this.panPxX();
    const centerY: number = height / 2 + this.panPxY();
    const maxRadius: number = (Math.min(width, height) / 2 - 34) * this.radarZoom;
    const points: Array<FieldwatchRadarPoint> = buildRadarPoints(this.sightings, fieldwatchApplication.getState().signatures);
    this.context.clearRect(0, 0, width, height);
    this.context.fillStyle = FieldwatchPaletteHolder.get().night; this.context.fillRect(0, 0, width, height);
    this.context.strokeStyle = FieldwatchPaletteHolder.get().outline;
    this.context.lineWidth = 2;
    [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1].forEach((scale: number): void => { this.context.beginPath(); this.context.arc(centerX, centerY, maxRadius * scale, 0, Math.PI * 2); this.context.stroke(); });
    this.context.strokeStyle = FieldwatchPaletteHolder.get().divider; this.context.lineWidth = 1;
    this.context.beginPath(); this.context.moveTo(centerX - maxRadius, centerY); this.context.lineTo(centerX + maxRadius, centerY); this.context.stroke();
    this.context.beginPath(); this.context.moveTo(centerX, centerY - maxRadius); this.context.lineTo(centerX, centerY + maxRadius); this.context.stroke();
    // 拖尾：在扫描线后方画一段逐渐变淡的扇形，替代原来的单根硬线。
    // 拖尾角度固定（不随帧率变化），因此视觉上是连续的光带而不是闪烁。
    const trailSpan: number = 0.5;
    const steps: number = 16;
    for (let step: number = steps; step >= 1; step -= 1) {
      const back: number = trailSpan * (step / steps);
      const alpha: number = 0.02 + 0.22 * (1 - step / steps);
      this.context.globalAlpha = alpha;
      this.context.strokeStyle = FieldwatchPaletteHolder.get().accent;
      this.context.lineWidth = 2;
      this.context.beginPath();
      this.context.moveTo(centerX, centerY);
      this.context.lineTo(
        centerX + Math.cos(this.radarAngle - back) * maxRadius,
        centerY + Math.sin(this.radarAngle - back) * maxRadius
      );
      this.context.stroke();
    }
    // 扫描线本体
    this.context.globalAlpha = 1;
    this.context.strokeStyle = FieldwatchPaletteHolder.get().accent;
    this.context.lineWidth = 3;
    this.context.beginPath();
    this.context.moveTo(centerX, centerY);
    this.context.lineTo(centerX + Math.cos(this.radarAngle) * maxRadius, centerY + Math.sin(this.radarAngle) * maxRadius);
    this.context.stroke();
    this.context.font = '18px sans-serif'; this.context.fillStyle = FieldwatchPaletteHolder.get().textDim; this.context.fillText('-40', centerX + 8, centerY - maxRadius * 0.25); this.context.fillText('-60', centerX + 8, centerY - maxRadius * 0.5); this.context.fillText('-80', centerX + 8, centerY - maxRadius * 0.75); this.context.fillText('-100', centerX + 8, centerY - maxRadius + 20);
    // **放不下图标的点降级为小圆点，画在这里。**
    //
    // 完整图标要占「图标 + 名称 + 强度」的宽度，拥挤时根本摆不开；
    // 但小圆点只占几个像素，同样空间能显示的信号数量高一个量级，
    // 而且保留颜色（种类与签名语义不丢）。
    //
    // 判断由 `labelPlan` 统一给出 —— 标签放得下的走 ArkUI 图标层，
    // 放不下的在这里画点，两边不会同时画同一个信号。
    const dotRadius: number = 4;
    points.forEach((point: FieldwatchRadarPoint): void => {
      if (this.dotKeys.indexOf('|' + point.key + '|') < 0) return;
      const x: number = this.canvasX(point.x, width, height);
      const y: number = this.canvasY(point.y, width, height);
      const signatureColor: string = signatureColorAt(point.colorIndex);
      this.context.fillStyle = signatureColor.length > 0 ? signatureColor
        : (point.kind === RadioKind.WIFI ? FieldwatchPaletteHolder.get().cyan : FieldwatchPaletteHolder.get().accent);
      this.context.beginPath();
      this.context.arc(x, y, dotRadius, 0, Math.PI * 2);
      this.context.fill();
    });
    // 标签不再画在 Canvas 上：它与图标是两个坐标系，必然分离。
    // 现在图标与文字合成一个 ArkUI 单元，共用同一套变换，永远贴在一起。
  }
  /**
   * 切换实时视图。
   *
   * 用 animateTo 包住状态变更，让内容淡入淡出；直接赋值会「啪」地一下换掉，
   * 在平板大屏上非常突兀。
   */
  private switchLiveMode(mode: FieldwatchLiveMode): void {
    if (mode === this.mode) return;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
      this.mode = mode;
    });
    fieldwatchApplication.updateLiveMode(mode);
  }
  private findSighting(key: string): Sighting | undefined { return this.sightings.find((item: Sighting): boolean => item.key === key); }
  private handleRadarTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Up || event.changedTouches.length === 0) return;
    const point: TouchObject = event.changedTouches[0];
    this.selectNearest(point.x, point.y);
  }
  /** hover 只用于鼠标场景；触屏上不参与选中，避免误触发。 */
  private handleRadarHover(isHover: boolean, event: HoverEvent): void {
    if (isHover) return;
  }
  /** 直接选中某个点（图标自身被点击时），锚点同样取自图标位置而非点击处。 */
  /**
   * 列表行 / 分类设备行点击：直接打开详情面板。
   *
   * 不复用 selectPoint：那个方法要按雷达图标坐标摆放悬浮预览卡，
   * 列表里没有雷达坐标，硬套会把卡片放到错误的位置。
   */
  private openDetailFor(sighting: Sighting): void {
    // **改为跳转到独立详情页**，不再开 sheet。
    //
    // 原版详情有 12 段、趋势图、在场时间轴和四个动作按钮，
    // 长度远超 sheet 能承载的范围；sheet 里滚动还会和拖拽关闭手势打架。
    // 页面化之后还能拿到 HDS 的顶栏材质与系统返回手势。
    // 模式切换由根页面在压栈前完成（见 `onOpenDetail` 的注入处）。
    this.onOpenDetail(sighting.key);
  }
  /** 点中某个信号（图标层 onClick）：**直接进详情页**。 */
  private selectPoint(point: FieldwatchRadarPoint): void {
    // 不再先弹预览卡：它只给三个字段，要看全还得再点一次，
    // 详情页是独立页面，返回手势直接回雷达，少一层中转（实测反馈）。
    const sighting: Sighting | undefined = this.findSighting(point.key);
    if (sighting !== undefined) this.openDetailFor(sighting);
  }
  /**
   * 命中判定（vp 坐标）。
   *
   * 三个要点：
   *  1. **与图标用同一个变换** —— 之前这里按整矩形算，图标按短边跨度+缩放+平移算，
   *     两套坐标导致「点图标点不中、点空白反而随机命中」。
   *  2. **阈值收紧到图标本身**（半个图标 + 少量余量），点空白必须不命中。
   *  3. **悬浮卡锚定在图标旁边**，而不是点击处 —— 否则卡片会「跑到刚点的地方」。
   */
  private selectNearest(x: number, y: number): void {
    const width: number = this.animW;
    const height: number = this.animH;
    if (width <= 0 || height <= 0) return;
    const threshold: number = this.radarIconSize / 2 + 10;
    let nearest: string = '';
    let best: number = threshold;
    let anchorX: number = 0;
    let anchorY: number = 0;
    // **先判气泡**：气泡是聚合结果，命中它应当展开成员列表，
    // 而不是去选中某个被聚合掉的成员。
    // **气泡的圆心与半径必须按它的实际渲染尺寸算。**
    //
    // 气泡比普通图标大（`clusterSize() + 16`），而 `nodeX/nodeY` 是按
    // `radarIconSize` 定位左上角的 —— 直接拿 `nodeX + radarIconSize/2` 当圆心，
    // 会比真实圆心偏出约 18px，半径也不够大，
    // 于是「气泡稳定显示在眼前，点它的正中心却没反应」（实测反馈）。
    const bubbleHalf: number = (this.clusterSize() + 16) / 2;
    const bubbleRadius: number = bubbleHalf + 8;
    for (let index: number = 0; index < this.radarNodes.length; index += 1) {
      const node: FieldwatchRadarNode = this.radarNodes[index];
      if (!node.isCluster()) continue;
      const bx: number = this.nodeX(node) + bubbleHalf;
      const by: number = this.nodeY(node) + bubbleHalf;
      const bdx: number = bx - x;
      const bdy: number = by - y;
      if (Math.sqrt(bdx * bdx + bdy * bdy) <= bubbleRadius) {
        this.clusterKey = this.clusterKey === node.key ? '' : node.key;
            return;
      }
    }
    this.clusterKey = '';
    // 只在**当前可见且未被聚合**的点里命中：隐去的或已进气泡的信号都不该被点中。
    //
    // **降级为小圆点的信号同样要能点中。**
    // 它们只是没有空间显示名称，本身仍是一个真实的信号源；
    // 之前把它们排除在外，用户点圆点没有任何反应（实测反馈）。
    // 命中半径仍是 `radarIconSize/2 + 10`，对 4px 的圆点来说是很大的容错区，
    // 密集处按「最近的一个」取胜，不会误选。
    this.visibleRadarPoints().filter((point: FieldwatchRadarPoint): boolean => this.clusteredKeys.indexOf('|' + point.key + '|') < 0).forEach((point: FieldwatchRadarPoint): void => {
      const px: number = this.iconCenterX(point);
      const py: number = this.iconCenterY(point);
      const dx: number = px - x;
      const dy: number = py - y;
      const current: number = Math.sqrt(dx * dx + dy * dy);
      if (current < best) { best = current; nearest = point.key; anchorX = px; anchorY = py; }
    });
    // 诊断：把触摸坐标、图标中心、阈值、命中结果全部打出来，
    // 用于确认 TouchObject 的单位（vp/px）与变换是否一致。
    logger.info('FieldwatchRadar', 'touch=(' + x.toFixed(1) + ',' + y.toFixed(1) + ')'
      + ' canvasPx=(' + width.toFixed(0) + ',' + height.toFixed(0) + ')'
      + ' radarVp=(' + this.radarW.toFixed(0) + ',' + this.radarH.toFixed(0) + ')'
      + ' zoom=' + this.radarZoom.toFixed(2)
      + ' offset=(' + this.radarOffsetX.toFixed(0) + ',' + this.radarOffsetY.toFixed(0) + ')'
      + ' best=' + best.toFixed(1) + ' threshold=' + threshold.toFixed(1)
      + ' hit=' + (nearest.length > 0 ? nearest : 'none'));
    // 点空白：不做事（原来会清掉选中，现在没有选中态了）。
    if (nearest.length === 0) return;
    // **直接进详情页，不再先弹预览卡。**
    //
    // 预览卡只给「名称 / 强度 / 地址」三个字段，要看全还得再点一次；
    // 详情页是独立页面，返回手势直接回雷达，少一层中转（实测反馈）。
    const sighting: Sighting | undefined = this.findSighting(nearest);
    if (sighting !== undefined) this.openDetailFor(sighting);
  }
  // 详情 sheet 已删除：详情统一走 `FieldwatchDeviceDetailPage`。
  // 保留 `buildDetailFields` 是因为「用此设备创建特征」的编辑器还复用它。
  /** 星闪设备类型名称；广播未携带类型时给出明确的「未知」而不是空白。 */
  private nearLinkClassText(sighting: Sighting): string {
    const label: string = nearLinkClassLabel(sighting.facts.nearLinkDeviceClass);
    return label.length > 0 ? label
      : resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_detail_nl_unknown'));
  }
  // ── 详情页新增字段的取值助手 ──

  /**
   * 由频率推算 Wi-Fi 信道号（原版 domain/Geo 与 RadioFacts 用同一套换算）。
   *
   * 2.4G：从 2412 MHz 起每 5 MHz 一个信道；14 信道是特例（2484）。
   * 5G：从 5000 MHz 起每 5 MHz 一个信道。
   * 频率为 0（非 Wi-Fi 或系统没给）时返回空串。
   */
  private channelText(sighting: Sighting): string {
    const mhz: number = sighting.facts.frequencyMhz;
    if (mhz <= 0) return '';
    if (mhz === 2484) return '14';
    if (mhz >= 2412 && mhz <= 2472) return Math.round((mhz - 2407) / 5).toString();
    if (mhz >= 5000 && mhz <= 5900) return Math.round((mhz - 5000) / 5).toString();
    return '';
  }
  /**
   * Wi-Fi 代际。由频率与带宽共同推断 —— 只看频率会把 5G 上的 Wi-Fi 4 说成 Wi-Fi 5。
   * 推断不出时返回空串，不硬猜。
   */
  private generationText(sighting: Sighting): string {
    const mhz: number = sighting.facts.frequencyMhz;
    const width: number = sighting.facts.channelWidth;
    if (mhz <= 0) return '';
    if (mhz < 2500) return width >= 40 ? 'Wi-Fi 4 (802.11n)' : 'Wi-Fi 4 及更早';
    if (mhz < 5925) return width >= 80 ? 'Wi-Fi 5 (802.11ac)' : 'Wi-Fi 4 (802.11n)';
    return 'Wi-Fi 6E / 7 (6 GHz)';
  }
  // ── Wi-Fi 裸枚举值 -> 可读文本 ──
  //
  // 鸿蒙给的是数字（band=1、channelWidth=0、securityType=3），
  // 直接显示就是「频段 1」「信道宽度 0」这种看不懂的东西。
  // 原版能直接显示是因为 Android 侧给的就是字符串。

  /** 频段：0 无 / 1 2.4G / 2 5G / 3 6G / 4 60G。 */
  private bandText(sighting: Sighting): string {
    if (sighting.kind !== RadioKind.WIFI) return this.notApplicableText();
    const value: number = sighting.facts.band;
    if (value === 1) return '2.4 GHz';
    if (value === 2) return '5 GHz';
    if (value === 3) return '6 GHz';
    if (value === 4) return '60 GHz';
    // 频段没给时用频率兜底，总比显示「0」有用。
    const mhz: number = sighting.facts.frequencyMhz;
    if (mhz >= 2400 && mhz < 2500) return '2.4 GHz';
    if (mhz >= 5000 && mhz < 5925) return '5 GHz';
    if (mhz >= 5925 && mhz < 7125) return '6 GHz';
    return this.notApplicableText();
  }
  /** 信道宽度：0 20M / 1 40M / 2 80M / 3 160M。 */
  private channelWidthText(sighting: Sighting): string {
    if (sighting.kind !== RadioKind.WIFI) return this.notApplicableText();
    const value: number = sighting.facts.channelWidth;
    if (value === 0) return '20 MHz';
    if (value === 1) return '40 MHz';
    if (value === 2) return '80 MHz';
    if (value === 3) return '160 MHz';
    return this.notApplicableText();
  }
  /** 安全类型：0 无效 / 1 开放 / 2 WEP / 3 WPA2(PSK) / 4 WPA3(SAE)。 */
  private securityText(sighting: Sighting): string {
    if (sighting.kind !== RadioKind.WIFI) return this.notApplicableText();
    const value: number = sighting.facts.securityType;
    if (value === 1) return '开放（无密码）';
    if (value === 2) return 'WEP（已过时）';
    if (value === 3) return 'WPA2 / PSK';
    if (value === 4) return 'WPA3 / SAE';
    return this.notApplicableText();
  }
  /** 地址类型：'固定' / '随机' / 空（平台没给）。 */
  private addressTypeText(sighting: Sighting): string {
    const value: string = sighting.facts.addressType;
    if (value === 'public') return resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_addr_public'));
    if (value === 'random') return resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_addr_random'));
    return '';
  }
  /**
   * 外观：优先名称，其次十六进制代码；都没有返回空串。
   * 名称来自 radiodb 的 app 段（此前从未被读取）。
   */
  private appearanceText(sighting: Sighting): string {
    const code: number = sighting.facts.appearance;
    if (code < 0) return '';
    const name: string = fieldwatchApplication.appearanceName(code);
    return name.length > 0 ? name : '0x' + code.toString(16).toUpperCase();
  }
  /** 外观代码本身；没携带返回空串。 */
  private appearanceCodeText(sighting: Sighting): string {
    const code: number = sighting.facts.appearance;
    return code < 0 ? '' : '0x' + code.toString(16).toUpperCase().padStart(4, '0');
  }
  /** 服务 UUID 列表，附带名称库里的可读名。 */
  private serviceUuidText(sighting: Sighting): string {
    const all: string[] = sighting.facts.serviceUuids;
    if (all.length === 0) return '';
    const parts: string[] = [];
    all.slice(0, 8).forEach((uuid: string): void => {
      parts.push(this.serviceUuidLabel(uuid));
    });
    if (all.length > 8) parts.push('+' + (all.length - 8).toString());
    return parts.join('\n');
  }
  /**
   * 服务 UUID 的统一展示形式：**有名字就「短形式 (名字)」，没有就原样**。
   *
   * 两处（提供的服务 / 服务数据）必须走同一个方法 —— 否则同一个 UUID 在
   * 「提供的服务」里显示 FDEE、在「服务数据」里显示完整 128 位，看起来像两个东西。
   */
  private serviceUuidLabel(uuid: string): string {
    const name: string = fieldwatchApplication.serviceUuidName(uuid);
    if (name.length === 0) return uuid;
    const hex: string = uuid.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
    let short: string = uuid;
    if (hex.length === 4) short = hex;
    else if (hex.length === 8) short = hex.substring(4, 8);
    else if (hex.length === 32 && hex.startsWith('0000') && hex.endsWith('00001000800000805F9B34FB')) short = hex.substring(4, 8);
    return short + ' (' + name + ')';
  }
  /** 服务数据记录列表。 */
  private serviceDataText(sighting: Sighting): string {
    const records: ServiceDataRecord[] = sighting.facts.serviceData;
    if (records.length === 0) return '';
    const parts: string[] = [];
    records.slice(0, 4).forEach((item: ServiceDataRecord): void => {
      parts.push(this.serviceUuidLabel(item.uuid) + ': ' + item.dataHex);
    });
    if (records.length > 4) parts.push('+' + (records.length - 4).toString());
    return parts.join('\n');
  }
  /** Wi-Fi 厂商 IE 的 OUI 列表。 */
  private vendorIeText(sighting: Sighting): string {
    const ouis: string[] = sighting.facts.vendorIeOuis;
    if (ouis.length === 0) return '';
    const parts: string[] = [];
    ouis.slice(0, 6).forEach((oui: string): void => {
      // IE 里的 OUI 是 3 字节十六进制；能查到厂商名就一并给出，否则只给 OUI。
      const vendor: string = fieldwatchApplication.vendorForOui(oui);
      parts.push(vendor.length > 0 ? oui + ' (' + vendor + ')' : oui);
    });
    if (ouis.length > 6) parts.push('+' + (ouis.length - 6).toString());
    return parts.join(' · ');
  }
  /**
   * 是否已不在空中：超过 30 秒没有再听到，且不是当前正在刷新的设备。
   *
   * 原版用 `device.gone`；我们的 Sighting 上没有这个标记，
   * 因此按最后听到时间就地判定，避免为它改一遍持久化结构。
   */
  private isGone(sighting: Sighting): boolean {
    return Date.now() - sighting.lastSeen > 30000;
  }
  /** 命中签名的额外关注备注；没有返回空串。 */
  private attentionText(sighting: Sighting): string {
    if (sighting.signatureIds.length === 0) return '';
    const fleets: SignatureFleet[] = fieldwatchApplication.getState().signatures;
    let found: string = '';
    sighting.signatureIds.forEach((id: string): void => {
      if (found.length > 0) return;
      const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
      if (fleet !== undefined && fleet.attentionNote.length > 0) found = fleet.attentionNote;
    });
    return found;
  }
  /** 区块标题：一条分隔线 + 标题，对应原版详情页的分段。 */
  @Builder private detailSection(title: ResourceStr) {
    Row() {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().accent)
    }.width('100%').padding({ top: 10, bottom: 2 })
  }
  /** 一行说明文字（用于提示、免责、警告）。 */
  @Builder private detailHint(text: ResourceStr, tint: string) {
    Text(text).fontSize(12).fontColor(tint).width('100%')
  }
  /** 只在 value 非空时渲染一行，避免满屏「未知」。 */
  @Builder private detailLineIfAny(label: ResourceStr, value: string) {
    if (value.length > 0) this.detailLine(label, value)
  }
  /**
   * 备注区块：自定义名称 + 观察者备注，都可编辑。
   *
   * 对应原版 DeviceDetailScreen 的「Custom name」与「Observer notes」两段。
   * 两条重要语义（原版 RadioBookmarks）：
   *   1. **命名不等于开启告警** —— upsertName 的 alertIfNew 默认 false；
   *   2. **BLE 随机地址不可命名** —— 地址会轮换，名字会绑到死键上。
   */
  /** 已保存的自定义名称；没有则显示「无」。 */
  private savedLabelOrNone(sighting: Sighting): string {
    const label: string = fieldwatchApplication.deviceLabel(sighting.key);
    return label.length > 0 ? label : this.noneText();
  }
  /** 已保存的观察者备注；没有则显示「无」。 */
  private savedNoteOrNone(sighting: Sighting): string {
    const note: string = fieldwatchApplication.deviceNote(sighting.key);
    return note.length > 0 ? note : this.noneText();
  }
  /** 蓝牙公司名；名称库查不到则退回十六进制 ID；没有厂商数据返回空串。 */
  private companyText(sighting: Sighting): string {
    const id: number = sighting.facts.manufacturerId;
    if (id <= 0) return '';
    const name: string = fieldwatchApplication.companyName(id);
    return name.length > 0 ? name : '0x' + id.toString(16).toUpperCase().padStart(4, '0');
  }
  @Builder private buildDeviceEditBlock(sighting: Sighting) {
    this.detailSection($r('app.string.fieldwatch_sec_notes'))
    // @Builder 内不能声明局部变量（ArkTS 限制），取值一律走方法调用。
    if (!this.detailEditOpen) {
      this.detailLine($r('app.string.fieldwatch_detail_custom_name'), this.savedLabelOrNone(sighting))
      this.detailLine($r('app.string.fieldwatch_detail_notes'), this.savedNoteOrNone(sighting))
      Button($r('app.string.fieldwatch_detail_edit')).backgroundColor(Color.Transparent).borderWidth(1)
        .borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text)
        .width('100%').onClick((): void => {
          // 打开编辑时把已保存的值灌进草稿，取消则原样丢弃。
          this.detailNameDraft = fieldwatchApplication.deviceLabel(sighting.key);
          this.detailNotesDraft = fieldwatchApplication.deviceNote(sighting.key);
          this.detailEditOpen = true;
        })
    } else {
      // 随机地址设备：明确说明为什么不能命名，而不是给一个点了没用的输入框。
      if (fieldwatchApplication.canSetCustomName(sighting)) {
        TextInput({ text: this.detailNameDraft,
          placeholder: $r('app.string.fieldwatch_detail_custom_name') }).height(44)
          .maxLength(FieldwatchApplication.MAX_DEVICE_LABEL)
          .onChange((value: string): void => { this.detailNameDraft = value; })
        this.detailHint($r('app.string.fieldwatch_detail_custom_name_hint'), FieldwatchPaletteHolder.get().textDim)
      } else {
        this.detailHint($r('app.string.fieldwatch_detail_custom_name_blocked'), FieldwatchPaletteHolder.get().amber)
      }
      TextInput({ text: this.detailNotesDraft,
        placeholder: $r('app.string.fieldwatch_detail_notes') }).height(44)
        .maxLength(FieldwatchApplication.MAX_DEVICE_NOTE)
        .onChange((value: string): void => { this.detailNotesDraft = value; })
      this.detailHint($r('app.string.fieldwatch_detail_notes_hint'), FieldwatchPaletteHolder.get().textDim)
      Row({ space: 8 }) {
        Button($r('app.string.fieldwatch_detail_save')).layoutWeight(1)
          .height(44).borderRadius(12).backgroundColor($r('app.color.button_primary'))
          .fontColor($r('app.color.fw_on_accent'))
          .onClick((): void => {
            if (fieldwatchApplication.canSetCustomName(sighting)) {
              fieldwatchApplication.upsertDeviceLabel(sighting.key, this.detailNameDraft);
            }
            fieldwatchApplication.upsertDeviceNote(sighting.key, this.detailNotesDraft,
              fieldwatchApplication.suggestDeviceLabel(sighting));
            this.detailEditOpen = false;
            // 不需要手动触发刷新：本页每秒重读一次状态，改完会在下一拍显示出来。
          })
        Button($r('app.string.fieldwatch_detail_hide')).layoutWeight(1)
          .height(44).borderRadius(12).backgroundColor(Color.Transparent).borderWidth(1)
          .borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text)
          .onClick((): void => { this.detailEditOpen = false; })
      }.width('100%')
    }
  }
  @Builder private buildDetailFields(sighting: Sighting) {
    // ── 头部 ──
    Row({ space: 10 }) { FieldwatchDeviceTypeIcon({ kind: sighting.kind, category: this.categoryFor(sighting), tint: this.tintFor(sighting) }); Text(fieldwatchApplication.displayName(sighting)).fontSize(18).fontColor($r('app.color.text_primary')) }
    if (this.isGone(sighting)) {
      this.detailHint($r('app.string.fieldwatch_detail_gone'), FieldwatchPaletteHolder.get().amber)
    }

    // ── 身份 ──
    this.detailSection($r('app.string.fieldwatch_sec_identity'))
    this.detailLine($r('app.string.fieldwatch_detail_type'), sighting.kind.toUpperCase())
    this.detailLine($r('app.string.fieldwatch_detail_name'), this.nameText(sighting))
    this.detailLine($r('app.string.fieldwatch_detail_address'), fieldwatchApplication.describeAddress(sighting))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_address_type'), this.addressTypeText(sighting))
    // 星闪的真实 MAC 属系统级权限，应用拿不到。地址很可能是系统分配的匿名标识、
    // 会随时间变化 —— 必须明确告诉用户，否则他会把它当成稳定的设备标识。
    if (sighting.kind === RadioKind.NEARLINK) {
      Text($r('app.string.fieldwatch_detail_nl_address_note')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().amber)
    }
    // 厂商来自 OUI 名称库；查不到就不占一行，避免满屏「未知」。
    this.detailLineIfAny($r('app.string.fieldwatch_detail_vendor'), sighting.facts.manufacturer)
    // 网络名称用独立的 label：复用「名称」会让身份区块里出现两行「名称」。
    this.detailLineIfAny($r('app.string.fieldwatch_detail_ssid'), sighting.facts.ssid)

    // ── 信号 ──
    this.detailSection($r('app.string.fieldwatch_sec_signal'))
    this.detailLine($r('app.string.fieldwatch_detail_rssi'), sighting.rssi.toString() + ' dBm')
    this.detailLine($r('app.string.fieldwatch_detail_location'), this.locationText(sighting))
    // 发射功率：-128 表示广告里没带这一项。
    if (sighting.facts.txPower > -128) {
      this.detailLine($r('app.string.fieldwatch_detail_tx_power'), sighting.facts.txPower.toString() + ' dBm')
      this.detailHint($r('app.string.fieldwatch_detail_tx_power_hint'), FieldwatchPaletteHolder.get().textDim)
    }
    this.detailLine($r('app.string.fieldwatch_detail_frequency'), wifiFactValue(sighting.kind, sighting.facts.frequencyMhz, ' MHz', this.notApplicableText()))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_channel'), this.channelText(sighting))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_generation'), this.generationText(sighting))
    this.detailLine($r('app.string.fieldwatch_detail_band'), this.bandText(sighting))
    this.detailLine($r('app.string.fieldwatch_detail_channel_width'), this.channelWidthText(sighting))

    // ── 蓝牙广播 ──
    if (sighting.kind === RadioKind.BLE) {
      this.detailSection($r('app.string.fieldwatch_sec_ble'))
      this.detailLine($r('app.string.fieldwatch_detail_nl_connectable'),
        resolveResourceString(this.getUIContext().getHostContext(),
          sighting.facts.connectable ? $r('app.string.fieldwatch_detail_nl_yes') : $r('app.string.fieldwatch_detail_nl_no')))
      this.detailLineIfAny($r('app.string.fieldwatch_detail_appearance'), this.appearanceText(sighting))
      this.detailLineIfAny($r('app.string.fieldwatch_detail_appearance_code'), this.appearanceCodeText(sighting))
      if (sighting.facts.advertiseFlags >= 0) {
        this.detailLine($r('app.string.fieldwatch_detail_flags'), '0x' + sighting.facts.advertiseFlags.toString(16).toUpperCase().padStart(2, '0'))
      }
    }
    // 星闪独有的两项信息：设备类型由广播直接声明（不靠特征库推断），
    // 以及设备是否声明可连接。BLE 侧没有等价字段。
    if (sighting.kind === RadioKind.NEARLINK) {
      this.detailSection($r('app.string.fieldwatch_sec_ble'))
      this.detailLine($r('app.string.fieldwatch_detail_nl_class'), this.nearLinkClassText(sighting))
      this.detailLine($r('app.string.fieldwatch_detail_nl_connectable'),
        resolveResourceString(this.getUIContext().getHostContext(),
          sighting.facts.nearLinkConnectable ? $r('app.string.fieldwatch_detail_nl_yes')
            : $r('app.string.fieldwatch_detail_nl_no')))
    }

    // ── Wi-Fi 接入点 ──
    if (sighting.kind === RadioKind.WIFI) {
      this.detailSection($r('app.string.fieldwatch_sec_wifi'))
      this.detailLine($r('app.string.fieldwatch_detail_security'), this.securityText(sighting))
      if (sighting.facts.hiddenSsid) {
        this.detailLine($r('app.string.fieldwatch_detail_hidden_ssid'), resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_detail_hidden_yes')))
      }
      this.detailLineIfAny($r('app.string.fieldwatch_detail_vendor_ie'), this.vendorIeText(sighting))
    }

    // ── 解码字段 ──
    this.detailSection($r('app.string.fieldwatch_sec_decoded'))
    this.detailLine($r('app.string.fieldwatch_detail_decoded'), this.decodedText(sighting))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_service_uuids'), this.serviceUuidText(sighting))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_service_data'), this.serviceDataText(sighting))

    // ── 广播里的厂商数据 ──
    // 整段只在**确实有厂商数据**时出现：否则会出现一个只有标题、下面空白的区块。
    if (sighting.kind === RadioKind.BLE && (sighting.facts.manufacturerId > 0 || sighting.facts.manufacturerDataHex.length > 0)) {
      this.detailSection($r('app.string.fieldwatch_sec_maker'))
      this.detailLineIfAny($r('app.string.fieldwatch_detail_vendor'), this.companyText(sighting))
      this.detailLineIfAny($r('app.string.fieldwatch_detail_raw_payload'),
        sighting.facts.manufacturerDataHex.length > 0
          ? Math.floor(sighting.facts.manufacturerDataHex.length / 2).toString() + ' B: ' + sighting.facts.manufacturerDataHex
          : '')
    }

    // ── 本次会话 ──
    this.detailSection($r('app.string.fieldwatch_sec_session'))
    this.detailLine($r('app.string.fieldwatch_detail_seen_count'), sighting.count.toString())
    this.detailLine($r('app.string.fieldwatch_detail_fresh'), sighting.fresh ? resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_detail_fresh_value')) : resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_detail_cached_value')))
    this.detailLineIfAny($r('app.string.fieldwatch_detail_raw_ad'), sighting.facts.rawAdHex)

    // ── 特征族 ──
    this.detailSection($r('app.string.fieldwatch_sec_family'))
    this.detailLine($r('app.string.fieldwatch_detail_signatures'), this.signatureText(sighting))
    this.detailLine($r('app.string.fieldwatch_detail_signature_reason'), this.signatureReasonText(sighting))

    // ── 额外关注 ──
    if (this.attentionText(sighting).length > 0) {
      this.detailSection($r('app.string.fieldwatch_sec_attention'))
      this.detailHint(this.attentionText(sighting), FieldwatchPaletteHolder.get().amber)
      this.detailHint($r('app.string.fieldwatch_detail_attention_note'), FieldwatchPaletteHolder.get().textDim)
    }

    // ── 备注：自定义名称 + 观察者备注（可编辑）──
    this.buildDeviceEditBlock(sighting)

    Row({ space: 8 }) {
      Button(this.isWatched(sighting) ? $r('app.string.fieldwatch_detail_unwatch') : $r('app.string.fieldwatch_detail_watch')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { fieldwatchApplication.toggleWatch(sighting); })
      // 跳转前必须先关掉详情 Sheet：Sheet 绑在本页，跳转不会自动收起它，
      // 结果搜寻页/编辑器会渲染在 Sheet 后面，看起来像「打开失败」。
      Button($r('app.string.fieldwatch_hunt_start')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { this.onStartHunt(sighting.key); })
      Button($r('app.string.fieldwatch_signatures_create_from_device')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { this.onCreateSignature(sighting.key); })
      Button($r('app.string.fieldwatch_detail_share')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { fieldwatchApplication.shareSighting(sighting); })
    }.width('100%')
  }
  private isWatched(sighting: Sighting): boolean { return fieldwatchApplication.getState().watchlist.some((target: WatchTarget): boolean => target.deviceKey === sighting.key && target.alert); }
  /** 预览卡提示：有命中签名时显示签名名，否则用通用提示。 */
  private previewHint(sighting: Sighting): string {
    const names: string[] = matchedSignatureNames(sighting.signatureIds, fieldwatchApplication.getState().signatures);
    if (names.length > 0) return names[0];
    return resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_device_preview_open'));
  }
  private tintFor(sighting: Sighting): string {
    const color: string = signatureColorAt(signatureColorIndex(sighting, fieldwatchApplication.getState().signatures));
    if (color.length > 0) return color;
    return sighting.kind === RadioKind.WIFI ? FieldwatchPaletteHolder.get().cyan : FieldwatchPaletteHolder.get().accent;
  }
  private categoryFor(sighting: Sighting): SignatureClass {
    const state = fieldwatchApplication.getState();
    const signatureId: string = sighting.signatureIds.length > 0 ? sighting.signatureIds[0] : '';
    const signature = state.signatures.find((item: SignatureFleet): boolean => item.id === signatureId);
    return signature === undefined ? SignatureClass.OTHER : foldedSignatureClass(signature.category);
  }
  private locationText(sighting: Sighting): string {
    const text: string = fieldwatchApplication.describeLocation(sighting);
    return text.length > 0 ? text : resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_none'));
  }
  private notApplicableText(): string { return resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_detail_not_applicable')); }
  private noneText(): string { return resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_none')); }
  private signatureText(sighting: Sighting): string {
    if (sighting.signatureIds.length === 0) return this.noneText();
    const fleets: SignatureFleet[] = fieldwatchApplication.getState().signatures;
    const names: string[] = [];
    sighting.signatureIds.forEach((id: string): void => {
      const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === id);
      names.push(fleet === undefined ? id : fleet.name);
    });
    return names.join(' · ');
  }
  private signatureReasonText(sighting: Sighting): string {
    if (sighting.signatureIds.length === 0) return this.noneText();
    const explanations: SignatureMatchExplanation[] = fieldwatchApplication.explainSighting(sighting);
    if (explanations.length === 0) return this.noneText();
    const parts: string[] = [];
    explanations.slice(0, 2).forEach((item: SignatureMatchExplanation): void => { parts.push(item.fleetName + ' ← ' + item.matchedRules.join(', ')); });
    return parts.join(' | ');
  }
  private decodedText(sighting: Sighting): string {
    if (sighting.decodedFields.length === 0) return this.noneText();
    const parts: string[] = [];
    sighting.decodedFields.forEach((value: DecodedFieldValue): void => { parts.push(value.label + ': ' + value.text); });
    return parts.join(' · ');
  }
  private nameText(sighting: Sighting): string {
    const text: string = fieldwatchApplication.describeName(sighting);
    return text.length > 0 ? text : resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_none'));
  }
  @Builder private detailLine(label: ResourceStr, value: string) { Row() { Text(label).width(126).fontColor($r('app.color.text_secondary')); Text(value).layoutWeight(1).fontColor($r('app.color.text_primary')) }.width('100%') }
  /**
   * 原版头部统计行：BLE / Wi-Fi / 星闪 / 总信号源。
   *
   * **此前星闪被算进了 Wi-Fi** —— 原来写的是 `if (BLE) ble += 1; else wifi += 1;`，
   * 二分法只有两支，星闪落进 `else`。所以头部显示的 Wi-Fi 数量其实是「Wi-Fi + 星闪」。
   * 现在三分支各自统计。
   *
   * 标签也改用资源（此前硬编码 `'BLE '` / `'Wi-Fi '`，英文界面下不会本地化）。
   */
  private statsLine(): string {
    const counts: number[] = countSightingsByKind(this.sightings);
    const ble: number = counts[0];
    const wifi: number = counts[1];
    const nearLink: number = counts[2];
    const parts: string[] = [];
    parts.push(this.radioLabel('app.string.fieldwatch_radio_ble') + ' ' + ble.toString());
    parts.push(this.radioLabel('app.string.fieldwatch_radio_wifi') + ' ' + wifi.toString());
    parts.push(this.radioLabel('app.string.fieldwatch_radio_nearlink') + ' ' + nearLink.toString());
    parts.push(this.sightingCountText(this.sightings.length));
    return parts.join(' · ');
  }

  /** Live 页自己的资源取字助手（`label` 是 Filters 页的方法，跨结构体不可用）。 */
  private radioLabel(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  /**
   * 某路无线电此刻是否**真的在工作**。
   *
   * 三路扫描器报告的 phase 取值不同：
   *   BLE / 星闪 -> `ScanState`（idle / scanning / paused / error）
   *   Wi-Fi     -> `WifiScanPhase`（12 个值，scanning / ready / waiting_for_retry / stale …）
   * 但「不可用」这一类是共通的，统一排除即可；其余都算在工作。
   */
  private radioActive(snapshot: RadioSourceSnapshot): boolean {
    return isRadioPhaseActive(snapshot.phase);
  }

  /**
   * 实时页右上角：当前**实际在工作的无线电组合**，例如「Wi-Fi+蓝牙+星闪模式」。
   *
   * 此前这里显示的是「N 次观测」。观测总数已经在下方统计行里，
   * 右上角这个位置用来回答「我现在到底在扫什么」更有价值 ——
   * 尤其是星闪开关、Wi-Fi 位置服务、权限被拒这些情况下，
   * 用户一眼就能看出哪一路没起来。
   */
  private workingModeText(): string {
    const state: FieldwatchApplicationState = fieldwatchApplication.getState();
    const parts: string[] = [];
    if (this.radioActive(state.wifiSnapshot)) parts.push(this.radioLabel('app.string.fieldwatch_radio_wifi'));
    if (this.radioActive(state.bleSnapshot)) parts.push(this.radioLabel('app.string.fieldwatch_radio_ble'));
    if (this.radioActive(state.nearLinkSnapshot)) parts.push(this.radioLabel('app.string.fieldwatch_radio_nearlink'));
    if (parts.length === 0) return this.radioLabel('app.string.fieldwatch_mode_idle');
    return parts.join('+') + this.radioLabel('app.string.fieldwatch_mode_suffix');
  }
  /** RSSI 条长度：-100 dBm 到 -35 dBm 映射到 4%..100%。 */
  private rssiBarWidth(item: Sighting): string {
    const ratio: number = (item.rssi + 100) / 65;
    const clamped: number = ratio < 0.04 ? 0.04 : (ratio > 1 ? 1 : ratio);
    return (clamped * 100).toFixed(1) + '%';
  }
  /** 首/末次：原版的「首 2m 7s · 末 6s」。 */
  private firstLastText(item: Sighting): string {
    // **`firstSeen` / `lastSeen` 是 epoch 毫秒，与 `Date.now()` 同单位，直接相减。**
    //
    // 这里原有注释写着「是 Unix 秒，必须 ×1000，否则会渲染出「首 349147h」」。
    // **那句话曾经是对的**（确实出现过 349147h），说明 `seenAt` 早期确实是秒；
    // 后来改成毫秒时散落各处的 `×1000` 没跟着改 —— 反过来制造了它本想避免的量级错误。
    // 实证：RDB 里 `seen_at` 范围 1791482209289→1791482301489，与设备 `Date.now()` 同量级。
    const now: number = Date.now();
    const firstMillis: number = item.firstSeen;
    const lastMillis: number = item.lastSeen;
    return '首 ' + this.durationText(now - firstMillis) + ' · ' + (lastMillis >= now - 2000 ? '末 now' : '末 ' + this.durationText(now - lastMillis));
  }
  private durationText(millis: number): string {
    const seconds: number = Math.max(0, Math.floor(millis / 1000));
    if (seconds < 60) return seconds.toString() + 's';
    const minutes: number = Math.floor(seconds / 60);
    const rest: number = seconds % 60;
    if (minutes < 60) return minutes.toString() + 'm ' + rest.toString() + 's';
    return Math.floor(minutes / 60).toString() + 'h ' + (minutes % 60).toString() + 'm';
  }
  /** 类别徽章底色：签名色 18% 透明，未命中用中性面板色。 */
  private badgeColor(item: Sighting): string {
    const names: string[] = matchedSignatureNames(item.signatureIds, fieldwatchApplication.getState().signatures);
    if (names.length === 0) return FieldwatchPaletteHolder.get().badgeBg;
    return this.tintFor(item) + '2E';
  }
  /** 该类别当前命中的设备数。 */
  private classCount(cls: SignatureClass): number {
    return this.sightings.filter((item: Sighting): boolean => this.categoryFor(item) === cls).length;
  }
  /** 该类别下已启用的目录条目数（原版的「N 个特征」）。 */
  private classFleetCount(cls: SignatureClass): number {
    return fieldwatchApplication.getState().signatures.filter((fleet: SignatureFleet): boolean =>
      foldedSignatureClass(fleet.category) === cls && fleet.enabled).length;
  }
  /** 原版按类别视图：大行 = 类别徽章 + 类别名 + N 个特征 + ▸ 计数。 */
  private isClassExpanded(cls: SignatureClass): boolean { return this.expandedClasses.indexOf(cls) >= 0; }
  /**
   * 展开 / 收起某个类别。
   *
   * 用 animateTo 包住状态变更，让展开区域的高度与箭头一起过渡；
   * 此前分类行有个 ▸ 箭头却完全没有展开逻辑，看起来能点其实点不动。
   */
  private toggleClass(cls: SignatureClass): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, (): void => {
      const at: number = this.expandedClasses.indexOf(cls);
      if (at >= 0) this.expandedClasses.splice(at, 1);
      else this.expandedClasses.push(cls);
    });
  }
  /** 类别下的设备行；点开详情。 */
  @Builder private buildClassDeviceRow(item: Sighting) {
    Row({ space: 10 }) {
      Stack() { FieldwatchDeviceTypeIcon({ kind: item.kind, category: this.categoryFor(item), tint: this.tintFor(item), glyphSize: this.rowM().iconGlyph }) }
        .width(this.rowM().iconBox).height(this.rowM().iconBox).borderRadius(this.rowM().iconBox / 2).backgroundColor(this.badgeColor(item))
      Text(fieldwatchApplication.displayName(item)).fontSize(this.rowM().titleSize).fontColor(FieldwatchPaletteHolder.get().text)
        .maxLines(1).layoutWeight(1)
      Text(item.rssi.toString() + ' dBm').fontSize(this.rowM().valueSize).fontColor(FieldwatchPaletteHolder.get().rssiBar)
    }.width('100%').padding({ left: 52, right: 14, top: 8, bottom: 8 })
      .onClick((): void => { this.openDetailFor(item); })
  }
  @Builder private buildClassRow(cls: SignatureClass) {
    Column({ space: 0 }) {
    Row({ space: 12 }) {
      Stack() { FieldwatchDeviceTypeIcon({ kind: RadioKind.BLE, category: cls, tint: FieldwatchPaletteHolder.get().accent, glyphSize: 22 }) }
        .width(40).height(40).borderRadius(20).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
      Column({ space: 3 }) {
        Text(signatureClassLabel(cls)).fontSize(18).fontColor(FieldwatchPaletteHolder.get().text)
        Text(this.classFleetCount(cls).toString() + ' ' + resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_class_fleet_unit'))).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.classCount(cls).toString()).fontSize(15).fontColor(FieldwatchPaletteHolder.get().textDim)
      // 箭头随展开状态旋转，给用户明确的反馈。
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
        .rotate({ angle: this.isClassExpanded(cls) ? 90 : 0 })
    }.width('100%').padding(14)
      .onClick((): void => { this.toggleClass(cls); })
    // 展开后**先按品牌分组，再在品牌下列设备**。
    //
    // 之前是一长串平铺的设备：同类里混着 Apple、Samsung、华为…，
    // 用户没法回答「这一类里有几个牌子、各多少台」（实测反馈）。
    // 品牌取自与列表页同一个解析链（OUI -> 蓝牙公司 ID 兜底），口径一致。
    if (this.isClassExpanded(cls)) {
      ForEach(this.classBrands(cls), (brand: string): void => {
        this.buildBrandHeader(brand, this.brandDevices(cls, brand).length)
        ForEach(this.brandDevices(cls, brand),
          (item: Sighting): void => { this.buildClassDeviceRow(item) }, (item: Sighting): string => item.key)
      }, (brand: string): string => cls + '|' + brand)
    }
    }.width('100%').backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
      .clip(true)
  }
  /**
   * 某类别下的品牌列表，按设备数降序。
   *
   * 无厂商标识的设备归到「未知品牌」—— 单独成组而不是丢掉，
   * 否则用户会以为这些设备凭空消失了。
   */
  private classBrands(cls: SignatureClass): string[] {
    return groupByBrand(this.sightings.filter((item: Sighting): boolean =>
      this.categoryFor(item) === cls), (item: Sighting): string => this.brandOf(item));
  }

  /** 某类别 + 某品牌下的设备。 */
  private brandDevices(cls: SignatureClass, brand: string): Sighting[] {
    return this.sightings.filter((item: Sighting): boolean =>
      this.categoryFor(item) === cls && this.brandOf(item) === brand);
  }

  /** 设备品牌：优先厂商名，没有则明确的「未知品牌」。 */
  private brandOf(item: Sighting): string {
    const vendor: string = fieldwatchApplication.vendorOfSighting(item);
    return vendor.length > 0 ? vendor : this.radioLabel('app.string.fieldwatch_brand_unknown');
  }

  /** 品牌小标题：缩进在类别之下，用一个小圆点 + 名称 + 数量。 */
  @Builder private buildBrandHeader(brand: string, count: number) {
    Row({ space: 8 }) {
      Column().width(5).height(5).borderRadius(3)
        .backgroundColor(FieldwatchPaletteHolder.get().accent)
      Text(brand).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1).layoutWeight(1)
      Text(count.toString()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
    }
    .width('100%')
    .padding({ left: 34, right: 16, top: 10, bottom: 4 })
  }

  /** 当前筛选下要渲染的类别。 */
  private filteredClasses(): SignatureClass[] {
    const all: SignatureClass[] = visibleSignatureClasses();
    if (!this.classOnlyHits) return all;
    return all.filter((cls: SignatureClass): boolean => this.classCount(cls) > 0);
  }

  /**
   * 分类视图的汇总行，对应原版的
   * 「102 个信号源 —— 55 个未匹配 —— 1 个属于多个分类 —— 15 个空值已隐藏」。
   *
   * 它回答的是「筛选到底藏了什么」—— 只放一个开关而不说藏了多少，
   * 用户没法判断该不该打开。
   */
  private classSummaryText(): string {
    const total: number = this.sightings.length;
    let matched: number = 0;
    let multi: number = 0;
    this.sightings.forEach((item: Sighting): void => {
      const names: string[] = matchedSignatureNames(item.signatureIds, fieldwatchApplication.getState().signatures);
      if (names.length > 0) matched += 1;
      if (names.length > 1) multi += 1;
    });
    let empty: number = 0;
    visibleSignatureClasses().forEach((cls: SignatureClass): void => {
      if (this.classCount(cls) === 0) empty += 1;
    });
    const parts: string[] = [];
    parts.push(this.radioLabel('app.string.fieldwatch_class_summary_total').replace('%s', total.toString()));
    parts.push(this.radioLabel('app.string.fieldwatch_class_summary_unmatched').replace('%s', (total - matched).toString()));
    if (multi > 0) parts.push(this.radioLabel('app.string.fieldwatch_class_summary_multi').replace('%s', multi.toString()));
    if (this.classOnlyHits && empty > 0) parts.push(this.radioLabel('app.string.fieldwatch_class_summary_hidden').replace('%s', empty.toString()));
    return parts.join(' —— ');
  }

  /** 分类视图顶部的「显示全部 / 仅显示有结果」二选一。 */
  @Builder private buildClassFilterRow() {
    Row({ space: 8 }) {
      this.buildClassFilterChip($r('app.string.fieldwatch_class_show_all'), false)
      this.buildClassFilterChip($r('app.string.fieldwatch_class_only_hits'), true)
    }.width('100%')
  }

  /** 与 `buildViewChip` 同一套样式，保证分类页的筛选条和视图芯片观感一致。 */
  @Builder private buildClassFilterChip(label: ResourceStr, onlyHits: boolean) {
    Button(label).backgroundColor(Color.Transparent).borderWidth(1).layoutWeight(1)
      .fontSize(14)
      .fontColor(this.classOnlyHits === onlyHits ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      .borderColor(this.classOnlyHits === onlyHits ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
      .onClick((): void => {
        this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseInOut }, (): void => {
          this.classOnlyHits = onlyHits;
        });
      })
  }

  @Builder private buildClassList() {
    Scroll() {
      Column({ space: 10 }) {
        this.buildClassFilterRow()
        Text(this.classSummaryText()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        ForEach(this.filteredClasses(), (cls: SignatureClass): void => { this.buildClassRow(cls) }, (cls: SignatureClass): string => cls)
      }.width('100%').padding({ left: 16, right: 16, bottom: 96 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  // ── 信号轨迹（原版 hybrid + sparklines）──
  //
  // 原版把「雷达 + 折线列表」合在一屏，折线就是每台设备的 RSSI 随时间变化。
  // 我们的「强度」视图只有一根当前值的条，看不出趋势，所以单开一个视图。

  /** sparkline 画框尺寸（vp）。固定尺寸让 `Path` 的命令串可以直接用绝对坐标。 */
  private static readonly SPARK_W: number = 132;
  private static readonly SPARK_H: number = 34;

  /**
   * RSSI 样本 → `Path` 的 commands 串。
   *
   * 纵轴映射与 `rssiBarWidth` 保持一致：**-100 dBm 到 -35 dBm 映射到整框高度**，
   * 这样同一条轨迹在条和折线上读出来的强弱一致。
   *
   * 用 `Path` 而不是 `Polyline`：后者的 `points` 声明是 `Array<any>`，
   * ArkTS 严格模式禁 `any`，传进去要绕类型；`commands` 是纯字符串，最省事也最稳。
   */
  private sparklinePath(item: Sighting): string {
    // **纵轴范围与副标题里的「lowest ~ highest」用同一个来源。**
    //
    // 固定范围时，高于 -35 dBm 的读数全被 clamp 到顶部，
    // 折线贴顶成一条直线，而旁边却写着 -29.5 dBm —— 图表与图例对不上。
    // **`Path.commands` 用 px，而 `.width()` 用 vp。**
    //
    // 原来两边都传 `SPARK_W`：命令按 px 解释、框按 vp，
    // 折线只画在框的左半边（实测反馈「轨迹图不对」）。
    const range: SparkRange = sparkRangeOf(item.rssiSamples);
    return sparklineCommands(item.rssiSamples,
      this.getUIContext().vp2px(FieldwatchLivePage.SPARK_W),
      this.getUIContext().vp2px(FieldwatchLivePage.SPARK_H), range);
  }

  /** 一条轨迹：样本不足时给文字提示，而不是画一条假的直线。 */
  @Builder private buildSparkline(item: Sighting) {
    Stack() {
      if (item.rssiSamples.length >= 2) {
        Path()
          .commands(this.sparklinePath(item))
          .width(FieldwatchLivePage.SPARK_W).height(FieldwatchLivePage.SPARK_H)
          .stroke(this.tintFor(item)).strokeWidth(2).fill(Color.Transparent)
          .strokeLineJoin(LineJoinStyle.Round).strokeLineCap(LineCapStyle.Round)
      } else {
        Text($r('app.string.fieldwatch_trail_waiting')).fontSize(10).fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }
    .width(FieldwatchLivePage.SPARK_W).height(FieldwatchLivePage.SPARK_H)
    .borderRadius(6).backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /**
   * RSSI 趋势：末样本 − 首样本。正数变强、负数变弱。
   *
   * `FieldwatchDomainService` 里本来就有 `rssiTrend` / `rssiAverage`，
   * **但全仓没有任何调用点** —— 所以界面上一直看不到均值与趋势。
   * 这里按同一口径直接算，不额外绕一层服务。
   */
  private trailTrend(item: Sighting): number {
    const samples: number[] = item.rssiSamples;
    if (samples.length < 2) return 0;
    return samples[samples.length - 1] - samples[0];
  }

  /** 轨迹行的副标题：样本数 + 均值 + 极值范围。 */
  private trailSubtitle(item: Sighting): string {
    const samples: number[] = item.rssiSamples;
    if (samples.length === 0) return '';
    let lowest: number = samples[0];
    let highest: number = samples[0];
    let total: number = 0;
    samples.forEach((value: number): void => {
      if (value < lowest) lowest = value;
      if (value > highest) highest = value;
      total += value;
    });
    const mean: number = Math.round(total / samples.length);
    const template: string = this.radioLabel('app.string.fieldwatch_trail_samples');
    return template.replace('%s', samples.length.toString())
      + ' · ' + lowest.toString() + ' ~ ' + highest.toString()
      + ' · ' + this.radioLabel('app.string.fieldwatch_detail_average') + ' ' + mean.toString();
  }

  /** 信号轨迹列表：每台设备一行，右侧是 RSSI 折线。 */
  @Builder private buildTrailList() {
    Scroll() {
      Column({ space: 8 }) {
        ForEach(sortSightingsForLiveMode(this.sightings, this.mode), (item: Sighting): void => {
          Row({ space: 10 }) {
            Stack() { FieldwatchDeviceTypeIcon({ kind: item.kind, category: this.categoryFor(item), tint: this.tintFor(item), glyphSize: this.rowM().iconGlyph }) }
              .width(this.rowM().iconBox).height(this.rowM().iconBox).borderRadius(this.rowM().iconBox / 2).backgroundColor(this.badgeColor(item))
            Column({ space: 3 }) {
              Text(fieldwatchApplication.displayName(item)).fontSize(this.rowM().titleSize).fontWeight(FontWeight.Medium)
                .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
              Text(this.trailSubtitle(item)).fontSize(this.rowM().subtitleSize).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Column({ space: 4 }) {
              Row({ space: 4 }) {
                SymbolGlyph($r(this.trailTrend(item) > 0 ? 'sys.symbol.arrow_up' : (this.trailTrend(item) < 0 ? 'sys.symbol.arrow_down' : 'sys.symbol.equal')))
                  .fontSize(11).fontColor([this.tintFor(item)])
                Text(item.rssi.toString()).fontSize(this.rowM().valueSize).fontColor(FieldwatchPaletteHolder.get().rssiBar)
              }
              this.buildSparkline(item)
            }.alignItems(HorizontalAlign.End)
          }.width('100%').padding(this.rowM().padding).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(this.rowM().radius)
            .onClick((): void => { this.openDetailFor(item); })
        }, (item: Sighting): string => item.key)
      }.width('100%').padding({ left: 16, right: 16, bottom: 96 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder private buildList() {
    Scroll() {
    Column({ space: 8 }) { ForEach(sortSightingsForLiveMode(this.sightings, this.mode), (item: Sighting): void => {
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Stack() { FieldwatchDeviceTypeIcon({ kind: item.kind, category: this.categoryFor(item), tint: this.tintFor(item), glyphSize: this.rowM().iconGlyph }) }
            .width(this.rowM().iconBox).height(this.rowM().iconBox).borderRadius(this.rowM().iconBox / 2).backgroundColor(this.badgeColor(item))
          Column({ space: 3 }) {
            Text(fieldwatchApplication.displayName(item)).fontSize(this.rowM().titleSize).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1);
            Row({ space: 5 }) {
              SymbolGlyph($r(item.kind === RadioKind.WIFI ? 'sys.symbol.wifi' : 'sys.symbol.bluetooth')).fontSize(12).fontColor([FieldwatchPaletteHolder.get().textDim])
              Text(this.listSubtitle(item)).fontSize(this.rowM().subtitleSize).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1).layoutWeight(1);
            }.width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Column({ space: 2 }) {
            Text((item.rssi > -90 ? '= ' : '< ') + item.rssi.toString()).fontSize(this.rowM().valueSize).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().rssiBar)
            // 频率受 §12.2「显示频率/信道」控制。
            if (this.showFrequency && item.facts.frequencyMhz > 0) Text(item.facts.frequencyMhz.toString() + 'MHz').fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
          }.alignItems(HorizontalAlign.End)
        }.width('100%')
        // RSSI 条受 §12.2「显示 RSSI 条」控制。
        if (this.showRssiBar) {
          Row() { Row().width(this.rssiBarWidth(item)).height(4).borderRadius(2).backgroundColor(FieldwatchPaletteHolder.get().rssiBar) }
            .width('100%').height(4).borderRadius(2).backgroundColor(FieldwatchPaletteHolder.get().rssiTrack)
        }
        // First/Last seen 受 §12.2「显示 First seen / Last seen」控制。
        if (this.showSeenTimes) Text(this.firstLastText(item)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%').padding(this.rowM().padding).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(this.rowM().radius)
      // 列表行必须能点开详情：雷达图标一直支持，列表此前漏了 onClick，
      // 于是「强度 / 时间线」两个视图点了没有任何反应。
      .onClick((): void => { this.openDetailFor(item); });
    }, (item: Sighting): string => item.key) }.width('100%').padding({ left: 16, right: 16, bottom: 96 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  /** 当前列表行尺寸。四个视图统一从这里取，不再各写魔法数字。 */
  private rowM(): FieldwatchRowMetrics { return rowMetricsFor(this.compactRows); }

  private sightingCountText(count: number): string {
    const template: string = resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_sighting_count'));
    return template.replace('%s', count.toString());
  }
  private listSubtitle(item: Sighting): string {
    let base: string = '';
    if (this.mode === FieldwatchLiveMode.TIMELINE) base = formatClockTime(item.lastSeen) + ' · ' + this.sightingCountText(item.count);
    else if (this.mode === FieldwatchLiveMode.CLASS) base = item.kind.toUpperCase() + ' · ' + this.categoryFor(item).toUpperCase();
    else base = item.kind.toUpperCase() + (item.facts.frequencyMhz > 0 ? ' · ' + item.facts.frequencyMhz.toString() + ' MHz' : '');
    // §12.2「显示签名名称」：命中签名时把签名名放在最前面，再解码标签，再类型/频率。
    const signature: string = this.showFleetName ? fieldwatchApplication.signatureNameOf(item) : '';
    const chips: string[] = liveDecodeLabels(item.decodedFields);
    const parts: string[] = [];
    if (signature.length > 0) parts.push(signature);
    chips.forEach((chip: string): void => { parts.push(chip); });
    parts.push(base);
    return parts.join(' · ');
  }
  @Builder private buildViewChip(label: ResourceStr, mode: FieldwatchLiveMode) {
    Button(label).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).height(36).layoutWeight(1).fontSize(15).backgroundColor(Color.Transparent).borderRadius(12).borderWidth(1)
      .fontColor(this.mode === mode ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      .borderColor(this.mode === mode ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
      .onClick((): void => { this.switchLiveMode(mode); })
  }
  /**
   * 无扫描权限时的受限说明卡。
   * 不弹系统权限窗，先由应用把「用来干什么 / 不给会怎样」讲清楚，用户点按钮才申请。
   */
  @Builder private buildRestrictedCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(16).fontColor([FieldwatchPaletteHolder.get().warn])
        Text($r('app.string.fieldwatch_restricted_title')).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
      }.width('100%')
      Text($r('app.string.fieldwatch_restricted_body')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text($r('app.string.fieldwatch_restricted_baseline')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      Row({ space: 8 }) {
        // 用统一按钮：底色与文字色成对定义，不会再出现「荧光绿底 + 默认白字」。
        FieldwatchButton({ label: $r('app.string.fieldwatch_restricted_enable_ble'), tone: FieldwatchButtonTone.PRIMARY,
          compact: true, fillWidth: false, disabled: this.permissionBusy,
          onTap: (): void => { void this.enableScanning(); } }).layoutWeight(1)
        // Wi-Fi 扫描不需要授权，因此这里没有对应的「开启」按钮。
        // 星闪：仅在设备支持且尚未授权时出现，与蓝牙按钮同一套流程。
        if (fieldwatchApplication.nearLinkAvailable() && this.nearLinkMissing) {
          FieldwatchButton({ label: $r('app.string.fieldwatch_restricted_enable_nl'), tone: FieldwatchButtonTone.OUTLINE,
            compact: true, fillWidth: false, disabled: this.permissionBusy,
            onTap: (): void => { void this.enableNearLinkScanning(); } }).layoutWeight(1)
        }
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }
  /** 申请星闪权限；成功后立即刷新权限快照与扫描。 */
  private async enableNearLinkScanning(): Promise<void> {
    this.permissionBusy = true;
    await fieldwatchApplication.requestNearLinkPermission();
    this.permissionBusy = false;
    this.afterPermissionChange();
  }
  private async enableScanning(): Promise<void> {
    this.permissionBusy = true;
    await fieldwatchApplication.requestPermission(FieldwatchPermissionKind.BLUETOOTH);
    this.permissionBusy = false;
    this.afterPermissionChange();
  }

  /** 授权结果回来后：有能力就启动扫描，并刷新受限态。 */
  private afterPermissionChange(): void {
    const snapshot: FieldwatchCapabilitySnapshot = fieldwatchApplication.permissionSnapshot();
    this.bleMissing = snapshot.bleUnavailable();
    fieldwatchApplication.startScan();
    this.refresh();
  }
  @Builder private buildLiveOverlay() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.fieldwatch_app_title')).fontSize(24).fontWeight(FontWeight.Bold).letterSpacing(1.8).fontColor(FieldwatchPaletteHolder.get().headerText)
        Blank()
        // 右上角显示当前工作模式（观测总数在下方统计行里，不重复占位）。
        Text(this.workingModeText()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      Text(this.statsLine()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      // 条件必须同时包含星闪：BLE 已授权但星闪未授权时，
      // 用户也需要在实时页看到星闪的引导入口。
      if (this.bleMissing || this.nearLinkMissing) this.buildRestrictedCard()
      // §12.1：扫描出错时明确告诉用户，而不是让雷达静静地不动。
      if (this.scanErrorText.length > 0) {
        // **必须走 `resolveResourceString`，不能拿 `$r()` 直接拼字符串。**
        // `$r()` 返回的是 `Resource` 对象，`+` 会调用它的 `toString()` ——
        // 结果就是用户看到的 `[object Object]扫描异常：…`。
        Text(this.radioLabel('app.string.fieldwatch_scan_error_prefix') + this.scanErrorText)
          .fontSize(12).fontColor($r('app.color.fw_on_warning')).width('100%')
          .padding(8).backgroundColor(FieldwatchPaletteHolder.get().amber).borderRadius(10)
      }
      Row({ space: 8 }) {
        this.buildViewChip($r('app.string.fieldwatch_view_radar'), FieldwatchLiveMode.RADAR)
        this.buildViewChip($r('app.string.fieldwatch_view_strength'), FieldwatchLiveMode.STRENGTH)
        this.buildViewChip($r('app.string.fieldwatch_view_timeline'), FieldwatchLiveMode.TIMELINE)
        this.buildViewChip($r('app.string.fieldwatch_view_trail'), FieldwatchLiveMode.TRAIL)
        this.buildViewChip($r('app.string.fieldwatch_view_class'), FieldwatchLiveMode.CLASS)
      }.width('100%')
    }.width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 8, bottom: 12 })
    .backgroundColor(FieldwatchPaletteHolder.get().night)
    /**
     * 把浮层实测高度回传给内容容器。
     *
     * 加 0.5 的容差再比：`onAreaChange` 会在亚像素级别反复触发，
     * 直接赋值会让 @State 每帧都变，内容区跟着反复重排。
     */
    .onAreaChange((_old: Area, now: Area): void => {
      const h: number = now.height as number;
      if (Math.abs(h - this.liveHeaderH) > 0.5) this.liveHeaderH = h;
    })
  }
}

@Component
struct FieldwatchFiltersPage {
  /** 状态栏高度（vp）：内容避让，但页面底板仍延伸到状态栏区域。 */
  @Prop topInset: number = 0;
  /**
   * 横屏且右栏未开时用两列。
   *
   * 竖屏与「右栏已开」都保持单列：前者宽度不够，后者可用宽度只剩三分之一。
   * 默认 false，所以竖屏标签栏那条路径无需改动。
   */
  @Prop twoColumn: boolean = false;
  @State private presetName: string = '';
  @State private tick: number = 0;
  /**
   * 精细筛选的 RSSI 下限。
   *
   * 必须是 `@State`：筛选状态存在 `fieldwatchApplication` 的普通对象里，
   * ArkUI 无法据此重建 UI，于是拖动滑块时数值标签永远停在初始值、
   * 松手后滑块还会被非响应式的旧值拉回去。
   */
  @State private rssiMinValue: number = -100;
  /** 名称 / OUI 输入框的受控值；重置筛选时才会跟着清空。 */
  @State private nameQueryValue: string = '';
  @State private ouiQueryValue: string = '';
  private presets: FilterPreset[] = [];

  /**
   * 把筛选状态绑定到 UI 的**唯一入口**（芯片选中态、开关状态都用它）。
   *
   * 筛选状态存在 `fieldwatchApplication` 的普通对象里，不是 `@State`，
   * ArkUI 因此不会在它变化时重建本页 —— 芯片外观就会停在首次渲染的样子。
   *
   * 这里**读一次 `this.tick`**（每次筛选变更都会自增）来建立响应式依赖：
   * 依赖是「构建期实际读取了哪个 @State」建立的，所以必须让这次读取真的发生在
   * 传给子组件的表达式里，写而不读是无效的。
   *
   * 不要改成 `.id(...)` 之类的写法 —— 属性方法里的读取不参与依赖收集（已实测无效）。
   */
  private filterBound(value: boolean): boolean {
    return this.tick >= 0 && value;
  }
  /** 三种无线电种类全开（「全部」芯片的选中态）。 */
  private radioFilterAll(): boolean {
    const filter: FilterDefinition = fieldwatchApplication.getState().filter;
    return filter.showWifi && filter.showBle && filter.showNearLink;
  }
  /** 当前是否只显示某一种无线电种类。 */
  private radioFilterIs(kind: RadioKind): boolean {
    const filter: FilterDefinition = fieldwatchApplication.getState().filter;
    if (kind === RadioKind.WIFI) return filter.showWifi && !filter.showBle && !filter.showNearLink;
    if (kind === RadioKind.BLE) return !filter.showWifi && filter.showBle && !filter.showNearLink;
    return !filter.showWifi && !filter.showBle && filter.showNearLink;
  }

  aboutToAppear(): void { this.refresh(); }
  private refresh(): void {
    this.presets = fieldwatchApplication.listFilterPresets();
    // 预设可能改变了 RSSI 下限，滑块状态要跟着走。
    this.rssiMinValue = fieldwatchApplication.getState().filter.rssiMin;
    this.nameQueryValue = fieldwatchApplication.getState().filter.nameQuery;
    this.ouiQueryValue = fieldwatchApplication.getState().filter.ouiQuery;
    this.tick += 1;
  }
  /** 当前筛选（筛选页各分区共用）。 */
  private filter(): FilterDefinition { return fieldwatchApplication.getState().filter; }
  private label(key: string): string { return resolveResourceString(this.getUIContext().getHostContext(), $r(key)); }
  private presetLabel(preset: FilterPreset): string {
    if (preset.name === 'all') return this.label('app.string.fieldwatch_preset_all');
    if (preset.name === 'wifi') return this.label('app.string.fieldwatch_filter_wifi_only');
    if (preset.name === 'ble') return this.label('app.string.fieldwatch_filter_ble_only');
    if (preset.name === 'nearlink') return this.label('app.string.fieldwatch_filter_nearlink_only');
    if (preset.name === 'strong') return this.label('app.string.fieldwatch_preset_strong');
    if (preset.name === 'with-you') return this.label('app.string.fieldwatch_filter_moving_with_you');
    if (preset.name === 'watched') return this.label('app.string.fieldwatch_filter_watched_only');
    return preset.name;
  }

  /** 卡片容器：原版 SectionCard 的等价物。 */
  @Builder private section(title: ResourceStr, hint: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
      if (hint.length > 0) Text(hint).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  // switchRow 已改为 FieldwatchSwitchRow 组件（与 chip 同一个原因）。
  // chip 已改为 FieldwatchChip 组件：@Builder 按值参数不响应式，是「点击没反应」的根因。

  // presetChip 已改为 FieldwatchPresetChip 组件；旧实现字色写死 textDim，选中态看不出来。
  private confirmDeletePreset(preset: FilterPreset): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_filter_delete_preset_title'),
      message: this.presetLabel(preset),
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_filter_delete'), action: (): void => {
        fieldwatchApplication.deleteFilterPresetNamed(preset.name);
        this.refresh();
      } }
    });
  }
  // ── 1 预设 ──
  @Builder private buildPresets() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_presets'), this.label('app.string.fieldwatch_filter_presets_hint'))
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.presets, (preset: FilterPreset): void => {
          FieldwatchPresetChip({ label: this.presetLabel(preset), active: this.presetName === preset.name,
          onTap: (): void => { fieldwatchApplication.applyFilterPresetByName(preset.name); this.presetName = preset.name; this.tick += 1; },
          onLongPress: (): void => { this.confirmDeletePreset(preset); } })
        }, (preset: FilterPreset): string => preset.name + '-' + this.tick.toString())
      }.width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.presetName, placeholder: $r('app.string.fieldwatch_filter_save_as') }).layoutWeight(1).height(42)
          .onChange((value: string): void => { this.presetName = value; })
        Button($r('app.string.fieldwatch_filter_save')).height(44).fontSize(15).backgroundColor(Color.Transparent).borderRadius(12).borderWidth(1)
          .fontColor(FieldwatchPaletteHolder.get().accent).borderColor(FieldwatchPaletteHolder.get().accent)
          .onClick((): void => {
            const name: string = this.presetName.trim();
            if (name.length === 0) return;
            fieldwatchApplication.saveFilterPresetNamed(name);
            this.presetName = '';
            this.refresh();
          })
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 2 信号类型 ──
  @Builder private buildRadios() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_radios'), this.label('app.string.fieldwatch_filter_radios_hint'))
      // 三种无线电种类各自单选，全部走 setRadioKind 收敛开关 ——
      // 只改 UI 不改引擎会造成「界面有选项但筛选不生效」。
      Row({ space: 8 }) {
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_both'), active: this.filterBound(this.radioFilterAll()),
          onTap: (): void => { fieldwatchApplication.setRadioKind(undefined); this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_wifi_only'), active: this.filterBound(this.radioFilterIs(RadioKind.WIFI)),
          onTap: (): void => { fieldwatchApplication.setRadioKind(RadioKind.WIFI); this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_ble_only'), active: this.filterBound(this.radioFilterIs(RadioKind.BLE)),
          onTap: (): void => { fieldwatchApplication.setRadioKind(RadioKind.BLE); this.tick += 1; } })
        // 星闪芯片只在设备支持星闪时出现：不支持的设备上不该有永远为空的筛选项。
        if (fieldwatchApplication.nearLinkAvailable()) {
          FieldwatchChip({ label: $r('app.string.fieldwatch_filter_nearlink_only'), active: this.filterBound(this.radioFilterIs(RadioKind.NEARLINK)),
            onTap: (): void => { fieldwatchApplication.setRadioKind(RadioKind.NEARLINK); this.tick += 1; } })
        }
        // 关键：必须在这里**读一次** tick 才能建立响应式依赖。
        // 只写不读的 @State 不会让 ArkUI 重建组件 —— 这正是「点了没反应」的最后一块。
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 3 与你同行 ──
  @Builder private buildMovingWithYou() {
    Column({ space: 10 }) {
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_moving_with_you'), hint: '',
        value: this.filterBound(this.filter().movingWithYou),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setMovingWithYouFilter(checked); this.tick += 1; } })
      Text(this.label('app.string.fieldwatch_filter_moving_hint')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text(fieldwatchApplication.travelStatusText()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().warn)
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 4 新发现 ──
  @Builder private buildNewDetections() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_new_detections'), '')
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_new_only'), hint: this.label('app.string.fieldwatch_filter_new_hint'),
        value: this.filterBound(this.filter().freshOnly),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setFreshOnlyFilter(checked); this.tick += 1; } })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 5 常驻设备 ──
  @Builder private buildWhoStays() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_who_stays'), '')
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_signatures_only'), hint: this.label('app.string.fieldwatch_filter_signatures_only_hint'),
        value: this.filterBound(this.filter().namedOnly),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setNamedOnlyFilter(checked); this.tick += 1; } })
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_watched_only'), hint: this.label('app.string.fieldwatch_filter_watched_hint'),
        value: this.filterBound(this.filter().watchedOnly),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setWatchedOnlyFilter(checked); this.tick += 1; } })
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_named_radios_only'), hint: this.label('app.string.fieldwatch_filter_named_hint'),
        value: this.filterBound(this.filter().customNamesOnly),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setCustomNamesOnlyFilter(checked); this.tick += 1; } })
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_hide_fastpair'), hint: this.label('app.string.fieldwatch_filter_fastpair_hint'),
        value: this.filterBound(this.filter().hideFastPairAccountKey),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setHideFastPairFilter(checked); this.tick += 1; } })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 6 特征分类 ──
  /**
   * 某个特征分类是否被选中。
   *
   * **必须在方法内部读一次 `this.tick`**：筛选状态存在 `fieldwatchApplication` 的
   * 普通对象里，不是 `@State`，ArkUI 无法建立依赖；只写 `tick` 不读等于没写，
   * 芯片颜色就会停在首次渲染的样子（用户反馈「点了没有选中态」）。
   */
  private classSelected(cls: SignatureClass): boolean {
    return this.tick >= 0 && this.filter().classes.indexOf(cls) >= 0;
  }
  @Builder private buildClassChip(cls: SignatureClass) {
    Row({ space: 6 }) {
      FieldwatchDeviceTypeIcon({ kind: RadioKind.BLE, category: cls, tint: FieldwatchPaletteHolder.get().accent, glyphSize: 16 })
      Text(signatureClassLabel(cls)).fontSize(14)
        .fontColor(this.classSelected(cls) ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().text)
      if (this.classSelected(cls)) {
        SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14).fontColor([FieldwatchPaletteHolder.get().accent])
      }
    }.width('48%').padding(10).borderRadius(10).borderWidth(this.classSelected(cls) ? 2 : 1)
      .borderColor(this.classSelected(cls) ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
      .backgroundColor(this.classSelected(cls) ? FieldwatchPaletteHolder.get().badgeBg : Color.Transparent)
      .onClick((): void => { fieldwatchApplication.toggleFilterClass(cls); this.tick += 1; })
  }
  @Builder private buildClasses() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_classes'), this.label('app.string.fieldwatch_filter_classes_hint'))
      Row({ space: 8 }) {
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_class_show_only'),
          active: this.filterBound(this.filter().useClassFilter && !this.filter().excludeClasses),
          onTap: (): void => { fieldwatchApplication.setClassFilterMode(false); this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_class_hide_these'),
          active: this.filterBound(this.filter().useClassFilter && this.filter().excludeClasses),
          onTap: (): void => { fieldwatchApplication.setClassFilterMode(true); this.tick += 1; } })
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(visibleSignatureClasses(), (cls: SignatureClass): void => { this.buildClassChip(cls) }, (cls: SignatureClass): string => cls)
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 7 已选特征 ──
  @Builder private buildSelectedSignatures() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_selected_signatures'), this.label('app.string.fieldwatch_filter_selected_hint'))
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_show_selected'), hint: '',
        value: this.filterBound(this.filter().includeSignatures),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setIncludeSignaturesFilter(checked); this.tick += 1; } })
      FieldwatchSwitchRow({ label: $r('app.string.fieldwatch_filter_hide_selected'), hint: '',
        value: this.filterBound(this.filter().excludeSignatures),
        onToggle: (checked: boolean): void => { fieldwatchApplication.setExcludeSignaturesFilter(checked); this.tick += 1; } })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── 8 精细筛选 ──
  @Builder private buildFineFilter() {
    Column({ space: 10 }) {
      this.section($r('app.string.fieldwatch_filter_fine'), '')
      Text(this.label('app.string.fieldwatch_filter_rssi_min') + ' ' + this.rssiMinValue.toString() + ' dBm')
        .fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
      Slider({ value: this.rssiMinValue, min: -100, max: -30, step: 1 })
        .selectedColor(FieldwatchPaletteHolder.get().accentActive).trackColor(FieldwatchPaletteHolder.get().rssiTrack).width('100%')
        .onChange((value: number): void => {
          this.rssiMinValue = Math.round(value);
          fieldwatchApplication.setRssiMinFilter(this.rssiMinValue);
        })
      TextInput({ text: this.nameQueryValue, placeholder: $r('app.string.fieldwatch_filter_name_contains') }).height(42)
        .onChange((value: string): void => {
          this.nameQueryValue = value;
          fieldwatchApplication.setNameQueryFilter(value);
        })
      TextInput({ text: this.ouiQueryValue, placeholder: $r('app.string.fieldwatch_filter_oui_contains') }).height(42)
        .onChange((value: string): void => {
          this.ouiQueryValue = value;
          fieldwatchApplication.setOuiQueryFilter(value);
        })
      Text(this.label('app.string.fieldwatch_filter_extra_logic')).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
      Text(this.label('app.string.fieldwatch_filter_logic_hint')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      Row({ space: 8 }) {
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_and'), active: this.filterBound(this.filter().logic === FilterLogic.AND),
          onTap: (): void => { fieldwatchApplication.setFilterLogic(FilterLogic.AND); this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_or'), active: this.filterBound(this.filter().logic === FilterLogic.OR),
          onTap: (): void => { fieldwatchApplication.setFilterLogic(FilterLogic.OR); this.tick += 1; } })
      }.width('100%')
      Button($r('app.string.fieldwatch_filter_reset')).height(44).width('100%').fontSize(15)
        .backgroundColor(Color.Transparent).borderRadius(12).borderWidth(1)
        .fontColor(FieldwatchPaletteHolder.get().warn).borderColor(FieldwatchPaletteHolder.get().outline)
        .onClick((): void => { this.confirmReset(); })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  private confirmReset(): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_filter_reset_title'),
      message: this.label('app.string.fieldwatch_filter_reset_body'),
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_filter_reset'), action: (): void => { fieldwatchApplication.resetFilter(); this.tick += 1; } }
    });
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
    // **页面标题**：与设置页同一套（26 号加粗、同一段顶部内边距）。
    //
    // 横屏下没有底部标签栏做「我在哪一页」的提示，标题就是唯一的定位锚点；
    // 筛选与记录原先都没有（实测反馈）。
    Text($r('app.string.fieldwatch_filters_title')).fontSize(26).fontWeight(FontWeight.Bold)
    if (this.twoColumn) {
      // **手写两列**：每列各自纵向堆叠，互不参照对方高度。
      //
      // 试过两种容器，都不行：
      //   - `Grid`：按行对齐，每行高度取该行最高的那个 -> 矮卡旁边必然留空；
      //   - `WaterFlow`：要测量每个 item 的高度，嵌在 `Scroll` 里约束无限，
      //     测错行高 -> **卡片互相重叠**（实测）。
      // 两个 `Column` 没有行对齐、也不需要测量，天然正确。
      Row({ space: 12 }) {
        Column({ space: 12 }) {
          this.buildPresets()
          this.buildMovingWithYou()
          this.buildWhoStays()
          this.buildSelectedSignatures()
        }.layoutWeight(1)
        Column({ space: 12 }) {
          this.buildRadios()
          this.buildNewDetections()
          this.buildClasses()
          this.buildFineFilter()
        }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
        this.buildPresets()
        this.buildRadios()
        this.buildMovingWithYou()
        this.buildNewDetections()
        this.buildWhoStays()
        this.buildClasses()
        this.buildSelectedSignatures()
        this.buildFineFilter()
    }
      }.width('100%').padding({ left: 12, right: 12, top: this.topInset + 8, bottom: 48 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
}
/** 与原版 LogExportKind 一致的 5 种格式（顺序即索引）。 */
const EXPORT_FORMATS: string[] = [
  'app.string.fieldwatch_report_export_csv',
  'app.string.fieldwatch_report_export_jsonl',
  'app.string.fieldwatch_report_export_gpx',
  'app.string.fieldwatch_report_export_kml',
  'app.string.fieldwatch_report_export_wigle',
];
@Component
struct FieldwatchReportsPage {
  /** 与原版 LogExportKind 一致的 5 种格式。 */
  @Prop topInset: number = 0;
  /**
   * 横屏且右栏未开时用两列。
   *
   * 竖屏与「右栏已开」都保持单列：前者宽度不够，后者可用宽度只剩三分之一。
   * 默认 false，所以竖屏标签栏那条路径无需改动。
   */
  @Prop twoColumn: boolean = false;
  @State private activeName: string = '';
  @State private savedSits: SitSummary[] = [];
  @State private observationCount: number = 0;
  @State private locatedCount: number = 0;
  @State private showUnmatchedBle: boolean = false;
  @State private logRows: number = 0;
  /** 导出格式 0=CSV 1=JSONL 2=GPX 3=KML 4=WiGLE。 */
  @State private exportFormat: number = 0;
  /** 导出信号源 0=两者 1=仅 Wi-Fi 2=仅 BLE。 */
  @State private exportRadios: number = 0;
  /** R6 候选特征。 */
  @State private candidates: SignatureCandidate[] = [];
  @State private candidateStats: string = '';
  @State private logKb: number = 0;
  @State private tick: number = 0;

  aboutToAppear(): void { this.refresh(); }
  private label(key: string): string { return resolveResourceString(this.getUIContext().getHostContext(), $r(key)); }
  private refresh(): void {
    const state = fieldwatchApplication.getState();
    this.activeName = state.activeSit === undefined ? '' : state.activeSit.name;
    this.savedSits = state.savedSits.slice();
    this.observationCount = state.sightings.length;
    this.locatedCount = state.sightings.filter((item: Sighting): boolean => item.location !== undefined).length;
    if (this.pathContext.width > 0) this.drawPath();
    void fieldwatchApplication.loadSavedSits().then((sits: SitSummary[]): void => { this.savedSits = sits; this.tick += 1; });
    const report: CandidateReport = fieldwatchApplication.candidateReport();
    this.candidates = report.families;
    this.candidateStats = report.uniqueRadios.toString() + ' 台信号源 · 未匹配 ' + report.unmatchedRadios.toString()
      + ' · 跳过随机 ' + report.skippedRandomized.toString() + ' · 跳过家用 ' + report.skippedHouseLike.toString();
    void fieldwatchApplication.logFootprint().then((footprint: FieldwatchLogFootprint): void => {
      this.logRows = footprint.rows;
      this.logKb = footprint.kilobytes();
      this.tick += 1;
    });
  }

  @Builder private card(title: ResourceStr, hint: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
      if (hint.length > 0) Text(hint).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  /** 行内并排按钮：用 layoutWeight 平分宽度，避免两个 100% 宽互相挤出屏幕。 */
  @Builder private rowButton(label: ResourceStr, tint: string, onTap: () => void) {
    Button(label).height(44).layoutWeight(1).fontSize(15).backgroundColor(Color.Transparent).borderRadius(12).borderWidth(1)
      .fontColor(tint).borderColor(FieldwatchPaletteHolder.get().outline).onClick(onTap)
  }
  /** 芯片：与筛选页同款描边胶囊。 */
  // chip 已改为 FieldwatchChip 组件：@Builder 按值参数不响应式，是「点击没反应」的根因。
  @Builder private actionButton(label: ResourceStr, tint: string, onTap: () => void) {
    Button(label).height(44).width('100%').fontSize(15).backgroundColor(Color.Transparent).borderRadius(12).borderWidth(1)
      .fontColor(tint).borderColor(FieldwatchPaletteHolder.get().outline).onClick(onTap)
  }

  // ── R1 观测记录 ──
  @Builder private buildSits() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_sits'), this.label('app.string.fieldwatch_reports_sits_hint'))
      Text(this.activeName.length > 0
        ? this.label('app.string.fieldwatch_reports_sit_running').replace('%s', this.activeName)
        : this.label('app.string.fieldwatch_reports_no_sit_running'))
        .fontSize(13).fontColor(this.activeName.length > 0 ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      if (this.activeName.length === 0) {
        this.actionButton($r('app.string.fieldwatch_reports_start_sit'), FieldwatchPaletteHolder.get().accent, (): void => { this.promptStartSit(); })
      } else {
        this.actionButton($r('app.string.fieldwatch_reports_finish_sit'), FieldwatchPaletteHolder.get().warn, (): void => {
          void fieldwatchApplication.finishSit().then((ok: boolean): void => { if (ok) this.refresh(); });
        })
      }
      if (this.savedSits.length === 0) Text($r('app.string.fieldwatch_reports_no_sits')).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.savedSits, (item: SitSummary): void => { this.buildSitRow(item) }, (item: SitSummary): string => item.id)
      if (this.savedSits.length > 0) {
        this.actionButton($r('app.string.fieldwatch_reports_delete_all_sits'), FieldwatchPaletteHolder.get().signalRed, (): void => { this.confirmDeleteAllSits(); })
      }
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }
  @Builder private buildSitRow(item: SitSummary) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.name).fontSize(15).layoutWeight(1).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
        Text(item.radioCount.toString()).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      Row({ space: 8 }) {
        this.rowButton($r('app.string.fieldwatch_reports_rename'), FieldwatchPaletteHolder.get().text, (): void => { this.promptRenameSit(item); })
        this.rowButton($r('app.string.fieldwatch_filter_delete'), FieldwatchPaletteHolder.get().signalRed, (): void => { this.confirmDeleteSit(item); })
      }.width('100%')
    }.width('100%').padding(10).backgroundColor(FieldwatchPaletteHolder.get().panel2).borderRadius(12)
  }
  private promptStartSit(): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_start_sit'),
      message: this.label('app.string.fieldwatch_reports_start_hint'),
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_reports_start'), action: (): void => {
        const name: string = this.label('app.string.fieldwatch_reports_sit_default_name') + ' ' + this.sitStamp();
        void fieldwatchApplication.startSit(name).then((ok: boolean): void => { if (ok) this.refresh(); });
      } }
    });
  }
  private sitStamp(): string {
    const date: Date = new Date();
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }
  private promptRenameSit(item: SitSummary): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_rename_sit'),
      message: item.name,
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_filter_save'), action: (): void => {
        void fieldwatchApplication.renameSit(item.id, item.name + '*').then((ok: boolean): void => { if (ok) this.refresh(); });
      } }
    });
  }
  private confirmDeleteSit(item: SitSummary): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_delete_sit_title'),
      message: item.name,
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_filter_delete'), action: (): void => {
        void fieldwatchApplication.deleteSit(item.id).then((ok: boolean): void => { if (ok) this.refresh(); });
      } }
    });
  }
  private confirmDeleteAllSits(): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_delete_all_sits'),
      message: this.label('app.string.fieldwatch_reports_delete_all_hint'),
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_filter_delete'), action: (): void => {
        void fieldwatchApplication.deleteAllSits().then((ok: boolean): void => { if (ok) this.refresh(); });
      } }
    });
  }

  // ── R2 轨迹 ──
  @Builder private buildPath() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_path'), this.label('app.string.fieldwatch_reports_path_hint'))
      Canvas(this.pathContext).width('100%').height(260)
        .backgroundColor(FieldwatchPaletteHolder.get().panel2).borderRadius(12)
        .onReady((): void => { this.drawPath(); })
      Text(this.pathStatusText()).fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }
  private locatedSightings(): Sighting[] {
    return fieldwatchApplication.getState().sightings.filter((item: Sighting): boolean => item.location !== undefined);
  }
  private pathStatusText(): string {
    const template: string = this.label('app.string.fieldwatch_reports_path_status');
    const meters: number = Math.round(fieldwatchApplication.travelPathMeters());
    return template.replace('%s', meters.toString()).replace('%d', this.locatedSightings().length.toString());
  }
  /** 北向上绘制：本机轨迹折线 + 起点/当前位置 + 带定位的信号源点。 */
  private drawPath(): void {
    const width: number = this.pathContext.width;
    const height: number = this.pathContext.height;
    const palette = FieldwatchPaletteHolder.get();
    this.pathContext.clearRect(0, 0, width, height);
    this.pathContext.fillStyle = palette.panel2;
    this.pathContext.fillRect(0, 0, width, height);
    const track: GpsSample[] = fieldwatchApplication.travelTrack();
    const located: Sighting[] = this.locatedSightings();
    if (track.length === 0 && located.length === 0) {
      this.pathContext.fillStyle = palette.textDim;
      // 画布字号是 px 字面量，必须在同一设备上与雷达画布的 18px 同尺度；
      // 原来的 14px 在高密度屏上只有约 4pt，用户反馈「特别小」。
      this.pathContext.font = '20px sans-serif';
      this.pathContext.fillText(this.label('app.string.fieldwatch_reports_path_empty'), 16, height / 2);
      return;
    }
    let minLat: number = 90; let maxLat: number = -90; let minLon: number = 180; let maxLon: number = -180;
    track.forEach((sample: GpsSample): void => {
      if (sample.latitude < minLat) minLat = sample.latitude;
      if (sample.latitude > maxLat) maxLat = sample.latitude;
      if (sample.longitude < minLon) minLon = sample.longitude;
      if (sample.longitude > maxLon) maxLon = sample.longitude;
    });
    located.forEach((item: Sighting): void => {
      const point: GpsSample = item.location as GpsSample;
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    });
    const spanLat: number = Math.max(maxLat - minLat, 0.0002);
    const spanLon: number = Math.max(maxLon - minLon, 0.0002);
    const pad: number = 24;
    const scaleX: number = (width - pad * 2) / spanLon;
    const scaleY: number = (height - pad * 2) / spanLat;
    const scale: number = Math.min(scaleX, scaleY);
    const offsetX: number = (width - spanLon * scale) / 2;
    const offsetY: number = (height - spanLat * scale) / 2;
    const px = (lon: number): number => offsetX + (lon - minLon) * scale;
    const py = (lat: number): number => height - offsetY - (lat - minLat) * scale;
    if (track.length > 1) {
      this.pathContext.strokeStyle = palette.accent;
      this.pathContext.lineWidth = 3;
      this.pathContext.lineJoin = 'round';
      this.pathContext.beginPath();
      this.pathContext.moveTo(px(track[0].longitude), py(track[0].latitude));
      for (let index: number = 1; index < track.length; index += 1) {
        this.pathContext.lineTo(px(track[index].longitude), py(track[index].latitude));
      }
      this.pathContext.stroke();
      this.pathContext.fillStyle = palette.text;
      this.pathContext.beginPath();
      this.pathContext.arc(px(track[0].longitude), py(track[0].latitude), 5, 0, Math.PI * 2);
      this.pathContext.fill();
      const last: GpsSample = track[track.length - 1];
      this.pathContext.fillStyle = palette.cyan;
      this.pathContext.beginPath();
      this.pathContext.arc(px(last.longitude), py(last.latitude), 7, 0, Math.PI * 2);
      this.pathContext.fill();
    }
    located.forEach((item: Sighting): void => {
      const point: GpsSample = item.location as GpsSample;
      const names: string[] = matchedSignatureNames(item.signatureIds, fieldwatchApplication.getState().signatures);
      this.pathContext.fillStyle = names.length > 0 ? palette.accent : palette.amber;
      this.pathContext.beginPath();
      this.pathContext.arc(px(point.longitude), py(point.latitude), 4, 0, Math.PI * 2);
      this.pathContext.fill();
    });
  }
  private readonly pathContext: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  // ── R2/R3 观测报告 ──
  @Builder private buildSitReport() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_sit_report'), this.label('app.string.fieldwatch_reports_sit_report_hint'))
      this.actionButton($r('app.string.fieldwatch_report_debrief'), FieldwatchPaletteHolder.get().text, (): void => { fieldwatchApplication.shareDebrief(); })
      Row() {
        Text($r('app.string.fieldwatch_reports_show_unmatched')).fontSize(15).layoutWeight(1).fontColor(FieldwatchPaletteHolder.get().text)
        Toggle({ type: ToggleType.Switch, isOn: this.showUnmatchedBle }).selectedColor(FieldwatchPaletteHolder.get().accentActive)
          .onChange((value: boolean): void => { this.showUnmatchedBle = value; })
      }.width('100%')
      Text($r('app.string.fieldwatch_reports_show_unmatched_hint')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      this.actionButton($r('app.string.fieldwatch_reports_debrief_pdf'), FieldwatchPaletteHolder.get().text, (): void => { void this.runDebriefPdf(); })
      this.actionButton($r('app.string.fieldwatch_reports_ai_export'), FieldwatchPaletteHolder.get().accent, (): void => { fieldwatchApplication.aiExportDebrief(); })
      Text(this.label('app.string.fieldwatch_reports_located') + ': ' + this.locatedCount.toString()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── R4 观测导出：格式 × 信号源 + 分享 + 保存到文件 ──
  @Builder private buildExport() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_export'), this.label('app.string.fieldwatch_reports_export_hint'))
      Text($r('app.string.fieldwatch_reports_format')).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(EXPORT_FORMATS, (item: string, index: number): void => {
          FieldwatchChip({ label: $r(item), active: this.exportFormat === index, compact: true,
            onTap: (): void => { this.exportFormat = index; this.tick += 1; } })
        }, (item: string): string => item)
      }.width('100%')
      Text($r('app.string.fieldwatch_reports_radios')).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
      Row({ space: 8 }) {
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_both'), active: this.exportRadios === 0,
          onTap: (): void => { this.exportRadios = 0; this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_wifi_only'), active: this.exportRadios === 1,
          onTap: (): void => { this.exportRadios = 1; this.tick += 1; } })
        FieldwatchChip({ label: $r('app.string.fieldwatch_filter_ble_only'), active: this.exportRadios === 2,
          onTap: (): void => { this.exportRadios = 2; this.tick += 1; } })
        // 星闪导出只在设备支持时出现，与筛选页保持一致。
        if (fieldwatchApplication.nearLinkAvailable()) {
          FieldwatchChip({ label: $r('app.string.fieldwatch_export_radios_nearlink'), active: this.exportRadios === 3,
            onTap: (): void => { this.exportRadios = 3; this.tick += 1; } })
        }
      }.width('100%')
      this.actionButton($r('app.string.fieldwatch_reports_share'), FieldwatchPaletteHolder.get().text, (): void => {
        fieldwatchApplication.shareExport(this.exportFormat, this.exportRadios);
      })
      this.actionButton($r('app.string.fieldwatch_reports_save_file'), FieldwatchPaletteHolder.get().accent, (): void => { void this.runSaveExport(); })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }
  private async runSaveExport(): Promise<void> {
    const saved: boolean = await fieldwatchApplication.saveExportAs(this.exportFormat, this.exportRadios);
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_save_file'),
      message: saved ? this.label('app.string.fieldwatch_reports_save_ok') : this.label('app.string.fieldwatch_reports_save_cancel'),
      confirm: { value: this.label('app.string.fieldwatch_common_confirm'), action: (): void => {} }
    });
  }

  // ── R5 对比观测 ──
  @Builder private buildCompare() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_compare'), this.label('app.string.fieldwatch_reports_compare_hint'))
      this.actionButton($r('app.string.fieldwatch_report_compare'), FieldwatchPaletteHolder.get().text, (): void => { fieldwatchApplication.shareCompare(); })
      this.actionButton($r('app.string.fieldwatch_reports_compare_pdf'), FieldwatchPaletteHolder.get().text, (): void => { void this.runComparePdf(); })
      this.actionButton($r('app.string.fieldwatch_reports_ai_export'), FieldwatchPaletteHolder.get().accent, (): void => { fieldwatchApplication.aiExportCompare(); })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // ── R6 目录 / 候选特征 ──
  @Builder private buildCatalog() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_catalog'), this.label('app.string.fieldwatch_reports_catalog_hint'))
      Text(this.candidateStats).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      if (this.candidates.length === 0) {
        Text($r('app.string.fieldwatch_reports_no_candidates')).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.candidates, (item: SignatureCandidate): void => { this.buildCandidateRow(item) }, (item: SignatureCandidate): string => item.id)
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }
  @Builder private buildCandidateRow(item: SignatureCandidate) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(item.proposedName).fontSize(15).layoutWeight(1).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
        Text(item.distinctRadios.toString() + ' 台')
          .fontSize(13).fontColor(item.strong() ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      Text(item.why).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      if (item.examples.length > 0) {
        Text(item.examples.join(' · ')).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
      }
      this.actionButton($r('app.string.fieldwatch_reports_add_candidate'), FieldwatchPaletteHolder.get().accent, (): void => {
        fieldwatchApplication.addCandidateToCatalog(item);
        this.refresh();
      })
    }.width('100%').padding(10).backgroundColor(FieldwatchPaletteHolder.get().panel2).borderRadius(12)
  }

  // ── R7 记录导出 ──
  @Builder private buildLog() {
    Column({ space: 10 }) {
      this.card($r('app.string.fieldwatch_reports_log_export'), this.label('app.string.fieldwatch_reports_log_hint'))
      Text(this.label('app.string.fieldwatch_reports_session_rows') + ': ' + this.logRows.toString() + '  ·  ' + this.logKb.toString() + ' KB')
        .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      this.actionButton($r('app.string.fieldwatch_reports_clear_logs'), FieldwatchPaletteHolder.get().signalRed, (): void => { this.confirmClearLog(); })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }
  /** 生成对比观测 PDF 并报告结果。 */
  private async runComparePdf(): Promise<void> {
    const path: string = await fieldwatchApplication.exportComparePdf();
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_compare_pdf'),
      message: path.length > 0
        ? this.label('app.string.fieldwatch_reports_pdf_ok').replace('%s', path)
        : this.label('app.string.fieldwatch_reports_pdf_failed'),
      confirm: { value: this.label('app.string.fieldwatch_common_confirm'), action: (): void => {} }
    });
  }
  /** 生成复盘 PDF 并报告结果（沙箱路径 + 是否可分享）。 */
  private async runDebriefPdf(): Promise<void> {
    const path: string = await fieldwatchApplication.exportDebriefPdf();
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_debrief_pdf'),
      message: path.length > 0
        ? this.label('app.string.fieldwatch_reports_pdf_ok').replace('%s', path)
        : this.label('app.string.fieldwatch_reports_pdf_failed'),
      confirm: { value: this.label('app.string.fieldwatch_common_confirm'), action: (): void => {} }
    });
  }
  private confirmClearLog(): void {
    this.getUIContext().showAlertDialog({
      title: this.label('app.string.fieldwatch_reports_clear_title'),
      message: this.label('app.string.fieldwatch_reports_clear_hint'),
      primaryButton: { value: this.label('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.label('app.string.fieldwatch_reports_clear_logs'), action: (): void => {
        fieldwatchApplication.clearLogs();
        this.refresh();
      } }
    });
  }

  build() { Scroll() { Column({ space: 12 }) {
      // **页面标题**：与设置页同一套（26 号加粗、同一段顶部内边距）。
      //
      // 横屏下没有底部标签栏做「我在哪一页」的提示，标题就是唯一的定位锚点；
      // 筛选与记录原先都没有（实测反馈）。
      Text($r('app.string.fieldwatch_reports_title')).fontSize(26).fontWeight(FontWeight.Bold)
    if (this.twoColumn) {
      // **手写两列**：每列各自纵向堆叠，互不参照对方高度。
      //
      // 试过两种容器，都不行：
      //   - `Grid`：按行对齐，每行高度取该行最高的那个 -> 矮卡旁边必然留空；
      //   - `WaterFlow`：要测量每个 item 的高度，嵌在 `Scroll` 里约束无限，
      //     测错行高 -> **卡片互相重叠**（实测）。
      // 两个 `Column` 没有行对齐、也不需要测量，天然正确。
      Row({ space: 12 }) {
        Column({ space: 12 }) {
          this.buildSits()
          this.buildSitReport()
          this.buildCompare()
          this.buildLog()
        }.layoutWeight(1)
        Column({ space: 12 }) {
          this.buildPath()
          this.buildExport()
          this.buildCatalog()
        }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      this.buildSits()
      this.buildPath()
      this.buildSitReport()
      this.buildExport()
      this.buildCompare()
      this.buildCatalog()
      this.buildLog()
    }
  }.width('100%').padding({ left: 12, right: 12, top: this.topInset + 8, bottom: 48 }) }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring) }
}

@Component
struct FieldwatchSettingsPage {
  @Prop topInset: number = 0;
  /**
   * 横屏且右栏未开时用两列。竖屏与「右栏已开」保持单列。
   */
  @Prop twoColumn: boolean = false;
  /** 手动重渲染计数器：筛选/设置直接改应用状态，不经过 @State，需要它来触发刷新。 */
  @State private tick: number = 0;
  onOpenSignatures: () => void = (): void => {};
  /** 打开反馈中心。**必须有默认空实现**：ArkTS 要求成员初始化，
   *  而漏传的表现是「点了没反应」（这个坑在本仓库出现过多次）。 */
  onOpenFeedback: () => void = (): void => {};
  /** 「关于」面板开关。 */
  /**
   * 设置页 sheet 的**唯一开关**。
   *
   * 用 `$$` 双向绑定：开关由 ArkUI 自己维护，下滑关闭会自动写回 false，
   * 不需要 `onDisappear` 手动清状态。
   *
   * **不要再改回「计算表达式 + onDisappear 写回」** —— 那样会在
   * 「上一次关闭」与「这一次打开」之间产生竞态：刚设上的标志被
   * 紧接着触发的 onDisappear 清掉，面板开了又关（实测反馈）。
   */
  @State private sheetOpen: boolean = false;
  /**
   * 面板内容：0=关于应用 1=隐私协议 2=用户协议 3=开源声明。
   *
   * 与开关分开存：这样切内容不用动开关，也就不会触发开关的竞态。
   */
  @State private sheetDoc: number = 0;
  /** 重看启动引导（设置页入口）。 */
  onReplayOnboarding: () => void = (): void => {};
  @StorageProp('ngf_current_theme') private currentTheme: string = 'auto';
  @State private scanIntensity: string = 'balanced';
  /** 当前外观主题覆盖（auto / light / dark），用于给三个按钮显示选中态。 */
  @State private themeOverride: string = 'auto';
  @State private paused: boolean = false;
  @State private locationTagging: boolean = false;
  /** 实时雷达显示设置（改完立即保存，Live 页每秒同步 → 无需重启）。 */
  @State private radarLabelFields: string = 'name,rssi';
  @State private radarLabelFontSize: number = 12;
  @State private radarIconSize: number = 26;
  /** 权限快照：设置页的权限分区据此显示每条的状态。 */
  @State private capability: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
  // 用应用层的**按能力过滤**目录：不支持星闪的设备不会列出星闪权限。
  private readonly permissionSpecs: FieldwatchPermissionSpec[] = fieldwatchApplication.permissionCatalog();
  /** 通知是否已启用（与普通权限分开跟踪，API 不同）。 */
  @State private notificationEnabled: boolean = false;
  @State private privacyMode: boolean = false;
  @State private keepScreenOn: boolean = false;
  @State private watchNotifications: boolean = false;
  @State private watchBeep: boolean = true;
  @State private watchVoice: boolean = false;
  @State private watchVoiceWhat: string = 'class';
  /** 列表显示的四个开关（§12.2）。 */
  @State private showRssiBar: boolean = true;
  @State private showFleetName: boolean = true;
  @State private showFrequency: boolean = true;
  @State private showSeenTimes: boolean = true;
  /** 列表行是否紧凑（四个视图共用同一套行样式，这里只切换尺寸档）。 */
  @State private compactRows: boolean = false;
  /**
   * 日志等级，取 `LogLevel` 的数值。
   *
   * 初值从应用状态读（构造函数里已按它设过 logger），
   * 保证界面显示的与实际生效的是同一个值。
   */
  @State private logLevel: number = 2;

  /**
   * 日志等级的选项。
   *
   * 只给四档：调试 / 信息 / 警告 / 错误。
   * `OFF` 与 `FATAL` 不给 —— 前者会让出问题时完全无据可查，
   * 后者比错误还高、实际用不到，摆出来只会让人犹豫。
   */
  private logLevelChoices(): LogLevelChoice[] {
    return [
      new LogLevelChoice(0, 'app.string.fieldwatch_log_debug'),
      new LogLevelChoice(1, 'app.string.fieldwatch_log_info'),
      new LogLevelChoice(2, 'app.string.fieldwatch_log_warn'),
      new LogLevelChoice(3, 'app.string.fieldwatch_log_error')
    ];
  }

  /** 语音内容三选一的单个选项；选中态与未选中态前景色成对给出，避免深色下发灰。 */
  @Builder
  voiceChip(value: string, label: Resource) {
    Text(label)
      .fontSize(14)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(18)
      .backgroundColor(this.watchVoiceWhat === value ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().panel)
      .fontColor(this.watchVoiceWhat === value ? $r('app.color.fw_on_primary') : $r('app.color.text_secondary'))
      .onClick((): void => { this.watchVoiceWhat = value; fieldwatchApplication.setWatchVoiceWhat(value); })
  }
  @State private backgroundScanning: boolean = false;
  @State private wifiStatus: string = '';
  /** §12.1：上次扫描的结果数与新鲜度；此前采集了却从未渲染。 */
  @State private wifiResultCount: number = 0;
  @State private wifiFresh: boolean = false;
  /** 星闪扫描相位与最近一次结果数（设备支持时才有意义）。 */
  @State private nearLinkPhase: string = '';
  @State private nearLinkCount: number = 0;
  @State private wifiLastSuccessAt: number = 0;
  @State private wifiNextAttemptAt: number = 0;
  @State private retryRemainingSeconds: number = 0;
  @State private observationCount: number = 0;
  @State private catalogVersion: number = 0;
  @State private catalogStatus: string = '';
  @State private signatureCount: number = 0;
  // 关注列表的计数与条目已随该段迁往独立页面，这里不再保留副本。
  private retryTimer: number = -1;

  aboutToAppear(): void {
    // 界面显示的等级必须与实际生效的一致，所以从应用状态读，不写死。
    this.logLevel = fieldwatchApplication.getState().settings.logLevel;
    this.refresh();
    this.retryTimer = setInterval((): void => { this.refresh(); }, 1000);
  }

  aboutToDisappear(): void {
    if (this.retryTimer >= 0) { clearInterval(this.retryTimer); this.retryTimer = -1; }
  }

  private refresh(): void {
    // **应用在后台时不做任何工作。**
    //
    // 本页的定时器在 `Tabs` 里随页面一起常驻，退到后台不会停。
    // 之前每秒都在重读主题门面、权限快照（3 次 checkPermission）和一整排 state 字段，
    // 叠加 Live 页的每秒刷新后，实测后台 CPU 稳定在 8~10%，
    // 与基线对照后归因给本应用的后台耗电约 **8.9%/小时**。
    // 这些值在后台没有任何观察者，纯属白算。
    // 保留定时器本身（唤醒开销极小）作为回到前台的探测点。
    if (!fieldwatchApplication.isAppForeground()) return;
    const state = fieldwatchApplication.getState();
    this.scanIntensity = state.settings.scanIntensity;
    // 主题由平台门面持有，必须主动读回来 —— 否则三个按钮永远显示不出选中态。
    this.themeOverride = themeModeName(ngfThemeManagerFacade.getCurrentTheme());
    this.paused = state.settings.displayPaused;
    this.locationTagging = state.settings.locationTagging;
    this.capability = fieldwatchApplication.permissionSnapshot();
    // 通知状态同样每秒读一次：在系统设置里改完回来要立刻反映。
    void ngfSystemNotificationManager.isEnabled().then((enabled: boolean): void => {
      if (enabled !== this.notificationEnabled) this.notificationEnabled = enabled;
    });
    this.privacyMode = state.settings.privacyMode;
    this.keepScreenOn = state.settings.keepScreenOn;
    this.watchNotifications = state.settings.watchNotifications;
    this.watchBeep = state.settings.watchBeep;
    this.watchVoice = state.settings.watchVoice;
    this.watchVoiceWhat = state.settings.watchVoiceWhat;
    this.showRssiBar = state.settings.showRssiBar;
    this.showFleetName = state.settings.showFleetName;
    this.showFrequency = state.settings.showFrequency;
    this.showSeenTimes = state.settings.showSeenTimes;
    this.compactRows = state.settings.listCompactRows;
    this.backgroundScanning = state.settings.backgroundScanning;
    // **相位不能直接显示原始枚举**（`waiting_for_retry` / `scanning` …）——
    // 那是给代码看的英文标识，用户读不懂，也没有本地化。
    // 与详情页里修过的「频段 1 / 信道宽度 0」是同一类问题。
    this.wifiStatus = this.wifiPhaseText(state.wifiSnapshot.phase);
    // 这两个此前**采集了却从未渲染**，§12.1 要求「显示扫描…状态」，
    // 结果数（上次扫到几个）与新鲜度（这批结果是不是新的）正是状态的一部分。
    this.wifiResultCount = state.wifiSnapshot.resultCount;
    this.wifiFresh = state.wifiSnapshot.fresh;
    this.nearLinkPhase = state.nearLinkSnapshot.phase;
    this.nearLinkCount = state.nearLinkSnapshot.resultCount;
    this.wifiLastSuccessAt = state.wifiSnapshot.lastSuccessAt;
    this.wifiNextAttemptAt = state.wifiSnapshot.nextAttemptAt;
    this.retryRemainingSeconds = remainingAttemptSeconds(this.wifiNextAttemptAt);
    this.observationCount = state.sightings.length;
    this.catalogVersion = state.catalogVersion;
    this.catalogStatus = state.catalogStatus;
    this.signatureCount = state.signatures.length;
    // 关注列表不再在本页展示，不再读 watchlist。
  }

  private wifiPhaseText(phase: string): string {
    return wifiPhaseLabel(this.getUIContext().getHostContext(), phase);
  }

  /**
   * 星闪扫描状态文案。
   *
   * 设备不支持时明确说明「本机不支持星闪」，而不是显示一个恒为 idle 的状态 ——
   * 后者会让用户以为功能坏了。
   */
  private nearLinkStatusText(): string {
    const context = this.getUIContext().getHostContext();
    const prefix: string = resolveResourceString(context, $r('app.string.fieldwatch_scan_nearlink_state')) + ': ';
    if (!fieldwatchApplication.nearLinkAvailable()) {
      return prefix + resolveResourceString(context, $r('app.string.fieldwatch_scan_nearlink_unsupported'));
    }
    return prefix + this.nearLinkPhase + ' · ' + this.nearLinkCount.toString() + ' 个';
  }
  private catalogStatusText(): string {
    const key: string = this.catalogStatus === 'updating' ? 'app.string.fieldwatch_catalog_status_updating'
      : this.catalogStatus === 'updated' ? 'app.string.fieldwatch_catalog_status_updated'
        : this.catalogStatus === 'failed' ? 'app.string.fieldwatch_catalog_status_failed'
          : 'app.string.fieldwatch_catalog_status_builtin';
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  /** 雷达标签字段开关：切换后立即保存，Live 页下一秒内生效。 */
  @Builder private buildFieldToggle(field: string, label: ResourceStr) {
    Row() {
      Text(label).layoutWeight(1).fontSize(14)
      Toggle({ type: ToggleType.Switch, isOn: this.radarLabelFields.indexOf(field) >= 0 })
        .onChange((value: boolean): void => {
          const parts: string[] = this.radarLabelFields.split(',').filter((item: string): boolean => item.length > 0 && item !== field);
          if (value) parts.push(field);
          const next: string = parts.join(',');
          this.radarLabelFields = next;
          fieldwatchApplication.setRadarLabelFields(next);
        })
    }.width('100%')
  }
  /** 尺寸步进器：字号（step 1）或图标大小（step 2）。 */
  /**
   * 尺寸步进器。
   *
   * **不要在 @Builder 里用参数传数值**：@Builder 的参数不是响应式状态，
   * 传进来的 number 只会在首次渲染时取值，之后加减都不会让 Text 更新。
   * 因此这里直接在 builder 内部读 @State，ArkUI 才能建立依赖并重绘。
   */
  @Builder private buildSizeStepper(label: ResourceStr, isFont: boolean) {
    Row({ space: 6 }) {
      Text(label).layoutWeight(1).fontSize(14)
      Button('-').height(32).width(44).backgroundColor(Color.Transparent)
        .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text)
        .onClick((): void => { this.applySize(isFont, -1); })
      Text(isFont ? this.radarLabelFontSize.toString() : this.radarIconSize.toString())
        .fontSize(14).width(44).textAlign(TextAlign.Center)
      Button('+').height(32).width(44).backgroundColor(Color.Transparent)
        .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text)
        .onClick((): void => { this.applySize(isFont, 1); })
    }.width('100%')
  }
  /** @param delta 方向（-1 减 / +1 加）；当前值直接读 @State，避免用不响应式的 builder 参数。 */
  private applySize(isFont: boolean, delta: number): void {
    if (isFont) {
      const next: number = this.radarLabelFontSize + delta;
      fieldwatchApplication.setRadarLabelFontSize(next);
      this.radarLabelFontSize = fieldwatchApplication.getState().settings.radarLabelFontSize;
    } else {
      const next: number = this.radarIconSize + delta * 2;
      fieldwatchApplication.setRadarIconSize(next);
      this.radarIconSize = fieldwatchApplication.getState().settings.radarIconSize;
    }
  }
  /** 设置页权限行：标题 + 状态 + 未授权时的「允许」按钮。 */
  /**
   * 权限卡片。**与启动引导里的是同一种卡片**（图标徽标 + 标题 + 状态 +
   * 用途 + 能力 + 被拒说明），而不是一行文字。
   *
   * 设置页的权限区是用户「回来补授权」的地方，信息必须和引导页一样全 ——
   * 只给一行标题的话，用户根本想不起来这条权限是干什么的。
   */
  @Builder private buildPermissionRow(spec: FieldwatchPermissionSpec) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r(this.permissionSymbol(spec.kind)))
            .fontSize(18).fontColor([FieldwatchPaletteHolder.get().accent])
        }.width(36).height(36).borderRadius(18).backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
        Text($r(spec.titleKey)).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        if (this.permissionGranted(spec.kind)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14)
              .fontColor([FieldwatchPaletteHolder.get().accent])
            Text($r('app.string.fieldwatch_onb_allowed')).fontSize(13)
              .fontColor(FieldwatchPaletteHolder.get().accent)
          }
        } else {
          Row({ space: 6 }) {
            FieldwatchButton({ label: $r('app.string.fieldwatch_onb_allow'), tone: FieldwatchButtonTone.PRIMARY,
              compact: true, fillWidth: false, onTap: (): void => { void this.requestOnePermission(spec.kind); } })
            Button($r('app.string.fieldwatch_manual_open_short')).height(32).fontSize(13)
              .backgroundColor(Color.Transparent).borderWidth(1)
              .borderColor(FieldwatchPaletteHolder.get().outline)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
              .onClick((): void => { this.openAppSettings(); })
          }
        }
      }.width('100%')
      Text($r(spec.whyKey)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_checkmark')).fontSize(12)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
        Text($r(spec.featureKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
      }.width('100%')
      // 被拒说明只在**确实没授权**时出现，否则四张卡片都挂一句警告，读起来像全是问题。
      if (!this.permissionGranted(spec.kind)) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(12)
            .fontColor([FieldwatchPaletteHolder.get().warn])
          Text($r(spec.deniedKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().warn).layoutWeight(1)
        }.width('100%')
      }
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(14)
  }

  /** 每条权限一个可辨识的图标（与引导页同一套映射）。 */
  private permissionSymbol(kind: FieldwatchPermissionKind): string {
    if (kind === FieldwatchPermissionKind.BLUETOOTH) return 'sys.symbol.dot_radiowaves';
    if (kind === FieldwatchPermissionKind.LOCATION) return 'sys.symbol.location_up_fill';
    return 'sys.symbol.location_up_fill';
  }

  /**
   * 通知权限卡片。
   *
   * **通知不走 `requestPermissionsFromUser`**，而是
   * `notificationManager.requestEnableNotification`，所以它不能混在权限目录里，
   * 必须单独成卡 —— 之前设置页压根没有它，用户找不到地方开。
   */
  @Builder private buildNotificationPermissionRow() {
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
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14)
              .fontColor([FieldwatchPaletteHolder.get().accent])
            Text($r('app.string.fieldwatch_onb_allowed')).fontSize(13)
              .fontColor(FieldwatchPaletteHolder.get().accent)
          }
        } else {
          Row({ space: 6 }) {
            FieldwatchButton({ label: $r('app.string.fieldwatch_onb_allow'), tone: FieldwatchButtonTone.PRIMARY,
              compact: true, fillWidth: false, onTap: (): void => { void this.requestNotificationPermission(); } })
            Button($r('app.string.fieldwatch_manual_open_short')).height(32).fontSize(13)
              .backgroundColor(Color.Transparent).borderWidth(1)
              .borderColor(FieldwatchPaletteHolder.get().outline)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
              .onClick((): void => { this.openAppSettings(); })
          }
        }
      }.width('100%')
      Text($r('app.string.fieldwatch_notification_permission_reason')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_checkmark')).fontSize(12)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
        Text($r('app.string.fieldwatch_settings_notif_feature')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
      }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(14)
  }

  /** 申请通知权限；结果立刻读回来，别让卡片停留在旧状态。 */
  private async requestNotificationPermission(): Promise<void> {
    await ngfSystemNotificationManager.requestPermission();
    this.notificationEnabled = await ngfSystemNotificationManager.isEnabled();
  }
  /** 打开本应用在系统设置里的权限页（与引导页同一 want）。 */
  /** 跳系统设置：与引导页共用同一个应用层实现，避免两处逻辑漂移。 */
  private openAppSettings(): void {
    fieldwatchApplication.openAppPermissionSettings((): void => {
      this.getUIContext().getPromptAction().showToast({
        message: resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_manual_toast')),
        duration: 3000
      });
    });
  }


  private permissionGranted(kind: FieldwatchPermissionKind): boolean {
    // 「设备发现和连接」同时管蓝牙与星闪：两者都拿到才算已授权。
    // 设备不支持星闪时不参与判定，否则会永远显示为未授权。
    if (kind === FieldwatchPermissionKind.BLUETOOTH) {
      const bleOk: boolean = this.capability.bluetooth;
      const nlOk: boolean = !fieldwatchApplication.nearLinkAvailable() || this.capability.nearlink;
      return bleOk && nlOk;
    }
    
    if (kind === FieldwatchPermissionKind.LOCATION) return this.capability.location;
    return this.capability.location;
  }
  /** 单条权限：授权成功后立刻刷新快照，并在获得扫描能力时启动扫描。 */
  /**
   * 单条权限：授权成功后启动扫描；**失败时必须弹说明框**。
   * 权限一旦被系统标记为「用户已决定」，requestPermissionsFromUser 会直接返回拒绝且不再弹窗，
   * 只更新状态而不告知用户，按钮看起来就是「点了没反应」。
   */
  private async requestOnePermission(kind: FieldwatchPermissionKind): Promise<void> {
    await fieldwatchApplication.requestPermission(kind);
    this.capability = fieldwatchApplication.permissionSnapshot();
    const granted: boolean = kind === FieldwatchPermissionKind.BLUETOOTH
      ? this.capability.bluetooth
      : this.capability.location;
    if (granted) {
      fieldwatchApplication.startScan();
      return;
    }
    this.showManualGrantDialog(kind);
  }
  /**
   * 「系统不会再弹出授权窗口」说明框。
   * **权限名称与系统设置路径都取自该权限自己的 spec**，
   * 不能写成固定文案 —— 否则两条权限会显示同一个名字，用户无从下手。
   */
  private showManualGrantDialog(kind: FieldwatchPermissionKind): void {
    const spec: FieldwatchPermissionSpec | undefined = fieldwatchApplication.permissionSpec(kind);
    if (spec === undefined) return;
    const host = this.getUIContext().getHostContext();
    const name: string = resolveResourceString(host, $r(spec.titleKey));
    const where: string = resolveResourceString(host, $r(spec.whereKey));
    this.getUIContext().showAlertDialog({
      title: resolveResourceString(host, $r('app.string.fieldwatch_manual_title')),
      message: resolveResourceString(host, $r('app.string.fieldwatch_manual_body'))
        .replace('%s', name)
        .replace('%p', where),
      primaryButton: {
        value: resolveResourceString(host, $r('app.string.fieldwatch_manual_cancel')),
        action: (): void => {}
      },
      secondaryButton: {
        value: resolveResourceString(host, $r('app.string.fieldwatch_manual_open')),
        action: (): void => { this.openAppSettings(); }
      }
    });
  }


  @Builder private buildSettingsScan() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_scan')).fontSize(18).fontWeight(FontWeight.Medium)
    Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_scan_current')) + ': ' + this.scanIntensity).fontSize(14).fontColor($r('app.color.text_secondary'))
    // 三档扫描强度必须显示选中态，否则点了看不出变化。
    Row({ space: 8 }) {
    FieldwatchChip({ label: $r('app.string.wifi_scan_basic'), active: this.scanIntensity === 'basic',
    onTap: (): void => { this.scanIntensity = 'basic'; fieldwatchApplication.setScanIntensity('basic'); this.tick += 1; } })
    FieldwatchChip({ label: $r('app.string.wifi_scan_balanced'), active: this.scanIntensity === 'balanced',
    onTap: (): void => { this.scanIntensity = 'balanced'; fieldwatchApplication.setScanIntensity('balanced'); this.tick += 1; } })
    FieldwatchChip({ label: $r('app.string.wifi_scan_saver'), active: this.scanIntensity === 'saver',
    onTap: (): void => { this.scanIntensity = 'saver'; fieldwatchApplication.setScanIntensity('saver'); this.tick += 1; } })
    }.width('100%')
    Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_status')) + ': ' + this.wifiStatus
    + (this.wifiResultCount > 0 ? ' · ' + this.wifiResultCount.toString() + ' 个结果' : '')
    + (this.wifiResultCount > 0 && !this.wifiFresh ? ' · ' + resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.wifi_cached')) : ''))
    .fontSize(14).fontColor($r('app.color.text_secondary'))
    // §12.1「解释系统扫描频率限制和可能的等待时间」：
    // 用户看到「下次尝试」和倒计时却不知道为什么，需要一句说明。
    Text($r('app.string.fieldwatch_wifi_throttle_hint')).fontSize(12).fontColor($r('app.color.text_secondary')).fontColor($r('app.color.text_secondary'))
    // 星闪扫描状态：只在设备支持时出现，不支持时给出一句明确说明而不是留空。
    Text(this.nearLinkStatusText()).fontSize(14)
    .fontColor(fieldwatchApplication.nearLinkAvailable()
    ? FieldwatchPaletteHolder.get().textDim : FieldwatchPaletteHolder.get().amber)
    Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_last_success')) + ': ' + this.timeLabel(this.wifiLastSuccessAt)).fontSize(14).fontColor($r('app.color.text_secondary'))
    Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_next_attempt')) + ': ' + this.timeLabel(this.wifiNextAttemptAt)).fontSize(14).fontColor($r('app.color.text_secondary'))
    if (this.retryRemainingSeconds > 0) Text(this.retryCountdownLabel()).fontSize(14).fontColor(FieldwatchPaletteHolder.get().amber)
    Button($r('app.string.fieldwatch_settings_retry')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { fieldwatchApplication.retryWifiScan(); this.refresh(); })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  @Builder private buildSettingsAppearance() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_permissions')).fontSize(18).fontWeight(FontWeight.Medium)
    Text($r('app.string.fieldwatch_settings_permissions_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    ForEach(this.permissionSpecs, (spec: FieldwatchPermissionSpec): void => {
    this.buildPermissionRow(spec)
    }, (spec: FieldwatchPermissionSpec): string => spec.kind)
    // 通知权限单独成卡（API 不同，不进权限目录）。
    this.buildNotificationPermissionRow()
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  @Builder private buildSettingsPrivacy() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_radar_display')).fontSize(18).fontWeight(FontWeight.Medium)
    Text($r('app.string.fieldwatch_settings_radar_display_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    this.buildFieldToggle('name', $r('app.string.fieldwatch_radar_field_name'))
    this.buildFieldToggle('address', $r('app.string.fieldwatch_radar_field_address'))
    this.buildFieldToggle('type', $r('app.string.fieldwatch_radar_field_type'))
    this.buildFieldToggle('rssi', $r('app.string.fieldwatch_radar_field_rssi'))
    this.buildFieldToggle('freq', $r('app.string.fieldwatch_radar_field_freq'))
    this.buildSizeStepper($r('app.string.fieldwatch_radar_label_size'), true)
    this.buildSizeStepper($r('app.string.fieldwatch_radar_icon_size'), false)
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  @Builder private buildSettingsListDisplay() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_display')).fontSize(18).fontWeight(FontWeight.Medium)
    Text($r('app.string.fieldwatch_settings_theme')).fontSize(16).fontWeight(FontWeight.Medium)
    Row({ space: 8 }) {
    // 三个按钮必须显示选中态，否则用户点了看不出任何变化（这正是之前的现象）。
    Button($r('app.string.fieldwatch_settings_theme_auto')).backgroundColor(Color.Transparent).borderWidth(1)
    .borderColor(this.themeOverride === 'auto' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
    .fontColor(this.themeOverride === 'auto' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
    .layoutWeight(1).onClick((): void => { this.applyTheme(NGFThemeMode.AUTO); })
    Button($r('app.string.fieldwatch_settings_theme_light')).backgroundColor(Color.Transparent).borderWidth(1)
    .borderColor(this.themeOverride === 'light' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
    .fontColor(this.themeOverride === 'light' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
    .layoutWeight(1).onClick((): void => { this.applyTheme(NGFThemeMode.LIGHT); })
    Button($r('app.string.fieldwatch_settings_theme_dark')).backgroundColor(Color.Transparent).borderWidth(1)
    .borderColor(this.themeOverride === 'dark' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
    .fontColor(this.themeOverride === 'dark' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
    .layoutWeight(1).onClick((): void => { this.applyTheme(NGFThemeMode.DARK); })
    }.width('100%')
    Button($r('app.string.fieldwatch_settings_replay_onboarding')).height(44).width('100%')
    .backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline)
    .fontColor(FieldwatchPaletteHolder.get().text)
    .onClick((): void => { this.onReplayOnboarding(); })

    Row() { Text($r('app.string.fieldwatch_settings_pause')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.paused }).onChange((value: boolean): void => { this.paused = value; fieldwatchApplication.setDisplayPaused(value); }) }.width('100%')
    Row() { Text($r('app.string.fieldwatch_settings_keep_screen_on')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn }).onChange((value: boolean): void => { void fieldwatchApplication.setKeepScreenOn(value).then((): void => { this.keepScreenOn = value; }); }) }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  @Builder private buildSettingsPermissions() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_location')).fontSize(18).fontWeight(FontWeight.Medium)
    Text($r('app.string.fieldwatch_settings_location_tagging')).fontSize(14).fontColor($r('app.color.text_secondary'))
    Toggle({ type: ToggleType.Switch, isOn: this.locationTagging }).onChange((value: boolean): void => { this.locationTagging = value; fieldwatchApplication.setLocationTagging(value); })
    // ── 列表显示的四个开关（§12.2 显示设置）──
    // 此前一项都没有，列表行里的 RSSI 条 / 频率 / First-Last 全部无条件渲染，
    // 而「显示签名名称」连展示能力本身都缺（列表行里根本没有签名名）。
    Text($r('app.string.fieldwatch_settings_display_section')).fontSize(14).fontColor($r('app.color.text_secondary'))
    Row() { Text($r('app.string.fieldwatch_settings_show_rssi_bar')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.showRssiBar })
    .onChange((value: boolean): void => { this.showRssiBar = value; fieldwatchApplication.setShowRssiBar(value); }) }
    Row() { Text($r('app.string.fieldwatch_settings_show_fleet_name')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.showFleetName })
    .onChange((value: boolean): void => { this.showFleetName = value; fieldwatchApplication.setShowFleetName(value); }) }
    Row() { Text($r('app.string.fieldwatch_settings_show_frequency')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.showFrequency })
    .onChange((value: boolean): void => { this.showFrequency = value; fieldwatchApplication.setShowFrequency(value); }) }
    Row() { Text($r('app.string.fieldwatch_settings_show_seen_times')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.showSeenTimes })
    .onChange((value: boolean): void => { this.showSeenTimes = value; fieldwatchApplication.setShowSeenTimes(value); }) }
    // 行密度：强度/时间线/信号轨迹/分类四个视图共用同一套行样式，
    // 这里只切换取哪一档尺寸（紧凑档一屏能多看几台）。
    Row() { Text($r('app.string.fieldwatch_settings_compact_rows')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.compactRows })
    .onChange((value: boolean): void => { this.compactRows = value; fieldwatchApplication.setListCompactRows(value); }) }
    Text($r('app.string.fieldwatch_settings_compact_rows_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    Row() { Text($r('app.string.fieldwatch_settings_privacy_mode')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.privacyMode }).onChange((value: boolean): void => { this.privacyMode = value; fieldwatchApplication.setPrivacyMode(value); }) }.width('100%')
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  /**
   * **通知与语音**：从「位置与隐私」里拆出来的独立一段。
   *
   * 原先它们混在位置设置下面 —— 「通知」与「语音告警」是两类不同的东西，
   * 和定位没有任何关系，放在一起让人找不到（实测反馈）。
   */
  @Builder private buildSettingsAlerts() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_alerts')).fontSize(18).fontWeight(FontWeight.Medium)
    Row() { Text($r('app.string.fieldwatch_settings_watch_notifications')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.watchNotifications }).onChange((value: boolean): void => { void fieldwatchApplication.setWatchNotifications(value).then((enabled: boolean): void => { this.watchNotifications = enabled; }); }) }.width('100%')
    Text($r('app.string.fieldwatch_settings_notifications_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    // ── 关注列表的可听告警（§12.3）──
    // 受上面的「关注通知」总开关管辖，这两个是子开关；与 Hunt 的 geiger tick 是两套告警。
    Row() { Text($r('app.string.fieldwatch_settings_watch_beep')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.watchBeep })
    .onChange((value: boolean): void => { this.watchBeep = value; fieldwatchApplication.setWatchBeep(value); }) }
    Text($r('app.string.fieldwatch_settings_watch_beep_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    Row() { Text($r('app.string.fieldwatch_settings_watch_voice')).layoutWeight(1);
    Toggle({ type: ToggleType.Switch, isOn: this.watchVoice })
    .onChange((value: boolean): void => { this.watchVoice = value; fieldwatchApplication.setWatchVoice(value); }) }
    Text($r('app.string.fieldwatch_settings_watch_voice_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    // 语音内容三选一，对应原版 AlertVoiceWhat。
    Text($r('app.string.fieldwatch_settings_voice_content')).fontSize(14).fontColor($r('app.color.text_secondary'))
    Row({ space: 8 }) {
    this.voiceChip('class', $r('app.string.fieldwatch_settings_voice_class'))
    this.voiceChip('signature', $r('app.string.fieldwatch_settings_voice_signature'))
    this.voiceChip('classSignature', $r('app.string.fieldwatch_settings_voice_both'))
    }.width('100%').justifyContent(FlexAlign.Start)
    Button($r('app.string.fieldwatch_settings_alert_test'))
    .backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().accent).fontColor(FieldwatchPaletteHolder.get().accent)
    .height(40).width('100%')
    .onClick((): void => { fieldwatchApplication.playAlertTest(); })
    Row() { Text($r('app.string.fieldwatch_settings_background_scanning')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.backgroundScanning }).onChange((value: boolean): void => { void fieldwatchApplication.setBackgroundScanning(value).then((enabled: boolean): void => { this.backgroundScanning = enabled; }); }) }.width('100%')
    Text($r('app.string.fieldwatch_settings_background_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }

  // 关注列表已从设置页迁出：现在是一个独立页面（`FieldwatchWatchlistPage`），
  // 从特征库进入，卡片点击也直达它。设置页不再重复提供第二份入口 ——
  // 同一个东西两个入口，迟早会有一处忘了改（陷阱 16）。
  /**
   * **关于应用**：版本信息、使用条款与开源声明。
   *
   * 原先这里只有「特征目录」，而「关于」面板的入口恰好藏在它里面 ——
   * 删掉特征目录时差点让那个面板失去入口。现在把三份文档与「关于」放在一起，
   * 它们本来就是同一类东西（关于这个应用本身）。
   */
  @Builder private buildSettingsLegal() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_settings_legal')).fontSize(18).fontWeight(FontWeight.Medium)
      Text($r('app.string.fieldwatch_settings_legal_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
      // 反馈中心放在「关于」这一组：它和条款、开源声明是同一类东西
      // —— 都是「关于这个应用」的对外通道。
      FieldwatchButton({ label: $r('app.string.fieldwatch_settings_feedback'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.onOpenFeedback(); } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_settings_about'), tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.sheetDoc = 0; this.sheetOpen = true; } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_legal_privacy'), tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.sheetDoc = 1; this.sheetOpen = true; } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_legal_terms'), tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.sheetDoc = 2; this.sheetOpen = true; } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_legal_oss'), tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.sheetDoc = 3; this.sheetOpen = true; } })
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }


  @Builder private buildSettingsGuide() {
    Column({ space: 8 }) {
    Text($r('app.string.fieldwatch_settings_data')).fontSize(18).fontWeight(FontWeight.Medium)
    Text(resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_observation_count')) + ': ' + this.observationCount.toString()).fontSize(14).fontColor($r('app.color.text_secondary'))
    Button($r('app.string.fieldwatch_reports_clear_logs')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).enabled(this.observationCount > 0).onClick((): void => { void fieldwatchApplication.clearObservationLog().then((): void => { this.refresh(); }); })
    Button($r('app.string.fieldwatch_settings_backup')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { fieldwatchApplication.saveSettingsBackup(); })
    Button($r('app.string.fieldwatch_settings_restore')).backgroundColor(Color.Transparent).borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline).fontColor(FieldwatchPaletteHolder.get().text).onClick((): void => { fieldwatchApplication.restoreSettingsBackup(); this.refresh(); })
    Text($r('app.string.fieldwatch_local_file_hint')).fontSize(13).fontColor($r('app.color.text_secondary'))
    // ── 日志等级 ──
    //
    // 默认 WARN：DEBUG/INFO 在扫描期间每秒都在打，真机上既拖性能、
    // 又把真正要看的那几条淹没。需要排查时再临时调低。
    Text($r('app.string.fieldwatch_settings_log_level')).fontSize(14)
      .fontColor($r('app.color.text_secondary'))
    Row({ space: 8 }) {
      ForEach(this.logLevelChoices(), (item: LogLevelChoice): void => {
        FieldwatchChip({ label: $r(item.labelKey), active: this.logLevel === item.value,
          onTap: (): void => {
            this.logLevel = item.value;
            fieldwatchApplication.setLogLevel(item.value);
            this.tick += 1;
          } })
      }, (item: LogLevelChoice): string => item.value.toString())
    }.width('100%').justifyContent(FlexAlign.Start)
    Text($r('app.string.fieldwatch_settings_log_level_hint')).fontSize(13)
      .fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
  }


  build() { Scroll() { Column({ space: 14 }) {
    Text($r('app.string.fieldwatch_settings_title')).fontSize(26).fontWeight(FontWeight.Bold)
    // **两列**：横屏且右栏未开。右栏一开可用宽度只剩三分之一，回到单列。
    if (this.twoColumn) {
      // **手写两列**：每列各自纵向堆叠，互不参照对方高度。
      //
      // 试过两种容器，都不行：
      //   - `Grid`：按行对齐，每行高度取该行最高的那个 -> 矮卡旁边必然留空；
      //   - `WaterFlow`：要测量每个 item 的高度，嵌在 `Scroll` 里约束无限，
      //     测错行高 -> **卡片互相重叠**（实测）。
      // 两个 `Column` 没有行对齐、也不需要测量，天然正确。
      Row({ space: 12 }) {
        Column({ space: 12 }) {
          this.buildSettingsScan()
          this.buildSettingsPrivacy()
          this.buildSettingsPermissions()
          this.buildSettingsAlerts()
          this.buildSettingsGuide()
        }.layoutWeight(1)
        Column({ space: 12 }) {
          this.buildSettingsAppearance()
          this.buildSettingsListDisplay()
          this.buildSettingsLegal()
        }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      this.buildSettingsScan()
      this.buildSettingsAppearance()
      this.buildSettingsPrivacy()
      this.buildSettingsListDisplay()
      this.buildSettingsPermissions()
      this.buildSettingsAlerts()
      this.buildSettingsGuide()
      this.buildSettingsLegal()
    }
  }.width('100%').padding({ left: 16, right: 16, top: this.topInset + 16, bottom: 48 }) }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    /**
     * **一个组件只能绑一个 `bindSheet`。**
     *
     * 之前这里绑了两次（关于面板 + 条款面板）—— `bindSheet` 是单槽属性，
     * **后一次绑定会把前一次顶掉**，于是条款能开、关于打不开（实测反馈）。
     *
     * 现在只绑一次：`sheetDoc` 决定内容（0 = 关于应用），
     * `$$this.sheetOpen` 只管开关 —— 下滑关闭由 ArkUI 自己写回 false，
     * **不需要 onDisappear 手动清状态**，也就没有那个竞态。
     */
    .bindSheet($$this.sheetOpen, this.buildSettingsSheet(), { height: SheetSize.LARGE })
  }

  /**
   * 条款面板：隐私协议 / 用户协议 / 开源声明共用同一个 sheet，按 `sheetDoc` 选正文。
   *
   * 三份文档结构相同（标题 + 若干段），共用一个面板比写三个 `bindSheet` 少一半代码，
   * 也不会出现「改了两处漏了第三处」。
   */
  /** 设置页唯一的 sheet 入口：按 `sheetDoc` 决定显示「关于」还是某份条款。 */
  @Builder private buildSettingsSheet() {
    if (this.sheetDoc === 0) {
      this.buildAboutSheet()
    } else if (this.sheetDoc === 3) {
      // 开源声明单独成块：正文里要插一个**可点击的仓库链接**，
      // 而通用条款 sheet 只渲染纯文本段落。
      this.buildOssSheet()
    } else {
      this.buildLegalSheet()
    }
  }

  /**
   * 开源声明。
   *
   * 仓库地址**单独做成可点击组件**，而不是混在正文里当普通文字 ——
   * 混在段落里既点不动、也看不出是链接（用户反馈）。
   */
  @Builder private buildOssSheet() {
    Column({ space: 12 }) {
      Text(this.text('app.string.fieldwatch_legal_oss')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Scroll() {
        Column({ space: 12 }) {
          Text(this.text('app.string.fieldwatch_legal_oss_p1')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
          // ── 仓库链接（可点）──
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.link')).fontSize(18)
              .fontColor([FieldwatchPaletteHolder.get().accent])
            Column({ space: 2 }) {
              Text(this.text('app.string.fieldwatch_legal_oss_repo_label')).fontSize(11)
                .fontColor(FieldwatchPaletteHolder.get().textDim)
              Text(REPOSITORY_URL).fontSize(14)
                .fontColor(FieldwatchPaletteHolder.get().accent)
                .decoration({ type: TextDecorationType.Underline, color: FieldwatchPaletteHolder.get().accent })
                .maxLines(2)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding(12).borderRadius(12)
          .backgroundColor(FieldwatchPaletteHolder.get().night)
          .onClick((): void => { void this.openAppGallery(REPOSITORY_URL); })
          Text(this.text('app.string.fieldwatch_legal_oss_p2')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
          Text(this.text('app.string.fieldwatch_legal_oss_p3')).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      FieldwatchButton({ label: $r('app.string.fieldwatch_about_close'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.sheetOpen = false; } })
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 }).alignItems(HorizontalAlign.Start)
  }

  /** 统一的取文案入口（设置页里多处需要字符串）。 */
  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  @Builder private buildLegalSheet() {
    Column({ space: 12 }) {
      Text(this.legalTitle()).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.legalParagraphs(), (para: string): void => {
            Text(para).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
          }, (para: string, index: number): string => index.toString())
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      FieldwatchButton({ label: $r('app.string.fieldwatch_about_close'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.sheetOpen = false; } })
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 }).alignItems(HorizontalAlign.Start)
  }

  /** 当前文档的标题键。 */
  private legalTitleKey(): string {
    if (this.sheetDoc === 1) return 'app.string.fieldwatch_legal_privacy';
    if (this.sheetDoc === 2) return 'app.string.fieldwatch_legal_terms';
    return 'app.string.fieldwatch_legal_oss';
  }
  private legalTitle(): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(this.legalTitleKey()));
  }
  /**
   * 当前文档的正文段落。
   *
   * 每段是独立字符串键，而不是一整块带换行的长文本 ——
   * 段落化之后排版由 ArkUI 负责，中英文混排的换行才正确。
   */
  private legalParagraphs(): string[] {
    const keys: string[] = this.legalParagraphKeys();
    const out: string[] = [];
    keys.forEach((key: string): void => {
      out.push(resolveResourceString(this.getUIContext().getHostContext(), $r(key)));
    });
    return out;
  }
  private legalParagraphKeys(): string[] {
    if (this.sheetDoc === 1) {
      // 隐私声明按服务端/法务给定的版本**逐段列出** ——
      // 段落键固定，改文案只改资源，不动代码。
      const keys: string[] = [];
      for (let i: number = 1; i <= PRIVACY_PARAGRAPH_COUNT; i += 1) {
        keys.push('app.string.fieldwatch_legal_privacy_p' + i.toString());
      }
      return keys;
    }
    if (this.sheetDoc === 2) {
      return ['app.string.fieldwatch_legal_terms_p1', 'app.string.fieldwatch_legal_terms_p2',
        'app.string.fieldwatch_legal_terms_p3'];
    }
    return ['app.string.fieldwatch_legal_oss_p1', 'app.string.fieldwatch_legal_oss_p2',
      'app.string.fieldwatch_legal_oss_p3'];
  }

  /**
   * 「关于」面板。
   *
   * 这里集中说明应用的三条底线：严格离线、只申请两项权限、数据只留在本机。
   * 放在设置页而不是单独页面：信息量小，弹层足够，也避免多一层导航。
   */
  /**
   * 同开发者的其他应用。
   *
   * 链接格式与漫匣一致（AppGallery 详情页 + 分享来源参数）。
   */
  private readonly developerApps: DeveloperApp[] = buildDeveloperApps();

  private async openAppGallery(url: string): Promise<void> {
    if (url.length === 0) return;
    const context: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined) return;
    try {
      await context.openLink(url, { appLinkingOnly: false });
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '打开应用市场失败 code=' + failure.code + ' msg=' + failure.message);
      this.getUIContext().getPromptAction().showToast({
        message: resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_dev_apps_failed')),
        duration: 2200
      });
    }
  }

  /** 与漫匣同一种卡片：图标（可选）+ 名称 + 描述，下面一条「在应用市场查看」。 */
  @Builder private buildDeveloperAppCard(item: DeveloperApp) {
    Column({ space: 0 }) {
      Row({ space: 14 }) {
        if (item.icon !== undefined) {
          Image(item.icon).width(56).height(56).borderRadius(14).objectFit(ImageFit.Cover)
        } else {
          Stack() {
            SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(26)
              .fontColor([FieldwatchPaletteHolder.get().accent])
          }.width(56).height(56).borderRadius(14)
          .backgroundColor(FieldwatchPaletteHolder.get().badgeBg)
        }
        Column({ space: 4 }) {
          Text(item.name).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(FieldwatchPaletteHolder.get().text)
          Text(item.description).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ left: 14, right: 14, top: 14, bottom: 12 })
      if (item.galleryUrl.length > 0) {
        Divider().strokeWidth(1).color(FieldwatchPaletteHolder.get().outline)
          .margin({ left: 14, right: 14 })
        Row() {
          Text($r('app.string.fieldwatch_dev_apps_view')).fontSize(15)
            .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
        }.width('100%').height(48).padding({ left: 14, right: 14 })
        .onClick((): void => { void this.openAppGallery(item.galleryUrl); })
      }
    }.width('100%')
    .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder private buildAboutSheet() {
    Column({ space: 12 }) {
      Text($r('app.string.fieldwatch_about_title')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text($r('app.string.fieldwatch_app_title')).fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim)
      // 一句话介绍：先让人知道这是什么，再往下看原则。
      Text($r('app.string.fieldwatch_about_intro')).fontSize(14)
        .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
      this.aboutLine($r('app.string.fieldwatch_about_principle'))
      this.aboutLine($r('app.string.fieldwatch_about_local'))
      this.aboutLine($r('app.string.fieldwatch_about_permissions'))
      this.aboutLine($r('app.string.fieldwatch_about_radiodb'))
      this.aboutLine($r('app.string.fieldwatch_about_license'))
      // ── 同开发者 App（与漫匣同一个模式：卡片 + 在应用市场查看）──
      Text($r('app.string.fieldwatch_dev_apps')).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text).margin({ top: 8 })
      ForEach(this.developerApps, (item: DeveloperApp): void => {
        this.buildDeveloperAppCard(item)
      }, (item: DeveloperApp): string => item.name)
      FieldwatchButton({ label: $r('app.string.fieldwatch_about_close'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.sheetOpen = false; } })
    }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 24 }).alignItems(HorizontalAlign.Start)
  }
  /** 关于面板里的一条说明：左侧一个圆点，右侧正文。 */
  @Builder private aboutLine(text: ResourceStr) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(14)
        .fontColor([FieldwatchPaletteHolder.get().accent])
      Text(text).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top)
  }
  private timeLabel(value: number): string { return value <= 0 ? resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_none')) : new Date(value).toLocaleTimeString(); }
  private retryCountdownLabel(): string {
    const template: string = resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_settings_retry_countdown'));
    return template.replace('%s', this.retryRemainingSeconds.toString());
  }

  private applyTheme(mode: NGFThemeMode): void {
    ngfThemeManagerFacade.setThemeOverride(mode);
    // 先更新状态让按钮立刻反映选中态，再让平台切换配色。
    this.themeOverride = themeModeName(mode);
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return;
    if (mode === NGFThemeMode.DARK) {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === NGFThemeMode.LIGHT) {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }
}

/**
 * 日志等级的一个选项。
 *
 * 用类而不是对象字面量：ArkTS 不允许未类型化的对象字面量，
 * 而且 `ForEach` 需要一个稳定的键，`value` 正好当键。
 */
/** 本应用的开源仓库地址（开源声明里作为可点击链接展示）。 */
const REPOSITORY_URL: string = 'https://github.com/DaLongZhuaZi/airwavefootprints';

/** 隐私声明的段落数（与 `fieldwatch_legal_privacy_pN` 资源一一对应）。 */
const PRIVACY_PARAGRAPH_COUNT: number = 24;

class LogLevelChoice {
  public value: number;
  public labelKey: string;
  constructor(value: number, labelKey: string) {
    this.value = value;
    this.labelKey = labelKey;
  }
}

/** 同开发者的其他应用（与漫匣同一套数据结构）。 */
class DeveloperApp {
  public name: string;
  public description: string;
  public galleryUrl: string;
  /** 应用图标；没有时用符号占位（与漫匣的 `icon?` 同一个思路）。 */
  public icon: Resource | undefined;
  constructor(name: string, description: string, galleryUrl: string, icon: Resource | undefined) {
    this.name = name;
    this.description = description;
    this.galleryUrl = galleryUrl;
    this.icon = icon;
  }
}

/**
 * 同开发者应用清单。
 *
 * 链接格式与漫匣完全一致（AppGallery 详情页 + 分享来源参数），
 * 这样两边的「同开发者 App」打开的是同一套页面。
 */
function buildDeveloperApps(): DeveloperApp[] {
  const list: DeveloperApp[] = [];
  list.push(new DeveloperApp('漫匣', '一款基于 HarmonyOS 的现代化漫画阅读应用',
    'https://appgallery.huawei.com/app/detail?id=com.dlzz.manxia&channelId=SHARE&source=appshare',
    $r('app.media.devapp_manxia')));
  list.push(new DeveloperApp('花漾字影', '帮您轻松创作更亮眼的手持弹幕内容',
    'https://appgallery.huawei.com/app/detail?id=com.dlzz.lumabloom&channelId=SHARE&source=appshare',
    $r('app.media.devapp_lumabloom')));
  list.push(new DeveloperApp('书脉', '支持多种格式的元数据编辑与封面管理',
    'https://appgallery.huawei.com/app/detail?id=com.dlzz.ebookparser&channelId=SHARE&source=appshare',
    $r('app.media.devapp_shumai')));
  list.push(new DeveloperApp('NGF Coder', '移动端 AI 编程协作工具',
    'https://appgallery.huawei.com/app/detail?id=com.dlzz.coder&channelId=SHARE&source=appshare',
    $r('app.media.devapp_ngfcoder')));
  list.push(new DeveloperApp('神秘 APP', '敬请期待', '', undefined));
  return list;
}

