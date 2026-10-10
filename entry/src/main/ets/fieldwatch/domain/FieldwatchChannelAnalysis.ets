/**
 * Wi-Fi 信道拥堵分析。
 *
 * 纯领域逻辑：不导入任何 HarmonyOS 系统包，也不产生用户可见文案。
 *
 * **为什么按频率算而不是按信道号算**：
 * 信道号在三个频段里含义不同（2.4G 的 6 与 5G 的 6 毫无关系），
 * 而且重叠发生在**频率**上 —— 2.4G 的 1/6/11 之所以互不重叠，
 * 是因为它们的中心频率相隔 25MHz、各自占 22MHz。
 * 统一在频率轴上做积分，三频段共用同一套逻辑，也自然支持 40/80/160MHz 的宽信道。
 */

export enum WifiBand {
  BAND_24 = '2.4G',
  BAND_5 = '5G',
  BAND_6 = '6G',
  UNKNOWN = 'unknown'
}

/** 各频段的频率范围（MHz）。6G 上界取 7125，覆盖整个 UNII-5..8。 */
export const BAND_24_START: number = 2400;
export const BAND_24_END: number = 2484;
export const BAND_5_START: number = 5150;
export const BAND_5_END: number = 5895;
export const BAND_6_START: number = 5925;
export const BAND_6_END: number = 7125;

/** 2.4G 的传统 22MHz 信道宽度（比标称 20MHz 宽，这正是相邻信道重叠的原因）。 */
export const CHANNEL_24_WIDTH_MHZ: number = 22;
/** 拥堵度采样的频率步长。5MHz 恰好是信道栅格。 */
export const LOAD_SAMPLE_STEP_MHZ: number = 5;

/**
 * 采样栅格的**原点**。
 *
 * **必须与信道号公式同源**：2.4G 的信道中心是 `2407 + 5k`，
 * 如果采样从频段起点（2400）按 5MHz 步进，采样点会落在 2400/2405/2410…
 * 与信道中心**整整错开 2MHz** —— 于是每个采样点的信道号都算不出来，
 * 「最拥挤信道」在界面上永远是空值（实测：单元测试直接抓到）。
 */
export function gridOrigin(band: WifiBand): number {
  if (band === WifiBand.BAND_24) return 2407;
  if (band === WifiBand.BAND_5) return 5000;
  return 5950;
}

export function wifiBandOf(frequencyMhz: number): WifiBand {
  if (frequencyMhz >= BAND_24_START && frequencyMhz <= BAND_24_END) return WifiBand.BAND_24;
  if (frequencyMhz >= BAND_5_START && frequencyMhz <= BAND_5_END) return WifiBand.BAND_5;
  if (frequencyMhz >= BAND_6_START && frequencyMhz <= BAND_6_END) return WifiBand.BAND_6;
  return WifiBand.UNKNOWN;
}

export function bandRange(band: WifiBand): number[] {
  if (band === WifiBand.BAND_24) return [BAND_24_START, BAND_24_END];
  if (band === WifiBand.BAND_5) return [BAND_5_START, BAND_5_END];
  if (band === WifiBand.BAND_6) return [BAND_6_START, BAND_6_END];
  return [BAND_24_START, BAND_24_END];
}

/**
 * 频率 -> 信道号。
 *
 * 三段的公式不同，因为 5G/6G 的信道号从各自的频段起点开始编号。
 * 返回 0 表示落在已知信道栅格之外（例如 2484MHz 的 14 信道、或厂商的非常规中心频率）。
 */
export function wifiChannelOf(frequencyMhz: number): number {
  // **必须校验是否真的落在栅格上。**
  // 直接 `Math.round` 会把 2413 这种「离 2412 有 1.2 个栅格」的频率
  // 也算成信道 1 —— 那是编造出来的信道号，图上会画到错误的位置。
  // 要求**精确落在栅格上**（不做 ±N 的容差）。
  // 曾经用 ±2MHz，结果 2413 也被算成信道 1 —— 那是个编造出来的位置。
  // 真实扫描结果的中心频率都是精确的 5MHz 栅格值；宁可显示不出信道号，也不编。
  if (frequencyMhz >= BAND_24_START && frequencyMhz <= BAND_24_END) {
    const channel: number = Math.round((frequencyMhz - 2407) / 5);
    if (channel < 1 || channel > 14) return 0;
    return frequencyMhz === 2407 + channel * 5 ? channel : 0;
  }
  if (frequencyMhz >= BAND_5_START && frequencyMhz <= BAND_5_END) {
    const channel: number = Math.round((frequencyMhz - 5000) / 5);
    if (channel < 32 || channel > 177) return 0;
    return frequencyMhz === 5000 + channel * 5 ? channel : 0;
  }
  if (frequencyMhz >= BAND_6_START && frequencyMhz <= BAND_6_END) {
    const channel: number = Math.round((frequencyMhz - 5950) / 5);
    if (channel < 1 || channel > 233) return 0;
    return frequencyMhz === 5950 + channel * 5 ? channel : 0;
  }
  return 0;
}

