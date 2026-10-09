import { FieldwatchPaletteHolder } from './FieldwatchPalette';

/**
 * 通用选择芯片。
 *
 * **为什么必须是 @Component 而不是 @Builder：**
 * ArkUI 的 `@Builder` 按值参数**不具备响应式能力** —— 把 `active` 作为参数传进去后，
 * 首次渲染之后再怎么改状态，芯片外观都不会更新。
 * 之前的实现正是这样：`@Builder chip(label, active, onTap)` + 调用点 `this.tick += 1` 补救，
 * 但 `tick` 从未在 builder 内部被读取，所以完全无效 —— 表现就是「点击没反应」。
 *
 * 换成 `@Component` + `@Prop`：`@Prop` 是单向响应式的，父组件重渲染时新值会推下来，
 * 芯片因此能正确反映选中态。
 */
@Component
export struct FieldwatchChip {
  @Prop label: ResourceStr = '';
  @Prop active: boolean = false;
  /** 可选：紧凑模式，用于空间紧张的筛选条。 */
  @Prop compact: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Button(this.label)
      .height(this.compact ? 32 : 36)
      .fontSize(this.compact ? 13 : 14)
      .backgroundColor(Color.Transparent)
      .borderRadius(10)
      .borderWidth(1)
      .fontColor(this.active ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      .borderColor(this.active ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
      .onClick((): void => { this.onTap(); })
  }
}

/**
 * 预设芯片。
 *
 * 与 `FieldwatchChip` 同样的原因必须做成组件；此外它需要展示「当前预设」的选中态，
 * 旧实现把字色写死为 textDim，导致选中与否外观完全一样。
 */
/**
 * 开关行。
 *
 * 与芯片同一个原因必须是 `@Component`：`@Builder` 的按值参数不响应式，
 * 开关会停在首次渲染的位置，用户拨不动或者拨了弹回去。
 */
@Component
export struct FieldwatchSwitchRow {
  @Prop label: ResourceStr = '';
  @Prop hint: string = '';
  @Prop value: boolean = false;
  onToggle: (checked: boolean) => void = (): void => {};

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(this.label).fontSize(16).layoutWeight(1).fontColor(FieldwatchPaletteHolder.get().text)
        Toggle({ type: ToggleType.Switch, isOn: this.value })
          .selectedColor(FieldwatchPaletteHolder.get().accentActive)
          .onChange((checked: boolean): void => { this.onToggle(checked); })
      }.width('100%')
      if (this.hint.length > 0) {
        Text(this.hint).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct FieldwatchPresetChip {
  @Prop label: string = '';
  @Prop active: boolean = false;
  onTap: () => void = (): void => {};
  onLongPress: () => void = (): void => {};

  build() {
    Button(this.label)
      .height(36)
      .fontSize(14)
      .backgroundColor(Color.Transparent)
      .borderRadius(10)
      .borderWidth(1)
      .fontColor(this.active ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      .borderColor(this.active ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline)
      .onClick((): void => { this.onTap(); })
      .gesture(LongPressGesture().onAction((): void => { this.onLongPress(); }))
  }
}