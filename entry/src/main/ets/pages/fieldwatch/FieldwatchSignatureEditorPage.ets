import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
// `NavigationSystemTransitionType` 是 ArkUI 全局枚举，与 `NavigationMode`、
// `BarPosition` 一样**不需要 import** —— 从 kit 导入会报「no exported member」。
import { NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, NGFMaterialSheetOptions, ngfVisualEffectsFacade, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { RadioKind, SignatureClass, visibleSignatureClasses } from '../../fieldwatch/domain/FieldwatchModels';
import {
  SignatureDecodeEndian, SignatureDecodeField, SignatureDecodeSource, SignatureDecodeType, SignatureDecodeWhen,
  SignatureDecodeWhenOp, SignatureFleet, SignatureFleetDecode, SignatureRule, SignatureRuleKind
} from '../../fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { signatureClassLabel } from '../../fieldwatch/ui/FieldwatchClassLabels';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchSegmentedChip } from '../../fieldwatch/ui/FieldwatchButton';

const RULE_KINDS: SignatureRuleKind[] = [
  SignatureRuleKind.OUI, SignatureRuleKind.MAC_PREFIX, SignatureRuleKind.NAME_CONTAINS, SignatureRuleKind.NAME_GLOB,
  SignatureRuleKind.SERVICE_UUID, SignatureRuleKind.SERVICE_DATA, SignatureRuleKind.MANUFACTURER_ID,
  SignatureRuleKind.MANUFACTURER_DATA, SignatureRuleKind.RADIO_KIND, SignatureRuleKind.HIDDEN_SSID,
  SignatureRuleKind.VENDOR_IE_OUI
];

const DECODE_TYPES: SignatureDecodeType[] = [
  SignatureDecodeType.U8, SignatureDecodeType.I8, SignatureDecodeType.U16, SignatureDecodeType.I16,
  SignatureDecodeType.U24, SignatureDecodeType.U32, SignatureDecodeType.I32, SignatureDecodeType.F32,
  SignatureDecodeType.BITS, SignatureDecodeType.UTF8, SignatureDecodeType.HEX, SignatureDecodeType.MAC,
  SignatureDecodeType.BOOL
];

const GATE_OPS: SignatureDecodeWhenOp[] = [
  SignatureDecodeWhenOp.EQ, SignatureDecodeWhenOp.NEQ, SignatureDecodeWhenOp.MASK, SignatureDecodeWhenOp.NMASK,
  SignatureDecodeWhenOp.LEN
];

/** 门控草稿；编辑器只暴露一层嵌套 and，数据模型本身支持任意深度。 */
class GateDraft {
  public enabled: boolean = false;
  public offset: string = '0';
  public length: string = '1';
  public op: SignatureDecodeWhenOp = SignatureDecodeWhenOp.EQ;
  public valueHex: string = '';
  constructor(enabled: boolean = false, offset: string = '0', length: string = '1', op: SignatureDecodeWhenOp = SignatureDecodeWhenOp.EQ, valueHex: string = '') {
    this.enabled = enabled; this.offset = offset; this.length = length; this.op = op; this.valueHex = valueHex;
  }
}

class NamedValueDraft {
  public key: string = '';
  public label: string = '';
  public strong: boolean = false;
  public note: string = '';
  constructor(key: string = '', label: string = '', strong: boolean = false, note: string = '') {
    this.key = key; this.label = label; this.strong = strong; this.note = note;
  }
}

function gateDraftOf(when: SignatureDecodeWhen | undefined): GateDraft {
  if (when === undefined) return new GateDraft();
  return new GateDraft(true, when.offset.toString(), when.length.toString(), when.op, when.valueHex);
}

function whenOf(draft: GateDraft, and: SignatureDecodeWhen | undefined): SignatureDecodeWhen | undefined {
  if (!draft.enabled) return undefined;
  return new SignatureDecodeWhen(toInt(draft.offset, 0), draft.op, draft.valueHex.trim(), toInt(draft.length, 1), and);
}

function namedDraftsOf(field: SignatureDecodeField): NamedValueDraft[] {
  const rows: NamedValueDraft[] = [];
  const labels: Map<string, string> | undefined = field.enumLabels;
  if (labels !== undefined) {
    labels.forEach((label: string, key: string): void => {
      const notes: Map<string, string> | undefined = field.enumNotes;
      const note: string = notes === undefined || notes.get(key) === undefined ? '' : (notes.get(key) as string);
      rows.push(new NamedValueDraft(key, label, field.liveEmphasis.indexOf(key) >= 0, note));
    });
  }
  return rows;
}

function toInt(value: string, fallback: number): number {
  const parsed: number = parseInt(value, 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

@Component
export struct FieldwatchSignatureEditorPage {
  fleetId: string = '';
  fromDeviceKey: string = '';
  /**
   * 内容层顶部避让。
   *
   * **必须与标题栏高度同源**：92 与 `NGFImmersiveTopChromePresetFactory.build` 的
   * `contentTopInset` 一致，也与设备详情页的 `DETAIL_CONTENT_TOP` 相同。
   * 写死一个小值会让内容压在标题栏底下。
   */
  private readonly contentTop: number = 92;
  /** 顶栏底板高度，与详情页同值。 */
  private readonly underlayHeight: number = 168;
  onClose: () => void = (): void => {};
  @State private editing: boolean = false;
  @State private nameText: string = '';
  @State private notesText: string = '';
  @State private attentionText: string = '';
  @State private category: SignatureClass = SignatureClass.OTHER;
  @State private fleetEnabled: boolean = true;
  @State private matchAny: boolean = true;
  // ── 匹配段的其余开关（原版「Matching」卡片里的五项）──
  // 这些字段模型里一直都有、目录里也在用，只是编辑器没给入口，
  // 等于用户永远改不了它们。
  @State private clusterByOui: boolean = false;
  @State private sequentialMac: boolean = false;
  // 用字符串存而不是 number：输入框中途会出现空串或只有负号的状态，
  // 直接 toInt 会把用户正在输入的内容吞掉。
  @State private minPeersText: string = '0';
  @State private peerWindowText: string = '60';
  @State private colorIndex: number = 0;
  /** 类别芯片是否展开。默认收起：多数时候只需确认当前选的是哪一个。 */
  @State private categoryExpanded: boolean = false;
  @State private rules: SignatureRule[] = [];
  @State private decodeEnabled: boolean = false;
  @State private decodeSource: SignatureDecodeSource = SignatureDecodeSource.MANUFACTURER_DATA;
  @State private decodeService: string = '';
  @State private decodeCompany: string = '0';
  @State private decodeIncludeCompany: boolean = false;
  @State private decodeFields: SignatureDecodeField[] = [];
  @State private notice: string = '';
  // ── 入场/退场动画 ──
  //
  // 与设备详情页同一套做法：**位移用 vp 而不是百分比** ——
  // 百分比会随容器宽度变化，横屏分栏时位移会被放大，看起来像「被拉伸」。
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  private leaving: boolean = false;
  @State private ruleOpen: boolean = false;
  @State private ruleIndex: number = -1;
  @State private ruleKind: SignatureRuleKind = SignatureRuleKind.NAME_CONTAINS;
  @State private ruleText: string = '';
  @State private ruleCompany: string = '0';
  @State private rulePrefix: string = '';
  @State private ruleRadio: number = 0;
  @State private fieldOpen: boolean = false;
  @State private fieldIndex: number = -1;
  @State private fieldId: string = '';
  @State private fieldLabel: string = '';
  @State private fieldOffset: string = '0';
  @State private fieldLength: string = '1';
  @State private fieldType: SignatureDecodeType = SignatureDecodeType.U8;
  @State private fieldEndian: SignatureDecodeEndian = SignatureDecodeEndian.LE;
  @State private fieldUnit: string = '';
  @State private fieldLive: boolean = false;
  @State private fieldGate: GateDraft = new GateDraft();
  @State private fieldGateAnd: GateDraft = new GateDraft();
  @State private fieldNamed: NamedValueDraft[] = [];

  aboutToAppear(): void {
    this.load();
    // 延后一帧再播：此时组件已完成首帧布局，位移才有起点。
    setTimeout((): void => { this.playEnter(); }, 0);
  }

  private playEnter(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.enterShift = 0;
      this.enterAlpha = 1;
    });
  }

  /** 退场：反向滑出后再出栈，否则会先「跳」没了。 */
  private leaveThenClose(): void {
    if (this.leaving) return;
    this.leaving = true;
    // **出栈必须挂在动画的 `onFinish` 上，不能用 `setTimeout(200)` 猜。**
    //
    // 猜时间会有一个窗口：动画还没走完就 pop，
    // 于是「模式从 Split 翻回 Stack」的拉伸被用户看见（实测反馈）。
    // `onFinish` 是动画真正结束的回调，时序上没有空档。
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.FastOutSlowIn,
      onFinish: (): void => { this.onClose(); }
    }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  private text(key: string): string { return resolveResourceString(this.getUIContext().getHostContext(), $r(key)); }

  private load(): void {
    if (this.fleetId.length > 0) {
      const existing: SignatureFleet | undefined = fieldwatchApplication.getState().signatures.find((item: SignatureFleet): boolean => item.id === this.fleetId);
      if (existing !== undefined) { this.applyFleet(existing); return; }
    }
    if (this.fromDeviceKey.length > 0) {
      const sighting = fieldwatchApplication.getState().sightings.find((item) => item.key === this.fromDeviceKey);
      if (sighting !== undefined) { this.applyFleet(fieldwatchApplication.createFleetFromSighting(sighting)); return; }
    }
    const created: SignatureFleet = new SignatureFleet('sig-' + Date.now().toString(), '', SignatureClass.OTHER, []);
    created.rules.push(new SignatureRule(SignatureRuleKind.NAME_CONTAINS));
    this.applyFleet(created);
  }

  private applyFleet(fleet: SignatureFleet): void {
    this.editing = fleet.id.length > 0 && fieldwatchApplication.getState().signatures.some((item: SignatureFleet): boolean => item.id === fleet.id);
    this.nameText = fleet.name;
    this.notesText = fleet.notes;
    this.attentionText = fleet.attentionNote;
    this.category = fleet.category;
    this.fleetEnabled = fleet.enabled;
    this.matchAny = fleet.matchAny;
    this.clusterByOui = fleet.clusterByOui;
    this.sequentialMac = fleet.sequentialMac;
    this.minPeersText = fleet.minPeers.toString();
    this.peerWindowText = fleet.peerWindowSec.toString();
    this.colorIndex = fleet.colorIndex;
    this.rules = fleet.rules.slice();
    const decode: SignatureFleetDecode | undefined = fleet.decode;
    this.decodeEnabled = decode !== undefined;
    this.decodeSource = decode === undefined ? SignatureDecodeSource.MANUFACTURER_DATA : decode.source;
    this.decodeService = decode === undefined ? '' : decode.serviceUuid;
    this.decodeCompany = decode === undefined ? '0' : decode.companyId.toString();
    this.decodeIncludeCompany = decode === undefined ? false : decode.includeCompanyId;
    this.decodeFields = decode === undefined ? [] : decode.fields.slice();
  }

  private buildFleet(): SignatureFleet {
    const fleet: SignatureFleet = new SignatureFleet(
      this.fleetId.length > 0 ? this.fleetId : 'sig-' + Date.now().toString(),
      this.nameText.trim(), this.category, this.rules.slice(), false
    );
    fleet.enabled = this.fleetEnabled;
    fleet.matchAny = this.matchAny;
    fleet.clusterByOui = this.clusterByOui;
    fleet.sequentialMac = this.sequentialMac;
    // 解析失败时退回默认值，而不是写入 NaN ——
    // 原版同样用 `toIntOrNull() ?: 0` / `?: 60` 兜底。
    fleet.minPeers = toInt(this.minPeersText, 0);
    fleet.peerWindowSec = toInt(this.peerWindowText, 60);
    fleet.colorIndex = this.colorIndex;
    fleet.notes = this.notesText.trim();
    fleet.attentionNote = this.attentionText.trim();
    if (this.decodeEnabled && this.decodeFields.length > 0) {
      fleet.decode = new SignatureFleetDecode(this.decodeSource, this.decodeFields.slice(), this.decodeService.trim(), toInt(this.decodeCompany, 0), this.decodeIncludeCompany);
    }
    return fleet;
  }

  private save(): void {
    if (this.nameText.trim().length === 0) { this.notice = this.text('app.string.fieldwatch_editor_invalid_name'); return; }
    const usable: SignatureRule[] = this.rules.filter((rule: SignatureRule): boolean => rule.text.length > 0 || rule.dataPrefixHex.length > 0 || rule.companyId > 0 || rule.kind === SignatureRuleKind.HIDDEN_SSID || rule.kind === SignatureRuleKind.RADIO_KIND);
    if (usable.length === 0) { this.notice = this.text('app.string.fieldwatch_editor_invalid_rule'); return; }
    const saved: boolean = fieldwatchApplication.saveUserFleet(this.buildFleet());
    this.notice = saved ? this.text('app.string.fieldwatch_editor_saved') : this.text('app.string.fieldwatch_editor_save_failed');
  }

  private sheetOptions(): NGFMaterialSheetOptions {
    const options: NGFMaterialSheetOptions = new NGFMaterialSheetOptions(ngfVisualEffectsFacade.buildSystemMaterialForSheet(), ngfVisualEffectsFacade.shouldUseSystemMaterialSurface());
    options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
    return options;
  }

  build() {
    HdsNavDestination() {
      // **与设备详情页同一种顶栏结构**：底板 + 滚动内容。
      //
      // 之前只有一层 `Column`，标题栏底下没有底板 ——
      // 滚动时内容会从标题栏区域直接穿过，观感与详情页不一致。
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({
          spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
            FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
            this.underlayHeight)
        })
        Scroll() {
          Column({ space: 12 }) {
          // **按原版的五张卡片组织**：身份 / 匹配 / 颜色 / 规则 / 解码字段。
          //
          // 之前是一串平铺输入框：看不出哪些项属于同一组，
          // 也看不出「备注」与「关注提示」是两件不同的事 ——
          // 前者只是给人看的说明，后者会在 Live 上打「!」并在复盘里出现。
          this.buildIdentityCard()
          this.buildMatchingCard()
          this.buildColorCard()
          this.buildRulesSection()
          this.buildDecodeSection()
          Row({ space: 8 }) {
            Button($r('app.string.fieldwatch_editor_save')).height(44).layoutWeight(1).onClick((): void => { this.save(); })
            Button($r('app.string.fieldwatch_editor_cancel')).height(44).layoutWeight(1).onClick((): void => { this.onClose(); })
          }.width('100%')
          if (this.notice.length > 0) Text(this.notice).fontSize(13).fontColor(FieldwatchPaletteHolder.get().warn)
          // **顶部避让必须与标题栏高度同源。**
          //
          // 原来写死 16，内容直接压在标题栏底下（实测反馈）。
          // 92 与 `NGFImmersiveTopChromePresetFactory.build` 的 `contentTopInset` 一致，
          // 也与设备详情页的 `DETAIL_CONTENT_TOP` 同源。
          }.width('100%').padding({ left: 16, right: 16, top: this.contentTop, bottom: 48 })
        }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      this.editing ? $r('app.string.fieldwatch_editor_title_edit') : $r('app.string.fieldwatch_editor_title_new'),
      $r('app.string.fieldwatch_editor_attention_hint'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    /**
     * **返回箭头与系统返回手势。**
     *
     * 不接这个回调，两者都不会关闭编辑器（顶栏箭头只是画出来的，
     * 系统手势也不会自动 pop）—— 详情页当初正是这个问题。
     * 返回 `true` 表示已处理，不要让系统再走一遍默认逻辑。
     */
    .onBackPressed((): boolean => {
      this.leaveThenClose();
      return true;
    })
    /**
     * **显式指定从右滑入。**
     *
     * 横屏下默认转场与页面自身的位移叠加，方向读起来是错的；
     * 明确成 `SLIDE_RIGHT` 后方向固定，配合上面的 `enterShift` 只滑一小段。
     */
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    /**
     * **位移与透明度必须加在 `HdsNavDestination` 根节点上，不能只加在内层内容上。**
     *
     * 退出时 `pop()` 会让 `subPageOpen` 变回 false，模式从 Split 翻到 Stack ——
     * 右栏要从 33% 拉伸到 100%。若只让内容淡出，**根节点的不透明背景仍在**，
     * 看到的是一整块实心空白面板在拉伸（实测反馈「先拉伸到全屏再消失」）。
     *
     * 加在根节点上，整页（含背景与标题栏）一起淡出，模式翻转时已无可见内容。
     */
    .translate({ x: this.enterShift })
    .opacity(this.enterAlpha)
    .bindSheet($$this.ruleOpen, this.buildRuleSheet(), this.sheetOptions())
  }

  /**
   * 卡片外壳：与详情页/特征库同一种观感（面板底 + 圆角 + 段标题）。
   *
   * 段标题用强调色小字，和详情页的 `sectionTitle` 保持一致 ——
   * 这样「新建特征」和「信号源详情」看起来是同一个 App。
   */
  @Builder
  private sectionCard(titleKey: string, hintKey: string) {
    Column({ space: 10 }) {
      Text($r(titleKey)).fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      if (hintKey.length > 0) {
        Text($r(hintKey)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%')
  }

  /** 一行开关：标题 + 说明（可选）+ 右侧开关。 */
  @Builder
  private switchRow(titleKey: string, hintKey: string, isOn: boolean, onToggle: (value: boolean) => void) {
    Column({ space: 2 }) {
      Row() {
        Text($r(titleKey)).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .onChange((value: boolean): void => { onToggle(value); })
      }.width('100%')
      if (hintKey.length > 0) {
        Text($r(hintKey)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      }
    }.width('100%')
  }

  /** 一行输入：标题 + 输入框。 */
  @Builder
  private inputRow(titleKey: string, value: string, onEdit: (text: string) => void) {
    Column({ space: 4 }) {
      Text($r(titleKey)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      TextInput({ text: value }).height(42).fontSize(14)
        .onChange((text: string): void => { onEdit(text); })
    }.width('100%')
  }

  // ── 身份 ──

  @Builder
  private buildIdentityCard() {
    Column({ space: 10 }) {
      this.sectionCard('app.string.fieldwatch_editor_sec_identity', '')
      this.inputRow('app.string.fieldwatch_editor_name', this.nameText,
        (text: string): void => { this.nameText = text; })
      this.inputRow('app.string.fieldwatch_editor_notes', this.notesText,
        (text: string): void => { this.notesText = text; })
      Text($r('app.string.fieldwatch_editor_notes_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.inputRow('app.string.fieldwatch_editor_attention', this.attentionText,
        (text: string): void => { this.attentionText = text; })
      Text($r('app.string.fieldwatch_editor_attention_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  // ── 匹配 ──

  @Builder
  private buildMatchingCard() {
    Column({ space: 10 }) {
      this.sectionCard('app.string.fieldwatch_editor_sec_matching', '')
      Text($r('app.string.fieldwatch_editor_category')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.buildCategoryChips()
      Text($r('app.string.fieldwatch_editor_category_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.switchRow('app.string.fieldwatch_editor_match_any', 'app.string.fieldwatch_editor_match_any_hint',
        this.matchAny, (value: boolean): void => { this.matchAny = value; })
      this.switchRow('app.string.fieldwatch_editor_cluster_oui', 'app.string.fieldwatch_editor_cluster_oui_hint',
        this.clusterByOui, (value: boolean): void => { this.clusterByOui = value; })
      this.switchRow('app.string.fieldwatch_editor_sequential_mac', 'app.string.fieldwatch_editor_sequential_mac_hint',
        this.sequentialMac, (value: boolean): void => { this.sequentialMac = value; })
      this.inputRow('app.string.fieldwatch_editor_min_peers', this.minPeersText,
        (text: string): void => { this.minPeersText = text; })
      this.inputRow('app.string.fieldwatch_editor_peer_window', this.peerWindowText,
        (text: string): void => { this.peerWindowText = text; })
      Text($r('app.string.fieldwatch_editor_peer_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      this.switchRow('app.string.fieldwatch_signatures_enabled', '', this.fleetEnabled,
        (value: boolean): void => { this.fleetEnabled = value; })
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  // ── 颜色 ──

  @Builder
  private buildColorCard() {
    Column({ space: 10 }) {
      this.sectionCard('app.string.fieldwatch_editor_sec_color', '')
      Row({ space: 8 }) {
        ForEach(FieldwatchPaletteHolder.get().signatureRamp,
          (color: string, index: number): void => {
            Stack() {
              // 选中态用一个勾，而不是只靠描边 ——
              // 九个色块并排时描边很难一眼分辨。
              if (this.colorIndex === index) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Color.White])
              }
            }
            .width(34).height(34).borderRadius(10).backgroundColor(color)
            .borderWidth(this.colorIndex === index ? 2 : 0)
            .borderColor(FieldwatchPaletteHolder.get().text)
            .onClick((): void => { this.colorIndex = index; })
          }, (color: string, index: number): string => color + index.toString())
      }.width('100%')
      Text($r('app.string.fieldwatch_editor_color_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
    }.width('100%').padding(14).backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
  }

  /**
   * 类别选择：**可展开/收起的一排芯片**。
   *
   * 类别有十几种，一直平铺会把「匹配」这张卡片撑得很高，
   * 而多数时候用户只想确认当前选的是哪一个。
   *
   * 收起时只显示当前类别 + 展开按钮；展开后是可横滑的完整列表。
   * 用 `animateTo` 包住状态切换，配合 `transition` 做高度与透明度过渡 ——
   * 直接赋值会「啪」地弹出来。
   */
  @Builder
  private buildCategoryChips() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // 收起时保留当前选中项，否则用户看不到自己选了什么。
        FieldwatchSegmentedChip({ label: signatureClassLabel(this.category), selected: true,
          onTap: (): void => { this.toggleCategoryExpanded(); } })
        Blank()
        Row({ space: 4 }) {
          Text(this.categoryExpanded
            ? $r('app.string.fieldwatch_editor_collapse')
            : $r('app.string.fieldwatch_editor_expand'))
            .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
          SymbolGlyph($r(this.categoryExpanded ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
            .fontSize(13).fontColor([FieldwatchPaletteHolder.get().textDim])
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(9)
        .backgroundColor(FieldwatchPaletteHolder.get().panel)
        .onClick((): void => { this.toggleCategoryExpanded(); })
      }.width('100%')
      if (this.categoryExpanded) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(visibleSignatureClasses(), (item: SignatureClass): void => {
              FieldwatchSegmentedChip({ label: signatureClassLabel(item), selected: this.category === item,
                onTap: (): void => { this.category = item; } })
            }, (item: SignatureClass): string => item)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring).width('100%')
        // 淡入 + 轻微下移，和备注编辑块用同一套观感。
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: -8 }))
            .animation({ duration: 200, curve: Curve.FastOutSlowIn }),
          TransitionEffect.opacity(0).animation({ duration: 140, curve: Curve.FastOutSlowIn })
        ))
      }
    }.width('100%')
  }

  private toggleCategoryExpanded(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, (): void => {
      this.categoryExpanded = !this.categoryExpanded;
    });
  }

  @Builder
  private buildRulesSection() {
    Row() {
      Text(this.text('app.string.fieldwatch_signatures_rules') + ' (' + this.rules.length.toString() + ')').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
      Button($r('app.string.fieldwatch_editor_add_rule')).height(36).onClick((): void => { this.openRule(-1); })
    }.width('100%')
    if (this.rules.length === 0) Text($r('app.string.fieldwatch_editor_no_rules')).fontSize(13).fontColor($r('app.color.text_secondary'))
    ForEach(this.rules, (rule: SignatureRule, index: number): void => {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(rule.kind).fontSize(13).fontColor($r('app.color.tag_blue'))
          Text(this.ruleSummary(rule)).fontSize(12).fontColor($r('app.color.text_primary')).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button($r('app.string.fieldwatch_signatures_edit')).height(36).onClick((): void => { this.openRule(index); })
      }.width('100%').padding(10).backgroundColor($r('app.color.background_secondary')).borderRadius(10)
    }, (rule: SignatureRule, index: number): string => rule.kind + rule.text + rule.dataPrefixHex + index.toString())
  }

  @Builder
  private buildDecodeSection() {
    Column({ space: 8 }) {
      Row() { Text($r('app.string.fieldwatch_signatures_decode')).fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.decodeEnabled }).onChange((value: boolean): void => { this.decodeEnabled = value; if (value && this.decodeFields.length === 0) this.decodeFields = [new SignatureDecodeField()]; }) }.width('100%')
      Text($r('app.string.fieldwatch_editor_decode_fields_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
      if (this.decodeEnabled) {
        Row({ space: 8 }) {
          FieldwatchSegmentedChip({ label: 'manufacturerData', selected: this.decodeSource === SignatureDecodeSource.MANUFACTURER_DATA, onTap: (): void => { this.decodeSource = SignatureDecodeSource.MANUFACTURER_DATA; } })
          FieldwatchSegmentedChip({ label: 'serviceData', selected: this.decodeSource === SignatureDecodeSource.SERVICE_DATA, onTap: (): void => { this.decodeSource = SignatureDecodeSource.SERVICE_DATA; } })
        }.width('100%')
        TextInput({ text: this.decodeService, placeholder: $r('app.string.fieldwatch_editor_decode_service') }).height(42).onChange((value: string): void => { this.decodeService = value; })
        TextInput({ text: this.decodeCompany, placeholder: $r('app.string.fieldwatch_editor_rule_company') }).type(InputType.Number).height(42).onChange((value: string): void => { this.decodeCompany = value; })
        Row() { Text($r('app.string.fieldwatch_editor_decode_include_company')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.decodeIncludeCompany }).onChange((value: boolean): void => { this.decodeIncludeCompany = value; }) }.width('100%')
        Row() {
          Text(this.text('app.string.fieldwatch_signatures_decode') + ' (' + this.decodeFields.length.toString() + ')').fontSize(15).layoutWeight(1)
          Button($r('app.string.fieldwatch_editor_add_field')).height(36).onClick((): void => { this.openField(-1); })
        }.width('100%')
        ForEach(this.decodeFields, (field: SignatureDecodeField, index: number): void => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(field.label.length > 0 ? field.label : field.id).fontSize(13).fontColor($r('app.color.text_primary'))
              Text('@' + field.offset.toString() + ' · ' + field.type + ' · ' + field.endian).fontSize(11).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button($r('app.string.fieldwatch_signatures_edit')).height(36).onClick((): void => { this.openField(index); })
          }.width('100%').padding(10).backgroundColor($r('app.color.background_secondary')).borderRadius(10)
        }, (field: SignatureDecodeField, index: number): string => field.id + index.toString())
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
    .bindSheet($$this.fieldOpen, this.buildFieldSheet(), this.sheetOptions())
  }

  private ruleSummary(rule: SignatureRule): string {
    const parts: string[] = [];
    if (rule.text.length > 0) parts.push(rule.text);
    if (rule.dataPrefixHex.length > 0) parts.push('0x' + rule.dataPrefixHex);
    if (rule.companyId > 0) parts.push('company=' + rule.companyId.toString());
    // 星闪是独立种类，不能再落进 BLE 分支显示成「BLE」。
    if (rule.radio !== undefined) parts.push(this.radioLabelOf(rule.radio));
    return parts.length > 0 ? parts.join(' · ') : rule.kind;
  }

  private openRule(index: number): void {
    this.ruleIndex = index;
    const rule: SignatureRule = index >= 0 && index < this.rules.length ? this.rules[index] : new SignatureRule(SignatureRuleKind.NAME_CONTAINS);
    this.ruleKind = rule.kind;
    this.ruleText = rule.text;
    this.ruleCompany = rule.companyId.toString();
    this.rulePrefix = rule.dataPrefixHex;
    this.ruleRadio = rule.radio === undefined ? 0
      : (rule.radio === RadioKind.WIFI ? 1 : (rule.radio === RadioKind.NEARLINK ? 3 : 2));
    this.ruleOpen = true;
  }

  /** 无线电种类 → 显示名。三态必须各自区分，否则星闪会被误认为 BLE。 */
  private radioLabelOf(kind: RadioKind): string {
    if (kind === RadioKind.WIFI) return 'Wi-Fi';
    if (kind === RadioKind.NEARLINK) return '星闪';
    return 'BLE';
  }
  private commitRule(): void {
    const rule: SignatureRule = new SignatureRule(this.ruleKind, this.ruleText.trim(), toInt(this.ruleCompany, 0), this.rulePrefix.trim(), this.ruleRadio === 0 ? undefined
      : (this.ruleRadio === 1 ? RadioKind.WIFI : (this.ruleRadio === 3 ? RadioKind.NEARLINK : RadioKind.BLE)));
    const next: SignatureRule[] = this.rules.slice();
    if (this.ruleIndex >= 0 && this.ruleIndex < next.length) next[this.ruleIndex] = rule;
    else next.push(rule);
    this.rules = next;
    this.ruleOpen = false;
  }

  private deleteRule(): void {
    if (this.ruleIndex < 0) return;
    this.rules = this.rules.filter((item: SignatureRule, index: number): boolean => index !== this.ruleIndex);
    this.ruleOpen = false;
  }

  @Builder
  private buildRuleSheet() {
    Scroll() {
      Column({ space: 10 }) {
        Text(this.ruleIndex >= 0 ? $r('app.string.fieldwatch_editor_edit_rule') : $r('app.string.fieldwatch_editor_add_rule')).fontSize(20).fontWeight(FontWeight.Bold)
        Text($r('app.string.fieldwatch_editor_rule_kind')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Scroll() {
          Row({ space: 8 }) {
            ForEach(RULE_KINDS, (item: SignatureRuleKind): void => {
              FieldwatchSegmentedChip({ label: item, selected: this.ruleKind === item, onTap: (): void => { this.ruleKind = item; } })
            }, (item: SignatureRuleKind): string => item)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%')
        TextInput({ text: this.ruleText, placeholder: $r('app.string.fieldwatch_editor_rule_text') }).height(44).onChange((value: string): void => { this.ruleText = value; })
        TextInput({ text: this.ruleCompany, placeholder: $r('app.string.fieldwatch_editor_rule_company') }).type(InputType.Number).height(44).onChange((value: string): void => { this.ruleCompany = value; })
        TextInput({ text: this.rulePrefix, placeholder: $r('app.string.fieldwatch_editor_rule_prefix') }).height(44).onChange((value: string): void => { this.rulePrefix = value; })
        Text($r('app.string.fieldwatch_editor_radio')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Row({ space: 8 }) {
          FieldwatchSegmentedChip({ label: $r('app.string.fieldwatch_editor_radio_any'), selected: this.ruleRadio === 0, onTap: (): void => { this.ruleRadio = 0; } })
          FieldwatchSegmentedChip({ label: 'Wi-Fi', selected: this.ruleRadio === 1, onTap: (): void => { this.ruleRadio = 1; } })
          FieldwatchSegmentedChip({ label: '星闪', selected: this.ruleRadio === 3, onTap: (): void => { this.ruleRadio = 3; } })
          FieldwatchSegmentedChip({ label: 'BLE', selected: this.ruleRadio === 2, onTap: (): void => { this.ruleRadio = 2; } })
        }.width('100%')
        Row({ space: 8 }) {
          Button($r('app.string.fieldwatch_editor_ok')).height(44).layoutWeight(1).onClick((): void => { this.commitRule(); })
          if (this.ruleIndex >= 0) Button($r('app.string.fieldwatch_editor_delete_rule')).height(44).layoutWeight(1).onClick((): void => { this.deleteRule(); })
        }.width('100%')
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }

  private openField(index: number): void {
    this.fieldIndex = index;
    const field: SignatureDecodeField = index >= 0 && index < this.decodeFields.length ? this.decodeFields[index] : new SignatureDecodeField();
    this.fieldId = field.id;
    this.fieldLabel = field.label;
    this.fieldOffset = field.offset.toString();
    this.fieldLength = field.resolvedLength().toString();
    this.fieldType = field.type;
    this.fieldEndian = field.endian;
    this.fieldUnit = field.unit;
    this.fieldLive = field.live;
    this.fieldGate = gateDraftOf(field.gate);
    this.fieldGateAnd = gateDraftOf(field.gate === undefined ? undefined : field.gate.and);
    this.fieldNamed = namedDraftsOf(field);
    this.fieldOpen = true;
  }

  private commitField(): void {
    const field: SignatureDecodeField = new SignatureDecodeField();
    field.id = this.fieldId.trim().length > 0 ? this.fieldId.trim() : 'field-' + (this.decodeFields.length + 1).toString();
    field.label = this.fieldLabel.trim().length > 0 ? this.fieldLabel.trim() : field.id;
    field.offset = toInt(this.fieldOffset, 0);
    field.length = toInt(this.fieldLength, 1);
    field.type = this.fieldType;
    field.endian = this.fieldEndian;
    field.unit = this.fieldUnit.trim();
    field.live = this.fieldLive;
    field.gate = whenOf(this.fieldGate, whenOf(this.fieldGateAnd, undefined));
    const labels: Map<string, string> = new Map<string, string>();
    const notes: Map<string, string> = new Map<string, string>();
    const emphasis: string[] = [];
    this.fieldNamed.forEach((row: NamedValueDraft): void => {
      const key: string = row.key.trim();
      if (key.length === 0) return;
      labels.set(key, row.label.trim().length > 0 ? row.label.trim() : key);
      if (row.note.trim().length > 0) notes.set(key, row.note.trim());
      if (row.strong) emphasis.push(key);
    });
    if (labels.size > 0) {
      field.enumLabels = labels;
      field.enumNotes = notes.size > 0 ? notes : undefined;
      field.liveEmphasis = emphasis;
    }
    const next: SignatureDecodeField[] = this.decodeFields.slice();
    if (this.fieldIndex >= 0 && this.fieldIndex < next.length) next[this.fieldIndex] = field;
    else next.push(field);
    this.decodeFields = next;
    this.fieldOpen = false;
  }

  private deleteField(): void {
    if (this.fieldIndex < 0) return;
    this.decodeFields = this.decodeFields.filter((item: SignatureDecodeField, index: number): boolean => index !== this.fieldIndex);
    this.fieldOpen = false;
  }

  @Builder
  private buildGateSection() {
    Column({ space: 8 }) {
      Row() { Text($r('app.string.fieldwatch_editor_gate')).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.fieldGate.enabled }).onChange((value: boolean): void => { this.fieldGate.enabled = value; }) }.width('100%')
      Text($r('app.string.fieldwatch_editor_gate_hint')).fontSize(11).fontColor($r('app.color.text_secondary'))
      if (this.fieldGate.enabled) {
        this.buildGateEditor(this.fieldGate, false)
        Row() { Text($r('app.string.fieldwatch_editor_gate_and')).fontSize(13).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.fieldGateAnd.enabled }).onChange((value: boolean): void => { this.fieldGateAnd.enabled = value; }) }.width('100%')
        if (this.fieldGateAnd.enabled) { this.buildGateEditor(this.fieldGateAnd, true) }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildGateEditor(draft: GateDraft, isAnd: boolean) {
    Column({ space: 6 }) {
      Text($r('app.string.fieldwatch_editor_gate_op')).fontSize(12).fontColor($r('app.color.text_secondary'))
      Scroll() {
        Row({ space: 8 }) {
          ForEach(GATE_OPS, (item: SignatureDecodeWhenOp): void => {
            FieldwatchSegmentedChip({ label: item, selected: draft.op === item,
              onTap: (): void => { draft.op = item; this.touchGate(isAnd); } })
          }, (item: SignatureDecodeWhenOp): string => item)
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%')
      Row({ space: 8 }) {
        TextInput({ text: draft.offset, placeholder: $r('app.string.fieldwatch_editor_field_offset') }).type(InputType.Number).height(40).layoutWeight(1).onChange((value: string): void => { draft.offset = value; this.touchGate(isAnd); })
        TextInput({ text: draft.length, placeholder: $r('app.string.fieldwatch_editor_field_length') }).type(InputType.Number).height(40).layoutWeight(1).onChange((value: string): void => { draft.length = value; this.touchGate(isAnd); })
      }.width('100%')
      TextInput({ text: draft.valueHex, placeholder: $r('app.string.fieldwatch_editor_gate_value') }).height(40).onChange((value: string): void => { draft.valueHex = value; this.touchGate(isAnd); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private touchGate(isAnd: boolean): void {
    if (isAnd) this.fieldGateAnd = this.fieldGateAnd;
    else this.fieldGate = this.fieldGate;
  }

  @Builder
  private buildNamedValueSection() {
    Column({ space: 8 }) {
      Row() {
        Text(this.text('app.string.fieldwatch_editor_named_values') + ' (' + this.fieldNamed.length.toString() + ')').fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button($r('app.string.fieldwatch_editor_add_named')).height(36).onClick((): void => {
          const next: NamedValueDraft[] = this.fieldNamed.slice();
          next.push(new NamedValueDraft());
          this.fieldNamed = next;
        })
      }.width('100%')
      Text($r('app.string.fieldwatch_editor_named_hint')).fontSize(11).fontColor($r('app.color.text_secondary'))
      ForEach(this.fieldNamed, (row: NamedValueDraft, index: number): void => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            TextInput({ text: row.key, placeholder: $r('app.string.fieldwatch_editor_named_key') }).height(38).layoutWeight(1).onChange((value: string): void => { this.updateNamed(index, value, undefined, undefined, undefined); })
            TextInput({ text: row.label, placeholder: $r('app.string.fieldwatch_editor_named_label') }).height(38).layoutWeight(1).onChange((value: string): void => { this.updateNamed(index, undefined, value, undefined, undefined); })
          }.width('100%')
          Row({ space: 8 }) {
            TextInput({ text: row.note, placeholder: $r('app.string.fieldwatch_editor_named_note') }).height(38).layoutWeight(1).onChange((value: string): void => { this.updateNamed(index, undefined, undefined, undefined, value); })
            Text($r('app.string.fieldwatch_editor_named_strong')).fontSize(12)
            Toggle({ type: ToggleType.Switch, isOn: row.strong }).onChange((value: boolean): void => { this.updateNamed(index, undefined, undefined, value, undefined); })
            Button($r('app.string.fieldwatch_editor_cancel')).height(36).onClick((): void => {
              this.fieldNamed = this.fieldNamed.filter((item: NamedValueDraft, position: number): boolean => position !== index);
            })
          }.width('100%')
        }.width('100%').padding(8).backgroundColor($r('app.color.background_secondary')).borderRadius(8)
      }, (row: NamedValueDraft, index: number): string => index.toString() + row.key)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private updateNamed(index: number, key: string | undefined, label: string | undefined, strong: boolean | undefined, note: string | undefined): void {
    const next: NamedValueDraft[] = [];
    this.fieldNamed.forEach((row: NamedValueDraft, position: number): void => {
      if (position !== index) { next.push(row); return; }
      next.push(new NamedValueDraft(
        key === undefined ? row.key : key,
        label === undefined ? row.label : label,
        strong === undefined ? row.strong : strong,
        note === undefined ? row.note : note
      ));
    });
    this.fieldNamed = next;
  }

  @Builder
  private buildFieldSheet() {
    Scroll() {
      Column({ space: 10 }) {
        Text(this.fieldIndex >= 0 ? $r('app.string.fieldwatch_editor_edit_field') : $r('app.string.fieldwatch_editor_add_field')).fontSize(20).fontWeight(FontWeight.Bold)
        TextInput({ text: this.fieldId, placeholder: $r('app.string.fieldwatch_editor_field_id') }).height(42).onChange((value: string): void => { this.fieldId = value; })
        TextInput({ text: this.fieldLabel, placeholder: $r('app.string.fieldwatch_editor_field_label') }).height(42).onChange((value: string): void => { this.fieldLabel = value; })
        Row({ space: 8 }) {
          TextInput({ text: this.fieldOffset, placeholder: $r('app.string.fieldwatch_editor_field_offset') }).type(InputType.Number).height(42).layoutWeight(1).onChange((value: string): void => { this.fieldOffset = value; })
          TextInput({ text: this.fieldLength, placeholder: $r('app.string.fieldwatch_editor_field_length') }).type(InputType.Number).height(42).layoutWeight(1).onChange((value: string): void => { this.fieldLength = value; })
        }.width('100%')
        Text($r('app.string.fieldwatch_editor_field_type')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Scroll() {
          Row({ space: 8 }) {
            ForEach(DECODE_TYPES, (item: SignatureDecodeType): void => {
              FieldwatchSegmentedChip({ label: item, selected: this.fieldType === item, onTap: (): void => { this.fieldType = item; } })
            }, (item: SignatureDecodeType): string => item)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).width('100%')
        Text($r('app.string.fieldwatch_editor_field_endian')).fontSize(14).fontColor($r('app.color.text_secondary'))
        Row({ space: 8 }) {
          FieldwatchSegmentedChip({ label: 'le', selected: this.fieldEndian === SignatureDecodeEndian.LE, onTap: (): void => { this.fieldEndian = SignatureDecodeEndian.LE; } })
          FieldwatchSegmentedChip({ label: 'be', selected: this.fieldEndian === SignatureDecodeEndian.BE, onTap: (): void => { this.fieldEndian = SignatureDecodeEndian.BE; } })
        }.width('100%')
        TextInput({ text: this.fieldUnit, placeholder: $r('app.string.fieldwatch_editor_field_unit') }).height(42).onChange((value: string): void => { this.fieldUnit = value; })
        Row() { Text($r('app.string.fieldwatch_editor_field_live')).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.fieldLive }).onChange((value: boolean): void => { this.fieldLive = value; }) }.width('100%')
        this.buildGateSection()
        this.buildNamedValueSection()
        Row({ space: 8 }) {
          Button($r('app.string.fieldwatch_editor_ok')).height(44).layoutWeight(1).onClick((): void => { this.commitField(); })
          if (this.fieldIndex >= 0) Button($r('app.string.fieldwatch_editor_delete_field')).height(44).layoutWeight(1).onClick((): void => { this.deleteField(); })
        }.width('100%')
      }.width('100%').padding(20)
    }.width('100%').height('100%')
  }
}
