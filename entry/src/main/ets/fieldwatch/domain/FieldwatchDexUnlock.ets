/**
 * 图鉴首次点亮弹层（P3-3 第 2 项）。纯逻辑 + 可单测。
 *
 * 硬要求（文档原文）：「只在首次点亮时出现，不得每次进页弹」。
 *
 * 因此判据必须落在**持久化的「已弹过」集合**上，而不是「本次会话里见过没有」——
 * 后者在重进页面、切标签、重装（数据还在时）都会重复弹，正是要避免的骚扰。
 */

import { DexEntry } from './FieldwatchDex';

/** 一次「新点亮」的摘要，供弹层渲染。 */
export class DexUnlock {
  public fleetId: string = '';
  public name: string = '';
  /** 类别资源键。 */
  public categoryKey: string = '';
  /** 稀有度资源键。 */
  public rarityKey: string = '';
  /** 点亮前的积分与点亮后的积分（弹层要展示「进度变化」）。 */
  public scoreBefore: number = 0;
  public scoreAfter: number = 0;
  /** 点亮前的等级标题键与之后（跨级时弹层要额外说「升级了」）。 */
  public levelBeforeKey: string = '';
  public levelAfterKey: string = '';
  constructor() {}
  /** 本次点亮带来的分数增量。 */
  delta(): number { return this.scoreAfter - this.scoreBefore; }
  /** 是否跨级（等级变化）。 */
  leveledUp(): boolean {
    return this.levelBeforeKey.length > 0 && this.levelAfterKey.length > 0
      && this.levelBeforeKey !== this.levelAfterKey;
  }
}

/**
 * 找出「刚刚第一次点亮」的条目。
 *
 * @param entries 当前图鉴（已按 seen 标记）
 * @param announced 已经弹过层的 fleetId 集合（持久化）
 * @returns 需要弹层的解锁项；**一次最多返回一个**（同时点亮多台时只弹最新的，
 *          否则用户会被连续弹层打断 —— 这是「不骚扰」的同一个原则）。空数组表示不弹。
 */
export function pendingUnlock(entries: DexEntry[], announced: string[]): DexEntry[] {
  const fresh: DexEntry[] = [];
  entries.forEach((entry: DexEntry): void => {
    if (!entry.seen) return;
    if (announced.indexOf(entry.fleetId) >= 0) return;
    fresh.push(entry);
  });
  if (fresh.length === 0) return [];
  // 只取一条：最近见到的那个（lastSeenAt 最大）最贴近用户刚做的事。
  fresh.sort((a: DexEntry, b: DexEntry): number => b.lastSeenAt - a.lastSeenAt);
  const out: DexEntry[] = [];
  out.push(fresh[0]);
  return out;
}

/**
 * 把「已弹过」集合与实际已点亮的条目对齐。
 *
 * 为什么要对齐：老用户的图鉴里早就有几十条点亮，如果直接把「已点亮」当作「该弹」，
 * 升级到本版本时会一次涌出几十个弹层。所以**第一次进入时先把现状全部标记为已弹**，
 * 之后只有真正新增的点亮才弹。
 *
 * @returns 应当持久化的「已弹」集合
 */
export function reconcileAnnounced(entries: DexEntry[], announced: string[]): string[] {
  const result: string[] = [];
  announced.forEach((id: string): void => {
    if (result.indexOf(id) < 0) result.push(id);
  });
  entries.forEach((entry: DexEntry): void => {
    if (!entry.seen) return;
    if (result.indexOf(entry.fleetId) < 0) result.push(entry.fleetId);
  });
  return result;
}

/** 把标记集编解码成存储字符串（换行分隔，与排查清单同一套做法）。 */
export function encodeAnnounced(ids: string[]): string {
  return ids.join('\n');
}

export function decodeAnnounced(text: string): string[] {
  if (text.length === 0) return [];
  return text.split('\n').filter((item: string): boolean => item.trim().length > 0);
}
