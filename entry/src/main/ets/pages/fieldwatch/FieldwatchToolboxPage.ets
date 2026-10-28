/**
 * 工具箱（改版后：入口中心 + 搜索）。
 *
 * 改版理由（设计文档第 3 节）：原来三件现场工具用标签页挤在一个页面里，
 * 别的页面跳进来还要靠 `pendingTool` 指定第几个标签 —— 标签状态、跳转目标、
 * 页面职责三样混在一起。现在三件工具各自独立成页，本页只负责「去哪儿」。
 *
 * 本页**不含任何工具本体**：只有搜索框与入口列表。工具型页面不得遗漏，
 * 新增工具页时必须同时在这里加一条入口。
 */

import { FIELDWATCH_TAB_BAR_RESERVE } from '../../fieldwatch/ui/FieldwatchLayout';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';

/** 一条入口。 */
class ToolEntry {
  /** 路由名（与 `FieldwatchRouteName` 对应）。 */
  public route: string = '';
  public titleKey: string = '';
  public descKey: string = '';
  public symbol: string = '';
  /** 是否为二级入口（附属于上一条，视觉上缩进）。 */
  public secondary: boolean = false;
  constructor(route: string = '', titleKey: string = '', descKey: string = '',
    symbol: string = '', secondary: boolean = false) {
    this.route = route;
    this.titleKey = titleKey;
    this.descKey = descKey;
    this.symbol = symbol;
    this.secondary = secondary;
  }
}

/**
 * 入口目录。
 *
 * 顺序按「现场常用度」排：信道分析与反追踪是驻场工具，
 * 安防/体检是周期性使用，寻踪是特定场景；ACL 专页作为安防的二级入口。
 */
function toolEntries(): ToolEntry[] {
  const list: ToolEntry[] = [];
  list.push(new ToolEntry('fieldwatch.channel_analysis',
    'app.string.fieldwatch_toolbox_entry_channel',
    'app.string.fieldwatch_toolbox_entry_channel_desc', 'sys.symbol.wifi'));
  list.push(new ToolEntry('fieldwatch.anti_track',
    'app.string.fieldwatch_toolbox_entry_antitrack',
    'app.string.fieldwatch_toolbox_entry_antitrack_desc', 'sys.symbol.pin'));
  list.push(new ToolEntry('fieldwatch.find',
    'app.string.fieldwatch_toolbox_entry_find',
    'app.string.fieldwatch_toolbox_entry_find_desc', 'sys.symbol.magnifyingglass'));
  list.push(new ToolEntry('fieldwatch.security',
    'app.string.fieldwatch_toolbox_entry_security',
    'app.string.fieldwatch_toolbox_entry_security_desc', 'sys.symbol.checkmark_shield'));
  list.push(new ToolEntry('fieldwatch.active_acl',
    'app.string.fieldwatch_toolbox_entry_acl',
    'app.string.fieldwatch_toolbox_entry_acl_desc', 'sys.symbol.lock_shield', true));
  list.push(new ToolEntry('fieldwatch.wifi_doctor',
    'app.string.fieldwatch_toolbox_entry_wifi',
    'app.string.fieldwatch_toolbox_entry_wifi_desc', 'sys.symbol.wifi_router'));
  list.push(new ToolEntry('fieldwatch.hunt',
    'app.string.fieldwatch_toolbox_entry_hunt',
    'app.string.fieldwatch_toolbox_entry_hunt_desc', 'sys.symbol.scope'));
  return list;
}

/**
 * 按关键词过滤入口。
 *
 * 匹配范围是**入口名称与说明的翻译结果**（中文子串即可），
 * 不匹配路由名 —— 用户不会去搜 `fieldwatch.channel_analysis`。
 * 空关键词返回全部。
 */
