import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { access, connection, constant } from '@kit.ConnectivityKit';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchPairedDevices';

/**
 * 本文件只需要这一个权限，`entry/src/main/module.json5` 里已经声明。
 *
 * **刻意不申请 GET_BLUETOOTH_PEERS_MAC 与 PERSISTENT_BLUETOOTH_PEERS_MAC**：
 * 前者能把虚拟地址换成真实 MAC，后者能让地址跨重启稳定 —— 两者都是 system_basic
 * 等级，普通应用拿不到；想拿只能走 ACL 加签，等于为了「找耳机」这个功能把应用的
 * 权限面整体抬高。产品的底线是「不新增权限」，所以宁可接受虚拟地址会变，
 * 用指纹兜底，也不去碰这两条权限。
 */
const ACCESS_BLUETOOTH: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';

/**
 * Class of Device 的主类别码（第 8–12 位右移后的 5 位值）。
 * 取值来自 Bluetooth SIG Baseband 表；系统枚举 `constant.MajorClass` 用的是
 * 已左移的写法（MAJOR_AUDIO_VIDEO = 0x0400），这里统一收敛成右移后的 5 位值，
 * 与 `domain/FieldwatchOwnDevice.kindFromDeviceClass(major, minor)` 的参数口径一致。
 */
const MAJOR_NETWORKING: number = 0x03;
const MAJOR_AUDIO_VIDEO: number = 0x04;
const MAJOR_PERIPHERAL: number = 0x05;

/** 设备家族：把「哪一类 Profile 能证明它在使用中」编码成一个小整数。 */
const FAMILY_NONE: number = 0;
const FAMILY_AUDIO: number = 1;
const FAMILY_PERIPHERAL: number = 2;
const FAMILY_NETWORK: number = 3;

/**
 * 系统配对名单里的一台设备。
 *
 * 全部字段都是**只读查询的结果**：这个类不持有任何连接句柄，
 * 拿到它也不代表能对该设备做任何动作。
 */
export class PairedDeviceEntry {
  /** 系统配对地址。API 26 未授予 GET_BLUETOOTH_PEERS_MAC 时这是**系统分配的虚拟地址**，不是真实 MAC。 */
  public address: string = '';
  /** `getRemoteDeviceName` 的结果；取不到（纯 BLE 配对、对端不响应、权限不足）时为空串。 */
  public name: string = '';
  /** `getRemoteDeviceClass().classOfDevice`，完整 24 位 CoD；失败为 -1。 */
  public deviceClass: number = -1;
  /** CoD 主类别（5 位，如 0x04 = 音频/视频）；失败为 -1。 */
  public majorClass: number = -1;
  /** CoD 次类别（6 位，如 0x06 = 头戴耳机）；失败为 -1。 */
  public majorMinorClass: number = -1;
  /** 是否可能正在被使用；判定口径与保守策略见 `FieldwatchPairedDevices.markInUse`。 */
  public inUse: boolean = false;
  /**
   * 恒为空串，**永远**。
   *
   * 持久标识要么来自 `connection.getPairedDevices()` 的真实 MAC，要么来自
   * `access.addPersistentDeviceId()` —— 两者都要求 PERSISTENT_BLUETOOTH_PEERS_MAC /
   * GET_BLUETOOTH_PEERS_MAC（system_basic），本项目不申请。
   * 字段保留是为了让上层代码不必写 `if (entry.persistentId ...)` 的分支，
   * 也为了让「拿不到持久锚」这件事在类型层面是显式的、可断言的。
   */
  public persistentId: string = '';
}

/**
 * 系统已配对蓝牙设备的只读视图。
 *
 * 三条硬约束（改这个文件前先读一遍）：
 *   1. **只读**。只允许调用 getPairedDevices / getRemoteDeviceName / getRemoteDeviceClass /
 *      getProfileConnectionState。绝不调用 pairDevice、connectAllowedProfiles、
 *      setDevicePairingConfirmation、各类 create*Profile().connect() ——
 *      「只被动接收、绝不发起配对或连接」是这个 App 的信任状，破一次就没了。
 *   2. **绝不抛出**。业务错误码 201（未授权）/ 801（不支持）/ 2900003（蓝牙关闭）
 *      都是正常路径（用户随时可能关蓝牙），一律降级成兜底值 + warn 日志。
 *   3. **不做 batching**。配对名单通常不到 20 条，逐个查询的开销远小于维护批处理状态的开销。
 */
export class FieldwatchPairedDevices {
  /** 名称缓存：同一次进程内同一地址只问系统一次。 */
  private readonly nameCache: Map<string, string> = new Map<string, string>();

