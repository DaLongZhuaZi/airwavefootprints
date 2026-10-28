import { BusinessError } from '@kit.BasicServicesKit';
import { access, ble } from '@kit.ConnectivityKit';
import { logger, ngfText } from 'ngf_framework';
import { RadioFacts, RadioKind, RadioSourceSnapshot, ScanObservation, ScanState, ServiceDataRecord } from '../domain/FieldwatchModels';
import { BleAdvertisementFacts, FieldwatchBleAdvertisementDecoder } from '../domain/FieldwatchParsers';
import { bytesToHex } from '../domain/FieldwatchHex';
import { IFieldwatchRadioScanner } from './FieldwatchRadioScanner';

const TAG: string = 'FieldwatchBleScanner';

export class FieldwatchBleScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  public readonly kind: RadioKind = RadioKind.BLE;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;
  private stateHandler: ((snapshot: RadioSourceSnapshot) => void) | undefined;
  private scanner: ble.BleScanner | undefined;
  private lastSuccessAt: number = 0;
  private readonly advertisementDecoder: FieldwatchBleAdvertisementDecoder = new FieldwatchBleAdvertisementDecoder();

  getSnapshot(): RadioSourceSnapshot { return new RadioSourceSnapshot(this.kind, this.state, this.lastSuccessAt, 0, false); }
  retryNow(): void { if (this.observationHandler !== undefined && this.errorHandler !== undefined) this.start(this.observationHandler, this.errorHandler, this.stateHandler); }

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void {
    // **重入保护**：已经在扫描时再 start，会先 stop 再 startScan，
    // 而系统此刻仍认为扫描未结束 —— 抛 2902050
    // 「Failed to start scan as Ble scan is already started by the app」。
    // 已经在扫就只替换回调，不重启系统扫描。
    if (this.state === ScanState.SCANNING) {
      this.observationHandler = onObservation;
      this.errorHandler = onError;
      this.stateHandler = onStateChange;
      return;
    }
    this.stop();
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    this.stateHandler = onStateChange;
    const bluetoothState: access.BluetoothState = access.getState();
    if (bluetoothState !== access.BluetoothState.STATE_ON) {
      this.fail(ngfText('app.string.fw_bl_31'));
      return;
    }
    try {
      if (this.scanner === undefined) this.scanner = ble.createBleScanner();
      const scanOptions: ble.ScanOptions = {
        interval: 0,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      };
      this.scanner.on('BLEDeviceFind', this.onDeviceFind);
      void this.scanner.startScan(null, scanOptions).catch((error: Object): void => { this.fail(this.errorMessage(error)); });
      this.state = ScanState.SCANNING;
      this.publishState();
      // 新一轮扫描的首条广播要立刻发布（见 publishStateThrottled 的边界说明）。
      this.lastPublishAt = 0;
      logger.info(TAG, 'BLE 扫描已启动');
    } catch (error) {
      this.fail(this.errorMessage(error));
    }
  }

  /**
   * 停止扫描。
   *
   * **只在真的处于扫描中时才调系统停扫接口**：本方法有多处调用点（切后台、组件析构），
   * 第二次调用时系统侧已经没有在跑的扫描，`stopScan()` 会回 2900099 / -1，
   * 日志里就是那两条连发的「停止 BLE 扫描失败」（真机复现）。
   * 守卫让第二次成为空操作 —— 调用点保留，不靠删调用点来消除告警。
   */
  stop(): void {
    if (this.state !== ScanState.SCANNING) {
      // 未在扫描：没有系统资源需要释放，只把本地状态归位，静默返回。
      logger.debug(TAG, '当前未在扫描，跳过系统停扫');
      this.state = ScanState.IDLE;
      this.publishState();
      return;
    }
    try {
      const scanner: ble.BleScanner | undefined = this.scanner;
      if (scanner !== undefined) {
        scanner.off('BLEDeviceFind', this.onDeviceFind);
        void scanner.stopScan().catch((error: Object): void => { logger.warn(TAG, '停止 BLE 扫描失败: ' + this.errorMessage(error)); });
      }
    } catch (error) {
      logger.warn(TAG, '停止 BLE 扫描失败: ' + this.errorMessage(error));
    }
    this.state = ScanState.IDLE;
    this.publishState();
  }

  private readonly onDeviceFind = (report: ble.ScanReport): void => {
    // 逐条观测的日志**刻意不打**：
    // 实测 BLE 回调约每秒 16~500 条，每条两行 debug 会在几秒内冲干净
    // 整个日志环形缓冲 —— Wi-Fi 与星闪的启动行因此被挤掉，
    // 排查时看起来像「Wi-Fi 没启动」，实际只是日志被冲没了。
    // 这里只保留回调批次计数，且同样做节流。
    this.logCallbackThrottled(report.scanResult.length);
    report.scanResult.forEach((result: ble.ScanResult): void => {
      const observation: ScanObservation = this.toObservation(result);
      this.lastSuccessAt = observation.seenAt;
      // **不要再逐条 publishState**：一批最多 500 条广播，逐条发布意味着每秒最多
      // 500 次快照分配 + 500 次 coordinator 状态汇总 + 500 次应用状态写入，
      // 而界面上「最近一次成功」只精确到秒。500ms 节流对观感没有任何影响。
      this.publishStateThrottled();
      // 单条观测不再逐条打日志，见 logCallbackThrottled 的说明。
      if (this.observationHandler !== undefined) this.observationHandler(observation);
    });
  };

  /** 上次向外发布状态快照的时刻；用于把逐条广播的状态发布压到 2 次/秒。 */
  private lastPublishAt: number = 0;

  /**
   * 节流后的状态发布：同一批广播里只发有限次。
   *
   * 边界情况：首条广播必须立刻发（否则「最近一次成功」要等到下一次才更新），
   * 所以 `lastPublishAt` 在 `start()` 里会重置为 0。
   */
  private publishStateThrottled(): void {
    const now: number = Date.now();
    if (now - this.lastPublishAt < 500) return;
    this.lastPublishAt = now;
    this.publishState();
  }

  /** 距离上次输出批次日志的毫秒数；用于把回调日志压到每 30 秒一条。 */
  private lastCallbackLogAt: number = 0;
  /** 上次输出后的累计观测条数，随日志一起给出，信息量不丢。 */
  private callbacksSinceLog: number = 0;
  private observationsSinceLog: number = 0;
  /**
   * 节流后的回调日志：**每 30 秒一条**，并汇报这期间的累计量。
   *
   * 直接删掉日志会让「到底有没有在收」变得不可验证；
   * 全量打日志又会冲掉其他无线电的日志。
   * 折中是低频汇总：既能证明链路活着，又不淹没有用信息。
   */
  private logCallbackThrottled(batchSize: number): void {
    this.callbacksSinceLog += 1;
    this.observationsSinceLog += batchSize;
    const now: number = Date.now();
    if (now - this.lastCallbackLogAt < 30000) return;
    this.lastCallbackLogAt = now;
    logger.debug(TAG, 'BLE 回调汇总: ' + this.callbacksSinceLog.toString() + ' 批 / '
      + this.observationsSinceLog.toString() + ' 条观测');
    this.callbacksSinceLog = 0;
    this.observationsSinceLog = 0;
  }
  private toObservation(result: ble.ScanResult): ScanObservation {
    const deviceId: string = result.deviceId;
    const deviceName: string = result.deviceName;
    const serviceUuids: string[] = result.serviceUuids === undefined ? [] : result.serviceUuids.slice();
    const serviceData: ServiceDataRecord[] = [];
    let manufacturerId: number = 0;
    let manufacturerDataHex: string = '';
    const manufacturerMap: Map<number, Uint8Array> | undefined = result.manufacturerDataMap;
    if (manufacturerMap !== undefined) {
      manufacturerMap.forEach((value: Uint8Array, key: number): void => {
        if (manufacturerId === 0) { manufacturerId = key; manufacturerDataHex = bytesToHex(value); }
      });
    }
    const serviceMap: Map<string, Uint8Array> | undefined = result.serviceDataMap;
    if (serviceMap !== undefined) {
      serviceMap.forEach((value: Uint8Array, key: string): void => { serviceData.push(new ServiceDataRecord(key, bytesToHex(value))); });
    }
    // ── 原始广播包：**无条件**解析，不再只当兜底 ──
    //
    // 鸿蒙给的 manufacturerDataMap / serviceDataMap / serviceUuids 只覆盖部分 AD 类型，
    // 而 `ScanResult.data` 是完整的广播包。此前只在两个 map 同时为空时才解析它，
    // 于是常规广播（几乎都有厂商数据）永远走不到这一步，
    // 结果 Appearance、Flags、Tx Power、16/128 位服务 UUID 全部被丢掉。
    //
    // 现在两边都解析，缺的用原始包补齐（平台值优先，避免解析差异）。
    // 整包字节只取一次：解析和 rawAdHex 共用同一份，
    // 原来这里 `new Uint8Array(result.data)` 建了两次，十六进制也转了两遍。
    const rawBytes: Uint8Array = new Uint8Array(result.data);
    const decoded: BleAdvertisementFacts = this.advertisementDecoder.decodeBytes(rawBytes);
    const serviceUuids16: string[] = [];
    const serviceUuids128: string[] = [];
    if (decoded.valid) {
      if (manufacturerId === 0) {
        manufacturerId = decoded.manufacturerId;
        manufacturerDataHex = decoded.manufacturerDataHex;
      }
      if (serviceData.length === 0) {
        decoded.serviceData.forEach((item: ServiceDataRecord): void => { serviceData.push(item); });
      }
      // 按长度分流：8/4 位十六进制是 16 位 UUID，32 位是 128 位 UUID。
      decoded.serviceUuids.forEach((uuid: string): void => {
        if (uuid.length <= 8) serviceUuids16.push(uuid); else serviceUuids128.push(uuid);
        if (serviceUuids.indexOf(uuid) < 0) serviceUuids.push(uuid);
      });
    }
    const facts: RadioFacts = new RadioFacts('', '', 0, serviceUuids, manufacturerDataHex, 0, 0, 0, false, manufacturerId, serviceData, []);
    facts.rawAdHex = decoded.valid ? bytesToHex(rawBytes) : '';
    facts.appearance = decoded.valid ? decoded.appearance : -1;
    facts.txPower = decoded.valid ? decoded.txPower : -128;
    facts.advertiseFlags = decoded.valid ? decoded.flags : -1;
    // 电量：平台 map 里没有这个概念，只能从原始广播包里解（Battery Service 服务数据）。
    // 解不到就是 -1 —— **不拿 RSSI 顶替**，看板据此决定「不显示」。
    facts.batteryPercent = decoded.valid ? decoded.batteryPercent : -1;
    facts.serviceUuids16 = serviceUuids16;
    facts.serviceUuids128 = serviceUuids128;
    facts.connectable = result.connectable === undefined ? false : result.connectable;
    // 详情页要的两项，此前解析出来了却没往 facts 里放：
    // 经典蓝牙 CoD（AD 0x0D）与**全部**厂商数据记录（AD 0xFF 可多条）。
    facts.deviceClass = decoded.valid ? decoded.deviceClass : -1;
    facts.mfgRecords = decoded.valid ? decoded.mfgRecords : [];
    // 注意：`primaryPhy` / `secondaryPhy` / `advertisingIntervalMs` **不填** ——
    // 鸿蒙 `ble.ScanResult` 只有 deviceId/address/rssi/data/deviceName/connectable/advertiseFlags，
    // 没有 PHY 与广播间隔字段（Android 有）。这是平台差异，不能编造，界面据此不展示。
    // 地址类型：API 23 起 ScanResult.address 才带 addressType。
    // 拿不到时留空串，界面据此不展示「地址类型」，而不是猜一个。
    const address: ble.BluetoothAddress | undefined = result.address;
    if (address !== undefined) {
      const raw: number = address.addressType as number;
      facts.addressType = raw === 0 ? 'public' : (raw === 1 ? 'random' : '');
    }
    return new ScanObservation('ble:' + deviceId, RadioKind.BLE, deviceId, deviceName, result.rssi, Date.now(), facts);
  }

  // 字节转十六进制统一走 `../../domain/FieldwatchHex` 的查表实现：
  // 原来的逐字节 `toString(16)` + `+=` 是录制里的第一号 CPU 热点（`bytesHex` 699 采样）。
  // 顺带删掉了从未被调用的 `toHex(ArrayBuffer)` —— 星闪扫码器有自己的同名实现。

  private fail(message: string): void {
    this.state = ScanState.ERROR;
    this.publishState(message);
    logger.warn(TAG, message);
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }

  private publishState(message: string = ''): void {
    if (this.stateHandler !== undefined) this.stateHandler(new RadioSourceSnapshot(this.kind, this.state, this.lastSuccessAt, 0, false, 0, message));
  }

  private errorMessage(error: Object): string {
    const businessError: BusinessError = error as BusinessError;
    return ngfText('app.string.fw_bl_212b') + businessError.code.toString() + ngfText('app.string.fw_bl_212c') + businessError.message;
  }
}
