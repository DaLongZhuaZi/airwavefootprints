import { BusinessError } from '@kit.BasicServicesKit';
import { Permissions } from '@kit.AbilityKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { logger, ngfLocationManagerFacade, ngfPermissionManagerFacade } from 'ngf_framework';
import { RadioFacts, RadioKind, RadioSourceSnapshot, ScanObservation, ScanState, ServiceDataRecord, WifiScanPhase } from '../domain/FieldwatchModels';
import { IFieldwatchRadioScanner } from './FieldwatchRadioScanner';

const TAG: string = 'FieldwatchWifiScanner';
const SYSTEM_REJECTED: number = 2501000;
const WIFI_DISABLED: number = 2501001;
const PERMISSION_DENIED: number = 201;
const UNSUPPORTED: number = 801;

export interface IFieldwatchWifiPlatform {
  isWifiActive(): boolean;
  isLocationEnabled(): boolean;
  startScan(): void;
  getScanInfoList(): Array<wifiManager.WifiScanInfo>;
  onScanStateChange(callback: (state: number) => void): void;
  offScanStateChange(callback: (state: number) => void): void;
}

export interface IFieldwatchWifiPermissionChecker {
  check(permission: Permissions): boolean;
}

export class HarmonyWifiPlatform implements IFieldwatchWifiPlatform {
  isWifiActive(): boolean { return wifiManager.isWifiActive(); }
  isLocationEnabled(): boolean { return ngfLocationManagerFacade.isLocationEnabled(); }
  startScan(): void { wifiManager.startScan(); }
  getScanInfoList(): Array<wifiManager.WifiScanInfo> { return wifiManager.getScanInfoList(); }
  onScanStateChange(callback: (state: number) => void): void { wifiManager.on('wifiScanStateChange', callback); }
  offScanStateChange(callback: (state: number) => void): void { wifiManager.off('wifiScanStateChange', callback); }
}

export class WifiScanSnapshot {
  public results: Array<ScanObservation> = [];
  public capturedAt: number = 0;
  public fresh: boolean = false;
  public phase: WifiScanPhase = WifiScanPhase.IDLE;
  public nextAttemptAt: number = 0;
  public lastErrorCode: number = 0;
  public lastErrorMessage: string = '';
}

export class FieldwatchWifiScanner implements IFieldwatchRadioScanner {
  /** 退避上限（原版为 45 秒：系统节流时再快也没用）。 */
  static readonly BACKOFF_CAP_MS: number = 45000;
  /** 退避基数（原版 8 秒，之后逐次翻倍）。 */
  static readonly BACKOFF_BASE_MS: number = 8000;
  /**
   * 第 n 次连续失败后的退避延迟：`min(45s, 8s * 2^(n-1))` → 8/16/32/45/45…
   *
   * **刻意做成静态纯函数**：这段梯级是原版明确契约，
   * 但梯级推进依赖真实定时器（8+16+32 秒），单测等不起；
   * 内联在失败处理里就等于这段契约**没有任何测试能锁住**。
   * 抽出来之后可以逐级断言，行为完全不变。
   */
  static backoffDelayFor(failureCount: number): number {
    if (failureCount < 1) return FieldwatchWifiScanner.BACKOFF_BASE_MS;
    const raw: number = FieldwatchWifiScanner.BACKOFF_BASE_MS * Math.pow(2, failureCount - 1);
    return Math.min(FieldwatchWifiScanner.BACKOFF_CAP_MS, raw);
  }
  public state: ScanState = ScanState.IDLE;
  public readonly kind: RadioKind = RadioKind.WIFI;
  private readonly platform: IFieldwatchWifiPlatform;
  private readonly permissionChecker: IFieldwatchWifiPermissionChecker;
  private readonly scanIntervalMs: number;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;
  private stateHandler: ((snapshot: RadioSourceSnapshot) => void) | undefined;
  private eventSubscribed: boolean = false;
  private awaitingScan: boolean = false;
  private retryTimer: number = -1;
  private nextAttemptAt: number = 0;
  private failureCount: number = 0;
  private lastSuccessAt: number = 0;
  private lastErrorCode: number = 0;
  private lastErrorMessage: string = '';
  private phase: WifiScanPhase = WifiScanPhase.IDLE;
  private lastResults: Array<ScanObservation> = [];
  private lastSnapshot: RadioSourceSnapshot = new RadioSourceSnapshot(RadioKind.WIFI, WifiScanPhase.IDLE);

