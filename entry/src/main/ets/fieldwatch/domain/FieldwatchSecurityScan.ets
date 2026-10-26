/**
 * 一键安防扫描的汇总与分享卡内容（纯逻辑，可单测）。
 *
 * 口径红线（落地文档 P1-5）：
 *   · 只说「正在广播的设备」，不出现「防偷拍」「查摄像头」；
 *   · 分享卡脚注必须写明「不广播的设备发现不了」；
 *   · 本模块**不产生任何用户可见文案**，只产出「有哪些数字」，
 *     文案由 UI 走资源键解析，术语红线只需在一处把关。
 */

import { RadioKind, Sighting, SignatureClass, foldedSignatureClass } from './FieldwatchModels';
import { SignatureFleet } from './signatures/FieldwatchSignatureModels';

/** 一次安防扫描的时长（文档：60 秒）。 */
export const SECURITY_SCAN_DURATION_MS: number = 60000;
/** 「跟随评分」的嫌疑线，与反跟随引擎的 70 分保持同一口径。 */
export const SECURITY_FOLLOW_SUSPECT_SCORE: number = 70;
/** 「跟随评分」的关注线（45），低于它不展示这一项。 */
export const SECURITY_FOLLOW_ATTENTION_SCORE: number = 45;
/** 「新面孔」要求的最少出现次数：只闪一次的偶发广播不算新面孔。 */
export const SECURITY_NEW_FACE_MIN_HITS: number = 3;
/** 分类 Top 保留几类。 */
export const SECURITY_TOP_CLASSES: number = 3;

/** 一个分类的计数。 */
export class SecurityClassCount {
  public category: SignatureClass;
  public count: number;
  constructor(category: SignatureClass = SignatureClass.OTHER, count: number = 0) {
    this.category = category;
    this.count = count;
  }
}

/**
 * 扫描汇总。UI 只读它，不再自己遍历 Sighting。
 *
 * `followScore` 取**窗口内最高分**而不是平均：用户问的是「有没有人在跟着我」，
 * 一台可疑设备就足以回答问题；平均分会把单台高分稀释成「看起来没事」。
 */
export class SecuritySummary {
  public total: number = 0;
  public ble: number = 0;
  public wifi: number = 0;
  public nearLink: number = 0;
  /** 分类计数（按数量降序，最多 `SECURITY_TOP_CLASSES` 类）。 */
  public topClasses: SecurityClassCount[] = [];
  /** 首次出现、且持续出现的设备台数。 */
  public newFaces: number = 0;
  /** 窗口内最高跟随评分；0 表示没有可疑目标。 */
  public followScore: number = 0;
  /** 是否有 ≥70 的可疑目标（UI 据此决定要不要说「有设备可能跟着你」）。 */
  public followSuspect: boolean = false;
  public startedAt: number = 0;
  public endedAt: number = 0;

  durationMs(): number { return this.endedAt - this.startedAt; }
  /** 0 台时 UI 要说「什么都没听到」，而不是显示一排 0。 */
  hasDevices(): boolean { return this.total > 0; }
  /** 是否值得展示跟随评分（只有过关注线才展示，避免永远显示一个 0）。 */
  showsFollow(): boolean { return this.followScore >= SECURITY_FOLLOW_ATTENTION_SCORE; }
}

/**
 * 按类别计数，降序取前 N 类。
 *
 * 分类来源是设备命中的特征库条目：一台设备可能命中多个 fleet，
 * **只取第一个**（`signatureIds[0]`）—— 同一台设备算进两个类会让「分类 Top」
 * 的总和超过设备总数，用户一眼就能看出数字不对。
 * 没命中任何 fleet 的设备归入 OTHER，保证各类计数之和 = 设备总数。
 */
