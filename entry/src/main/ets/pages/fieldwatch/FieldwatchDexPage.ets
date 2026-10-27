import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FieldwatchStoredObservation } from '../../fieldwatch/data/FieldwatchObservationRepository';
import { DexEntry, DexRarity, DexSummary, dexDisplayName } from '../../fieldwatch/domain/FieldwatchDex';
import { SignatureClass } from '../../fieldwatch/domain/FieldwatchModels';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { DexEntryDataSource } from '../../fieldwatch/ui/FieldwatchDexDataSource';
import { DexBadge, DexLevelProgress } from '../../fieldwatch/domain/FieldwatchDexBadges';
import { DexUnlock } from '../../fieldwatch/domain/FieldwatchDexUnlock';
import { ShareCardContent } from '../../fieldwatch/platform/FieldwatchShareCard';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const DEX_UNDERLAY_HEIGHT: number = 168;

/** 分类进度行。 */
class DexCategoryRow {
  public key: string = '';
  public label: string = '';
  public total: number = 0;
  public seen: number = 0;
}

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
  /** 打开特征库里的这一条（由根页面压栈）。 */
  onOpenCatalog: (fleetId: string) => void = (fleetId: string): void => {};
  /** 去实时页并按该特征筛选（由根页面切换标签页）。 */
  onFindLive: (fleetId: string) => void = (fleetId: string): void => {};
  /** 网格数据源（LazyForEach 用）。 */
  private readonly dataSource: DexEntryDataSource = new DexEntryDataSource();
  @State private entries: DexEntry[] = [];
  @State private summary: DexSummary | undefined = undefined;
  @State private loading: boolean = true;
  /** 分类进度是否展开（默认折叠，避免把网格挤到屏幕外）。 */
  @State private progressExpanded: boolean = false;
  /** 待弹的首次点亮（P3-3）。undefined = 不弹。 */
  @State private unlock: DexUnlock | undefined = undefined;
  /** 弹层是否正在分享（防重复点）。 */
  @State private sharing: boolean = false;
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
    this.dataSource.reset(entries);
    this.summary = fieldwatchApplication.dexSummary(entries);
    this.loading = false;
    // P3-3：只在**首次点亮**时出一条；已弹过、未点亮的都不会返回。
    // 首次运行会把现状全部标记为已弹，因此老用户升级不会涌出几十个弹层。
    this.unlock = fieldwatchApplication.nextDexUnlock(entries);
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
        // P3-3 首次点亮弹层：盖在内容之上（Stack 后写的在上层）。
        // 用半透明遮罩包一层，让点击不透到下面的格子；点遮罩也算「知道了」。
        if (this.unlock !== undefined) {
          Column() {
            this.buildUnlockSheet()
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#99000000')
          .onClick((): void => { this.closeUnlock(); })
        }
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
      // 等级与积分（P3-2 图鉴玩法）。
      this.buildLevel()
      // 分类进度（P3-1：不要只有一个总数，每类点亮几 / 共几）。
      this.buildCategoryProgress()
      // 勋章（P3-2）。
      this.buildBadges()
      if (this.summary !== undefined && (this.summary as DexSummary).newToday > 0) {
        Text(this.text('app.string.fieldwatch_dex_new_today').replace('%1', (this.summary as DexSummary).newToday.toString()))
          .fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
      }
      // **LazyForEach + 固定高度的 Grid**（P3-1 性能修复）：
      // 原来用 ForEach 一次建 611 个格子，进页首帧就要实例化六百多个组件。
      // Grid 必须给高度，LazyForEach 才有视口可算；用 layoutWeight 撑满剩余空间。
      Grid() {
        LazyForEach(this.dataSource, (entry: DexEntry): void => {
          GridItem() { this.buildCell(entry) }
        }, (entry: DexEntry): string => entry.fleetId)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(8).rowsGap(8)
      .width('100%').height('100%').layoutWeight(1)
      .cachedCount(12)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 等级：观察者 → 探索者 → 猎手 → 大师，附积分与下一级进度。 */
  @Builder
  private buildLevel() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.medal')).fontSize(20)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text(this.levelTitle()).fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().headerText).layoutWeight(1)
        Text(this.text('app.string.fieldwatch_dex_score_line').replace('%1', this.score().toString()))
          .fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      }.width('100%')
      Text(this.levelHint()).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      if (!this.levelProgress().isMax()) {
        Progress({ value: this.score(), total: Math.max(1, this.score() + this.levelProgress().remain),
          type: ProgressType.Linear })
          .width('100%').height(4).color(FieldwatchPaletteHolder.get().accent)
      }
    }.width('100%').padding(12).borderRadius(12).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  private score(): number { return fieldwatchApplication.dexScoreOf(this.entries); }

  private levelProgress(): DexLevelProgress { return fieldwatchApplication.dexLevelOf(this.entries); }

  private levelTitle(): string {
    return this.text(this.levelProgress().current.titleKey);
  }

  private levelHint(): string {
    const progress: DexLevelProgress = this.levelProgress();
    if (progress.isMax()) return this.text('app.string.fieldwatch_dex_level_max');
    return this.text('app.string.fieldwatch_dex_level_next').replace('%1', progress.remain.toString());
  }

  /** 勋章：四枚，已获得的亮色、未获得灰色并给出达成条件。 */
  @Builder
  private buildBadges() {
    Column({ space: 6 }) {
      Text($r('app.string.fieldwatch_dex_badges_title')).fontSize(13)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      Row({ space: 8 }) {
        ForEach(this.badges(), (badge: DexBadge): void => {
          Column({ space: 3 }) {
            SymbolGlyph($r(badge.earned ? 'sys.symbol.medal_fill' : 'sys.symbol.medal'))
              .fontSize(20)
              .fontColor([badge.earned ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().outline])
            Text(this.text(badge.titleKey)).fontSize(10).maxLines(1)
              .fontColor(badge.earned ? FieldwatchPaletteHolder.get().text : FieldwatchPaletteHolder.get().textDim)
              .textAlign(TextAlign.Center)
            Text(this.text(badge.descKey)).fontSize(9).maxLines(2)
              .fontColor(FieldwatchPaletteHolder.get().textDim).textAlign(TextAlign.Center)
          }.layoutWeight(1).padding(6).borderRadius(10)
          .backgroundColor(badge.earned ? FieldwatchPaletteHolder.get().badgeBg : Color.Transparent)
        }, (badge: DexBadge): string => badge.id)
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private badges(): DexBadge[] { return fieldwatchApplication.dexBadgesOf(this.entries); }

  /**
   * 首次点亮弹层（P3-3 第 2 项）。
   *
   * 覆盖在页面之上而不是用系统 Dialog：需要展示内容（名称/类别/稀有度/积分变化）
   * 与两个动作（分享 / 知道了），系统 Dialog 的自定义能力不够。
   * **只在 `this.unlock !== undefined` 时出现**，关掉后立即置空，不会重复弹。
   */
  @Builder
  private buildUnlockSheet() {
    if (this.unlock !== undefined) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.star_fill')).fontSize(40)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text($r('app.string.fieldwatch_dex_unlock_title')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().headerText).textAlign(TextAlign.Center)
        Text((this.unlock as DexUnlock).name).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).textAlign(TextAlign.Center)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(this.text((this.unlock as DexUnlock).categoryKey)).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
          Text('·').fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(this.text((this.unlock as DexUnlock).rarityKey)).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().accent)
        }
        Text(this.text('app.string.fieldwatch_dex_unlock_score')
          .replace('%1', (this.unlock as DexUnlock).delta().toString()))
          .fontSize(14).fontColor(FieldwatchPaletteHolder.get().accent)
        // 跨级时额外说一句：只报积分不报升级会让人错过等级变化。
        if ((this.unlock as DexUnlock).leveledUp()) {
          Text(this.text('app.string.fieldwatch_dex_unlock_levelup')
            .replace('%1', this.text((this.unlock as DexUnlock).levelAfterKey)))
            .fontSize(13).fontColor(FieldwatchPaletteHolder.get().headerText)
        }
        FieldwatchButton({ label: $r('app.string.fieldwatch_dex_unlock_share'),
          tone: FieldwatchButtonTone.PRIMARY, disabled: this.sharing,
          onTap: (): void => { void this.shareUnlock(); } })
        FieldwatchButton({ label: $r('app.string.fieldwatch_dex_unlock_close'),
          tone: FieldwatchButtonTone.OUTLINE, onTap: (): void => { this.closeUnlock(); } })
      }
      .width('100%').padding(24).borderRadius(20).margin({ left: 24, right: 24 })
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 关闭弹层并记为已弹（下次不再弹同一条）。 */
  private closeUnlock(): void {
    const current: DexUnlock | undefined = this.unlock;
    if (current !== undefined) fieldwatchApplication.markDexUnlockAnnounced(current.fleetId);
    this.unlock = undefined;
  }

  /**
   * 分享卡（P3-3 第 2 项）：**复用现有 ShareCard 能力**，不新增分享渠道。
   */
  private async shareUnlock(): Promise<void> {
    const current: DexUnlock | undefined = this.unlock;
    if (current === undefined || this.sharing) return;
    this.sharing = true;
    const content: ShareCardContent = new ShareCardContent();
    content.title = this.text('app.string.fieldwatch_dex_unlock_share_title');
    content.headline = this.text('app.string.fieldwatch_dex_unlock_share_headline')
      .replace('%1', current.name);
    const lines: string[] = [];
    lines.push(this.text('app.string.fieldwatch_dex_level_line')
      .replace('%1', this.text(current.levelAfterKey))
      .replace('%2', current.scoreAfter.toString()));
    // 分享卡用 extraLines 承载附加行（ShareCardContent 没有 lines 字段）。
    content.extraLines = lines;
    content.footnote = this.text('app.string.fieldwatch_dex_subtitle')
      .replace('%1', (this.summary === undefined ? 0 : (this.summary as DexSummary).seen).toString())
      .replace('%2', (this.summary === undefined ? 0 : (this.summary as DexSummary).total).toString());
    const ok: boolean = await fieldwatchApplication.shareSecurityCard(content);
    this.sharing = false;
    if (ok) this.closeUnlock();
  }

  /**
   * 分类进度：每类「点亮 / 共几」。
   *
   * 只列**有点亮或有条目**的类别，避免几十个空类别把首屏占满。
   * 进度条用宽度百分比表达，不用颜色区分（色弱可读）。
   */
  @Builder
  private buildCategoryProgress() {
    Column({ space: 6 }) {
      // **默认折叠**：真机上 20 行分类把图鉴网格挤到了屏幕之外，
      // 而网格才是这个页面的主体。默认只显示一行摘要，展开才看全部分类。
      Row({ space: 6 }) {
        Text($r('app.string.fieldwatch_dex_class_progress')).fontSize(13)
          .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
        Text(this.progressSummary()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
        SymbolGlyph($r(this.progressExpanded ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
          .fontSize(13).fontColor([FieldwatchPaletteHolder.get().textDim])
      }.width('100%')
      .onClick((): void => { this.progressExpanded = !this.progressExpanded; })
      // 折叠时只显示前 3 类（已点亮最多的那几类），展开才全列。
      ForEach(this.visibleCategoryRows(), (row: DexCategoryRow): void => {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(row.label).fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
            Text(row.seen.toString() + ' / ' + row.total.toString()).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().accent)
          }.width('100%')
          Progress({ value: row.seen, total: Math.max(1, row.total), type: ProgressType.Linear })
            .width('100%').height(4).color(FieldwatchPaletteHolder.get().accent)
        }.width('100%')
      }, (row: DexCategoryRow): string => row.key)
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4 })
  }

  /** 折叠态的摘要：已点亮类别数 / 总类别数。 */
  private progressSummary(): string {
    const rows: DexCategoryRow[] = this.categoryRows();
    let touched: number = 0;
    rows.forEach((row: DexCategoryRow): void => { if (row.seen > 0) touched += 1; });
    return touched.toString() + ' / ' + rows.length.toString();
  }

  /** 实际渲染的分类行：折叠时只给前 3（已按点亮数排序）。 */
  private visibleCategoryRows(): DexCategoryRow[] {
    const rows: DexCategoryRow[] = this.categoryRows();
    if (this.progressExpanded) return rows;
    return rows.slice(0, 3);
  }

  /** 分类进度行。 */
  private categoryRows(): DexCategoryRow[] {
    const rows: DexCategoryRow[] = [];
    const order: string[] = [];
    const totals: Map<string, number> = new Map<string, number>();
    const seens: Map<string, number> = new Map<string, number>();
    this.entries.forEach((entry: DexEntry): void => {
      const key: string = String(entry.category);
      if (order.indexOf(key) < 0) order.push(key);
      const total: number | undefined = totals.get(key);
      totals.set(key, total === undefined ? 1 : total + 1);
      if (entry.seen) {
        const seen: number | undefined = seens.get(key);
        seens.set(key, seen === undefined ? 1 : seen + 1);
      }
    });
    order.forEach((key: string): void => {
      const total: number = totals.get(key) === undefined ? 0 : totals.get(key) as number;
      const seen: number = seens.get(key) === undefined ? 0 : seens.get(key) as number;
      // 完全没点亮且条目很少的类别不列（避免首屏被空类别占满）。
      if (seen === 0 && total < 3) return;
      const row: DexCategoryRow = new DexCategoryRow();
      row.key = key;
      row.label = resolveResourceString(this.getUIContext().getHostContext(), signatureClassLabel(key as SignatureClass));
      row.total = total;
      row.seen = seen;
      rows.push(row);
    });
    rows.sort((a: DexCategoryRow, b: DexCategoryRow): number => b.seen - a.seen);
    return rows;
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
      // 稀有度口径说明：避免用户把「库内稀有」误解成「遇见概率低」。
      Text($r('app.string.fieldwatch_dex_rarity_note')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      // 两处跳转（文档要求：详情页接通「特征库详情」与「去实时页找它」）。
      if (entry.seen) {
        FieldwatchButton({ label: $r('app.string.fieldwatch_dex_open_catalog'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true,
          onTap: (): void => { this.onOpenCatalog(entry.fleetId); } })
      }
      FieldwatchButton({ label: $r('app.string.fieldwatch_dex_find_live'),
        tone: FieldwatchButtonTone.OUTLINE, compact: true,
        onTap: (): void => { this.onFindLive(entry.fleetId); } })
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
