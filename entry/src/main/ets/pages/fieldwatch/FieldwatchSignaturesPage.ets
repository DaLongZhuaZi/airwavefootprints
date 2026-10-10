import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { logger, NGFHdsTitleBarOptionsFactory, NGFMaterialSheetOptions, ngfVisualEffectsFacade, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { SignatureClass, foldedSignatureClass, visibleSignatureClasses } from '../../fieldwatch/domain/FieldwatchModels';
import { SignatureFleet, SignatureRule } from '../../fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { FieldwatchSignatureDetail } from '../../fieldwatch/ui/FieldwatchSignatureDetail';
import { SignatureImportResult, SignaturePackError } from '../../fieldwatch/domain/signatures/FieldwatchSignatureCatalog';
import { FieldwatchCatalogImportOutcome } from '../../fieldwatch/data/FieldwatchCatalogRepository';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { SignatureFleetDataSource } from '../../fieldwatch/ui/FieldwatchFleetDataSource';
import { SignatureSortMode, sortSignatureFleets } from '../../fieldwatch/ui/FieldwatchUiState';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone, FieldwatchSegmentedChip } from '../../fieldwatch/ui/FieldwatchButton';


@Component
export struct FieldwatchSignaturesPage {
  /** 作为底部标签内嵌渲染时置 true：跳过 HdsNavDestination 外壳。 */
  embedded: boolean = false;
  /**
   * 是否用两列排布。
   *
   * 横屏且**右栏没开**时为 true：平板横屏宽度足够，单列会留出大片空白。
   * 右栏一开（Split）可用宽度只剩三分之一，必须回到单列 ——
   * 否则每列窄到放不下名称。
   *
   * 用 `lanes` 而不是手写两列：`List` 的 `lanes` 会**按可视区自动分配行**，
   * 滚动、回收、间距都由它处理；手写 Row 包两份 List 反而会各滚各的。
   */
  twoColumn: boolean = false;
  /**
   * 是否横屏。
   *
   * 横屏下详情**不能走底部 sheet**：Navigation 在无子页面时是 Stack 模式，
   * 整页占满窗口，sheet 会横跨两栏。改为压栈到右侧分栏，与设备详情同一套做法。
   */
  landscape: boolean = false;
  onEditFleet: (fleetId: string, deviceKey: string) => void = (): void => {};
  /** 横屏下把详情压进右侧分栏（由根页面实现）。 */
  onOpenDetail: (fleetId: string) => void = (fleetId: string): void => {};
  /**
   * 打开关注列表（横屏进右栏，竖屏整页）。
   *
   * **故意不给默认值**：默认空函数会把点击静默吃掉，
   * 表现为「这个按钮怎么点都没反应」而且**没有任何日志**。
   * 本文件里 `onEditFleet` 已经因此踩过一次（见 FieldwatchPage 的注释），
   * 关注列表又踩了第二次（横屏布局那个调用点漏传）。
   * 去掉默认值后，漏传是**编译错误**，不会再漏到运行时。
   */
  onOpenWatchlist: () => void = (): void => {
    // ArkTS 要求 struct 成员必须有初始值，所以去不掉默认值 ——
    // 那就让它**吵**：漏传时打 error 日志，而不是静默吃掉点击。
    // error 级默认就会进 hilog，不需要把日志等级调低也能看到。
    logger.error('FieldwatchSignaturesPage', 'onOpenWatchlist 未接线：这次点击被丢弃');
  };
  @State private query: string = '';
  @State private category: SignatureClass | undefined = undefined;
  @State private categoryIndex: number = -1;
  @State private version: number = 0;
  @State private total: number = 0;
  @State private notice: string = '';
  @State private detailId: string = '';
  /** 特征库列表的数据源；LazyForEach 依赖它做按需构建。 */
  private fleetSource: SignatureFleetDataSource = new SignatureFleetDataSource();
  @State private sheetOpen: boolean = false;
  @State private tick: number = 0;
  /** 外层转发的关注状态变化计数；变化即重建列表（横屏分栏时列表同屏可见）。 */
  @Prop @Watch('onFollowTick') followTick: number = 0;
  /**
   * 本页当前是否可见；不可见时不做任何刷新（`Tabs` 会让页面常驻）。
   *
   * **不能叫 `visible`**：本组件已有一个同名的 `visible()` 过滤方法，会撞名（实测编译失败）。
   */
  @Prop pageVisible: boolean = true;
  private refreshTimer: number = -1;

  onFollowTick(): void { this.refresh(); }
  @State private sortMode: SignatureSortMode = SignatureSortMode.NAME;

