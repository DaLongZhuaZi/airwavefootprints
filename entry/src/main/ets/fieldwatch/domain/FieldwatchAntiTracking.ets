/**
 * 反追踪识别（疑似跟踪设备）。
 *
 * 纯领域逻辑：不导入任何 HarmonyOS 系统包，也不产生用户可见文案。
 *
 * **为什么不能用「距离」一个数判断**：
 * 一台固定在某处的设备，你走远了自然就收不到；
 * 而**跟着你走的**设备，会在你走过一整条弯路的全程里一直出现 ——
 * 关键不是「你走了多少米」，而是「你走了多少米、绕了多少弯，它还在」。
 * 所以地理维度看两个量：路径长度，以及**路径长度 / 首末直线位移**（曲折度）。
 * 沿直线走 500m 再原路返回，位移是 0 而路径是 1000m；
 * 此时仍有设备一路伴随，那才是真正的信号。
 *
 * 三个维度各自独立，任一维度都不足以定性，合起来才有意义：
 *   ① 时间跨度与持续性 —— 短暂路过不算；
 *   ② 地理共动 —— 你动它也在（且你是绕弯走的）；
 *   ③ 信号强度拟合 —— 你在动而它的强度**几乎不变**，说明它跟着你一起动。
 */

/** 单台设备的一次观测样本。 */
export class TrackPoint {
  public at: number = 0;
  public rssi: number = -127;
  constructor(at: number = 0, rssi: number = -127) { this.at = at; this.rssi = rssi; }
}

/** 用户自身的一个位置点（来自应用的 travelTrack）。 */
export class GeoPoint {
  public at: number = 0;
  public lat: number = 0;
  public lon: number = 0;
  constructor(at: number = 0, lat: number = 0, lon: number = 0) { this.at = at; this.lat = lat; this.lon = lon; }
}

export enum FollowRisk { NONE = 'none', WATCH = 'watch', SUSPECT = 'suspect' }

/** 只看最近 30 分钟；更早的观测与「现在跟着你」无关。 */
export const TRACK_WINDOW_MS: number = 30 * 60 * 1000;
/** 时间跨度下限：低于这个时长不足以定性。 */
export const TRACK_MIN_SPAN_MS: number = 8 * 60 * 1000;
export const TRACK_MIN_SAMPLES: number = 8;
/** 持续性分桶的粒度。 */
export const TRACK_BUCKET_MS: number = 60 * 1000;
/** 判定「你确实走了一段路」的下限。 */
export const TRACK_MIN_PATH_M: number = 200;
/** 曲折度下限：路径 / 直线位移。1.5 表示明显不是一条直线。 */
export const TRACK_MIN_PATH_RATIO: number = 1.5;
/** 拟合斜率的「几乎不变」阈值（dB/分钟）。 */
export const TRACK_SLOPE_FLAT_DB_PER_MIN: number = 2.0;

export const SUSPECT_SCORE: number = 70;
export const WATCH_SCORE: number = 45;

const EARTH_RADIUS_M: number = 6371000;

