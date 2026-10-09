import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { NGFHdsTitleBarOptionsFactory, NGFMaterialSheetOptions, ngfVisualEffectsFacade, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { SignatureClass, foldedSignatureClass, visibleSignatureClasses } from '../../fieldwatch/domain/FieldwatchModels';
import { SignatureDecodeField, SignatureFleet, SignatureFleetDecode, SignatureRule } from '../../fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { SignatureImportResult, SignaturePackError } from '../../fieldwatch/domain/signatures/FieldwatchSignatureCatalog';
import { FieldwatchCatalogImportOutcome } from '../../fieldwatch/data/FieldwatchCatalogRepository';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { SignatureFleetDataSource } from '../../fieldwatch/ui/FieldwatchFleetDataSource';
import { SignatureSortMode, sortSignatureFleets } from '../../fieldwatch/ui/FieldwatchUiState';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone, FieldwatchSegmentedChip } from '../../fieldwatch/ui/FieldwatchButton';

const DECODE_TYPE_LABELS: string[] = ['u8', 'i8', 'u16', 'i16', 'u24', 'u32', 'i32', 'f32', 'bits', 'utf8', 'hex', 'mac', 'bool'];

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
  onEditFleet: (fleetId: string, deviceKey: string) => void = (): void => {};
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
  }

  private refresh(): void {
    const state = fieldwatchApplication.getState();
    this.version = state.catalogVersion;
    this.total = state.signatures.length;
    // 数据源必须跟着重建：LazyForEach 只从它取数，
    // 不重载的话搜索/筛选/启用停用都不会反映到列表上。
    this.fleetSource.reload(this.visible());
    this.tick += 1;
  }

  private fleets(): SignatureFleet[] { return fieldwatchApplication.getState().signatures; }

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
          }, (fleet: SignatureFleet): string => fleet.id + '-' + fleet.enabled.toString())
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
  private confirmDelete(fleet: SignatureFleet): void {
    this.getUIContext().showAlertDialog({
      title: this.noticeText('app.string.fieldwatch_signatures_delete'),
      message: this.noticeText('app.string.fieldwatch_signatures_delete_confirm'),
      primaryButton: { value: this.noticeText('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.noticeText('app.string.fieldwatch_signatures_delete'), action: (): void => {
        fieldwatchApplication.removeUserFleet(fleet.id);
        this.sheetOpen = false;
        this.refresh();
      } }
    });
  }
  @Builder
  private buildRow(fleet: SignatureFleet) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(fleet.name).fontSize(15).fontColor($r('app.color.text_primary')).maxLines(1)
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
    .onClick((): void => { this.detailId = fleet.id; this.sheetOpen = true; })
  }

  @Builder
  private buildDetailSheet() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.detailFleet() !== undefined) {
          this.buildDetailContent(this.detailFleet() as SignatureFleet)
        }
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  @Builder
  private buildDetailContent(fleet: SignatureFleet) {
    Text(fleet.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
    Text(signatureClassLabel(foldedSignatureClass(fleet.category))).fontSize(13).fontColor($r('app.color.text_secondary'))
    Text((fleet.builtIn ? this.noticeText('app.string.fieldwatch_signatures_stock') : this.noticeText('app.string.fieldwatch_signatures_user')) + ' · ' + (fleet.enabled ? this.noticeText('app.string.fieldwatch_signatures_enabled') : this.noticeText('app.string.fieldwatch_signatures_disabled')))
      .fontSize(13).fontColor($r('app.color.text_secondary'))
    if (fleet.attentionNote.length > 0) Text(fleet.attentionNote).fontSize(13).fontColor(FieldwatchPaletteHolder.get().warn)
    if (fleet.notes.length > 0) Text(fleet.notes).fontSize(12).fontColor($r('app.color.text_secondary'))
    Text(this.noticeText('app.string.fieldwatch_signatures_rules') + ' (' + fleet.rules.length.toString() + ')').fontSize(16).fontWeight(FontWeight.Medium)
    if (fleet.rules.length === 0) Text($r('app.string.fieldwatch_signatures_no_rules')).fontSize(13).fontColor($r('app.color.text_secondary'))
    ForEach(fleet.rules, (rule: SignatureRule): void => {
      Row({ space: 8 }) {
        Text(rule.kind).fontSize(12).fontColor($r('app.color.tag_blue')).width(150)
        Text(this.ruleText(rule)).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(2)
      }.width('100%')
    }, (rule: SignatureRule): string => rule.kind + rule.text + rule.dataPrefixHex + rule.companyId.toString())
    if (fleet.decode !== undefined) { this.buildDecodeSection(fleet.decode) }
    Button(fieldwatchApplication.isSignatureWatched(fleet.id) ? $r('app.string.fieldwatch_signatures_unwatch') : $r('app.string.fieldwatch_signatures_watch')).height(44).width('100%').onClick((): void => {
      fieldwatchApplication.toggleSignatureWatch(fleet);
      this.refresh();
    })
    if (!fleet.builtIn) {
      Row({ space: 8 }) {
        Button($r('app.string.fieldwatch_signatures_edit')).height(44).layoutWeight(1).onClick((): void => { this.sheetOpen = false; this.onEditFleet(fleet.id, ''); })
        Button($r('app.string.fieldwatch_signatures_delete')).height(44).layoutWeight(1).onClick((): void => { this.confirmDelete(fleet); })
      }.width('100%')
    }
  }

  @Builder
  private buildDecodeSection(decode: SignatureFleetDecode) {
    Text(this.noticeText('app.string.fieldwatch_signatures_decode') + ' (' + decode.source + ')').fontSize(16).fontWeight(FontWeight.Medium)
    ForEach(decode.fields, (field: SignatureDecodeField): void => {
      Row({ space: 8 }) {
        Text(field.label).fontSize(12).fontColor($r('app.color.tag_blue')).width(150)
        Text(this.decodeFieldText(field)).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(2)
      }.width('100%')
    }, (field: SignatureDecodeField): string => field.id)
  }

  private ruleText(rule: SignatureRule): string {
    const parts: string[] = [];
    if (rule.text.length > 0) parts.push(rule.text);
    if (rule.dataPrefixHex.length > 0) parts.push('0x' + rule.dataPrefixHex);
    if (rule.companyId > 0) parts.push('company=' + rule.companyId.toString());
    return parts.length > 0 ? parts.join(' · ') : rule.kind;
  }

  private decodeFieldText(field: SignatureDecodeField): string {
    const type: string = DECODE_TYPE_LABELS.indexOf(field.type) >= 0 ? field.type : 'hex';
    const parts: string[] = ['@' + field.offset.toString(), type, field.endian];
    if (field.unit.length > 0) parts.push(field.unit);
    if (field.enumLabels !== undefined) parts.push('named=' + field.enumLabels.size.toString());
    return parts.join(' · ');
  }
}
