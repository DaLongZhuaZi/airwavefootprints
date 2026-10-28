import { curves } from '@kit.ArkUI';
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
import { heroClassOf, ShareCardContent, ShareCardMaterial } from '../../fieldwatch/platform/FieldwatchShareCard';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { deviceClassSymbol } from '../../fieldwatch/ui/FieldwatchDeviceTypeIcon';
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
  /**
   * 入场动画状态（与特征详情页 `FieldwatchDeviceDetailPage` 完全一致）。
   *
   * 位移用 vp 而不是百分比：百分比会随容器宽度变化，横屏分栏收起时
   * 容器变全宽、位移量跟着放大，看起来像「被拉伸」。
   */
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  /** 是否正在退场，防重复触发。 */
  private leaving: boolean = false;

  onClose: () => void = (): void => {};
  /** 打开特征库里的这一条（由根页面压栈）。 */
  onOpenCatalog: (fleetId: string) => void = (fleetId: string): void => {};
  /** 空态「去扫描发现」：跳到安防扫描页（由根页面注入）。 */
  onGoScan: () => void = (): void => {};
  /** 去实时页并按该特征筛选（由根页面切换标签页）。 */
  onFindLive: (fleetId: string) => void = (fleetId: string): void => {};
  /** 网格数据源（LazyForEach 用）。 */
  private readonly dataSource: DexEntryDataSource = new DexEntryDataSource();
  @State private entries: DexEntry[] = [];
  @State private summary: DexSummary | undefined = undefined;
  @State private loading: boolean = true;
  /** 分类进度是否展开（默认折叠，避免把网格挤到屏幕外）。 */
  @State private progressExpanded: boolean = false;
  /** 搜索关键词（改版设计 6.1：611 个格子没有筛选等于没有）。 */
  @State private keyword: string = '';
  /** 筛选：0 全部 / 1 已点亮 / 2 未点亮。 */
  @State private filterMode: number = 0;
  /** 过滤后的条目数（用于空态判断）。 */
  @State private visibleCount: number = 0;
  /** 待弹的首次点亮（P3-3）。undefined = 不弹。 */
  @State private unlock: DexUnlock | undefined = undefined;
  /** 弹层是否正在分享（防重复点）。 */
  @State private sharing: boolean = false;
  /** 选中条目（点开显示详情）；undefined 表示未选。 */
  @State private selected: DexEntry | undefined = undefined;
  /** 详情 sheet 是否显示（改版设计 6.1：点格子进详情 sheet）。 */
  @State private showDetail: boolean = false;
  /** 点亮弹层的星星缩放（0.4 → 1.0，弹入感）。 */
  @State private unlockStarScale: number = 0.4;

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
    this.leaveThen((): void => { this.onClose(); });
  }

  /**
   * 退场后执行指定动作（而不是只会关闭）。
   *
   * 「去实时页找它」这类**带去向的按钮**必须走这里：
   * 先播完退场动画再跳转，否则页面「啪」地消失、目标页又没变化，
   * 用户看到的就是「点了没反应」（真机实测反馈）。
   */
  private leaveThen(action: () => void): void {
    if (this.leaving) return;
    this.leaving = true;
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => { action(); }
    }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  aboutToAppear(): void {
    // **必须延后一帧再播入场动画**：
    // 内容先以「右侧 40vp + 全透明」落位，下一帧再动到原位。
    // 直接在同帧调 animateTo 的话，首帧就已经是终态，用户看不到任何动画
    // （参照页 `FieldwatchDeviceDetailPage` 的注释与实现完全一致）。
    setTimeout((): void => { this.playEnter(); }, 0);
    void this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    const history: FieldwatchStoredObservation[] = await fieldwatchApplication.loadObservationHistory(2000);
    const entries: DexEntry[] = fieldwatchApplication.dexEntries(history);
    this.entries = entries;
    this.summary = fieldwatchApplication.dexSummary(entries);
    this.applyFilter();
    this.loading = false;
    // P3-3：只在**首次点亮**时出一条；已弹过、未点亮的都不会返回。
    // 首次运行会把现状全部标记为已弹，因此老用户升级不会涌出几十个弹层。
    const nextUnlock: DexUnlock | undefined = fieldwatchApplication.nextDexUnlock(entries);
    this.unlock = nextUnlock;
    if (nextUnlock !== undefined) this.playUnlockAnimation();
  }

  private text(key: string): string {
    // **空键直接兜底，不要走 `$r`** —— `$r('')` 本身就会刷一条运行时 E 日志。
    // 其余坏键靠「不把已解析文案当键喂进来」根治，不指望 catch 消日志。
    if (key.length === 0) return '';
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

  /** 已点亮总数（用于区分「筛选没命中」与「一条都没点亮」）。 */
  private seenTotal(): number {
    const summary: DexSummary | undefined = this.summary;
    return summary === undefined ? 0 : summary.seen;
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
          .padding({ left: 24, right: 24 })
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#99000000')
          // 弹层出现动画：缩放 + 淡入，250ms（与安防授权弹窗同一套）。
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
            .animation({ duration: 250, curve: Curve.FastOutSlowIn }))
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
    // 详情 sheet（改版设计 6.1）：从页内切换改为底部 sheet，保留网格上下文。
    .bindSheet($$this.showDetail, this.buildDetailSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true
    })
    .onBackPressed((): boolean => {
      // 详情 sheet 开着时，返回先关 sheet（一级一级退，符合直觉）。
      if (this.selected !== undefined) { this.selected = undefined; return true; }
      // **必须走 leaveThenClose，不能直接 onClose** —— 直接 pop 会让整页瞬间消失，
      // 横屏分栏时右栏从半宽突然拉伸到全宽，看起来像「闪一下」（用户反馈：
      // 设备图鉴缺少离场动画）。
      this.leaveThenClose();
      return true;
    })
    // 入场/退场自绘（与特征详情页一致）：整页含背景一起位移+淡入淡出。
    // **不能只给内层内容做动画** —— 分栏收起时右栏从 33% 拉伸到 100%，
    // 根节点的不透明背景仍在，会看到一整块实心空白面板在拉伸。
    .translate({ x: this.enterShift })
    .opacity(this.enterAlpha)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.loading) {
          Text($r('app.string.fieldwatch_dex_loading')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        } else if (false) {
          // 详情已改 sheet（见根节点 bindSheet），页内不再切换 ——
          // 否则 sheet 弹出时背后还会同时渲染一份详情，出现「双层详情」。
          this.buildDetail(this.selected as DexEntry)
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
      // 搜索 + 筛选（改版设计 6.1）。
      this.buildSearchBar()
      if (this.visibleCount === 0) {
        // 区分两种空：**筛选没命中** vs **一条都没点亮**。
        // 前者是「换个词」，后者要给动作（改版设计 1：空态给动作）。
        if (this.seenTotal() === 0) {
          Column({ space: 8 }) {
            Text(this.text('app.string.fieldwatch_dex_empty_guide')).fontSize(13)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
            FieldwatchButton({ label: $r('app.string.fieldwatch_dex_go_scan'),
              tone: FieldwatchButtonTone.PRIMARY, compact: true, fillWidth: false,
              onTap: (): void => { this.onGoScan(); } })
          }.width('100%').padding({ top: 20 }).alignItems(HorizontalAlign.Start)
        } else {
          Text(this.text('app.string.fieldwatch_dex_no_match')).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%').padding({ top: 20 })
        }
      }
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

  /** 搜索框 + 三档筛选芯片。 */
  @Builder
  private buildSearchBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
        TextInput({ placeholder: this.text('app.string.fieldwatch_dex_search'), text: this.keyword })
          .layoutWeight(1).backgroundColor(Color.Transparent)
          .fontColor(FieldwatchPaletteHolder.get().text)
          .placeholderColor(FieldwatchPaletteHolder.get().textDim)
          .onChange((value: string): void => {
            this.keyword = value;
            this.applyFilter();
          })
      }.width('100%').height(42).padding({ left: 12, right: 12 })
      .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
      Row({ space: 8 }) {
        this.buildFilterChip('app.string.fieldwatch_dex_filter_all', 0)
        this.buildFilterChip('app.string.fieldwatch_dex_filter_seen', 1)
        this.buildFilterChip('app.string.fieldwatch_dex_filter_unseen', 2)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFilterChip(labelKey: string, mode: number) {
    Text(this.text(labelKey)).fontSize(12)
      .fontColor(this.filterMode === mode ? FieldwatchPaletteHolder.get().accent
        : FieldwatchPaletteHolder.get().textDim)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .borderWidth(1)
      .borderColor(this.filterMode === mode ? FieldwatchPaletteHolder.get().accent
        : FieldwatchPaletteHolder.get().outline)
      .onClick((): void => {
        this.filterMode = mode;
        this.applyFilter();
      })
  }

  /**
   * 按关键词与筛选档位重算可见条目，并重置数据源。
   *
   * 过滤在**已算好的 entries 上做**，不重新查库 —— 稀有度/积分/等级都基于全集，
   * 过滤只影响网格显示什么，不影响统计口径。
   */
  private applyFilter(): void {
    const key: string = this.keyword.trim().toLowerCase();
    const out: DexEntry[] = [];
    for (let i: number = 0; i < this.entries.length; i += 1) {
      const entry: DexEntry = this.entries[i];
      if (this.filterMode === 1 && !entry.seen) continue;
      if (this.filterMode === 2 && entry.seen) continue;
      if (key.length > 0 && entry.name.toLowerCase().indexOf(key) < 0) continue;
      out.push(entry);
    }
    this.visibleCount = out.length;
    this.dataSource.reset(out);
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
          // 点亮过程动画：星星从 0.4 弹到 1.0，配 spring 曲线有「蹦出来」的手感。
          .scale({ x: this.unlockStarScale, y: this.unlockStarScale })
        Text($r('app.string.fieldwatch_dex_unlock_title')).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().headerText).textAlign(TextAlign.Center)
        Text((this.unlock as DexUnlock).name).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).textAlign(TextAlign.Center)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          // **直接当文案用，不要再过 text()**：categoryText 已经解析过，
          // 再 $r 一次会变成非法键，运行时刷 Invalid resource ID: 0 且这里渲染为空。
          Text((this.unlock as DexUnlock).categoryText).fontSize(12)
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
      // 同上：width 100% + 水平 margin 会溢出，边距交给父容器。
      .width('100%').padding(24).borderRadius(20)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 关闭弹层并记为已弹（下次不再弹同一条）。 */
  /**
   * 点亮过程动画：星星从 0.4 弹到 1.0。
   *
   * 先归零再推进 —— 连续点亮多台时，第二次也能看到同样的弹入效果。
   */
  private playUnlockAnimation(): void {
    this.unlockStarScale = 0.4;
    setTimeout((): void => {
      this.getUIContext().animateTo({
        duration: 420,
        curve: curves.springMotion(0.42, 0.82)
      }, (): void => {
        this.unlockStarScale = 1;
      });
    }, 32);
  }

  private closeUnlock(): void {
    const current: DexUnlock | undefined = this.unlock;
    if (current !== undefined) fieldwatchApplication.markDexUnlockAnnounced(current.fleetId);
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, (): void => {
      this.unlock = undefined;
    });
  }

  /**
   * 分享卡（P3-3 第 2 项）：**复用现有 ShareCard 能力**，不新增分享渠道。
   */
  /**
   * 图鉴卡的 trait：类别 · 点亮日期。
   *
   * `categoryText` 是**已解析文案**（不是资源键）；为空时按「其他设备」兜底，
   * 保证不会出现「 · 10-28」这种空段。
   */
  private dexTraitOf(current: DexUnlock, entry: DexEntry | undefined): string {
    const parts: string[] = [];
    // 类别一定有一段（兜底「其他设备」），不会出现「 · 日期」这种空段。
    parts.push(this.dexCategoryText(current.categoryText, entry));
    const date: string = this.dexUnlockDate(entry);
    if (date.length > 0) {
      // 日期前面必须带含义：模型里只有「最近一次见到」，所以写「最近出现」。
      parts.push(this.text('app.string.fieldwatch_share_trait_date').replace('%1', date));
    }
    return parts.join(' · ');
  }

  /**
   * 类别文案：真实中文类名 → 资源键解析值 → 「其他设备」。
   *
   * **绝不把裸英文类名（如 other / law-enforcement）输出给用户**：
   * `signatureClassLabel` 返回的就是已解析的中文类名，优先用它；
   * 它若为空或回退成枚举值本身，说明没有可用文案，直接兜底「其他设备」。
   */
  private dexCategoryText(categoryText: string, entry: DexEntry | undefined): string {
    if (entry !== undefined) {
      const real: string = signatureClassLabel(entry.category).trim();
      if (real.length > 0 && real !== entry.category) return real;
    }
    // `categoryText` 已经是解析好的文案，**不能再过 `text()`**（那会变成非法资源键）。
    const fromText: string = categoryText.trim();
    if (fromText.length > 0) return fromText;
    return this.text('app.string.fieldwatch_share_other_device');
  }

  /**
   * 点亮日期（MM-DD）。
   *
   * 数据模型只存了「最近一次点亮」（`lastSeenAt`），没有首次点亮时间；
   * 这里用最近点亮日期，与图鉴格子上的日期口径一致。
   */
  private dexUnlockDate(entry: DexEntry | undefined): string {
    if (entry === undefined || !(entry.lastSeenAt > 0)) return '';
    const date: Date = new Date(entry.lastSeenAt);
    return (date.getMonth() + 1).toString().padStart(2, '0') + '-'
      + date.getDate().toString().padStart(2, '0');
  }

  /** 按 fleetId 找图鉴条目（分享卡要拿它的类别与稀有度）。 */
  private entryOf(fleetId: string): DexEntry | undefined {
    for (let index: number = 0; index < this.entries.length; index += 1) {
      if (this.entries[index].fleetId === fleetId) return this.entries[index];
    }
    return undefined;
  }

  /** 稀有度 → 卡片材质（边框渐变与等级带颜色）。 */
  private materialOfRarity(rarity: DexRarity): ShareCardMaterial {
    if (rarity === DexRarity.EPIC) return ShareCardMaterial.GOLD;
    if (rarity === DexRarity.RARE) return ShareCardMaterial.PURPLE;
    if (rarity === DexRarity.UNCOMMON) return ShareCardMaterial.BLUE;
    return ShareCardMaterial.STEEL;
  }

  private async shareUnlock(): Promise<void> {
    const current: DexUnlock | undefined = this.unlock;
    if (current === undefined || this.sharing) return;
    this.sharing = true;
    const content: ShareCardContent = new ShareCardContent();
    const seen: number = this.summary === undefined ? 0 : (this.summary as DexSummary).seen;
    const total: number = this.summary === undefined ? 0 : (this.summary as DexSummary).total;
    // 收藏卡语法（文档 §1）：主体图 + 等级带（左 x/611、右 tier 词）+ 名称 + trait + 脚注 + 品牌。
    const entry: DexEntry | undefined = this.entryOf(current.fleetId);
    content.heroClass = entry === undefined ? 'other' : heroClassOf(entry.category);
    content.bandLeft = seen.toString() + ' / ' + total.toString();
    content.bandRight = this.text(current.rarityKey);
    content.name = current.name;
    // trait = 类别 · 点亮日期（等级与分数不再进 trait，它们属于弹层信息）。
    content.trait = this.dexTraitOf(current, entry);
    // **图鉴卡不设脚注**：等级带左侧已经是「x / 611」，脚注再重复一遍是废话。
    // 安防卡的强制句不受影响（在安防页那边设置）。
    content.footnote = '';
    content.brand = this.text('app.string.fieldwatch_share_brand');
    content.material = entry === undefined
      ? ShareCardMaterial.STEEL
      : this.materialOfRarity(entry.rarity);
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
    Column({ space: 4 }) {
      Stack() {
        // 改版设计 6.1：**按类别给专属图标**，不再全格子同一个电波符号；
        // 稀有度仍用颜色区分，两者叠加可读（图标说「是什么」，颜色说「多稀有」）。
        SymbolGlyph($r(deviceClassSymbol(entry.category))).fontSize(22)
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
      // 改版设计 6.1：格子再加两项信息 —— 出现次数与首次点亮时间。
      if (entry.seen) {
        Text('×' + entry.sightings.toString()).fontSize(9)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        Text(this.shortDate(entry.lastSeenAt)).fontSize(9)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
    }
    .width('100%').padding(8).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => {
      this.selected = entry;
      this.showDetail = true;
    })
  }

  /** 首次/最近点亮日期的短格式（月-日）；0 返回空串。 */
  private shortDate(at: number): string {
    if (!(at > 0)) return '';
    const date: Date = new Date(at);
    return (date.getMonth() + 1).toString() + '-' + date.getDate().toString();
  }

  /** 详情 sheet 的内容（改版设计 6.1）。 */
  @Builder
  private buildDetailSheet() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.selected !== undefined) {
          this.buildDetail(this.selected)
        }
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }.width('100%').scrollBar(BarState.Off)
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
        onTap: (): void => { this.leaveThen((): void => { this.onFindLive(entry.fleetId); }); } })
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