export function filterEntries(all: ToolEntry[], titles: string[], descs: string[],
  keyword: string): ToolEntry[] {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) return all;
  const out: ToolEntry[] = [];
  for (let i: number = 0; i < all.length; i += 1) {
    const title: string = i < titles.length ? titles[i].toLowerCase() : '';
    const desc: string = i < descs.length ? descs[i].toLowerCase() : '';
    if (title.indexOf(key) >= 0 || desc.indexOf(key) >= 0) out.push(all[i]);
  }
  return out;
}

@Component
export struct FieldwatchToolboxPage {
  topInset: number = 0;
  /** 底部安全区高度；与 FIELDWATCH_TAB_BAR_RESERVE 叠加。 */
  @Prop bottomInset: number = 0;
  twoColumn: boolean = false;
  /** 本页当前是否可见（保留该属性以兼容既有调用点）。 */
  @Prop pageVisible: boolean = true;
  /** 打开某个工具页（由根页面注入，按路由名压栈）。 */
  onOpenTool: (route: string) => void = (route: string): void => {};
  @State private keyword: string = '';
  @State private tick: number = 0;

  private text(key: string): string {
    return fieldwatchText(key);
  }

  build() {
    Column() {
      this.buildTitle()
      this.buildEntries()
    }.width('100%').height('100%')
  }

  @Builder
  private buildTitle() {
    Column() {
      Text(fieldwatchText('app.string.fieldwatch_toolbox_title')).fontSize(26)
        .fontWeight(FontWeight.Bold).fontColor(FieldwatchPaletteHolder.get().headerText)
    }.width('100%').alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: this.topInset + 16, bottom: 10 })
  }

  /** 搜索框：按入口名称与一句话说明过滤。 */
  @Builder
  private buildSearch() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
      TextInput({ placeholder: this.text('app.string.fieldwatch_toolbox_search'), text: this.keyword })
        .layoutWeight(1).backgroundColor(Color.Transparent)
        .fontColor(FieldwatchPaletteHolder.get().text)
        .placeholderColor(FieldwatchPaletteHolder.get().textDim)
        .onChange((value: string): void => { this.keyword = value; this.tick += 1; })
    }.width('100%').height(44).padding({ left: 12, right: 12 })
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(12)
    .margin({ bottom: 6 })
  }

  @Builder
  private buildEntries() {
    Scroll() {
      Column({ space: 8 }) {
        this.buildSearch()
        if (this.visibleEntries().length === 0) {
          // 空态给一句话，不留空白页。
          Text(this.text('app.string.fieldwatch_toolbox_no_match')).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
            .padding({ top: 24 })
        } else {
          ForEach(this.visibleEntries(), (entry: ToolEntry): void => {
            this.buildEntryRow(entry)
          }, (entry: ToolEntry): string => entry.route)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
  }

  @Builder
  private buildEntryRow(entry: ToolEntry) {
    Row({ space: 12 }) {
      SymbolGlyph($r(entry.symbol)).fontSize(22)
        .fontColor([FieldwatchPaletteHolder.get().accent])
      Column({ space: 3 }) {
        Text(this.text(entry.titleKey)).fontSize(15)
          .fontColor(FieldwatchPaletteHolder.get().text)
        Text(this.text(entry.descKey)).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
    }.width('100%').borderRadius(12)
    // **二级入口用左内边距缩进，不用 margin**：
    // `width('100%')` 配水平 margin 会让卡片比视口宽，右侧被裁掉（真机实测）。
    .padding({ left: entry.secondary ? 34 : 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => { this.onOpenTool(entry.route); })
  }

  /** 过滤后的可见入口。 */
  private visibleEntries(): ToolEntry[] {
    const all: ToolEntry[] = toolEntries();
    const titles: string[] = [];
    const descs: string[] = [];
    all.forEach((entry: ToolEntry): void => {
      titles.push(this.text(entry.titleKey));
      descs.push(this.text(entry.descKey));
    });
    return filterEntries(all, titles, descs, this.keyword);
  }
}
