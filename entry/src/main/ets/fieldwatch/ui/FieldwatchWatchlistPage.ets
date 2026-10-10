import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../application/FieldwatchApplication';
import { SignatureClass, foldedSignatureClass, WatchTarget } from '../domain/FieldwatchModels';
import { SignatureFleet, SignatureRule } from '../domain/signatures/FieldwatchSignatureModels';
import { signatureClassLabel } from './FieldwatchClassLabels';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from './FieldwatchButton';
import { FieldwatchChip } from './FieldwatchChip';

/** 添加模式下的一个类别分组。 */
class WatchlistAddGroup {
  public key: string = '';
  /** `signatureClassLabel` 返回 `ResourceStr`，这里不能收窄成 `string`（实测编译失败）。 */
  public label: ResourceStr = '';
  public items: SignatureFleet[] = [];
}

/**
 * 关注列表（**竖屏整页与横屏右栏共用同一份**）。
 *
 * 与特征详情页**逐项对齐**：同一套 `HdsNavDestination` 顶栏结构、同一块沉浸底板、
 * 同一个 `contentTop` / `underlayHeight`、同一套入场退场位移与透明度、
 * 同样的 `SLIDE_RIGHT` 转场与「返回必须走动画再 pop」。
 * 这两页在设计上是同一个层级的兄弟页，任何一处不一致都会被一眼看出来。
 *
 * 两种模式：
 *   - 已关注：当前 `state.watchlist`，可逐条移除；
 *   - 从特征库添加：列出特征库里**尚未关注**的条目，点一下即关注。
 *
 * 真值只有 `state.watchlist` 一处：本页只读它、只调应用层 API，
 * 不在本地维护一份副本 —— 副本与真值迟早不一致。
 */
@Component
export struct FieldwatchWatchlistPage {
  /** 横屏右栏宿主需要自己的标题栏；竖屏整页也需要。 */
  withShell: boolean = false;
  onClose: () => void = (): void => {};
  /** 顶部系统安全区高度（vp），由根页面测量后传入；见 `ngfImmersiveContentTop`。 */
  topInset: number = 0;
  /**
   * 内容层顶部避让。
   *
   * **不是 92** —— 底板实际覆盖 `underlayHeight + 顶部安全区`，
   * 写 92 会让首个内容元素整块落在底板的覆盖带里被压暗（实测）。
   * 见 `ngfImmersiveContentTop` 的说明。
   */
  private contentTop(): number { return ngfImmersiveContentTop(this.underlayHeight, this.topInset); }
  /** 顶栏沉浸底板高度，与详情页 / 编辑页同值。 */
  private readonly underlayHeight: number = 168;
  // ── 入场 / 退场动画（与特征详情页同一套）──
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  @State private tick: number = 0;
  /** false = 已关注；true = 从特征库添加。 */
  @State private adding: boolean = false;
  /** 添加模式的搜索词。 */
  @State private addQuery: string = '';
  /** 添加模式下已展开的类别；默认全折叠，先看类别再看条目。 */
  @State private expanded: string[] = [];
  private leaving: boolean = false;

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  /** tick 参与计算，确保 refresh() 之后会重算。 */
  private watched(): WatchTarget[] {
    const bump: number = this.tick;
    const list: WatchTarget[] = fieldwatchApplication.getWatchlist();
    return bump >= 0 ? list : list;
  }

  /**
   * 按类别分组的「可关注」条目。
   *
   * **不再平铺整个特征库**：244 条一次性铺开既没有结构也没法定位（实测反馈）。
   * 现在按类别分组 + 默认折叠 + 顶部搜索，用户先看类别、再展开、或直接搜。
   */
  private addGroups(): WatchlistAddGroup[] {
    const bump: number = this.tick;
    const needle: string = this.addQuery.trim().toLowerCase();
    const groups: WatchlistAddGroup[] = [];
    const positions: Map<string, number> = new Map<string, number>();
    fieldwatchApplication.visibleSignatures().forEach((fleet: SignatureFleet): void => {
      // 已关注的从「添加」里排除：它们已经在左边那一栏了。
      if (fieldwatchApplication.isSignatureWatched(fleet.id)) return;
      if (needle.length > 0) {
        const inName: boolean = fleet.name.toLowerCase().indexOf(needle) >= 0;
        const inRules: boolean = fleet.rules.some((rule: SignatureRule): boolean =>
          (rule.text + ' ' + rule.dataPrefixHex).toLowerCase().indexOf(needle) >= 0);
        if (!inName && !inRules) return;
      }
      const folded: SignatureClass = foldedSignatureClass(fleet.category);
      const key: string = String(folded);
      const at: number | undefined = positions.get(key);
      if (at === undefined) {
        const group: WatchlistAddGroup = new WatchlistAddGroup();
        group.key = key;
        group.label = signatureClassLabel(folded);
        group.items.push(fleet);
        positions.set(key, groups.length);
        groups.push(group);
      } else {
        groups[at].items.push(fleet);
      }
    });
    return bump >= 0 ? groups : groups;
  }

  /**
   * 该分组是否展开。
   *
   * **搜索时一律展开**：结果已经筛过一遍了，再折叠会让人以为「没搜到」。
   */
  private isExpanded(key: string): boolean {
    if (this.addQuery.trim().length > 0) return true;
    return this.expanded.indexOf(key) >= 0;
  }

