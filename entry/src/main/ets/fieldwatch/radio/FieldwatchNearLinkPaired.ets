import { BusinessError } from '@kit.BasicServicesKit';
import { manager as nearlinkManager, remoteDevice as nearlinkRemoteDevice } from '@kit.ConnectivityKit';
import { SignatureClass } from '../domain/FieldwatchModels';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchNearLinkPaired';

/** 「已连接」取值：`@ohos.nearlink.constant` 的 `ConnectionState.STATE_CONNECTED = 1`。 */
const NEARLINK_STATE_CONNECTED: number = 1;

/**
 * 星闪已配对设备网关（文档落地点四的升级路径）。
 *
 * 文档原本按「拿不到配对列表」设计（v1 只做现扫现认），但 V5 在本机 API 26 SDK 里
 * 查到了 `@ohos.nearlink.manager.getPairedDevices(): string[]`
 * （注释：Gets the list of devices that have been paired with the current device），
 * 并明确要求「若查到接口，再按落地点一的同构方式补导入，不改上层」——本文件即那一步。
 *
 * 与蓝牙那条**分开成独立接口**：两个系统的枚举、权限与地址语义都不同，
 * 塞进同一个接口只会让两边都变形。上层拿到的仍是统一的候选结构。
 *
 * 只读：只调 `getPairedDevices` / `getDeviceName` / `getDeviceClass` / `getConnectionState`，
 * **不发起配对或连接**。
 */
export interface IFieldwatchNearLinkPairedPlatform {
  /** 本机是否支持星闪（不支持时不该画「你的设备」里的星闪段）。 */
  isSupported(): boolean;
  getPairedDevices(): string[];
  /** 名称；查不到返回空串（UI 显示「未命名设备」）。 */
  getDeviceName(address: string): string;
  /** `nearlink.constant.DeviceClass` 原始值；查不到返回 -1。 */
  getDeviceClass(address: string): number;
  /** 当前是否连着本机。 */
  isConnected(address: string): boolean;
}

export class HarmonyNearLinkPairedPlatform implements IFieldwatchNearLinkPairedPlatform {
  isSupported(): boolean {
    try {
      return nearlinkManager.isNearLinkSupported();
    } catch (error) {
      return false;
    }
  }

  getPairedDevices(): string[] {
    try {
      if (!nearlinkManager.isNearLinkSupported()) return [];
      return nearlinkManager.getPairedDevices();
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '取星闪已配对名单失败 code=' + failure.code);
      return [];
    }
  }

  getDeviceName(address: string): string {
    const device: nearlinkRemoteDevice.RemoteDevice | undefined = this.deviceOf(address);
    if (device === undefined) return '';
    try {
      return device.getDeviceName();
    } catch (error) {
      return '';
    }
  }

  getDeviceClass(address: string): number {
    const device: nearlinkRemoteDevice.RemoteDevice | undefined = this.deviceOf(address);
    if (device === undefined) return -1;
    try {
      return device.getDeviceClass() as number;
    } catch (error) {
      return -1;
    }
  }

  isConnected(address: string): boolean {
    const device: nearlinkRemoteDevice.RemoteDevice | undefined = this.deviceOf(address);
    if (device === undefined) return false;
    try {
      return (device.getConnectionState() as number) === NEARLINK_STATE_CONNECTED;
    } catch (error) {
      return false;
    }
  }

  /** 按地址取远端设备对象；创建失败（已取消配对等）返回 undefined。 */
  private deviceOf(address: string): nearlinkRemoteDevice.RemoteDevice | undefined {
    try {
      return nearlinkRemoteDevice.createRemoteDevice(address);
    } catch (error) {
      logger.debug(TAG, '创建星闪远端设备失败: ' + address);
      return undefined;
    }
  }
}

/** 星闪设备类别 → 应用类别（**粗映射**）。 */
export function nearLinkCategoryOf(deviceClass: number): SignatureClass {
  // 只做「档案在『我的东西』里要有对得上的图标」这一件事；
  // 认领列表用的是原生类别（`nearLinkClassSymbol` 更精确，可分出鼠标/触控板/手写笔）。
  if (deviceClass < 0) return SignatureClass.OTHER;
  const major: number = deviceClass & 0x000F00;
  if (major === 0x000200) return SignatureClass.PHONE;
  if (major === 0x000400) return SignatureClass.WEARABLE;
  if (major === 0x000600 || major === 0x000700 || major === 0x000800) return SignatureClass.AUDIO;
  if (major === 0x000E00) return SignatureClass.CAMERA;
  if (major === 0x000B00) return SignatureClass.VEHICLE;
  if (major === 0x000C00) return SignatureClass.HOME;
  return SignatureClass.OTHER;
}
