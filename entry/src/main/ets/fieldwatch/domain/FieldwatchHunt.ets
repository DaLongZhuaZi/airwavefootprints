/**
 * 单目标的相对响度搜寻（Hunt）。
 *
 * RSSI 既不是距离也不是方位；“安静/消失”与“更近/更远”同等重要。
 * 本模块是纯领域逻辑：不导入任何 HarmonyOS 系统包，也不产生用户可见文案
 * （文案由 UI 通过资源键解析）。
 */

export enum HuntCue {
  VERY_CLOSE = 'very_close',
  CLOSER = 'closer',
  FURTHER = 'further',
  SAME = 'same',
  WAITING = 'waiting',
  QUIET = 'quiet',
  GONE = 'gone'
}

export class HuntSample {
  public rssi: number;
  public at: number;
  constructor(rssi: number, at: number) { this.rssi = rssi; this.at = at; }
}

/** 最近窗口：用于计算“当前响度”。 */
export const HUNT_RECENT_MS: number = 2000;
/** 更早窗口：与最近窗口比较得出趋势。 */
export const HUNT_EARLIER_FROM_MS: number = 8000;
export const HUNT_EARLIER_TO_MS: number = 3500;
/** 趋势判定阈值（dB）。 */
export const HUNT_STEP_DB: number = 3;
/** 超过该时长没有新包即视为安静。 */
export const HUNT_QUIET_MS: number = 8000;
/** 与 DeviceExplain 的“非常强”同一阈值：口袋/手持/同一背包，不是米。 */
export const HUNT_VERY_CLOSE_DBM: number = -45;
/** Geiger tick 映射区间；响端比“非常近”更快。 */
export const HUNT_TICK_LOUD_DBM: number = -40;
export const HUNT_TICK_QUIET_DBM: number = -90;
export const HUNT_TICK_FAST_MS: number = 90;
export const HUNT_TICK_SLOW_MS: number = 1400;
/** 单次 Hunt 保留的最大样本数。 */
export const HUNT_MAX_SAMPLES: number = 240;

/** 蓝牙用 127 表示“不可用”，那不是发射功率也不是真实听感。 */
export function huntRssiMeasured(rssi: number): boolean {
  return rssi >= -127 && rssi <= 126;
}

export function huntAverage(samples: HuntSample[]): number {
  if (samples.length === 0) return 0;
  let total: number = 0;
  samples.forEach((sample: HuntSample): void => { total += sample.rssi; });
  return total / samples.length;
}

/** 会话内实测区间；用于展示“最低到最高”。 */
export function huntSessionRange(samples: HuntSample[]): string {
  let low: number = 127;
  let high: number = -127;
  let count: number = 0;
  samples.forEach((sample: HuntSample): void => {
    if (!huntRssiMeasured(sample.rssi)) return;
    if (sample.rssi < low) low = sample.rssi;
    if (sample.rssi > high) high = sample.rssi;
    count += 1;
  });
  if (count === 0) return '';
  if (low === high) return low.toString();
  return low.toString() + '..' + high.toString();
}

export function huntPeak(samples: HuntSample[]): number {
  let peak: number = -127;
  samples.forEach((sample: HuntSample): void => {
    if (!huntRssiMeasured(sample.rssi)) return;
    if (sample.rssi > peak) peak = sample.rssi;
  });
  return peak;
}

/** 最近一次有效测量值；当前值不可用时回退到历史。 */
export function huntLastMeasured(rssi: number, samples: HuntSample[]): number {
  if (huntRssiMeasured(rssi)) return rssi;
  for (let index = samples.length - 1; index >= 0; index -= 1) {
    if (huntRssiMeasured(samples[index].rssi)) return samples[index].rssi;
  }
  return 127;
}

/**
 * 判定当前提示状态。
 * @param lastSeen 最后一次收到该目标的时间；0 表示还没有收到过。
 * @param missing 目标是否已离开实时集合。
 */