  /**
   * 现在能不能读配对名单：ACCESS_BLUETOOTH 已授予 **且** 蓝牙已开启。
   *
   * 两个条件缺一不可：未授权时任何查询都会抛 201；蓝牙关闭时抛 2900003。
   * 先判断再调用，可以让「用户关了蓝牙」这种常态不产生一堆 warn 日志。
   */
  available(): boolean {
    return this.permitted() && this.bluetoothOn();
  }

  /**
   * 读取系统配对名单。
   *
   * 单台设备的查询失败只影响那一台（字段留兜底值），不影响整张名单 ——
   * 「部分可用」比「全有或全无」更符合用户预期：看不到名字总比看不到设备好。
   */
  list(): PairedDeviceEntry[] {
    const result: PairedDeviceEntry[] = [];
    if (!this.available()) return result;
    let addresses: string[] | undefined = undefined;
    try {
      addresses = connection.getPairedDevices();
    } catch (error) {
      logger.warn(TAG, '读取系统配对名单失败: ' + this.errorMessage(error));
      return result;
    }
    if (addresses === undefined || addresses.length === 0) return result;
    for (let index: number = 0; index < addresses.length; index += 1) {
      const raw: string | undefined = addresses[index];
      if (raw === undefined) continue;
      const address: string = raw;
      if (address.length === 0) continue;
      result.push(this.readEntry(address));
    }
    this.markInUse(result);
    return result;
  }

  /**
   * 单个地址的名称查询，带进程内缓存。
   *
   * 认领向导要多次显示同一个名字（列表、确认页、寻找页标题），
   * 每次都问系统一遍既慢又会产生一串 IPC 日志。
   * 缓存**只写入查询成功的结果**（包括「查到了但确实没名字」的空串）：
   * 抛异常时说明这次没问成（权限刚被撤销、蓝牙刚关），不该把失败永久钉在缓存里。
   */
  nameOf(address: string): string {
    const key: string = address.trim();
    if (key.length === 0) return '';
    const cached: string | undefined = this.nameCache.get(key);
    if (cached !== undefined) return cached;
    if (!this.available()) return '';
    return this.fetchName(key);
  }

  /** 读一台设备的全部只读字段；任何一步失败都只影响对应字段。 */
  private readEntry(address: string): PairedDeviceEntry {
    const entry: PairedDeviceEntry = new PairedDeviceEntry();
    entry.address = address;
    entry.name = this.fetchName(address);
    // persistentId 恒为空串：见 PairedDeviceEntry.persistentId 的说明。
    entry.persistentId = '';
    const deviceClass: connection.DeviceClass | undefined = this.fetchDeviceClass(address);
    if (deviceClass !== undefined) {
      entry.deviceClass = deviceClass.classOfDevice;
      // 系统给的两个枚举是**已左移**的写法（MAJOR_AUDIO_VIDEO = 0x0400、
      // AUDIO_VIDEO_HEADPHONES = 0x0418），右移回 5 位 / 6 位才是 SIG 表里的类别码。
      // 不做这一步的话，下游 `kindFromDeviceClass` 会把每一台音频设备都当成 OTHER。
      const major: number = deviceClass.majorClass as number;
      const majorMinor: number = deviceClass.majorMinorClass as number;
      entry.majorClass = (major >> 8) & 0x1F;
      entry.majorMinorClass = (majorMinor >> 2) & 0x3F;
    }
    return entry;
  }

  /**
   * 标记「可能正在使用中」。
   *
   * **为什么这里只能给出「可能」**：API 26 的
   * `connection.getProfileConnectionState(profileId?)` **没有 deviceId 参数**，
   * 它只回答「这个 Profile 此刻有没有连着设备」，不回答「连的是哪一台」。
   * 想精确到某一台，只能自己 `createA2dpSrcProfile()` 之类建出 Profile 对象再调
   * `getConnectionState(deviceId)` —— 那属于连接侧的动作，与「绝不发起连接」相悖，故不用。
   *
   * 策略因此刻意保守：只有当同一家族在名单里**恰好只有一台**时，才把该家族的
   * Profile 连接状态算到它头上；同族有两台（比如两副耳机）一律 false ——
   * 宁可少显示一个「正在使用中」，也不能张冠李戴。
   */
  private markInUse(entries: PairedDeviceEntry[]): void {
    // 四个槽位与上面 FAMILY_NONE/AUDIO/PERIPHERAL/NETWORK 一一对应，下标即家族号。
    const counts: number[] = [0, 0, 0, 0];
    entries.forEach((entry: PairedDeviceEntry): void => {
      counts[this.familyOf(entry.majorClass)] += 1;
    });
    entries.forEach((entry: PairedDeviceEntry): void => {
      const family: number = this.familyOf(entry.majorClass);
      if (family === FAMILY_NONE) return;
      if (counts[family] !== 1) return;
      entry.inUse = this.familyConnected(family);
    });
  }

