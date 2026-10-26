import { TrackSuspect } from './FieldwatchAntiTracking';
/**
 * 反跟随自动提醒的策略层（P1-6）。
 *
 * **不重写评分引擎**：评分仍然是 `FieldwatchAntiTracking.assessTrack`，
 * 本模块只回答三件「什么时候该响」的事：
 *   ① 多久评估一次（前台 15 分钟）；
 *   ② 什么分数才推送（≥70）；
 *   ③ 同一目标多久内不重复打扰（24 小时）。
 *
 * 抽成纯逻辑是为了能单测：去重与节流一旦写进应用层，
 * 就只能靠「真机等 24 小时」来验证，那等于没验证。
 */

/** 前台评估间隔：文档指定 15 分钟。 */
export const ANTI_TRACK_EVAL_INTERVAL_MS: number = 15 * 60 * 1000;
/** 推送门槛：与评分引擎的嫌疑线同一口径（70）。 */
export const ANTI_TRACK_PUSH_SCORE: number = 70;
/** 关注线（45）：45–70 只进清单，不推送。 */
export const ANTI_TRACK_WATCH_SCORE: number = 45;
/** 同一目标的去重窗口：24 小时内只推一次。 */
export const ANTI_TRACK_DEDUP_MS: number = 24 * 60 * 60 * 1000;

/** 一条「已推过的记录」：目标键 + 推送时刻。 */
export class AntiTrackPushRecord {
  public key: string;
  public at: number;
  constructor(key: string = '', at: number = 0) { this.key = key; this.at = at; }
}

/** 一次评估的结论。 */
export class AntiTrackDecision {
  /** 值得推送的目标键（已过门槛且未被去重）。 */
  public pushKeys: string[] = [];
  /** 本次评估看到的所有目标键（供「清单」展示）。 */
  public watchKeys: string[] = [];
  /** 被 24 小时去重挡下的目标数（诊断用）。 */
  public dedupedCount: number = 0;
  constructor() {}
  /** 本次是否要真的发通知。 */
  shouldNotify(): boolean { return this.pushKeys.length > 0; }
}

/**
 * 决定这次评估要不要推送。
 *
 * @param suspects  目标列表（键 + 分数）
 * @param history   已推送记录（调用方持有，可落盘）
 * @param now       当前时刻
 *
 * 两条规则缺一不可：
 *   · **分数门槛 70**：45–70 只进清单。低了会天天报「疑似」，用户会关掉通知；
 *   · **24 小时去重**：同一台设备在一天内只提醒一次。没有它，15 分钟一轮的评估
 *     会在一小时内把同一台设备报四次，效果和骚扰无异。
 */
export function decideAntiTrackPush(suspects: TrackSuspect[], history: AntiTrackPushRecord[], now: number): AntiTrackDecision {
  const decision: AntiTrackDecision = new AntiTrackDecision();
  suspects.forEach((suspect: TrackSuspect): void => {
    if (suspect.evidence.score >= ANTI_TRACK_WATCH_SCORE) decision.watchKeys.push(suspect.key);
    if (suspect.evidence.score < ANTI_TRACK_PUSH_SCORE) return;
    if (recentlyPushed(suspect.key, history, now)) {
      decision.dedupedCount += 1;
      return;
    }
    decision.pushKeys.push(suspect.key);
  });
  return decision;
}

/** 该目标在去重窗口内是否已经推过。 */
export function recentlyPushed(key: string, history: AntiTrackPushRecord[], now: number): boolean {
  let hit: boolean = false;
  history.forEach((record: AntiTrackPushRecord): void => {
    if (hit) return;
    if (record.key !== key) return;
    if (now - record.at < ANTI_TRACK_DEDUP_MS) hit = true;
  });
  return hit;
}

/**
 * 把这次推过的目标写回历史，并顺手清掉过期记录。
 *
 * 清理是必须的：历史只在去重窗口内有意义，留着不删会让它随运行时长无限增长，
 * 而落盘这份历史时又会把整份数组写进设置存储。
 */
export function recordPushes(history: AntiTrackPushRecord[], keys: string[], now: number): AntiTrackPushRecord[] {
  const kept: AntiTrackPushRecord[] = [];
  history.forEach((record: AntiTrackPushRecord): void => {
    if (now - record.at < ANTI_TRACK_DEDUP_MS) kept.push(record);
  });
  keys.forEach((key: string): void => {
    kept.push(new AntiTrackPushRecord(key, now));
  });
  return kept;
}

/**
 * 这次评估是否到点了。
 *
 * 用「距上次评估是否超过 15 分钟」而不是固定 setInterval：
 * 应用可能被切到后台再切回来，定时器会被系统掐掉，
 * 回来后靠这个判断能立刻补一次评估，而不是再等满 15 分钟。
 */
export function shouldEvaluate(lastEvaluatedAt: number, now: number): boolean {
  if (lastEvaluatedAt <= 0) return true;
  return now - lastEvaluatedAt >= ANTI_TRACK_EVAL_INTERVAL_MS;
}

/** 推送文案里要显示的目标名：有名字用名字，没有就用键。 */
export function pushLabelOf(suspect: TrackSuspect): string {
  return suspect.label.length > 0 ? suspect.label : suspect.key;
}

