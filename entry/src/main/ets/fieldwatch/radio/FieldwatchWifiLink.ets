import { BusinessError } from '@kit.BasicServicesKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchWifiLink';

/**
 * 当前连着的那个 AP —— 「找路由器」认领捷径卡的数据来源。
 *
 * **接口名按 SDK 实况修正**：文档里写的 `getConnectedInfo()` 在 API 26 SDK 中
 * **不存在**（`@ohos.wifiManager.d.ts` 里命中 0 次），实际接口是
 * `getLinkedInfo()` / `getLinkedInfoSync()`。这里用同步版本：
 * 认领卡是在渲染时读一次的快照，没必要为它引入 Promise 与竞态。
 *
 * **BSSID 不能当长期锚（已核实）**：`@ohos.wifiManager.d.ts` 多处注释写明
 * 「If does't have the permission of `ohos.permission.GET_WIFI_PEERS_MAC`,
 * return **random bssid**」，而该权限在 `PermissionDefinitions.json` 里是
 * `availableLevel=system_basic`（普通应用需 ACL），本 App 未声明。
 * 所以 `bssidStable` 恒为 false，UI 与 Matcher 都**不要**用 BSSID 认同一台路由器；
 * Wi-Fi 目标只能靠 **SSID + 当前连接关系 + RSSI 行为**识别，并如实告知用户
 * 「同名网络无法区分」。
 */
export class WifiCurrentAp {
  public ssid: string = '';
  /** 系统给的 bssid；无 GET_WIFI_PEERS_MAC 时是随机值，**仅供当次会话内参考**。 */
  public bssid: string = '';
  public rssi: number = 0;
  /** 频段（MHz）。 */
  public band: number = 0;
  /** BSSID 是否可作为长期锚：本 App 恒为 false（见文件头说明）。 */
  public bssidStable: boolean = false;
}

/** 平台接口：把系统调用收敛在这里，便于注入假实现单测。 */
export interface IFieldwatchWifiLinkPlatform {
  isWifiActive(): boolean;
  readLinkedInfo(): WifiCurrentAp;
}

export class HarmonyWifiLinkPlatform implements IFieldwatchWifiLinkPlatform {
  isWifiActive(): boolean {
    try {
      return wifiManager.isWifiActive();
    } catch (error) {
      return false;
    }
  }

  readLinkedInfo(): WifiCurrentAp {
    const ap: WifiCurrentAp = new WifiCurrentAp();
    try {
      const info: wifiManager.WifiLinkedInfo = wifiManager.getLinkedInfoSync();
      ap.ssid = info.ssid;
      ap.bssid = info.bssid;
      ap.rssi = info.rssi;
      ap.band = info.band;
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.debug(TAG, '读当前 AP 失败（未连 Wi-Fi 或未授权）code=' + failure.code);
    }
    return ap;
  }
}

/**
 * 「当前 AP」查询门面。
 *
 * 只做一件事：把「有没有连 Wi-Fi、连的是谁」变成一个可以放心画在认领卡上的对象。
 * 未连接 / 未授权 / 读失败时 `current()` 返回 undefined —— 调用方据此**不显示**捷径卡，
 * 而不是显示一张空白卡让用户猜。
 */
export class FieldwatchWifiLink {
  private readonly platform: IFieldwatchWifiLinkPlatform;

  constructor(platform: IFieldwatchWifiLinkPlatform = new HarmonyWifiLinkPlatform()) {
    this.platform = platform;
  }

  /** 当前 AP；没连、没权限或读失败都返回 undefined。 */
  current(): WifiCurrentAp | undefined {
    if (!this.platform.isWifiActive()) return undefined;
    const ap: WifiCurrentAp = this.platform.readLinkedInfo();
    // SSID 为空说明系统没给出可用信息（例如被置空）——按「拿不到」处理，
    // 不能凭一个空名字做认领（那会把用户带到一个认不出是谁的目标上）。
    if (ap.ssid.length === 0) return undefined;
    return ap;
  }
}
