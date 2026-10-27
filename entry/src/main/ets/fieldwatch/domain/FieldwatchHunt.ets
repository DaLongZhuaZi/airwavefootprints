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

export const HUNT_DIRECTION_SECTOR_COUNT: number = 16;
export const HUNT_DIRECTION_MIN_COVERAGE: number = 8;
export const HUNT_DIRECTION_MIN_CONTRAST_DB: number = 3;
export const HUNT_DIRECTION_INVALID_RSSI: number = 127;

/** RSSI sample paired with the device heading at observation time. */
export class HuntDirectionSample {
  public heading: number;
  public rssi: number;
  constructor(heading: number, rssi: number) { this.heading = heading; this.rssi = rssi; }
}

/** Coarse relative direction estimate. Missing sectors remain explicitly unavailable. */
export class HuntDirectionMap {
  private readonly totals: number[] = [];
  private readonly counts: number[] = [];

  constructor() {
    for (let index: number = 0; index < HUNT_DIRECTION_SECTOR_COUNT; index += 1) {
      this.totals.push(0);
      this.counts.push(0);
    }
  }

  addSample(heading: number, rssi: number): boolean {
    if (!Number.isFinite(heading) || !huntRssiMeasured(rssi)) return false;
    const sector: number = huntDirectionSector(heading);
    if (sector < 0) return false;
    this.totals[sector] += rssi;
    this.counts[sector] += 1;
    return true;
  }

  coverage(): number {
    let covered: number = 0;
    this.counts.forEach((count: number): void => { if (count > 0) covered += 1; });
    return covered;
  }

  sectorRssi(sector: number): number {
    if (sector < 0 || sector >= HUNT_DIRECTION_SECTOR_COUNT || this.counts[sector] === 0) return HUNT_DIRECTION_INVALID_RSSI;
    return this.totals[sector] / this.counts[sector];
  }

  peakHeading(): number {
    const peak: number = this.peakSector();
    return peak < 0 ? HUNT_DIRECTION_INVALID_RSSI : huntDirectionSectorHeading(peak);
  }

  relativeDelta(currentHeading: number): number {
    const peak: number = this.peakHeading();
    if (peak === HUNT_DIRECTION_INVALID_RSSI || !Number.isFinite(currentHeading)) return HUNT_DIRECTION_INVALID_RSSI;
    let delta: number = peak - normalizeHuntHeading(currentHeading);
    if (delta > 180) delta -= 360;
    if (delta <= -180) delta += 360;
    return delta;
  }

  ready(): boolean {
    if (this.coverage() < HUNT_DIRECTION_MIN_COVERAGE) return false;
    const peakValue: number = this.peakRssi();
    if (peakValue === HUNT_DIRECTION_INVALID_RSSI) return false;
    let total: number = 0;
    let count: number = 0;
    for (let sector: number = 0; sector < HUNT_DIRECTION_SECTOR_COUNT; sector += 1) {
      const value: number = this.sectorRssi(sector);
      if (value === HUNT_DIRECTION_INVALID_RSSI) continue;
      total += value;
      count += 1;
    }
    return count > 0 && peakValue - total / count >= HUNT_DIRECTION_MIN_CONTRAST_DB;
  }

  private peakSector(): number {
    let bestSector: number = -1;
    let bestRssi: number = -127;
    for (let sector: number = 0; sector < HUNT_DIRECTION_SECTOR_COUNT; sector += 1) {
      if (this.counts[sector] === 0) continue;
      const average: number = this.totals[sector] / this.counts[sector];
      if (average > bestRssi) { bestRssi = average; bestSector = sector; }
    }
    return bestSector;
  }

  private peakRssi(): number {
    const sector: number = this.peakSector();
    return sector < 0 ? HUNT_DIRECTION_INVALID_RSSI : this.sectorRssi(sector);
  }
}