export function huntCue(samples: HuntSample[], now: number, lastSeen: number, missing: boolean): HuntCue {
  if (missing) return HuntCue.GONE;
  if (lastSeen <= 0) return HuntCue.WAITING;
  if (now - lastSeen > HUNT_QUIET_MS) return HuntCue.QUIET;
  const usable: HuntSample[] = samples.filter((sample: HuntSample): boolean => huntRssiMeasured(sample.rssi));
  const recent: HuntSample[] = usable.filter((sample: HuntSample): boolean => sample.at >= now - HUNT_RECENT_MS);
  let loud: number = -127;
  let hasLoud: boolean = false;
  if (recent.length > 0) {
    loud = huntAverage(recent);
    hasLoud = true;
  } else {
    for (let index = usable.length - 1; index >= 0; index -= 1) {
      if (now - usable[index].at <= HUNT_QUIET_MS) { loud = usable[index].rssi; hasLoud = true; break; }
    }
  }
  if (hasLoud && loud >= HUNT_VERY_CLOSE_DBM) return HuntCue.VERY_CLOSE;
  const earlier: HuntSample[] = usable.filter((sample: HuntSample): boolean => sample.at <= now - HUNT_EARLIER_TO_MS && sample.at >= now - HUNT_EARLIER_FROM_MS);
  if (recent.length < 2 || earlier.length < 2) return HuntCue.WAITING;
  const delta: number = huntAverage(recent) - huntAverage(earlier);
  if (delta >= HUNT_STEP_DB) return HuntCue.CLOSER;
  if (delta <= -HUNT_STEP_DB) return HuntCue.FURTHER;
  return HuntCue.SAME;
}

/** 两次 tick 的间隔；返回 -1 表示保持静默。安静与消失不 tick。 */
export function huntTickIntervalMs(rssi: number, cue: HuntCue): number {
  if (cue === HuntCue.QUIET || cue === HuntCue.GONE) return -1;
  if (!huntRssiMeasured(rssi)) return -1;
  const span: number = HUNT_TICK_LOUD_DBM - HUNT_TICK_QUIET_DBM;
  let ratio: number = (rssi - HUNT_TICK_QUIET_DBM) / span;
  if (ratio < 0) ratio = 0;
  if (ratio > 1) ratio = 1;
  return Math.round(HUNT_TICK_SLOW_MS + (HUNT_TICK_FAST_MS - HUNT_TICK_SLOW_MS) * ratio);
}

/** 视觉强度 0..3；UI 用它决定脉冲与颜色强度。 */
export function huntCueLevel(cue: HuntCue): number {
  if (cue === HuntCue.VERY_CLOSE) return 3;
  if (cue === HuntCue.CLOSER) return 2;
  if (cue === HuntCue.SAME) return 1;
  if (cue === HuntCue.FURTHER) return 1;
  return 0;
}

/** 资源键后缀，UI 用 app.string.fieldwatch_hunt_cue_<key> 解析文案。 */
export function huntCueKey(cue: HuntCue): string {
  if (cue === HuntCue.VERY_CLOSE) return 'very_close';
  if (cue === HuntCue.CLOSER) return 'closer';
  if (cue === HuntCue.FURTHER) return 'further';
  if (cue === HuntCue.SAME) return 'same';
  if (cue === HuntCue.QUIET) return 'quiet';
  if (cue === HuntCue.GONE) return 'gone';
  return 'waiting';
}

/**
 * 一次**已结束**的搜寻记录。
 *
 * 工具箱的「信号追踪」面板要展示历史，而 `HuntSession` 在停止时就没了 ——
 * 所以停止时把关键指标固化下来，UI 只读这份快照。
 */
export class HuntRecord {
  public targetKey: string = '';
  public label: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public peak: number = -127;
  public samples: number = 0;
  public average: number = 0;
  public durationMs(): number { return this.endedAt - this.startedAt; }
}

/** 搜寻历史的汇总。 */
export class HuntStats {
  public sessions: number = 0;
  public totalMs: number = 0;
  public bestPeak: number = -127;
  public bestLabel: string = '';
}

/** 一次 Hunt 会话；由应用层持有，UI 只读。 */
export class HuntSession {
  public targetKey: string = '';
  public label: string = '';
  public startedAt: number = 0;
  public lastSeen: number = 0;
  public lastRssi: number = 127;
  public missing: boolean = false;
  public samples: HuntSample[] = [];

  constructor(targetKey: string = '', label: string = '', startedAt: number = 0) {
    this.targetKey = targetKey; this.label = label; this.startedAt = startedAt;
  }

  addSample(rssi: number, at: number): void {
    if (this.samples.length >= HUNT_MAX_SAMPLES) this.samples.shift();
    this.samples.push(new HuntSample(rssi, at));
    this.lastRssi = rssi;
    this.lastSeen = at;
    this.missing = false;
  }

  peak(): number { return huntPeak(this.samples); }
  rangeText(): string { return huntSessionRange(this.samples); }
  average(): number {
    const usable: HuntSample[] = this.samples.filter((sample: HuntSample): boolean => sample.at >= this.lastSeen - HUNT_RECENT_MS);
    return usable.length > 0 ? huntAverage(usable) : huntAverage(this.samples);
  }
  cue(now: number): HuntCue { return huntCue(this.samples, now, this.lastSeen, this.missing); }
}
