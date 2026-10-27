/**
 * 设备图鉴的稀有度与点亮规则（P2-11）。纯逻辑 + 可单测。
 *
 * 图鉴的设计目标：把「我见过哪些设备」变成一个有进展感的东西。
 * 因此规则必须满足两点：
 *   ① **可对账** —— 图鉴上的每一个数字都能从历史观测里数出来，不引入任何估算；
 *   ② **稀有度有依据** —— 不能凭感觉给「稀有」，要按特征库里的实际数量算。
 */

import { SignatureClass } from './FieldwatchModels';
import { SignatureFleet } from './signatures/FieldwatchSignatureModels';

/**
 * 稀有度档位。
 *
 * 判定看的是「该类特征在特征库里有多少条」：库里越少，见到一次越稀奇。
 * 这是**可对账**的口径 —— 同一份特征库、同一份历史，算出来的档位永远一样。
 */
export enum DexRarity {
  /** 常见：同类特征 ≥ DEX_COMMON_COUNT 条。 */
  COMMON = 'common',
  /** 少见：同类特征在 稀有 与 常见 之间。 */
  UNCOMMON = 'uncommon',
  /** 稀有：同类特征少于 DEX_RARE_COUNT 条。 */
  RARE = 'rare',
  /** 极稀有：星闪或专业设备类（本身就是少见硬件）。 */
  EPIC = 'epic'
}

/** 同类特征达到这个数量就算「常见」。 */
export const DEX_COMMON_COUNT: number = 20;
/** 同类特征少于这个数量就算「稀有」。 */
export const DEX_RARE_COUNT: number = 5;

/**
 * 星闪与专业设备类一律标稀有。
 *
 * 理由：这类设备本身在生活里就少（星闪终端、执法/监控设备），
 * 而且它们的出现往往正是用户装这个应用想看到的东西 —— 值得单独点亮一下。
 */
export function isEpicClass(category: SignatureClass): boolean {
  if (category === SignatureClass.SURVEILLANCE) return true;
  if (category === SignatureClass.LAW_ENFORCEMENT) return true;
  if (category === SignatureClass.DRONE) return true;
  if (category === SignatureClass.HACKING) return true;
  return false;
}

/**
 * 计算一个 fleet 的稀有度。
 *
 * @param fleet      目标特征
 * @param allFleets  当前特征库全集（用来数同类有多少条）
 */
export function rarityOf(fleet: SignatureFleet, allFleets: SignatureFleet[]): DexRarity {
  if (isEpicClass(fleet.category)) return DexRarity.EPIC;
  let sameClass: number = 0;
  allFleets.forEach((item: SignatureFleet): void => {
    if (item.category === fleet.category) sameClass += 1;
  });
  if (sameClass >= DEX_COMMON_COUNT) return DexRarity.COMMON;
  if (sameClass < DEX_RARE_COUNT) return DexRarity.RARE;
  return DexRarity.UNCOMMON;
}

/** 图鉴里的一条目。 */
export class DexEntry {
  /** 特征库 id。 */
  public fleetId: string = '';
  public name: string = '';
  public category: SignatureClass = SignatureClass.OTHER;
  public rarity: DexRarity = DexRarity.COMMON;
  /** 是否见过（点亮）。 */
  public seen: boolean = false;
  /** 见过几次（按设备计，不是按观测计）。 */
  public sightings: number = 0;
  /** 最近一次见到的时间；0 表示从未。 */
  public lastSeenAt: number = 0;
  constructor(fleetId: string = '', name: string = '') { this.fleetId = fleetId; this.name = name; }
}

/** 图鉴的汇总。 */
export class DexSummary {
  public total: number = 0;
  public seen: number = 0;
  public constructor() {}
  /** 点亮比例 0..1。 */
  ratio(): number { return this.total <= 0 ? 0 : this.seen / this.total; }
  /** 今天新点亮的数量（由调用方传入今日见过的 fleet 集合）。 */
  public newToday: number = 0;
}

/**
 * 组装图鉴。
 *
 * @param allFleets     特征库全集（**只取启用的**：停用的条目不该出现在图鉴里，
 *                      否则用户会对着一个永远点不亮的格子困惑）
 * @param seenFleetIds  历史观测里出现过的 fleetId（含次数与最近时间）
 * @param seenToday     今天首次见到的 fleetId 集合
 */
export function buildDex(allFleets: SignatureFleet[], seenFleetIds: Map<string, number[]>,
  seenToday: string[]): DexEntry[] {
  const entries: DexEntry[] = [];
  allFleets.forEach((fleet: SignatureFleet): void => {
    if (!fleet.enabled) return;
    const entry: DexEntry = new DexEntry(fleet.id, fleet.name);
    entry.category = fleet.category;
    entry.rarity = rarityOf(fleet, allFleets);
    const stats: number[] | undefined = seenFleetIds.get(fleet.id);
    if (stats !== undefined) {
      entry.seen = true;
      entry.sightings = stats[0];
      entry.lastSeenAt = stats[1];
    }
    entries.push(entry);
  });
  return entries;
}

/** 汇总：总数 / 已见 / 今日新增。 */
export function summarizeDex(entries: DexEntry[], seenToday: string[]): DexSummary {
  const summary: DexSummary = new DexSummary();
  summary.total = entries.length;
  let today: number = 0;
  entries.forEach((entry: DexEntry): void => {
    if (entry.seen) summary.seen += 1;
    if (seenToday.indexOf(entry.fleetId) >= 0 && entry.seen) today += 1;
  });
  summary.newToday = today;
  return summary;
}

/**
 * 排序：**已点亮的在前、再按稀有度、最后按名字**。
 *
 * 最初写成「未见的排前面」，真机上一眼就看出问题：特征库有 611 条，
 * 而用户只见过 12 条 —— 未点亮的 599 个格子把已点亮的 12 个彻底埋到了页尾，
 * 「点亮了 12 个」这件事在界面上完全看不见，图鉴就失去了进展感。
 *
 * 现在的口径是「先让我看到我有什么」，翻到底才是「还有什么没点亮」。
 */
export function sortDex(entries: DexEntry[]): DexEntry[] {
  return entries.slice().sort((a: DexEntry, b: DexEntry): number => {
    if (a.seen !== b.seen) return a.seen ? -1 : 1;
    const rankA: number = rarityRank(a.rarity);
    const rankB: number = rarityRank(b.rarity);
    if (rankA !== rankB) return rankB - rankA;
    return a.name.localeCompare(b.name);
  });
}

function rarityRank(rarity: DexRarity): number {
  if (rarity === DexRarity.EPIC) return 4;
  if (rarity === DexRarity.RARE) return 3;
  if (rarity === DexRarity.UNCOMMON) return 2;
  return 1;
}

/** 未点亮的条目显示成「？？？」，不泄露名字。 */
export function dexDisplayName(entry: DexEntry): string {
  return entry.seen ? entry.name : '？？？';
}
