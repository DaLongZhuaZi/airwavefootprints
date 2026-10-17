import { BusinessError } from '@kit.BasicServicesKit';
import { a2dp, access, baseProfile, connection, hfp, hid } from '@kit.ConnectivityKit';
import { logger } from 'ngf_framework';
import { RadioKind, SignatureClass } from '../domain/FieldwatchModels';
import {
  HarmonyNearLinkPairedPlatform, IFieldwatchNearLinkPairedPlatform, nearLinkCategoryOf
} from './FieldwatchNearLinkPaired';

const TAG: string = 'FieldwatchPairedDevices';

/**
 * 系统已配对设备网关 —— 「找东西」的认领名单来源。
 *
 * **为什么它是主锚**：今天用户想找自己的耳机，只能在一两百条广播里靠名字肉眼认；
 * 而 `connection.getPairedDevices()` 直接把「你自己配过对的设备」列出来，
 * 一次点击就能认领（见 docs/Fieldwatch找东西深度落地.md 落地点一）。
 *
 * **只读边界**：本文件只做**查询** —— `getPairedDevices` / `getRemoteDeviceName` /
 * `getRemoteDeviceClass` / Profile 的 `getConnectedDevices` 与状态订阅，
 * 不调用 `pairDevice` 等任何会发起配对或连接的动作，与 App「只接收不连接」的底线一致。
 *
 * **两条已经用 SDK 类型定义核实的约束（决定了这里不做什么）：**
 *
 * 1. **拿不到持久 ID**：`access.addPersistentDeviceId` 需要
 *    `ohos.permission.PERSISTENT_BLUETOOTH_PEERS_MAC`，该权限在
 *    `toolchains/lib/PermissionDefinitions.json` 里是 `availableLevel=system_basic`，
 *    普通应用需 ACL 才可申请 —— 所以本网关**不提供**持久锚，身份稳定性交给
 *    配对关系存续期内的虚拟地址 + 指纹兜底（Matcher 负责）。
 * 2. **虚拟地址与扫描 deviceId 是否同值仍未证实**（文档 §八 V1，头号真机项）：
 *    因此这里如实把系统给的值原样输出（`virtualAddress`），**不在网关里做任何
 *    「它就是扫描里那个 deviceId」的假设** —— 那一层判断留给 Matcher 与真机结论。
 */

/**
 * 经典蓝牙里可以问「现在连着谁」的三个 Profile 面。
 *
 * 纯 BLE 设备（防丢器、部分手环）不在这里：它们的连接由各自 App 的 GATT 维持，
 * 系统**不向第三方提供**「任意 App 的 BLE 连接清单」—— 那类目标只有
 * 「在附近 / 上次见到」两态，文案不要许诺第三态。
 */
export enum PairedProfileKind {
  /** A2DP 源（本机作 source）：耳机、音箱。 */
  AUDIO = 0,
  /** HFP AG（本机作音频网关）：车载免提。 */
  HANDSFREE = 1,
  /** HID Host（本机作主机）：键盘、鼠标、手柄。 */
  INPUT = 2
}

/** 「已连接」的取值：`@ohos.bluetooth.constant` 的 `ProfileConnectionState.STATE_CONNECTED = 2`。 */
const PROFILE_STATE_CONNECTED: number = 2;

/* ── DeviceClass 取值（`@ohos.bluetooth.constant` 的 MajorClass / MajorMinorClass）──
 * 这里用数字常量而不是 SDK 枚举：分类映射要能被 LocalUnit 直接喂数字覆盖，
 * 且不必让测试文件依赖蓝牙 Kit。每个常量后面都标了来源。 */
const MAJOR_PHONE: number = 0x0200;
const MAJOR_AUDIO_VIDEO: number = 0x0400;
const MAJOR_IMAGING: number = 0x0600;
const MAJOR_WEARABLE: number = 0x0700;
const MAJOR_HEALTH: number = 0x0900;

const MINOR_WEARABLE_HEADSET: number = 0x0404;
const MINOR_LOUDSPEAKER: number = 0x0414;
const MINOR_HEADPHONES: number = 0x0418;
const MINOR_CAR_AUDIO: number = 0x0420;
const MINOR_HIFI_AUDIO: number = 0x0428;

/** 只取我们需要的两位；SDK 的 `DeviceClass` 更宽，这里收敛成纯数据便于单测。 */
export class PairedClassFacts {
  public majorClass: number = 0;
  public minorClass: number = 0;
}

