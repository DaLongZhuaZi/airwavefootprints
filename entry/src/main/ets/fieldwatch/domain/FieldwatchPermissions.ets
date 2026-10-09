import { Permissions } from '@kit.AbilityKit';

/**
 * Fieldwatch 的权限目录。
 *
 * **命名必须与系统设置里显示的项目逐字一致** —— 用户在应用里看到的叫法，
 * 必须能让他在系统设置里直接找到对应项，否则说明就是无效的。
 *
 * 系统设置里本应用的用户可见项（真机截图确认）为：
 *   位置 / 设备发现和连接 / 应用获取设备方向 / 运动数据 / 应用联网 / 通知
 *
 * **不需要用户授权的权限绝不能列进来**：
 *   - GET_WIFI_INFO / SET_WIFI_INFO 是 system_grant，安装即授予，
 *     系统设置里没有对应项，用户无从「授予」——把它写成一条待申请权限是错的。
 *   - INTERNET 同样是 system_grant，对应系统设置里的「应用联网」（数据开关），
 *     不是一个可以「同意/拒绝」的授权项。
 *
 * 因此真正需要用户授权的只有下面两条；Wi-Fi 扫描能力始终可用，不依赖任何授权。
 */
export enum FieldwatchPermissionKind {
  /** 系统设置里的「设备发现和连接」（ohos.permission.ACCESS_BLUETOOTH）。 */
  BLUETOOTH = 'BLUETOOTH',
  /** 系统设置里的「位置」（ohos.permission.APPROXIMATELY_LOCATION）。 */
  LOCATION = 'LOCATION',
  /**
   * 星闪（NearLink）扫描（ohos.permission.ACCESS_NEARLINK）。
   *
   * 实测为 user_grant / normal / NORMAL，不涉及 ACL。
   * 仅在设备支持星闪时才向用户申请 —— 无此硬件的设备上不该索要用不到的权限。
   */
  NEARLINK = 'NEARLINK'
}

/** 一条权限的完整说明。 */
export class FieldwatchPermissionSpec {
  public kind: FieldwatchPermissionKind;
  /** 系统权限名（首条），用于 checkAccessTokenSync / requestPermissionsFromUser。 */
  public permissionId: Permissions;
  /**
   * 该系统设置项**实际覆盖的全部底层权限**。
   *
   * 一个系统设置项可能对应多条底层权限 —— 例如「设备发现和连接」同时管
   * `ACCESS_BLUETOOTH` 与 `ACCESS_NEARLINK`。用户看到的是**一项**，
   * 因此应用内也只能显示一项，申请时把缺失的逐条补齐。
   */
  public permissionIds: Permissions[];
  /** 标题：**与系统设置里的名称逐字一致**。 */
  public titleKey: string;
  /** 这条权限用来干什么。 */
  public whyKey: string;
  /** 它支撑哪些功能。 */
  public featureKey: string;
  /** 拒绝后无法使用的功能（只写失去什么，不写还有什么能用）。 */
  public deniedKey: string;
  /** 在系统设置里的所在位置提示，帮助用户按名找到。 */
  public whereKey: string;

  constructor(
    kind: FieldwatchPermissionKind,
    permissionId: Permissions,
    titleKey: string,
    whyKey: string,
    featureKey: string,
    deniedKey: string,
    whereKey: string
  ) {
    this.kind = kind;
    this.permissionId = permissionId;
    this.permissionIds = [permissionId];
    this.titleKey = titleKey;
    this.whyKey = whyKey;
    this.featureKey = featureKey;
    this.deniedKey = deniedKey;
    this.whereKey = whereKey;
  }
}

/** 权限目录（顺序即引导页与设置页的展示顺序）。 */
export function buildPermissionSpecs(): FieldwatchPermissionSpec[] {
  const specs: FieldwatchPermissionSpec[] = [];
  specs.push(new FieldwatchPermissionSpec(
    FieldwatchPermissionKind.BLUETOOTH,
    'ohos.permission.ACCESS_BLUETOOTH',
    'app.string.fieldwatch_perm_ble_title',
    'app.string.fieldwatch_perm_ble_why',
    'app.string.fieldwatch_perm_ble_feature',
    'app.string.fieldwatch_perm_ble_denied',
    'app.string.fieldwatch_perm_ble_where'
  ));
  // 「设备发现和连接」在系统设置里同时管蓝牙与星闪，因此这一条覆盖两个底层权限。
  specs[0].permissionIds = ['ohos.permission.ACCESS_BLUETOOTH', 'ohos.permission.ACCESS_NEARLINK'];
  specs.push(new FieldwatchPermissionSpec(
    FieldwatchPermissionKind.LOCATION,
    'ohos.permission.APPROXIMATELY_LOCATION',
    'app.string.fieldwatch_perm_loc_title',
    'app.string.fieldwatch_perm_loc_why',
    'app.string.fieldwatch_perm_loc_feature',
    'app.string.fieldwatch_perm_loc_denied',
    'app.string.fieldwatch_perm_loc_where'
  ));
  return specs;
}

/**
 * 不需要任何权限即可使用的功能清单（引导页与受限态共用，避免两处说法不一致）。
 */
export const FIELDWATCH_BASELINE_FEATURE_KEYS: string[] = [
  'app.string.fieldwatch_baseline_catalog',
  'app.string.fieldwatch_baseline_wifi',
  'app.string.fieldwatch_baseline_log',
  'app.string.fieldwatch_baseline_report',
  'app.string.fieldwatch_baseline_settings'
];

/** 与上面一一对应的图标（顺序必须一致）。 */
export const FIELDWATCH_BASELINE_SYMBOLS: string[] = [
  'sys.symbol.list_checkmark',
  'sys.symbol.wifi',
  'sys.symbol.clock',
  'sys.symbol.doc_text',
  'sys.symbol.gearshape'
];

/** 一条权限的当前状态。 */
export class FieldwatchPermissionStatus {
  public kind: FieldwatchPermissionKind;
  public granted: boolean;
  constructor(kind: FieldwatchPermissionKind, granted: boolean) {
    this.kind = kind;
    this.granted = granted;
  }
}

/**
 * 能力快照。
 *
 * **Wi-Fi 不在其中**：Wi-Fi 信息由系统自动授予，始终可用，
 * 所以「能不能扫描」不存在 Wi-Fi 维度，只看蓝牙。
 */
export class FieldwatchCapabilitySnapshot {
  public bluetooth: boolean = false;
  public location: boolean = false;
  /** 星闪扫描权限；设备不支持星闪时保持 false，且不参与申请。 */
  public nearlink: boolean = false;
  /** 蓝牙授权后即可接收 BLE 广播；Wi-Fi 部分始终可用。 */
  canScanBle(): boolean { return this.bluetooth; }
  /** 是否处于「BLE 不可用、只能看 Wi-Fi」的降级状态。 */
  bleUnavailable(): boolean { return !this.bluetooth; }
  grantedCount(): number {
    let count: number = 0;
    if (this.bluetooth) count += 1;
    if (this.location) count += 1;
    if (this.nearlink) count += 1;
    return count;
  }
}