  /**
   * **必须走 `ensureCatalogLoaded`，不能只 `refresh()`。**
   *
   * 内置目录是在应用构造时异步加载的。若本页在它完成之前出现
   * （启动即在本页、或启动后很快切过来），`refresh()` 读到的是空目录，
   * 而且**之后没有任何东西再刷新** —— 页面就永远停在「0 / 0、没有匹配的签名」。
   *
   * 实时页早就用了这个模式（`FieldwatchPage` 里 `ensureCatalogLoaded().then(refreshView)`），
   * 本页漏了 —— 与「同一件事两处各写一遍、改一处漏一处」是同一类问题。
   */
  aboutToAppear(): void {
    this.refresh();
    void fieldwatchApplication.ensureCatalogLoaded().then((): void => { this.refresh(); });
    // 本页的行内内容（关注状态、命中次数）都是运行期会变的，
    // 靠 `ensureCatalogLoaded` 那种一次性刷新覆盖不到。
    //
    // 只在**可见且前台**时刷：`Tabs` 会让页面常驻，
    // 不可见时每秒重算 240 条的命中次数纯属白烧电。
    this.refreshTimer = setInterval((): void => {
      if (!this.pageVisible || !fieldwatchApplication.isAppForeground()) return;
      this.refresh();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer < 0) return;
    clearInterval(this.refreshTimer);
    this.refreshTimer = -1;
  }

  private refresh(): void {
    const state = fieldwatchApplication.getState();
    this.version = state.catalogVersion;
    // 计数与列表都跳过墓碑（已删除的内置行仍留在目录里，见 removeFleet）。
    this.total = fieldwatchApplication.visibleSignatures().length;
    // 数据源必须跟着重建：LazyForEach 只从它取数，
    // 不重载的话搜索/筛选/启用停用都不会反映到列表上。
    this.fleetSource.reload(this.visible());
    this.tick += 1;
  }

  private fleets(): SignatureFleet[] { return fieldwatchApplication.visibleSignatures(); }

  private visible(): SignatureFleet[] {
    const needle: string = this.query.trim().toLowerCase();
    const result: SignatureFleet[] = [];
    this.fleets().forEach((fleet: SignatureFleet): void => {
      if (this.category !== undefined && foldedSignatureClass(fleet.category) !== this.category) return;
      if (needle.length > 0) {
        const inName: boolean = fleet.name.toLowerCase().indexOf(needle) >= 0;
        const inRules: boolean = fleet.rules.some((rule: SignatureRule): boolean => (rule.text + ' ' + rule.dataPrefixHex).toLowerCase().indexOf(needle) >= 0);
        if (!inName && !inRules) return;
      }
      result.push(fleet);
    });
    return sortSignatureFleets(result, this.sortMode);
  }

  private detailFleet(): SignatureFleet | undefined {
    return this.fleets().find((fleet: SignatureFleet): boolean => fleet.id === this.detailId);
  }

  private hitsText(count: number): string {
    const template: string = resolveResourceString(this.getUIContext().getHostContext(), $r('app.string.fieldwatch_signatures_hits'));
    return template.replace('%s', count.toString());
  }

  private noticeText(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private sheetOptions(): NGFMaterialSheetOptions {
    const options: NGFMaterialSheetOptions = new NGFMaterialSheetOptions(ngfVisualEffectsFacade.buildSystemMaterialForSheet(), ngfVisualEffectsFacade.shouldUseSystemMaterialSurface());
    options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
    return options;
  }

  /** 表头：标题 / 说明 / 版本 / 搜索 / 类别 / 工具条。**始终单列、横跨整宽。** */
  @Builder
  private buildHeader() {
    Column({ space: 12 }) {
      Text($r('app.string.fieldwatch_signatures_title')).fontSize(26).fontWeight(FontWeight.Bold)
      Text($r('app.string.fieldwatch_signatures_description')).fontSize(13).fontColor($r('app.color.text_secondary'))
      // 「目录版本 / 签名总数」原先在这里占一整行，但它属于**元信息**，
      // 和标题、搜索框并列时会打断「标题 -> 描述 -> 搜索」的阅读顺序。
      // 移到下方统计行的中央（见 `buildToolbar`），与「显示 N / N」同行。
      TextInput({ placeholder: $r('app.string.fieldwatch_signatures_search') }).height(44)
        .onChange((value: string): void => { this.query = value; })
      this.buildCategoryChips()
      this.buildToolbar()
      if (this.notice.length > 0) Text(this.notice).fontSize(13).fontColor(FieldwatchPaletteHolder.get().warn)
      Text($r('app.string.fieldwatch_signatures_offline')).fontSize(12).fontColor($r('app.color.text_secondary'))
      if (this.visible().length === 0) Text($r('app.string.fieldwatch_signatures_empty')).fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
  }

  @Builder
  private buildBody() {
      Column() {
        // List + LazyForEach：244 条只构建可视区内的行。
        // 原实现是 Scroll + ForEach，一次性构建全部行，首屏开销与滚动掉帧都很明显。
        // **`space` 必须给**：不给的话行与行严丝合缝贴在一起，
        // 一整列卡片看起来像一块整板，分不出条数（实测反馈）。
        // **表头必须在 `List` 外面。**
        //
        // 它原本是 `List` 的第一个 `ListItem` —— 一旦开了两列，
        // `lanes` 会把表头当成普通一项塞进**左列**，
        // 于是标题、搜索框、类别芯片、工具条全挤在左半边（实测反馈「最诡异」）。
        //
        // 表头是「页面级」信息，不属于列表项；移出去后天然横跨整宽，
        // 列表照旧可以按需分两列。
        this.buildHeader()
        // 只构建可视区内的行；数据源在 refresh() 里整体重载。
        List({ space: 8 }) {
          LazyForEach(this.fleetSource, (fleet: SignatureFleet): void => {
            ListItem() { this.buildRow(fleet) }.width('100%')
          },
          /**
           * **key 必须包含所有「运行期会变、且行内会渲染」的状态。**
           *
           * LazyForEach 按 key 缓存行：key 不变就**复用旧行、不重建**。
           * 之前 key 只有 `id-enabled`，于是「已关注」标记与命中次数都永远停在
           * 首次构建那一刻 —— 表现就是「不改 key 就得重载页面才刷新」（实测反馈）。
           *
           * 把命中次数也放进来是**有意的**：它每秒都可能变，
           * 而 key 变化恰好只在「这一行真的要重画」时发生，比无差别重建省得多。
           */
          (fleet: SignatureFleet): string => fleet.id + '-' + fleet.enabled.toString()
            + '-' + (fieldwatchApplication.isSignatureWatched(fleet.id) ? '1' : '0')
            + '-' + fieldwatchApplication.countMatches(fleet.id).toString())
          ListItem().height(32)
        }
        .layoutWeight(1)
        .width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        .lanes(this.twoColumn ? 2 : 1, 8)
      }
      .width('100%').height('100%')
  }

  build() {
    if (this.embedded) {
      // 内嵌（底部标签）模式同样要挂详情面板：
      // 之前只有 HdsNavDestination 分支挂了 bindSheet，导致标签页里点签名行没有任何反应。
      Column() { this.buildBody() }
        .width('100%').height('100%')
        .bindSheet($$this.sheetOpen, this.buildDetailSheet(), this.sheetOptions())
    } else {
      HdsNavDestination() { this.buildBody() }
        .titleBar(NGFHdsTitleBarOptionsFactory.build(
          $r('app.string.fieldwatch_signatures_title'),
          $r('app.string.fieldwatch_signatures_description'),
          FieldwatchPaletteHolder.get().night,
          hdsMaterial.MaterialLevel.GENTLE,
          true,
          false
        ))
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
        .bindSheet($$this.sheetOpen, this.buildDetailSheet(), this.sheetOptions())
    }
  }

  @Builder
  private buildCategoryChips() {
    Scroll() {
      Row({ space: 8 }) {
        FieldwatchSegmentedChip({ label: $r('app.string.fieldwatch_signatures_category_all'), selected: this.categoryIndex < 0,
          onTap: (): void => { this.categoryIndex = -1; this.category = undefined; } })
        ForEach(visibleSignatureClasses(), (item: SignatureClass): void => {
          FieldwatchSegmentedChip({ label: signatureClassLabel(item),
            selected: foldedSignatureClass(this.category === undefined ? SignatureClass.OTHER : this.category) === item && this.categoryIndex >= 0,
            onTap: (): void => { this.category = item; this.categoryIndex = visibleSignatureClasses().indexOf(item); } })
        }, (item: SignatureClass): string => item)
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%')
  }

  /** 当前排序的可读标签（明确写成「排序：」以免被当成第二种筛选）。 */
  private sortLabelText(): string {
    const prefix: string = this.noticeText('app.string.fieldwatch_signatures_sort_prefix');
    const name: string = this.noticeText(this.sortMode === SignatureSortMode.NAME
      ? 'app.string.fieldwatch_signatures_sort_name'
      : 'app.string.fieldwatch_signatures_sort_class');
    return prefix + name;
  }
  /** 「显示 M / 共 N 条」——用户一眼知道筛选是否生效。 */
  private statsText(): string {
    const prefix: string = this.noticeText('app.string.fieldwatch_signatures_stats');
    return prefix + ' ' + this.visible().length.toString() + ' / ' + this.total.toString();
  }

  /**
   * 目录元信息：版本与签名总数。
   *
   * 单独成方法而不是内联拼接：它在表头被移走后换了位置，
   * 文案格式只应有一处定义，免得两处漂移。
   */
  private catalogMetaText(): string {
    return this.noticeText('app.string.fieldwatch_signatures_version') + ': ' + this.version.toString()
      + ' · ' + this.noticeText('app.string.fieldwatch_signatures_total') + ': ' + this.total.toString();
  }

  /** 顶部只保留两类控件：主操作（新建）+ 元信息（条数 / 排序 / 更多）。 */
  @Builder private buildToolbar() {
    Row({ space: 8 }) {
      FieldwatchButton({ label: $r('app.string.fieldwatch_signatures_new'), tone: FieldwatchButtonTone.PRIMARY,
        fillWidth: false, onTap: (): void => { this.onEditFleet('', ''); } }).layoutWeight(1)
      // 关注列表入口。放在这一行而不是「更多」菜单里：
      // 卡片点击会直达该页，用户需要在同一处也能自己找得到。
      FieldwatchButton({ label: $r('app.string.fieldwatch_watchlist_title'), tone: FieldwatchButtonTone.OUTLINE,
        fillWidth: false, onTap: (): void => { this.onOpenWatchlist(); } }).layoutWeight(1)
      Button($r('app.string.fieldwatch_signatures_more')).height(44).width(96)
        .backgroundColor($r('app.color.background_secondary'))
        .bindMenu(this.buildMoreMenu())
    }.width('100%')
    // 统计行：左边「显示 N / N」，**中间元信息**，右边排序按钮。
    //
    // 用 `Blank()` 把中间项夹在正中：两侧都留弹性空间，
    // 中间那一项才会落在行中央，而不是被左边那串数字挤偏。
    Row({ space: 8 }) {
      Text(this.statsText()).fontSize(12).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(this.catalogMetaText()).fontSize(12).fontColor($r('app.color.text_secondary'))
      Blank()
      Button(this.sortLabelText()).height(36).fontSize(13)
        .backgroundColor($r('app.color.background_secondary'))
        .onClick((): void => {
          this.sortMode = this.sortMode === SignatureSortMode.NAME ? SignatureSortMode.CLASS : SignatureSortMode.NAME;
        })
    }.width('100%')
  }

  /** 维护类操作全部收进「更多」，避免和筛选控件抢注意力。 */
  @Builder private buildMoreMenu() {
    Column() {
      this.buildMenuItem($r('app.string.fieldwatch_signatures_seed_watch'), (): void => {
        const added: number = fieldwatchApplication.seedBuiltInWatchTargets();
        const template: string = added > 0
          ? this.noticeText('app.string.fieldwatch_signatures_seed_done')
          : this.noticeText('app.string.fieldwatch_signatures_seed_none');
        this.notice = added > 0 ? template.replace('%s', added.toString()) : template;
      })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_share'), (): void => { fieldwatchApplication.shareCatalogSummary(); })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_export_file'), (): void => { void this.runExportFile(); })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_import_file'), (): void => { void this.runImportFile(); })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_save_downloads'), (): void => { void this.runSaveDownloads(); })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_update'), (): void => { void this.runUpdate(); })
      this.buildMenuItem($r('app.string.fieldwatch_signatures_restore'), (): void => { this.confirmRestore(); })
    }.width(220).padding({ top: 6, bottom: 6 })
  }
  @Builder private buildMenuItem(label: ResourceStr, onTap: () => void) {
    Row() { Text(label).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text) }
      .width('100%').height(46).padding({ left: 16, right: 16 })
      .onClick(onTap)
  }

