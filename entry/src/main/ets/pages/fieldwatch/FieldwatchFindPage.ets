import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FindCandidate, FIND_TROUBLE_AFTER_MS, FIND_WIGGLE_SPREAD_DB, FIND_WIGGLE_WINDOW_MS, findTroubleKeys } from '../../fieldwatch/domain/FieldwatchFindModel';
import { HuntCue, HuntSession, huntCueKey, huntCueLevel, huntRecentSpread } from '../../fieldwatch/domain/FieldwatchHunt';
import { FieldwatchHuntCombinedFeedback, IFieldwatchHuntFeedback } from '../../fieldwatch/platform/FieldwatchHuntFeedback';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/** 顶栏沉浸底板高度，与关注列表 / 特征详情同值。 */
const FIND_UNDERLAY_HEIGHT: number = 168;
/** 点击预算验收用的常量：首页 → 找东西 → 点设备 → 向导，认领与进入合并为一步。 */
const FIND_REFRESH_MS: number = 1000;

/**
 * 找东西（日常版）。
 *
 * **判定逻辑零重写**：状态机直接用 `FieldwatchHunt.huntCue()` 的七态，
 * 声震反馈直接用 `FieldwatchHuntFeedback`，会话用应用层那一个 `HuntSession`。
 * 本页只做三件事 —— 把七态翻译成人话、把响度画成热度条、给一个「找到了」。
 *
 * 术语红线：本页不出现 RSSI / dBm / MAC / 广播 / 签名。热度条从 `huntCueLevel` 取档，
 * 不显示任何 dBm 数值；「上次见到」只给相对时间。
 *
 * 点击预算（A.4 上线门禁）：
 *   - 首次认领 ≤3 次：首页「找东西」(1) → 点设备名 (2) → 向导自动开扫；
 *     已配对设备在列表里点一下即认领 + 进入，不额外增加一步。
 *   - 再次找 ≤2 次：首页「找东西」(1) → 点已认领设备 (2)。
 *   - 过程中零决策点：没有「要不要继续」之类的问句，只有「找到了」。
 */
@Component
export struct FieldwatchFindPage {
  /** 是否自带 HDS 顶栏（路由目标页）。 */
  withShell: boolean = true;
  /** 顶部系统安全区高度（vp）。 */
  topInset: number = 0;
  /** 关闭页面。 */
  onClose: () => void = (): void => {};
  /** true = 正在向导里找；false = 选设备列表。 */
  @State private guiding: boolean = false;
  /** 向导目标名（已翻译好的人话，直接渲染）。 */
  @State private targetLabel: string = '';
  @State private targetKey: string = '';
  @State private cue: HuntCue = HuntCue.WAITING;
  /** 向导开始的时刻；用于 WAITING 超时判定。 */
  @State private guideStartedAt: number = 0;
  /** WAITING 是否已超时（超过 10 秒无任何包）。 */
  @State private troubleOpen: boolean = false;
  /** 是否显示「同名多台，晃一晃确认」提示。 */
  @State private wiggleHint: boolean = false;
  /** 声震开关：会话级，默认全开（A.4「声震开关是唯一可选项且默认全开」）。 */
  @State private soundOn: boolean = true;
  @State private vibrateOn: boolean = true;
  @State private pulseScale: number = 1;
  /**
   * 候选列表快照。
   *
   * **不能在 build 里现算**：`findCandidates()` 会去问系统配对名单（同步 IPC），
   * 而 ArkUI 的 build 每秒可能被调用多次 —— 在渲染路径里做 IPC 会直接卡帧。
   * 这里只在定时刷新与进入页面时各算一次。
   */
  @State private candidates: FindCandidate[] = [];
  /** 定时器计数：候选列表按 3 秒一次重算，见 `refresh()`。 */
  private refreshTick: number = 0;
  @State private soundSupported: boolean = false;
  @State private hapticSupported: boolean = false;
  private readonly feedback: IFieldwatchHuntFeedback = new FieldwatchHuntCombinedFeedback();
  private refreshTimer: number = -1;
  private tickTimer: number = -1;

