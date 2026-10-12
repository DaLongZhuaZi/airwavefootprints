/**
 * 启动引导的「换页点击闸门」。
 *
 * **为什么单独抽成模块：** 这段判定就是「引导第 ④ 页被直接跳过」这个真机问题的全部逻辑。
 * 留在 `@Component` 里只能靠手点复现；抽成纯函数后 LocalUnit 可以把
 * 「按下在旧页、抬起在新页」「连点第二下」「隔一会儿的正常点击」三种情形逐条钉死，
 * 以后改动画时长或按钮文案都不会再悄悄退回去。
 *
 * **问题现场：** 底部主按钮换页前后**位置不变、文案会变**（前三页「继续」→ 末页「开始使用」），
 * 而换页要等 165 ms 加上 260 ms 入场动画才稳定。只要「按下」发生在旧页、
 * 「抬起」落到新页，这一次点击就会被新文案吃掉 —— 用户以为在翻页，
 * 实际点到了「开始使用」，第 ④ 页只闪现不到一帧就结束了引导。
 */

/** 换页落地后的点击静默窗口（毫秒）：覆盖 260 ms 入场动画，外加人的反应时间。 */
export const ONB_STEP_GUARD_MS: number = 420;

/**
 * 这一次点击是否还算数。
 *
 * @param pressedStep 按下时所在的步骤（由 `onTouch` 的 Down 记录）
 * @param currentStep 判定时的当前步骤
 * @param stepChangedAt 换页真正落地的时刻（毫秒时间戳）
 * @param now 判定时刻（毫秒时间戳）
 */
export function onboardingTapAccepted(pressedStep: number, currentStep: number, stepChangedAt: number, now: number): boolean {
  // ① 按下与抬起之间换过页 —— 这次点击属于上一页，作废。
  if (pressedStep !== currentStep) return false;
  // ② 换页落地后的静默窗口内 —— 忽略（连点的第二下必然落在新文案上）。
  return now - stepChangedAt >= ONB_STEP_GUARD_MS;
}
