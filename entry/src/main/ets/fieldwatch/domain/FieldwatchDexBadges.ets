/**
 * 图鉴玩法：等级与勋章（P3-2 第 4 项）。纯逻辑 + 可单测。
 *
 * 设计约束（文档原文）：
 *   · 等级按**点亮数与稀有分**升级（观察者 → 探索者 → 猎手 → 大师）；
 *   · 勋章是离散成就（首台星闪 / 首台监控类 / 集齐一类 / 连续 7 天新发现）；
 *   · **稀有度口径不变**（库内同类数量，可对账），文案要注明是「库内稀有度」。
 *
 * 所有计算都只依赖「已点亮的条目」，因此可以拿历史数据对账 ——
 * 等级不会因为界面刷新而漂移。
 */

import { DexEntry, DexRarity } from './FieldwatchDex';

/** 等级门槛：达到该分数即升到对应等级。 */
export class DexLevel {
  public level: number = 0;
  public titleKey: string = '';
  /** 进入该等级所需的最低分。 */
  public threshold: number = 0;
  constructor(level: number = 0, titleKey: string = '', threshold: number = 0) {
    this.level = level;
    this.titleKey = titleKey;
    this.threshold = threshold;
  }
}

/**
 * 四级等级表。
 *
 * 分数构成见 `dexScore`：普通 1 分、少见 2 分、稀有 4 分、极稀有 8 分。
 * 门槛刻意拉开：只点亮十几台常见设备的人停在观察者，
 * 要升到大师必须真的积累（这也是图鉴作为长尾留存功能的意义）。
 */
export function dexLevels(): DexLevel[] {
  const levels: DexLevel[] = [];
  levels.push(new DexLevel(1, 'app.string.fieldwatch_dex_level_observer', 0));
  levels.push(new DexLevel(2, 'app.string.fieldwatch_dex_level_explorer', 30));
  levels.push(new DexLevel(3, 'app.string.fieldwatch_dex_level_hunter', 90));
  levels.push(new DexLevel(4, 'app.string.fieldwatch_dex_level_master', 200));
  return levels;
}

/** 单条已点亮条目的分数（稀有度越高越多）。 */
export function entryScore(entry: DexEntry): number {
  if (!entry.seen) return 0;
  if (entry.rarity === DexRarity.EPIC) return 8;
  if (entry.rarity === DexRarity.RARE) return 4;
  if (entry.rarity === DexRarity.UNCOMMON) return 2;
  return 1;
}

/** 总积分：所有已点亮条目的分数之和。 */
export function dexScore(entries: DexEntry[]): number {
  let total: number = 0;
  entries.forEach((entry: DexEntry): void => { total += entryScore(entry); });
  return total;
}

/** 当前等级（按分数落在哪一档）。 */
export function levelOf(score: number): DexLevel {
  const levels: DexLevel[] = dexLevels();
  let current: DexLevel = levels[0];
  levels.forEach((level: DexLevel): void => {
    if (score >= level.threshold) current = level;
  });
  return current;
}

/** 下一级与还差多少分；已满级时 next 为 undefined、remain 为 0。 */
export class DexLevelProgress {
  public current: DexLevel = new DexLevel();
  public next: DexLevel | undefined = undefined;
  public remain: number = 0;
  constructor() {}
  isMax(): boolean { return this.next === undefined; }
}

export function levelProgress(score: number): DexLevelProgress {
  const progress: DexLevelProgress = new DexLevelProgress();
  const levels: DexLevel[] = dexLevels();
  progress.current = levelOf(score);
  levels.forEach((level: DexLevel): void => {
    if (level.threshold > progress.current.threshold && progress.next === undefined) progress.next = level;
  });
  const next: DexLevel | undefined = progress.next;
  progress.remain = next === undefined ? 0 : Math.max(0, next.threshold - score);
  return progress;
}

/** 一枚勋章。 */
export class DexBadge {
  public id: string = '';
  public titleKey: string = '';
  public descKey: string = '';
  public earned: boolean = false;
  constructor(id: string = '', titleKey: string = '', descKey: string = '') {
    this.id = id;
    this.titleKey = titleKey;
    this.descKey = descKey;
  }
}