/**
 * 信道宽度编码 -> MHz。
 *
 * 取值与 `wifi.WifiChannelWidthType` 一致；未知一律按 20MHz 处理 ——
 * 宁可低估占用宽度，也不要把一个 20MHz 的 AP 画成 160MHz 去污染整张图。
 */
export function wifiChannelWidthMhz(widthCode: number): number {
  if (widthCode === 2) return 40;
  if (widthCode === 3) return 80;
  if (widthCode === 4) return 160;
  if (widthCode === 5) return 80;
  return 20;
}

/** 该频段实际占用的宽度：2.4G 是 22MHz，其余按标称值。 */
export function occupiedWidthMhz(band: WifiBand, widthCode: number): number {
  if (band === WifiBand.BAND_24) return CHANNEL_24_WIDTH_MHZ;
  return wifiChannelWidthMhz(widthCode);
}

/** 一条待画的弧：中心频率、占用宽度、信号强度。 */
export class ChannelArc {
  public key: string = '';
  public label: string = '';
  public centerMhz: number = 0;
  public widthMhz: number = 20;
  public rssi: number = -127;
  constructor(key: string = '', label: string = '', centerMhz: number = 0, widthMhz: number = 20, rssi: number = -127) {
    this.key = key; this.label = label; this.centerMhz = centerMhz; this.widthMhz = widthMhz; this.rssi = rssi;
  }
}

/** 某个频率采样点上的拥堵情况。 */
export class ChannelLoad {
  public frequencyMhz: number = 0;
  public channel: number = 0;
  /** 占用该点的 AP 数（含邻道重叠）。 */
  public overlappingAps: number = 0;
  /** 中心正好落在该信道的 AP 数。 */
  public centeredAps: number = 0;
  /** 最强的那个 AP 的 dBm。 */
  public strongestDbm: number = -127;
  /** 归一化拥堵度 0..100。 */
  public loadScore: number = 0;
}

export class BandSurvey {
  public band: WifiBand = WifiBand.UNKNOWN;
  public arcs: ChannelArc[] = [];
  /** 采样点的拥堵曲线，按频率升序。 */
  public loads: ChannelLoad[] = [];
  public totalAps: number = 0;
  public busiestChannel: number = 0;
  public busiestScore: number = 0;
  /** 推荐信道；0 表示无法给出（该频段没有 AP）。 */
  public recommendedChannel: number = 0;
  public recommendedScore: number = 0;
}

/** dBm -> 线性功率。拥堵是功率叠加，不是 dB 相加。 */
function linearPower(dbm: number): number {
  if (dbm <= -127 || dbm > 0) return 0;
  return Math.pow(10, dbm / 10);
}

/** 2.4G 只有 1/6/11 三个互不重叠的信道；推荐必须从这里选。 */
export const NON_OVERLAPPING_24: number[] = [1, 6, 11];

/**
 * 统计一个频段。
 *
 * @param arcs 该频段的所有 AP（已经过滤好频段）
 */
