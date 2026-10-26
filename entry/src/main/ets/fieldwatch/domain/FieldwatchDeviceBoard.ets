/**
 * 我的设备看板的数据装配（P2-12）与找车（P2-13）。纯逻辑 + 可单测。
 *
 * 看板每台设备一张卡，卡片要回答四件事：
 *   ① 在附近吗（实时列表里有它）；
 *   ② 上次见到是什么时候；
 *   ③ 叫什么（自定义名优先）；
 *   ④ 电量多少（**解不到就不显示**）。
 */

import { OwnDeviceProfile } from './FieldwatchOwnDevice';

/** 「在附近」的判定窗口：与在场判定的残留时间同量级。 */
export const BOARD_NEARBY_MS: number = 60 * 1000;

/** 看板卡片上的一台设备。 */
export class DeviceBoardCard {
  public profileId: string = '';
  public label: string = '';
  /** 实时列表里的键；空串表示此刻不在附近。 */
  public liveKey: string = '';
  public nearby: boolean = false;
  public lastSeenAt: number = 0;
  /** 电量百分比；-1 表示解不出来（**不要显示这一行**）。 */
  public batteryPercent: number = -1;
  /** 是否标记为「我的车」（P2-13）。 */
  public isCar: boolean = false;
  /** 最后听到时的坐标；0 表示没有定位。 */
  public lastLatitude: number = 0;
  public lastLongitude: number = 0;
  constructor() {}
  hasBattery(): boolean { return this.batteryPercent >= 0 && this.batteryPercent <= 100; }
  hasLocation(): boolean { return this.lastLatitude !== 0 && this.lastLongitude !== 0; }
}

/** 组装一张卡片。 */
export function boardCardOf(profile: OwnDeviceProfile, liveKey: string, lastSeenAt: number,
  batteryPercent: number, now: number): DeviceBoardCard {
  const card: DeviceBoardCard = new DeviceBoardCard();
  card.profileId = profile.id;
  card.label = profile.label();
  card.liveKey = liveKey;
  // 「在附近」看的是**实时键是否命中**而不是时间差：
  // 时间差会把「刚离开 30 秒」也显示成在附近，用户按着卡片去找会扑空。
  card.nearby = liveKey.length > 0;
  card.lastSeenAt = lastSeenAt;
  card.batteryPercent = batteryPercent;
  card.isCar = profile.kind === 'car';
  card.lastLatitude = profile.lastLatitude;
  card.lastLongitude = profile.lastLongitude;
  return card;
}

/**
 * 电量显示文本；解不出来返回空串。
 *
 * 空串的语义是「这一行不渲染」。**绝不返回「--%」或「未知」**：
 * 那会让用户以为设备报了电量但读不出来，而实际上是设备根本没广播电量。
 */
export function batteryText(percent: number): string {
  if (percent < 0 || percent > 100) return '';
  return percent.toString() + '%';
}

/**
 * 找车的「最后听到它」一行（P2-13）。
 *
 * 格式：`今天 18:02，B2 层附近`。时间用相对日（今天/昨天/日期），
 * 「楼层」在拿不到定位时省略 —— **不编造楼层**。
 * 返回的是**片段**，由 UI 用资源模板拼起来（文案要过 i18n）。
 */
export class CarLastSeenParts {
  /** 时间片段（如「今天 18:02」）。 */
  public when: string = '';
  /** 位置片段（如「B2 层附近」）；空串表示没有定位。 */
  public where: string = '';
  constructor(when: string = '', where: string = '') { this.when = when; this.where = where; }
}

/** 两个时间是否同一天（本机时区）。 */
export function sameDay(a: number, b: number): boolean {
  if (a <= 0 || b <= 0) return false;
  const first: Date = new Date(a);
  const second: Date = new Date(b);
  return first.getFullYear() === second.getFullYear()
    && first.getMonth() === second.getMonth()
    && first.getDate() === second.getDate();
}

/** 时刻 → `HH:mm`。 */
export function clockOf(at: number): string {
  if (at <= 0) return '';
  const date: Date = new Date(at);
  return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
}

/**
 * 组装「最后听到它」的两个片段。
 *
 * @param at        最后听到的时刻
 * @param latitude  纬度（0 表示没有定位）
 * @param longitude 经度
 * @param floorHint 楼层提示（通常拿不到；空串则省略）
 */
export function carLastSeenParts(at: number, latitude: number, longitude: number, floorHint: string): CarLastSeenParts {
  const parts: CarLastSeenParts = new CarLastSeenParts();
  if (at > 0) {
    const today: boolean = sameDay(at, Date.now());
    parts.when = today ? clockOf(at) : new Date(at).toLocaleDateString() + ' ' + clockOf(at);
  }
  // 有坐标才算「知道在哪」；没有坐标时 where 留空，UI 不渲染那一段。
  if (latitude !== 0 && longitude !== 0) {
    parts.where = floorHint.length > 0 ? floorHint : '';
  }
  return parts;
}

/** 坐标是否值得跳地图（有定位且不是 0,0 这种占位）。 */
export function hasUsableLocation(latitude: number, longitude: number): boolean {
  if (latitude === 0 && longitude === 0) return false;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return false;
  return true;
}

/**
 * 跳系统地图的 URI。**不自建地图**（文档明确要求）。
 *
 * 用 `geo:` 方案：系统地图与第三方地图都认这个 scheme，
 * 且不绑定某一家厂商的地图应用。
 */
export function mapUri(latitude: number, longitude: number, label: string): string {
  const query: string = latitude.toString() + ',' + longitude.toString();
  return 'geo:' + query + '?q=' + query + '(' + encodeURIComponent(label) + ')';
}

/** 看板排序：在附近优先，其次按上次见到的新旧。 */
export function sortBoardCards(cards: DeviceBoardCard[]): DeviceBoardCard[] {
  return cards.slice().sort((a: DeviceBoardCard, b: DeviceBoardCard): number => {
    if (a.nearby !== b.nearby) return a.nearby ? -1 : 1;
    return b.lastSeenAt - a.lastSeenAt;
  });
}