/** 两点球面距离（米）。 */
export function haversineMeters(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const toRad: number = Math.PI / 180;
  const dLat: number = (bLat - aLat) * toRad;
  const dLon: number = (bLon - aLon) * toRad;
  const lat1: number = aLat * toRad;
  const lat2: number = bLat * toRad;
  const h: number = Math.sin(dLat / 2) * Math.sin(dLat / 2)
    + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

export class TrackEvidence {
  public spanMs: number = 0;
  public sampleCount: number = 0;
  /** 出现时长占时间跨度的比例 0..1。 */
  public presenceRatio: number = 0;
  /** 你在这段时间里走过的路径长度（米）。 */
  public pathMeters: number = 0;
  /** 首末直线位移（米）。 */
  public displacementMeters: number = 0;
  /** 曲折度 = 路径 / 位移；位移过小时按 100m 兜底，避免除零放大噪声。 */
  public pathRatio: number = 0;
  /** 线性拟合斜率（dB/分钟）。 */
  public rssiSlopePerMin: number = 0;
  /** 拟合残差标准差（dB），越小说明强度越稳。 */
  public rssiResidualDb: number = 0;
  public score: number = 0;
  public hasGeo: boolean = false;
}

/** 线性最小二乘拟合 y = slope * x + intercept。 */
function fitLine(xs: number[], ys: number[]): number[] {
  const n: number = xs.length;
  if (n < 2) return [0, ys.length > 0 ? ys[0] : 0];
  let sx: number = 0; let sy: number = 0;
  for (let i: number = 0; i < n; i += 1) { sx += xs[i]; sy += ys[i]; }
  const mx: number = sx / n; const my: number = sy / n;
  let num: number = 0; let den: number = 0;
  for (let i: number = 0; i < n; i += 1) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  const slope: number = den === 0 ? 0 : num / den;
  return [slope, my - slope * mx];
}

function clamp01(value: number): number { return value < 0 ? 0 : (value > 1 ? 1 : value); }

/**
 * 评估一台设备。
 *
 * @param samples 该设备的 (时间, 强度) 序列
 * @param travel  用户自身的位置轨迹（时间升序）
 * @param now     当前时间
 */
export function assessTrack(samples: TrackPoint[], travel: GeoPoint[], now: number): TrackEvidence {
  const evidence: TrackEvidence = new TrackEvidence();
  const windowed: TrackPoint[] = samples.filter((point: TrackPoint): boolean => point.at >= now - TRACK_WINDOW_MS);
  evidence.sampleCount = windowed.length;
  if (windowed.length < TRACK_MIN_SAMPLES) return evidence;
  const first: number = windowed[0].at;
  const last: number = windowed[windowed.length - 1].at;
  evidence.spanMs = last - first;
  if (evidence.spanMs < TRACK_MIN_SPAN_MS) return evidence;
  // ① 持续性：把时间跨度切成 1 分钟桶，看有多少桶里出现过。
  const buckets: number = Math.max(1, Math.ceil(evidence.spanMs / TRACK_BUCKET_MS));
  const seen: boolean[] = [];
  for (let i: number = 0; i < buckets; i += 1) seen.push(false);
  windowed.forEach((point: TrackPoint): void => {
    const index: number = Math.min(buckets - 1, Math.floor((point.at - first) / TRACK_BUCKET_MS));
    if (index >= 0) seen[index] = true;
  });
  let filled: number = 0;
  seen.forEach((value: boolean): void => { if (value) filled += 1; });
  evidence.presenceRatio = filled / buckets;
  // ② 地理共动：取该设备出现期间用户自己的轨迹。
  const geo: GeoPoint[] = travel.filter((point: GeoPoint): boolean => point.at >= first && point.at <= last);
  evidence.hasGeo = geo.length >= 2;
  if (evidence.hasGeo) {
    let path: number = 0;
    for (let i: number = 1; i < geo.length; i += 1) {
      path += haversineMeters(geo[i - 1].lat, geo[i - 1].lon, geo[i].lat, geo[i].lon);
    }
    evidence.pathMeters = path;
    evidence.displacementMeters = haversineMeters(geo[0].lat, geo[0].lon, geo[geo.length - 1].lat, geo[geo.length - 1].lon);
    // 位移很小时不做除法：静止时的比值没有意义，只会放大 GPS 抖动。
    evidence.pathRatio = path / Math.max(evidence.displacementMeters, 100);
  }
  // ③ 强度拟合：以「分钟」为单位，斜率才有人能读懂的量纲。
  const xs: number[] = [];
  const ys: number[] = [];
  windowed.forEach((point: TrackPoint): void => {
    xs.push((point.at - first) / 60000);
    ys.push(point.rssi);
  });
  const line: number[] = fitLine(xs, ys);
  evidence.rssiSlopePerMin = line[0];
  let residual: number = 0;
  for (let i: number = 0; i < xs.length; i += 1) {
    const predicted: number = line[0] * xs[i] + line[1];
    residual += (ys[i] - predicted) * (ys[i] - predicted);
  }
  evidence.rssiResidualDb = Math.sqrt(residual / xs.length);
  // ④ 合成分。三个维度分别封顶，避免任一维度单独把分数顶满。
  const spanScore: number = clamp01(evidence.spanMs / (20 * 60 * 1000)) * 25;
  const presenceScore: number = evidence.presenceRatio * 15;
  const pathScore: number = evidence.hasGeo ? clamp01(evidence.pathMeters / 600) * 20 : 0;
  const ratioScore: number = evidence.hasGeo && evidence.pathRatio >= TRACK_MIN_PATH_RATIO
    ? clamp01((evidence.pathRatio - TRACK_MIN_PATH_RATIO) / 1.5) * 15 + 5 : 0;
  // 「你动它不动」：斜率越平、残差越小，越像是它跟着你一起动。
  const flatScore: number = clamp01(1 - Math.abs(evidence.rssiSlopePerMin) / TRACK_SLOPE_FLAT_DB_PER_MIN) * 15;
  const stableScore: number = clamp01(1 - evidence.rssiResidualDb / 6) * 10;
  evidence.score = Math.round(Math.min(100, spanScore + presenceScore + pathScore + ratioScore + flatScore + stableScore));
  return evidence;
}

/**
 * 把总分拆成三个维度的贡献：`[时间, 地理, 信号]`。
 *
 * 面板要把「为什么是这个分数」摊开给用户看 ——
 * 只给一个总分，用户没法判断该不该在意（是「陪了很久」还是「信号一直很稳」）。
 *
 * 与 `assessTrack` 里的加权**同一套系数**，抽出来是为了不写两遍。
 */
export function evidenceBreakdown(evidence: TrackEvidence): number[] {
  const timeScore: number = clamp01(evidence.spanMs / (20 * 60 * 1000)) * 25 + evidence.presenceRatio * 15;
  const pathScore: number = evidence.hasGeo ? clamp01(evidence.pathMeters / 600) * 20 : 0;
  const ratioScore: number = evidence.hasGeo && evidence.pathRatio >= TRACK_MIN_PATH_RATIO
    ? clamp01((evidence.pathRatio - TRACK_MIN_PATH_RATIO) / 1.5) * 15 + 5 : 0;
  const flatScore: number = clamp01(1 - Math.abs(evidence.rssiSlopePerMin) / TRACK_SLOPE_FLAT_DB_PER_MIN) * 15;
  const stableScore: number = clamp01(1 - evidence.rssiResidualDb / 6) * 10;
  return [Math.round(timeScore), Math.round(pathScore + ratioScore), Math.round(flatScore + stableScore)];
}

/** 各维度的满分，供 UI 画进度条。 */
export const EVIDENCE_MAX: number[] = [40, 40, 25];

export function riskOf(score: number): FollowRisk {
  if (score >= SUSPECT_SCORE) return FollowRisk.SUSPECT;
  if (score >= WATCH_SCORE) return FollowRisk.WATCH;
  return FollowRisk.NONE;
}

/** 一台被判定为需要留意的设备（领域层的纯数据，不含文案）。 */
export class TrackSuspect {
  public key: string = '';
  public label: string = '';
  public risk: FollowRisk = FollowRisk.NONE;
  public evidence: TrackEvidence = new TrackEvidence();
}

/** 用户自身移动轨迹的摘要（反追踪面板的「我的移动」块）。 */
export class TravelSummary {
  public pathMeters: number = 0;
  public displacementMeters: number = 0;
  public pathRatio: number = 0;
  public fixes: number = 0;
  public spanMs: number = 0;
}

/**
 * 汇总一段轨迹。
 *
 * 与 `assessTrack` 里的地理部分**同一套算法**（路径 / 首末位移 / 曲折度），
 * 只是这里算的是「我」而不是某台设备 —— 抽成函数是为了避免两处各写一遍。
 */
export function travelSummaryOf(points: GeoPoint[]): TravelSummary {
  const summary: TravelSummary = new TravelSummary();
  summary.fixes = points.length;
  if (points.length < 2) return summary;
  let path: number = 0;
  for (let i: number = 1; i < points.length; i += 1) {
    path += haversineMeters(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
  }
  summary.pathMeters = path;
  summary.displacementMeters = haversineMeters(points[0].lat, points[0].lon,
    points[points.length - 1].lat, points[points.length - 1].lon);
  summary.pathRatio = path / Math.max(summary.displacementMeters, 100);
  summary.spanMs = points[points.length - 1].at - points[0].at;
  return summary;
}

/** 一条反追踪判定记录（面板里的「判定记录」）。 */
export class AntiTrackEvent {
  public at: number = 0;
  public key: string = '';
  public label: string = '';
  public score: number = 0;
  public risk: FollowRisk = FollowRisk.NONE;
}

/** 反追踪面板的汇总计数。 */
export class AntiTrackStats {
  /** 参与评估的设备数（有足够样本的）。 */
  public evaluated: number = 0;
  public suspect: number = 0;
  public watch: number = 0;
  /** 最高分，用来判断「离触发还有多远」。 */
  public topScore: number = 0;
  public topLabel: string = '';
}

export function formatMinutes(ms: number): string { return Math.round(ms / 60000).toString(); }
export function formatMeters(meters: number): string {
  if (meters >= 1000) return (Math.round(meters / 100) / 10).toString() + ' km';
  return Math.round(meters).toString() + ' m';
}
