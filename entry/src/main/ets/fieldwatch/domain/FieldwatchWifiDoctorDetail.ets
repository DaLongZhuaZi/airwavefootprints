/**
 * Wi-Fi 体检页的 AP 详情与房间趋势（P3-3 第 1 项）。纯逻辑 + 可单测。
 *
 * 数据来源全部是**已有能力**：
 *   · 当前 AP：`WifiCurrentAp`（WifiLink，已在不新增权限的前提下可用）
 *   · 房间趋势：`fieldwatch_room_checks` 表（RoomCheckRepository，P1-7 已落库）
 * 本模块不碰系统接口，只做「把已有数据整理成人能看的东西」。
 */

import { RoomCheck, RoomSignalGrade, gradeOf } from './FieldwatchWifiDoctor';

/**
 * 由频段推出信道。
 *
 * 为什么不用系统给信道：`WifiCurrentAp` 只有 `band`（MHz），
 * 频段 → 信道是确定映射，自己算比再申请一个权限去读信道干净。
 * 2.4G 用经典公式 (f-2407)/5；5G 从 5180 起每 5MHz 一个信道。
 *
 * 返回 0 表示无法推断（未知频段）。
 */
export function channelOfBand(band: number): number {
  if (!(band > 0)) return 0;
  if (band >= 2400 && band < 2500) {
    // 2.4G 信道 1..13，中心频点 2412 + 5*(ch-1)。
    const channel: number = Math.round((band - 2407) / 5);
    return channel >= 1 && channel <= 14 ? channel : 0;
  }
  if (band >= 4900 && band < 5900) {
    // 5G 信道号 = (f - 5000) / 5。
    const channel: number = Math.round((band - 5000) / 5);
    return channel > 0 ? channel : 0;
  }
  return 0;
}

/** 频段的展示名（2.4G / 5G / 6G / 未知）。 */
export function bandLabelKey(band: number): string {
  if (band >= 2400 && band < 2500) return 'app.string.fieldwatch_wifi_band_24';
  if (band >= 4900 && band < 5900) return 'app.string.fieldwatch_wifi_band_5';
  if (band >= 5900 && band < 7200) return 'app.string.fieldwatch_wifi_band_6';
  return 'app.string.fieldwatch_wifi_band_unknown';
}

/**
 * 该信道是否属于「拥挤」区段。
 *
 * 2.4G 只有 1 / 6 / 11 三个互不重叠信道，落在这三个上算好；
 * 其余（含中间重叠段）都算拥挤 —— 这与信道分析页的建议口径一致。
 * 5G 及以上不做此判断（信道多、重叠少），一律返回 false。
 */
export function isCrowdedChannel(channel: number, band: number): boolean {
  if (!(channel > 0)) return false;
  if (band >= 2400 && band < 2500) {
    return channel !== 1 && channel !== 6 && channel !== 11;
  }
  return false;
}

/**
 * AP 快照：详情渲染只需这四项。
 *
 * 单独定义而不是复用 `WifiCurrentAp`：领域层不该依赖 radio 层的类，
 * 而且这个结构与「当前连接」这件事解耦，可以来自任何来源（含测试构造）。
 */
export interface ApSnapshot {
  ssid: string;
  bssid: string;
  rssi: number;
  band: number;
}

/** 当前 AP 的详情行（供 UI 逐行渲染）。 */
export class ApDetailRow {
  public labelKey: string = '';
  public value: string = '';
  /** 是否为需要提醒的值（拥挤信道等）。 */
  public warn: boolean = false;
  constructor(labelKey: string = '', value: string = '', warn: boolean = false) {
    this.labelKey = labelKey;
    this.value = value;
    this.warn = warn;
  }
}

/**
 * 组装当前 AP 的详情行。
 *
 * **BSSID 标注「本次会话内参考」**：没有 GET_WIFI_PEERS_MAC 时系统返回随机 BSSID，
 * 把它当成长期标识会误导用户（V6-b 已核实）。
 */
export function apDetailRows(ap: ApSnapshot): ApDetailRow[] {
  const rows: ApDetailRow[] = [];
  const channel: number = channelOfBand(ap.band);
  rows.push(new ApDetailRow('app.string.fieldwatch_wifi_detail_ssid',
    ap.ssid.length > 0 ? ap.ssid : '-'));
  rows.push(new ApDetailRow('app.string.fieldwatch_wifi_detail_bssid',
    ap.bssid.length > 0 ? ap.bssid : '-'));
  rows.push(new ApDetailRow('app.string.fieldwatch_wifi_detail_band', bandLabelKey(ap.band)));
  rows.push(new ApDetailRow('app.string.fieldwatch_wifi_detail_channel',
    channel > 0 ? channel.toString() : '-', isCrowdedChannel(channel, ap.band)));
  rows.push(new ApDetailRow('app.string.fieldwatch_wifi_detail_rssi',
    ap.rssi < 0 ? ap.rssi.toString() + ' dBm' : '-', false));
  return rows;
}

