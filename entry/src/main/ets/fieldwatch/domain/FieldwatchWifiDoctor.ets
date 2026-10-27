/**
 * Wi-Fi 体检的房间版逻辑（P1-7）。纯逻辑 + 可单测，不碰 UI 与系统 API。
 *
 * 它回答四个问题（落地文档原文）：
 *   ① 每个房间的信号分档；
 *   ② 最差的房间点名；
 *   ③ 信道拥挤程度；
 *   ④ 双频缺口（家里有 5G 却没用上）。
 *
 * **阈值全部集中成常量**：文档要求「按实测调」，散落的魔法数没法一次性调。
 */

import { BandSurvey, WifiBand } from './FieldwatchChannelAnalysis';

/** 一次静置采样的时长（文档：20 秒）。 */
export const ROOM_SCAN_DURATION_MS: number = 20000;
/** 信号分档阈值（样本中位 RSSI，dBm）。 */
export const ROOM_STRONG_DBM: number = -55;
export const ROOM_OK_DBM: number = -67;
export const ROOM_WEAK_DBM: number = -75;
/** 低于这个值基本不可用（视频会卡）。 */
export const ROOM_BAD_DBM: number = -80;
/** 一个房间至少要多少个样本才算「测过」。 */
export const ROOM_MIN_SAMPLES: number = 5;
/** 双频缺口的判定：5G 上至少要有这么多 AP 才算「家里有 5G」。 */
export const ROOM_DUAL_BAND_MIN_APS: number = 1;
/** 信道拥挤判定：同信道 AP 数达到它就算拥挤。 */
export const ROOM_CROWDED_APS: number = 4;

/** 信号档位。 */
export enum RoomSignalGrade {
  STRONG = 'strong',
  OK = 'ok',
  WEAK = 'weak',
  BAD = 'bad',
  UNKNOWN = 'unknown'
}

/** 一个房间的采样结果。 */
export class RoomCheck {
  /** 房间标签（用户自己起的名，如「客厅」「主卧」）。 */
  public label: string = '';
  /** 该房间实测到的中位 RSSI；0 表示没有样本。 */
  public medianRssi: number = 0;
  public sampleCount: number = 0;
  /** 该房间最强 AP 的 BSSID（用来判断在房间里连的是哪个）。 */
  public bestBssid: string = '';
  public bestChannel: number = 0;
  public startedAt: number = 0;
  public endedAt: number = 0;
  constructor(label: string = '') { this.label = label; }
  /** 该房间是否算测过（样本够）。 */
  measured(): boolean { return this.sampleCount >= ROOM_MIN_SAMPLES; }
  grade(): RoomSignalGrade { return gradeOf(this.medianRssi, this.sampleCount); }
}

/** RSSI → 档位。样本不足一律 UNKNOWN，不拿单次读数冒充「房间信号」。 */
export function gradeOf(medianRssi: number, sampleCount: number): RoomSignalGrade {
  if (sampleCount < ROOM_MIN_SAMPLES) return RoomSignalGrade.UNKNOWN;
  if (medianRssi >= ROOM_STRONG_DBM) return RoomSignalGrade.STRONG;
  if (medianRssi >= ROOM_OK_DBM) return RoomSignalGrade.OK;
  if (medianRssi >= ROOM_WEAK_DBM) return RoomSignalGrade.WEAK;
  return RoomSignalGrade.BAD;
}

/**
 * 中位数。
 *
 * 用中位数而不是平均：一个房间静置 20 秒里几乎必然夹着几个 -90 的野值
 * （人走过、门关上），平均值会被它们拖下去，得出一间房「信号很差」的错误结论。
 */