/**
 * 计算勋章。
 *
 * @param entries   图鉴条目
 * @param streakDays 连续有新发现的天数（由调用方按历史记录算，见 `consecutiveDays`）
 */
export function dexBadges(entries: DexEntry[], streakDays: number): DexBadge[] {
  const badges: DexBadge[] = [];

  // ① 首台监控类：点亮任意一条监控/摄像头类。
  let surveillance: boolean = false;
  entries.forEach((entry: DexEntry): void => {
    if (!entry.seen) return;
    if (entry.category === 'surveillance' || entry.category === 'camera') surveillance = true;
  });
  const monitor: DexBadge = new DexBadge('first_surveillance',
    'app.string.fieldwatch_dex_badge_surveillance', 'app.string.fieldwatch_dex_badge_surveillance_desc');
  monitor.earned = surveillance;
  badges.push(monitor);

  // ② 首台极稀有：点亮任意一条极稀有。
  let epic: boolean = false;
  entries.forEach((entry: DexEntry): void => {
    if (entry.seen && entry.rarity === DexRarity.EPIC) epic = true;
  });
  const rare: DexBadge = new DexBadge('first_epic',
    'app.string.fieldwatch_dex_badge_epic', 'app.string.fieldwatch_dex_badge_epic_desc');
  rare.earned = epic;
  badges.push(rare);

  // ③ 集齐一类：任意一个类别全部点亮。
  const totalByClass: Map<string, number> = new Map<string, number>();
  const seenByClass: Map<string, number> = new Map<string, number>();
  entries.forEach((entry: DexEntry): void => {
    const key: string = String(entry.category);
    const total: number | undefined = totalByClass.get(key);
    totalByClass.set(key, total === undefined ? 1 : total + 1);
    if (entry.seen) {
      const seen: number | undefined = seenByClass.get(key);
      seenByClass.set(key, seen === undefined ? 1 : seen + 1);
    }
  });
  let completed: boolean = false;
  totalByClass.forEach((total: number, key: string): void => {
    if (completed) return;
    const seen: number | undefined = seenByClass.get(key);
    if (total > 0 && seen !== undefined && seen >= total) completed = true;
  });
  const fullClass: DexBadge = new DexBadge('full_class',
    'app.string.fieldwatch_dex_badge_full_class', 'app.string.fieldwatch_dex_badge_full_class_desc');
  fullClass.earned = completed;
  badges.push(fullClass);

  // ④ 连续 7 天有新发现。
  const streak: DexBadge = new DexBadge('streak_7',
    'app.string.fieldwatch_dex_badge_streak', 'app.string.fieldwatch_dex_badge_streak_desc');
  streak.earned = streakDays >= 7;
  badges.push(streak);

  return badges;
}

/**
 * 连续有新发现的天数。
 *
 * @param daysWithNew 有过新发现的日子（本地日零点时间戳，升序）
 * @param now         当前时刻
 *
 * 判据：从**今天或昨天**往前数连续的自然日。允许从昨天起算是因为用户可能今天还没打开过。
 * 断一天就归零 —— 「连续」不能靠四舍五入。
 */
export function consecutiveDays(daysWithNew: number[], now: number): number {
  if (daysWithNew.length === 0) return 0;
  const DAY: number = 24 * 60 * 60 * 1000;
  const today: number = startOfDay(now);
  // 从今天往前找第一个有记录的日子；只允许今天是空（还没打开）。
  let cursor: number = today;
  if (daysWithNew.indexOf(today) < 0) {
    cursor = today - DAY;
    if (daysWithNew.indexOf(cursor) < 0) return 0;
  }
  let streak: number = 0;
  while (daysWithNew.indexOf(cursor) >= 0) {
    streak += 1;
    cursor -= DAY;
  }
  return streak;
}

export function startOfDay(at: number): number {
  const date: Date = new Date(at);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}