  /** 主类别码 → 家族。未知类别（含 -1）一律 FAMILY_NONE，不参与「使用中」判定。 */
  private familyOf(majorClass: number): number {
    if (majorClass === MAJOR_AUDIO_VIDEO) return FAMILY_AUDIO;
    if (majorClass === MAJOR_PERIPHERAL) return FAMILY_PERIPHERAL;
    if (majorClass === MAJOR_NETWORKING) return FAMILY_NETWORK;
    return FAMILY_NONE;
  }

  /** 该家族有没有 Profile 处于已连接。任一查询抛异常都按「没连」处理。 */
  private familyConnected(family: number): boolean {
    if (family === FAMILY_AUDIO) {
      // 耳机/音箱同时可能挂 A2DP（听歌）或 HFP（通话），两个都要问。
      return this.profileConnected(constant.ProfileId.PROFILE_A2DP_SOURCE)
        || this.profileConnected(constant.ProfileId.PROFILE_HANDSFREE_AUDIO_GATEWAY);
    }
    if (family === FAMILY_PERIPHERAL) {
      return this.profileConnected(constant.ProfileId.PROFILE_HID_HOST);
    }
    if (family === FAMILY_NETWORK) {
      return this.profileConnected(constant.ProfileId.PROFILE_PAN_NETWORK);
    }
    return false;
  }

  /**
   * 单个 Profile 的连接状态查询。
   *
   * 只认 STATE_CONNECTED：CONNECTING / DISCONNECTING 都是过渡态，
   * 拿过渡态去点亮「正在使用中」会让列表在连接瞬间闪一下，反而让人不信任。
   */
  private profileConnected(profileId: constant.ProfileId): boolean {
    try {
      const state: constant.ProfileConnectionState = connection.getProfileConnectionState(profileId);
      return state === constant.ProfileConnectionState.STATE_CONNECTED;
    } catch (error) {
      logger.warn(TAG, '查询 Profile 连接状态失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 名称查询。成功（含空串结果）才写缓存，见 nameOf 的说明。 */
  private fetchName(address: string): string {
    try {
      const raw: string | undefined = connection.getRemoteDeviceName(address);
      const name: string = raw === undefined ? '' : raw.trim();
      this.nameCache.set(address, name);
      return name;
    } catch (error) {
      // 201/801/2900003/2900099 都在这里：纯 BLE 配对的手环经常根本不响应名称读取。
      logger.warn(TAG, '读取配对设备名称失败: ' + this.errorMessage(error));
      return '';
    }
  }

  /** 类别查询。失败返回 undefined，由调用方把三个字段留在 -1。 */
  private fetchDeviceClass(address: string): connection.DeviceClass | undefined {
    try {
      const deviceClass: connection.DeviceClass | undefined = connection.getRemoteDeviceClass(address);
      if (deviceClass === undefined) return undefined;
      return deviceClass;
    } catch (error) {
      logger.warn(TAG, '读取配对设备类别失败: ' + this.errorMessage(error));
      return undefined;
    }
  }

  /** ACCESS_BLUETOOTH 是否已授予。与 NGF 的 PermissionManagerFacade 用的是同一套 API 形态。 */
  private permitted(): boolean {
    try {
      // 必须带 GET_BUNDLE_INFO_WITH_APPLICATION(0x1)：默认 flag 不返回 appInfo，
      // 拿不到 accessTokenId 就无从校验。
      // 写法与 `ngf_framework/.../PermissionManagerFacade.checkPermission` 逐行对齐：
      // 那是仓库里唯一已验证可编译的取 tokenId + 查授权组合，不另创新写法。
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId: number = info.appInfo.accessTokenId;
      const atManager = abilityAccessCtrl.createAtManager();
      const status: abilityAccessCtrl.GrantStatus = atManager.checkAccessTokenSync(tokenId, ACCESS_BLUETOOTH);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      logger.warn(TAG, '查询蓝牙授权状态失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 蓝牙是否已开启。getState 本身也会抛（服务未起时 2900001），按「没开」处理。 */
  private bluetoothOn(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (error) {
      logger.warn(TAG, '读取蓝牙开关状态失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

export const fieldwatchPairedDevices: FieldwatchPairedDevices = new FieldwatchPairedDevices();