export function medianOf(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted: number[] = values.slice().sort((a: number, b: number): number => a - b);
  const middle: number = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/** 体检报告的整体结论。 */
export class WifiDoctorReport {
  public rooms: RoomCheck[] = [];
  /** 最差房间的下标；-1 表示没有可比较的房间。 */
  public worstIndex: number = -1;
  /** 24G / 5G 各有几个 AP（用来判双频缺口）。 */
  public aps24: number = 0;
  public aps5: number = 0;
  /** 最拥挤的信道与它的 AP 数。 */
  public crowdedChannel: number = 0;
  public crowdedCount: number = 0;
  /** 是否存在双频缺口（有 5G 能力但 5G 上一次都没听到）。 */
  public dualBandGap: boolean = false;
  constructor() {}
  /** 有没有任何一个房间真的测过。 */
  hasMeasuredRoom(): boolean {
    let measured: boolean = false;
    this.rooms.forEach((room: RoomCheck): void => { if (room.measured()) measured = true; });
    return measured;
  }
  worstRoom(): RoomCheck | undefined {
    return this.worstIndex < 0 || this.worstIndex >= this.rooms.length ? undefined : this.rooms[this.worstIndex];
  }
}

/**
 * 找出最差的房间。
 *
 * 只比较**测过的**房间：没测的房间 medianRssi 是 0，直接比较会把它们当成
 * 「信号极差」，于是「最差房间」永远是那个没测的房间。
 */
export function worstRoomIndex(rooms: RoomCheck[]): number {
  let index: number = -1;
  let lowest: number = 0;
  for (let i: number = 0; i < rooms.length; i += 1) {
    if (!rooms[i].measured()) continue;
    if (index < 0 || rooms[i].medianRssi < lowest) {
      index = i;
      lowest = rooms[i].medianRssi;
    }
  }
  return index;
}

/**
 * 从信道调查结果里统计「最拥挤的信道」。
 *
 * 用 `surveyBand` 已经算好的 busiestChannel / busiestScore，
 * 不另写一套计数 —— 否则工具箱页与体检页会给出两个不同的「最挤信道」。
 */
export function crowdingOf(survey: BandSurvey): number[] {
  return [survey.busiestChannel, survey.busiestScore];
}

/**
 * 组装体检报告。
 *
 * @param rooms   各房间的采样结果
 * @param aps24   2.4G 上听到的 AP 数
 * @param aps5    5G 上听到的 AP 数
 * @param survey24 2.4G 的信道调查（可为空，此时不给拥挤结论）
 */
export function buildWifiDoctor(rooms: RoomCheck[], aps24: number, aps5: number,
  survey24: BandSurvey | undefined): WifiDoctorReport {
  const report: WifiDoctorReport = new WifiDoctorReport();
  report.rooms = rooms;
  report.worstIndex = worstRoomIndex(rooms);
  report.aps24 = aps24;
  report.aps5 = aps5;
  if (survey24 !== undefined) {
    const crowding: number[] = crowdingOf(survey24);
    report.crowdedChannel = crowding[0];
    report.crowdedCount = crowding[1];
  }
  // 双频缺口：家里确实有 5G 信号（aps5 达到下限），但采样房间里一次都没听到 5G。
  // 反过来「一个 5G AP 都没有」是房子/设备限制，不是用户能修的问题，不报。
  report.dualBandGap = aps5 < ROOM_DUAL_BAND_MIN_APS && aps24 >= ROOM_DUAL_BAND_MIN_APS;
  return report;
}

/** 信道是否拥挤（用于报告里点名）。 */
export function channelCrowded(count: number): boolean {
  return count >= ROOM_CROWDED_APS;
}

/**
 * 报告的行摘要（键 + 参数），UI 按资源键渲染。
 * **不返回裸中文**：文案要过 i18n 与术语 grep 两道关。
 */
export class DoctorLine {
  public key: string;
  public arg: string;
  constructor(key: string = '', arg: string = '') { this.key = key; this.arg = arg; }
}

export function doctorLines(report: WifiDoctorReport): DoctorLine[] {
  const lines: DoctorLine[] = [];
  const worst: RoomCheck | undefined = report.worstRoom();
  // 只有一个房间时**不说「最弱」**：一个房间谈不上最弱，那句话会读起来像 bug。
  // 至少两间才比较，这也是文档「至少 2 个家庭环境实测」的同一口径。
  if (worst !== undefined && report.rooms.length > 1) {
    lines.push(new DoctorLine('app.string.fieldwatch_wifi_doctor_worst', worst.label));
  }
  if (worst !== undefined) {
    // 档位是枚举值，**必须由 UI 翻译**；这里传原始值会让界面显示 `strong`。
    lines.push(new DoctorLine('app.string.fieldwatch_wifi_doctor_grade', worst.grade()));
  }
  if (report.crowdedChannel > 0 && channelCrowded(report.crowdedCount)) {
    lines.push(new DoctorLine('app.string.fieldwatch_wifi_doctor_crowded', report.crowdedChannel.toString()));
  }
  if (report.dualBandGap) {
    lines.push(new DoctorLine('app.string.fieldwatch_wifi_doctor_dualband', ''));
  }
  return lines;
}

/** 频段标签，供 UI 直接显示。 */
export function bandLabel(band: WifiBand): string {
  if (band === WifiBand.BAND_24) return '2.4G';
  if (band === WifiBand.BAND_5) return '5G';
  if (band === WifiBand.BAND_6) return '6G';
  return '';
}
