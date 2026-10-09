import { FieldwatchDeviceTypeIcon } from './FieldwatchDeviceTypeIcon';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';
import { RadioKind, SignatureClass } from '../domain/FieldwatchModels';

/**
 * 实时页里「一行一台设备」的统一外观。
 *
 * ## 为什么要有这个文件
 *
 * 强度、时间线、信号轨迹、分类四个视图原来各写各的行 ——
 * 图标 34/34/28、名称 17/16/15、右侧读数 17/15/14，都不一致，
 * 切视图时同一台设备看起来像换了个东西（实测反馈）。
 *
 * 统一靠「只有一处定义」来保证，而不是靠「记得改四处」——
 * 后者一定会随时间漂移。
 *
 * ## 尺寸体系
 *
 * 全部尺寸由 `FieldwatchRowMetrics` 一处给出，支持紧凑/标准两档；
 * 其它地方不要再写魔法数字。
 */
export class FieldwatchRowMetrics {
  public iconBox: number;
  public iconGlyph: number;
  public titleSize: number;
  public subtitleSize: number;
  public valueSize: number;
  public padding: number;
  public radius: number;
  public rowGap: number;
  constructor(iconBox: number, iconGlyph: number, titleSize: number, subtitleSize: number,
    valueSize: number, padding: number, radius: number, rowGap: number) {
    this.iconBox = iconBox; this.iconGlyph = iconGlyph;
    this.titleSize = titleSize; this.subtitleSize = subtitleSize;
    this.valueSize = valueSize; this.padding = padding;
    this.radius = radius; this.rowGap = rowGap;
  }
}

/** 标准档：信息量与点击面积平衡。 */
export function standardRowMetrics(): FieldwatchRowMetrics {
  return new FieldwatchRowMetrics(34, 18, 16, 11, 15, 12, 14, 10);
}

/** 紧凑档：一屏多看几台，适合设备密集的场合。 */
export function compactRowMetrics(): FieldwatchRowMetrics {
  return new FieldwatchRowMetrics(28, 15, 15, 10, 14, 9, 12, 8);
}

/** 按设置取行尺寸。`compact` 来自设置项 `listCompactRows`。 */
export function rowMetricsFor(compact: boolean): FieldwatchRowMetrics {
  return compact ? compactRowMetrics() : standardRowMetrics();
}

/**
 * 设备行的左侧：类型图标 + 名称 + 副标题。
 *
 * 四个视图共用；右侧读数各自不同（有的带折线、有的带趋势箭头），
 * 所以只统一左侧与整行的底色/圆角/内边距。
 */
@Component
export struct FieldwatchSignalRowLeading {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop kind: RadioKind = RadioKind.BLE;
  @Prop category: SignatureClass = SignatureClass.OTHER;
  @Prop tint: string = '';
  @Prop badge: string = '';
  @Prop iconBox: number = 34;
  @Prop iconGlyph: number = 18;
  @Prop titleSize: number = 16;
  @Prop subtitleSize: number = 11;
  @Prop rowGap: number = 10;

  build() {
    Row({ space: this.rowGap }) {
      Stack() {
        FieldwatchDeviceTypeIcon({
          kind: this.kind, category: this.category, tint: this.tint, glyphSize: this.iconGlyph
        })
      }
      .width(this.iconBox).height(this.iconBox).borderRadius(this.iconBox / 2)
      .backgroundColor(this.badge)
      Column({ space: 3 }) {
        Text(this.title).fontSize(this.titleSize).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1).layoutWeight(1)
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(this.subtitleSize)
            .fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%')
  }
}