/** 系统已配对设备的一条信息（网关输出，UI 只认这个）。 */
export class PairedDeviceInfo {
  /** 系统给的地址（配对关系存续期内稳定）。**不要**假定它等于扫描的 deviceId。 */
  public virtualAddress: string = '';
  /** 系统名称；查不到时为空串，UI 显示「未命名设备」并允许用户改名。 */
  public name: string = '';
  public majorClass: number = 0;
  public minorClass: number = 0;
  /** 映射到应用已有类别体系（决定图标）。 */
  public category: SignatureClass = SignatureClass.OTHER;
  /** 该设备支持的 Profile 面（有任意一个 Profile 对象能查到它就列入）。 */
  public profiles: PairedProfileKind[] = [];
  /** 当前是否至少在某个 Profile 上连着本机 —— 「正在连着手机」态的判据。 */
  public connected: boolean = false;
  /** 来自哪个无线电系统：蓝牙（含经典侧）或星闪。 */
  public kind: RadioKind = RadioKind.BLE;
  /** 星闪原生类别（nearlink.constant.DeviceClass）；-1 表示非星闪或没取到。 */
  public nearLinkDeviceClass: number = -1;
}

/** 平台接口：把系统调用收敛在这里，网关逻辑可注入假实现做单测。 */
export interface IFieldwatchPairedPlatform {
  isBluetoothOn(): boolean;
  getPairedDevices(): string[];
  getRemoteDeviceName(deviceId: string): string;
  getRemoteDeviceClass(deviceId: string): PairedClassFacts;
  getConnectedDevices(kind: PairedProfileKind): string[];
  onConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void;
  offConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void;
}

/**
 * DeviceClass → 应用已有类别（决定列表图标）。
 *
 * 纯函数：不碰系统、可在 LocalUnit 里逐条覆盖。未知一律 `OTHER` ——
 * 宁可显示成通用图标，也不要猜错类别（用户会以为认错设备了）。
 */
export function pairedCategoryOf(majorClass: number, minorClass: number): SignatureClass {
  // 先看主次类：同为「音频大类」，耳机/音箱/车载在找东西时是三种目标。
  if (minorClass === MINOR_CAR_AUDIO) return SignatureClass.VEHICLE;
  if (minorClass === MINOR_HEADPHONES || minorClass === MINOR_WEARABLE_HEADSET
    || minorClass === MINOR_LOUDSPEAKER || minorClass === MINOR_HIFI_AUDIO) return SignatureClass.AUDIO;
  if (majorClass === MAJOR_AUDIO_VIDEO) return SignatureClass.AUDIO;
  if (majorClass === MAJOR_WEARABLE) return SignatureClass.WEARABLE;
  if (majorClass === MAJOR_HEALTH) return SignatureClass.HEALTH;
  if (majorClass === MAJOR_PHONE) return SignatureClass.PHONE;
  if (majorClass === MAJOR_IMAGING) return SignatureClass.CAMERA;
  // 外设（键盘/鼠标）、计算机、网络设备等应用没有对应类别，落 OTHER。
  return SignatureClass.OTHER;
}

/** 真实平台实现：只做查询，并在每个调用点吞掉运行期异常。 */
export class HarmonyPairedPlatform implements IFieldwatchPairedPlatform {
  private a2dpProfile: a2dp.A2dpSourceProfile | undefined;
  private hfpProfile: hfp.HandsFreeAudioGatewayProfile | undefined;
  private hidProfile: hid.HidHostProfile | undefined;

  isBluetoothOn(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (error) {
      logger.warn(TAG, '读蓝牙状态失败: ' + String(error));
      return false;
    }
  }