export function surveyBand(band: WifiBand, arcs: ChannelArc[]): BandSurvey {
  const survey: BandSurvey = new BandSurvey();
  survey.band = band;
  survey.arcs = arcs;
  survey.totalAps = arcs.length;
  const range: number[] = bandRange(band);
  const start: number = range[0];
  const end: number = range[1];
  if (arcs.length === 0) return survey;
  // ① 逐采样点做功率叠加。
  const rawLoads: number[] = [];
  const samples: number[] = [];
  // **只在合法信道的中心频率上采样。**
  //
  // 两件事必须同时成立：
  //  ① 采样点落在信道栅格上（`origin + 5k`），否则算不出信道号；
  //  ② 该信道号必须真实存在 —— 2.4G 的栅格往前推一格是 `2407 - 5 = 2402`，
  //     那是信道 -1，采到它只会往排行里塞一个不存在的信道。
  //
  // 所以直接遍历标准信道号，而不是在频率轴上盲目步进。
  const channels: number[] = standardChannels(band);
  const centers: number[] = [];
  channels.forEach((channel: number): void => {
    const frequency: number = channelFrequency(band, channel);
    if (frequency >= start && frequency <= end) centers.push(frequency);
  });
  for (let index: number = 0; index < centers.length; index += 1) {
    const f: number = centers[index];
    let power: number = 0;
    let overlapping: number = 0;
    let centered: number = 0;
    let strongest: number = -127;
    arcs.forEach((arc: ChannelArc): void => {
      const half: number = arc.widthMhz / 2;
      if (f < arc.centerMhz - half || f > arc.centerMhz + half) return;
      power += linearPower(arc.rssi);
      overlapping += 1;
      if (Math.abs(arc.centerMhz - f) <= LOAD_SAMPLE_STEP_MHZ / 2) centered += 1;
      if (arc.rssi > strongest) strongest = arc.rssi;
    });
    rawLoads.push(power);
    samples.push(f);
    const load: ChannelLoad = new ChannelLoad();
    load.frequencyMhz = f;
    load.channel = wifiChannelOf(f);
    load.overlappingAps = overlapping;
    load.centeredAps = centered;
    load.strongestDbm = strongest;
    survey.loads.push(load);
  }
  // ② 归一化到 0..100。用最大值做分母，图上的相对高低才有意义。
  let maxPower: number = 0;
  rawLoads.forEach((value: number): void => { if (value > maxPower) maxPower = value; });
  for (let i: number = 0; i < survey.loads.length; i += 1) {
    survey.loads[i].loadScore = maxPower > 0 ? Math.round(rawLoads[i] / maxPower * 100) : 0;
  }
  // ③ 最拥挤点。
  let busiest: number = 0;
  for (let i: number = 1; i < survey.loads.length; i += 1) {
    if (survey.loads[i].loadScore > survey.loads[busiest].loadScore) busiest = i;
  }
  survey.busiestChannel = survey.loads[busiest].channel;
  survey.busiestScore = survey.loads[busiest].loadScore;
  // ④ 推荐：在候选信道里挑最空的。
  const candidates: number[] = band === WifiBand.BAND_24 ? NON_OVERLAPPING_24 : standardChannels(band);
  let bestChannel: number = 0;
  let bestScore: number = 101;
  candidates.forEach((channel: number): void => {
    const center: number = channelFrequency(band, channel);
    const score: number = loadAt(survey, center);
    if (score < bestScore) { bestScore = score; bestChannel = channel; }
  });
  survey.recommendedChannel = bestChannel;
  survey.recommendedScore = bestScore === 101 ? 0 : bestScore;
  return survey;
}

function loadAt(survey: BandSurvey, frequencyMhz: number): number {
  let best: number = 0;
  let found: boolean = false;
  survey.loads.forEach((load: ChannelLoad): void => {
    if (Math.abs(load.frequencyMhz - frequencyMhz) > LOAD_SAMPLE_STEP_MHZ / 2) return;
    best = load.loadScore;
    found = true;
  });
  return found ? best : 0;
}

/** 信道号 -> 中心频率。 */
export function channelFrequency(band: WifiBand, channel: number): number {
  if (band === WifiBand.BAND_24) return 2407 + channel * 5;
  if (band === WifiBand.BAND_5) return channel <= 144 ? 5000 + channel * 5 : 5000 + channel * 5;
  if (band === WifiBand.BAND_6) return 5950 + channel * 5;
  return 0;
}

/** 该频段的标准信道号列表（用于推荐候选与刻度）。 */
export function standardChannels(band: WifiBand): number[] {
  const result: number[] = [];
  if (band === WifiBand.BAND_24) {
    for (let channel: number = 1; channel <= 13; channel += 1) result.push(channel);
    return result;
  }
  if (band === WifiBand.BAND_5) {
    for (let channel: number = 36; channel <= 64; channel += 4) result.push(channel);
    for (let channel: number = 100; channel <= 144; channel += 4) result.push(channel);
    for (let channel: number = 149; channel <= 165; channel += 4) result.push(channel);
    return result;
  }
  if (band === WifiBand.BAND_6) {
    for (let channel: number = 1; channel <= 233; channel += 4) result.push(channel);
    return result;
  }
  return result;
}

/** 拥堵度的文字分级；0..2 供 UI 选颜色。 */
export function loadLevel(score: number): number {
  if (score >= 67) return 2;
  if (score >= 34) return 1;
  return 0;
}
