/**
 * 同名多台的「晃一晃」确认（文档 §7.3 防呆设计第一条）。
 *
 * **要解决的问题**：家里两副同型号耳机时，「哪一台是我的」靠名字和指纹都分不出来
 * （指纹相同、名字相同）。但有一个用户天然会做的动作能分开它们：**拿起自己要找的那台晃一晃** ——
 * 被晃动的那台，信号强度会在几秒内出现特征性波动，而旁边那台纹丝不动。
 *
 * **为什么不用「对着地址尾号猜」**：那是把设备内部标识推给用户，日常用户既看不懂也不该看
 * （术语 grep 验收也禁止 MAC 出现在日常页）。
 *
 * 本文件是纯逻辑：不碰系统、不碰 UI，输入是「每台候选最近的强度采样」，输出是
 * 「是否已能确定是哪一台」。**宁可不确定也不猜** —— 认错一台会直接导致寻找方向完全相反。
 */

/** 一次确认用到的采样（只要强度与时刻，故不复用观测类型，便于单测直接构造）。 */
export class ShakeSample {
  public rssi: number = 0;
  public at: number = 0;

  constructor(rssi: number, at: number) {
    this.rssi = rssi;
    this.at = at;
  }
}

/* ── 判定参数：集中成常量，真机阶段只调这里 ── */
/** 只看最近 4 秒：晃动是短动作，窗口太长会把「走过来的过程」也算成波动。 */
export const SHAKE_WINDOW_MS: number = 4000;
/** 少于 4 个样本的极差不可信（2 个点随便都能拉出 6 dB）。 */
export const SHAKE_MIN_SAMPLES: number = 4;
/**
 * 判定「这台在动」的最小极差。
 *
 * 静止设备在同一点上通常只有 2~4 dB 的抖动（多径），8 dB 基本只可能来自位移或遮挡变化。
 */
export const SHAKE_MIN_SPREAD_DB: number = 8;
/** 领先第二名多少才算「明显」：两台都在动时，差得不够多就不选。 */
export const SHAKE_LEAD_DB: number = 4;

/* ── 「强且纹丝不动」的怀疑判据（文档 §7.3 第二条防呆）── */
/**
 * 判定「纹丝不动」的最大极差。
 *
 * 与晃动阈值相反：晃动要求 ≥8 dB，这里要求**≤3 dB** —— 同一点上的多径抖动通常 2~4 dB，
 * 所以「很强 + 几乎不跳」更像是**贴在墙上的固定设备**（比如别人的同款耳机放在桌上），
 * 而不是你手里正在被寻找的那台。
 */
export const STATIC_SUSPECT_MAX_SPREAD_DB: number = 3;
/** 观察窗口：判断「一直没变化」需要看够久（文档说的是「一直」）。 */
export const STATIC_SUSPECT_WINDOW_MS: number = 12000;
/** 少于这个样本数不下结论（避免刚进来两三个包就提示）。 */
export const STATIC_SUSPECT_MIN_SAMPLES: number = 6;

/**
 * 信号是否「又强又不动」。
 *
 * 强度由调用方判（例如「非常近」状态），本函数只回答「**一直没变化**」。
 * 刻意只做提示、不做断言：文档要求的是「不自动断言，只提示」——
 * 因为固定设备与口袋里的设备在这一项上长得一样，唯一能分开的是**用户拿起来晃一晃**。
 */
export function staticStrongSuspect(samples: ShakeSample[], now: number,
  windowMs: number = STATIC_SUSPECT_WINDOW_MS): boolean {
  let min: number = 0;
  let max: number = 0;
  let count: number = 0;
  samples.forEach((sample: ShakeSample): void => {
    if (sample.at < now - windowMs) return;
    if (count === 0) { min = sample.rssi; max = sample.rssi; }
    if (sample.rssi < min) min = sample.rssi;
    if (sample.rssi > max) max = sample.rssi;
    count += 1;
  });
  if (count < STATIC_SUSPECT_MIN_SAMPLES) return false;
  return max - min <= STATIC_SUSPECT_MAX_SPREAD_DB;
}

