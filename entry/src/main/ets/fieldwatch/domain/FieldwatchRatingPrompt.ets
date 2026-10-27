/**
 * 评分引导的频次与状态（P1-10）。纯逻辑，可单测。
 *
 * 规则（落地文档原文）：
 *   · 在两个成功时刻出现 —— 找东西点「找到了」、一键扫描出卡后；
 *   · **同一用户 30 天内最多出现 1 次**；
 *   · **拒绝后不再出现**；
 *   · 弹层不阻塞主流程。
 *
 * 三条都要可测，所以状态与判定放在这里，页面只负责渲染与跳转。
 */

/** 30 天窗口。 */
export const RATING_COOLDOWN_MS: number = 30 * 24 * 60 * 60 * 1000;

/** 用户的评分引导状态。 */
export class RatingPromptState {
  /** 上次展示的时刻；0 表示从未展示。 */
  public lastShownAt: number = 0;
  /** 用户是否已经明确拒绝（点过「以后再说」或直接关掉）。拒绝后**永久**不再出现。 */
  public declined: boolean = false;
  /** 是否已经去商店评过（点过「去评分」）。评过同样不再打扰。 */
  public rated: boolean = false;
  constructor() {}
}

/**
 * 现在能不能弹评分引导。
 *
 * 四个条件全部满足才弹：未拒绝、未评过、30 天内没弹过、当前有可展示的成功时刻。
 * 判定顺序把「已拒绝/已评过」放最前：那是终态，没必要再算时间窗。
 */
export function shouldPromptRating(state: RatingPromptState, now: number): boolean {
  if (state.declined) return false;
  if (state.rated) return false;
  if (state.lastShownAt <= 0) return true;
  return now - state.lastShownAt >= RATING_COOLDOWN_MS;
}

/** 记录一次「已展示」，返回新状态（不修改入参，便于调用方决定何时落盘）。 */
export function markRatingShown(state: RatingPromptState, now: number): RatingPromptState {
  const next: RatingPromptState = new RatingPromptState();
  next.lastShownAt = now;
  next.declined = state.declined;
  next.rated = state.rated;
  return next;
}

/** 记录「拒绝」：永久不再出现。 */
export function markRatingDeclined(state: RatingPromptState, now: number): RatingPromptState {
  const next: RatingPromptState = markRatingShown(state, now);
  next.declined = true;
  return next;
}

/** 记录「去评分」：视为已满足，不再出现。 */
export function markRatingRated(state: RatingPromptState, now: number): RatingPromptState {
  const next: RatingPromptState = markRatingShown(state, now);
  next.rated = true;
  return next;
}

/** 状态序列化（落设置存储用）。只存三个字段，形态简单到不需要 JSON。 */
export function encodeRatingState(state: RatingPromptState): string {
  return state.lastShownAt.toString() + '|' + (state.declined ? '1' : '0') + '|' + (state.rated ? '1' : '0');
}

/** 反序列化；坏数据一律当成「从未展示」。 */
export function decodeRatingState(text: string): RatingPromptState {
  const state: RatingPromptState = new RatingPromptState();
  if (text.length === 0) return state;
  const parts: string[] = text.split('|');
  if (parts.length !== 3) return state;
  const shown: number = parseInt(parts[0], 10);
  state.lastShownAt = isNaN(shown) || shown < 0 ? 0 : shown;
  state.declined = parts[1] === '1';
  state.rated = parts[2] === '1';
  return state;
}

/**
 * 商店详情页链接。
 *
 * **核实结果**：HarmonyOS 没有提供「应用内直接弹评分框」的官方接口
 * （`@kit.StoreKit` 只有 `productViewManager` 这类商品展示能力，不含评分）。
 * 因此按文档给的兜底方案：跳应用市场详情页，由用户在详情页里评分。
 * 链接形态用 `store://appgallery.huawei.com/app/detail?id=<bundleName>`，
 * 这是应用市场支持的直达 URI；打不开时由页面兜底成一句提示而不是静默失败。
 */
export function storeDetailUri(bundleName: string): string {
  return 'store://appgallery.huawei.com/app/detail?id=' + bundleName;
}