/**
 * 一个房间的趋势。
 *
 * 「历次分档变化」= 按时间正序排列的各次 grade（UNKNOWN 表示那次样本不足）。
 */
export class RoomTrend {
  public label: string = '';
  /** 按时间正序的档位序列。 */
  public grades: RoomSignalGrade[] = [];
  /** 历次测量时刻（与 grades 同序）。 */
  public times: number[] = [];
  constructor(label: string = '') { this.label = label; }
  /** 次数。 */
  count(): number { return this.grades.length; }
  /** 最新一次档位；没有记录返回 UNKNOWN。 */
  latest(): RoomSignalGrade {
    return this.grades.length === 0 ? RoomSignalGrade.UNKNOWN : this.grades[this.grades.length - 1];
  }
  /** 首次档位；没有记录返回 UNKNOWN。 */
  first(): RoomSignalGrade {
    return this.grades.length === 0 ? RoomSignalGrade.UNKNOWN : this.grades[0];
  }
  /** 相比首次，信号是变好 / 变差 / 不变（按档位序号）。 */
  trend(): number {
    if (this.grades.length < 2) return 0;
    const a: number = gradeOrder(this.first());
    const b: number = gradeOrder(this.latest());
    // UNKNOWN 不参与比较：样本不足不能算「变差」。
    if (a < 0 || b < 0) return 0;
    return b - a;
  }
}

/** 档位强弱序号：越大越强；UNKNOWN 返回 -1（不参与比较）。 */
export function gradeOrder(grade: RoomSignalGrade): number {
  if (grade === RoomSignalGrade.BAD) return 0;
  if (grade === RoomSignalGrade.WEAK) return 1;
  if (grade === RoomSignalGrade.OK) return 2;
  if (grade === RoomSignalGrade.STRONG) return 3;
  return -1;
}

/**
 * 从房间体检记录算出每个房间的趋势。
 *
 * @param records 仓储读出的记录（顺序任意）
 * @returns 按房间标签聚合的趋势，房间顺序按最近一次测量倒序（最近测的排前面）
 */
export function roomTrends(records: RoomCheck[]): RoomTrend[] {
  const byLabel: Map<string, RoomCheck[]> = new Map<string, RoomCheck[]>();
  records.forEach((record: RoomCheck): void => {
    const key: string = record.label;
    const list: RoomCheck[] | undefined = byLabel.get(key);
    if (list === undefined) {
      const created: RoomCheck[] = [];
      created.push(record);
      byLabel.set(key, created);
    } else {
      list.push(record);
    }
  });
  const trends: RoomTrend[] = [];
  byLabel.forEach((list: RoomCheck[], key: string): void => {
    const sorted: RoomCheck[] = list.slice().sort((a: RoomCheck, b: RoomCheck): number => a.endedAt - b.endedAt);
    const trend: RoomTrend = new RoomTrend(key);
    sorted.forEach((record: RoomCheck): void => {
      trend.grades.push(gradeOf(record.medianRssi, record.sampleCount));
      trend.times.push(record.endedAt);
    });
    trends.push(trend);
  });
  // 最近测过的房间排前面。
  trends.sort((a: RoomTrend, b: RoomTrend): number => {
    const ta: number = a.times.length === 0 ? 0 : a.times[a.times.length - 1];
    const tb: number = b.times.length === 0 ? 0 : b.times[b.times.length - 1];
    return tb - ta;
  });
  return trends;
}

// ── 复测提醒（P3-3 第 1 项）──

/**
 * 复测提醒状态。
 *
 * 设计约束（文档原文）：建议发出后，**下次进页 / 下次扫描**时提示复测一次；
 * 不是后台常驻提醒，可关闭、不骚扰。
 * 因此这里只有「待提示」这一个布尔 + 一个可关闭开关，没有定时器、没有通知。
 */
export class RetestPrompt {
  /** 是否有待提示的复测（上次给了改信道建议）。 */
  public pending: boolean = false;
  /** 建议的信道（提示语里要说「试试信道 N」）。 */
  public suggestedChannel: number = 0;
  /** 需要复测的房间标签（可空：整屋信道建议时为空）。 */
  public roomLabel: string = '';
  constructor() {}
  /** 是否应该展示提示：待提示且用户没关掉。 */
  shouldShow(disabled: boolean): boolean { return this.pending && !disabled; }
}

/** 是否该在进页时弹复测提醒（与 `RetestPrompt.shouldShow` 同一口径，独立函数便于单测）。 */
export function shouldPromptRetest(pending: boolean, disabled: boolean): boolean {
  return pending && !disabled;
}
