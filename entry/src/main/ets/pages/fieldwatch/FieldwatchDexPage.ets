import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FieldwatchStoredObservation } from '../../fieldwatch/data/FieldwatchObservationRepository';
import { DexEntry, DexRarity, DexSummary, dexDisplayName } from '../../fieldwatch/domain/FieldwatchDex';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';

const DEX_UNDERLAY_HEIGHT: number = 168;

/**
 * 设备图鉴（P2-11）。
 *
 * 按建 fleet 维度聚合历史 signatureIds：点亮的显示彩色图标与名字，
 * 未点亮的显示剪影 + 「？？？」。点开一条接 `DeviceExplain` 的文案。
 *
 * **对账口径**：本页的「已见 N / 共 M」全部由 `buildDex` 从同一份特征库与
 * 同一份历史算出（见 `FieldwatchDex`），页面不做任何二次统计 ——
 * 否则「图鉴统计与历史数据对账一致」这条验收无从保证。
 */
@Component
export struct FieldwatchDexPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  @State private entries: DexEntry[] = [];
  @State private summary: DexSummary | undefined = undefined;
  @State private loading: boolean = true;
  /** 选中条目（点开显示详情）；undefined 表示未选。 */
  @State private selected: DexEntry | undefined = undefined;

  aboutToAppear(): void {
    void this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    const history: FieldwatchStoredObservation[] = await fieldwatchApplication.loadObservationHistory(2000);
    const entries: DexEntry[] = fieldwatchApplication.dexEntries(history);
    this.entries = entries;
    this.summary = fieldwatchApplication.dexSummary(entries);
    this.loading = false;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(DEX_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  private rarityColor(rarity: DexRarity): string {
    if (rarity === DexRarity.EPIC) return FieldwatchPaletteHolder.get().signalRed;
    if (rarity === DexRarity.RARE) return FieldwatchPaletteHolder.get().amber;
    if (rarity === DexRarity.UNCOMMON) return FieldwatchPaletteHolder.get().cyan;
    return FieldwatchPaletteHolder.get().accent;
  }

  private rarityKey(rarity: DexRarity): string {
    if (rarity === DexRarity.EPIC) return 'app.string.fieldwatch_dex_rarity_epic';
    if (rarity === DexRarity.RARE) return 'app.string.fieldwatch_dex_rarity_rare';
    if (rarity === DexRarity.UNCOMMON) return 'app.string.fieldwatch_dex_rarity_uncommon';
    return 'app.string.fieldwatch_dex_rarity_common';
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.withShell) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              DEX_UNDERLAY_HEIGHT)
          })
        }
        this.buildBody()
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_dex_title'),
      this.summaryLine(),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .hideTitleBar(!this.withShell)
    .onBackPressed((): boolean => {
      if (this.selected !== undefined) { this.selected = undefined; return true; }
      this.onClose();
      return true;
    })
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.loading) {
          Text($r('app.string.fieldwatch_dex_loading')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        } else if (this.selected !== undefined) {
          this.buildDetail(this.selected)
        } else {
          this.buildGrid()
        }
        // 页脚注：**必须写清卸载重装清零**（文档验收原文，与隐私口径一致）。
        Text($r('app.string.fieldwatch_dex_footnote')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
          .width('100%').padding({ top: 8 })
      }
      .width('100%').constraintSize({ maxWidth: 640 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 32 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  private summaryLine(): string {
    const summary: DexSummary | undefined = this.summary;
    if (summary === undefined) return '';
    const template: string = this.text('app.string.fieldwatch_dex_subtitle');
    return template.replace('%1', summary.seen.toString()).replace('%2', summary.total.toString());
  }

  @Builder
  private buildGrid() {
    Column({ space: 10 }) {
      if (this.summary !== undefined && (this.summary as DexSummary).newToday > 0) {
        Text(this.text('app.string.fieldwatch_dex_new_today').replace('%1', (this.summary as DexSummary).newToday.toString()))
          .fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
      }
      Grid() {
        ForEach(this.entries, (entry: DexEntry): void => {
          GridItem() { this.buildCell(entry) }
        }, (entry: DexEntry): string => entry.fleetId)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8).rowsGap(8)
      .width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 一格图鉴：点亮是彩色 + 名字，未点亮是剪影 + 「？？？」。 */
  @Builder
  private buildCell(entry: DexEntry) {
    Column({ space: 6 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right')).fontSize(22)
          .fontColor([entry.seen ? this.rarityColor(entry.rarity) : FieldwatchPaletteHolder.get().outline])
      }
      .width(52).height(52).borderRadius(16)
      .backgroundColor(entry.seen ? FieldwatchPaletteHolder.get().badgeBg : Color.Transparent)
      .borderWidth(1)
      .borderColor(entry.seen ? this.rarityColor(entry.rarity) : FieldwatchPaletteHolder.get().outline)
      Text(dexDisplayName(entry)).fontSize(12).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor(entry.seen ? FieldwatchPaletteHolder.get().text : FieldwatchPaletteHolder.get().textDim)
        .textAlign(TextAlign.Center)
      Text(this.text(this.rarityKey(entry.rarity))).fontSize(10)
        .fontColor(this.rarityColor(entry.rarity))
    }
    .width('100%').padding(8).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => { this.selected = entry; })
  }

  /** 详情：接 DeviceExplain 的文案（通过类标签与命中统计呈现）。 */
  @Builder
  private buildDetail(entry: DexEntry) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right')).fontSize(26)
          .fontColor([this.rarityColor(entry.rarity)])
        Text(dexDisplayName(entry)).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().headerText).layoutWeight(1)
      }.width('100%')
      Text(resolveResourceString(this.getUIContext().getHostContext(), signatureClassLabel(entry.category)))
        .fontSize(14).fontColor(FieldwatchPaletteHolder.get().text)
      Text(this.text(this.rarityKey(entry.rarity))).fontSize(13)
        .fontColor(this.rarityColor(entry.rarity))
      if (entry.seen) {
        Text(this.text('app.string.fieldwatch_dex_seen_times').replace('%1', entry.sightings.toString()))
          .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
        Text(this.text('app.string.fieldwatch_dex_last_seen').replace('%1', this.clockOf(entry.lastSeenAt)))
          .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      } else {
        Text($r('app.string.fieldwatch_dex_not_seen')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }.width('100%').padding(16).borderRadius(16).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 最近见到的时刻（本地时间 HH:mm）。空值返回占位。 */
  private clockOf(at: number): string {
    if (at <= 0) return '—';
    const date: Date = new Date(at);
    const hh: string = date.getHours().toString().padStart(2, '0');
    const mm: string = date.getMinutes().toString().padStart(2, '0');
    return hh + ':' + mm;
  }
}
