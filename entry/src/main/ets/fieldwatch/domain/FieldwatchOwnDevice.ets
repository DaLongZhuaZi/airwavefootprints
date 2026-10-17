import { GpsSample, RadioKind } from './FieldwatchModels';
import { SignatureClass } from './FieldwatchModels';

/**
 * 自有设备档案（「找东西」认领后存下来的东西）。
 *
 * **为什么单独建模型而不是扩 `WatchTarget`**（文档落地点五的取舍）：
 * 关注体系是「我关心哪些信号」的过滤器语义，自有设备是「这台是我的东西」的身份语义 ——
 * 两者的生命周期与匹配规则完全不同，混在一起迟早互相污染。`WatchTarget` 只在需要
 * 提醒时引用档案 id。
 *
 * **没有 `persistentId` 字段（已核实）**：文档原设计想用
 * `access.addPersistentDeviceId` 做跨蓝牙开关的持久锚，但该接口需要
 * `ohos.permission.PERSISTENT_BLUETOOTH_PEERS_MAC`，在
 * `PermissionDefinitions.json` 中是 `availableLevel=system_basic`（普通应用需 ACL）。
 * 因此身份稳定性只能靠「配对期内的虚拟地址 + 指纹兜底」，这也正是文档预留的降级分支。
 */
export class OwnDeviceFingerprint {
  /** 广播名（认领那一刻的名字，不是用户改名）。 */
  public name: string = '';
  /** BLE 厂商数据（不含 Company ID），与 `RadioFacts.manufacturerDataHex` 同源。 */
  public manufacturerDataHex: string = '';
  /** 服务 UUID 集（BLE）或厂商 IE OUI（Wi-Fi）。 */
  public serviceUuids: string[] = [];
  /** 认领时命中的签名 id。 */
  public signatureIds: string[] = [];
}

export class OwnDevice {
  /** 本机档案 id（本地生成，非系统 id）。 */
  public id: string = '';
  /** 用户可见名称：系统名 / 广播名 / 用户改名。 */
  public displayName: string = '';
  public kind: RadioKind = RadioKind.BLE;
  /**
   * 配对期内的快速锚（BLE/Wi-Fi 是系统虚拟地址或 BSSID，星闪是当次 deviceId）。
   *
   * 可以为空：星闪 v1 只现扫现认时若用户没记地址，就只有指纹可用。
   */
  public virtualAddress: string = '';
  /**
   * 该地址的稳定性是否已被真机证实。
   *
   * **默认 false**，只有文档 §八 的 V1（BLE）/V5（星闪）/V6-b（Wi-Fi）在真机上确认
   * 地址稳定后才由代码置 true。UI 在 false 时如实提示「下次可能需要重新认领」——
   * 这比让用户以为它永远认得出来要诚实。
   */
  public addressStable: boolean = false;
  public category: SignatureClass = SignatureClass.OTHER;
  public fingerprint: OwnDeviceFingerprint = new OwnDeviceFingerprint();
  /** 用户按过「这不是我的」的指纹（同一型号的别人的设备）。 */
  public denyFingerprints: OwnDeviceFingerprint[] = [];
  public lastSeenAt: number = 0;
  public lastLocation: GpsSample | undefined = undefined;
  public createdAt: number = 0;
  /** 认领来源：'paired' | 'scan' | 'current_ap'（记录用户是从哪条路认领的，便于排查）。 */
  public claimSource: string = '';
}
