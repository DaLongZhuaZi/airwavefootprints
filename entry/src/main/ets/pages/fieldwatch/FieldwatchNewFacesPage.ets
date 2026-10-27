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
          ForEach(this.entries, (entry: NewFaceEntry): void => {
            this.buildRow(entry)
          }, (entry: NewFaceEntry): string => entry.deviceKey)
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
      if (entry.signatureName.length > 0) {
        Text(entry.signatureName).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      }
      // 整条可点进详情（P3-2 第 1 项：新面孔不能只列名字，要能看证据/首次出现/轨迹）。
      Row({ space: 6 }) {
        FieldwatchButton({
          label: $r('app.string.fieldwatch_newfaces_mine'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => {
            fieldwatchApplication.excludeNewFace(entry.deviceKey);
            void this.reload();
          }
        })
        FieldwatchButton({
          label: $r('app.string.fieldwatch_newfaces_detail'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => { this.onOpenDetail(entry.deviceKey); }
        })
      }.width('100%')
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }
}