/** 一台候选的晃动评估结果。 */
export class ShakeCandidate {
  /** 观测 key（用于绑定会话，**不进 UI**）。 */
  public key: string = '';
  /** 窗口内极差；-1 表示样本不足、还不能判断。 */
  public spread: number = -1;
  public samples: number = 0;
  /** 是否判定为「在动」。 */
  public moving: boolean = false;
}

/** 判定结果。 */
export class ShakeDecision {
  /** 结论：绑到这台；`decided` 为 false 时无意义。 */
  public key: string = '';
  public decided: boolean = false;
  public candidates: ShakeCandidate[] = [];
}

/**
 * 窗口内极差（max - min）。
 *
 * 用极差而不是方差：晃动只有几个样本，方差对小样本很敏感且需要开方；
 * 极差直接对应「信号摆动幅度」，用户在界面上看到的就是这个量。
 *
 * @returns 极差；样本不足时返回 -1（调用方必须把它当作「还不知道」，而不是 0）
 */
export function shakeSpread(samples: ShakeSample[], now: number, windowMs: number = SHAKE_WINDOW_MS): number {
  let min: number = 0;
  let max: number = 0;
  let count: number = 0;
  samples.forEach((sample: ShakeSample): void => {
    if (sample.at < now - windowMs) return;
    if (count === 0) { min = sample.rssi; max = sample.rssi; }
    if (sample.rssi < min) min = sample.rssi;
    if (sample.rssi > max) max = sample.rssi;
    count += 1;
  });
  if (count < SHAKE_MIN_SAMPLES) return -1;
  return max - min;
}

/** 评估一台候选。 */
export function scoreShake(key: string, samples: ShakeSample[], now: number, windowMs: number = SHAKE_WINDOW_MS): ShakeCandidate {
  const candidate: ShakeCandidate = new ShakeCandidate();
  candidate.key = key;
  candidate.spread = shakeSpread(samples, now, windowMs);
  candidate.samples = samples.length;
  candidate.moving = candidate.spread >= SHAKE_MIN_SPREAD_DB;
  return candidate;
}

/**
 * 从多台同名候选里挑出「用户正在晃的那台」。
 *
 * 规则（刻意保守）：
 * 1. 只有在动的候选才可能被选中 —— **纹丝不动的最强信号永远不会赢**，
 *    那条正是文档 §7.3 说的「贴在墙上的同款设备」；
 * 2. 只有一台在动 → 就是它；
 * 3. 多台在动 → 领先第二名达到 `SHAKE_LEAD_DB` 才选，否则**返回未确定**，
 *    让用户继续晃（比猜错强：猜错会让寻找方向完全相反）。
 */
export function decideShaken(candidates: ShakeCandidate[]): ShakeDecision {
  const decision: ShakeDecision = new ShakeDecision();
  decision.candidates = candidates;
  const moving: ShakeCandidate[] = candidates.filter((item: ShakeCandidate): boolean => item.moving);
  if (moving.length === 0) return decision;
  /**
   * **先排序再取第一/第二**，而不是边遍历边维护。
   *
   * 后者极易写成「把冠军自己的极差当成第二名」—— 那样任何领先幅度都会被算成 0，
   * 于是永远判不出结果（这个错误被单测 `requires a clear lead` 逮到过）。
   * 排序写法还有个附带好处：并列第一时 runnerUp 等于冠军值，领先差为 0，
   * 自然落进「不选」分支 —— 并列本来就不该替用户拍板。
   */
  const spreads: number[] = moving.map((item: ShakeCandidate): number => item.spread);
  spreads.sort((left: number, right: number): number => right - left);
  const runnerUpSpread: number = spreads.length > 1 ? spreads[1] : -1;
  const bestHits: ShakeCandidate[] = moving.filter((item: ShakeCandidate): boolean => item.spread === spreads[0]);
  const best: ShakeCandidate = bestHits[0];
  if (moving.length === 1 || best.spread - runnerUpSpread >= SHAKE_LEAD_DB) {
    decision.key = best.key;
    decision.decided = true;
  }
  return decision;
}