export function topClassesOf(sightings: Sighting[], fleets: SignatureFleet[]): SecurityClassCount[] {
  const counts: Map<string, number> = new Map<string, number>();
  sightings.forEach((sighting: Sighting): void => {
    let category: SignatureClass = SignatureClass.OTHER;
    if (sighting.signatureIds.length > 0) {
      const firstId: string = sighting.signatureIds[0];
      const fleet: SignatureFleet | undefined = fleets.find((item: SignatureFleet): boolean => item.id === firstId);
      if (fleet !== undefined) category = foldedSignatureClass(fleet.category);
    }
    // **没命中特征库时不要一律塞进「其他」**：实测 119 台里有 91 台落进去，
    // 「分类 Top」就变成「其他 91 / 查找器 16 / 手机 8」，等于没分类。
    // Wi-Fi 设备能确定是「路由器/网络设备」（SSID 就是它的身份），
    // 所以按无线电种类给一个**有意义的兜底**；BLE 无特征命中仍归 OTHER，
    // 因为我们确实不知道它是什么，编一个类别就是撒谎。
    if (category === SignatureClass.OTHER && sighting.kind === RadioKind.WIFI) {
      category = SignatureClass.ISP;
    }
    const key: string = String(category);
    const current: number | undefined = counts.get(key);
    counts.set(key, current === undefined ? 1 : current + 1);
  });
  const result: SecurityClassCount[] = [];
  counts.forEach((count: number, key: string): void => {
    result.push(new SecurityClassCount(key as SignatureClass, count));
  });
  // 数量降序；同数量按类别名升序 —— 否则同一份数据每次渲染顺序都可能变，
  // 分享卡上「Top 1」会莫名其妙地在两类之间跳。
  result.sort((first: SecurityClassCount, second: SecurityClassCount): number => {
    if (second.count !== first.count) return second.count - first.count;
    return String(first.category).localeCompare(String(second.category));
  });
  if (result.length <= SECURITY_TOP_CLASSES) return result;
  return result.slice(0, SECURITY_TOP_CLASSES);
}

/**
 * 统计「新面孔」：本次扫描开始时还不存在、结束前已出现 ≥N 次的设备。
 *
 * 用「开始时刻之前是否见过」而不是「firstSeen 是否等于本次扫描开始」，
 * 是因为后者会被 app 冷启动时的首批快照全部判成新的 —— 那样扫一次就报几十个
 * 「新面孔」，用户立刻就不信这个数字了。
 * 因此 `knownKeys` 必须由调用方传入**扫描开始那一刻的实时列表键集合**。
 */
export function newFaceCount(sightings: Sighting[], knownKeys: string[]): number {
  let count: number = 0;
  sightings.forEach((sighting: Sighting): void => {
    if (knownKeys.indexOf(sighting.key) >= 0) return;
    if (sighting.count < SECURITY_NEW_FACE_MIN_HITS) return;
    count += 1;
  });
  return count;
}

/** 按无线电种类分别计数；三个数之和等于 total。 */
export function countByKind(sightings: Sighting[]): number[] {
  let ble: number = 0;
  let wifi: number = 0;
  let nearLink: number = 0;
  sightings.forEach((sighting: Sighting): void => {
    if (sighting.kind === RadioKind.WIFI) wifi += 1;
    else if (sighting.kind === RadioKind.NEARLINK) nearLink += 1;
    else ble += 1;
  });
  return [ble, wifi, nearLink];
}

/**
 * 组装汇总。
 *
 * @param sightings    扫描结束时仍在本场里的设备
 * @param fleets       当前特征库（用来把 signatureIds 翻成类别）
 * @param knownKeys    扫描**开始**那一刻已存在的设备键（用于「新面孔」基线）
 * @param followScore  当前窗口内的最高跟随评分（0 表示没有）
 */
export function buildSecuritySummary(sightings: Sighting[], fleets: SignatureFleet[], knownKeys: string[],
  followScore: number, startedAt: number, endedAt: number): SecuritySummary {
  const summary: SecuritySummary = new SecuritySummary();
  summary.total = sightings.length;
  const kinds: number[] = countByKind(sightings);
  summary.ble = kinds[0];
  summary.wifi = kinds[1];
  summary.nearLink = kinds[2];
  summary.topClasses = topClassesOf(sightings, fleets);
  summary.newFaces = newFaceCount(sightings, knownKeys);
  // 负分与 NaN 都不该出现在卡片上：跟随评分由引擎给出，这里兜一道底。
  const safeScore: number = isNaN(followScore) ? 0 : Math.max(0, Math.round(followScore));
  summary.followScore = safeScore;
  summary.followSuspect = safeScore >= SECURITY_FOLLOW_SUSPECT_SCORE;
  summary.startedAt = startedAt;
  summary.endedAt = endedAt;
  return summary;
}

/**
 * 分享卡上的一句话结论键（不是文案本身）。
 *
 * 三种可能，UI 按资源键渲染：
 *   · suspicious：有 ≥70 分目标 → 「有设备可能跟着你」
 *   · crowded：设备较多（≥20 台）→ 「身边设备挺多的」
 *   · quiet：其余 → 「身边比较安静」
 * **绝不出现「安全」「被偷拍」一类结论**：本应用只测「有没有在广播」，
 * 而不在广播的设备它根本发现不了，说「安全」是在撒谎。
 */
export function summaryHeadlineKey(summary: SecuritySummary): string {
  if (summary.followSuspect) return 'app.string.fieldwatch_security_headline_suspicious';
  if (summary.total >= 20) return 'app.string.fieldwatch_security_headline_crowded';
  return 'app.string.fieldwatch_security_headline_quiet';
}
