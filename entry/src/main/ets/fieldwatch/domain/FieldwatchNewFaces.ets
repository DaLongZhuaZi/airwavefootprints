/**
 * 新面孔清单（P2-14）。纯逻辑 + 可单测。
 *
 * 口径（文档原文）：以本机历史 deviceKey 集合为基线，列出
 * 「从未见过 + 信号较强 + 持续出现」的设备。
 *
 * 三个条件缺一不可，理由分别是：
 *   · 从未见过：这正是「新面孔」的定义；
 *   · 信号较强：远处的路人设备天天都不一样，列进来会淹没真正的目标；
 *   · 持续出现：只闪一帧的广播（快照式设备、共享单车锁）不是「在附近的东西」。
 */

import { Sighting } from './FieldwatchModels';

/** 「信号较强」的门槛（dBm）：低于它按噪声处理。 */
export const NEW_FACE_MIN_RSSI: number = -75;
/** 「持续出现」要求的最少观测次数。 */
export const NEW_FACE_MIN_HITS: number = 3;
/** 清单最多展示几条（再多用户不会看，也会拖慢渲染）。 */
export const NEW_FACE_LIMIT: number = 30;

/** 一条新面孔。 */
export class NewFaceEntry {
  public deviceKey: string = '';
  public name: string = '';
  public rssi: number = -127;
  public hits: number = 0;
  public firstSeen: number = 0;
  public lastSeen: number = 0;
  /** 命中的特征名（可为空）。 */
  public signatureName: string = '';
  constructor() {}
}

/**
 * 筛选新面孔。
 *
 * @param sightings 当前实时列表
 * @param baseline  本机历史 deviceKey 集合（基线）
 * @param excluded  已被「这是我家的」移出清单的键
 */
export function newFacesOf(sightings: Sighting[], baseline: string[], excluded: string[],
  signatureNameOf: (sighting: Sighting) => string): NewFaceEntry[] {
  const result: NewFaceEntry[] = [];
  sightings.forEach((item: Sighting): void => {
    if (baseline.indexOf(item.key) >= 0) return;
    if (excluded.indexOf(item.key) >= 0) return;
    // 强度门槛：过滤远处噪声。未测量值（127）必须排除。
    if (item.rssi > 126 || item.rssi < NEW_FACE_MIN_RSSI) return;
    if (item.count < NEW_FACE_MIN_HITS) return;
    const entry: NewFaceEntry = new NewFaceEntry();
    entry.deviceKey = item.key;
    entry.name = item.name;
    entry.rssi = item.rssi;
    entry.hits = item.count;
    entry.firstSeen = item.firstSeen;
    entry.lastSeen = item.lastSeen;
    entry.signatureName = signatureNameOf(item);
    result.push(entry);
  });
  // 排序：先按命中次数（越稳定越靠前），再按强度。
  result.sort((a: NewFaceEntry, b: NewFaceEntry): number => {
    if (a.hits !== b.hits) return b.hits - a.hits;
    return b.rssi - a.rssi;
  });
  if (result.length <= NEW_FACE_LIMIT) return result;
  return result.slice(0, NEW_FACE_LIMIT);
}

/**
 * 基线是否可用。
 *
 * 「本机历史」为空（刚装、刚清过数据）时**不能**说「全是新面孔」：
 * 那会把整个环境都列进来，用户第一次打开就被几十条淹没。
 * 所以基线为空时直接判定不可用，页面显示「先积累一段时间再看」。
 */
export function baselineUsable(baseline: string[]): boolean {
  return baseline.length > 0;
}

/**
 * 家庭场景的「手动开启基线对比」。
 *
 * 文档明确「不做地理围栏自动判定」：由用户自己决定要不要开。
 * 开关状态存在设置里（由应用层负责），这里只给出默认值语义。
 */
export const NEW_FACE_BASELINE_DEFAULT_ON: boolean = false;