  getPairedDevices(): string[] {
    try {
      return connection.getPairedDevices();
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '取已配对名单失败 code=' + failure.code);
      return [];
    }
  }

  getRemoteDeviceName(deviceId: string): string {
    try {
      // 带 alias 的重载优先：用户在系统设置里改过名字时，别名比原始名字更贴近他的认知。
      return connection.getRemoteDeviceName(deviceId, true);
    } catch (error) {
      try {
        return connection.getRemoteDeviceName(deviceId);
      } catch (inner) {
        return '';
      }
    }
  }

  getRemoteDeviceClass(deviceId: string): PairedClassFacts {
    const facts: PairedClassFacts = new PairedClassFacts();
    try {
      const deviceClass: connection.DeviceClass = connection.getRemoteDeviceClass(deviceId);
      facts.majorClass = deviceClass.majorClass as number;
      facts.minorClass = deviceClass.majorMinorClass as number;
    } catch (error) {
      logger.debug(TAG, '取设备类别失败（按未知处理）: ' + deviceId);
    }
    return facts;
  }

  getConnectedDevices(kind: PairedProfileKind): string[] {
    const profile: baseProfile.BaseProfile | undefined = this.profileOf(kind);
    if (profile === undefined) return [];
    try {
      return profile.getConnectedDevices();
    } catch (error) {
      logger.debug(TAG, '取已连接设备失败: profile=' + kind.toString());
      return [];
    }
  }

  onConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void {
    const profile: baseProfile.BaseProfile | undefined = this.profileOf(kind);
    if (profile === undefined) return;
    try {
      profile.on('connectionStateChange', (param: baseProfile.StateChangeParam): void => {
        callback(param.deviceId, (param.state as number) === PROFILE_STATE_CONNECTED);
      });
    } catch (error) {
      logger.warn(TAG, '订阅连接状态失败: profile=' + kind.toString());
    }
  }

  offConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void {
    const profile: baseProfile.BaseProfile | undefined = this.profileOf(kind);
    if (profile === undefined) return;
    try {
      profile.off('connectionStateChange');
    } catch (error) {
      logger.debug(TAG, '取消订阅连接状态失败: profile=' + kind.toString());
    }
  }

  /** Profile 对象按需创建并缓存：创建失败（不支持/权限）返回 undefined，调用方按「查不到」处理。 */
  private profileOf(kind: PairedProfileKind): baseProfile.BaseProfile | undefined {
    try {
      if (kind === PairedProfileKind.AUDIO) {
        if (this.a2dpProfile === undefined) this.a2dpProfile = a2dp.createA2dpSrcProfile();
        return this.a2dpProfile;
      }
      if (kind === PairedProfileKind.HANDSFREE) {
        if (this.hfpProfile === undefined) this.hfpProfile = hfp.createHfpAgProfile();
        return this.hfpProfile;
      }
      if (this.hidProfile === undefined) this.hidProfile = hid.createHidHostProfile();
      return this.hidProfile;
    } catch (error) {
      logger.warn(TAG, '创建 Profile 对象失败（按不支持处理）: ' + kind.toString());
      return undefined;
    }
  }
}

/**
 * 认领名单网关。
 *
 * 生命周期：页面出现时 `list()` 拉一次，`subscribe()` 订阅连接变化；
 * 页面离开时 **必须** `unsubscribe()`（与雷达、扫描器的订阅配对规则一致）。
 */
export class FieldwatchPairedDevices {
  private readonly platform: IFieldwatchPairedPlatform;
  /** 星闪那条单独注入：两个系统的枚举与权限都不同，不混进同一个接口。 */
  private readonly nearLink: IFieldwatchNearLinkPairedPlatform;
  private listener: ((deviceId: string, connected: boolean) => void) | undefined;
  private readonly profileListener = (deviceId: string, connected: boolean): void => {
    if (this.listener !== undefined) this.listener(deviceId, connected);
  };

  constructor(platform: IFieldwatchPairedPlatform = new HarmonyPairedPlatform(),
    nearLink: IFieldwatchNearLinkPairedPlatform = new HarmonyNearLinkPairedPlatform()) {
    this.platform = platform;
    this.nearLink = nearLink;
  }

  /** 蓝牙是否可用（关闭时名单为空，UI 应引导用户开蓝牙而不是显示空列表）。 */
  isBluetoothOn(): boolean {
    return this.platform.isBluetoothOn();
  }

