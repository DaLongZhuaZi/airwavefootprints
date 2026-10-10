import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../application/FieldwatchApplication';
import { SignatureClass, foldedSignatureClass } from '../domain/FieldwatchModels';
import { SignatureDecodeField, SignatureFleet, SignatureFleetDecode, SignatureRule } from '../domain/signatures/FieldwatchSignatureModels';
import { signatureClassLabel } from './FieldwatchClassLabels';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from './FieldwatchButton';

const DECODE_TYPE_LABELS: string[] = ['u8', 'i8', 'u16', 'i16', 'u24', 'u32', 'i32', 'f32', 'bits', 'utf8', 'hex', 'mac', 'bool'];

/**
 * 特征详情内容（**竖屏 sheet 与横屏右栏共用同一份**）。
 *
 * 为什么抽成组件而不是两个 @Builder：
 * 竖屏是底部 sheet、横屏是右侧分栏，两种**宿主**不同，但内容必须逐字一致。
 * 写成两份一定会漂移 —— 本仓库已经因为「同一件事写两遍」踩过多次（陷阱 16）。
 *
 * 底部动作行按原版语义：**关注 / 编辑 同一行，删除单独一行**。
 * 「编辑该特征」对内置特征同样开放（编辑后按用户覆盖持久化）。
 */
