import { GpsSample, RadioKind, Sighting } from './FieldwatchModels';
import { OwnDevice } from './FieldwatchOwnDevice';

/**
 * 「上次见到」的观测回写（文档落地点二的隐藏价值）。
 *
 * 文档原话：「断开时刻就是最可信的 lastSeen。耳机放下摘除、车熄火断开的瞬间记一条记录，
 * 『上次见到』从此是事件级的，不是扫描碰运气。」
 *
 * 之前只有用户点「找到了」才会回写 —— 那意味着**用户没在找的时候，档案里的时间是死的**，
 * 而「上次见到」恰恰是 GONE 状态下唯一能给用户的线索。这里把它补成观测驱动。
 *
 * 纯逻辑：输入档案 + 实时观测，输出「哪些档案需要把 lastSeen 推到什么时刻」，
 * 由调用方落库（本文件不碰 RDB，便于单测）。
 */

/** 同一条档案两次回写之间的最小间隔（避免每秒都写一次数据库）。 */
export const OWN_DEVICE_STAMP_MIN_GAP_MS: number = 10000;

/** 一条待回写。 */
export class OwnDeviceStamp {
  public deviceId: string = '';
  public seenAt: number = 0;
  public location: GpsSample | undefined = undefined;
}

/**
 * 观测是否能认出这台自有设备。
 *
 * - BLE / 星闪：**地址直配**（V1 真机已证实：配对虚拟地址 == 扫描 deviceId）；
 * - Wi-Fi：**地址或名字，命中其一即可**。
 *
 * Wi-Fi 为什么是「或」：V6-b 已核实没有 `GET_WIFI_PEERS_MAC` 时系统返回的是随机/遮蔽 bssid，
 * 所以**不能只信地址**；但 2026-10-16 直接读设备库的两次采样（应用重启前后）显示，
 * 同一个 AP 的地址在**会话内是稳定的**（`DLZZ_5G` 始终 `12:a1:84…`，且 `getLinkedInfoSync`
 * 与 `getScanInfoList` 给的是同一个值）—— 那么地址可用时按地址认更精确，
 * 地址变了再由名字兜住。跨系统重启是否变仍未知，所以是「或」而不是「只用地址」。
 */
function observationMatches(device: OwnDevice, sighting: Sighting): boolean {
  if (device.kind !== sighting.kind) return false;
  const byAddress: boolean = device.virtualAddress.length > 0 && device.virtualAddress === sighting.address;
  if (device.kind !== RadioKind.WIFI) return byAddress;
  const byName: boolean = device.displayName.length > 0 && device.displayName === sighting.name;
  return byAddress || byName;
}

/**
 * 按地址找档案 id。
 *
 * **连接事件的专用入口**：Profile 的连接状态变化只给一个地址（没有名字、没有观测），
 * 而这条路径恰恰是最有价值的一条 —— 经典蓝牙设备**连着时通常不广播**，
 * 观测回写根本采不到它；断开那一刻才是事件级的证据（文档落地点二的隐藏价值）。
 *
 * 只认 BLE：只有经典侧能拿到连接事件；星闪与 Wi-Fi 不走这条。
 *
 * @returns 命中的档案 id；没有则空串
 */
export function ownDeviceIdForAddress(devices: OwnDevice[], kind: RadioKind, address: string): string {
  if (address.length === 0) return '';
  const hits: OwnDevice[] = devices.filter((device: OwnDevice): boolean =>
    device.kind === kind && device.virtualAddress.length > 0 && device.virtualAddress === address);
  return hits.length > 0 ? hits[0].id : '';
}

/**
 * 算出需要回写的档案。
 *
 * **只推进、不回退**：观测时刻比档案里已有的还旧时不动它（乱序到达的观测不能让
 * 「上次见到」倒退）。间隔小于 `minGapMs` 的也不写，避免把一个 2 秒刷新变成写库风暴。
 */
export function ownDevicesToStamp(
  devices: OwnDevice[],
  sightings: Sighting[],
  now: number,
  minGapMs: number = OWN_DEVICE_STAMP_MIN_GAP_MS
): OwnDeviceStamp[] {
  const out: OwnDeviceStamp[] = [];
  devices.forEach((device: OwnDevice): void => {
    let best: Sighting | undefined = undefined;
    sightings.forEach((sighting: Sighting): void => {
      if (!observationMatches(device, sighting)) return;
      if (best === undefined || sighting.lastSeen > best.lastSeen) best = sighting;
    });
    if (best === undefined) return;
    const hit: Sighting = best;
    if (hit.lastSeen <= device.lastSeenAt) return;
    // 距上次回写太近就跳过；但**首次回写**（档案里还没有时间）不受间隔限制。
    if (device.lastSeenAt > 0 && now - device.lastSeenAt < minGapMs) return;
    const stamp: OwnDeviceStamp = new OwnDeviceStamp();
    stamp.deviceId = device.id;
    stamp.seenAt = hit.lastSeen;
    stamp.location = hit.location;
    out.push(stamp);
  });
  return out;
}
