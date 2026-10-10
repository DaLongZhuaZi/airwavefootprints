import { FileUtils, logger, NGFNotificationRequest, NGFNotificationType, ngfBackgroundTaskManager, ngfLocationManagerFacade, ngfPermissionManagerFacade, ngfScreenKeepAwakeFacade, ngfSystemNotificationManager, ngfSystemShareFacade, resolveResourceString, uiContextManager, LogLevel } from 'ngf_framework';
import { AppSettings, DecodedFieldValue, FieldwatchLogFootprint, FilterDefinition, FilterLogic, FilterPreset, GpsSample, LogEntry, RadioFacts, RadioKind, RadioSourceSnapshot, ScanObservation, ScanState, SignatureClass, Sighting, SitSummary, WatchTarget, foldedSignatureClass } from '../domain/FieldwatchModels';
import { FieldwatchCompareResult, FieldwatchCompareService, FieldwatchFilterEngine, FieldwatchPrivacyService, FieldwatchSignatureEngine } from '../domain/FieldwatchDomainService';
import { SignatureFleet } from '../domain/signatures/FieldwatchSignatureModels';
import { FieldwatchWatchAlert, parseVoiceWhat } from '../platform/FieldwatchWatchAlert';
import { signatureClassLabel } from '../ui/FieldwatchClassLabels';
import { HuntCue, HuntRecord, HuntSession, HuntStats } from '../domain/FieldwatchHunt';
import { matchedSignatureNames, signatureHitCounts } from '../ui/FieldwatchUiState';
import { SignaturePackError, StockCatalogUpdateResult, overlayStockFleets } from '../domain/signatures/FieldwatchSignatureCatalog';
import { FieldwatchSignatureEngine as FieldwatchFleetEngine, FieldwatchSignatureFieldDecoder, SignatureMatchContext, SignatureMatchExplanation, signatureContextOfObservation, signatureContextOfSighting } from '../domain/signatures/FieldwatchSignatureEngine';
import { FieldwatchExportSerializer } from '../domain/FieldwatchExportSerializer';
import { FieldwatchSettingsRepository } from '../data/FieldwatchSettingsRepository';
import {
  buildWidgetCardData, FieldwatchWidgetForm, FieldwatchWidgetState, parseWidgetForms, parseWidgetState
} from '../domain/FieldwatchWidgetState';
import {
  AntiTrackEvent, AntiTrackStats, assessTrack, FollowRisk, formatMinutes, GeoPoint, riskOf, TrackEvidence, TrackPoint,
  TrackSuspect, TRACK_MIN_SAMPLES, TRACK_WINDOW_MS, travelSummaryOf, TravelSummary
} from '../domain/FieldwatchAntiTracking';
import { FieldwatchCatalogImportOutcome, FieldwatchCatalogRepository } from '../data/FieldwatchCatalogRepository';
import { FieldwatchCatalogFileGateway } from '../platform/FieldwatchCatalogFileGateway';
import { FieldwatchBleScanner } from '../radio/FieldwatchBleScanner';
import { FieldwatchNearLinkScanner } from '../radio/FieldwatchNearLinkScanner';
import { IFieldwatchRadioScanner } from '../radio/FieldwatchRadioScanner';
import { FieldwatchWifiScanner } from '../radio/FieldwatchWifiScanner';
import { FieldwatchObservationCoordinator } from '../radio/FieldwatchObservationCoordinator';
import { FieldwatchObservationRepository, FieldwatchStoredObservation } from '../data/FieldwatchObservationRepository';
import { FieldwatchGeoService } from '../domain/FieldwatchDomainService';
import { FieldwatchDebriefPdf } from '../platform/FieldwatchDebriefPdf';
import { CandidateReport, SignatureCandidate, SignatureCandidateEngine, SignatureFamilyHint } from '../domain/FieldwatchCandidateEngine';
import { common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { manager as nearlinkManager } from '@kit.ConnectivityKit';
import { FieldwatchRadioDb } from '../domain/FieldwatchRadioDb';
import { ngfSettingsStoreFacade, ngfWidgetManagerFacade } from 'ngf_framework';
import { buildPermissionSpecs, FieldwatchCapabilitySnapshot, FieldwatchPermissionKind, FieldwatchPermissionSpec } from '../domain/FieldwatchPermissions';
import { fileIo } from '@kit.CoreFileKit';

const TAG: string = 'FieldwatchApplication';
/** 本机轨迹最多保留的定位样本数（约几分钟的步行/驾车）。 */
const TRAVEL_SAMPLE_LIMIT: number = 600;

export class FieldwatchApplicationState {
  public scanState: ScanState = ScanState.IDLE;
  public errorMessage: string = '';
  public sightings: Sighting[] = [];
  public logs: LogEntry[] = [];
  public signatures: SignatureFleet[] = [];
  public catalogVersion: number = 0;
  // 状态键必须与其它赋值点一致（`'builtin'`）。
  // 此前初值是中文显示串 `'内置目录'` —— 靠 `catalogStatusText()` 的兜底分支
  // 恰好也能显示成「内置目录」，所以看不出问题；但状态键混入显示文案是个隐患。
  public catalogStatus: string = 'builtin';
  public watchlist: WatchTarget[] = [];
  public filter: FilterDefinition = new FilterDefinition();
  public settings: AppSettings = new AppSettings();
  public wifiSnapshot: RadioSourceSnapshot = new RadioSourceSnapshot(RadioKind.WIFI);
  public bleSnapshot: RadioSourceSnapshot = new RadioSourceSnapshot(RadioKind.BLE);
  /** 星闪扫描状态；设备不支持星闪时保持默认的 IDLE。 */
  public nearLinkSnapshot: RadioSourceSnapshot = new RadioSourceSnapshot(RadioKind.NEARLINK);
  public activeSit: SitSummary | undefined = undefined;
  public savedSits: SitSummary[] = [];
}

export class FieldwatchApplication {
  private readonly state: FieldwatchApplicationState = new FieldwatchApplicationState();
  private readonly signatureEngine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
  private readonly fleetEngine: FieldwatchFleetEngine = new FieldwatchFleetEngine();
  private readonly fieldDecoder: FieldwatchSignatureFieldDecoder = new FieldwatchSignatureFieldDecoder();
  private readonly catalogFileGateway: FieldwatchCatalogFileGateway = new FieldwatchCatalogFileGateway();
  private readonly geoService: FieldwatchGeoService = new FieldwatchGeoService();
  private readonly debriefPdf: FieldwatchDebriefPdf = new FieldwatchDebriefPdf();
  private readonly candidateEngine: SignatureCandidateEngine = new SignatureCandidateEngine();
  private readonly radioDb: FieldwatchRadioDb = new FieldwatchRadioDb();
  /** 各无线电上次已记录的相位，用于把状态日志降为「仅相位变化时」。 */
  private lastLoggedPhase: Map<string, string> = new Map<string, string>();
  /** 本机 GPS 轨迹样本；由定位更新喂入，供「与你同行」判定与状态行使用。 */
  private travelSamples: GpsSample[] = [];

  /**
   * 每台设备的 (时间, 强度) 序列，反追踪识别用。
   *
   * **为什么另存一份**：`Sighting.rssiSamples` 只有强度、**没有时间**，
   * 而反追踪的核心之一就是「你在动、它的强度几乎不变」的**拟合斜率** ——
   * 没有时间轴就无从拟合。这里按窗口滚动保存，长度有上限。
   */
  private readonly deviceTracks: Map<string, TrackPoint[]> = new Map<string, TrackPoint[]>();
  /** 已经就「疑似跟踪」发过通知的设备；每台每次运行只吵一次。 */
  private readonly antiTrackAlerted: Set<string> = new Set<string>();

  private recordDeviceSample(key: string, at: number, rssi: number): void {
    let list: TrackPoint[] | undefined = this.deviceTracks.get(key);
    if (list === undefined) {
      list = [];
      this.deviceTracks.set(key, list);
    }
    list.push(new TrackPoint(at, rssi));
    // 只留窗口内的：长时间运行不能让这个 Map 无限增长。
    const cutoff: number = at - TRACK_WINDOW_MS;
    while (list.length > 0 && list[0].at < cutoff) list.shift();
  }
  setTravelSamples(samples: GpsSample[]): void {
    this.travelSamples = samples;
    this.filterEngine.setTravelSamples(samples);
  }
  private readonly filterEngine: FieldwatchFilterEngine = new FieldwatchFilterEngine();
  private readonly privacyService: FieldwatchPrivacyService = new FieldwatchPrivacyService();
  private readonly compareService: FieldwatchCompareService = new FieldwatchCompareService();
  private readonly exportSerializer: FieldwatchExportSerializer = new FieldwatchExportSerializer();
  private readonly settingsRepository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
  private readonly catalogRepository: FieldwatchCatalogRepository = new FieldwatchCatalogRepository();
  private readonly observationRepository: FieldwatchObservationRepository = new FieldwatchObservationRepository();
  private radioScanner: FieldwatchObservationCoordinator;
  private sequence: number = 0;
  private restoreStarted: boolean = false;
  private huntSession: HuntSession | undefined = undefined;
  /** 已结束的搜寻记录；只保留最近若干条。 */
  private static readonly HUNT_HISTORY_MAX: number = 20;
  private readonly huntHistory: HuntRecord[] = [];
  /** 反追踪判定记录；只保留最近若干条。 */
  private static readonly ANTITRACK_LOG_MAX: number = 50;
  private readonly antiTrackLog: AntiTrackEvent[] = [];
  private readonly watchedNotificationIds: Map<string, number> = new Map<string, number>();
  /** `reloadSettings` 的重试计数（存储未就绪时用）。 */
  private settingsReloadAttempts: number = 0;
  /** 本次进程是否已做过启动期通知清理。 */
  private notificationsCleared: boolean = false;
  private clearingNotifications: Promise<void> | undefined = undefined;

  /**
   * 启动期清理上一次运行残留的通知。**每个进程只做一次。**
   *
   * 为什么必须做：进程被杀时（崩溃 / 强制停止 / 从最近任务划掉），
   * 上一次的通知不会被撤销 ——
   *   - 关注告警的 id 只在 `watchedNotificationIds` 这个**内存** Map 里，重启即失忆；
   *   - 运行状态通知的伴随 id 由系统每次申请时分配，上一个同样没持久化。
   * 结果是旧通知永远挂在通知栏，和新会话的通知并存。
   *
   * 并发安全：`syncBackgroundTask` 会在第一次发布之前 `await` 它，
   * 因此不会出现「先发新通知、再被这次清理一起清掉」。
   */
  async clearStaleNotifications(): Promise<void> {
    if (this.notificationsCleared) return;
    const pending: Promise<void> | undefined = this.clearingNotifications;
    if (pending !== undefined) { await pending; return; }
    const task: Promise<void> = this.performNotificationCleanup();
    this.clearingNotifications = task;
    try { await task; } finally { this.clearingNotifications = undefined; }
  }

  private async performNotificationCleanup(): Promise<void> {
    this.watchedNotificationIds.clear();
    await ngfSystemNotificationManager.cancelAll();
    this.notificationsCleared = true;
  }
  /** 关注列表的可听告警（双响 + 语音），与 Hunt 的 tick 是两套独立告警。 */
  private readonly watchAlert: FieldwatchWatchAlert = new FieldwatchWatchAlert();
  private nextNotificationId: number = 4101;
  private cachedLocation: GpsSample | undefined = undefined;
  /** 星闪能力探测结果（默认 false，探测通过才置真）。 */
  private nearLinkSupported: boolean = false;
  /** 运行状态通知的刷新计时器；-1 表示未启动。 */
  private stateNotificationTimer: number = -1;
  /** 通知是否已启用；未启用时不发布，避免平台反复报错。 */
  private notificationsEnabled: boolean = false;
  private locationRequest: Promise<GpsSample | undefined> | undefined = undefined;
  private readonly locationTtlMs: number = 15000;

  constructor() {
    this.state.signatures = this.catalogRepository.loadSaved();
    this.state.settings = this.settingsRepository.load();
    this.state.watchlist = this.settingsRepository.loadWatchlist();
    this.radioScanner = this.buildCoordinator();
    this.loadRadioDb();
    // **日志等级要在一切之前生效**，否则启动阶段那几十条 INFO 已经打出去了。
    this.applyLogLevel(this.state.settings.logLevel);
    void this.loadBundledCatalog();
  }

  /**
   * 把设置里的等级应用到 logger。
   *
   * 两个等级都要设：`setLevel` 管要不要构造日志内容，
   * `setHilogOutputLevel` 管要不要真的写进 hilog —— 只设一个仍会漏。
   */
  private applyLogLevel(value: number): void {
    // 只接受 `LogLevel` 的合法取值（-1 与 0..4），其余一律退回 WARN。
    // 不做 `LOG_LEVEL_VALUES.indexOf` —— 那个常量没有从框架导出。
    const valid: boolean = value === LogLevel.OFF
      || (value >= LogLevel.DEBUG && value <= LogLevel.FATAL);
    const level: LogLevel = valid ? value : LogLevel.WARN;
    logger.setLevel(level);
    logger.setHilogOutputLevel(level);
  }

  /**
   * 重新从设置存储读取全部设置。
   *
   * **为什么需要它**：`FieldwatchApplication` 是单例，构造函数在**模块导入时**就执行了，
   * 而框架数据层是在 `EntryAbility.onCreate` 里 `ngfStarterKernel.bootstrap()` 才引导的 ——
   * 也就是**晚于**构造函数。`SettingsManager` 的读接口走的是**内存缓存**，
   * 缓存只在 `initialize()` 之后才填充；构造函数里那次 `load()` 因此全部读成**默认值**，
   * 而之后没有任何地方重读。
   *
   * 后果：**每次启动，所有设置都静默回到默认值** —— 磁盘上的值还在（`save()` 写进去了），
   * 只是没人读。表现就是「开关设好了，重开 app 又变回关闭」。
   *
   * 这也解释了为什么「引导只出现一次」是对的：那个标志是按需查询的
   * （`onboardingSeen()` 在页面里现读），查询时机晚于 bootstrap，所以读得到；
   * 而 `AppSettings` 只在构造期读过一次。
   */
  reloadSettings(): void {
    // **未就绪就重试。**
    //
    // `SettingsManager.initialize` 是 `void` 异步调用的，`bootstrap()` 返回时它多半还没走完；
    // 此时读设置会**静默**全部落回默认值 —— 上一轮只在 onCreate / onWindowStageCreate
    // 各读一次，实测仍然读到了默认值（用户反馈「重开 app 开关又关了」）。
    // 改成轮询到「真的就绪」为止，最多 40 次 × 50ms = 2 秒。
    if (!ngfSettingsStoreFacade.isReady()) {
      if (this.settingsReloadAttempts < 40) {
        this.settingsReloadAttempts += 1;
        setTimeout((): void => { this.reloadSettings(); }, 50);
      } else {
        logger.warn(TAG, '设置存储迟迟未就绪，本次仍按默认值运行');
      }
      return;
    }
    this.settingsReloadAttempts = 0;
    this.state.settings = this.settingsRepository.load();
    this.state.watchlist = this.settingsRepository.loadWatchlist();
    // 日志等级同样要重新应用：构造期读到的是默认 WARN。
    this.applyLogLevel(this.state.settings.logLevel);
    logger.info(TAG, '设置已重新载入: 后台运行=' + this.state.settings.backgroundScanning.toString()
      + ' 扫描强度=' + this.state.settings.scanIntensity + ' 屏幕常亮=' + this.state.settings.keepScreenOn.toString());
  }

  /** 设置日志等级并落盘。`LogLevel` 的数值直接存，便于以后加档不用改存储格式。 */
  setLogLevel(value: number): void {
    this.state.settings.logLevel = value;
    this.applyLogLevel(value);
    this.settingsRepository.save(this.state.settings);
  }
  getState(): FieldwatchApplicationState { return this.state; }

  /**
   * 把卡片要显示的状态写进设置存储。
   *
   * **方向为什么是「应用写、卡片侧拉」**：`formProvider` 没有「列出本应用全部卡片」
   * 的接口 —— 主应用拿不到自己的 formId，也就无从 `updateForm`。
   * 而 FormExtensionAbility 在 `onAddForm` / `onUpdateForm` 里天然拿得到 formId，
   * 所以反过来：应用只写状态，卡片侧负责取用与刷新。
   *
   * `running` 的口径与要求一致：**允许后台运行 且 应用确实在后台**。
   * 前台时卡片显示「app 未运行」—— 它此刻并没有在后台采集。
   * `heartbeatAt` 供卡片侧判断新鲜度：应用被杀后心跳会停，
   * 卡片据此在超时后自行显示「app 未运行」，而不是永远停在最后一张快照上。
   */
  writeWidgetState(): void {
    const snapshot: FieldwatchWidgetState = new FieldwatchWidgetState();
    snapshot.running = this.state.settings.backgroundScanning && !this.appForeground;
    snapshot.heartbeatAt = Date.now();
    snapshot.paused = this.state.settings.displayPaused;
    this.state.sightings.forEach((item: Sighting): void => {
      if (item.kind === RadioKind.WIFI) snapshot.wifi += 1;
      else if (item.kind === RadioKind.NEARLINK) snapshot.nearLink += 1;
      else snapshot.ble += 1;
    });
    // 大卡片：最近一次命中的关注目标，以及最近一次命中的特征族。
    //
    // **用下标 + 显式 for，不用闭包内赋值** ——
    // ArkTS 的控制流分析看不到回调里的赋值，会把 `let x: T | undefined`
    // 一路窄化成 `never`，随后 `x.rssi` 直接编译失败（实测）。
    const now: number = Date.now();
    const sightings: Sighting[] = this.state.sightings;
    const targets: WatchTarget[] = this.state.watchlist;
    let watchIndex: number = -1;
    let watchLabel: string = '';
    let familyIndex: number = -1;
    for (let i: number = 0; i < sightings.length; i += 1) {
      const item: Sighting = sightings[i];
      for (let t: number = 0; t < targets.length; t += 1) {
        const target: WatchTarget = targets[t];
        if (!target.alert) continue;
        const hit: boolean = target.deviceKey.length > 0
          ? target.deviceKey === item.key
          : (target.signatureId.length > 0 && item.signatureIds.indexOf(target.signatureId) >= 0);
        if (!hit) continue;
        if (watchIndex < 0 || item.lastSeen > sightings[watchIndex].lastSeen) {
          watchIndex = i;
          watchLabel = target.label;
        }
      }
      const names: string[] = matchedSignatureNames(item.signatureIds, this.state.signatures);
      if (names.length > 0 && (familyIndex < 0 || item.lastSeen > sightings[familyIndex].lastSeen)) {
        familyIndex = i;
      }
    }
    if (watchIndex >= 0) {
      snapshot.watchLabel = watchLabel;
      snapshot.watchRssi = sightings[watchIndex].rssi;
      snapshot.watchAgeSec = Math.max(0, Math.round((now - sightings[watchIndex].lastSeen) / 1000));
    }
    if (familyIndex >= 0) {
      const familyNames: string[] = matchedSignatureNames(sightings[familyIndex].signatureIds, this.state.signatures);
      snapshot.familyLabel = familyNames.length > 0 ? familyNames[0] : '';
      snapshot.familyAgeSec = Math.max(0, Math.round((now - sightings[familyIndex].lastSeen) / 1000));
    }
    this.settingsRepository.saveWidgetState(JSON.stringify(snapshot));
    // 状态变了就顺手推一次卡片。
    this.pushWidgetData(snapshot);
  }

  /**
   * 把卡片数据推给扩展登记过的卡片。
   *
   * 主应用**拿不到自己的 formId**（`formProvider` 没有枚举接口），
   * 所以由 FormExtensionAbility 在 `onAddForm` 时反向登记到设置存储里。
   * 没有这条推送，卡片就只能等系统 30 分钟的周期刷新 —— 表现就是「卡片是死的」。
   */
  private pushWidgetData(snapshot: FieldwatchWidgetState): void {
    const forms: FieldwatchWidgetForm[] = parseWidgetForms(this.settingsRepository.loadWidgetForms());
    if (forms.length === 0) return;
    const now: number = Date.now();
    forms.forEach((form: FieldwatchWidgetForm): void => {
      void ngfWidgetManagerFacade.updateWidgetData(form.id, buildWidgetCardData(snapshot, form.dimension, now));
    });
  }

  /**
   * 待处理的目标标签页（快捷方式 / 卡片带进来的 `targetTab`）。
   *
   * **为什么放在应用层而不是页面里**：入口有三个 —— 快捷方式、卡片点击、
   * 以及应用已在运行时的 `onNewWant`。它们拿到的都是 `want.parameters`，
   * 而页面可能还没创建（冷启动）或已经创建（热启动），
   * 所以需要一个「先记下、页面出现时消费」的中间态。
   *
   * -1 表示没有待处理项。
   */
  private pendingTab: number = -1;

  /**
   * 待处理的目标**路由**（不是标签页）。
   *
   * 标签页用 `pendingTab`（下标），但关注列表是**压栈的页面**、不是某个标签页，
   * 两者不能用同一个通道 —— 否则「打开关注列表」会被当成「切到第 N 个标签页」。
   */
  private pendingRoute: string = '';
  /** 待处理的目标工具页（工具箱内部的下标）；-1 表示没有。 */
  private pendingTool: number = -1;

  /** 取走待处理的目标工具页；取走后清空。 */
  consumePendingTool(): number {
    const value: number = this.pendingTool;
    this.pendingTool = -1;
    return value;
  }

  /** 取走待处理的目标路由；取走后清空（只生效一次）。 */
  consumePendingRoute(): string {
    const value: string = this.pendingRoute;
    this.pendingRoute = '';
    return value;
  }

  /** 按名称记下目标标签页；未知名称忽略（不猜）。 */
  requestTab(name: string): void {
    // 卡片点击要直达关注列表页（不是某个标签页），单独走路由通道。
    if (name === 'watchlist') { this.pendingRoute = 'fieldwatch.watchlist'; return; }
    if (name === 'live') this.pendingTab = 0;
    else if (name === 'filters') this.pendingTab = 1;
    else if (name === 'signatures') this.pendingTab = 2;
    else if (name === 'reports') this.pendingTab = 3;
    else if (name === 'toolbox') this.pendingTab = 4;
    // 深链到工具箱里的某一个工具页：
    // 与 `targetTab` 同一条链（快捷方式 / 卡片 / `aa start --ps` 都能用），
    // 这样「打开反追踪」不必先落到工具箱再让用户点一下。
    else if (name === 'toolbox-channel') { this.pendingTab = 4; this.pendingTool = 0; }
    else if (name === 'toolbox-hunt') { this.pendingTab = 4; this.pendingTool = 1; }
    else if (name === 'toolbox-antitrack') { this.pendingTab = 4; this.pendingTool = 2; }
    else if (name === 'settings') this.pendingTab = 5;
  }

  /** 取走待处理的目标标签页；取走后清空（只生效一次）。 */
  consumePendingTab(): number {
    const value: number = this.pendingTab;
    this.pendingTab = -1;
    return value;
  }

  /**
   * 页面侧兜底：构造期若 Ability 上下文尚未就绪，内置目录会加载为空。
   * 这里在页面出现时再试一次，成功前不缓存失败结果。
   */
  async ensureCatalogLoaded(): Promise<void> {
    // 构造期上下文可能尚未就绪，名称库与内置目录都在这里重试一次。
    if (!this.radioDb.isReady()) this.loadRadioDb();
    if (this.state.signatures.length > 0) return;
    await this.loadBundledCatalog();
  }

  /** 内置 stock 目录随应用打包，异步加载后与沙箱用户目录合并，不阻塞首帧。 */
  /**
   * 载入 IEEE / 蓝牙名称库（rawfile 里的 radiodb.bin，与原版同一份数据）。
   * 失败不影响其它功能：筛选的厂商匹配会退化为只匹配 MAC。
   */
  private loadRadioDb(): void {
    try {
      const context = uiContextManager.getFullAbilityContext();
      if (context === null) {
        logger.warn(TAG, '名称库未载入：没有 Ability 上下文');
        return;
      }
      const raw: Uint8Array = context.resourceManager.getRawFileContentSync('lookups/radiodb.bin');
      if (this.radioDb.load(raw)) {
        FieldwatchFilterEngine.setRadioDb(this.radioDb);
        // 自检：用真实数据解析一个已知 OUI，确认索引与名称池都对得上。
        // 厂商名过滤完全依赖这条链路，载入成功但查不出名字时必须能立刻发现。
        logger.info(TAG, '名称库诊断 ' + this.radioDb.describe());
        // 自检覆盖三级，三个 MAC 都取自 bin 里的**真实条目**（已逐条核对）：
        //   MA-L 00:1B:63          -> Apple, Inc.
        //   MA-M 00:55:DA:0        -> Shinko Technos co.,ltd.   （long 段 28 位）
        //   MA-S 00:1B:C5:00:0     -> Converging Systems Inc.   （long 段 36 位）
        // 注意 00:1B:C5 与 00:01:BC 是**两个不同的 OUI**，不要弄混 ——
        // 用 00:01:BC:50:... 测会落到 MA-L 回退（那家是 Brains Corporation），
        // 看似通过实则根本没走到 MA-S。
        // MA-M / MA-S 两级来自 `long` 段 —— 该段此前**从未被读取**，
        // 只测 MA-L 的话「long 没生效」会完全看不出来。
        logger.info(TAG, '名称库自检 MA-L 00:1B:63 -> ' + this.radioDb.vendorForOui24('00:1B:63')
          + ' / MA-M 00:55:DA:00 -> ' + this.radioDb.vendorForOui24('00:55:DA:00:00:01')
          + ' / MA-S 00:1B:C5:00:00 -> ' + this.radioDb.vendorForOui24('00:1B:C5:00:00:00:01')
          + ' / 公司 0x004C -> ' + this.radioDb.company(0x004C));
      }
    } catch (error) {
      logger.warn(TAG, '名称库载入失败: ' + String(error));
    }
  }
  private async loadBundledCatalog(): Promise<void> {
    const stock: SignatureFleet[] = await this.catalogRepository.loadStock();
    if (stock.length === 0) {
      logger.warn(TAG, '内置特征库尚未就绪（可能缺少 Ability 上下文），将在页面出现时重试');
      return;
    }
    const saved: SignatureFleet[] = this.state.signatures;
    const merged: SignatureFleet[] = overlayStockFleets(saved, stock);
    this.state.signatures = merged.length > 0 ? merged : stock;
    this.state.catalogVersion = this.catalogRepository.getStockVersion();
    this.state.catalogStatus = 'builtin';
    logger.info(TAG, '特征库就绪: ' + this.state.signatures.length.toString() + ' 条签名, version=' + this.state.catalogVersion.toString());
  }
  // ── 权限：逐条检查 / 逐条请求 / 能力快照（应用商店合规：无权限也要可用） ──
  /** 当前权限快照，决定 Live 页是正常扫描还是显示受限说明。 */
  permissionSnapshot(): FieldwatchCapabilitySnapshot {
    const snapshot: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
    snapshot.bluetooth = ngfPermissionManagerFacade.checkPermission('ohos.permission.ACCESS_BLUETOOTH');
    snapshot.location = ngfPermissionManagerFacade.checkPermission('ohos.permission.APPROXIMATELY_LOCATION');
    // 星闪：设备不支持时直接视为 false，不参与申请流程。
    snapshot.nearlink = this.nearLinkSupported
      && ngfPermissionManagerFacade.checkPermission('ohos.permission.ACCESS_NEARLINK');
    return snapshot;
  }
  /**
   * 申请单条权限。
   * 一次只申请一条：用户应当能「给蓝牙但不给定位」，批量弹窗会被视为捆绑索取。
   */
  async requestPermission(kind: FieldwatchPermissionKind): Promise<boolean> {
    const spec: FieldwatchPermissionSpec | undefined = this.permissionSpec(kind);
    if (spec === undefined) return false;
    // 一个系统设置项可能覆盖多条底层权限（如「设备发现和连接」同时管蓝牙与星闪）：
    // 把其中尚未授予的逐条补齐，任一未拿到就返回 false。
    const missing: Permissions[] = spec.permissionIds.filter((id: Permissions): boolean =>
      !ngfPermissionManagerFacade.checkPermission(id));
    if (missing.length === 0) return true;
    let allGranted: boolean = true;
    for (let index: number = 0; index < missing.length; index += 1) {
      const granted: boolean = await ngfPermissionManagerFacade.requestPermissions([missing[index]]);
      logger.info(TAG, '权限申请结果 ' + missing[index] + ' = ' + granted.toString());
      if (!granted) allGranted = false;
    }
    return allGranted;
  }
  permissionSpec(kind: FieldwatchPermissionKind): FieldwatchPermissionSpec | undefined {
    return buildPermissionSpecs().find((item: FieldwatchPermissionSpec): boolean => item.kind === kind);
  }
  /**
   * 权限目录。
   *
   * **按硬件能力过滤**：设备不支持星闪时不列出星闪权限 ——
   * 在无此硬件的设备上向用户索要一个用不到的权限，既无意义也违反合规要求。
   */
  permissionCatalog(): FieldwatchPermissionSpec[] {
    // 星闪已并入「设备发现和连接」这一条，不再有需要按能力过滤的独立条目。
    return buildPermissionSpecs();
  }
  /**
   * 申请 BLE 扫描所需的权限（系统设置里的「设备发现和连接」）。
   * 返回是否已获得；**Wi-Fi 不需要任何授权**，因此这里不再涉及 Wi-Fi。
   */
  async requestScanPermissions(): Promise<boolean> {
    if (this.permissionSnapshot().bluetooth) return true;
    await this.requestPermission(FieldwatchPermissionKind.BLUETOOTH);
    return this.permissionSnapshot().bluetooth;
  }
  /**
   * 申请星闪扫描权限（系统设置里的「星闪」）。
   *
   * 与其它权限同一套流程：**由用户主动触发，不自动弹窗**；
   * 设备不支持星闪时直接返回 false，不发起任何申请。
   */
  async requestNearLinkPermission(): Promise<boolean> {
    if (!this.nearLinkSupported) return false;
    if (this.permissionSnapshot().nearlink) return true;
    // 星闪没有独立的系统设置项：它与蓝牙同属「设备发现和连接」，
    // 因此申请走同一条目（内部会把缺失的底层权限逐条补齐）。
    return await this.requestPermission(FieldwatchPermissionKind.BLUETOOTH);
  }
  /**
   * 打开本应用在系统设置里的权限页。
   *
   * **为什么延后一帧**：对话框的按钮回调运行在对话框窗口的关闭过程中，此时同步调用
   * startAbility 会与窗口切换竞争，被系统静默丢弃（无异常、无日志、无反应）。
   * 延后等待对话框完全关闭后再拉起，就能稳定成功。
   *
   * 这个延后**放在 helper 内部**，因此任何调用点（普通按钮、对话框按钮、菜单项）都自动安全，
   * 不需要每个调用方各自记得处理 —— 避免同类问题在别的入口再次出现。
   *
   * @param onFailed 拉起失败时的回调，用于向用户给出可用的替代路径，而不是无声失败。
   */
  openAppPermissionSettings(onFailed: () => void): void {
    setTimeout((): void => {
      const context: common.UIAbilityContext | null = uiContextManager.getFullAbilityContext();
      if (!context) {
        logger.error(TAG, '打开系统设置失败：缺少 UIAbilityContext');
        onFailed();
        return;
      }
      try {
        context.startAbility({
          bundleName: 'com.huawei.hmos.settings',
          abilityName: 'com.huawei.hmos.settings.MainAbility',
          uri: 'application_info_entry',
          parameters: { pushParams: context.applicationInfo.name }
        }).then((): void => {
          logger.info(TAG, '系统设置已拉起');
        }).catch((error: BusinessError): void => {
          logger.error(TAG, '打开系统设置失败: code=' + error.code + ' msg=' + error.message);
          onFailed();
        });
      } catch (error) {
        logger.error(TAG, '打开系统设置异常: ' + (error as Error).message);
        onFailed();
      }
    }, 150);
  }  /** 首次启动引导是否已完成。 */
  onboardingSeen(): boolean { return this.settingsRepository.loadOnboardingSeen(); }
  markOnboardingSeen(): void { this.settingsRepository.saveOnboardingSeen(true); }
  /** 用户选择「先用基础功能」后不再自动弹权限说明。 */
  permissionPromptDismissed(): boolean { return this.settingsRepository.loadPermissionPromptDismissed(); }
  markPermissionPromptDismissed(): void { this.settingsRepository.savePermissionPromptDismissed(true); }

  startBleScan(): void {
    this.startScan();
  }

  startScan(): void {
    this.state.errorMessage = '';
    void this.restoreRecentObservations();
    // 状态通知**不在这里启动**。
    //
    // 它此前在这里启动、却**从来没有停止过** —— `stopStateNotification()` 是死代码，
    // 于是定时器自扫描开始就永久运行，与前台/后台无关，也与「有没有后台长时任务」无关。
    // 通知的用途是伴随后台长时任务（鸿蒙要求长时任务必须有用户可见通知），
    // 因此正确的位置是 `onAbilityBackground` 里随任务一起起停。
    // 启动时就按设置同步后台长时任务，而不是等用户切到后台才启动。
    void this.syncBackgroundTask();
    this.radioScanner.start((observation: ScanObservation): void => { this.ingest(observation); }, (message: string, kind: RadioKind): void => {
      if (kind === RadioKind.BLE && this.state.errorMessage.length === 0) {
        this.state.errorMessage = message;
      }
    }, (snapshot: RadioSourceSnapshot): void => {
      // **只在相位变化时输出**：BLE 每收到一条观测就发一次快照（实测 17 次/秒），
      // 逐条打 info 会在几秒内把日志环形缓冲冲干净 —— Wi-Fi 与星闪的启动行
      // 因此被挤掉，排查时看起来像「那两个无线电没启动」，实际只是日志被淹了。
      // 相位不变时的重复快照对排查没有信息量，不打。
      this.logRadioPhase(snapshot);
      // 三种无线电种类各自归档；此前星闪会落进 BLE 分支，导致 BLE 状态被星闪覆盖。
      if (snapshot.kind === RadioKind.WIFI) this.state.wifiSnapshot = snapshot;
      else if (snapshot.kind === RadioKind.NEARLINK) this.state.nearLinkSnapshot = snapshot;
      else this.state.bleSnapshot = snapshot;
    });
    this.state.wifiSnapshot = this.radioScanner.getSnapshot(RadioKind.WIFI);
    this.state.bleSnapshot = this.radioScanner.getSnapshot(RadioKind.BLE);
    this.state.nearLinkSnapshot = this.radioScanner.getSnapshot(RadioKind.NEARLINK);
    this.state.scanState = this.radioScanner.state === ScanState.IDLE ? ScanState.ERROR : this.radioScanner.state;
  }
  retryWifiScan(): void {
    this.radioScanner.retry(RadioKind.WIFI);
    this.state.wifiSnapshot = this.radioScanner.getSnapshot(RadioKind.WIFI);
  }
  /** 重试星闪扫描；设备不支持时什么都不做。 */
  retryNearLinkScan(): void {
    if (!this.nearLinkSupported) return;
    this.radioScanner.retry(RadioKind.NEARLINK);
    this.state.nearLinkSnapshot = this.radioScanner.getSnapshot(RadioKind.NEARLINK);
  }
  async startSit(name: string): Promise<boolean> {
    if (name.trim().length === 0 || this.state.activeSit !== undefined) return false;
    const summary: SitSummary = new SitSummary('sit-' + Date.now().toString(), name.trim(), Date.now());
    const saved: boolean = await this.observationRepository.saveSit(summary);
    if (saved) this.state.activeSit = summary;
    logger.info(TAG, '开始 sit: id=' + summary.id + ', startedAt=' + summary.startedAt.toString() + ', saved=' + saved.toString());
    return saved;
  }
  async finishSit(): Promise<boolean> {
    const active: SitSummary | undefined = this.state.activeSit;
    if (active === undefined) return false;
    active.endedAt = Date.now();
    await this.observationRepository.flush();
    const storedKeys: Array<string> = await this.observationRepository.loadObservationKeysBetween(active.startedAt, active.endedAt);
    const memoryKeys: Array<string> = this.state.sightings.map((sighting: Sighting): string => sighting.key);
    const mergedKeys: Set<string> = new Set<string>(storedKeys);
    memoryKeys.forEach((key: string): void => { if (key.length > 0) mergedKeys.add(key); });
    active.deviceKeys = Array.from(mergedKeys);
    active.radioCount = active.deviceKeys.length;
    logger.info(TAG, '结束 sit: id=' + active.id + ', startedAt=' + active.startedAt.toString() + ', endedAt=' + active.endedAt.toString() + ', storedKeys=' + storedKeys.length.toString() + ', memoryKeys=' + memoryKeys.length.toString() + ', mergedKeys=' + active.radioCount.toString());
    const saved: boolean = await this.observationRepository.saveSit(active, active.deviceKeys);
    if (saved) {
      this.state.savedSits = await this.observationRepository.loadSits();
      this.state.activeSit = undefined;
    }
    return saved;
  }
  async loadSavedSits(): Promise<SitSummary[]> {
    const sits: SitSummary[] = await this.observationRepository.loadSits();
    this.state.savedSits = sits;
    return sits;
  }
  async deleteSit(id: string): Promise<boolean> {
    const deleted: boolean = await this.observationRepository.deleteSit(id);
    if (deleted) this.state.savedSits = this.state.savedSits.filter((item: SitSummary): boolean => item.id !== id);
    return deleted;
  }
  async updateCatalog(): Promise<boolean> {
    this.state.catalogStatus = 'updating';
    const result: StockCatalogUpdateResult = await this.catalogRepository.updateStockCatalog(this.state.signatures);
    if (result.error !== SignaturePackError.NONE) {
      this.state.catalogStatus = 'failed';
      return false;
    }
    this.state.signatures = this.catalogRepository.loadSaved();
    this.state.catalogVersion = result.catalogVersion;
    this.state.catalogStatus = 'updated';
    return true;
  }

  /** 从用户选择的签名包文本导入；失败时目录保持不变。 */
  importCatalogPack(text: string): FieldwatchCatalogImportOutcome {
    const outcome: FieldwatchCatalogImportOutcome = this.catalogRepository.importPack(this.state.signatures, text);
    if (outcome.result.error === SignaturePackError.NONE) this.state.signatures = outcome.fleets;
    return outcome;
  }

  /** 导出完整目录到用户选择的位置（系统文件选择器）。 */
  async exportCatalogToUserFile(): Promise<boolean> {
    return await this.catalogFileGateway.saveToFile('fieldwatch-signatures.json', this.catalogRepository.exportText(this.state.signatures));
  }

  /** 直接写入系统下载目录（不弹选择器）。 */
  async exportCatalogToDownloads(): Promise<boolean> {
    return await this.catalogFileGateway.saveToDownloads('fieldwatch-signatures.json', this.catalogRepository.exportText(this.state.signatures));
  }
  /** 从用户选择的签名包导入；取消或失败时目录保持不变。 */
  async importCatalogFromUserFile(): Promise<FieldwatchCatalogImportOutcome | undefined> {
    const content: string = await this.catalogFileGateway.pickAndRead();
    if (content.length === 0) return undefined;
    return this.importCatalogPack(content);
  }

  /** 只分享目录摘要，不把 2 MB 目录文本塞进分享面板。 */
  shareCatalogSummary(): void {
    const text: string = 'Fieldwatch signatures\n' + 'version: ' + this.state.catalogVersion.toString() + '\n' + 'signatures: ' + this.state.signatures.length.toString() + '\n';
    ngfSystemShareFacade.shareText(text);
  }

  async restoreDefaultCatalog(): Promise<boolean> {
    const restored: SignatureFleet[] = await this.catalogRepository.restoreDefaults();
    if (restored.length === 0) return false;
    this.state.signatures = restored;
    this.state.catalogVersion = this.catalogRepository.getStockVersion();
    this.state.catalogStatus = 'builtin';
    return true;
  }

  setFleetEnabled(fleetId: string, enabled: boolean): boolean {
    const fleet: SignatureFleet | undefined = this.state.signatures.find((item: SignatureFleet): boolean => item.id === fleetId);
    if (fleet === undefined) return false;
    fleet.enabled = enabled;
    return this.catalogRepository.save(this.state.signatures);
  }

  /**
   * 删除一条特征（用户特征与内置特征都能删）。
   *
   * 两条路径**故意不同**：
   *   - 用户特征：直接从目录里移除；
   *   - 内置特征：来自只读 rawfile 包，删不掉，改为留一条**墓碑**
   *     （`deleted = true` + `enabled = false`）。行还在，所以启动时的 stock 覆盖
   *     不会把它加回来；列表与匹配都跳过它。
   *
   * 「恢复默认目录」会重建整个目录，墓碑随之清除 —— 这就是撤销路径。
   */
  removeFleet(fleetId: string): boolean {
    const fleet: SignatureFleet | undefined = this.state.signatures.find((item: SignatureFleet): boolean => item.id === fleetId);
    if (fleet === undefined) return false;
    if (fleet.builtIn) {
      fleet.deleted = true;
      // 同时停用：匹配引擎按 enabled 过滤，墓碑绝不能继续命中。
      fleet.enabled = false;
    } else {
      this.state.signatures = this.state.signatures.filter((item: SignatureFleet): boolean => item.id !== fleetId);
    }
    return this.catalogRepository.save(this.state.signatures);
  }
  /** 目录里实际可见的特征（跳过墓碑）。列表、计数与统计都应走它。 */
  visibleSignatures(): SignatureFleet[] {
    return this.state.signatures.filter((item: SignatureFleet): boolean => !item.deleted);
  }

  /**
   * 保存一条特征（新建或编辑，内置特征也走这里）。
   *
   * **字段清单必须与编辑器的可编辑项一一对应。** 此前这里漏拷了
   * `clusterByOui` / `sequentialMac` / `minPeers` / `peerWindowSec` ——
   * 编辑器里改这四项、点保存、界面回到「匹配」段看着像是记住了，
   * 实际写库时被丢掉，重启即还原。
   *
   * 内置行额外打 `userEdited`：启动时的 stock 覆盖逻辑据此整行让位给本地值，
   * 否则用户对内置特征的修改会在下次启动被静默覆盖。
   */
  saveUserFleet(fleet: SignatureFleet): boolean {
    const existing: SignatureFleet | undefined = this.state.signatures.find((item: SignatureFleet): boolean => item.id === fleet.id);
    if (existing === undefined) this.state.signatures.push(fleet);
    else {
      existing.name = fleet.name;
      existing.category = fleet.category;
      existing.enabled = fleet.enabled;
      existing.matchAny = fleet.matchAny;
      existing.colorIndex = fleet.colorIndex;
      existing.clusterByOui = fleet.clusterByOui;
      existing.sequentialMac = fleet.sequentialMac;
      existing.minPeers = fleet.minPeers;
      existing.peerWindowSec = fleet.peerWindowSec;
      existing.notes = fleet.notes;
      existing.attentionNote = fleet.attentionNote;
      existing.rules = fleet.rules;
      existing.decode = fleet.decode;
      if (existing.builtIn) existing.userEdited = true;
      // 编辑一条被删除过的内置行等于把它找回来。
      existing.deleted = false;
    }
    return this.catalogRepository.save(this.state.signatures);
  }

  /** 开始一次单目标搜寻；同一时间只允许一个 Hunt 会话。 */
  startHunt(sighting: Sighting): void {
    const session: HuntSession = new HuntSession(sighting.key, this.privacyService.displayName(sighting, this.state.settings.privacyMode), Date.now());
    sighting.rssiSamples.forEach((value: number): void => { session.addSample(value, sighting.lastSeen); });
    session.lastRssi = sighting.rssi;
    session.lastSeen = sighting.lastSeen;
    this.huntSession = session;
    logger.info(TAG, '开始搜寻: key=' + sighting.key + ', 历史样本=' + sighting.rssiSamples.length.toString());
  }

  stopHunt(): void {
    const session: HuntSession | undefined = this.huntSession;
    if (session !== undefined) {
      logger.info(TAG, '停止搜寻: key=' + session.targetKey);
      // **先固化再丢弃**：`HuntSession` 一置空，历史就没了，
      // 而工具箱的「信号追踪」面板要展示历史。
      const record: HuntRecord = new HuntRecord();
      record.targetKey = session.targetKey;
      record.label = session.label;
      record.startedAt = session.startedAt;
      record.endedAt = Date.now();
      record.peak = session.peak();
      record.samples = session.samples.length;
      record.average = session.average();
      this.huntHistory.unshift(record);
      if (this.huntHistory.length > FieldwatchApplication.HUNT_HISTORY_MAX) this.huntHistory.pop();
    }
    this.huntSession = undefined;
  }

  /** 已结束的搜寻记录，最新的在前。 */
  getHuntHistory(): HuntRecord[] { return this.huntHistory.slice(); }

  /** 搜寻历史汇总。 */
  huntStats(): HuntStats {
    const stats: HuntStats = new HuntStats();
    stats.sessions = this.huntHistory.length;
    this.huntHistory.forEach((record: HuntRecord): void => {
      stats.totalMs += record.durationMs();
      if (record.peak > stats.bestPeak) { stats.bestPeak = record.peak; stats.bestLabel = record.label; }
    });
    return stats;
  }

  getHunt(): HuntSession | undefined { return this.huntSession; }

  /** 当前提示状态；目标已离开实时集合时标记为 missing。 */
  huntCueNow(): HuntCue {
    const session: HuntSession | undefined = this.huntSession;
    if (session === undefined) return HuntCue.GONE;
    session.missing = !this.state.sightings.some((item: Sighting): boolean => item.key === session.targetKey);
    return session.cue(Date.now());
  }

  /** 单设备的签名命中解释，用于详情页展示“为什么命中”。 */
  explainSighting(sighting: Sighting): SignatureMatchExplanation[] {
    return this.fleetEngine.explain(signatureContextOfSighting(sighting), this.state.signatures);
  }

  /** 某个签名当前命中的设备数，用于目录页展示实际效果。 */
  countMatches(fleetId: string): number {
    return this.state.sightings.filter((item: Sighting): boolean => item.signatureIds.indexOf(fleetId) >= 0).length;
  }

  /** 从一台已观测设备反推一条用户签名；结果不落库，由编辑器确认后保存。 */
  createFleetFromSighting(sighting: Sighting): SignatureFleet {
    return this.fleetEngine.suggestFleet(signatureContextOfSighting(sighting));
  }
  async clearObservationLog(): Promise<boolean> {
    const cleared: boolean = await this.observationRepository.clearObservations();
    if (cleared) {
      this.state.logs = [];
      this.state.sightings = [];
    }
    return cleared;
  }
  // ── 实时雷达显示设置：保存即生效，Live 页每秒同步一次，无需重启 ──
  setRadarLabelFields(fields: string): void {
    this.state.settings.radarLabelFields = fields;
    this.settingsRepository.save(this.state.settings);
  }
  setRadarLabelFontSize(size: number): void {
    this.state.settings.radarLabelFontSize = Math.max(9, Math.min(20, Math.round(size)));
    this.settingsRepository.save(this.state.settings);
  }
  setRadarIconSize(size: number): void {
    this.state.settings.radarIconSize = Math.max(16, Math.min(44, Math.round(size)));
    this.settingsRepository.save(this.state.settings);
  }
  /**
   * 星闪能力探测（落地第 1 步）。
   *
   * 星闪有硬件门槛（错误码 801 = 芯片不支持），必须先探测再决定：
   *   - 不支持 → 完全不显示星闪 UI，也不申请 ACCESS_NEARLINK 权限；
   *   - 支持   → 才进入权限申请与扫描器接入流程。
   *
   * 这里只做探测与记录，不申请权限、不启动扫描。
   */
  probeNearLinkCapability(): void {
    // 探测结果会影响协调器构成，因此探测后重建一次（幂等，且此时尚未开始扫描）。
    try {
      const supported: boolean = nearlinkManager.isNearLinkSupported();
      logger.info(TAG, '星闪能力探测：isNearLinkSupported=' + supported.toString());
      if (!supported) {
        this.nearLinkSupported = false;
        return;
      }
      const state: nearlinkManager.NearlinkState = nearlinkManager.getState();
      logger.info(TAG, '星闪开关状态=' + JSON.stringify(state));
      this.nearLinkSupported = true;
      // 探测通过后重建协调器，把星闪扫描器纳入。
      // 只在「尚未开始扫描」时重建，避免打断正在进行的扫描。
      if (this.state.scanState !== ScanState.SCANNING) this.radioScanner = this.buildCoordinator();
      // 本机名称需要 ACCESS_NEARLINK，未授权时会抛错，属于预期，不阻断探测。
      if (ngfPermissionManagerFacade.checkPermission('ohos.permission.ACCESS_NEARLINK')) {
        logger.info(TAG, '本机星闪名称=' + nearlinkManager.getLocalName());
      } else {
        logger.info(TAG, '星闪名称未读取：ACCESS_NEARLINK 尚未授权');
      }
    } catch (error) {
      // 801 = 芯片不支持；其它错误同样按「不可用」处理，绝不因此崩溃。
      const code: number = (error as BusinessError).code;
      logger.warn(TAG, '星闪能力探测失败: code=' + code + ' msg=' + (error as BusinessError).message);
      this.nearLinkSupported = false;
    }
  }
  /** 本机是否支持星闪（探测结果，供 UI 决定是否显示星闪相关入口）。 */
  nearLinkAvailable(): boolean { return this.nearLinkSupported; }
  setScanIntensity(intensity: string): void {
    if (intensity !== 'basic' && intensity !== 'balanced' && intensity !== 'saver') return;
    this.state.settings.scanIntensity = intensity;
    this.settingsRepository.save(this.state.settings);
    const wasScanning: boolean = this.state.scanState === ScanState.SCANNING;
    this.radioScanner.stop();
    this.radioScanner = this.buildCoordinator();
    this.state.scanState = ScanState.IDLE;
    if (wasScanning) this.startScan();
  }
  setFilter(filter: FilterDefinition): void { this.state.filter = filter; }
  clearFilter(): void { this.state.filter = new FilterDefinition(); }
  setRadioFilter(kind: RadioKind | undefined): void { this.state.filter.radioKind = kind; }
  setMinimumRssiFilter(value: number | undefined): void { this.state.filter.minimumRssi = value; }
  setFilterLogic(logic: FilterLogic): void { this.state.filter.logic = logic; this.commitFilter(); }
  setSignatureClassFilter(category: SignatureClass | undefined): void { this.state.filter.signatureClass = category; }
  setSignatureFilter(signatureId: string): void { this.state.filter.signatureId = signatureId; }
  setWatchedOnlyFilter(enabled: boolean): void { this.state.filter.watchedOnly = enabled; this.commitFilter(); }
  /** 仅新发现：与 cachedOnly 互斥，单独提供入口。 */
  setFreshOnlyFilter(enabled: boolean): void {
    this.state.filter.freshOnly = enabled;
    if (enabled) this.state.filter.cachedOnly = false;
    this.commitFilter();
  }
  setAttentionOnlyFilter(enabled: boolean): void { this.state.filter.attentionOnly = enabled; }
  setFreshFilter(freshOnly: boolean, cachedOnly: boolean): void { this.state.filter.freshOnly = freshOnly; this.state.filter.cachedOnly = cachedOnly; }
  setMatchedOnlyFilter(enabled: boolean): void { this.state.filter.namedOnly = enabled; }
  setDecodedOnlyFilter(enabled: boolean): void { this.state.filter.decodedOnly = enabled; this.commitFilter(); }
  setLocatedOnlyFilter(enabled: boolean): void { this.state.filter.locatedOnly = enabled; this.commitFilter(); }
  setNamedOnlyFilter(enabled: boolean): void { this.state.filter.namedOnly = enabled; this.commitFilter(); }

  /**
   * 内置 6 个预设 + 用户自定义预设。
   * 同名时以用户保存的为准（用户改过内置预设后应保留自己的版本）。
   */
  listFilterPresets(): FilterPreset[] {
    const merged: FilterPreset[] = this.filterEngine.defaultPresets();
    this.settingsRepository.listFilterPresets().forEach((saved: FilterPreset): void => {
      const index: number = merged.findIndex((item: FilterPreset): boolean => item.name === saved.name);
      if (index >= 0) merged[index] = saved; else merged.push(saved);
    });
    return merged;
  }
  /** 用户自定义命名过的信号源 key 集合（对应原版 namedRadioKeys）。 */
  namedRadioKeys(): string[] {
    const keys: string[] = [];
    this.state.watchlist.forEach((target: WatchTarget): void => {
      if (target.deviceKey.length > 0 && target.label.length > 0) keys.push(target.deviceKey);
    });
    this.state.sightings.forEach((item: Sighting): void => {
      if (item.name.length > 0 && keys.indexOf(item.key) < 0) keys.push(item.key);
    });
    return keys;
  }
  // ── 筛选页写入通道：每个入口都持久化，保证重启后筛选仍然生效 ──
  private commitFilter(): void { this.settingsRepository.saveFilterState(this.state.filter); }
  setRadioSwitches(wifi: boolean, ble: boolean): void {
    const filter: FilterDefinition = this.state.filter;
    filter.showWifi = wifi;
    filter.showBle = ble;
    filter.radioKind = undefined;
    this.commitFilter();
  }
  /**
   * 按无线电种类单选。
   *
   * 传入 `RadioKind` 时把三种开关收敛到该种类；传入 `undefined` 表示全部显示。
   * 星闪必须与 BLE 分开处理，否则「仅 BLE」会把星闪一起放行。
   */
  setRadioKind(kind: RadioKind | undefined): void {
    const filter: FilterDefinition = this.state.filter;
    filter.radioKind = kind;
    filter.showWifi = kind === undefined || kind === RadioKind.WIFI;
    filter.showBle = kind === undefined || kind === RadioKind.BLE;
    filter.showNearLink = kind === undefined || kind === RadioKind.NEARLINK;
    this.commitFilter();
  }
  setMovingWithYouFilter(enabled: boolean): void { this.state.filter.movingWithYou = enabled; this.commitFilter(); }
  setCustomNamesOnlyFilter(enabled: boolean): void { this.state.filter.customNamesOnly = enabled; this.commitFilter(); }
  setHideFastPairFilter(enabled: boolean): void { this.state.filter.hideFastPairAccountKey = enabled; this.commitFilter(); }
  /** 点按类别芯片：在集合里增删，并自动进入「仅显示」模式。 */
  toggleFilterClass(cls: SignatureClass): void {
    const filter: FilterDefinition = this.state.filter;
    const index: number = filter.classes.indexOf(cls);
    if (index >= 0) filter.classes.splice(index, 1); else filter.classes.push(cls);
    filter.useClassFilter = true;
    this.commitFilter();
  }
  setClassFilterMode(exclude: boolean): void {
    this.state.filter.useClassFilter = true;
    this.state.filter.excludeClasses = exclude;
    this.commitFilter();
  }
  setIncludeSignaturesFilter(enabled: boolean): void { this.state.filter.includeSignatures = enabled; this.commitFilter(); }
  setExcludeSignaturesFilter(enabled: boolean): void { this.state.filter.excludeSignatures = enabled; this.commitFilter(); }
  setRssiMinFilter(value: number): void { this.state.filter.rssiMin = value; this.commitFilter(); }
  setNameQueryFilter(value: string): void { this.state.filter.nameQuery = value; this.commitFilter(); }
  setOuiQueryFilter(value: string): void { this.state.filter.ouiQuery = value; this.commitFilter(); }
  resetFilter(): void { this.state.filter = new FilterDefinition(); this.commitFilter(); }
  applyFilterPresetByName(name: string): boolean {
    const preset: FilterDefinition | undefined = this.settingsRepository.loadFilterPreset(name);
    if (preset === undefined) return false;
    this.state.filter = preset;
    this.commitFilter();
    return true;
  }
  /** 「与你同行」分区里的 GPS 轨迹状态行。 */
  travelStatusText(): string {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return '';
    const template: string = resolveResourceString(context, $r('app.string.fieldwatch_filter_travel_status'));
    const meters: number = Math.round(this.geoService.pathLengthMeters(this.travelSamples));
    return template.replace('%s', meters.toString());
  }

  deleteFilterPresetNamed(name: string): void { this.settingsRepository.deleteFilterPreset(name); }
  hasFilterPreset(name: string): boolean { return this.settingsRepository.hasFilterPreset(name); }
  applyDefaultPreset(): FilterDefinition {
    const preset: FilterDefinition = this.settingsRepository.loadDefaultPreset();
    this.state.filter = preset;
    return preset;
  }

  /** 内置关注项：Extra attention 签名与无人机类签名；已存在的跳过。 */
  seedBuiltInWatchTargets(): number {
    let added: number = 0;
    this.state.signatures.forEach((fleet: SignatureFleet): void => {
      const wanted: boolean = fleet.attentionNote.length > 0 || foldedSignatureClass(fleet.category) === SignatureClass.DRONE;
      if (!wanted) return;
      if (this.state.watchlist.some((target: WatchTarget): boolean => target.signatureId === fleet.id)) return;
      this.state.watchlist.push(new WatchTarget('', fleet.id, fleet.name, true, fleet.attentionNote));
      added += 1;
    });
    if (added > 0) this.settingsRepository.saveWatchlist(this.state.watchlist);
    logger.info(TAG, '内置关注项已添加: ' + added.toString());
    return added;
  }

  getWatchlist(): WatchTarget[] { return this.state.watchlist; }

  /** 用户自身的位置轨迹，转成领域层的 GeoPoint。 */
  private travelPoints(): GeoPoint[] {
    return this.travelSamples.map((sample: GpsSample): GeoPoint =>
      new GeoPoint(sample.at, sample.latitude, sample.longitude));
  }

  /**
   * 反追踪评估结果，按分数降序。
   *
   * **只读**，不产生任何副作用（通知走 `scanAntiTracking`）——
   * 页面每 2 秒调一次，让一个 getter 发通知会变成刷屏。
   */
  antiTrackingReport(): TrackSuspect[] {
    const now: number = Date.now();
    const travel: GeoPoint[] = this.travelPoints();
    const result: TrackSuspect[] = [];
    this.state.sightings.forEach((item: Sighting): void => {
      const samples: TrackPoint[] | undefined = this.deviceTracks.get(item.key);
      if (samples === undefined) return;
      const evidence: TrackEvidence = assessTrack(samples, travel, now);
      const risk: FollowRisk = riskOf(evidence.score);
      if (risk === FollowRisk.NONE) return;
      const suspect: TrackSuspect = new TrackSuspect();
      suspect.key = item.key;
      suspect.label = item.name.length > 0 ? item.name : item.key;
      suspect.risk = risk;
      suspect.evidence = evidence;
      result.push(suspect);
    });
    return result.sort((a: TrackSuspect, b: TrackSuspect): number => b.evidence.score - a.evidence.score);
  }

  /** 用户的位置轨迹是否可用；不可用时地理维度恒为 0，界面必须说明。 */
  antiTrackingHasGeo(): boolean { return this.travelSamples.length >= 2; }

  /**
   * **全部**参与评估的设备（含分数低于阈值的）。
   *
   * 面板要回答「为什么这台没报」，所以不能只给超过阈值的那些 ——
   * 那会让用户以为算法根本没在看它们。
   */
  antiTrackingAll(): TrackSuspect[] {
    const now: number = Date.now();
    const travel: GeoPoint[] = this.travelPoints();
    const result: TrackSuspect[] = [];
    this.state.sightings.forEach((item: Sighting): void => {
      const samples: TrackPoint[] | undefined = this.deviceTracks.get(item.key);
      if (samples === undefined) return;
      const evidence: TrackEvidence = assessTrack(samples, travel, now);
      // 样本不足的（score 0 且样本数不够）不列出来，否则列表会被刚出现的设备淹没。
      if (evidence.sampleCount < TRACK_MIN_SAMPLES) return;
      const suspect: TrackSuspect = new TrackSuspect();
      suspect.key = item.key;
      suspect.label = item.name.length > 0 ? item.name : item.key;
      suspect.risk = riskOf(evidence.score);
      suspect.evidence = evidence;
      result.push(suspect);
    });
    return result.sort((a: TrackSuspect, b: TrackSuspect): number => b.evidence.score - a.evidence.score);
  }

  /** 反追踪面板的汇总计数。 */
  antiTrackStats(): AntiTrackStats {
    const stats: AntiTrackStats = new AntiTrackStats();
    const all: TrackSuspect[] = this.antiTrackingAll();
    stats.evaluated = all.length;
    all.forEach((suspect: TrackSuspect): void => {
      if (suspect.risk === FollowRisk.SUSPECT) stats.suspect += 1;
      else if (suspect.risk === FollowRisk.WATCH) stats.watch += 1;
    });
    if (all.length > 0) { stats.topScore = all[0].evidence.score; stats.topLabel = all[0].label; }
    return stats;
  }

  /** 判定记录，最新的在前。 */
  antiTrackEvents(): AntiTrackEvent[] { return this.antiTrackLog.slice(); }

  /** 我自己的移动摘要（面板的「我的移动」块）。 */
  travelSummary(): TravelSummary { return travelSummaryOf(this.travelPoints()); }

  /**
   * 周期性评估，并对**新出现**的疑似跟踪设备推一条通知。
   *
   * 每台设备每次运行只推一次：这条告警是「有个东西一直跟着你」，
   * 反复推会把真正重要的那一次淹没。
   */
  scanAntiTracking(): void {
    const suspects: TrackSuspect[] = this.antiTrackingReport();
    suspects.forEach((suspect: TrackSuspect): void => {
      if (suspect.risk !== FollowRisk.SUSPECT) return;
      if (this.antiTrackAlerted.has(suspect.key)) return;
      this.antiTrackAlerted.add(suspect.key);
      // 先落记录：通知可能因为权限没发出去，但「什么时候判定过什么」必须留下。
      const event: AntiTrackEvent = new AntiTrackEvent();
      event.at = Date.now();
      event.key = suspect.key;
      event.label = suspect.label;
      event.score = suspect.evidence.score;
      event.risk = suspect.risk;
      this.antiTrackLog.unshift(event);
      if (this.antiTrackLog.length > FieldwatchApplication.ANTITRACK_LOG_MAX) this.antiTrackLog.pop();
      const context = uiContextManager.getFullAbilityContext();
      if (context === null) return;
      const title: string = resolveResourceString(context, $r('app.string.fieldwatch_antitrack_notify_title'));
      const template: string = resolveResourceString(context, $r('app.string.fieldwatch_antitrack_notify_body'));
      const body: string = template.replace('%1', suspect.label)
        .replace('%2', formatMinutes(suspect.evidence.spanMs));
      const notificationId: number = this.nextNotificationId;
      this.nextNotificationId += 1;
      void ngfSystemNotificationManager.publish(
        new NGFNotificationRequest(notificationId, title, body, NGFNotificationType.BASIC));
      logger.warn(TAG, '疑似跟踪设备: ' + suspect.label + ' 分数=' + suspect.evidence.score.toString());
    });
  }

  removeWatchTarget(index: number): void {
    if (index < 0 || index >= this.state.watchlist.length) return;
    this.state.watchlist = this.state.watchlist.filter((target: WatchTarget, position: number): boolean => position !== index);
    this.settingsRepository.saveWatchlist(this.state.watchlist);
  }
  /** 保存当前过滤条件为具名预设；同名覆盖。 */
  saveFilterPresetNamed(name: string): boolean {
    const saved: boolean = this.settingsRepository.saveFilterPreset(name, this.state.filter);
    if (saved) logger.info(TAG, '筛选预设已保存: ' + name);
    return saved;
  }

  applyFilterPreset(name: string): FilterDefinition | undefined {
    const preset: FilterDefinition | undefined = this.settingsRepository.loadFilterPreset(name);
    if (preset === undefined) return undefined;
    this.state.filter = preset;
    return preset;
  }
  updateLiveMode(mode: string): void { this.state.settings.liveMode = mode; this.settingsRepository.save(this.state.settings); }
  stopBleScan(): void { this.stopScan(); }
  stopScan(): void { this.radioScanner.stop(); this.state.scanState = ScanState.IDLE; logger.info(TAG, '无线电扫描已停止'); }
  setDisplayPaused(paused: boolean): void { this.state.settings.displayPaused = paused; this.settingsRepository.save(this.state.settings); this.state.scanState = paused ? ScanState.PAUSED : ScanState.SCANNING; }
  setPrivacyMode(enabled: boolean): void { this.state.settings.privacyMode = enabled; this.settingsRepository.save(this.state.settings); }
  setLocationTagging(enabled: boolean): void { this.state.settings.locationTagging = enabled; this.settingsRepository.save(this.state.settings); }
  async setKeepScreenOn(enabled: boolean): Promise<void> { await ngfScreenKeepAwakeFacade.setEnabled(enabled); this.state.settings.keepScreenOn = enabled; this.settingsRepository.save(this.state.settings); }
  async setWatchNotifications(enabled: boolean): Promise<boolean> {
    if (enabled) {
      const granted: boolean = await ngfSystemNotificationManager.requestPermission();
      if (!granted) return false;
    }
    if (!enabled) {
      const ids: Array<number> = Array.from(this.watchedNotificationIds.values());
      for (let index: number = 0; index < ids.length; index += 1) await ngfSystemNotificationManager.cancel(ids[index]);
      this.watchedNotificationIds.clear();
    }
    this.state.settings.watchNotifications = enabled;
    this.settingsRepository.save(this.state.settings);
    return true;
  }
  async setBackgroundScanning(enabled: boolean): Promise<boolean> {
    if (enabled) {
      // 走 `syncBackgroundTask`：它与前台路径共用同一份文案与同一条启动逻辑。
      // 此前这里自己拼了一套硬编码标题（`'Fieldwatch'` / taskReason），
      // 于是「前台持有的通知」与「这里启动的通知」文案不一致。
      await this.syncBackgroundTask();
    } else {
      await ngfBackgroundTaskManager.stopContinuousTask();
      // 通知定时器必须一起停：此前只停了任务，定时器仍在每 15 秒发一次通知，
      // 于是「关掉后台运行」之后通知栏里反而一直有东西。
      this.stopStateNotification();
    }
    this.state.settings.backgroundScanning = enabled;
    this.settingsRepository.save(this.state.settings);
    // 允许/取消后台运行会直接改变卡片要显示的「是否在运行」，必须立刻同步。
    this.writeWidgetState();
    return true;
  }
  /**
   * 启动「运行状态」常驻通知。
   *
   * 应用启动后立刻发一条，并**持续刷新**当前运行情况（各类信号源计数、扫描相位）。
   * 这是鸿蒙对长时任务的官方要求：用户必须能随时看到应用正在后台做什么；
   * 同时它也让「应用到底还在不在跑」这件事变得可见，而不是只能靠猜。
   *
   * 固定 ID + 覆盖更新，因此反复调用不会堆通知。
   */
  private startStateNotification(): void {
    if (this.stateNotificationTimer >= 0) return;
    // 通知权限可能尚未授予（引导页会引导用户开启）。未开启时不去发布，
    // 否则平台每次都会抛「Notification disabled」，3 秒一条错误日志毫无意义。
    void ngfSystemNotificationManager.isEnabled().then((enabled: boolean): void => {
      this.notificationsEnabled = enabled;
      if (!enabled) {
        logger.info(TAG, '通知未启用，运行状态通知暂不发布（可在引导或设置中开启）');
        return;
      }
      this.publishStateNotification();
      if (this.stateNotificationTimer < 0) {
        // 15 秒一次，不是 3 秒。
        //
        // `publishStateNotification` 每次都要：取上下文、解析两个字符串资源（IPC）、
        // 遍历全部信号源计数、再发布一次通知（通知服务 IPC，跨进程）。
        // 3 秒一次等于把这两次 IPC 变成常态负载；线程剖析显示主 JS 线程占用显著，
        // 基线对照归因给本应用的后台耗电约 8.9%/小时。
        // 通知里的计数是给人看的，15 秒的粒度足够，也更少打扰用户。
        this.stateNotificationTimer = setInterval((): void => {
          this.publishStateNotification();
          // 心跳与计数一起走这条 15 秒的定时器：卡片侧据此判断应用是否还在运行。
          this.writeWidgetState();
          // 反追踪评估与状态通知同频：15 秒足够，也不需要另开定时器。
          this.scanAntiTracking();
        }, 15000);
      }
    });
  }
  private stopStateNotification(): void {
    if (this.stateNotificationTimer >= 0) { clearInterval(this.stateNotificationTimer); this.stateNotificationTimer = -1; }
  }
  /** 组装并发布当前运行状态。文案走资源，便于本地化。 */
  private publishStateNotification(): void {
    if (!this.notificationsEnabled) return;
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return;
    const title: string = resolveResourceString(context, $r('app.string.fieldwatch_state_notification_title'));
    let ble: number = 0;
    let wifi: number = 0;
    let nearLink: number = 0;
    this.state.sightings.forEach((item: Sighting): void => {
      if (item.kind === RadioKind.WIFI) wifi += 1;
      else if (item.kind === RadioKind.NEARLINK) nearLink += 1;
      else ble += 1;
    });
    let body: string = 'BLE ' + ble.toString() + ' · Wi-Fi ' + wifi.toString();
    // 星闪只在设备支持时出现，与雷达头部保持一致的顺序。
    if (this.nearLinkSupported) {
      body += ' · ' + resolveResourceString(context, $r('app.string.fieldwatch_radio_nearlink')) + ' ' + nearLink.toString();
    }
    if (this.state.settings.displayPaused) {
      body += ' · ' + resolveResourceString(context, $r('app.string.fieldwatch_state_notification_paused'));
    }
    void ngfBackgroundTaskManager.publishStateNotification(title, body);
  }
  /**
   * 按设置同步后台长时任务。
   *
   * 应用启动时就要调用：此前只在「切到后台」时才启动长时任务，
   * 导致设置里开着后台运行、应用却一直没进入受保护的后台态，
   * 用户切出去没多久就被系统挂起。
   */
  async syncBackgroundTask(): Promise<void> {
    // **先清残留、再发通知。** 顺序反了会把本次刚发的运行状态通知一起清掉。
    await this.clearStaleNotifications();
    // 后台任务同样依赖通知：鸿蒙要求长时任务必须伴随一条用户可见的通知。
    this.notificationsEnabled = await ngfSystemNotificationManager.isEnabled();
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return;
    const title: string = resolveResourceString(context, $r('app.string.fieldwatch_state_notification_title'));
    const body: string = resolveResourceString(context, $r('app.string.fieldwatch_background_running'));
    // **前台也持有长时任务**（用户明确要求：前台运行时通知应当是常驻的）。
    //
    // 鸿蒙上「不可划掉的通知」只有长时任务伴随通知这一种机制 ——
    // `isOngoing` / `isUnremovable` 在 API 26 声明里都标注 Not supported currently。
    // 因此要满足「前台常驻通知」，就只能在前台也持有长时任务；
    // 未开启后台运行的用户切到后台时再把它停掉（见 onAbilityBackground）。
    const started: boolean = await ngfBackgroundTaskManager.startContinuousTask('fieldwatch.scan', title, body);
    if (started) this.startStateNotification();
    // 冷启动也要写一次：卡片可能正在显示，不能等下一次状态变化。
    this.writeWidgetState();
  }
  async onAbilityBackground(): Promise<void> {
    // 先落标志：页面在下一个 tick 就会据此停掉 60fps 重绘。
    this.appForeground = false;
    // 卡片口径是「允许后台运行 且 确实在后台」——进后台后要立刻重算。
    this.writeWidgetState();
    if (this.state.settings.backgroundScanning) {
      if (this.state.scanState === ScanState.SCANNING) {
        // 用户明确要求后台继续扫描：保持长时任务与伴随通知。
        // 前台已经持有，这里只是确保（`syncBackgroundTask` 幂等，已在运行就只刷新内容）。
        await this.syncBackgroundTask();
      }
      return;
    }
    // 未开启后台扫描：**完全暂停信号收集**，长时任务与常驻通知一起关掉。
    // 记住「退后台前在扫描」，回前台时据此恢复 —— 平台只会暂停扫描，不会帮你恢复。
    this.resumeScanOnForeground = this.state.scanState === ScanState.SCANNING;
    this.stopStateNotification();
    await ngfBackgroundTaskManager.stopContinuousTask();
    // **用户没有开启后台扫描时必须停扫。**
    //
    // 此前这里只处理「开了后台扫描」的分支，没开就什么都不做 ——
    // 结果退到后台后 BLE 与 Wi-Fi 仍在全速运行：
    // 实测 30 秒收到 2179 条 BLE 观测（约 72 条/秒），Wi-Fi 也继续产出 fresh 结果，
    // 进程 CPU 稳定在 80% 以上。用户既没有要求后台扫描，界面上也没有任何提示，
    // 属于纯粹的静默耗电。
    if (this.state.scanState === ScanState.SCANNING) {
      this.stopScan();
      logger.info(TAG, '已退到后台且未开启后台扫描，无线电扫描已停止');
    }
  }
  /**
   * 应用是否在前台。
   *
   * **页面的 `visible` 只表示「这个标签页被选中」，不表示应用在前台** ——
   * 退到后台时标签页仍然是选中的，因此只判断 `visible` 的定时器会继续全速运行。
   * 实测后果：应用退到后台后 CPU 仍占 ~106%（60fps 雷达重绘），
   * 且 ark ts heap 以约 14 MB/分持续增长。
   */
  private appForeground: boolean = true;
  isAppForeground(): boolean { return this.appForeground; }

  async onAbilityForeground(): Promise<void> {
    this.appForeground = true;
    // 回前台后卡片应显示「app 未运行」（此刻并没有在后台采集）。
    this.writeWidgetState();
    // 回到前台：**重新持有长时任务与常驻通知**（前台要求通知常驻）。
    // 它可能在退后台时被停掉（未开启后台运行的分支）。
    void this.syncBackgroundTask();
    // **恢复扫描**：平台在后台暂停了 BLE 扫描，回前台不会自动恢复。
    //
    // 必须先 `stopScan()` 再 `startScan()`：BLE 扫描器的 `start()` 会再次
    // `on('BLEDeviceFind', ...)`，直接重复调用会叠加监听器导致同一观测被重复处理。
    // `stopScan()` 里的 `off(...)` 正好把它摘干净。
    if (this.resumeScanOnForeground) {
      this.resumeScanOnForeground = false;
      this.stopScan();
      this.startScan();
      logger.info(TAG, '回到前台，无线电扫描已重新启动');
    }
    // **不要在这里按「有没有开后台运行」去停长时任务** ——
    // 前台是要求通知常驻的，上面刚把它起来，这里再停就自相矛盾了。
    // 权限不需要在这里重新探测：
    // Live 页与 Settings 页都在自己的 1 秒刷新里重读 permissionSnapshot()，
    // 因此从系统设置改完权限切回来，最多 1 秒就会自己更新。
    // （曾在此处加过一套订阅机制，核实后发现与轮询完全重复，已删除——
    //   不要为已覆盖的需求旁路新增平行实现。）
  }
  async onAbilityDestroy(): Promise<void> { await ngfBackgroundTaskManager.stopContinuousTask(); }
  shareSighting(sighting: Sighting): void { ngfSystemShareFacade.shareText(this.exportSerializer.serializeJsonl([sighting], this.state.settings)); }
  /**
   * 详情页「以文本分享」：把详情纯文本交给系统分享面板。
   *
   * 此前这个入口与「AI 导出」**只弹了一个「前 60 字」的 Toast，文本没有去处** ——
   * 按钮看起来有反应，实际什么都没分享出去。
   * 分享一律走 `ngfSystemShareFacade.shareText`（ShareKit 纯文本），
   * 与 `shareSighting` / `shareDebrief` / `shareExport` 同一条路。
   */
  shareDetailText(sighting: Sighting, signatureNames: string[]): void {
    ngfSystemShareFacade.shareText(this.detailTextOf(sighting, signatureNames));
  }
  /**
   * 详情页「AI 导出」：把 AI 提示词交给系统分享面板。
   *
   * 不加 `AI_MAX_CHARS` 截断：那个上限是给「整场观测」的导出用的（要列全部设备），
   * 这里只有一台设备，文本量远小于上限。
   */
  shareDetailPrompt(sighting: Sighting, signatureNames: string[]): void {
    ngfSystemShareFacade.shareText(this.detailPromptOf(sighting, signatureNames));
  }
  /** 重命名已保存的观测：读回后改名再写回。 */
  async renameSit(id: string, name: string): Promise<boolean> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) return false;
    const sits: SitSummary[] = await this.loadSavedSits();
    const target: SitSummary | undefined = sits.find((item: SitSummary): boolean => item.id === id);
    if (target === undefined) return false;
    target.name = trimmed;
    return await this.observationRepository.saveSit(target, target.deviceKeys);
  }
  /** 删除全部已保存观测（进行中的观测不受影响）。 */
  async deleteAllSits(): Promise<boolean> {
    const sits: SitSummary[] = await this.loadSavedSits();
    let ok: boolean = true;
    for (let index: number = 0; index < sits.length; index += 1) {
      const deleted: boolean = await this.observationRepository.deleteSit(sits[index].id);
      if (!deleted) ok = false;
    }
    await this.loadSavedSits();
    return ok;
  }
  /** 候选特征：日志里未匹配的信号源按 key 汇总（只分享，不写目录）。 */
  // ── AI 导出（原版 domain/DebriefPrompt.kt / SitDiffPrompt.kt） ──
  /** 15 分钟窗口。 */
  private static readonly AI_WINDOW_MS: number = 15 * 60 * 1000;
  /** 近 5 分钟切片。 */
  private static readonly AI_SHORT_MS: number = 5 * 60 * 1000;
  private static readonly AI_MAX_CHARS: number = 90000;
  private aiBand(values: number[], low: number, high: number): number {
    return values.filter((value: number): boolean => value >= low && value <= high).length;
  }
  private aiPct(part: number, total: number): number { return total <= 0 ? 0 : Math.round(part * 100 / total); }
  private aiDuration(millis: number): string {
    const seconds: number = Math.max(0, Math.floor(millis / 1000));
    const minutes: number = Math.floor(seconds / 60);
    if (minutes >= 60) return Math.floor(minutes / 60).toString() + 'h' + (minutes % 60).toString() + 'm';
    if (minutes > 0) return minutes.toString() + 'm' + (seconds % 60).toString() + 's';
    return seconds.toString() + 's';
  }
  private aiUtc(millis: number): string {
    const date: Date = new Date(millis);
    const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
    return date.getUTCFullYear().toString() + '-' + pad(date.getUTCMonth() + 1) + '-' + pad(date.getUTCDate()) + 'T'
      + pad(date.getUTCHours()) + ':' + pad(date.getUTCMinutes()) + ':' + pad(date.getUTCSeconds()) + 'Z';
  }
  /** 单行设备描述：与原版 DebriefPrompt.row 同构。 */
  /** 无线电种类的导出/统计标签。集中一处，避免每个三元表达式都漏掉星闪。 */
  private radioLabel(kind: RadioKind): string {
    if (kind === RadioKind.WIFI) return 'WIFI';
    if (kind === RadioKind.NEARLINK) return 'NEARLINK';
    return 'BLE';
  }
  private aiRow(item: Sighting, windowStart: number, now: number): string {
    const parts: string[] = [];
    parts.push(this.radioLabel(item.kind));
    parts.push(item.key.replace(/^[a-z]+:/, ''));
    const label: string = this.displayName(item);
    if (label.length > 0 && label !== item.key) parts.push(label.substring(0, 32));
    parts.push('rssi=' + item.rssi.toString() + 'dBm');
    if (item.signatureIds.length > 0) parts.push('sig=' + item.signatureIds.map((id: string): string => {
      const fleet: SignatureFleet | undefined = this.state.signatures.find((f: SignatureFleet): boolean => f.id === id);
      return fleet === undefined ? id : fleet.name;
    }).join(' + '));
    const decoded: string[] = item.decodedFields.filter((value: DecodedFieldValue): boolean => value.live).map((value: DecodedFieldValue): string => value.text);
    if (decoded.length > 0) parts.push('decoded=' + decoded.join(','));
    parts.push('dwell=' + this.aiDuration(Math.max(0, now - item.firstSeen)));
    return parts.join(' ');
  }
  /** 粘贴即用的 AI 补充说明（Reports → AI 导出）。 */
  aiExportDebrief(): void {
    const now: number = Date.now();
    const windowStart: number = now - FieldwatchApplication.AI_WINDOW_MS;
    const shortStart: number = now - FieldwatchApplication.AI_SHORT_MS;
    const all: Sighting[] = this.state.sightings;
    const recent: Sighting[] = all.filter((item: Sighting): boolean => item.lastSeen >= windowStart || item.firstSeen >= windowStart);
    const short: Sighting[] = recent.filter((item: Sighting): boolean => item.lastSeen >= shortStart || item.firstSeen >= shortStart);
    const wifi: Sighting[] = recent.filter((item: Sighting): boolean => item.kind === RadioKind.WIFI);
    const ble: Sighting[] = recent.filter((item: Sighting): boolean => item.kind === RadioKind.BLE);
    const nearLink: Sighting[] = recent.filter((item: Sighting): boolean => item.kind === RadioKind.NEARLINK);
    const signed: Sighting[] = recent.filter((item: Sighting): boolean => item.signatureIds.length > 0);
    const arrived: Sighting[] = recent.filter((item: Sighting): boolean => item.firstSeen >= windowStart);
    const gone: Sighting[] = recent.filter((item: Sighting): boolean => item.lastSeen < now - 45000);
    const persistent: Sighting[] = recent.filter((item: Sighting): boolean => (now - item.firstSeen) >= FieldwatchApplication.AI_WINDOW_MS * 2 / 3);
    const attention: Sighting[] = recent.filter((item: Sighting): boolean => item.signatureIds.some((id: string): boolean =>
      this.state.signatures.some((fleet: SignatureFleet): boolean => fleet.id === id && fleet.attentionNote.length > 0)));
    const finders: Sighting[] = recent.filter((item: Sighting): boolean => item.signatureIds.some((id: string): boolean =>
      this.state.signatures.some((fleet: SignatureFleet): boolean => fleet.id === id && foldedSignatureClass(fleet.category) === SignatureClass.FINDER)));
    const bleRssi: number[] = ble.map((item: Sighting): number => item.rssi);
    const wifiRssi: number[] = wifi.map((item: Sighting): number => item.rssi);
    const nl: string = String.fromCharCode(10);
    const lines: string[] = [];
    lines.push('# Fieldwatch AI 补充说明 / AI Export addendum');
    lines.push('');
    lines.push('实验性用途。Fieldwatch 是只接收的被动监听工具，不做关联、不做注入、不连云。');
    lines.push('');
    lines.push('You are a field RF analyst for the operator who collected this sit. Fieldwatch is receive-only.');
    lines.push('The onboard Debrief (verbatim below) already tabulated the sit. Do not reprint its rosters.');
    lines.push('');
    lines.push('## Constraints you must respect');
    lines.push('- Hear-only. Wi-Fi rows are access points only. BLE rows are advertisers. Kind + MAC.');
    lines.push('- Signature / OUI / company matches are hypotheses, not identity, not a person or vehicle.');
    lines.push('- GPS stamps (if present) are this phone at hear-time, not the other radio.');
    lines.push('- RSSI is loudness at the phone, not meters.');
    lines.push('- Live RAM cap is about 400 radios; unnamed BLE evicts after ~3 min.');
    lines.push('- Do not claim a tracker is following unless the onboard co-travel section supports it.');
    lines.push('- A decoded live value is catalog text for that advertisement. Quote the catalog sentence when you use it.');
    lines.push('- Do not give safety advice. Do not tell the operator they are safe or in danger.');
    lines.push('- Treat this paste as operationally sensitive.');
    lines.push('');
    lines.push('## Your output (required)');
    lines.push('1. **Disclaimer** — repeat the experimental-use disclaimer first.');
    lines.push('2. **What the onboard Debrief already established** — 3-5 sentences.');
    lines.push('3. **What the numbers add** — 5- vs 15-minute counts, RSSI bands, RAND BLE percent, arrivals per minute, persistence.');
    lines.push('4. **Extra attention and tracking callouts** — full identifiers from the working table.');
    lines.push('5. **What another sit or Hunt would shrink** — concrete in-app next steps only.');
    lines.push('**Takeaway (required, last line).** One sentence starting with 要点： that adds one number.');
    lines.push('');
    lines.push('## Collection context');
    lines.push('- Tool: Fieldwatch, receive-only, no association / injection / cloud.');
    lines.push('- Window: last 15 minutes (' + this.aiUtc(windowStart) + ' -> ' + this.aiUtc(now) + ' UTC), with a 5-minute recent slice.');
    lines.push('- Scan intensity: ' + this.state.settings.scanIntensity + '.');
    lines.push('- Location tags: ' + (this.state.settings.locationTagging ? 'on' : 'off') + '.');
    lines.push('');
    lines.push('## Onboard Debrief (verbatim)');
    lines.push('');
    lines.push(this.buildDebrief().trim());
    lines.push('');
    lines.push('## Working data (for the addendum — do not copy rosters into the answer)');
    lines.push('');
    lines.push('15 min: Wi-Fi ' + wifi.length.toString() + '  BLE ' + ble.length.toString()
      + '  NearLink ' + nearLink.length.toString() + '  signed ' + signed.length.toString()
      + '  RAND BLE ' + ble.length.toString() + '/' + ble.length.toString() + ' (' + this.aiPct(ble.length, ble.length).toString() + '%)'
      + '  first-seen ' + arrived.length.toString() + '  persistent ' + persistent.length.toString() + '  gone/quiet ' + gone.length.toString());
    lines.push('5 min: Wi-Fi ' + short.filter((i: Sighting): boolean => i.kind === RadioKind.WIFI).length.toString()
      + '  BLE ' + short.filter((i: Sighting): boolean => i.kind === RadioKind.BLE).length.toString()
      + '  NearLink ' + short.filter((i: Sighting): boolean => i.kind === RadioKind.NEARLINK).length.toString()
      + '  signed ' + short.filter((i: Sighting): boolean => i.signatureIds.length > 0).length.toString());
    lines.push('BLE RSSI (n=' + ble.length.toString() + '): >=-50 ' + this.aiBand(bleRssi, -50, 0).toString()
      + '  -51..-70 ' + this.aiBand(bleRssi, -70, -51).toString() + '  -71..-85 ' + this.aiBand(bleRssi, -85, -71).toString()
      + '  <-85 ' + bleRssi.filter((v: number): boolean => v < -85).length.toString());
    lines.push('Wi-Fi RSSI (n=' + wifi.length.toString() + '): >=-50 ' + this.aiBand(wifiRssi, -50, 0).toString()
      + '  -51..-70 ' + this.aiBand(wifiRssi, -70, -51).toString() + '  -71..-85 ' + this.aiBand(wifiRssi, -85, -71).toString()
      + '  <-85 ' + wifiRssi.filter((v: number): boolean => v < -85).length.toString());
    lines.push('GPS path: tagging ' + (this.state.settings.locationTagging ? 'on' : 'off') + '  fixes ' + this.travelTrack().length.toString()
      + '  length ' + Math.round(this.travelPathMeters()).toString() + ' m');
    lines.push('');
    lines.push('Extra attention:');
    if (attention.length === 0) lines.push('- None.');
    attention.forEach((item: Sighting): void => { lines.push('- ' + this.aiRow(item, windowStart, now)); });
    lines.push('');
    lines.push('Finder-tag-like radios (stress-test of onboard tracking; not a tail list):');
    if (finders.length === 0) lines.push('- None.');
    finders.forEach((item: Sighting): void => { lines.push('- ' + this.aiRow(item, windowStart, now)); });
    lines.push('');
    lines.push('## End of working data');
    lines.push('Write the addendum now, following **Your output** at the top. Do not rewrite the onboard Debrief.');
    const body: string = lines.join(nl);
    ngfSystemShareFacade.shareText(body.length <= FieldwatchApplication.AI_MAX_CHARS
      ? body
      : body.substring(0, FieldwatchApplication.AI_MAX_CHARS) + nl + nl + '[truncated for share-sheet size]');
  }
  /** 对比观测的 AI 补充说明。 */
  aiExportCompare(): void {
    const nl: string = String.fromCharCode(10);
    const lines: string[] = [];
    lines.push('# Fieldwatch AI 对比补充说明 / Compare addendum');
    lines.push('');
    lines.push('Same report, two formats. Presence only — only in this sit, only in the second, in both.');
    lines.push('');
    lines.push('## Constraints you must respect');
    lines.push('- Hear-only. Presence, not identity.');
    lines.push('- Do not give safety advice.');
    lines.push('');
    lines.push('## Compare (verbatim)');
    lines.push('');
    lines.push(this.buildCompareText());
    lines.push('');
    lines.push('**Takeaway (required, last line).** One sentence starting with 要点：.');
    ngfSystemShareFacade.shareText(lines.join(nl));
  }
  /** 对比的纯文本摘要（AI 导出用）。 */
  private buildCompareText(): string {
    const nl: string = String.fromCharCode(10);
    const current: Sighting[] = this.state.sightings;
    const saved: SitSummary | undefined = this.state.savedSits.length === 0 ? undefined : this.state.savedSits[0];
    const lines: string[] = [];
    lines.push('本次观测: ' + current.length.toString() + ' 台信号源');
    lines.push(saved === undefined ? '没有可对比的第二段观测。' : ('第二段观测: ' + saved.name + ' · ' + saved.radioCount.toString() + ' 台'));
    lines.push('只比较在场情况 —— 仅在本次、仅在第二段、两者都在。');
    return lines.join(nl);
  }
  /** 复盘/对比 PDF 共用的生成入口。 */
  private async buildPdf(text: string, fileName: string): Promise<string> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return '';
    return this.debriefPdf.build(text, context.filesDir + '/' + fileName);
  }
  /** 生成复盘 PDF 到应用沙箱，返回路径；失败返回空串。 */
  async exportDebriefPdf(): Promise<string> {
    return await this.buildPdf(this.buildDebrief(), 'fieldwatch-debrief.pdf');
  }
  /** 生成对比观测 PDF。 */
  async exportComparePdf(): Promise<string> {
    return await this.buildPdf(this.buildCompareText(), 'fieldwatch-compare.pdf');
  }
  /** 本次会话的日志占用：行数 + 数据库目录字节数。 */
  async logFootprint(): Promise<FieldwatchLogFootprint> {
    const rows: number = await this.observationRepository.loadRecent(200000).then((list): number => list.length);
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return new FieldwatchLogFootprint(rows, 0);
    let bytes: number = 0;
    try {
      // RDB 文件位于 databaseDir 的下级子目录（如 entry/），必须递归统计；
      // 只量目录本身会得到目录 inode 的几 KB，严重低估。
      bytes = this.directoryBytes(context.databaseDir, 0);
    } catch (error) {
      logger.warn(TAG, '读取数据库目录失败: ' + String(error));
    }
    return new FieldwatchLogFootprint(rows, bytes);
  }
  /** 递归累计目录字节数；深度上限 3，避免异常目录结构导致无限递归。 */
  private directoryBytes(dir: string, depth: number): number {
    if (depth > 3) return 0;
    let total: number = 0;
    fileIo.listFileSync(dir).forEach((name: string): void => {
      const path: string = dir + '/' + name;
      try {
        const stat: fileIo.Stat = fileIo.statSync(path);
        total += stat.isDirectory() ? this.directoryBytes(path, depth + 1) : stat.size;
      } catch (error) {
        logger.debug(TAG, '跳过不可读条目: ' + name);
      }
    });
    return total;
  }
  /** 清空本地日志（观测存储）。 */
  clearLogs(): void {
    void this.observationRepository.clearObservations().then((ok: boolean): void => {
      if (ok) this.state.sightings = [];
    });
  }  // ── 观测/记录导出：格式 × 信号源（原版 GeoExport.kt 的 LogExportKind / LogExportRadios） ──
  /** 按信号源选择过滤。0=全部 1=仅 Wi-Fi 2=仅 BLE 3=仅星闪。 */
  private exportFiltered(radios: number): Sighting[] {
    if (radios === 1) return this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.WIFI);
    if (radios === 2) return this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.BLE);
    if (radios === 3) return this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.NEARLINK);
    return this.state.sightings;
  }
  /** 导出正文。0=CSV 1=JSONL 2=GPX 3=KML 4=WiGLE。 */
  exportText(format: number, radios: number): string {
    const list: Sighting[] = this.exportFiltered(radios);
    if (format === 0) return this.exportSerializer.serializeCsv(list, this.state.settings);
    if (format === 1) return this.exportSerializer.serializeJsonl(list, this.state.settings);
    if (format === 2) return this.exportSerializer.serializeGpx(list, this.state.settings);
    if (format === 3) return this.exportSerializer.serializeKml(list, this.state.settings);
    return this.exportSerializer.serializeWigle(list, this.state.settings);
  }
  /** 导出文件名，扩展名与原版 GeoExport.Format 一致（WiGLE 也是 .csv）。 */
  exportFileName(format: number): string {
    const stamp: string = new Date().toISOString().substring(0, 19).replace(/[:T]/g, '-');
    if (format === 0) return 'fieldwatch-log-' + stamp + '.csv';
    if (format === 1) return 'fieldwatch-log-' + stamp + '.jsonl';
    if (format === 2) return 'fieldwatch-log-' + stamp + '.gpx';
    if (format === 3) return 'fieldwatch-log-' + stamp + '.kml';
    return 'fieldwatch-wigle-' + stamp + '.csv';
  }
  shareExport(format: number, radios: number): void {
    ngfSystemShareFacade.shareText(this.exportText(format, radios));
  }
  /** 经系统文件选择器另存到用户指定位置。 */
  async saveExportAs(format: number, radios: number): Promise<boolean> {
    return await this.catalogFileGateway.saveToFile(this.exportFileName(format), this.exportText(format, radios));
  }  // ── R6 候选特征（原版 domain/SignatureCandidates.kt） ──
  /** 分析当前日志中的未匹配信号源，返回候选特征报告。 */
  candidateReport(): CandidateReport {
    return this.candidateEngine.analyze(this.state.sightings, this.state.signatures);
  }
  /** 把候选写入目录（用户审核后才调用）。返回新特征的 id，失败返回空串。 */
  addCandidateToCatalog(candidate: SignatureCandidate): string {
    const id: string = 'user-' + Date.now().toString() + '-' + Math.floor(Math.random() * 10000).toString();
    const fleet: SignatureFleet = this.candidateEngine.toFleet(candidate, id);
    this.state.signatures = this.state.signatures.concat([fleet]);
    this.catalogRepository.save(this.state.signatures.filter((item: SignatureFleet): boolean => !item.builtIn));
    logger.info(TAG, '候选特征已写入目录: ' + fleet.name);
    return id;
  }  shareDebrief(): void { ngfSystemShareFacade.shareText(this.buildDebrief()); }
  shareCompare(): void {
    if (this.state.savedSits.length < 2) return;
    const first: SitSummary = this.state.savedSits[0];
    const second: SitSummary = this.state.savedSits[1];
    const comparison: FieldwatchCompareResult = this.compareService.compare(first.deviceKeys, second.deviceKeys);
    const sharedSignatures: string[] = this.signatureNamesForKeys(comparison.sharedKeys);
    const report: string = 'Fieldwatch Compare\n'
      + first.name + ': ' + first.radioCount.toString() + ' radios\n'
      + second.name + ': ' + second.radioCount.toString() + ' radios\n'
      + 'Shared: ' + comparison.sharedKeys.length.toString() + '\n'
      + 'Added: ' + comparison.addedKeys.length.toString() + '\n'
      + 'Removed: ' + comparison.removedKeys.length.toString() + '\n'
      + 'Difference: ' + (second.radioCount - first.radioCount).toString() + ' radios\n'
      + 'Shared signatures: ' + (sharedSignatures.length > 0 ? sharedSignatures.join(', ') : '-') + '\n';
    ngfSystemShareFacade.shareText(report);
  }
  saveSettingsBackup(): boolean { return this.saveExport('settings.fieldwatch', this.settingsRepository.exportBackup(this.state.settings)); }
  restoreSettingsBackup(): boolean {
    const content: string = FileUtils.readText('fieldwatch/exports/settings.fieldwatch');
    const restored: boolean = this.settingsRepository.importBackup(content);
    if (restored) this.state.settings = this.settingsRepository.load();
    return restored;
  }

  private saveExport(fileName: string, content: string): boolean {
    FileUtils.createDirectory('fieldwatch/exports');
    return FileUtils.writeText('fieldwatch/exports/' + fileName, content);
  }
  buildDebrief(): string {
    const wifiCount: number = this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.WIFI).length;
    const bleCount: number = this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.BLE).length;
    const nearLinkCount: number = this.state.sightings.filter((item: Sighting): boolean => item.kind === RadioKind.NEARLINK).length;
    const active: string = this.state.activeSit === undefined ? 'No active sit' : this.state.activeSit.name;
    const located: number = this.state.sightings.filter((item: Sighting): boolean => item.location !== undefined).length;
    let report: string = 'Airwave Footprints Debrief\n'
      + 'Observations: ' + this.state.sightings.length.toString() + '\n'
      + 'Wi-Fi: ' + wifiCount.toString() + '\n'
      + 'BLE: ' + bleCount.toString() + '\n'
      + 'NearLink: ' + nearLinkCount.toString() + '\n'
      + 'With location: ' + located.toString() + '\n'
      + 'Active sit: ' + active + '\n'
      + 'Catalog: version ' + this.state.catalogVersion.toString() + ', ' + this.state.signatures.length.toString() + ' signatures\n';
    const matched: number = this.state.sightings.filter((item: Sighting): boolean => item.signatureIds.length > 0).length;
    report += '\nSignatures\n' + 'Matched radios: ' + matched.toString() + '\n';
    const hits: string[] = signatureHitCounts(this.state.sightings, this.state.signatures);
    if (hits.length === 0) report += '  (no signature matched)\n';
    else hits.slice(0, 12).forEach((line: string): void => { report += '  ' + line + '\n'; });
    const decoded: string[] = this.decodedSummary();
    report += '\nDecoded fields\n';
    if (decoded.length === 0) report += '  (no decoded field)\n';
    else decoded.slice(0, 12).forEach((line: string): void => { report += '  ' + line + '\n'; });
    return report;
  }

  /** 按“字段: 值”统计解码结果，供 Debrief 和导出摘要复用。 */
  decodedSummary(): string[] {
    const counts: Map<string, number> = new Map<string, number>();
    this.state.sightings.forEach((sighting: Sighting): void => {
      sighting.decodedFields.forEach((value: DecodedFieldValue): void => {
        const key: string = value.label + ': ' + value.text;
        const current: number | undefined = counts.get(key);
        counts.set(key, current === undefined ? 1 : current + 1);
      });
    });
    const entries: string[] = [];
    counts.forEach((value: number, key: string): void => { entries.push(value.toString().padStart(4, ' ') + '  ' + key); });
    entries.sort((first: string, second: string): number => second.localeCompare(first));
    return entries;
  }

  /** 把设备 key 解析成命中的签名名，用于 Compare 报告。 */
  private signatureNamesForKeys(keys: string[]): string[] {
    const names: string[] = [];
    keys.forEach((key: string): void => {
      const sighting: Sighting | undefined = this.state.sightings.find((item: Sighting): boolean => item.key === key);
      if (sighting === undefined) return;
      matchedSignatureNames(sighting.signatureIds, this.state.signatures).forEach((name: string): void => {
        if (names.indexOf(name) < 0) names.push(name);
      });
    });
    return names;
  }
  filteredSightings(): Sighting[] { return this.state.sightings.filter((sighting: Sighting): boolean => this.filterEngine.pass(sighting, this.state.filter, this.state.signatures, this.state.watchlist, this.namedRadioKeys(), Date.now())); }
  displayName(sighting: Sighting): string { return this.privacyService.displayName(sighting, this.state.settings.privacyMode); }

  /**
   * 命中签名的显示名（§12.2「显示签名名称」）。
   *
   * 此前**列表行里根本不显示签名名称**，所以那一条清单要求不只是缺个开关，
   * 而是缺了整个展示能力。这里取该设备命中的第一个签名；没有签名时返回空串，
   * 由调用方决定要不要显示。
   */
  signatureNameOf(sighting: Sighting): string {
    const fleet: SignatureFleet | undefined = this.fleetOfSighting(sighting);
    return fleet === undefined ? '' : fleet.name;
  }
  describeName(sighting: Sighting): string { return this.privacyService.deviceName(sighting); }
  describeAddress(sighting: Sighting): string { return this.privacyService.maskAddress(sighting.address, this.state.settings.privacyMode); }
  describeLocation(sighting: Sighting): string { return this.privacyService.maskLocation(sighting.location, this.state.settings.privacyMode); }

  /** 关注对象命中：既支持具体设备键，也支持整个签名或产品族。 */
  private watchTargetHits(target: WatchTarget, sighting: Sighting): boolean {
    if (!target.alert) return false;
    if (target.deviceKey.length > 0 && target.deviceKey === sighting.key) return true;
    if (target.signatureId.length > 0 && sighting.signatureIds.indexOf(target.signatureId) >= 0) return true;
    return false;
  }

  isSignatureWatched(signatureId: string): boolean {
    return this.state.watchlist.some((target: WatchTarget): boolean => target.signatureId === signatureId && target.signatureId.length > 0);
  }

  /** 关注/取消关注整个签名；命中该签名的任何设备都会触发关注逻辑。 */
  toggleSignatureWatch(fleet: SignatureFleet): void {
    const existing: WatchTarget | undefined = this.state.watchlist.find((target: WatchTarget): boolean => target.signatureId === fleet.id);
    if (existing !== undefined) {
      this.state.watchlist = this.state.watchlist.filter((target: WatchTarget): boolean => target !== existing);
    } else {
      this.state.watchlist.push(new WatchTarget('', fleet.id, fleet.name, true));
    }
    this.settingsRepository.saveWatchlist(this.state.watchlist);
  }

  toggleWatch(sighting: Sighting): void {
    const existing: WatchTarget | undefined = this.state.watchlist.find((target: WatchTarget): boolean => target.deviceKey === sighting.key);
    if (existing !== undefined) {
      this.state.watchlist = this.state.watchlist.filter((target: WatchTarget): boolean => target !== existing);
      this.settingsRepository.saveWatchlist(this.state.watchlist);
      return;
    }
    this.state.watchlist.push(new WatchTarget(sighting.key, '', sighting.name, true));
    this.settingsRepository.saveWatchlist(this.state.watchlist);
  }

  // ── 设备级自定义名称与观察者备注（原版 domain/RadioBookmarks.kt）──
  //
  // 两者都存在关注条目的 label / note 上，因此**命名不等于开启告警**：
  // 原版 upsertName 的 alertIfNew 默认 false，upsertNotes 新建时 alert 也是 false。
  // 这一点必须保持 —— 只想起个名字的用户不该因此收到告警。

  /** 自定义名称上限（原版 RadioBookmarks.MAX_NAME）。 */
  static readonly MAX_DEVICE_LABEL: number = 22;
  /** 观察者备注上限（原版 RadioBookmarks.MAX_NOTES）。 */
  static readonly MAX_DEVICE_NOTE: number = 280;

  /** 原版 RadioBookmarks.clip：去空格 → 截断 → 空则用 'Radio'。 */
  // ── 名称库的公开查询（详情页要显示外观名与服务 UUID 名）──

  /** GAP Appearance -> 名称；查不到返回空串（界面据此只显示代码）。 */
  // ── 设备详情页需要的取数口 ──

  /** 按 key 找当前在场的设备；找不到返回 undefined（设备可能已经离开列表）。 */
  sightingByKey(key: string): Sighting | undefined {
    return this.state.sightings.find((item: Sighting): boolean => item.key === key);
  }

  /** 该设备命中的签名展示名（去重）。详情页的「匹配的特征」与特征族都用它。 */
  signatureNamesFor(sighting: Sighting): string[] {
    return matchedSignatureNames(sighting.signatureIds, this.state.signatures);
  }

  /**
   * 详情页的**纯文本转储**（对齐原版 `DeviceDetailText.build`）。
   *
   * 与原版一致：同样的字段、不带趋势图与在场条 —— 它是给「粘贴到别处」用的，
   * 图形在纯文本里没有意义。
   */
  detailTextOf(sighting: Sighting, signatureNames: string[]): string {
    const nl: string = String.fromCharCode(10);
    const out: string[] = [];
    out.push('Fieldwatch 设备详情');
    out.push(new Date().toISOString());
    out.push('实验性输出。不是法律意义上的身份。这是系统暴露出来的内容，不代表一定存在追踪器或摄像头。');
    out.push('');
    out.push(this.describeName(sighting));
    out.push('MAC: ' + sighting.address);
    out.push('');
    const names: string[] = signatureNames.length > 0 ? signatureNames : this.signatureNamesFor(sighting);
    out.push('## 身份');
    out.push('信号源: ' + (sighting.kind === RadioKind.WIFI ? 'Wi-Fi 接入点（在广播网络）' : (sighting.kind === RadioKind.NEARLINK ? '星闪广播源' : '蓝牙低功耗广播源')));
    out.push('厂商: ' + this.vendorOfSighting(sighting));
    out.push('');
    out.push('## 信号');
    out.push('此处强度 (RSSI): ' + sighting.rssi.toString() + ' dBm');
    out.push('本次会话听到的强度范围: ' + sighting.rssiMin.toString() + ' ~ ' + sighting.rssiMax.toString() + ' dBm');
    if (sighting.facts.txPower > -128) out.push('声明的发射功率: ' + sighting.facts.txPower.toString() + ' dBm');
    if (sighting.facts.frequencyMhz > 0) out.push('频率: ' + sighting.facts.frequencyMhz.toString() + ' MHz');
    out.push('');
    out.push('## 本次会话');
    out.push('首次出现: ' + new Date(sighting.firstSeen).toLocaleString());
    out.push('最后出现: ' + new Date(sighting.lastSeen).toLocaleString());
    out.push('命中次数: ' + sighting.count.toString());
    if (sighting.location !== undefined) {
      out.push('最后定位: ' + sighting.location.latitude.toFixed(5) + ', ' + sighting.location.longitude.toFixed(5));
      out.push('最后定位是听到它时手机的位置，不是这台信号源的位置。');
    }
    if (names.length > 0) out.push('匹配的特征: ' + names.join('; '));
    if (sighting.facts.rawAdHex.length > 0) out.push('原始广播: ' + sighting.facts.rawAdHex);
    return out.join(nl) + nl;
  }

  /**
   * AI 导出提示词（对齐原版 `DeviceDetailPrompt.build`）。
   *
   * 结构：免责声明 → 角色设定 → 约束清单 → 采集上下文 → 观测转储 → 要求的分析小节。
   * **约束清单是重点**：它明确禁止模型编造字段、把 RSSI 换算成距离、
   * 或声称这台设备在跟踪谁 —— 这些正是这类数据最容易被过度解读的地方。
   */
  detailPromptOf(sighting: Sighting, signatureNames: string[]): string {
    const nl: string = String.fromCharCode(10);
    const out: string[] = [];
    out.push('> 实验性功能。不构成法律意义上的身份认定。');
    out.push('');
    out.push('你是一位射频 / 隐私分析专家，熟悉 IEEE OUI、蓝牙 SIG 分配号、GAP Appearance、蓝牙广播格式与 Wi-Fi 信标。');
    out.push('');
    out.push('用户希望从一条 Fieldwatch 观测中尽可能了解**这一台**无线电。Fieldwatch 是仅接收的被动观测工具。');
    out.push('');
    out.push('必须遵守的约束：');
    out.push('- 这是**一台**广播设备，不是人、车辆或法律身份。');
    out.push('- Wi-Fi 行**只有接入点**。关联的客户端不可见。');
    out.push('- BLE 行是广播源。随机 MAC 不是稳定身份，轮换后无法串联。');
    out.push('- 特征 / OUI / 公司 / UUID 匹配都是**假设**，不是序列号、机主或追踪器存在的证据。');
    out.push('- GPS 时间戳是**操作者手机**在听到它时的位置，不是这台设备的位置。');
    out.push('- RSSI 是在手机处的响度，不是测得的距离。');
    out.push('- 不要编造转储里没有的字段。数据薄弱时就说薄弱，并说明还需要什么。');
    out.push('- 不要声称这台设备在跟踪任何人。不要给安全建议。');
    out.push('- 把这段粘贴当作敏感信息处理（MAC、SSID、载荷、GPS）。');
    out.push('');
    out.push('## 采集上下文');
    out.push('- 工具: Fieldwatch（鸿蒙版），仅接收，不关联、不注入、不上云。');
    out.push('- 主题: ' + this.describeName(sighting) + '。');
    out.push('- 本次会话命中次数: ' + sighting.count.toString() + '。');
    out.push('- 随机 MAC: ' + (this.isRandomizedAddress(sighting.address) ? '是' : '否') + '。');
    out.push('');
    out.push('## 观测转储（与详情页逐字一致）');
    out.push('');
    out.push(this.detailTextOf(sighting, signatureNames));
    out.push('');
    out.push('## 你的分析（必须包含以下小节）');
    out.push('1. **它最可能是什么** —— 产品类别、可能的品牌/系列、可能的型号。给出 0–100 的置信度。');
    out.push('2. **注册表 / 格式解码** —— IEEE OUI 或 CID；蓝牙 SIG 公司；GAP Appearance；16 位 UUID。');
    out.push('3. **这类产品通常做什么** —— 手机、标签、音箱、车机、AP、摄像头等，以及典型射频行为。');
    out.push('4. **Fieldwatch 实际看到了什么、看不到什么** —— 平台限制。');
    out.push('5. **信号与在场** —— 此处响度；会话内的 RSSI 范围；在空中的时段。**不要把 RSSI 换算成米。**');
    out.push('6. **特征匹配** —— 命中的特征当作筛选命中，不是身份。说明载荷是否支持这个匹配。');
    out.push('7. **待解问题** —— 还需要什么额外观测才能提高或降低置信度。');
    out.push('8. **不能得出的结论** —— 简明列出转储**不**支持的结论（机主、跟踪、法律身份、距离）。');
    out.push('');
    out.push('最后用一行给出**要点**（这台无线电最可能是什么，以及下一步该查什么）。不要给安全建议。');
    return out.join(nl);
  }

  /** 地址是否为随机 / 隐私地址（本地管理位置位且非多播）。 */
  isRandomizedAddress(mac: string): boolean {
    const hex: string = mac.replace(/[^A-Fa-f0-9]/g, '');
    if (hex.length < 2) return false;
    const first: number = parseInt(hex.substring(0, 2), 16);
    if (isNaN(first)) return false;
    return (first & 0x02) !== 0 && (first & 0x01) === 0;
  }

  /** 对单台设备做签名族判定（详情页「特征族」）。 */
  assessFamilyFor(sighting: Sighting, matchedNames: string[]): SignatureFamilyHint {
    return this.candidateEngine.assessFamily(sighting, this.state.sightings, matchedNames);
  }

  /** 名称库只读访问（详情页的解释层要用 appearance / company / serviceUuid）。 */
  radioDbRef(): FieldwatchRadioDb { return this.radioDb; }

  /**
   * 该设备的厂商名；查不到返回空串。
   *
   * 走 `RadioDb.vendorFor` 这条**唯一**的解析链，与 `facts.manufacturer` 同源 ——
   * 分类页的品牌分组、详情页标题、详情文本转储都读它，
   * 因此不会再出现「列表里有品牌、分类页却归到未知品牌」的分裂。
   */
  vendorOfSighting(sighting: Sighting): string {
    return this.radioDb.vendorFor(sighting.facts.manufacturer, sighting.address, sighting.facts.manufacturerId);
  }

  appearanceName(value: number): string {
    return this.radioDb.isReady() ? this.radioDb.appearance(value) : '';
  }
  /** 服务 UUID -> 名称；查不到返回空串。 */
  serviceUuidName(uuid: string): string {
    return this.radioDb.isReady() ? this.radioDb.serviceUuid(uuid) : '';
  }
  /** 3 字节 OUI -> 厂商名；查不到返回空串。 */
  vendorForOui(oui: string): string {
    return this.radioDb.isReady() ? this.radioDb.vendorForOui24(oui) : '';
  }
  /** 蓝牙公司 ID -> 名称；查不到返回空串。 */
  companyName(id: number): string {
    return this.radioDb.isReady() ? this.radioDb.company(id) : '';
  }

  /** 上次输出观测汇总的时间与各类计数。 */
  private lastIngestLogAt: number = 0;
  /** 上次淘汰的时间戳，用于节流。 */
  private lastEvictAt: number = 0;
  /**
   * 退到后台前是否处于扫描态 —— 回前台时据此决定要不要重启扫描。
   *
   * **这是必须的**：鸿蒙在应用真正进入后台时会自行暂停 BLE 扫描，
   * 但回到前台时**不会**自动恢复。实测（真后台 → 回前台 70 秒）：
   * 渲染恢复（`ForEach 142`）而 `观测接收汇总` 为 0、`无线电状态` 为 0，
   * 即**雷达冻住、再也收不到新设备**。
   */
  private resumeScanOnForeground: boolean = false;
  private ingestCounts: Map<string, number> = new Map<string, number>();
  /**
   * 观测接收汇总日志：每 30 秒一条，给出各类无线电这期间收到的条数。
   *
   * 逐条打日志会淹没有用信息，完全不打又无法验证「链路是否活着」；
   * 折中是低频汇总 —— 既有证据，又不干扰。
   */
  private logIngestThrottled(kind: RadioKind): void {
    const previous: number = this.ingestCounts.get(kind) ?? 0;
    this.ingestCounts.set(kind, previous + 1);
    const now: number = Date.now();
    if (now - this.lastIngestLogAt < 30000) return;
    this.lastIngestLogAt = now;
    const parts: string[] = [];
    this.ingestCounts.forEach((count: number, key: string): void => { parts.push(key + '=' + count.toString()); });
    // 一并给出**实时列表条数**：这是判断淘汰是否生效的唯一可观测指标。
    // 只报「收到了多少」会看不出列表有没有被压住（收到一万条但列表稳定在 400 才是对的）。
    logger.debug(TAG, '观测接收汇总(约30秒): ' + parts.join(', ')
      + ' | 实时列表 ' + this.state.sightings.length.toString() + ' 条');
    this.ingestCounts = new Map<string, number>();
  }
  /** 追加一条内存日志，超出上限时丢弃最旧的（见 MAX_LOG_ENTRIES 的说明）。 */
  private appendLogEntry(entry: LogEntry): void {
    this.state.logs.push(entry);
    const overflow: number = this.state.logs.length - FieldwatchApplication.MAX_LOG_ENTRIES;
    if (overflow > 0) this.state.logs.splice(0, overflow);
  }
  /** 相位变化日志；相同相位重复上报时静默，避免淹没其他无线电的日志。 */
  private logRadioPhase(snapshot: RadioSourceSnapshot): void {
    const previous: string | undefined = this.lastLoggedPhase.get(snapshot.kind);
    if (previous === snapshot.phase) return;
    this.lastLoggedPhase.set(snapshot.kind, snapshot.phase);
    logger.info(TAG, '无线电状态 kind=' + snapshot.kind + ', phase=' + snapshot.phase
      + ', fresh=' + snapshot.fresh.toString() + ', count=' + snapshot.resultCount.toString());
  }
  // ── 实时列表淘汰（原版 data/DeviceStore.kt）──
  //
  // **此前我们完全没有淘汰逻辑**：`state.sightings` 只增不减，
  // 只有 RDB 侧限了 5000 条，内存里就能一路涨到 5000。
  // 而原版稳态是 **400**、绝对上限 **900** —— 这正是「雷达上的内容越来越多、
  // 比安卓原版多好几倍且不停上升」的原因。
  //
  // （我们自己的 AI 导出文案里早就写着「Live RAM cap is about 400 radios;
  //   unnamed BLE evicts after ~3 min」，却从没实现过。文档写了不等于做了。）

  /** 匿名设备（没有命中任何签名）的淘汰年龄：3 分钟。 */
  static readonly EVICT_ANON_MS: number = 3 * 60 * 1000;
  /** 已知设备（命中过签名）的淘汰年龄：15 分钟。 */
  static readonly EVICT_NAMED_MS: number = 15 * 60 * 1000;
  /** 稳态上限：超过后先淘汰「匿名且已超期」的。 */
  static readonly MAX_LIVE_SIGHTINGS: number = 400;
  /** 绝对上限：无论是否匿名，都不允许超过这个数量。 */
  static readonly HARD_LIVE_SIGHTINGS: number = 900;
  /** 判定「还需保留」的滞留窗口，与原版 live 列表的 linger 对齐。 */
  private static readonly LIVE_LINGER_MS: number = 45000;

  /**
   * 实时列表淘汰。**移植自原版 `DeviceStore.refreshLocked` + `evictOverflow`**。
   *
   * 两级：
   *   ① 按年龄：匿名 3 分钟、已知 15 分钟没有再次听到就移除；
   *   ② 按容量：超过 400 先淘汰「匿名且超过滞留窗口」的（最旧优先）；
   *      仍超过 900 再淘汰匿名中非「人群固定」的；再超则无条件淘汰最旧的。
   *
   * 节流调用：观测以每秒几十条的速率到达，逐条扫全表代价过高。
   */
  private evictSightings(now: number): void {
    const all: Sighting[] = this.state.sightings;
    if (all.length === 0) return;
    // ⓪ 先刷新在场状态（对齐原版 `DeviceStore` 的 gone 扫描）。
    //
    // **必须在淘汰之前做**：淘汰会把老设备整条移走，
    // 而走开扫描要把它们的在场时段**关闭**（`end = lastSeen`）——
    // 顺序反了的话，那些设备会带着一条「永远开放」的时段离开。
    const linger: number = FieldwatchApplication.LIVE_LINGER_MS;
    all.forEach((item: Sighting): void => { item.refreshPresence(now, linger); });
    // ① 按年龄淘汰
    const kept: Sighting[] = all.filter((item: Sighting): boolean => {
      const cut: number = item.signatureIds.length > 0
        ? FieldwatchApplication.EVICT_NAMED_MS : FieldwatchApplication.EVICT_ANON_MS;
      return item.lastSeen >= now - cut;
    });
    if (kept.length <= FieldwatchApplication.MAX_LIVE_SIGHTINGS) {
      if (kept.length !== all.length) {
        this.state.sightings = kept;
        logger.info(TAG, '实时列表按年龄淘汰，剩余 ' + kept.length.toString() + ' 条');
      }
      return;
    }
    // ② 容量淘汰：按原版的优先级依次排出候选，取够为止。
    const byOldest = (a: Sighting, b: Sighting): number => a.lastSeen - b.lastSeen;
    const unnamed: Sighting[] = kept.filter((item: Sighting): boolean => item.signatureIds.length === 0);
    const named: Sighting[] = kept.filter((item: Sighting): boolean => item.signatureIds.length > 0);
    const candidates: Sighting[] = [];
    // 第一优先：匿名且已超过滞留窗口（最旧优先）
    unnamed.filter((item: Sighting): boolean => now - item.lastSeen > linger)
      .sort(byOldest).forEach((item: Sighting): void => { candidates.push(item); });
    // 第二优先：其余匿名（最旧优先）
    unnamed.filter((item: Sighting): boolean => now - item.lastSeen <= linger)
      .sort(byOldest).forEach((item: Sighting): void => { candidates.push(item); });
    // 最后才动已命名的设备（最旧优先）—— 它们是有识别价值的，尽量保留
    named.sort(byOldest).forEach((item: Sighting): void => { candidates.push(item); });
    // 目标：先降到稳态上限；只有当匿名设备已经淘无可淘时，才继续降到绝对上限。
    const floorCount: number = unnamed.length >= kept.length - FieldwatchApplication.MAX_LIVE_SIGHTINGS
      ? FieldwatchApplication.MAX_LIVE_SIGHTINGS : FieldwatchApplication.HARD_LIVE_SIGHTINGS;
    const target: number = kept.length > FieldwatchApplication.HARD_LIVE_SIGHTINGS
      ? Math.min(floorCount, FieldwatchApplication.HARD_LIVE_SIGHTINGS) : FieldwatchApplication.MAX_LIVE_SIGHTINGS;
    const victims: Set<string> = new Set<string>();
    for (let index: number = 0; index < candidates.length; index += 1) {
      if (kept.length - victims.size <= target) break;
      victims.add(candidates[index].key);
    }
    if (victims.size === 0) return;
    this.state.sightings = kept.filter((item: Sighting): boolean => !victims.has(item.key));
    logger.info(TAG, '实时列表容量淘汰: ' + victims.size.toString() + ' 条，剩余 '
      + this.state.sightings.length.toString() + ' 条（上限 ' + target.toString() + '）');
  }

  /**
   * 内存里的观测记录。
   *
   * **必须封顶**：它对每条观测都 push 一次（实测约 100 条/秒），
   * 而 `LogEntry` 持有 `ScanObservation` 引用 —— 不封顶就是每秒 100 个对象
   * 永不回收，实测堆以约 18 MB/分单调增长。
   *
   * 原版把日志**写到磁盘**（`data/LogStore.kt` 的 `filesDir/logs`）并做轮转，
   * 内存里不留全量，这里按同样思路只保留最近的一段。
   *
   * 目前这个数组**没有消费方**（页面只用过 `state.logs.length`，而那个值也没有被渲染），
   * 真正的持久化在 `observationRepository`（RDB，上限 5000）。
   * 保留字段是为了不破坏 `clearObservationLog()` 的既有语义。
   */
  private static readonly MAX_LOG_ENTRIES: number = 1000;

  clipDeviceLabel(name: string): string {
    const trimmed: string = name.trim().substring(0, FieldwatchApplication.MAX_DEVICE_LABEL);
    return trimmed.length === 0 ? 'Radio' : trimmed;
  }
  /** 原版 RadioBookmarks.clipNotes：去空格 → 截断（不填默认值）。 */
  clipDeviceNote(text: string): string {
    return text.trim().substring(0, FieldwatchApplication.MAX_DEVICE_NOTE);
  }

  /** 该设备的自定义名称；没有返回空串。 */
  deviceLabel(deviceKey: string): string {
    const target: WatchTarget | undefined = this.state.watchlist.find((item: WatchTarget): boolean => item.deviceKey === deviceKey);
    return target === undefined ? '' : target.label;
  }
  /** 该设备的观察者备注；没有返回空串。 */
  deviceNote(deviceKey: string): string {
    const target: WatchTarget | undefined = this.state.watchlist.find((item: WatchTarget): boolean => item.deviceKey === deviceKey);
    return target === undefined ? '' : target.note;
  }
  /**
   * 原版 RadioBookmarks.canSetCustomName：**BLE 随机地址不允许命名**。
   *
   * 随机地址会轮换，名字会绑死在一个再也听不到的键上 —— 让用户以为设备还在。
   * Wi-Fi 永远可以命名（本地管理位的 BSSID 通常稳定）。
   */
  canSetCustomName(sighting: Sighting): boolean {
    if (sighting.kind !== RadioKind.BLE) return true;
    return sighting.facts.addressType.toLowerCase() !== 'random';
  }
  /**
   * 原版 RadioBookmarks.suggestLabel：默认名取设备标题，取不到则用 MAC 后 8 位。
   */
  suggestDeviceLabel(sighting: Sighting): string {
    const title: string = sighting.name.trim();
    if (title.length > 0) return this.clipDeviceLabel(title);
    const compact: string = sighting.address.replace(/[^0-9A-Fa-f]/g, '');
    return this.clipDeviceLabel(compact.length >= 8 ? compact.substring(compact.length - 8) : compact);
  }
  /**
   * 写入自定义名称。对应原版 upsertName(alertIfNew = false)。
   *
   * 已存在条目只改 label；新建条目时 alert 保持 false。
   */
  upsertDeviceLabel(deviceKey: string, name: string): void {
    const label: string = this.clipDeviceLabel(name);
    const existing: WatchTarget | undefined = this.state.watchlist.find((item: WatchTarget): boolean => item.deviceKey === deviceKey);
    if (existing !== undefined) {
      existing.label = label;
    } else {
      this.state.watchlist.push(new WatchTarget(deviceKey, '', label, false, ''));
    }
    this.settingsRepository.saveWatchlist(this.state.watchlist);
  }
  /**
   * 写入观察者备注。对应原版 upsertNotes。
   *
   * 没有条目且备注为空时**什么都不做** —— 原版在这里直接 return watchlist，
   * 避免为一条空备注凭空建出关注条目。
   */
  upsertDeviceNote(deviceKey: string, note: string, suggestLabel: string): void {
    const clipped: string = this.clipDeviceNote(note);
    const existing: WatchTarget | undefined = this.state.watchlist.find((item: WatchTarget): boolean => item.deviceKey === deviceKey);
    if (existing !== undefined) {
      existing.note = clipped;
    } else {
      if (clipped.length === 0) return;
      this.state.watchlist.push(new WatchTarget(deviceKey, '', this.clipDeviceLabel(suggestLabel), false, clipped));
    }
    this.settingsRepository.saveWatchlist(this.state.watchlist);
  }

  /**
   * 把 OUI 厂商名补到观测上。
   *
   * `RadioFacts.manufacturer` 此前**从未被填充过** —— 所有构造点都传空串，
   * 于是依赖它的地方全部静默失效：
   *   - 候选引擎的厂商排除（芯片模组厂商、已知噪声 OUI）拿到空串，等于没生效；
   *   - 详情页与导出看不到厂商。
   *
   * 名称库本身是完整的（MA-L 39995 条 / 34781 个名称），只是从没人把结果写进去。
   * 放在 ingest 入口：覆盖全部信号源、全部路径（含定位标记分支与恢复分支）。
   *
   * 解析链本身在 `RadioDb.vendorFor` —— **只写一遍**。此前这条链在本方法、
   * `vendorOfSighting` 与筛选引擎的 `vendorOf` 里各写了一份且口径不同
   * （这里两级、那两处一级），结果就是列表里看得到品牌、
   * 分类页的品牌分组却整片落进「未知品牌」。
   */
  private attachVendor(observation: ScanObservation): void {
    if (observation.facts.manufacturer.length > 0) return;
    const vendor: string = this.radioDb.vendorFor('', observation.address, observation.facts.manufacturerId);
    if (vendor.length > 0) observation.facts.manufacturer = vendor;
  }
  private ingest(observation: ScanObservation): void {
    this.attachVendor(observation);
    if (this.state.settings.locationTagging) { void this.ingestWithLocation(observation); return; }
    this.ingestNow(observation);
  }

  private async ingestWithLocation(observation: ScanObservation): Promise<void> {
    const location: GpsSample | undefined = await this.getCurrentLocationSample();
    if (location !== undefined) {
      observation.location = location;
      this.recordTravelSample(location);
    }
    this.ingestNow(observation);
  }
  /**
   * 把本机定位样本追加到轨迹，并同步给筛选引擎。
   * 「与你同行」判定依赖这条轨迹（原版 CoTravel 用的是手机自身的移动轨迹）。
   */
  private recordTravelSample(sample: GpsSample): void {
    const samples: GpsSample[] = this.travelSamples.slice();
    const last: GpsSample | undefined = samples.length === 0 ? undefined : samples[samples.length - 1];
    // 同一个点重复追加没有意义，还会把轨迹长度算成 0 位移的噪声
    if (last !== undefined && last.latitude === sample.latitude && last.longitude === sample.longitude) return;
    samples.push(sample);
    while (samples.length > TRAVEL_SAMPLE_LIMIT) samples.shift();
    this.setTravelSamples(samples);
  }
  /** 本机轨迹的当前长度（米），供筛选页状态行与轨迹画布使用。 */
  travelPathMeters(): number { return this.geoService.pathLengthMeters(this.travelSamples); }
  travelTrack(): GpsSample[] { return this.travelSamples.slice(); }
  private async getCurrentLocationSample(): Promise<GpsSample | undefined> {
    const now: number = Date.now();
    if (this.cachedLocation !== undefined && now - this.cachedLocation.at < this.locationTtlMs) return this.cachedLocation;
    if (this.locationRequest !== undefined) return await this.locationRequest;
    this.locationRequest = this.readCurrentLocation();
    const result: GpsSample | undefined = await this.locationRequest;
    this.locationRequest = undefined;
    if (result !== undefined) this.cachedLocation = result;
    return result;
  }

  private async readCurrentLocation(): Promise<GpsSample | undefined> {
    const location = await ngfLocationManagerFacade.getCurrentLocation();
    return location === null ? undefined : new GpsSample(location.latitude, location.longitude, Date.now());
  }

  private ingestNow(observation: ScanObservation): void {
    // **不要逐条观测打日志**：BLE 稳态约 17~31 条/秒，每条一行 debug 会在几秒内
    // 把整个日志环形缓冲冲干净 —— Wi-Fi 与星闪的启动行被挤掉后，
    // 排查时看起来像「那两个无线电没启动」，实际只是日志被淹。
    // 需要「收到了多少」时看下面的汇总行，它每 30 秒给一次累计量。
    this.logIngestThrottled(observation.kind);
    const context: SignatureMatchContext = signatureContextOfObservation(observation);
    const matched: string[] = this.fleetEngine.matchContext(context, this.state.signatures);
    const decoded: DecodedFieldValue[] = this.decodeFields(matched, context);
    const hunt: HuntSession | undefined = this.huntSession;
    if (hunt !== undefined && hunt.targetKey === observation.key) hunt.addSample(observation.rssi, observation.seenAt);
    // 反追踪需要 (时间, 强度) 序列，与 Hunt 各自独立。
    this.recordDeviceSample(observation.key, observation.seenAt, observation.rssi);
    const existing: Sighting | undefined = this.state.sightings.find((item: Sighting): boolean => item.key === observation.key);
    if (existing === undefined) { const sighting: Sighting = Sighting.fromObservation(observation); sighting.signatureIds = matched; sighting.decodedFields = decoded; this.state.sightings.push(sighting); this.notifyWatched(sighting); }
    else { existing.ingest(observation); existing.signatureIds = matched; existing.decodedFields = decoded; }
    this.sequence += 1;
    this.appendLogEntry(new LogEntry('log-' + this.sequence.toString(), observation, matched));
    void this.observationRepository.append(observation);
    // 淘汰节流：观测每秒几十条，逐条扫全表代价过高；5 秒一次足够跟上。
    const nowMs: number = Date.now();
    if (nowMs - this.lastEvictAt >= 5000) {
      this.lastEvictAt = nowMs;
      this.evictSightings(nowMs);
    }
  }

  private notifyWatched(sighting: Sighting): void {
    if (!this.state.settings.watchNotifications) return;
    const watched: boolean = this.state.watchlist.some((target: WatchTarget): boolean => this.watchTargetHits(target, sighting));
    if (!watched) return;
    if (this.watchedNotificationIds.has(sighting.key)) return;
    const name: string = sighting.name.length > 0 ? sighting.name : sighting.address;
    const context = uiContextManager.getFullAbilityContext();
    const title: string = context === null ? '' : resolveResourceString(context, $r('app.string.fieldwatch_notification_title'));
    const prefix: string = context === null ? '' : resolveResourceString(context, $r('app.string.fieldwatch_notification_watched')) + ': ';
    const notificationId: number = this.nextNotificationId;
    this.nextNotificationId += 1;
    this.watchedNotificationIds.set(sighting.key, notificationId);
    const request: NGFNotificationRequest = new NGFNotificationRequest(notificationId, title, prefix + name, NGFNotificationType.BASIC);
    void ngfSystemNotificationManager.publish(request);
    this.alertOnWatched(sighting);
  }

  /**
   * 关注设备的可听告警（§7.2「声音提示/Beep」「语音提示」）。
   *
   * 由总开关 `watchNotifications` 把关（调用点已早退），蜂鸣与语音各自再受子开关控制。
   * 与 Hunt 的 geiger tick 是两套独立告警：这里是**双响**，Hunt 是随距离变化的单次短促 tick。
   */
  private alertOnWatched(sighting: Sighting): void {
    const beep: boolean = this.state.settings.watchBeep;
    const voice: boolean = this.state.settings.watchVoice;
    if (!beep && !voice) return;
    if (beep) this.watchAlert.doublePip();
    if (voice) {
      this.watchAlert.speak(this.watchedClassName(sighting), this.watchedSignatureName(sighting),
        parseVoiceWhat(this.state.settings.watchVoiceWhat));
    }
  }

  /** 语音里的「类别」：优先签名类别名，没有签名时退化为无线电类型。 */
  private watchedClassName(sighting: Sighting): string {
    const fleet: SignatureFleet | undefined = this.fleetOfSighting(sighting);
    if (fleet !== undefined) {
      const context = uiContextManager.getFullAbilityContext();
      if (context !== null) return resolveResourceString(context, signatureClassLabel(fleet.category));
    }
    // 语音会念出来，属于用户可听内容，同样走资源。
    const ctx = uiContextManager.getFullAbilityContext();
    if (ctx === null) return 'Wi-Fi';
    if (sighting.kind === RadioKind.WIFI) return resolveResourceString(ctx, $r('app.string.fieldwatch_radio_wifi'));
    if (sighting.kind === RadioKind.NEARLINK) return resolveResourceString(ctx, $r('app.string.fieldwatch_radio_nearlink'));
    return resolveResourceString(ctx, $r('app.string.fieldwatch_radio_ble'));
  }

  /** 语音里的「签名」：命中签名的名称。 */
  private watchedSignatureName(sighting: Sighting): string {
    const fleet: SignatureFleet | undefined = this.fleetOfSighting(sighting);
    return fleet === undefined ? '' : fleet.name;
  }

  /** 取该设备命中的第一个签名。 */
  private fleetOfSighting(sighting: Sighting): SignatureFleet | undefined {
    for (let index: number = 0; index < sighting.signatureIds.length; index += 1) {
      const id: string = sighting.signatureIds[index];
      const found: SignatureFleet | undefined = this.state.signatures.find((item: SignatureFleet): boolean => item.id === id);
      if (found !== undefined) return found;
    }
    return undefined;
  }

  /** 「测试声音/语音」用：按当前设置立刻响一次，不需要真的有设备出现。 */
  playAlertTest(): void {
    this.watchAlert.doublePip();
    if (this.state.settings.watchVoice) {
      this.watchAlert.speak('测试设备', '测试签名', parseVoiceWhat(this.state.settings.watchVoiceWhat));
    }
  }

  /** 预热告警的音频与语音引擎；设置页打开或开启语音时调用，避免首次告警是哑的。 */
  prepareAlert(wantVoice: boolean): void {
    void this.watchAlert.prepare(wantVoice);
  }
  /** 设置器：蜂鸣开关。 */
  setWatchBeep(enabled: boolean): void {
    this.state.settings.watchBeep = enabled;
    this.settingsRepository.save(this.state.settings);
    if (enabled) this.prepareAlert(false);
  }
  /** 设置器：语音开关；开启时顺带预热引擎。 */
  setWatchVoice(enabled: boolean): void {
    this.state.settings.watchVoice = enabled;
    this.settingsRepository.save(this.state.settings);
    if (enabled) this.prepareAlert(true);
  }
  /** 设置器：语音内容（class / signature / classSignature）。 */
  setWatchVoiceWhat(value: string): void {
    this.state.settings.watchVoiceWhat = value;
    this.settingsRepository.save(this.state.settings);
  }
  /** 设置器：§12.2 的四个列表显示开关。 */
  setShowRssiBar(value: boolean): void {
    this.state.settings.showRssiBar = value;
    this.settingsRepository.save(this.state.settings);
  }
  setShowFleetName(value: boolean): void {
    this.state.settings.showFleetName = value;
    this.settingsRepository.save(this.state.settings);
  }
  setShowFrequency(value: boolean): void {
    this.state.settings.showFrequency = value;
    this.settingsRepository.save(this.state.settings);
  }
  setShowSeenTimes(value: boolean): void {
    this.state.settings.showSeenTimes = value;
    this.settingsRepository.save(this.state.settings);
  }
  /** 列表行密度：四个视图共用同一套行样式，只切换尺寸档。 */
  setListCompactRows(value: boolean): void {
    this.state.settings.listCompactRows = value;
    this.settingsRepository.save(this.state.settings);
  }
  /** 设置器：Hunt 页 geiger tick 声音（§12.3）。 */
  setHuntBeep(enabled: boolean): void {
    this.state.settings.huntBeep = enabled;
    this.settingsRepository.save(this.state.settings);
  }
  /** 设置器：Hunt 页 geiger tick 触感。 */
  setHuntVibrate(enabled: boolean): void {
    this.state.settings.huntVibrate = enabled;
    this.settingsRepository.save(this.state.settings);
  }
  /** 供设置页显示能力可用性：语音引擎是否就绪。 */
  alertVoiceAvailable(): boolean { return this.watchAlert.voiceAvailable(); }
  alertSoundAvailable(): boolean { return this.watchAlert.soundAvailable(); }

  private async restoreRecentObservations(): Promise<void> {
    if (this.restoreStarted) return;
    this.restoreStarted = true;
    const stored: Array<FieldwatchStoredObservation> = await this.observationRepository.loadRecent();
    if (stored.length === 0) return;
    const seenKeys: Map<string, boolean> = new Map();
    stored.reverse().forEach((item: FieldwatchStoredObservation): void => {
      const facts: RadioFacts = new RadioFacts(item.ssid, '', item.frequencyMhz, [], '', item.band, item.channelWidth, item.securityType, item.ssid.length === 0);
      const observation: ScanObservation = new ScanObservation(item.key, item.kind, item.address, item.name, item.rssi, item.seenAt, facts, undefined, item.fresh);
      const existing: Sighting | undefined = this.state.sightings.find((sighting: Sighting): boolean => sighting.key === observation.key);
      if (existing === undefined) {
        // 恢复出来的观测也要补厂商：旧记录是在填充逻辑存在之前写下的。
      this.attachVendor(observation);
      const restored: Sighting = Sighting.fromObservation(observation);
        this.state.sightings.push(restored);
      } else {
        existing.ingest(observation);
      }
      if (!seenKeys.has(observation.key)) {
        seenKeys.set(observation.key, true);
        this.sequence += 1;
        this.appendLogEntry(new LogEntry('restored-' + this.sequence.toString(), observation, []));
      }
    });
    logger.info(TAG, '已恢复本地观测: ' + stored.length.toString() + ' 条');
  }

  private scanInterval(): number {
    if (this.state.settings.scanIntensity === 'basic') return 30000;
    if (this.state.settings.scanIntensity === 'saver') return 60000;
    return 45000;
  }

  private buildCoordinator(): FieldwatchObservationCoordinator {
    const scanners: Array<IFieldwatchRadioScanner> = [];
    scanners.push(new FieldwatchBleScanner());
    scanners.push(new FieldwatchWifiScanner(undefined, undefined, this.scanInterval()));
    // 星闪只在设备支持时接入。不支持时不加入协调器 ——
    // 既不扫描、也不会触发权限申请，UI 上也不会有任何星闪入口。
    if (this.nearLinkSupported) scanners.push(new FieldwatchNearLinkScanner());
    return new FieldwatchObservationCoordinator(scanners);
  }

  private decodeFields(matched: string[], context: SignatureMatchContext): DecodedFieldValue[] {
    const values: DecodedFieldValue[] = [];
    matched.forEach((id: string): void => {
      const fleet: SignatureFleet | undefined = this.state.signatures.find((item: SignatureFleet): boolean => item.id === id);
      if (fleet === undefined) return;
      this.fieldDecoder.decode(fleet, context).forEach((value: DecodedFieldValue): void => { values.push(value); });
    });
    return values;
  }
}

export const fieldwatchApplication: FieldwatchApplication = new FieldwatchApplication();