  aboutToAppear(): void {
    void fieldwatchApplication.ensureOwnDevicesLoaded();
    this.hapticSupported = this.feedback.hapticAvailable();
    void this.feedback.prepare().then((): void => { this.soundSupported = this.feedback.soundAvailable(); });
    // 首帧就要有内容：等第一次定时器触发会白屏一秒。
    void fieldwatchApplication.ensureOwnDevicesLoaded().then((): void => {
      this.candidates = fieldwatchApplication.findCandidates();
    });
    this.candidates = fieldwatchApplication.findCandidates();
    this.refreshTimer = setInterval((): void => { this.refresh(); }, FIND_REFRESH_MS);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    this.clearTick();
    this.feedback.release();
    // 离开页面时结束会话：否则这一次搜寻会一直挂在应用层，回来时接着算。
    if (this.guiding) fieldwatchApplication.stopHunt();
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(FIND_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  private refresh(): void {
    if (!this.guiding) {
      // 候选列表**不每秒重算**：`findCandidates()` 会同步问一次系统配对名单（IPC），
      // 一秒一次在滚动时会明显掉帧。3 秒一次对「刚认领完回来能看到」已经足够快。
      this.refreshTick += 1;
      if (this.refreshTick % 3 === 0) this.candidates = fieldwatchApplication.findCandidates();
      return;
    }
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) { this.cue = HuntCue.GONE; return; }
    this.cue = fieldwatchApplication.huntCueNow();
    // WAITING 超时展开排查卡：只判「还没收到任何包」这一种，
    // QUIET（听到过又断了）已经有一句专门的人话，不需要再叠排查卡。
    if (!this.troubleOpen && this.cue === HuntCue.WAITING
      && Date.now() - this.guideStartedAt >= FIND_TROUBLE_AFTER_MS) {
      this.troubleOpen = true;
    }
    this.checkWiggle(session);
    this.armTick();
  }

  /**
   * 同名多台的「晃一晃确认」。
   *
   * 只在**候选不唯一**时提示：唯一的设备不需要让用户晃。
   * 判定用的是最近 3 秒内的极差 —— 拿起来晃动会让强度剧烈起伏，
   * 静止设备不会。这只是提示，不改变任何匹配结论（认错设备的代价由 matcher 兜）。
   */
  private checkWiggle(session: HuntSession): void {
    // 每次刷新都重算一次：用户可能刚好把另一台同名设备拿走了。
    this.wiggleHint = fieldwatchApplication.findTargetIsAmbiguous();
    if (!this.wiggleHint) return;
    const spread: number = huntRecentSpread(session.samples, Date.now(), FIND_WIGGLE_WINDOW_MS);
    if (spread >= FIND_WIGGLE_SPREAD_DB) {
      // 抖起来了：给出「就是这台」的确认，不自动替用户做任何事。
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_find_wiggle_confirmed'),
        duration: 2000
      });
      this.wiggleHint = false;
    }
  }

  private clearTick(): void {
    if (this.tickTimer >= 0) { clearTimeout(this.tickTimer); this.tickTimer = -1; }
  }

  private armTick(): void {
    this.clearTick();
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) return;
    const interval: number = huntTickMsOf(this.cue);
    if (interval < 0) return;
    this.tickTimer = setTimeout((): void => { this.fireTick(); }, interval);
  }

  /** 一次反馈：声、震、脉冲三通道并行（A.4 无障碍要求，不能只靠颜色）。 */
  private fireTick(): void {
    this.tickTimer = -1;
    if ((this.soundOn || this.vibrateOn)) {
      if (this.soundOn && this.soundSupported) this.feedback.tick(20);
      else if (this.vibrateOn && this.hapticSupported) this.feedback.tick(20);
    }
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, (): void => { this.pulseScale = 1.22; });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, (): void => { this.pulseScale = 1; });
    }, 90);
    this.armTick();
  }

  /** 用户点了某台设备：先认领（若是配对名单来的），再开找。一次点击做两件事。 */
  private pick(candidate: FindCandidate): void {
    if (!candidate.claimed()) {
      const claimed: boolean = fieldwatchApplication.claimOwnDevice(candidate.deviceKey, candidate.address, candidate.name);
      if (!claimed) {
        this.getUIContext().getPromptAction().showToast({
          message: this.text('app.string.fieldwatch_find_claim_failed'),
          duration: 2000
        });
        return;
      }
    }
    if (!fieldwatchApplication.startHuntByKey(candidate.deviceKey)) {
      // 还没听到它：不能说「找不到」，只能说「现在还没听到」。
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_find_not_heard'),
        duration: 2500
      });
      return;
    }
    this.guiding = true;
    // 认领后列表变了（多了一条「我的设备」），回到列表时要立刻看到。
    this.candidates = fieldwatchApplication.findCandidates();
    this.targetLabel = candidate.name.length > 0 ? candidate.name : this.text('app.string.fieldwatch_find_unnamed');
    this.targetKey = candidate.deviceKey;
    this.guideStartedAt = Date.now();
    this.troubleOpen = false;
    this.cue = fieldwatchApplication.huntCueNow();
    this.armTick();
  }

  /** 「找到了」：收尾 -> 回列表。这是全流程唯一的决策点。 */
  private finishFound(): void {
    fieldwatchApplication.stopHunt();
    this.clearTick();
    this.guiding = false;
    this.troubleOpen = false;
    this.getUIContext().getPromptAction().showToast({
      message: this.text('app.string.fieldwatch_find_found_toast'),
      duration: 1800
    });
  }

  private backToList(): void {
    fieldwatchApplication.stopHunt();
    this.clearTick();
    this.guiding = false;
    this.troubleOpen = false;
  }

  /** 纠错：「这不是我的」——把当前目标移出认领，并把它这次的长相记进黑名单。 */
  private notMine(): void {
    fieldwatchApplication.denyOwnDevice(this.targetKey);
    this.backToList();
    this.getUIContext().getPromptAction().showToast({
      message: this.text('app.string.fieldwatch_find_denied_toast'),
      duration: 2000
    });
  }

  private cueColor(): string {
    const level: number = huntCueLevel(this.cue);
    if (level >= 3) return FieldwatchPaletteHolder.get().huntVeryClose;
    if (level === 2) return FieldwatchPaletteHolder.get().huntCloser;
    if (level === 1) return FieldwatchPaletteHolder.get().huntSame;
    return FieldwatchPaletteHolder.get().huntFar;
  }

  build() {
    if (this.withShell) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.TopStart }) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              FIND_UNDERLAY_HEIGHT)
          })
          if (this.guiding) this.buildGuide()
          else this.buildList()
        }.width('100%').height('100%')
      }
      .titleBar(NGFHdsTitleBarOptionsFactory.build(
        $r('app.string.fieldwatch_find_title'),
        this.guiding ? this.targetLabel : $r('app.string.fieldwatch_find_subtitle'),
        FieldwatchPaletteHolder.get().night,
        hdsMaterial.MaterialLevel.GENTLE,
        true,
        false
      ))
      .onBackPressed((): boolean => {
        if (this.guiding) { this.backToList(); return true; }
        this.onClose();
        return true;
      })
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    } else {
      if (this.guiding) this.buildGuide()
      else this.buildList()
    }
  }

  // ── 列表：认领区 + 已认领 + 最近听到 ──
  @Builder
  private buildList() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.candidates.length === 0) this.buildEmpty()
        else {
          ForEach(this.candidates, (item: FindCandidate): void => {
            this.buildCandidateRow(item)
          }, (item: FindCandidate): string => item.deviceKey + '|' + item.source)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildEmpty() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.dot_radiowaves')).fontSize(40)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
      Text($r('app.string.fieldwatch_find_empty')).fontSize(15)
        .fontColor(FieldwatchPaletteHolder.get().text).textAlign(TextAlign.Center)
      Text($r('app.string.fieldwatch_find_empty_hint')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ top: 60, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 一行候选。
   *
   * 已认领 / 已配对 / 最近听到三种来源用**同一行样式**，只用右侧小字区分来源：
   * 三套样式会让用户以为它们是三种不同的东西，而这一步的目标只有一个 —— 点一下。
   */
  @Builder
  private buildCandidateRow(item: FindCandidate) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right')).fontSize(20)
          .fontColor([item.claimed() ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
      }
      .width(44).height(44).borderRadius(14)
      .backgroundColor(FieldwatchPaletteHolder.get().badgeBg)

      Column({ space: 3 }) {
        Text(item.name.length > 0 ? item.name : this.text('app.string.fieldwatch_find_unnamed')).fontSize(16)
          .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.sourceLabel(item))
          .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text(item.claimed() ? $r('app.string.fieldwatch_find_start') : $r('app.string.fieldwatch_find_claim_action'))
        .fontSize(13).fontColor(FieldwatchPaletteHolder.get().accent)
    }
    .width('100%').padding(14)
    .borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => { this.pick(item); })
  }

  private sourceLabel(item: FindCandidate): string {
    if (item.claimed()) return this.text('app.string.fieldwatch_find_source_own');
    if (item.source === 'paired') {
      return item.inUse ? this.text('app.string.fieldwatch_find_source_paired_in_use')
        : this.text('app.string.fieldwatch_find_source_paired');
    }
    return this.text('app.string.fieldwatch_find_source_scan');
  }

  // ── 向导 ──
  @Builder
  private buildGuide() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildHeat()
        Text(this.text('app.string.fieldwatch_find_cue_' + huntCueKey(this.cue)))
          .fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().headerText)
          .width('100%').textAlign(TextAlign.Center)
        if (this.cue === HuntCue.GONE || this.cue === HuntCue.QUIET) this.buildLastSeen()
        if (this.troubleOpen) this.buildTrouble()
        if (this.wiggleHint) this.buildWiggle()
        this.buildSwitches()
        FieldwatchButton({
          label: $r('app.string.fieldwatch_find_found'),
          tone: FieldwatchButtonTone.PRIMARY,
          onTap: (): void => { this.finishFound(); }
        })
        FieldwatchButton({
          label: $r('app.string.fieldwatch_find_not_mine'),
          tone: FieldwatchButtonTone.OUTLINE,
          compact: true,
          onTap: (): void => { this.notMine(); }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 热度条：**不显示任何 dBm**。
   *
   * 四档（远 / 近一些 / 很近 / 就在旁边）由 `huntCueLevel` 决定，
   * 同时用「段数 + 颜色 + 中间大字」三通道表达（A.4：热度不能只靠颜色）。
   */
  @Builder
  private buildHeat() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(210).height(210).fillOpacity(0.10).fill(this.cueColor())
          .scale({ x: this.pulseScale, y: this.pulseScale })
        Circle().width(160).height(160).fillOpacity(0.20).fill(this.cueColor())
        Column({ space: 6 }) {
          Text(this.heatLabel()).fontSize(28).fontWeight(FontWeight.Bold)
            .fontColor(FieldwatchPaletteHolder.get().headerText)
          Text($r('app.string.fieldwatch_find_heat')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }
      }
      .width('100%').height(230)

      Row({ space: 6 }) {
        ForEach([0, 1, 2, 3], (level: number): void => {
          Row()
            .height(8).layoutWeight(1).borderRadius(4)
            .backgroundColor(huntCueLevel(this.cue) >= level ? this.cueColor() : FieldwatchPaletteHolder.get().outline)
            .animation({ duration: 200, curve: Curve.EaseOut })
        }, (level: number): string => level.toString())
      }.width('100%')
    }
    .width('100%').padding({ top: 8, bottom: 4 })
  }

  private heatLabel(): string {
    const level: number = huntCueLevel(this.cue);
    if (level >= 3) return this.text('app.string.fieldwatch_find_heat_very_high');
    if (level === 2) return this.text('app.string.fieldwatch_find_heat_high');
    if (level === 1) return this.text('app.string.fieldwatch_find_heat_mid');
    return this.text('app.string.fieldwatch_find_heat_low');
  }

  /** GONE / QUIET 时给「上次见到」，但**不说丢了**（A.4 原文）。 */
  @Builder
  private buildLastSeen() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.clock')).fontSize(14)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
      Text(fieldwatchApplication.findLastSeenText(this.targetKey))
        .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
    }
    .width('100%').padding(12)
    .borderRadius(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  /** 排查卡：最多三条，按目标类型给第三条。 */
  @Builder
  private buildTrouble() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_find_trouble_title')).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().headerText)
      ForEach(findTroubleKeys(fieldwatchApplication.findTargetKind(this.targetKey)), (key: string): void => {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.info_circle')).fontSize(13)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text($r(key)).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        }.width('100%')
      }, (key: string): string => key)
    }
    .width('100%').padding(14).alignItems(HorizontalAlign.Start)
    .borderRadius(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  @Builder
  private buildWiggle() {
    Row({ space: 8 }) {
      // 符号必须取自 SystemSymbolCatalog 的实有名单：`hand_raised` 不在其中（编译期 10903329）。
      // `hand_raised_fingers_spread` 是「举手/拿起」语义里最接近「拿起你的那台」的一枚。
      SymbolGlyph($r('sys.symbol.hand_raised_fingers_spread')).fontSize(14)
        .fontColor([FieldwatchPaletteHolder.get().warn])
      Text($r('app.string.fieldwatch_find_wiggle')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().warn).layoutWeight(1)
    }
    .width('100%').padding(12)
    .borderRadius(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
  }

  /** 声震开关：唯一可选项，默认全开。 */
  @Builder
  private buildSwitches() {
    Column({ space: 4 }) {
      Row() {
        Text($r('app.string.fieldwatch_find_sound')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.soundOn })
          .enabled(this.soundSupported)
          .onChange((value: boolean): void => { this.soundOn = value; })
      }.width('100%')
      Row() {
        Text($r('app.string.fieldwatch_find_vibrate')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vibrateOn })
          .enabled(this.hapticSupported)
          .onChange((value: boolean): void => { this.vibrateOn = value; })
      }.width('100%')
    }
    .width('100%')
  }
}

/**
 * 档位 → 节拍间隔。
 *
 * **不复用 `huntTickIntervalMs`**：那个函数按 dBm 线性映射（专业版要「离得越近滴得越急」的
 * 连续感），而日常版手里只有档位、没有 dBm（也不能显示它）。
 * 这里用四档固定节奏，节奏差异比连续映射更易读，也不会因为一次野值突然乱跳。
 */
function huntTickMsOf(cue: HuntCue): number {
  const level: number = huntCueLevel(cue);
  if (cue === HuntCue.QUIET || cue === HuntCue.GONE) return -1;
  if (level >= 3) return 160;
  if (level === 2) return 380;
  if (level === 1) return 760;
  return 1200;
}