  constructor(platform: IFieldwatchWifiPlatform = new HarmonyWifiPlatform(), permissionChecker: IFieldwatchWifiPermissionChecker = new DefaultWifiPermissionChecker(), scanIntervalMs: number = 45000) {
    this.platform = platform;
    this.permissionChecker = permissionChecker;
    this.scanIntervalMs = scanIntervalMs;
  }

  getSnapshot(): RadioSourceSnapshot { return this.lastSnapshot; }
  getWifiSnapshot(): WifiScanSnapshot {
    const snapshot: WifiScanSnapshot = new WifiScanSnapshot();
    snapshot.results = this.lastResults.map((item: ScanObservation): ScanObservation => new ScanObservation(item.key, item.kind, item.address, item.name, item.rssi, item.seenAt, item.facts, item.location, this.lastSnapshot.fresh));
    snapshot.capturedAt = this.lastSuccessAt;
    snapshot.fresh = this.lastSnapshot.fresh;
    snapshot.phase = this.phase;
    snapshot.nextAttemptAt = this.nextAttemptAt;
    snapshot.lastErrorCode = this.lastErrorCode;
    snapshot.lastErrorMessage = this.lastErrorMessage;
    return snapshot;
  }

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void {
    if (this.eventSubscribed && this.state !== ScanState.IDLE) return;
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    this.stateHandler = onStateChange;
    this.clearRetryTimer();
    this.subscribe();
    this.phase = WifiScanPhase.PRECHECK;
    this.publishState();
    this.tryScan(false);
  }

  stop(): void {
    this.clearRetryTimer();
    if (this.eventSubscribed) {
      try { this.platform.offScanStateChange(this.onScanStateChange); } catch (error) { logger.warn(TAG, '取消 Wi-Fi 扫描监听失败: ' + this.errorMessage(error)); }
    }
    this.eventSubscribed = false;
    this.awaitingScan = false;
    this.observationHandler = undefined;
    this.errorHandler = undefined;
    this.stateHandler = undefined;
    this.state = ScanState.IDLE;
    this.phase = WifiScanPhase.IDLE;
    this.nextAttemptAt = 0;
    this.publishState();
  }

  retryNow(): void {
    if (this.state === ScanState.IDLE) return;
    this.clearRetryTimer();
    this.nextAttemptAt = 0;
    this.failureCount = 0;
    this.tryScan(true);
  }

  private subscribe(): void {
    if (this.eventSubscribed) return;
    try {
      this.platform.onScanStateChange(this.onScanStateChange);
      this.eventSubscribed = true;
    } catch (error) {
      this.handleFailureCode(this.codeOf(error), '注册 Wi-Fi 扫描状态监听失败');
    }
  }