  // ── 目录维护动作（已收进「更多」菜单） ──
  private async runExportFile(): Promise<void> {
    const saved: boolean = await fieldwatchApplication.exportCatalogToUserFile();
    this.notice = saved ? this.noticeText('app.string.fieldwatch_signatures_export_done') : this.noticeText('app.string.fieldwatch_signatures_export_failed');
  }
  private async runSaveDownloads(): Promise<void> {
    const saved: boolean = await fieldwatchApplication.exportCatalogToDownloads();
    this.notice = saved ? this.noticeText('app.string.fieldwatch_signatures_export_done') : this.noticeText('app.string.fieldwatch_signatures_export_failed');
  }
  private async runImportFile(): Promise<void> {
    const outcome: FieldwatchCatalogImportOutcome | undefined = await fieldwatchApplication.importCatalogFromUserFile();
    if (outcome === undefined) {
      this.notice = this.noticeText('app.string.fieldwatch_signatures_import_failed');
      return;
    }
    this.applyImportOutcome(outcome.result);
    this.refresh();
  }
  /** 导入结果 → 用户可读提示；任何失败都必须明确说出来，不能静默。 */
  private applyImportOutcome(result: SignatureImportResult): void {
    if (result.error !== SignaturePackError.NONE) {
      this.notice = this.noticeText('app.string.fieldwatch_signatures_import_failed');
      return;
    }
    if (result.added === 0 && result.merged === 0) {
      this.notice = this.noticeText('app.string.fieldwatch_signatures_import_empty');
      return;
    }
    this.notice = this.noticeText('app.string.fieldwatch_signatures_updated') + ' +' + result.added.toString();
  }
  private async runUpdate(): Promise<void> {
    this.notice = this.noticeText('app.string.fieldwatch_catalog_status_updating');
    const updated: boolean = await fieldwatchApplication.updateCatalog();
    this.notice = updated ? this.noticeText('app.string.fieldwatch_signatures_updated') : this.noticeText('app.string.fieldwatch_signatures_update_failed');
    this.refresh();
  }
  private confirmRestore(): void {
    this.getUIContext().showAlertDialog({
      title: this.noticeText('app.string.fieldwatch_signatures_restore'),
      message: this.noticeText('app.string.fieldwatch_signatures_restore_confirm'),
      primaryButton: { value: this.noticeText('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.noticeText('app.string.fieldwatch_signatures_restore'), action: (): void => { void this.runRestore(); } }
    });
  }
  private async runRestore(): Promise<void> {
    const restored: boolean = await fieldwatchApplication.restoreDefaultCatalog();
    this.notice = restored ? this.noticeText('app.string.fieldwatch_signatures_updated') : this.noticeText('app.string.fieldwatch_signatures_import_failed');
    this.refresh();
  }
  @Builder
  private buildRow(fleet: SignatureFleet) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Text(fleet.name).fontSize(15).fontColor($r('app.color.text_primary')).maxLines(1)
          // 已关注：名称旁边给一个 symbol + 文字。
          // 只看名称的话，用户没法在 240 多条里认出自己关注了哪几个。
          if (fieldwatchApplication.isSignatureWatched(fleet.id)) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(13)
              .fontColor([$r('app.color.button_primary')])
            Text($r('app.string.fieldwatch_signatures_watched')).fontSize(12)
              .fontColor($r('app.color.button_primary'))
          }
        }.width('100%')
        Text(signatureClassLabel(foldedSignatureClass(fleet.category))).fontSize(13).fontColor($r('app.color.text_secondary')).maxLines(1)
        Text((fleet.builtIn ? this.noticeText('app.string.fieldwatch_signatures_stock') : this.noticeText('app.string.fieldwatch_signatures_user'))
          + ' · ' + this.noticeText('app.string.fieldwatch_signatures_rules') + ': ' + fleet.rules.length.toString()
          + ' · ' + this.hitsText(fieldwatchApplication.countMatches(fleet.id)))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: fleet.enabled }).onChange((value: boolean): void => {
        fieldwatchApplication.setFleetEnabled(fleet.id, value);
        this.refresh();
      })
    }
    .width('100%').padding(12).backgroundColor($r('app.color.background_secondary')).borderRadius(12)
    .onClick((): void => {
      if (this.landscape) this.onOpenDetail(fleet.id);
      else { this.detailId = fleet.id; this.sheetOpen = true; }
    })
  }

  @Builder
  private buildDetailSheet() {
    // 内容抽到 FieldwatchSignatureDetail：竖屏 sheet 与横屏右栏**共用同一份**，
    // 避免「同一件事写两遍」——两处必然漂移。
    FieldwatchSignatureDetail({
      fleetId: this.detailId,
      onEdit: (fleetId: string): void => {
        this.sheetOpen = false;
        this.onEditFleet(fleetId, '');
      },
      onClose: (): void => { this.sheetOpen = false; },
      // 关注状态变了就重建列表，让行内的「已关注」立刻出现/消失。
      onFollowChanged: (): void => { this.refresh(); }
    })
  }
}