  /**
   * 读系统已配对名单。
   *
   * 排序：**正在连着手机的排最前**，其余按名称；
   * 理由是「找东西」最常见的场景就是找那个还连着/刚断开的耳机 —— 它应该在第一位。
   */
  list(): PairedDeviceInfo[] {
    const out: PairedDeviceInfo[] = [];
    if (!this.platform.isBluetoothOn()) return out;
    const connectedAddresses: string[] = this.connectedAddresses();
    const addresses: string[] = this.platform.getPairedDevices();
    addresses.forEach((address: string): void => {
      /**
       * **单台设备的任何一次查询失败，都不能让整批名单失败。**
       *
       * 现实里「遍历期间用户在系统设置里取消了配对」就会让这一条查询抛错；
       * 一个 try 包住整批的写法会让用户**连自己的耳机都看不到** —— 那是本功能最不能接受的失败。
       * 所以这里逐台兜住，坏的那台跳过，其余照常返回。
       *
       * （平台实现在每个调用点也各自吞异常；两处都兜是有意的 —— 这条不变量由遍历方负责，
       * 不能依赖平台实现是否老实。单测就是按「假平台直接抛」来钉住它的。）
       */
      try {
        const info: PairedDeviceInfo = new PairedDeviceInfo();
        info.virtualAddress = address;
        // 名称与类别各自降级，**不因为查不到就把这台设备从名单里删掉** ——
        // 删掉等于用户找不到自己的设备；显示「未命名设备」至少还能靠类别图标与连接态认出来。
        info.name = this.safeName(address);
        const facts: PairedClassFacts = this.safeClass(address);
        info.majorClass = facts.majorClass;
        info.minorClass = facts.minorClass;
        info.category = pairedCategoryOf(facts.majorClass, facts.minorClass);
        info.profiles = this.profilesFor(address, connectedAddresses);
        info.connected = connectedAddresses.includes(address);
        out.push(info);
      } catch (error) {
        logger.warn(TAG, '跳过一台查不到的已配对设备: ' + address);
      }
    });
    // 星闪：V5 已确认 SDK 有配对列表接口，按落地点一同构接入（文档明确要求的升级路径）。
    this.nearLink.getPairedDevices().forEach((address: string): void => {
      try {
        const info: PairedDeviceInfo = new PairedDeviceInfo();
        info.kind = RadioKind.NEARLINK;
        info.virtualAddress = address;
        info.name = this.nearLink.getDeviceName(address);
        info.nearLinkDeviceClass = this.nearLink.getDeviceClass(address);
        info.category = nearLinkCategoryOf(info.nearLinkDeviceClass);
        info.connected = this.nearLink.isConnected(address);
        out.push(info);
      } catch (error) {
        logger.warn(TAG, '跳过一台查不到的星闪配对设备: ' + address);
      }
    });
    out.sort((left: PairedDeviceInfo, right: PairedDeviceInfo): number => {
      if (left.connected !== right.connected) return left.connected ? -1 : 1;
      return left.name.localeCompare(right.name);
    });
    return out;
  }

  /** 某个地址当前是否在任意 Profile 上连着本机（「正在连着手机」态）。 */
  isConnected(deviceId: string): boolean {
    return this.connectedAddresses().includes(deviceId);
  }

  /** 订阅经典侧连接状态变化（耳机连上/断开是「上次见到」最可信的时刻）。 */
  subscribe(listener: (deviceId: string, connected: boolean) => void): void {
    this.unsubscribe();
    this.listener = listener;
    this.platform.onConnectionStateChange(PairedProfileKind.AUDIO, this.profileListener);
    this.platform.onConnectionStateChange(PairedProfileKind.HANDSFREE, this.profileListener);
    this.platform.onConnectionStateChange(PairedProfileKind.INPUT, this.profileListener);
  }

  unsubscribe(): void {
    if (this.listener === undefined) return;
    this.listener = undefined;
    this.platform.offConnectionStateChange(PairedProfileKind.AUDIO, this.profileListener);
    this.platform.offConnectionStateChange(PairedProfileKind.HANDSFREE, this.profileListener);
    this.platform.offConnectionStateChange(PairedProfileKind.INPUT, this.profileListener);
  }

  /** 查名称：失败与「没有名字」都返回空串（UI 显示「未命名设备」并允许改名）。 */
  private safeName(address: string): string {
    try {
      return this.platform.getRemoteDeviceName(address);
    } catch (error) {
      logger.debug(TAG, '查名称失败，按未命名处理: ' + address);
      return '';
    }
  }

  /** 查设备类别：失败按「未知」处理，图标回落通用样式。 */
  private safeClass(address: string): PairedClassFacts {
    try {
      return this.platform.getRemoteDeviceClass(address);
    } catch (error) {
      logger.debug(TAG, '查设备类别失败，按未知处理: ' + address);
      return new PairedClassFacts();
    }
  }

  /** 三个 Profile 面里当前所有已连接地址（去重）。 */
  private connectedAddresses(): string[] {
    const out: string[] = [];
    const kinds: PairedProfileKind[] = [PairedProfileKind.AUDIO, PairedProfileKind.HANDSFREE, PairedProfileKind.INPUT];
    kinds.forEach((kind: PairedProfileKind): void => {
      this.platform.getConnectedDevices(kind).forEach((address: string): void => {
        if (!out.includes(address)) out.push(address);
      });
    });
    return out;
  }

  /** 该地址出现在哪些 Profile 的已连接名单里。 */
  private profilesFor(address: string, connectedAddresses: string[]): PairedProfileKind[] {
    const out: PairedProfileKind[] = [];
    if (!connectedAddresses.includes(address)) return out;
    const kinds: PairedProfileKind[] = [PairedProfileKind.AUDIO, PairedProfileKind.HANDSFREE, PairedProfileKind.INPUT];
    kinds.forEach((kind: PairedProfileKind): void => {
      if (this.platform.getConnectedDevices(kind).includes(address)) out.push(kind);
    });
    return out;
  }
}