  private tryScan(force: boolean): void {
    if (this.awaitingScan || this.state === ScanState.IDLE && this.observationHandler === undefined) return;
    const now: number = Date.now();
    if (!force && this.nextAttemptAt > now) {
      this.phase = WifiScanPhase.WAITING_FOR_RETRY;
      this.state = ScanState.ERROR;
      this.publishState();
      this.scheduleRetry(this.nextAttemptAt - now);
      return;
    }
    if (!this.permissionChecker.check('ohos.permission.GET_WIFI_INFO') || !this.permissionChecker.check('ohos.permission.SET_WIFI_INFO')) {
      this.handleFailureCode(PERMISSION_DENIED, 'Wi-Fi 信息权限未授予，请重新授权');
      return;
    }
    if (!this.platform.isWifiActive()) {
      this.handleFailureCode(WIFI_DISABLED, 'Wi-Fi 未开启，请先打开 Wi-Fi');
      return;
    }
    if (!this.platform.isLocationEnabled()) {
      this.lastErrorCode = 0;
      this.lastErrorMessage = '系统位置信息未开启，Wi-Fi 扫描需要位置服务';
      this.nextAttemptAt = 0;
      this.phase = WifiScanPhase.LOCATION_DISABLED;
      this.state = ScanState.ERROR;
      this.publishState();
      return;
    }
    this.emitCachedResults();
    this.awaitingScan = true;
    this.phase = WifiScanPhase.SCANNING;
    this.state = ScanState.SCANNING;
    this.lastSnapshot = new RadioSourceSnapshot(this.kind, this.phase, this.lastSuccessAt, this.nextAttemptAt, false, this.lastErrorCode, this.lastErrorMessage, this.lastResults.length);
    this.publishState();
    logger.info(TAG, '请求 Wi-Fi 扫描: nextAttemptAt=' + this.nextAttemptAt.toString());
    try {
      this.platform.startScan();
    } catch (error) {
      this.awaitingScan = false;
      this.handleFailure(error);
    }
  }

  private readonly onScanStateChange = (scanState: number): void => {
    if (!this.awaitingScan || this.observationHandler === undefined) return;
    logger.info(TAG, 'wifiScanStateChange=' + scanState.toString());
    if (scanState === 1) {
      this.awaitingScan = false;
      this.handleSuccess();
    } else {
      this.awaitingScan = false;
      this.handleFailureCode(SYSTEM_REJECTED, '系统暂时拒绝或节流 Wi-Fi 扫描');
    }
  };

  private handleSuccess(): void {
    try {
      const infos: Array<wifiManager.WifiScanInfo> = this.platform.getScanInfoList();
      const observations: Array<ScanObservation> = this.toObservations(infos, true);
      logger.info(TAG, 'Wi-Fi 扫描回调成功，结果数=' + observations.length.toString());
      this.failureCount = 0;
      this.lastErrorCode = 0;
      this.lastErrorMessage = '';
      this.nextAttemptAt = Date.now() + this.scanIntervalMs;
      if (observations.length > 0) {
        this.lastResults = observations;
        this.lastSuccessAt = Date.now();
        this.emitObservations(observations);
        this.phase = WifiScanPhase.READY;
        this.lastSnapshot = new RadioSourceSnapshot(this.kind, this.phase, this.lastSuccessAt, this.nextAttemptAt, true, 0, '', observations.length);
      } else {
        this.phase = this.lastResults.length > 0 ? WifiScanPhase.STALE : WifiScanPhase.READY;
        this.lastSnapshot = new RadioSourceSnapshot(this.kind, this.phase, this.lastSuccessAt, this.nextAttemptAt, false, 0, '', 0);
      }
      this.state = ScanState.SCANNING;
      this.publishState();
      this.scheduleRetry(this.scanIntervalMs);
    } catch (error) {
      this.handleFailure(error);
    }
  }

  private handleFailure(error: Object): void { this.handleFailureCode(this.codeOf(error), this.errorMessage(error)); }