  private toggleExpanded(key: string): void {
    const at: number = this.expanded.indexOf(key);
    if (at >= 0) this.expanded = this.expanded.filter((item: string): boolean => item !== key);
    else this.expanded = this.expanded.concat([key]);
  }

  private groupCountText(count: number): string {
    return this.text('app.string.fieldwatch_watchlist_group_count').replace('%s', count.toString());
  }

  private refresh(): void { this.tick += 1; }

  private shellTitle(): ResourceStr { return $r('app.string.fieldwatch_watchlist_title'); }

  private shellSubtitle(): ResourceStr {
    const template: string = this.text('app.string.fieldwatch_watchlist_subtitle');
    return template.replace('%s', this.watched().length.toString());
  }

  aboutToAppear(): void {
    if (!this.withShell) return;
    // 延后一帧再播：此时组件已完成首帧布局，位移才有起点。
    setTimeout((): void => { this.playEnter(); }, 0);
  }

  private playEnter(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.enterShift = 0;
      this.enterAlpha = 1;
    });
  }

  /** 退场：反向滑出后再出栈。出栈挂在动画 `onFinish` 上，不用 setTimeout 猜时间。 */
  private leaveThenClose(): void {
    if (this.leaving) return;
    this.leaving = true;
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => { this.onClose(); }
    }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  build() {
    if (this.withShell) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.TopStart }) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              this.underlayHeight)
          })
          this.buildBody()
        }.width('100%').height('100%')
      }
      .titleBar(NGFHdsTitleBarOptionsFactory.build(
        this.shellTitle(),
        this.shellSubtitle(),
        FieldwatchPaletteHolder.get().night,
        hdsMaterial.MaterialLevel.GENTLE,
        true,
        false
      ))
      .onBackPressed((): boolean => {
        this.leaveThenClose();
        return true;
      })
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .translate({ x: this.enterShift })
      .opacity(this.enterAlpha)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    } else {
      this.buildBody()
    }
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          FieldwatchChip({ label: $r('app.string.fieldwatch_watchlist_tab_watched'), active: !this.adding,
            onTap: (): void => { this.adding = false; } })
          FieldwatchChip({ label: $r('app.string.fieldwatch_watchlist_tab_add'), active: this.adding,
            onTap: (): void => { this.adding = true; } })
        }.width('100%')
        if (this.adding) this.buildAddList()
        else this.buildWatchList()
      }.width('100%').padding({ left: 20, right: 20, top: this.withShell ? this.contentTop() : 20, bottom: 20 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildWatchList() {
    Column({ space: 8 }) {
      if (this.watched().length === 0) {
        Text($r('app.string.fieldwatch_watchlist_empty')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
      ForEach(this.watched(), (target: WatchTarget, index: number): void => {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(target.label.length > 0 ? target.label : target.signatureId).fontSize(15)
              .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
            Text(this.sourceLabel(target)).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
            if (target.note.length > 0) {
              Text(target.note).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(2)
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button($r('app.string.fieldwatch_watchlist_remove'))
            .height(32).fontSize(13).backgroundColor(Color.Transparent)
            .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline)
            .fontColor(FieldwatchPaletteHolder.get().text)
            .onClick((): void => {
              fieldwatchApplication.removeWatchTarget(index);
              this.refresh();
            })
        }.width('100%').padding(12)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
      }, (target: WatchTarget, index: number): string => index.toString() + '-' + target.signatureId + '-' + target.deviceKey)
    }.width('100%')
  }

  /** 来源说明：关注的是「特征」还是「具体设备」。 */
  private sourceLabel(target: WatchTarget): string {
    if (target.deviceKey.length > 0) return this.text('app.string.fieldwatch_watchlist_source_device');
    return this.text('app.string.fieldwatch_watchlist_source_signature');
  }

  @Builder
  private buildAddList() {
    Column({ space: 10 }) {
      // 搜索框：244 条不给人搜索，等于逼用户一条条翻。
      TextInput({ text: this.addQuery, placeholder: $r('app.string.fieldwatch_watchlist_search') })
        .height(40).width('100%').fontSize(14)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(10)
        .onChange((value: string): void => { this.addQuery = value; })
      if (this.addGroups().length === 0) {
        Text($r('app.string.fieldwatch_watchlist_add_empty')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
      ForEach(this.addGroups(), (group: WatchlistAddGroup): void => {
        Column({ space: 6 }) {
          // 类别行：点一下收起/展开。默认折叠，先给出结构再给内容。
          Row({ space: 8 }) {
            SymbolGlyph($r(this.isExpanded(group.key) ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
              .fontSize(14).fontColor([FieldwatchPaletteHolder.get().textDim])
            Text(group.label).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
            Text(this.groupCountText(group.items.length)).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
          }.width('100%').padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick((): void => { this.toggleExpanded(group.key); })
          if (this.isExpanded(group.key)) {
            ForEach(group.items, (fleet: SignatureFleet): void => {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text(fleet.name).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
                  Text(signatureClassLabel(foldedSignatureClass(fleet.category))).fontSize(12)
                    .fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(22)
                  .fontColor([FieldwatchPaletteHolder.get().accent])
              }.width('100%').padding(12)
              .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
              .onClick((): void => {
                fieldwatchApplication.toggleSignatureWatch(fleet);
                this.refresh();
              })
            }, (fleet: SignatureFleet): string => fleet.id)
          }
        }.width('100%')
      }, (group: WatchlistAddGroup): string => group.key)
    }.width('100%')
  }
}
