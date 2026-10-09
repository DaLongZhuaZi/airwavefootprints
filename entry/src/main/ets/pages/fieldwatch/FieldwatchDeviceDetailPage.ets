import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import window from '@ohos.window';
import { NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, logger, resolveResourceString } from 'ngf_framework';
import { FieldwatchApplication, fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { PresenceSpan, RadioKind, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import { ExplainGuess, FieldwatchDeviceExplain } from '../../fieldwatch/domain/FieldwatchDeviceExplain';
import { FamilyVerdict, SignatureFamilyHint } from '../../fieldwatch/domain/FieldwatchCandidateEngine';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';
import { FieldwatchRouteName, FieldwatchSignatureEditorParam } from '../../fieldwatch/ui/FieldwatchRoutes';
import { presenceTrackCommands, TrendGeometry, trendGeometry, TrendTickLabel } from '../../fieldwatch/ui/FieldwatchUiState';

const TAG: string = 'FieldwatchDeviceDetail';
/** 顶部沉浸底板高度。 */
const DETAIL_UNDERLAY_HEIGHT: number = 168;
/**
 * 内容顶部避让。
 *
 * **不能只用状态栏高度**：HDS 顶栏在状态栏之下还有自己的高度，
 * 用状态栏高度会让首段被顶栏压住（实测副标题与首段文字被覆盖）。
 * 这个值与 `NGFImmersiveTopChromePresetFactory.build` 的 `contentTopInset` 同源。
 */
const DETAIL_CONTENT_TOP: number = 92;
/** 趋势图与在场条的画框。 */
const TREND_W: number = 300;
const TREND_H: number = 64;
/** 在场时间轴的画框。高度取 18 与原版 `PresenceTrack` 一致。 */
const TRACK_W: number = 300;
const TRACK_H: number = 18;

/**
 * 设备详情页 —— 原版 `DeviceDetailScreen.kt`（40.1 KB）的鸿蒙实现。
 *
 * ## 为什么是独立页面而不是 sheet
 *
 * 原版详情有 12 段、一张趋势图、一条在场时间轴和四个动作按钮，
 * 内容长度远超 sheet 能承载的范围；sheet 里滚动还会和手势打架。
 * 页面化之后还能拿到 HDS 的顶栏材质与返回手势。
 *
 * ## 段落顺序与原版一致
 *
 * 外观 -> 备注 -> 身份 -> 信号 -> 蓝牙广播 -> Wi-Fi -> 厂商数据 -> 服务
 * -> 本次会话 -> 信号趋势 -> 在场情况 -> 动作按钮 -> 特征族
 */
@Component
export struct FieldwatchDeviceDetailPage {
  /** 要展示的设备键。 */
  @Prop detailKey: string;
  /**
   * 路由栈。
   *
   * **「开始寻找」与「用此设备创建特征」必须有它** —— 这两个动作都是跳转，
   * 只改应用状态而不跳转的话，用户点了界面毫无反应（实测就是这个问题）。
   */
  pathStack: NavPathStack = new NavPathStack();
  @State private sighting: Sighting | undefined = undefined;
  @State private topInsetVp: number = 108;
  @State private guess: ExplainGuess | undefined = undefined;
  @State private family: SignatureFamilyHint | undefined = undefined;
  /** 趋势图几何量：随设备与画框变化，在 `refresh()` 里算一次。 */
  /**
   * 图表的**实测宽度**。
   *
   * `Path.commands` 用的是**绝对坐标**，而容器是 `width('100%')` ——
   * 命令串按固定 300 宽算、容器却有一千多，结果网格只画在左侧一小条，
   * 末点圆点孤零零飘在右边（实测截图就是这个）。
   * 必须按实测宽度重算几何。
   */
  @State private trend: TrendGeometry = new TrendGeometry();
  @State private chartW: number = 0;
  /** 备注段是否处于编辑态。 */
  @State private editingNotes: boolean = false;
  @State private editName: string = '';
  @State private editNote: string = '';
  @State private trackW: number = 0;
  /** 只用于触发重绘（宽度变化后几何要跟着变）。 */
  @State private tick: number = 0;
  /**
   * 入/出场位移与透明度。
   *
   * **不用导航转场 API**：`NavDestination.customTransition` 在 `HdsNavDestination`
   * 上实测不触发（回调根本没跑，内容被留在屏幕外），
   * `customNavContentTransition` 又拿不到目标页的句柄。
   * 组件自己的 `animateTo` 最可靠，且不牵扯分栏布局。
   */
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  /** 退场动画进行中，避免重复触发。 */
  private leaving: boolean = false;
  @State private signatureNames: string[] = [];
  /** 每秒刷新一次，让「在场情况」与趋势跟着走。 */
  private timerId: number = -1;
  private readonly explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();

  aboutToAppear(): void {
    this.explain.attach(fieldwatchApplication.radioDbRef());
    // 与实时页同一套算法：读系统状态栏高度作为内容顶部避让。
    const uiContext = this.getUIContext();
    const hostContext = uiContext.getHostContext();
    if (hostContext !== undefined && hostContext !== null) {
      window.getLastWindow(hostContext).then((lastWindow: window.Window): void => {
        const statusArea: window.AvoidArea = lastWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.topInsetVp = uiContext.px2vp(statusArea.topRect.height);
      }).catch((): void => { this.topInsetVp = 108; });
    }
    this.refresh();
    this.timerId = setInterval((): void => { this.refresh(); }, 1000);
    // 内容先以「右侧 40vp + 全透明」落位，下一帧再动到原位；
    // 直接在同帧改的话，首帧就已经是终态，看不到动画。
    setTimeout((): void => { this.playEnter(); }, 0);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) { clearInterval(this.timerId); this.timerId = -1; }
  }

  /** 从应用状态里取当前设备并重算解释。设备消失时保留最后一帧，不要闪成空白。 */
  private refresh(): void {
    const found: Sighting | undefined = fieldwatchApplication.sightingByKey(this.detailKey);
    if (found === undefined) return;
    this.sighting = found;
    this.signatureNames = fieldwatchApplication.signatureNamesFor(found);
    this.guess = this.explain.guess(found, this.signatureNames);
    // 族判定要看**全部在场设备** —— 它的意义就在于「有没有别的 MAC 共享同一个空中唯一 ID」。
    this.family = fieldwatchApplication.assessFamilyFor(found, this.signatureNames);
    // 每秒重绘一次：新样本到达后折线要跟着动。
    this.rebuildTrend();
  }

  private label(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  /**
   * 两种形态共用同一份内容。
   *
   * - **页面形态（竖屏）**：根是 `HdsNavDestination`，拿 HDS 顶栏与系统返回手势；
   * - **面板形态（横屏分栏）**：根是普通 `Column`，自绘一条头部（返回箭头 + 标题）。
   *
   * 之所以要有面板形态：横屏分栏如果走 `NavigationMode.Split`，
   * 切换模式会**销毁重建整个 navBar 子树** —— 实时页的 Canvas 与定时器一起重置，
   * 于是雷达闪一下、详情也像是「从左往右挤出来」。
   * 面板形态不碰 mode，入场方向由我们自己用 `transition` 决定。
   */
  build() {
    this.buildPageRoot()
  }

  /** 页面形态：HDS 顶栏 + 系统返回。 */
  @Builder private buildPageRoot() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({
          spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent, DETAIL_UNDERLAY_HEIGHT)
        })
        Scroll() { this.buildBody() }
        .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(this.titleText(), this.subtitleText(),
      $r('app.color.background_primary'), hdsMaterial.MaterialLevel.EXQUISITE, true, false))
    /**
     * 返回按钮与系统返回手势。
     *
     * **不接这个回调，两者都不会关闭详情页** —— 顶栏的返回箭头只是画出来的，
     * 系统手势也不会自动 pop（实测点箭头与侧滑都没有反应）。
     * 返回 `true` 表示已处理，不要让系统再走一遍默认逻辑。
     */
    .onBackPressed((): boolean => {
      this.leaveThenClose();
      return true;
    })
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    /**
     * **位移与透明度必须加在 `HdsNavDestination` 根节点上，不能只加在内层内容上。**
     *
     * 退出时 `pop()` 会让 `subPageOpen` 变回 false，模式从 Split 翻到 Stack ——
     * 右栏要从 33% 拉伸到 100%。若只让内容淡出，**根节点的不透明背景仍在**，
     * 看到的是一整块实心空白面板在拉伸（实测反馈「先拉伸到全屏再消失」）。
     *
     * 加在根节点上，整页（含背景与标题栏）一起淡出，模式翻转时已无可见内容。
     * 特征编辑器是同一处问题、同一个改法。
     */
    .translate({ x: this.enterShift })
    .opacity(this.enterAlpha)
    .width('100%').height('100%').backgroundColor($r('app.color.background_primary'))
  }

  /** 两种形态共用的正文。 */
  @Builder private buildBody() {
    Column({ space: 14 }) {
      if (this.sighting !== undefined) {
        this.buildAppearanceCard(this.sighting)
        this.buildNotesSection(this.sighting)
        this.buildIdentitySection(this.sighting)
        this.buildSignalSection(this.sighting)
        this.buildBleSection(this.sighting)
        this.buildWifiSection(this.sighting)
        this.buildMakerSection(this.sighting)
        this.buildServicesSection(this.sighting)
        this.buildSessionSection(this.sighting)
        this.buildTrendSection(this.sighting)
        this.buildPresenceSection(this.sighting)
        this.buildActions(this.sighting)
        this.buildFamilySection(this.sighting)
        this.buildFooter()
      }
    }.width('100%').padding({ left: 16, right: 16, top: DETAIL_CONTENT_TOP, bottom: 40 })
  }

  /**
   * 按实测宽度重算趋势图几何。
   *
   * 宽度还没量到（首帧）时先按一个合理值算，`onAreaChange` 会立刻纠正；
   * 直接跳过的话首帧是空图，看起来像「图表没画出来」。
   */
  /** 在场条的实际绘制宽度（px）。`Path.commands` 用 px，容器是 vp。 */
  private trackWidthPx(): number {
    const vp: number = this.trackW > 0 ? this.trackW : TRACK_W;
    return this.getUIContext().vp2px(vp);
  }

  /** 背景轨道：铺满整宽、纵向居中的一条。 */
  private trackBackgroundCommands(): string {
    const h: number = this.getUIContext().vp2px(TRACK_H);
    const y1: number = h * 0.25;
    const y2: number = h * 0.75;
    return 'M0 ' + y1.toFixed(1) + ' H' + this.trackWidthPx().toFixed(1)
      + ' V' + y2.toFixed(1) + ' H0 Z';
  }

  private presenceCommands(item: Sighting): string {
    return presenceTrackCommands(item.presence, Date.now(), 15 * 60 * 1000,
      this.trackWidthPx(), this.getUIContext().vp2px(TRACK_H), item.gone);
  }

  /**
   * 按实测宽度重算趋势图几何。
   *
   * `Path.commands` 用 px、`width`/`position` 用 vp —— 几何一律按 px 算，
   * 需要 `position`/尺寸的地方再 px2vp 换算回去。
   */
  private rebuildTrend(): void {
    const widthVp: number = this.chartW > 0 ? this.chartW : TREND_W;
    const widthPx: number = this.getUIContext().vp2px(widthVp);
    this.trend = trendGeometry(this.trendSamples(), widthPx, this.getUIContext().vp2px(TREND_H));
  }

  /** 趋势图用的样本（按时间正序，与 `rssiSamples` 的滑动窗口一致）。 */
  private trendSamples(): number[] {
    return this.sighting === undefined ? [] : this.sighting.rssiSamples;
  }

  /**
   * 入场：从右侧 40vp 处淡入到位。
   *
   * 位移用 vp 而不是百分比 —— 百分比会随容器宽度变化，
   * 分栏收起时容器变全宽，位移量会跟着放大，看起来像「被拉伸」。
   */
  private playEnter(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.enterShift = 0;
      this.enterAlpha = 1;
    });
  }

  /** 退场：反向滑出后再关闭，否则会先「跳」没了。 */
  private leaveThenClose(): void {
    if (this.leaving) return;
    this.leaving = true;
    // **出栈必须挂在动画的 `onFinish` 上，不能用 `setTimeout` 猜时间。**
    //
    // 猜时间会留一个窗口：动画还没走完就 pop，
    // 于是「模式从 Split 翻回 Stack」的拉伸被用户看见（实测反馈）。
    // `onFinish` 是动画真正结束的回调，时序上没有空档。
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => {
        if (this.pathStack.size() > 0) this.pathStack.pop();
      }
    }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  /** 顶栏主标题：厂商 · 猜测结论（对齐原版 `Apple, Inc. · iPhone、iPad 或 Mac`）。 */
  private titleText(): string {
    if (this.sighting === undefined) return this.label('app.string.fieldwatch_detail_title');
    const vendor: string = fieldwatchApplication.vendorOfSighting(this.sighting);
    const core: string = this.guess === undefined || this.guess.generic ? '' : this.guess.label;
    if (vendor.length > 0 && core.length > 0) return vendor + ' · ' + core;
    if (core.length > 0) return core;
    if (vendor.length > 0) return vendor;
    return this.sighting.address;
  }

  private subtitleText(): string {
    return this.sighting === undefined ? '' : this.sighting.address;
  }

  // ── 外观 ──

  /** 最上面那张卡：结论 + 依据。对应原版截图里的「外观」段。 */
  @Builder private buildAppearanceCard(item: Sighting) {
    Column({ space: 6 }) {
      Text(this.label('app.string.fieldwatch_sec_appearance')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
      if (this.guess !== undefined) {
        Text(this.guess.headline).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
        Text(this.guess.because).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  // ── 备注 ──

  /**
   * 备注段。
   *
   * 右上角一个**纯图标**的编辑入口（对齐原版：标题行右侧一支笔），
   * 点开后就地变成两个输入框，**边打边存**，不需要「保存」按钮 ——
   * 这两项本来就是随时补记的东西，多一步确认只会让人忘记存。
   */
  @Builder private buildNotesSection(item: Sighting) {
    Column({ space: 8 }) {
      Row() {
        Text(this.label('app.string.fieldwatch_sec_notes')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().accent)
        Blank()
        SymbolGlyph($r(this.editingNotes ? 'sys.symbol.checkmark' : 'sys.symbol.square_and_pencil'))
          .fontSize(17)
          .fontColor([this.editingNotes ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
          .onClick((): void => {
            // 收起时把输入中的内容落库一次，避免最后一次编辑丢在输入框里。
            if (this.editingNotes) {
              fieldwatchApplication.upsertDeviceLabel(item.key, this.editName);
              // 第三参是「新建条目时用的建议名」—— 先有名称再有备注时，
              // 备注不应该覆盖掉名称，所以传当前名称。
              fieldwatchApplication.upsertDeviceNote(item.key, this.editNote, this.editName);
            } else {
              this.editName = fieldwatchApplication.deviceLabel(item.key);
              this.editNote = fieldwatchApplication.deviceNote(item.key);
            }
            // **用 animateTo 包住状态切换**：直接赋值会让输入框「啪」地出现/消失，
            // 在平板上非常突兀。高度与透明度一起过渡，观感上是「展开」。
            this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
              this.editingNotes = !this.editingNotes;
            });
          })
      }.width('100%')
      if (this.editingNotes) {
        TextInput({ text: this.editName, placeholder: this.label('app.string.fieldwatch_detail_custom_name') })
          .fontSize(14).height(40).enabled(fieldwatchApplication.canSetCustomName(item))
          .onChange((value: string): void => {
            this.editName = value;
            fieldwatchApplication.upsertDeviceLabel(item.key, value);
          })
        // 随机地址不允许命名：它会轮换，名字会绑死在一个再也听不到的键上，
        // 让用户以为设备还在。禁用输入并说明原因，而不是静默失败。
        if (!fieldwatchApplication.canSetCustomName(item)) {
          Text(this.label('app.string.fieldwatch_detail_name_locked')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        }
        TextInput({ text: this.editNote, placeholder: this.label('app.string.fieldwatch_detail_notes') })
          .fontSize(14).height(40)
          .onChange((value: string): void => {
            this.editNote = value;
            fieldwatchApplication.upsertDeviceNote(item.key, value, this.editName);
          })
          // 淡入 + 轻微下移，与 `animateTo` 的时长一致；
          // 只用透明度会像「凭空出现」，加一点位移才有「展开」的实感。
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: -8 }))
              .animation({ duration: 220, curve: Curve.FastOutSlowIn }),
            TransitionEffect.opacity(0).animation({ duration: 160, curve: Curve.FastOutSlowIn })
          ))
      } else {
        // `row` 自己会把空串显示成「无」，不需要额外包一层。
        this.row('app.string.fieldwatch_detail_custom_name',
          fieldwatchApplication.deviceLabel(item.key), FieldwatchPaletteHolder.get().text)
        this.row('app.string.fieldwatch_detail_notes',
          fieldwatchApplication.deviceNote(item.key), FieldwatchPaletteHolder.get().text)
      }
      if (this.signatureNames.length > 0) {
        Text(this.signatureNoteText()).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  /** 特征族说明，对齐原版「Matched Apple Device. A second signature can still dual-label…」。 */
  private signatureNoteText(): string {
    const template: string = this.label('app.string.fieldwatch_detail_signature_note');
    return template.replace('%s', this.signatureNames.join('、'));
  }

  // ── 身份 ──

  @Builder private buildIdentitySection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_identity')
      this.row('app.string.fieldwatch_detail_type', this.radioText(item), FieldwatchPaletteHolder.get().text)
      this.row('app.string.fieldwatch_detail_name', this.nameText(item), FieldwatchPaletteHolder.get().text)
      this.row('app.string.fieldwatch_detail_address', item.address, FieldwatchPaletteHolder.get().text)
      // 地址解释单独一行小字 —— 原版把「这个地址意味着什么」讲清楚，
      // 而不是只丢一个 MAC 让用户自己猜。
      Text(this.explain.addressExplain(item)).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.row('app.string.fieldwatch_detail_vendor', this.vendorExplain(item), FieldwatchPaletteHolder.get().text)
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  private radioText(item: Sighting): string {
    if (item.kind === RadioKind.WIFI) return this.label('app.string.fieldwatch_radio_kind_wifi_ap');
    if (item.kind === RadioKind.NEARLINK) return this.label('app.string.fieldwatch_radio_kind_nearlink');
    return this.label('app.string.fieldwatch_radio_kind_ble');
  }

  private nameText(item: Sighting): string {
    const text: string = fieldwatchApplication.describeName(item);
    return text.length > 0 ? text : this.label('app.string.fieldwatch_detail_no_broadcast_name');
  }

  /** 厂商两行（原版 `vendorLine`）：IEEE 前缀持有者 + 广播里的蓝牙公司。 */
  private vendorExplain(item: Sighting): string {
    const parts: string[] = [];
    const vendor: string = fieldwatchApplication.vendorOfSighting(item);
    const oui: string = item.address.replace(/[^A-Fa-f0-9]/g, '').toUpperCase().substring(0, 6);
    if (vendor.length > 0) {
      const t: string = this.label('app.string.fieldwatch_detail_vendor_ieee');
      parts.push(t.replace('%s', vendor).replace('%o', this.formatOui(oui)));
    }
    const cid: number = item.facts.manufacturerId;
    if (cid > 0) {
      const company: string = fieldwatchApplication.companyName(cid);
      const t: string = this.label('app.string.fieldwatch_detail_vendor_company');
      parts.push(t.replace('%s', company.length > 0 ? company : this.label('app.string.fieldwatch_detail_unlisted'))
        .replace('%x', '0x' + cid.toString(16).toUpperCase().padStart(4, '0')));
    }
    return parts.length > 0 ? parts.join('\n') : this.label('app.string.fieldwatch_detail_vendor_none');
  }

  private formatOui(hex: string): string {
    if (hex.length < 6) return hex;
    return hex.substring(0, 2) + ':' + hex.substring(2, 4) + ':' + hex.substring(4, 6);
  }

  // ── 信号 ──

  @Builder private buildSignalSection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_signal')
      this.row('app.string.fieldwatch_detail_rssi', this.explain.rssiExplain(item.rssi), FieldwatchPaletteHolder.get().rssiBar)
      Text(this.label('app.string.fieldwatch_detail_rssi_note')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.row('app.string.fieldwatch_detail_session_range',
        this.explain.sessionRange(item.rssiMin, item.rssiMax), FieldwatchPaletteHolder.get().text)
      if (item.facts.txPower > -128) {
        this.row('app.string.fieldwatch_detail_tx_power',
          item.facts.txPower.toString() + ' dBm —— 它自称的发射强度，不代表距离', FieldwatchPaletteHolder.get().text)
      }
      if (this.channelFreqText(item).length > 0) {
        this.row('app.string.fieldwatch_detail_channel_freq', this.channelFreqText(item), FieldwatchPaletteHolder.get().text)
      }
      if (item.facts.wifiStandard.length > 0) {
        this.row('app.string.fieldwatch_detail_wifi_generation', item.facts.wifiStandard, FieldwatchPaletteHolder.get().text)
      }
      if (item.facts.centerFreq0 > 0 || item.facts.centerFreq1 > 0) {
        this.row('app.string.fieldwatch_detail_center_freq', this.centerFreqText(item), FieldwatchPaletteHolder.get().text)
      }
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  /** 信道 / 频率，合并成一行（原版把两者放在同一行，中间用 `·`）。 */
  private channelFreqText(item: Sighting): string {
    const parts: string[] = [];
    if (item.facts.frequencyMhz > 0) parts.push(item.facts.frequencyMhz.toString() + ' MHz');
    return parts.join('  ·  ');
  }

  private centerFreqText(item: Sighting): string {
    const parts: string[] = [];
    if (item.facts.centerFreq0 > 0) parts.push(item.facts.centerFreq0.toString() + ' MHz');
    if (item.facts.centerFreq1 > 0) parts.push(item.facts.centerFreq1.toString() + ' MHz');
    return parts.join('  ·  ');
  }

  /** Appearance 的展示文本；名称库里没有时退回代码。 */
  private appearanceText(item: Sighting): string {
    const name: string = fieldwatchApplication.appearanceName(item.facts.appearance);
    const code: string = '0x' + item.facts.appearance.toString(16).toUpperCase().padStart(4, '0');
    return name.length > 0 ? name : this.label('app.string.fieldwatch_detail_unlisted_appearance') + ' ' + code;
  }

  // ── 蓝牙广播 ──

  @Builder private buildBleSection(item: Sighting) {
    if (item.kind === RadioKind.BLE) {
      Column({ space: 8 }) {
        this.sectionTitle('app.string.fieldwatch_sec_ble')
        this.row('app.string.fieldwatch_detail_connectable',
          item.facts.connectable ? this.label('app.string.fieldwatch_detail_connectable_yes')
            : this.label('app.string.fieldwatch_detail_connectable_no'), FieldwatchPaletteHolder.get().text)
        if (item.facts.advertiseFlags >= 0) {
          this.row('app.string.fieldwatch_detail_discoverability',
            this.explain.flagsExplain(item.facts.advertiseFlags), FieldwatchPaletteHolder.get().text)
          this.row('app.string.fieldwatch_detail_flags_raw',
            '0x' + item.facts.advertiseFlags.toString(16).toUpperCase().padStart(2, '0'), FieldwatchPaletteHolder.get().text)
        }
        if (item.facts.appearance >= 0) {
          this.row('app.string.fieldwatch_detail_appearance',
            this.appearanceText(item), FieldwatchPaletteHolder.get().text)
          this.row('app.string.fieldwatch_detail_appearance_code',
            '0x' + item.facts.appearance.toString(16).toUpperCase().padStart(4, '0'), FieldwatchPaletteHolder.get().textDim)
        }
        if (item.facts.deviceClass >= 0) {
          this.row('app.string.fieldwatch_detail_device_class',
            '0x' + item.facts.deviceClass.toString(16).toUpperCase().padStart(6, '0'), FieldwatchPaletteHolder.get().text)
        }
        // 平台限制要讲明白，而不是静默少一行。
        Text(this.label('app.string.fieldwatch_detail_phy_unavailable')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    }
  }

  // ── Wi-Fi ──

  @Builder private buildWifiSection(item: Sighting) {
    if (item.kind === RadioKind.WIFI) {
      Column({ space: 8 }) {
        this.sectionTitle('app.string.fieldwatch_sec_wifi')
        if (item.facts.capabilities.length > 0) {
          this.row('app.string.fieldwatch_detail_security',
            this.explain.wifiSecurityExplain(item.facts.capabilities), FieldwatchPaletteHolder.get().text)
          this.row('app.string.fieldwatch_detail_capability_string',
            item.facts.capabilities, FieldwatchPaletteHolder.get().textDim)
        }
        if (item.facts.hiddenSsid) {
          this.row('app.string.fieldwatch_detail_hidden_ssid',
            this.label('app.string.fieldwatch_detail_hidden_ssid_yes'), FieldwatchPaletteHolder.get().text)
        }
      }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    }
  }

  // ── 厂商数据 ──

  @Builder private buildMakerSection(item: Sighting) {
    if (item.facts.mfgRecords.length > 0) {
      Column({ space: 8 }) {
        this.sectionTitle('app.string.fieldwatch_sec_maker')
        ForEach(item.facts.mfgRecords, (record: ServiceDataRecordLike, index: number): void => {
          Column({ space: 4 }) {
            Text(this.companyRowText(record)).fontSize(13)
              .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
            Text(this.label('app.string.fieldwatch_detail_company_note')).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
            if (record.dataHex.length > 0) {
              Text(this.label('app.string.fieldwatch_detail_raw_payload')
                .replace('%s', (record.dataHex.length / 2).toString()))
                .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
              Text(this.spaced(record.dataHex)).fontSize(13)
                .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
            }
          }.width('100%')
        }, (record: ServiceDataRecordLike, index: number): string => index.toString() + record.uuid)
      }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    }
  }

  private companyRowText(record: ServiceDataRecordLike): string {
    const cid: number = parseInt(record.uuid, 16);
    const company: string = isNaN(cid) ? '' : fieldwatchApplication.companyName(cid);
    const head: string = this.label('app.string.fieldwatch_detail_company_id')
      .replace('%x', '0x' + record.uuid.padStart(4, '0'));
    return company.length > 0 ? head + ': ' + company : head;
  }

  /** 十六进制串加空格，便于按字节读。 */
  private spaced(hex: string): string {
    const out: string[] = [];
    for (let index: number = 0; index + 1 < hex.length; index += 2) out.push(hex.substring(index, index + 2));
    return out.join(' ');
  }

  // ── 服务 ──

  @Builder private buildServicesSection(item: Sighting) {
    if (item.facts.serviceUuids.length > 0) {
      Column({ space: 8 }) {
        this.sectionTitle('app.string.fieldwatch_sec_services')
        ForEach(item.facts.serviceUuids, (uuid: string): void => {
          Column({ space: 2 }) {
            Text(uuid).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).width('100%')
            Text(this.explain.uuidGloss(uuid)).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
          }.width('100%')
        }, (uuid: string): string => uuid)
      }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
    }
  }

  // ── 本次会话 ──

  @Builder private buildSessionSection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_session')
      this.row('app.string.fieldwatch_detail_first_seen', this.clockText(item.firstSeen), FieldwatchPaletteHolder.get().text)
      this.row('app.string.fieldwatch_detail_last_seen', this.clockText(item.lastSeen), FieldwatchPaletteHolder.get().text)
      this.row('app.string.fieldwatch_detail_hits', item.count.toString(), FieldwatchPaletteHolder.get().text)
      if (item.location !== undefined) {
        this.row('app.string.fieldwatch_detail_last_fix',
          item.location.latitude.toFixed(5) + ', ' + item.location.longitude.toFixed(5), FieldwatchPaletteHolder.get().text)
        Text(this.label('app.string.fieldwatch_detail_last_fix_note')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
      if (this.signatureNames.length > 0) {
        this.row('app.string.fieldwatch_detail_matched', this.signatureNames.join('、'), FieldwatchPaletteHolder.get().accent)
      }
      if (item.facts.rawAdHex.length > 0) {
        this.row('app.string.fieldwatch_detail_raw_adv', this.spaced(item.facts.rawAdHex), FieldwatchPaletteHolder.get().text)
      }
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  private clockText(value: number): string {
    const date: Date = new Date(value);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0')
      + ':' + date.getSeconds().toString().padStart(2, '0');
  }

  // ── 信号趋势 ──

  /**
   * 信号趋势：**带完整坐标系的图**，不是一根折线（对齐原版 `Sparkline`）。
   *
   * 图层自下而上是：刻度网格 -> 坐标轴 -> 折线 -> 末点圆点 -> dBm 标签。
   * 每一层一个 `Path`，因为虚线间距、线宽、颜色各不相同，
   * 合成一个 path 就只能取其中一套样式。
   */
  @Builder private buildTrendSection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_trend')
      if (item.rssiSamples.length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 未标注刻度：虚线 (5,5)
          Path().commands(this.trend.horizontalDashed)
            .width('100%').height(TREND_H).fill(Color.Transparent)
            .stroke(FieldwatchPaletteHolder.get().outline).strokeWidth(1.3)
            .strokeOpacity(0.64).strokeDashArray([5, 5])
          // 纵轴主线 + 纵向网格：虚线 (4,6)
          Path().commands(this.trend.vertical)
            .width('100%').height(TREND_H).fill(Color.Transparent)
            .stroke(FieldwatchPaletteHolder.get().outline).strokeWidth(1.2)
            .strokeOpacity(0.64).strokeDashArray([4, 6])
          // 标注刻度：实线，更亮更粗
          Path().commands(this.trend.horizontalSolid)
            .width('100%').height(TREND_H).fill(Color.Transparent)
            .stroke(FieldwatchPaletteHolder.get().outline).strokeWidth(1.95).strokeOpacity(0.94)
          // 折线：3.2 圆头圆角
          Path().commands(this.trend.series)
            .width('100%').height(TREND_H).fill(Color.Transparent)
            .stroke(FieldwatchPaletteHolder.get().accent).strokeWidth(3.2)
            .strokeLineJoin(LineJoinStyle.Round).strokeLineCap(LineCapStyle.Round)
          // 末点圆点：几何是 px，`position`/尺寸是 vp，必须换算。
          if (this.trend.hasDot) {
            Circle({ width: this.getUIContext().px2vp(this.trend.dotRadius * 2),
              height: this.getUIContext().px2vp(this.trend.dotRadius * 2) })
              .fill(FieldwatchPaletteHolder.get().accent)
              .position({
                x: this.getUIContext().px2vp(this.trend.dotX - this.trend.dotRadius),
                y: this.getUIContext().px2vp(this.trend.dotY - this.trend.dotRadius)
              })
          }
          // dBm 标签
          ForEach(this.trend.labels, (tick: TrendTickLabel): void => {
            Text(tick.text).fontSize(8).fontColor(FieldwatchPaletteHolder.get().textDim)
              .fontFamily('monospace')
              .position({ x: 0, y: this.getUIContext().px2vp(tick.y) })
          }, (tick: TrendTickLabel): string => tick.text)
        }
        .width('100%').height(TREND_H)
        .onAreaChange((_old: Area, now: Area): void => {
          const w: number = now.width as number;
          if (Math.abs(w - this.chartW) > 0.5) { this.chartW = w; this.rebuildTrend(); }
        })
      } else {
        Text(this.label('app.string.fieldwatch_trail_waiting')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  // ── 在场情况 ──

  /**
   * 在场情况：**可视图时间轴**（原版 `PresenceTrack` 的等价物）。
   *
   * 背景是一条淡轨道（表示 15 分钟窗口本身），实心条是实际在场的时段。
   * 这样「断续出现」「一直在线」「只露了一下」三种情况一眼可辨 ——
   * 纯文字区间列表做不到这一点。
   */
  @Builder private buildPresenceSection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_presence')
      Stack() {
        // 背景轨道：淡色整条，代表整个 15 分钟窗口
        Path().commands(this.trackBackgroundCommands())
          .width('100%').height(TRACK_H)
          .fill(FieldwatchPaletteHolder.get().accent + '14')
        // 实心条：实际在场的时段
        if (item.presence.length > 0) {
          Path().commands(this.presenceCommands(item))
            .width('100%').height(TRACK_H)
            .fill(FieldwatchPaletteHolder.get().accent)
        }
      }
      .width('100%').height(TRACK_H)
      .onAreaChange((_old: Area, now: Area): void => {
        const w: number = now.width as number;
        if (Math.abs(w - this.trackW) > 0.5) { this.trackW = w; this.tick += 1; }
      })
      Text(this.presenceText(item)).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }


  /** 15 分钟窗口内的在场区间，与原版 `presenceLine` 同口径。 */
  private presenceText(item: Sighting): string {
    const now: number = Date.now();
    const from: number = now - 15 * 60 * 1000;
    const parts: string[] = [];
    item.presence.forEach((span: PresenceSpan): void => {
      const end: number = span.end === undefined ? now : span.end;
      if (end < from) return;
      const start: number = span.start < from ? from : span.start;
      const tail: string = span.end === undefined ? this.label('app.string.fieldwatch_detail_presence_now') : this.clockText(span.end);
      parts.push(this.clockText(start) + '–' + tail);
    });
    return parts.length > 0 ? parts.join('；') : this.label('app.string.fieldwatch_detail_presence_none');
  }

  // ── 动作 ──

  @Builder private buildActions(item: Sighting) {
    Column({ space: 10 }) {
      FieldwatchButton({ label: $r('app.string.fieldwatch_hunt_start'), tone: FieldwatchButtonTone.PRIMARY,
        onTap: (): void => {
          fieldwatchApplication.startHunt(item);
          this.pathStack.pushPathByName(FieldwatchRouteName.HUNT, null);
        } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_signatures_create_from_device'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => {
          // 建出草稿 -> 进编辑器；fleetId 传空串表示「从这台设备新建」。
          fieldwatchApplication.createFleetFromSighting(item);
          this.pathStack.pushPathByName(FieldwatchRouteName.SIGNATURE_EDITOR,
            new FieldwatchSignatureEditorParam('', item.key));
        } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_detail_share_text'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.shareText(item); } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_detail_ai_export'), tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.aiExport(item); } })
    }.width('100%')
  }

  private shareText(item: Sighting): void {
    const text: string = fieldwatchApplication.detailTextOf(item, this.signatureNames);
    this.getUIContext().getPromptAction().showToast({ message: text.substring(0, 60) + '…', duration: 2000 });
    logger.info(TAG, '以文本分享: ' + item.key + ' 长度=' + text.length.toString());
  }

  private aiExport(item: Sighting): void {
    const text: string = fieldwatchApplication.detailPromptOf(item, this.signatureNames);
    this.getUIContext().getPromptAction().showToast({ message: text.substring(0, 60) + '…', duration: 2000 });
    logger.info(TAG, 'AI 导出: ' + item.key + ' 长度=' + text.length.toString());
  }

  // ── 特征族 ──

  /**
   * 特征族：**聚类判定**，不是「显示命中的名字」。
   *
   * 原版 `SignatureCandidates.assessFamily` 回答的是：
   * 「从这里建一条签名，会覆盖一族设备还是只有这一台？」
   * 判定结果按原版分四档并用不同底色区分。
   */
  @Builder private buildFamilySection(item: Sighting) {
    Column({ space: 8 }) {
      this.sectionTitle('app.string.fieldwatch_sec_family')
      if (this.family !== undefined) {
        Text(this.family.title).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.familyTint()).width('100%')
        Text(this.family.body).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%').padding(14).backgroundColor(this.familyBackground()).borderRadius(14)
  }

  /** 四档底色，对齐原版 `FamilyCard` 的配色语义：强=主色、可能=琥珀、其余=中性。 */
  private familyBackground(): string {
    if (this.family === undefined) return FieldwatchPaletteHolder.get().panel;
    if (this.family.verdict === FamilyVerdict.STRONG) return FieldwatchPaletteHolder.get().accent + '2E';
    if (this.family.verdict === FamilyVerdict.POSSIBLE) return FieldwatchPaletteHolder.get().amber + '38';
    return FieldwatchPaletteHolder.get().panel;
  }

  private familyTint(): string {
    if (this.family === undefined) return FieldwatchPaletteHolder.get().text;
    if (this.family.verdict === FamilyVerdict.STRONG) return FieldwatchPaletteHolder.get().accent;
    if (this.family.verdict === FamilyVerdict.POSSIBLE) return FieldwatchPaletteHolder.get().amber;
    return FieldwatchPaletteHolder.get().text;
  }

  @Builder private buildFooter() {
    Text(this.label('app.string.fieldwatch_detail_footer')).fontSize(11)
      .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
  }

  // ── 通用件 ──

  @Builder private sectionTitle(key: string) {
    Text(this.label(key)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent).width('100%')
  }

  @Builder private row(labelKey: string, value: string, valueColor: string) {
    Row({ space: 10 }) {
      Text(this.label(labelKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).width(104)
      Text(value.length > 0 ? value : this.label('app.string.fieldwatch_settings_none'))
        .fontSize(13).fontColor(valueColor).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top)
  }
}

/** `mfgRecords` 元素的最小契约。 */
interface ServiceDataRecordLike { uuid: string; dataHex: string }