  private handleFailureCode(code: number, message: string): void {
    this.lastErrorCode = code;
    this.lastErrorMessage = message;
    this.failureCount += 1;
    // 延迟公式抽成静态纯函数：原来内联在私有方法里，无法被单测锁定，
    // 而梯级要靠真实定时器（8+16+32 秒）推进，单测根本等不起 ——
    // 结果是「改掉公式不会有任何测试报警」。
    const delay: number = FieldwatchWifiScanner.backoffDelayFor(this.failureCount);
    if (code === PERMISSION_DENIED) this.phase = WifiScanPhase.PERMISSION_DENIED;
    else if (code === WIFI_DISABLED) this.phase = WifiScanPhase.WIFI_DISABLED;
    else if (code === UNSUPPORTED) this.phase = WifiScanPhase.UNSUPPORTED;
    else if (code === SYSTEM_REJECTED) { this.phase = WifiScanPhase.SYSTEM_REJECTED; }
    else this.phase = WifiScanPhase.ERROR;
    if (code === SYSTEM_REJECTED || code === 0) {
      this.phase = code === SYSTEM_REJECTED ? WifiScanPhase.WAITING_FOR_RETRY : this.phase;
      this.nextAttemptAt = Date.now() + delay;
      this.scheduleRetry(delay);
    } else {
      this.nextAttemptAt = 0;
    }
    this.state = ScanState.ERROR;
    this.publishState();
    logger.warn(TAG, 'Wi-Fi 扫描失败 code=' + code.toString() + ', message=' + message + ', nextAttemptAt=' + this.nextAttemptAt.toString());
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }

  private emitCachedResults(): void {
    if (this.lastResults.length === 0) return;
    const cached: Array<ScanObservation> = this.lastResults.map((item: ScanObservation): ScanObservation => new ScanObservation(item.key, item.kind, item.address, item.name, item.rssi, item.seenAt, item.facts, item.location, false));
    this.phase = WifiScanPhase.STALE;
    this.lastSnapshot = new RadioSourceSnapshot(this.kind, this.phase, this.lastSuccessAt, this.nextAttemptAt, false, this.lastErrorCode, this.lastErrorMessage, cached.length);
    this.emitObservations(cached);
  }

  private emitObservations(observations: Array<ScanObservation>): void { if (this.observationHandler !== undefined) observations.forEach((item: ScanObservation): void => { if (this.observationHandler !== undefined) this.observationHandler(item); }); }

  private toObservations(infos: Array<wifiManager.WifiScanInfo>, fresh: boolean): Array<ScanObservation> {
    const observations: Array<ScanObservation> = [];
    infos.forEach((info: wifiManager.WifiScanInfo): void => {
      if (info.bssid === undefined || info.bssid.length === 0) { logger.warn(TAG, '丢弃 BSSID 为空的 Wi-Fi 结果'); return; }
      const facts: RadioFacts = new RadioFacts(info.ssid, '', info.frequency, [], this.infoElementsHex(info.infoElems), info.band, info.channelWidth, info.securityType, info.ssid.length === 0, 0, [], this.vendorIeOuis(info.infoElems));
      // 详情页要、此前没采集的 Wi-Fi 字段。
      // `supportedRates` 鸿蒙不给（`WifiScanInfo` 里没有这个字段），只能留空。
      facts.capabilities = info.capabilities === undefined ? '' : info.capabilities;
      facts.centerFreq0 = info.centerFrequency0 === undefined ? 0 : info.centerFrequency0;
      facts.centerFreq1 = info.centerFrequency1 === undefined ? 0 : info.centerFrequency1;
      facts.vendorIeRecords = this.vendorIeRecords(info.infoElems);
      facts.wifiStandard = this.wifiCategoryLabel(info.supportedWifiCategory);
      // **`seenAt` 必须与 BLE 用同一时钟域（`Date.now()` 的 epoch 毫秒）。**
      //
      // 此前用的是 `info.timestamp`，但实测它不是 epoch 毫秒：
      //   info.timestamp = 738889649511  vs  Date.now() = 1791482622195
      // 比值 2.4（按纳秒解读恰为约 12 分钟开机时长）。
      // 后果：写进 RDB 的 `seen_at` 恒小于 BLE，在
      // `ORDER BY seen_at DESC LIMIT 5000` 的裁剪里排在最底 —— **Wi-Fi 观测写完就被删**。
      // 实测证据：`fieldwatch_observations` 5001 行全部是 `ble`，一条 `wifi` 都没有。
      observations.push(new ScanObservation('wifi:' + info.bssid, RadioKind.WIFI, info.bssid, info.ssid, info.rssi, Date.now(), facts, undefined, fresh));
    });
    return observations;
  }

