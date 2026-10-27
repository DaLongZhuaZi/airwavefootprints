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
/**
 * 按类别预计算「同类有多少条」。
 *
 * **这是性能修复点（P3-1 第 4 项）**：原来的 `rarityOf` 对每一条 fleet 都要遍历
 * 整个特征库数同类数量 —— 611 条就是 611×611 ≈ 37 万次比较，进页即卡。
 * 现在全库只扫一遍得到「类别 → 条数」，之后每条 O(1) 查。
 */
export function classCountsOf(allFleets: SignatureFleet[]): Map<string, number> {
  const counts: Map<string, number> = new Map<string, number>();
  allFleets.forEach((item: SignatureFleet): void => {
    const key: string = String(item.category);
    const current: number | undefined = counts.get(key);
    counts.set(key, current === undefined ? 1 : current + 1);
  });
  return counts;
}

/**
 * 用**预计算的类计数**算一个 fleet 的稀有度。
 *
 * 只提供 Map 版本（不再有「传全库数组」的重载）：那样调用方想写出 O(n²) 都做不到，
 * 性能问题从接口形状上消失，而不是靠注释提醒。
 */
export function rarityOf(fleet: SignatureFleet, counts: Map<string, number>): DexRarity {
  if (isEpicClass(fleet.category)) return DexRarity.EPIC;
  const sameClass: number | undefined = counts.get(String(fleet.category));
  const total: number = sameClass === undefined ? 0 : sameClass;
  if (total >= DEX_COMMON_COUNT) return DexRarity.COMMON;
  if (total < DEX_RARE_COUNT) return DexRarity.RARE;
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
  // 类计数只算一次，供全表复用（原来是每条 fleet 各扫一遍全库）。
  const counts: Map<string, number> = classCountsOf(allFleets);
  allFleets.forEach((fleet: SignatureFleet): void => {
    if (!fleet.enabled) return;
    const entry: DexEntry = new DexEntry(fleet.id, fleet.name);
    entry.category = fleet.category;
    entry.rarity = rarityOf(fleet, counts);
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

/**
 * 把历史里的旧 fleetId 映射到当前特征库的 id（按 **fleet 名归一**）。
 *
 * 为什么需要（P3-1「联动」）：点亮存在观测表的 `signature_ids` 里，那串 id 是
 * **当时那版特征库**的 id。特征库在线更新后，同一条 fleet 可能换了 id ——
 * 不做映射的话，用户的旧点亮会集体失效（图鉴突然「变空」）。
 *
 * 归一键用 fleet 名（小写去空白）而不是 id：名字是稳定的人类可读标识，
 * id 是内部键、会随库版本变化。同名重名时以**先出现的**为准（与排序口径一致）。
 *
 * @returns 历史 id → 当前 id 的映射；对不上的旧 id 不出现在结果里（其点亮会丢，
 *          但这是数据里确实找不到对应 fleet 的情况，不编造匹配）。
 */
export function mapLegacyIds(allFleets: SignatureFleet[], legacyIds: string[]): Map<string, string> {
  const mapping: Map<string, string> = new Map<string, string>();
  if (legacyIds.length === 0) return mapping;
  // 当前库的 id 集合：已经能对上的旧 id 直接跳过，省掉后面的名字比对。
  const currentIds: Map<string, string> = new Map<string, string>();
  allFleets.forEach((fleet: SignatureFleet): void => { currentIds.set(fleet.id, fleet.id); });
  const byName: Map<string, string> = new Map<string, string>();
  allFleets.forEach((fleet: SignatureFleet): void => {
    const key: string = nameKeyOf(fleet.name);
    if (key.length === 0) return;
    if (byName.get(key) === undefined) byName.set(key, fleet.id);
  });
  legacyIds.forEach((oldId: string): void => {
    if (currentIds.get(oldId) !== undefined) {
      mapping.set(oldId, oldId);
      return;
    }
    // 旧 id 已不存在：尝试把它当成「名字」再匹配一次（有些历史库把名字当 id 存过）。
    const byNameHit: string | undefined = byName.get(nameKeyOf(oldId));
    if (byNameHit !== undefined) mapping.set(oldId, byNameHit);
  });
  return mapping;
}

/** fleet 名归一键：小写、去首尾空白、压缩内部空白。 */
export function nameKeyOf(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

/** 未点亮的条目显示成「？？？」，不泄露名字。 */
export function dexDisplayName(entry: DexEntry): string {
  return entry.seen ? entry.name : '？？？';
}
