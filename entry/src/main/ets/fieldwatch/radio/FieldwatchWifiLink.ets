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
  /**
   * 频段（MHz）。
   *
   * 优先取 `WifiLinkedInfo.band`；**部分设备该字段返回 0**
   * （真机实测：DLZZ_5G 的 band=0，导致详情页显示「未知频段」、信道算不出来），
   * 此时用 `WifiLinkedInfo.frequency` 兜底。0 表示确实拿不到。
   */
  public band: number = 0;
  /** BSSID 是否可作为长期锚：本 App 恒为 false（见文件头说明）。 */
  public bssidStable: boolean = false;
}

/**
 * 把系统给的 band 枚举 + frequency 换算成 **MHz**。
 *
 * 为什么需要这一步（真机实证）：
 *   `WifiLinkedInfo.band` 是**枚举**而不是频率 —— 实测 band=2 对应 freq=5260（5G）。
 *   把它当 MHz 用，会让频段判定与信道推算全部失效（详情页显示「未知频段」）。
 *
 * 换算优先级：**frequency 优先**（它是真实频点，最可靠）；
 * frequency 不可用时，按枚举给一个该频段的代表频点 —— 足以让「2.4G / 5G」判对，
 * 但信道会不准，所以此时 `WifiCurrentAp.bandExact` 应为 false（调用方据此不展示信道）。
 *
 * @returns 频段（MHz）；两者都不可用返回 0
 */
export function bandToMhz(bandEnum: number, frequency: number): number {
  if (frequency > 0) return frequency;
  // 枚举兜底：1 = 2.4G，2 = 5G（本机 SDK 语义）。
  if (bandEnum === 1) return 2437;
  if (bandEnum === 2) return 5180;
  return 0;
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
      // **`band` 不是 MHz，是枚举**（真机 hilog 实证：band=2 对应 freq=5260 的 5G 网络）。
      // 早前把它当 MHz 直接喂给详情页，才出现「未知频段、信道算不出」。
      // 详情页要的是 MHz，所以这里统一换算成 MHz —— **以 frequency 为准**（它才是真频率），
      // frequency 不可用时再按枚举推一个代表频点。
      ap.band = bandToMhz(info.band, info.frequency);
      logger.debug(TAG, '当前 AP: band枚举=' + info.band.toString() + ' frequency=' + info.frequency.toString()
        + ' -> bandMhz=' + ap.band.toString());
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
