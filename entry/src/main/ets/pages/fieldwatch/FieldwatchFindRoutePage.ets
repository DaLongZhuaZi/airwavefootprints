/*
 * 找东西：独立路由页壳层。
 *
 * **为什么要单独抽一个文件**：本页原先内联在 `FieldwatchPage` 的路由分发里，
 * 用的是 `.systemTransition(SLIDE_RIGHT)`。横屏分栏时右栏只占一半宽度，
 * 系统滑动转场会把整块面板从屏幕右缘推进来，与其它子页的「位移 + 淡入」不一致
 * （用户反馈「找东西页面在横屏下的关闭动画错误」）。
 *
 * 抽成组件后就能套用与 `FieldwatchDeviceDetailPage` 完全相同的自绘动画，
 * 见项目规则 PR-016。
 */
import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import {
  NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay
} from 'ngf_framework';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchFindPage } from './FieldwatchFindPage';

/** 沉浸式底板高度：与其它子页保持一致。 */
const FIND_ROUTE_UNDERLAY_HEIGHT: number = 168;

@Component
export struct FieldwatchFindRoutePage {
  /** 顶部安全区（沉浸式）。 */
  topInset: number = 0;
  /** 底部安全区高度。 */
  @Prop bottomInset: number = 0;
  /** 关闭本页（由根页面注入）。 */
  onClose: () => void = (): void => {};

  /**
   * 入场动画状态（与特征详情页 `FieldwatchDeviceDetailPage` 一致，见 PR-016）。
   *
   * 位移用 vp 而不是百分比：百分比会随容器宽度变化，
   * 横屏分栏收起时容器变全宽、位移量跟着放大，看起来像「被拉伸」。
   */
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  private leaving: boolean = false;

  aboutToAppear(): void {
    // **必须延后一帧再播入场动画**：
    // 内容先以「右侧 40vp + 全透明」落位，下一帧再动到原位。
    // 直接在同帧调 animateTo 的话，首帧就已经是终态，用户看不到任何动画
    // （参照页 `FieldwatchDeviceDetailPage` 的注释与实现完全一致）。
    setTimeout((): void => { this.playEnter(); }, 0);
  }

  /** 入场：从右侧 40vp 处淡入到位（240ms）。 */
  private playEnter(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.enterShift = 0;
      this.enterAlpha = 1;
    });
  }

  /**
   * 退场：反向滑出后再关闭。
   *
   * **出栈挂在动画 `onFinish` 上，不用 `setTimeout` 猜时间** ——
   * 猜时间会留一个空档：动画没走完就 pop，用户会看到「分栏收起时面板被拉伸」。
   */
  private leaveThenClose(): void {
    if (this.leaving) return;
    this.leaving = true;
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => { this.onClose(); }
    }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({
          spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
            FIND_ROUTE_UNDERLAY_HEIGHT)
        })
        FieldwatchFindPage({
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          hideInlineTitle: true
        })
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_find_title'),
      $r('app.string.fieldwatch_find_intro'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .onBackPressed((): boolean => { this.leaveThenClose(); return true; })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    // 入场/退场自绘（与特征详情页一致）：整页含背景一起位移+淡入淡出。
    .translate({ x: this.enterShift })
    .opacity(this.enterAlpha)
    .width('100%').height('100%')
  }
}