import { FieldwatchPaletteHolder } from './FieldwatchPalette';

/**
 * 扫描强度：固定三节点的进度条控件。
 *
 * **为什么不用三个芯片：** 三档本质是同一根轴上的三个位置
 * （基础 30 秒 ← 平衡 45 秒 → 节能 60 秒），进度条能把「当前落在轴的哪一段」
 * 直接画出来 —— 往右一格就是再省一档；并排的三个芯片只能表达「选中了哪个」，
 * 表达不出这种方向感。
 *
 * **三种改法都能用（保留原先「一次点中」的手感）：**
 * - 拖动滑块：`step = 1`，松手自动吸附到最近的节点；
 * - 点击轨道空白处：跳到点击位置最近的节点；
 * - 点击节点下方的文字：等价于选中该档。
 *
 * **为什么三个标签不抽成 `@Builder`：** `@Builder` 的按值参数不具响应式
 * （见 `FieldwatchChip` 顶部那段说明），选中态会停在首次渲染的结果上，
 * 表现就是「点了颜色不变」。因此标签直接写在 `build()` 里、只读 `this.intensity`。
 *
 * **职责边界：** 组件只回传档位字符串；生效与落盘由调用方走应用层
 * `setScanIntensity()`（引导页与设置页共用同一套副作用，避免两处漂移）。
 */
@Component
export struct FieldwatchIntensitySlider {
  /** 当前档位：'basic' | 'balanced' | 'saver'。 */
  @Prop intensity: string = 'balanced';
  /**
   * 档位确定后回调一次。
   *
   * **拖动过程中不回调**：`onChange` 在拖动时每帧都触发，逐帧落盘会把
   * 扫描器反复重配，用户能直接感到卡顿。
   */
  onPick: (intensity: string) => void = (): void => {};

  /** 档位 → 节点下标（0 / 1 / 2）。 */
  private nodeOf(intensity: string): number {
    if (intensity === 'basic') return 0;
    if (intensity === 'saver') return 2;
    return 1;
  }

  /** 节点下标 → 档位；越界时收敛到两端，避免浮点取整出现第三个值。 */
  private intensityAt(index: number): string {
    if (index <= 0) return 'basic';
    if (index >= 2) return 'saver';
    return 'balanced';
  }

  build() {
    Column({ space: 2 }) {
      Slider({ value: this.nodeOf(this.intensity), min: 0, max: 2, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(6)
        .showSteps(true)
        .selectedColor(FieldwatchPaletteHolder.get().accent)
        .trackColor(FieldwatchPaletteHolder.get().rssiTrack)
        .blockColor(FieldwatchPaletteHolder.get().accentActive)
        .onChange((value: number, mode: SliderChangeMode): void => {
          // 只认「松手」与「点击轨道」两种结束态；Begin/Moving 交给滑块自己画。
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) return;
          this.onPick(this.intensityAt(Math.round(value)));
        })
      Row() {
        Text($r('app.string.wifi_scan_basic')).fontSize(12).layoutWeight(1).textAlign(TextAlign.Start)
          .fontColor(this.intensity === 'basic' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
          .onClick((): void => { this.onPick('basic'); })
        Text($r('app.string.wifi_scan_balanced')).fontSize(12).layoutWeight(1).textAlign(TextAlign.Center)
          .fontColor(this.intensity === 'balanced' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
          .onClick((): void => { this.onPick('balanced'); })
        Text($r('app.string.wifi_scan_saver')).fontSize(12).layoutWeight(1).textAlign(TextAlign.End)
          .fontColor(this.intensity === 'saver' ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
          .onClick((): void => { this.onPick('saver'); })
      }.width('100%')
    }.width('100%')
  }
}
