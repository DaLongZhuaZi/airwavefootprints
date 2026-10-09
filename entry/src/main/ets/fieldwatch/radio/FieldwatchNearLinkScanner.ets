import { BusinessError } from '@kit.BasicServicesKit';
import { manager as nearlinkManager, scan as nearlinkScan } from '@kit.ConnectivityKit';
import { logger } from 'ngf_framework';
import { RadioFacts, RadioKind, RadioSourceSnapshot, ScanObservation, ScanState } from '../domain/FieldwatchModels';
import { IFieldwatchRadioScanner } from './FieldwatchRadioScanner';

const TAG: string = 'FieldwatchNearLinkScanner';

/**
 * 星闪（NearLink）被动扫描器。
 *
 * 与 `FieldwatchBleScanner` 实现**同一个契约**，因此协调器、状态机、重试、UI 全部复用，
 * 上层无需任何改动 —— 这是「体验与蓝牙完全一致」的实现基础。
 *
 * 只做被动监听：不连接、不配对、不传输数据（虽然权限上完全允许）。
 */
export class FieldwatchNearLinkScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  public readonly kind: RadioKind = RadioKind.NEARLINK;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;
  private stateHandler: ((snapshot: RadioSourceSnapshot) => void) | undefined;
  private lastSuccessAt: number = 0;
  private started: boolean = false;

  getSnapshot(): RadioSourceSnapshot {
    return new RadioSourceSnapshot(this.kind, this.state, this.lastSuccessAt, 0, false);
  }

  retryNow(): void {
    if (this.observationHandler !== undefined && this.errorHandler !== undefined) {
      this.start(this.observationHandler, this.errorHandler, this.stateHandler);
    }
  }

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void {
    this.stop();
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    this.stateHandler = onStateChange;

    // 1) 硬件能力门控：芯片不支持时（错误码 801）直接判定不可用，
    //    既不启动扫描也不申请权限 —— 不能在无此硬件的设备上索要用不到的权限。
    let supported: boolean = false;
    try {
      supported = nearlinkManager.isNearLinkSupported();
    } catch (error) {
      this.fail('星闪能力探测失败：' + this.errorMessage(error));
      return;
    }
    if (!supported) {
      this.fail('本机不支持星闪');
      return;
    }

    // 2) 开关状态：与蓝牙「蓝牙未开启」同款处理，给用户可操作的提示。
    try {
      const state: nearlinkManager.NearlinkState = nearlinkManager.getState();
      if (state !== nearlinkManager.NearlinkState.STATE_ON) {
        this.fail('星闪未开启，请先开启星闪后重试');
        return;
      }
    } catch (error) {
      this.fail('读取星闪状态失败：' + this.errorMessage(error));
      return;
    }

    try {
      nearlinkScan.onDeviceFound(this.onDeviceFound);
      this.started = true;
      // 字段名与枚举名以 SDK d.ts 为准：ScanOptions.scanMode（默认 LOW_POWER）。
      const options: nearlinkScan.ScanOptions = {
        scanMode: nearlinkScan.ScanMode.SCAN_MODE_LOW_POWER
      };
      void nearlinkScan.startScan(null, options).then((): void => {
        this.state = ScanState.SCANNING;
        this.publishState();
        logger.info(TAG, '星闪扫描已启动');
      }).catch((error: BusinessError): void => {
        this.fail(this.describeScanError(error));
      });
    } catch (error) {
      this.fail(this.describeScanError(error as BusinessError));
    }
  }

  stop(): void {
    try {
      if (this.started) {
        nearlinkScan.offDeviceFound(this.onDeviceFound);
        this.started = false;
      }
      void nearlinkScan.stopScan().catch((error: BusinessError): void => {
        logger.warn(TAG, '停止星闪扫描失败: ' + this.errorMessage(error));
      });
    } catch (error) {
      logger.warn(TAG, '停止星闪扫描失败: ' + this.errorMessage(error));
    }
    this.state = ScanState.IDLE;
    this.publishState();
  }

  private readonly onDeviceFound = (results: nearlinkScan.ScanResults[]): void => {
    results.forEach((result: nearlinkScan.ScanResults): void => {
      const observation: ScanObservation | undefined = this.toObservation(result);
      if (observation === undefined) return;
      this.lastSuccessAt = observation.seenAt;
      this.publishState();
      if (this.observationHandler !== undefined) this.observationHandler(observation);
    });
  }

  /**
   * 扫描结果 → 观测。
   *
   * 两个必须处理的点：
   *  1. **rssi = 127 表示无效**，必须丢弃 —— 否则会在雷达上出现落在圆心的虚假强信号。
   *  2. **地址很可能是匿名/可变标识**（真实 MAC 属系统级权限，本应用不申请），
   *     因此不能当作稳定设备 ID；设备名与设备类型才是识别依据。
   */
  private toObservation(result: nearlinkScan.ScanResults): ScanObservation | undefined {
    const rssi: number = result.rssi;
    if (rssi === 127 || rssi > 0) {
      logger.debug(TAG, '丢弃无效星闪信号强度: ' + rssi.toString());
      return undefined;
    }
    const address: string = result.address !== undefined ? result.address : '';
    if (address.length === 0) return undefined;
    const name: string = result.deviceName !== undefined ? result.deviceName : '';
    const facts: RadioFacts = new RadioFacts();
    // 星闪广播原始字节交给特征库引擎匹配（与 BLE 的 data 同性质）。
    facts.manufacturerDataHex = this.toHex(result.data);
    // 设备类型由星闪广播直接携带，无需特征库命中即可显示正确图标。
    facts.nearLinkDeviceClass = result.deviceClass !== undefined ? result.deviceClass : -1;
    facts.nearLinkConnectable = result.isConnectable === true;
    return new ScanObservation('nearlink:' + address, RadioKind.NEARLINK, address, name, rssi, Date.now(), facts);
  }

  /** ArrayBuffer → 十六进制串。空数据返回空串，不抛错。 */
  private toHex(data: ArrayBuffer | undefined): string {
    if (data === undefined || data.byteLength === 0) return '';
    const bytes: Uint8Array = new Uint8Array(data);
    let hex: string = '';
    for (let index: number = 0; index < bytes.length; index += 1) {
      const value: number = bytes[index];
      hex += (value < 16 ? '0' : '') + value.toString(16);
    }
    return hex;
  }

  /** 把星闪错误码翻译成用户可读的说明，而不是把错误码直接抛给用户。 */
  private describeScanError(error: BusinessError): string {
    const code: number = error.code;
    if (code === 201) return '星闪扫描权限未授予';
    if (code === 801) return '本机不支持星闪';
    if (code === 36100003) return '星闪未开启，请先开启星闪后重试';
    return '星闪扫描失败（' + code.toString() + '）：' + error.message;
  }

  private errorMessage(error: Object): string {
    const business: BusinessError = error as BusinessError;
    return business.code !== undefined ? business.code.toString() + ' ' + business.message : String(error);
  }

  private fail(message: string): void {
    this.state = ScanState.ERROR;
    logger.warn(TAG, message);
    this.publishState();
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }

  private publishState(): void {
    if (this.stateHandler !== undefined) this.stateHandler(this.getSnapshot());
  }
}