@Component
export struct FieldwatchSignatureDetail {
  fleetId: string = '';
  /** 横屏右栏宿主需要自己的标题栏；sheet 宿主不需要。 */
  withShell: boolean = false;
  onEdit: (fleetId: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  /** 顶部系统安全区高度（vp），由根页面测量后传入。 */
  topInset: number = 0;
  /** 关注状态变化时通知外层（横屏分栏时列表同屏可见，必须重建）。 */
  onFollowChanged: () => void = (): void => {};
  @State private tick: number = 0;
  /**
   * 是否已关注。
   *
   * **必须是 `@State`，不能靠 `tick` 带出来**：按钮所在的 `@Builder` 收到的是
   * 同一个 `fleet` 对象引用，ArkUI 比较参数后判定「没变」会**直接跳过重建** ——
   * 于是 `refresh()` 白调，标签永远停在「关注该特征」（实测反馈）。
   * `@State` 的读取会被注册成依赖，改了必定重建。
   */
  @State private watched: boolean = false;
  /**
   * 内容层顶部避让。
   *
   * **不是 92** —— 底板实际覆盖 `underlayHeight + 顶部安全区`（本机 168 + 28 = 196vp），
   * 且合成在内容之上；写 92 时首个内容元素会被压暗（实测：强调色被冲淡）。
   * 见 `ngfImmersiveContentTop`。
   */
  private contentTop(): number { return ngfImmersiveContentTop(this.underlayHeight, this.topInset); }
  /** 顶栏沉浸底板高度，与详情页 / 编辑页同值。 */
  private readonly underlayHeight: number = 168;
  // ── 入场 / 退场动画（与特征编辑页同一套）──
  //
  // **位移用 vp 而不是百分比**：百分比会随容器宽度变化，横屏分栏时位移被放大，
  // 看起来像「被拉伸」。
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  private leaving: boolean = false;

  private fleet(): SignatureFleet | undefined {
    // tick 参与计算，确保 refresh() 之后会重算（否则改名/关注状态不刷新）。
    const bump: number = this.tick;
    const found: SignatureFleet | undefined = fieldwatchApplication.getState().signatures
      .find((item: SignatureFleet): boolean => item.id === this.fleetId);
    return bump >= 0 ? found : found;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private refresh(): void {
    this.tick += 1;
    // 关注状态一律从应用层重算，不在本地做乐观更新 ——
    // 真值只有一处（`state.watchlist`），本地推断迟早与它不一致。
    this.watched = fieldwatchApplication.isSignatureWatched(this.fleetId);
  }

  /**
   * 顶栏主标题：**当前特征的名称**。
   *
   * 原来写死「特征库」—— 打开之后看不出自己在看哪一条。
   * 名称空（或该行已不在目录中）时回退到「特征详情」。
   */
  private shellTitle(): ResourceStr {
    const fleet: SignatureFleet | undefined = this.fleet();
    if (fleet === undefined || fleet.name.length === 0) return $r('app.string.fieldwatch_signatures_detail_subtitle');
    return fleet.name;
  }

  /** 顶栏副标题：**当前类别**，与列表行、详情正文用同一个折叠口径。 */
  private shellSubtitle(): ResourceStr {
    const fleet: SignatureFleet | undefined = this.fleet();
    if (fleet === undefined) return $r('app.string.fieldwatch_signatures_title');
    return signatureClassLabel(foldedSignatureClass(fleet.category));
  }

  /** 只有右栏宿主需要播入场；sheet 宿主由 sheet 自己负责呈现动画。 */
  aboutToAppear(): void {
    // 关注状态与入场动画无关：分栏与 sheet 两种承载方式都要先读一次真值。
    this.watched = fieldwatchApplication.isSignatureWatched(this.fleetId);
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

  /**
   * 退场：反向滑出后再出栈，否则会先「跳」没了。
   *
   * **出栈必须挂在动画的 `onFinish` 上，不能用 `setTimeout(200)` 猜** ——
   * 猜时间会留一个窗口：动画没走完就 pop，模式从 Split 翻回 Stack 的拉伸会被看见。
   */
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
      // **与特征编辑页同一种顶栏结构**：沉浸底板 + 顶部避让 + 入场/退场动画。
      //
      // 只写 `HdsNavDestination { 内容 }` 会缺两样东西：
      //  ① 标题栏底下没有底板，滚动内容直接从标题栏区域穿过；
      //  ② 首行内容被标题栏压住（没有顶部避让）。
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
      /** 返回箭头与系统返回手势都要走退场动画，不能直接 pop。 */
      .onBackPressed((): boolean => {
        this.leaveThenClose();
        return true;
      })
      /** 显式从右滑入：横屏下默认转场与自身位移叠加时方向会读起来是错的。 */
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      /**
       * **位移与透明度必须加在 `HdsNavDestination` 根节点上，不能只加在内层内容上。**
       *
       * 退出时 `pop()` 让 `subPageOpen` 变回 false，模式从 Split 翻到 Stack ——
       * 右栏要从 33% 拉伸到 100%。只让内容淡出的话，根节点的不透明背景仍在，
       * 看到的是一整块实心空白面板在拉伸（实测反馈）。
       */
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
        if (this.fleet() !== undefined) {
          this.buildContent(this.fleet() as SignatureFleet)
        } else {
          // 行被删掉（或目录被重置）时不能留白屏：明确说一句。
          Text($r('app.string.fieldwatch_signatures_detail_gone')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        }
      }.width('100%').padding({ left: 20, right: 20, top: this.withShell ? this.contentTop() : 20, bottom: 20 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildContent(fleet: SignatureFleet) {
    Text(fleet.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor(FieldwatchPaletteHolder.get().text)
    Text(signatureClassLabel(foldedSignatureClass(fleet.category))).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
    Text((fleet.builtIn ? this.text('app.string.fieldwatch_signatures_stock') : this.text('app.string.fieldwatch_signatures_user'))
      + ' · ' + (fleet.enabled ? this.text('app.string.fieldwatch_signatures_enabled') : this.text('app.string.fieldwatch_signatures_disabled')))
      .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
    if (fleet.attentionNote.length > 0) Text(fleet.attentionNote).fontSize(13).fontColor(FieldwatchPaletteHolder.get().warn)
    if (fleet.notes.length > 0) Text(fleet.notes).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
    Text(this.text('app.string.fieldwatch_signatures_rules') + ' (' + fleet.rules.length.toString() + ')').fontSize(16).fontWeight(FontWeight.Medium)
    if (fleet.rules.length === 0) Text($r('app.string.fieldwatch_signatures_no_rules')).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
    ForEach(fleet.rules, (rule: SignatureRule): void => {
      Row({ space: 8 }) {
        Text(rule.kind).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent).width(150)
        Text(this.ruleText(rule)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(2)
        // 规则自己的开关状态要看得见：关掉的规则仍然在，只是不参与匹配。
        if (!rule.enabled) Text($r('app.string.fieldwatch_signatures_rule_off')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().warn)
      }.width('100%')
    }, (rule: SignatureRule): string => rule.kind + rule.text + rule.dataPrefixHex + rule.companyId.toString() + rule.enabled.toString())
    if (fleet.decode !== undefined) { this.buildDecodeSection(fleet.decode) }
    // ── 动作：关注 / 编辑 同一行，删除单独一行 ──
    Row({ space: 8 }) {
      FieldwatchButton({
        label: this.watched
          ? $r('app.string.fieldwatch_signatures_unwatch') : $r('app.string.fieldwatch_signatures_watch'),
        tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => {
          fieldwatchApplication.toggleSignatureWatch(fleet);
          this.refresh();
          // 通知外层重建列表：横屏分栏时列表与详情同屏，
          // 不通知的话列表上的「已关注」要等下次进页面才会更新。
          this.onFollowChanged();
        }
      }).layoutWeight(1)
      FieldwatchButton({ label: $r('app.string.fieldwatch_signatures_edit_fleet'), tone: FieldwatchButtonTone.PRIMARY,
        onTap: (): void => { this.onEdit(fleet.id); } }).layoutWeight(1)
    }.width('100%')
    FieldwatchButton({ label: $r('app.string.fieldwatch_signatures_delete'), tone: FieldwatchButtonTone.OUTLINE,
      onTap: (): void => { this.confirmDelete(fleet); } })
  }

  private confirmDelete(fleet: SignatureFleet): void {
    this.getUIContext().showAlertDialog({
      title: this.text('app.string.fieldwatch_signatures_delete'),
      message: this.text('app.string.fieldwatch_signatures_delete_confirm'),
      primaryButton: { value: this.text('app.string.fieldwatch_filter_cancel'), action: (): void => {} },
      secondaryButton: { value: this.text('app.string.fieldwatch_signatures_delete'), action: (): void => {
        fieldwatchApplication.removeFleet(fleet.id);
        this.onClose();
      } }
    });
  }

  @Builder
  private buildDecodeSection(decode: SignatureFleetDecode) {
    Text(this.text('app.string.fieldwatch_signatures_decode') + ' (' + decode.source + ')').fontSize(16).fontWeight(FontWeight.Medium)
    ForEach(decode.fields, (field: SignatureDecodeField): void => {
      Row({ space: 8 }) {
        Text(field.label).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent).width(150)
        Text(this.decodeFieldText(field)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(2)
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
