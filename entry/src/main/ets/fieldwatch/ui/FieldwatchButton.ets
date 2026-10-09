import { FieldwatchPaletteHolder } from './FieldwatchPalette';
/**
 * 可选芯片：用于「从一组里选一个」的场景（类别、来源、规则类型、无线电种类、
 * 字段类型、字节序、排序方式…）。
 *
 * **为什么要做成组件**：这类按钮此前写成
 * `backgroundColor(选中 ? button_primary : background_secondary)`，
 * **只改底色、不设文字色**。深色主题下 button_primary 是荧光绿 `#3DFF9A`，
 * 而 ArkUI 的默认文字色是白色 —— 白字打在荧光绿上对比度约 1.4:1，
 * 完全看不清。选中态与未选中态的文字色必须与底色成对定义，
 * 交给调用方各自设置就一定还会漏。
 */
@Component
export struct FieldwatchSegmentedChip {
  @Prop label: ResourceStr = '';
  @Prop selected: boolean = false;
  /** 紧凑档：36 高、13 号字；常规档 40 高、14 号字。 */
  @Prop compact: boolean = true;
  /** 是否占满一行（并为并排场景提供 layoutWeight）。 */
  @Prop fillWidth: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Button(this.label)
      .height(this.compact ? 36 : 40)
      .fontSize(this.compact ? 13 : 14)
      .borderRadius(12)
      .backgroundColor(this.selected ? $r('app.color.button_primary') : $r('app.color.background_secondary'))
      // 文字色与底色成对：选中是深绿，未选中是正文色，两种状态都清晰。
      .fontColor(this.selected ? $r('app.color.fw_on_accent') : $r('app.color.text_primary'))
      .width(this.fillWidth ? '100%' : undefined)
      .onClick((): void => { this.onTap(); })
  }
}

/**
 * 按钮语气。
 *
 * 与颜色资源的对应关系固定在这里，**调用方不再各自挑颜色** ——
 * 这正是「同一页面上按钮排布与配色花样过多」的根因。
 */
export enum FieldwatchButtonTone {
  /**
   * 实心强调。
   *
   * 底色是荧光绿（深色主题 `#3DFF9A`），**文字必须用 `fw_on_accent`（深绿）**：
   * 深绿配荧光绿对比度约 11:1。
   * 此前大量按钮只设底色不设文字色，ArkUI 就用默认白字 ——
   * 白字打在荧光绿上对比度只有约 1.4:1，也就是「根本看不清」。
   */
  PRIMARY = 0,
  /** 描边：透明底 + 描边 + 正文色。次级动作默认用它。 */
  OUTLINE = 1,
  /** 危险：红底 + 对应深/浅文字色。 */
  DANGER = 2,
  /** 提醒：琥珀底 + 对应深/浅文字色。 */
  WARN = 3
}

/**
 * 统一按钮。
 *
 * **尺寸只允许两档**（常规 44 / 紧凑 36），圆角固定 12 ——
 * 此前同类页面里 32/34/36/38/42/44/46/48 混用、圆角 10/12 混用，
 * 视觉上像是不同人拼出来的。
 *
 * 必须用 `@Component` 而不是 `@Builder`：`@Builder` 的按值参数不响应式，
 * 按钮的选中/禁用态不会更新（这个坑本项目已经踩过一次）。
 */
@Component
export struct FieldwatchButton {
  @Prop label: ResourceStr = '';
  @Prop tone: number = FieldwatchButtonTone.PRIMARY;
  /** 紧凑档：36 高、13 号字，用于卡片内并排的次级动作。 */
  @Prop compact: boolean = false;
  /** 是否占满一行。并排按钮应设为 false 并用 layoutWeight 分配。 */
  @Prop fillWidth: boolean = true;
  @Prop disabled: boolean = false;
  onTap: () => void = (): void => {};

  private bgColor(): ResourceColor {
    if (this.tone === FieldwatchButtonTone.PRIMARY) return $r('app.color.button_primary');
    if (this.tone === FieldwatchButtonTone.DANGER) return $r('app.color.button_warning');
    if (this.tone === FieldwatchButtonTone.WARN) return $r('app.color.button_secondary');
    return Color.Transparent;
  }
  /** 文字色与底色成对定义，不允许调用方单独覆盖，保证对比度不会被改坏。 */
  private fgColor(): ResourceColor {
    if (this.tone === FieldwatchButtonTone.PRIMARY) return $r('app.color.fw_on_accent');
    if (this.tone === FieldwatchButtonTone.DANGER) return $r('app.color.fw_on_danger');
    if (this.tone === FieldwatchButtonTone.WARN) return $r('app.color.fw_on_warning');
    return FieldwatchPaletteHolder.get().text;
  }
  private borderTone(): ResourceColor {
    return this.tone === FieldwatchButtonTone.OUTLINE
      ? FieldwatchPaletteHolder.get().outline : Color.Transparent;
  }

  build() {
    Button(this.label)
      .height(this.compact ? 36 : 44)
      .fontSize(this.compact ? 13 : 15)
      .borderRadius(12)
      .borderWidth(this.tone === FieldwatchButtonTone.OUTLINE ? 1 : 0)
      .backgroundColor(this.bgColor())
      .fontColor(this.fgColor())
      .borderColor(this.borderTone())
      .enabled(!this.disabled)
      .opacity(this.disabled ? 0.5 : 1)
      .width(this.fillWidth ? '100%' : undefined)
      .onClick((): void => { if (!this.disabled) this.onTap(); })
  }
}