export function normalizeHuntHeading(heading: number): number {
  const normalized: number = heading % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

export function huntDirectionSector(heading: number): number {
  if (!Number.isFinite(heading)) return -1;
  const normalized: number = normalizeHuntHeading(heading);
  return Math.floor(normalized / (360 / HUNT_DIRECTION_SECTOR_COUNT));
}

export function huntDirectionSectorHeading(sector: number): number {
  if (sector < 0 || sector >= HUNT_DIRECTION_SECTOR_COUNT) return HUNT_DIRECTION_INVALID_RSSI;
  return (sector + 0.5) * (360 / HUNT_DIRECTION_SECTOR_COUNT);
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

/**
 * 判据用的时间窗。
 *
 * **为什么需要它**：默认值（近窗 2 秒 / 远窗 3.5–8 秒 / 静默 8 秒）是给 **BLE** 调的 ——
 * BLE 稳态每秒十几到几十条包。而 **Wi-Fi 扫描是几十秒一次的突发**：用 BLE 的窗，
 * 两次扫描之间会一直显示「安静」，`CLOSER/FURTHER/SAME` 几乎永远出不来
 * （真机实测：平板正连着路由器，向导却停在「暂时听不到它了」）。
 *
 * 所以窗要跟着**无线种类**走，而不是跟着 dB 走 —— 文档说「Wi-Fi 的 RSSI 同样适用」是对的，
 * 但没说时间窗也适用。
 */
export class HuntWindows {
  public recentMs: number = HUNT_RECENT_MS;
  public earlierFromMs: number = HUNT_EARLIER_FROM_MS;
  public earlierToMs: number = HUNT_EARLIER_TO_MS;
  public quietMs: number = HUNT_QUIET_MS;
}

/** Wi-Fi 用：按扫描节奏放宽（近窗=最近一次扫描，远窗=再上一次，静默=漏掉一次扫描）。 */
export const HUNT_WIFI_WINDOWS: HuntWindows = buildWifiWindows();

function buildWifiWindows(): HuntWindows {
  const windows: HuntWindows = new HuntWindows();
  windows.recentMs = 35000;
  windows.earlierFromMs = 70000;
  windows.earlierToMs = 35000;
  windows.quietMs = 45000;
  return windows;
}

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
export function huntCue(samples: HuntSample[], now: number, lastSeen: number, missing: boolean,
  windows: HuntWindows = new HuntWindows()): HuntCue {
  if (missing) return HuntCue.GONE;
  if (lastSeen <= 0) return HuntCue.WAITING;
  if (now - lastSeen > windows.quietMs) return HuntCue.QUIET;
  const usable: HuntSample[] = samples.filter((sample: HuntSample): boolean => huntRssiMeasured(sample.rssi));
  const recent: HuntSample[] = usable.filter((sample: HuntSample): boolean => sample.at >= now - windows.recentMs);
  let loud: number = -127;
  let hasLoud: boolean = false;
  if (recent.length > 0) {
    loud = huntAverage(recent);
    hasLoud = true;
  } else {
    for (let index = usable.length - 1; index >= 0; index -= 1) {
      if (now - usable[index].at <= windows.quietMs) { loud = usable[index].rssi; hasLoud = true; break; }
    }
  }
  if (hasLoud && loud >= HUNT_VERY_CLOSE_DBM) return HuntCue.VERY_CLOSE;
  const earlier: HuntSample[] = usable.filter((sample: HuntSample): boolean => sample.at <= now - windows.earlierToMs && sample.at >= now - windows.earlierFromMs);
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

/**
 * 最近一段样本的**离散度**（极差，dB），用于「同名多台用晃一晃确认」。
 *
 * 为什么用极差而不是方差：晃动的特征就是「这一小段里有过大起伏」，
 * 极差直接反映这件事且不需要开方，读数能直接对着 UI 说人话；
 * 方差对单个野值的惩罚更重，反而容易被一次误码带偏。
 *
 * 只统计**最近 count 条已测量样本**：更早的样本属于「拿起来之前」，
 * 混进来会把静止设备的历史波动也算成本次晃动。
 */
export function huntRecentSpread(samples: HuntSample[], now: number, windowMs: number): number {
  let low: number = 127;
  let high: number = -127;
  let count: number = 0;
  samples.forEach((sample: HuntSample): void => {
    if (!huntRssiMeasured(sample.rssi)) return;
    if (now - sample.at > windowMs) return;
    if (sample.rssi < low) low = sample.rssi;
    if (sample.rssi > high) high = sample.rssi;
    count += 1;
  });
  // 少于两条谈不上「起伏」：一条样本的极差恒为 0，会把它误判成静止。
  if (count < 2) return 0;
  return high - low;
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
  /** 提示状态；`windows` 让调用方按无线种类换时间窗（Wi-Fi 的扫描节奏比 BLE 慢一个量级）。 */
  cue(now: number, windows: HuntWindows = new HuntWindows()): HuntCue {
    return huntCue(this.samples, now, this.lastSeen, this.missing, windows);
  }
}
