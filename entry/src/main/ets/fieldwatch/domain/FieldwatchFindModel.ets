/**
 * 「找东西」日常版的数据装配（纯逻辑，不碰 UI、不碰系统 API）。
 *
 * 为什么单独一层：这个页面要同时展示三批候选 ——
 *   ① 系统配对名单（只读，未认领）
 *   ② 已认领的自有设备
 *   ③ 最近听到的设备（认领入口）
 * 三批之间有去重与优先顺序（已认领的不再出现在配对/扫描列表里），
 * 这套规则放进页面会既难测又容易在改版时漂移。
 */

import { OwnDeviceProfile, deviceAddressOfKey, normalizeDeviceAddress } from './FieldwatchOwnDevice';

/** 一条「可找/可认领」的候选。UI 只读它，不再自己拼装。 */
export class FindCandidate {
  /** 扫描键（'ble:AA:BB'）；来自配对名单时由地址拼出，保证与 Sighting.key 同口径。 */
  public deviceKey: string;
  public address: string;
  public name: string;
  /** 已认领时指向档案 id；空串表示还没认领。 */
  public profileId: string;
  /** 来源：'paired'（系统配对名单）| 'own'（已认领）| 'scan'（最近听到）。 */
  public source: string;
  /** 当前是否正连着手机（仅配对名单能判定；其余恒 false）。 */
  public inUse: boolean;
  /** 最近一次听到的时间；0 表示未知。 */
  public lastSeenAt: number;
  constructor(deviceKey: string = '', address: string = '', name: string = '', profileId: string = '',
    source: string = 'scan', inUse: boolean = false, lastSeenAt: number = 0) {
    this.deviceKey = deviceKey;
    this.address = address;
    this.name = name;
    this.profileId = profileId;
    this.source = source;
    this.inUse = inUse;
    this.lastSeenAt = lastSeenAt;
  }
  /** 有档案就是已认领；UI 据此决定显示「这是我的」还是「开始找」。 */
  claimed(): boolean { return this.profileId.length > 0; }
}

/**
 * 把「已认领档案」接到实时扫描结果上，取出它当前的扫描键。
 *
 * 为什么需要它：档案里存的是认领那一刻的地址/键，重新配对后地址可能变；
 * 用户点「我的耳机」时真正要 Hunt 的是**此刻正在广播的那个键**。
 * 匹配交给 matcher（地址 → 指纹），这里只做「按 deviceKey 找同一台」的兜底：
 * 地址一致、或扫描键里的地址一致，就算同一台。
 */
export function resolveLiveKey(profile: OwnDeviceProfile, liveKeys: string[]): string {
  if (profile.deviceKey.length > 0 && liveKeys.indexOf(profile.deviceKey) >= 0) return profile.deviceKey;
  const target: string = normalizeDeviceAddress(profile.virtualAddress);
  if (target.length === 0) return '';
  for (let index: number = 0; index < liveKeys.length; index += 1) {
    const key: string = liveKeys[index];
    if (normalizeDeviceAddress(deviceAddressOfKey(key)) === target) return key;
  }
  return '';
}

/**
 * 合并三批候选，按「已认领 → 配对名单 → 最近听到」排序，并按地址去重。
 *
 * 去重口径用**归一化地址**而不是 deviceKey：配对名单只有地址没有键，
 * 已认领档案可能也只有其一；用键去重会让同一台设备同时出现在两栏里。
 * 已认领的条目优先保留（它带着 profileId，点进去能直接开找）。
 */
export function mergeFindCandidates(claimed: FindCandidate[], paired: FindCandidate[], scanned: FindCandidate[]): FindCandidate[] {
  const out: FindCandidate[] = [];
  const seen: string[] = [];
  const push = (item: FindCandidate): void => {
    const address: string = normalizeDeviceAddress(item.address.length > 0 ? item.address : deviceAddressOfKey(item.deviceKey));
    const key: string = address.length > 0 ? address : item.deviceKey;
    if (key.length === 0) return;
    if (seen.indexOf(key) >= 0) return;
    seen.push(key);
    out.push(item);
  };
  claimed.forEach(push);
  paired.forEach(push);
  scanned.forEach(push);
  return out;
}

/**
 * 排查卡的三条建议键（WAITING 超时后自动展开）。
 *
 * 按目标类型给不同的第三条：耳机多半在盒里、车钥匙多半在包/口袋、
 * 追踪器可能贴在某件东西上。**只给三条**，多了用户不会读。
 * 返回资源键而不是文案：日常页禁术语，文案必须在资源文件里统一把关。
 */
export function findTroubleKeys(kind: string): string[] {
  const keys: string[] = [
    'app.string.fieldwatch_find_trouble_1',
    'app.string.fieldwatch_find_trouble_2',
  ];
  if (kind === 'headphones' || kind === 'speaker') keys.push('app.string.fieldwatch_find_trouble_3');
  else keys.push('app.string.fieldwatch_find_trouble_4');
  return keys;
}

/** WAITING 超过这个时长就认为「该给排查建议了」。 */
export const FIND_TROUBLE_AFTER_MS: number = 10000;
/** 「晃一晃确认」判定的窗口与离散度阈值。 */
export const FIND_WIGGLE_WINDOW_MS: number = 3000;
export const FIND_WIGGLE_SPREAD_DB: number = 8;