  /** 提取厂商自定义 IE（element 221 / 0xDD）的 3 字节 OUI，用于 VENDOR_IE_OUI 签名规则。 */
  private vendorIeOuis(elements: Array<wifiManager.WifiInfoElem>): string[] {
    const result: string[] = [];
    if (elements === undefined) return result;
    elements.forEach((element: wifiManager.WifiInfoElem): void => {
      if (element.eid !== 221) return;
      const content: Uint8Array = element.content;
      if (content === undefined || content.length < 3) return;
      const oui: string = this.bytesHex(content.slice(0, 3));
      if (oui.length === 6 && result.indexOf(oui) < 0) result.push(oui);
    });
    return result;
  }

  /**
   * 厂商 IE 的完整记录：OUI + element type + 数据。
   *
   * 与 `vendorIeOuis` 的区别是**保留了 element type 与载荷** ——
   * 原版详情页会把 type 一起展示（`Vendor OUI xxxxxx type N`），
   * 只留 OUI 会丢掉「这条 IE 是干什么的」这一半信息。
   * 复用 ServiceDataRecord 作载体：uuid 位放 OUI，dataHex 放 type+载荷。
   */
  private vendorIeRecords(elements: Array<wifiManager.WifiInfoElem>): ServiceDataRecord[] {
    const result: ServiceDataRecord[] = [];
    if (elements === undefined) return result;
    elements.forEach((element: wifiManager.WifiInfoElem): void => {
      if (element.eid !== 221) return;
      const content: Uint8Array = element.content;
      if (content === undefined || content.length < 3) return;
      result.push(new ServiceDataRecord(this.bytesHex(content.slice(0, 3)), this.bytesHex(content.slice(3))));
    });
    return result;
  }

  /** Wi-Fi 代际标签。鸿蒙只给到 WifiCategory 枚举，映射成可读文字。 */
  private wifiCategoryLabel(category: number | undefined): string {
    if (category === undefined) return '';
    if (category === 2) return 'Wi-Fi 6';
    if (category === 3) return 'Wi-Fi 6+';
    if (category === 4) return 'Wi-Fi 7';
    return '';
  }

  private infoElementsHex(elements: Array<wifiManager.WifiInfoElem>): string {
    let result: string = '';
    elements.forEach((element: wifiManager.WifiInfoElem): void => { const id: string = element.eid.toString(16).toUpperCase(); result += (id.length === 1 ? '0' + id : id) + ':' + this.bytesHex(element.content); });
    return result;
  }

  private bytesHex(data: Uint8Array): string {
    const bytes: Uint8Array = data;
    let result: string = '';
    for (let index: number = 0; index < bytes.length; index += 1) { const value: string = bytes[index].toString(16).toUpperCase(); result += value.length === 1 ? '0' + value : value; }
    return result;
  }

  private scheduleRetry(delay: number): void {
    this.clearRetryTimer();
    if (this.observationHandler === undefined || delay <= 0) return;
    this.retryTimer = setTimeout((): void => { this.retryTimer = -1; this.tryScan(false); }, delay);
  }

  private clearRetryTimer(): void { if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; } }
  private publishState(): void { this.lastSnapshot = new RadioSourceSnapshot(this.kind, this.phase, this.lastSuccessAt, this.nextAttemptAt, this.phase === WifiScanPhase.READY && this.lastSnapshot.fresh, this.lastErrorCode, this.lastErrorMessage, this.lastResults.length); if (this.stateHandler !== undefined) this.stateHandler(this.lastSnapshot); }
  private codeOf(error: Object): number { const businessError: BusinessError = error as BusinessError; return businessError.code === undefined ? 0 : businessError.code; }
  private errorMessage(error: Object): string { const businessError: BusinessError = error as BusinessError; return businessError.message === undefined ? 'Wi-Fi 扫描失败' : businessError.message; }
}

class DefaultWifiPermissionChecker implements IFieldwatchWifiPermissionChecker {
  check(permission: Permissions): boolean { return ngfPermissionManagerFacade.checkPermission(permission); }
}
