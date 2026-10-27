import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { NewFaceEntry } from '../../fieldwatch/domain/FieldwatchNewFaces';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const FACES_UNDERLAY_HEIGHT: number = 168;

/**
 * 新面孔清单（P2-14）。
 *
 * 列出「从未见过 + 信号较强 + 持续出现」的设备；每条都可以一键「这是我家的」移出。
 * 家庭场景的基线对比由用户手动开启（文档明确不做地理围栏自动判定）。
 */
/** 新面孔分组（今日 / 本周）。 */
class NewFaceGroup {
  public titleKey: string = '';
  public items: NewFaceEntry[] = [];
  constructor(titleKey: string = '') { this.titleKey = titleKey; }
}

@Component
export struct FieldwatchNewFacesPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  /** 打开该设备的详情页（P3-2：每条新面孔都要能点进去看证据）。 */
  onOpenDetail: (deviceKey: string) => void = (deviceKey: string): void => {};
  @State private entries: NewFaceEntry[] = [];
  @State private loading: boolean = true;
  @State private compareOn: boolean = false;

  aboutToAppear(): void {
    this.compareOn = fieldwatchApplication.baselineCompareEnabled();
    void this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.entries = await fieldwatchApplication.newFaces();
    this.loading = false;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(FACES_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.withShell) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              FACES_UNDERLAY_HEIGHT)
          })
        }
        this.buildBody()
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_newfaces_title'),
      $r('app.string.fieldwatch_newfaces_subtitle'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .hideTitleBar(!this.withShell)
    .onBackPressed((): boolean => { this.onClose(); return true; })
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 12 }) {
        this.buildToggle()
        if (this.loading) {
          Text($r('app.string.fieldwatch_newfaces_loading')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        } else if (this.entries.length === 0) {
          Text($r('app.string.fieldwatch_newfaces_empty')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
          // 空状态给动作（文档第 1 项「通用」要求）：不开对比开关就没有基线，
          // 而空清单最常见的原因正是开关没开 —— 直接把开关摆出来。
          if (!this.compareOn) {
            FieldwatchButton({ label: $r('app.string.fieldwatch_newfaces_compare'),
              tone: FieldwatchButtonTone.OUTLINE,
              onTap: (): void => { this.enableCompare(); } })
          }
        } else {
          // 改版设计 6.2：按今日 / 本周分组，今日组置顶。
          ForEach(this.groupedRows(), (group: NewFaceGroup): void => {
            Text(this.text(group.titleKey)).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
              .padding({ top: 6, bottom: 2 })
            ForEach(group.items, (entry: NewFaceEntry): void => {
              this.buildRow(entry)
            }, (entry: NewFaceEntry): string => entry.deviceKey)
          }, (group: NewFaceGroup): string => group.titleKey)
        }
      }
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  /** 打开对比基线（空状态的动作按钮用，与 Toggle 同一条路径）。 */
  private enableCompare(): void {
    this.compareOn = true;
    fieldwatchApplication.setBaselineCompare(true);
    void this.reload();
  }

  /** 手动基线开关：**不做自动判定**（文档明确要求）。 */
  @Builder
  private buildToggle() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.fieldwatch_newfaces_compare')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.compareOn })
          .onChange((value: boolean): void => {
            this.compareOn = value;
            fieldwatchApplication.setBaselineCompare(value);
            void this.reload();
          })
      }.width('100%')
      Text($r('app.string.fieldwatch_newfaces_compare_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  @Builder
  /**
   * 一条新面孔（改版设计 6.2）：加首次出现时间、信号强度、风险提示、拉黑动作。
   *
   * 原来一行只有「名称 + 出现次数 + 特征名」，用户没法判断这台值不值得处理。
   */
  private buildRow(entry: NewFaceEntry) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.dot_radiowaves')).fontSize(18)
          .fontColor([FieldwatchPaletteHolder.get().warn])
        Text(entry.name.length > 0 ? entry.name : this.text('app.string.fieldwatch_find_unnamed'))
          .fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.hits.toString() + '×').fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      // 改版设计 6.2：首次出现时间 + 信号强度 + 风险提示（一行说清）。
      Text(this.rowMeta(entry)).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%').maxLines(2)
      if (entry.signatureName.length > 0) {
        Text(entry.signatureName).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      }
      // 行动作：查看详情 / 这是我家的 / 拉黑。
      Row({ space: 6 }) {
        FieldwatchButton({
          label: $r('app.string.fieldwatch_newfaces_detail'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => { this.onOpenDetail(entry.deviceKey); }
        })
        FieldwatchButton({
          label: $r('app.string.fieldwatch_newfaces_mine'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => {
            fieldwatchApplication.excludeNewFace(entry.deviceKey);
            void this.reload();
          }
        })
        FieldwatchButton({
          label: $r('app.string.fieldwatch_newfaces_block'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => {
            // 拉黑：与「这是我家的」同一套排除机制，只是语义不同（不再出现在新面孔里）。
            fieldwatchApplication.excludeNewFace(entry.deviceKey);
            void this.reload();
          }
        })
      }.width('100%')
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /**
   * 按今日 / 本周分组（改版设计 6.2）。
   *
   * 判据用 `firstSeen`：今天首次出现的进「今日」，其余进「本周」。
   * 空组不显示，避免出现一个只有标题的空段。
   */
  private groupedRows(): NewFaceGroup[] {
    const today: Date = new Date();
    const startOfToday: number = new Date(today.getFullYear(), today.getMonth(),
      today.getDate()).getTime();
    const todayGroup: NewFaceGroup = new NewFaceGroup('app.string.fieldwatch_newfaces_group_today');
    const weekGroup: NewFaceGroup = new NewFaceGroup('app.string.fieldwatch_newfaces_group_week');
    this.entries.forEach((entry: NewFaceEntry): void => {
      if (entry.firstSeen >= startOfToday) todayGroup.items.push(entry);
      else weekGroup.items.push(entry);
    });
    const out: NewFaceGroup[] = [];
    if (todayGroup.items.length > 0) out.push(todayGroup);
    if (weekGroup.items.length > 0) out.push(weekGroup);
    return out;
  }

  /** 一行的次要信息：首次出现 · 信号 · 风险提示。 */
  private rowMeta(entry: NewFaceEntry): string {
    const parts: string[] = [];
    if (entry.firstSeen > 0) {
      const date: Date = new Date(entry.firstSeen);
      const hh: string = date.getHours().toString().padStart(2, '0');
      const mm: string = date.getMinutes().toString().padStart(2, '0');
      parts.push((date.getMonth() + 1).toString() + '-' + date.getDate().toString() + ' ' + hh + ':' + mm);
    }
    if (entry.rssi < 0) parts.push(entry.rssi.toString() + ' dBm');
    // 风险提示：用「值得留意」而不是「危险」定性（沿用三档口径的措辞克制）。
    if (entry.hits >= 3) parts.push(this.text('app.string.fieldwatch_newfaces_worth_note'));
    return parts.join(' · ');
  }

}
