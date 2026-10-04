import { BusinessError } from '@kit.BasicServicesKit';
import { access, ble } from '@kit.ConnectivityKit';
import { logger } from 'ngf_framework';
import { RadioFacts, RadioKind, ScanObservation, ScanState } from '../domain/FieldwatchModels';
import { IFieldwatchRadioScanner } from './FieldwatchRadioScanner';

const TAG: string = 'FieldwatchBleScanner';

export class FieldwatchBleScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;
  private scanner: ble.BleScanner | undefined;

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void): void {
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    const bluetoothState: access.BluetoothState = access.getState();
    if (bluetoothState !== access.BluetoothState.STATE_ON) {
      this.fail('蓝牙未开启，请先开启蓝牙后重试');
      return;
    }
    try {
      if (this.scanner === undefined) this.scanner = ble.createBleScanner();
      const scanOptions: ble.ScanOptions = {
        interval: 0,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      };
      this.scanner.onBLEDeviceFind(this.onDeviceFind);
      void this.scanner.startScan(null, scanOptions).catch((error: Object): void => { this.fail(this.errorMessage(error)); });
      this.state = ScanState.SCANNING;
      logger.info(TAG, 'BLE 扫描已启动');
    } catch (error) {
      this.fail(this.errorMessage(error));
    }
  }

  stop(): void {
    try {
      const scanner: ble.BleScanner | undefined = this.scanner;
      if (scanner !== undefined) {
        scanner.offBLEDeviceFind(this.onDeviceFind);
        void scanner.stopScan().catch((error: Object): void => { logger.warn(TAG, '停止 BLE 扫描失败: ' + this.errorMessage(error)); });
      }
    } catch (error) {
      logger.warn(TAG, '停止 BLE 扫描失败: ' + this.errorMessage(error));
    }
    this.state = ScanState.IDLE;
  }

  private readonly onDeviceFind = (report: ble.ScanReport): void => {
    report.scanResult.forEach((result: ble.ScanResult): void => {
      const observation: ScanObservation = this.toObservation(result);
      if (this.observationHandler !== undefined) this.observationHandler(observation);
    });
  };

  private toObservation(result: ble.ScanResult): ScanObservation {
    const deviceId: string = result.deviceId;
    const deviceName: string = result.deviceName;
    const serviceUuids: string[] = result.serviceUuids === undefined ? [] : result.serviceUuids;
    const manufacturerDataHex: string = this.toHex(result.data);
    const facts: RadioFacts = new RadioFacts('', '', 0, serviceUuids, manufacturerDataHex);
    return new ScanObservation('ble:' + deviceId, RadioKind.BLE, deviceId, deviceName, result.rssi, Date.now(), facts);
  }

  private toHex(data: ArrayBuffer | undefined): string {
    if (data === undefined) return '';
    const bytes: Uint8Array = new Uint8Array(data);
    let result: string = '';
    for (let index: number = 0; index < bytes.length; index += 1) {
      const value: string = bytes[index].toString(16).toUpperCase();
      result += value.length === 1 ? '0' + value : value;
    }
    return result;
  }

  private fail(message: string): void {
    this.state = ScanState.ERROR;
    logger.warn(TAG, message);
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }

  private errorMessage(error: Object): string {
    const businessError: BusinessError = error as BusinessError;
    return 'BLE 扫描失败（' + businessError.code.toString() + '）：' + businessError.message;
  }
}
