import { logger, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FieldwatchOwnDeviceRepository } from '../../fieldwatch/data/FieldwatchOwnDeviceRepository';
import { probeOf } from '../../fieldwatch/domain/FieldwatchOwnDeviceMatcher';
import { OwnDevice, OwnDeviceFingerprint } from '../../fieldwatch/domain/FieldwatchOwnDevice';
import {
  HUNT_WIFI_WINDOWS, HuntCue, HuntSample, HuntSession, huntCue, huntCueKey, huntCueLevel, huntTickIntervalMs
} from '../../fieldwatch/domain/FieldwatchHunt';
import { claimKeyOf } from '../../fieldwatch/domain/FieldwatchFindClaim';
import { RadioFacts, RadioKind, RadioRssiSample, ScanObservation, Sighting } from '../../fieldwatch/domain/FieldwatchModels';
import {
  decideShaken, ShakeCandidate, ShakeDecision, ShakeSample, scoreShake,
  SHAKE_MIN_SPREAD_DB, staticStrongSuspect
} from '../../fieldwatch/domain/FieldwatchShakeConfirm';
import { IFieldwatchHuntFeedback, FieldwatchHuntCombinedFeedback } from '../../fieldwatch/platform/FieldwatchHuntFeedback';
import { FieldwatchButton, FieldwatchButtonTone } from './FieldwatchButton';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';
import { fieldwatchText } from './FieldwatchResText';

const TAG: string = 'FieldwatchFindWizard';

/** 「还没收到任何数据包」出现多久后展开排查卡（文档 §7.2：超 10 秒）。 */
const FIND_HELP_AFTER_MS: number = 10000;
/** 「非常近」的长震时长。 */
const FIND_VERY_CLOSE_HAPTIC_MS: number = 120;
/** 常规节拍时长（与专业页一致）。 */
const FIND_TICK_MS: number = 22;
/** 未测量标记：与 `HUNT_DIRECTION_INVALID_RSSI` 同值，表示「还没有样本」。 */
const RSSI_UNMEASURED: number = 127;

/**
 * 寻找向导 —— 专业 Hunt 页的**日常翻译版**。
 *
 * 依据：`docs/Fieldwatch找东西深度落地.md` 落地点六与 §7.2/§7.4。
 *
 * **判定逻辑零重写**：七态判据、盖革滴答间隔、「非常近」阈值全部来自 Hunt 领域层
 * （`huntCue()` / `huntTickIntervalMs()` / `HUNT_VERY_CLOSE_DBM`），本组件只做三件事：
 * 大号三通道热度（颜色 + 字号 + 声震）、一句人话、排查卡。
 * 阈值以后调整，专业页与这里会一起变。
 *
 * **不显示任何数字**：没有 dBm、没有 RSSI、没有米数 —— 日常用户看不懂，
 * 而且数字会诱使他把注意力放在「数变了多少」而不是「走向哪边」。
 */
@Component
export struct FieldwatchFindWizard {
  /** 要找的那台自有设备。 */
  @Prop device: OwnDevice = new OwnDevice();
  /** 它此刻是不是正连着这台手机（父层每 2 秒刷新传入）。 */
  @Prop connected: boolean = false;
  /** 结束寻找（找到或放弃都走这里）。 */
  onClose: (found: boolean) => void = (found: boolean): void => {};

  @State private cue: HuntCue = HuntCue.WAITING;
  @State private pulseScale: number = 1;
  @State private elapsedMs: number = 0;
  @State private beep: boolean = true;
  @State private vibrate: boolean = true;
  /** 是否已经拿到过任何样本（决定要不要展开排查卡）。 */
  @State private hasSamples: boolean = false;
  @State private lastSeenAt: number = 0;
  /** 刚排除过一台（显示一次提示）。 */
  @State private excluded: boolean = false;
  /** 信号又强又不动 —— 提示「可能是别的同款设备」（文档 §7.3，只提示不断言）。 */
  @State private staticSuspect: boolean = false;

  private readonly feedback: IFieldwatchHuntFeedback = new FieldwatchHuntCombinedFeedback();
  private readonly repository: FieldwatchOwnDeviceRepository = new FieldwatchOwnDeviceRepository();
  private refreshTimer: number = -1;
  private tickTimer: number = -1;
  private startedAt: number = 0;
  private tickSupported: boolean = false;
  /** 已经尝试过的观测 key（避免同一次寻找反复重启会话）。 */
  private boundKey: string = '';
  /** 上一秒的状态：用来做「刚进入非常近」的边沿触发（长震只震一次）。 */
  private lastCue: HuntCue = HuntCue.WAITING;
  /** 同名候选台数（0 表示没有同名台）。同名多台时不能替用户猜是哪一台。 */
  @State private sameNameCount: number = 0;
  /** 同名候选的观测（顺序稳定，UI 的「附近第 N 台」按它画）。 */
  private sameNameSightings: Sighting[] = [];
  /** 同名候选的晃动评估结果。 */
  @State private shakeRows: ShakeCandidate[] = [];
  /** 是否显示「晃一晃」确认卡。 */
  @State private showShakeCard: boolean = false;
  /** 已确认选中的候选 key（打勾用）；空串表示还没确认。 */
  @State private shakeResolvedKey: string = '';
  private shakeResolvedAt: number = 0;
  /**
   * 是否靠**名字**（而不是地址）绑上的。
   *
   * 这既是给用户的诚实说明（地址变了要讲清楚），也是文档 §八 V1 的真机判据：
   * 这句出现 = 配对地址与扫描地址**不同值**；不出现而样本照常进来 = 同值。
   */
  @State private matchedByName: boolean = false;
  /** 已经判定过一次 V1（配对地址是否等于扫描地址），只记一次日志。 */
  private v1Judged: boolean = false;

  aboutToAppear(): void {
    this.startedAt = Date.now();
    this.lastSeenAt = this.device.lastSeenAt;
    this.tickSupported = this.feedback.hapticAvailable();
    void this.feedback.prepare();
    const settings = fieldwatchApplication.getState().settings;
    this.beep = settings.huntBeep;
    this.vibrate = settings.huntVibrate;
    this.startSession();
    this.refreshTimer = setInterval((): void => { this.refresh(); }, 1000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    this.clearTick();
    // 会话由本组件负责收尾：不停止的话，离开后它还会一直吃样本。
    fieldwatchApplication.stopHunt();
    this.feedback.release();
  }

  /**
   * 开一次寻找会话。
   *
   * **能扫到就用真观测，扫不到就造一个「等信号」的会话**：
   * 寻找会话跟踪的是观测 key，而经典蓝牙配对设备未必会出现在 BLE 扫描里 ——
   * 没有真观测时不能就此认定「找不到」，而要让会话先等着，
   * 由 `refresh()` 在收到匹配观测时接管（这同时是 V1 证伪时的兜底路径）。
   */
  private startSession(): void {
    const key: string = claimKeyOf(this.device.kind, this.device.virtualAddress);
    this.boundKey = key;
    const live: Sighting | undefined = this.sightingOf(key);
    if (live !== undefined) {
      fieldwatchApplication.startHunt(live);
      this.hasSamples = live.rssiHistory.length > 0;
      return;
    }
    const facts: RadioFacts = new RadioFacts();
    const observation: ScanObservation = new ScanObservation(
      key, this.device.kind, this.device.virtualAddress, this.device.displayName, RSSI_UNMEASURED, Date.now(), facts);
    fieldwatchApplication.startHunt(Sighting.fromObservation(observation));
    this.hasSamples = false;
  }

  private sightingOf(key: string): Sighting | undefined {
    let found: Sighting | undefined = undefined;
    fieldwatchApplication.getState().sightings.forEach((item: Sighting): void => {
      if (found === undefined && item.key === key) found = item;
    });
    return found;
  }

  private refresh(): void {
    this.elapsedMs = Date.now() - this.startedAt;
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) return;
    this.cue = this.computeCue(session);
    // 边沿触发：刚进入「非常近」时给一次长震（§7.2「整屏变色 + 长震 + 大字」），
    // 而不是每秒都长震一次 —— 持续长震会让用户只想把手机放下。
    if (this.cue === HuntCue.VERY_CLOSE && this.lastCue !== HuntCue.VERY_CLOSE
      && this.vibrate && this.tickSupported) {
      this.feedback.tick(FIND_VERY_CLOSE_HAPTIC_MS);
    }
    this.lastCue = this.cue;
    this.staticSuspect = this.judgeStaticSuspect(session);
    if (session.samples.length > 0) this.hasSamples = true;
    if (session.lastSeen > 0) this.lastSeenAt = session.lastSeen;
    // 目标地址变了（或本来就是另一个随机地址）时，用指纹把会话重新绑到真观测上。
    this.rebindIfNeeded();
    this.backfillFromBoundSighting();
    this.updateShakeCard();
    this.armTick();
  }

  /**
   * 同名多台时的「晃一晃」确认（文档 §7.3）。
   *
   * 每秒评估一次：谁在动、动得够不够明显；判定唯一时立刻改绑到它，
   * 并让打勾停留三秒（用户要看到「刚才那下生效了」）。
   */
  private updateShakeCard(): void {
    if (this.sameNameSightings.length <= 1) {
      this.showShakeCard = false;
      return;
    }
    const now: number = Date.now();
    const rows: ShakeCandidate[] = [];
    this.sameNameSightings.forEach((item: Sighting): void => {
      const samples: ShakeSample[] = [];
      item.rssiHistory.forEach((sample: RadioRssiSample): void => {
        samples.push(new ShakeSample(sample.rssi, sample.at));
      });
      rows.push(scoreShake(item.key, samples, now));
    });
    this.shakeRows = rows;
    if (this.shakeResolvedKey.length > 0) {
      // 已确认：让 ✓ 停留约 3 秒再把卡片收掉。
      this.showShakeCard = now - this.shakeResolvedAt < 3000;
      return;
    }
    this.showShakeCard = true;
    const decision: ShakeDecision = decideShaken(rows);
    if (!decision.decided) return;
    const targets: Sighting[] = this.sameNameSightings.filter((item: Sighting): boolean => item.key === decision.key);
    if (targets.length === 0) return;
    this.shakeResolvedKey = decision.key;
    this.shakeResolvedAt = now;
    this.matchedByName = true;
    this.rebindTo(targets[0]);
  }

  /**
   * V1 兜底：地址对不上时，用指纹在实时观测里找这台设备，找到就把会话切过去，
   * 并把指纹回填进档案（下次就能直接靠指纹认出来）。
   */
  private rebindIfNeeded(): void {
    const sightings: Sighting[] = fieldwatchApplication.getState().sightings;
    // **用数组收集、再取第一个**，而不是「一个 let + 闭包里赋值」：
    // 后者会被 ArkTS 的类型收窄判成 `never`（闭包里的赋值不参与外部控制流分析），
    // `byAddress !== undefined` 的真分支于是访问不到任何属性。
    const addressHits: Sighting[] = [];
    const byName: Sighting[] = [];
    sightings.forEach((item: Sighting): void => {
      if (item.kind !== this.device.kind) return;
      // ① 地址直配（V1 成立时的主路径，也是配对名单内部的快速锚）。
      if (addressHits.length === 0 && item.address.length > 0 && item.address === this.device.virtualAddress) {
        addressHits.push(item);
      }
      // ② 同名候选（V1 **证伪**时的兜底：配对给的是虚拟地址，扫描给的是另一个地址，
      //    唯一还能对上的线索就是名字）。见 docs/Fieldwatch找东西深度落地.md §八 V1。
      if (this.device.displayName.length > 0 && item.name === this.device.displayName) byName.push(item);
    });
    this.sameNameCount = byName.length;
    this.sameNameSightings = byName;
    this.judgeV1(addressHits.length > 0, byName.length);
    if (addressHits.length > 0) {
      const hit: Sighting = addressHits[0];
      this.matchedByName = false;
      if (hit.key !== this.boundKey) this.rebindTo(hit);
      return;
    }
    // 只有**唯一**同名候选时才自动改绑：两台同名设备时替用户猜错，比找不到更糟
    // （文档 §7.3「同名多台」要求让用户确认，那个确认环节在下一轮补）。
    if (byName.length === 1) {
      this.matchedByName = true;
      this.rebindTo(byName[0]);
    }
  }

  /**
   * 记一次 V1 判定结果。
   *
   * 这是文档 §八 V1 的真机取证点：**「同名的有、同龄的没有」就是「配对地址 != 扫描地址」的直接证据**。
   * 只记一次，且只记判定结论与数量 —— 不打印任何地址（隐私底线）。
   */
  private judgeV1(addressHit: boolean, nameCount: number): void {
    if (this.v1Judged) return;
    if (!addressHit && nameCount === 0) return;
    this.v1Judged = true;
    logger.info(TAG, 'V1 判定: 目标=' + (this.device.displayName.length > 0 ? this.device.displayName : '(未命名)')
      + ' 地址直配=' + (addressHit ? '命中' : '未命中') + ' 同名候选=' + nameCount.toString());
  }

  /** 把会话改绑到真观测上，并把广播指纹回填进档案。 */
  private rebindTo(sighting: Sighting): void {
    this.boundKey = sighting.key;
    fieldwatchApplication.startHunt(sighting);
    this.hasSamples = sighting.rssiHistory.length > 0 || sighting.rssi > 0;
    this.backfillFingerprint(sighting);
  }

  /**
   * 只要当前绑定的 key 对应着**真观测**，就把它的指纹补进档案。
   *
   * **为什么不能只在改绑时回填**：V1 成立时走的是地址直配，key 一开始就相等 →
   * 永远不触发改绑 → 档案里的指纹一直是空的。这是拉取设备上的 `fieldwatch.db`
   * 直接看表才发现的（两条档案的 `fingerprint.name` 都是空串）：
   * 平时看不出问题，可一旦地址发生变化（V2 未证实 / 系统随机化），就无路可退。
   */
  private backfillFromBoundSighting(): void {
    if (this.device.fingerprint.name.length > 0) return;
    const hits: Sighting[] = fieldwatchApplication.getState().sightings.filter(
      (item: Sighting): boolean => item.key === this.boundKey);
    if (hits.length === 0) return;
    this.backfillFingerprint(hits[0]);
  }

  /** 用第一次真正扫到的广播回填指纹（认领时只有系统配对名，不能当指纹用）。 */
  private backfillFingerprint(sighting: Sighting): void {
    if (this.device.fingerprint.name.length > 0) return;
    const probe = probeOf(sighting);
    this.device.fingerprint.name = probe.name;
    this.device.fingerprint.manufacturerDataHex = probe.manufacturerDataHex;
    this.device.fingerprint.serviceUuids = probe.serviceUuids;
    this.device.fingerprint.signatureIds = probe.signatureIds;
    void this.repository.save(this.device);
  }

  /**
   * 取当前提示状态。
   *
   * **蓝牙走原路径**（应用层已经算好 missing：目标不在实时集合里就是 GONE）。
   *
   * **非蓝牙（Wi-Fi 等）自己算**，原因有两个：
   * ① 时间窗要按扫描节奏放宽（`HUNT_WIFI_WINDOWS`）—— 用 BLE 的 2/8 秒窗，
   *    两次扫描之间会一直显示「安静」，方向类状态永远出不来（真机实测：
   *    平板正连着路由器，向导却停在「暂时听不到它了」）；
   * ② `missing` 也不能用「在不在实时集合里」判：Wi-Fi 目标本来就会在两次扫描之间
   *    从集合里消失，那会把「刚扫过、只是还没到下一次」误报成 GONE（「它不在附近」）。
   *    这里改成「超过一个静默窗没样本才算不在」。
   */
  private computeCue(session: HuntSession): HuntCue {
    if (this.device.kind === RadioKind.BLE) return fieldwatchApplication.huntCueNow();
    const now: number = Date.now();
    const missing: boolean = session.lastSeen <= 0 || now - session.lastSeen > HUNT_WIFI_WINDOWS.quietMs;
    return huntCue(session.samples, now, session.lastSeen, missing, HUNT_WIFI_WINDOWS);
  }

  /**
   * 「很强但一直没变化」的怀疑判据（文档 §7.3）。
   *
   * 只对**蓝牙**目标用：Wi-Fi 目标本来就是固定路由器，「信号不动」是正常的，
   * 对它提示「可能是别的同款设备」纯属噪音。
   *
   * 也只在「非常近」时才提示 —— 文档举的例子就是「纹丝不动的最强信号贴在墙上」，
   * 中等强度下不动更像是你站着没走。
   *
   * **只提示、不断言**：固定设备与口袋里的设备在这一项上长得一样，
   * 唯一能分开的是让用户拿起来晃一晃（那就是上面的确认卡在做的事）。
   */
  private judgeStaticSuspect(session: HuntSession): boolean {
    if (this.device.kind !== RadioKind.BLE) return false;
    if (this.cue !== HuntCue.VERY_CLOSE) return false;
    const converted: ShakeSample[] = [];
    session.samples.forEach((sample: HuntSample): void => {
      converted.push(new ShakeSample(sample.rssi, sample.at));
    });
    return staticStrongSuspect(converted, Date.now());
  }

  private clearTick(): void {
    if (this.tickTimer >= 0) { clearTimeout(this.tickTimer); this.tickTimer = -1; }
  }

  /** 按当前响度重新安排下一次节拍；安静或消失时不排程（领域层返回负数）。 */
  private armTick(): void {
    this.clearTick();
    const session: HuntSession | undefined = fieldwatchApplication.getHunt();
    if (session === undefined) return;
    const interval: number = huntTickIntervalMs(session.lastRssi, this.cue);
    if (interval < 0) return;
    this.tickTimer = setTimeout((): void => { this.fireTick(); }, interval);
  }

  private fireTick(): void {
    this.tickTimer = -1;
    if ((this.beep || this.vibrate) && this.tickSupported) this.feedback.tick(FIND_TICK_MS);
    this.getUIContext().animateTo({ duration: 80, curve: Curve.EaseOut }, (): void => { this.pulseScale = 1.28; });
    setTimeout((): void => {
      this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseIn }, (): void => { this.pulseScale = 1; });
    }, 80);
    this.armTick();
  }

  private finish(found: boolean): void {
    if (found) {
      this.device.lastSeenAt = Date.now();
      void this.repository.save(this.device);
    }
    this.clearTick();
    fieldwatchApplication.stopHunt();
    this.feedback.release();
    this.onClose(found);
  }

  /**
   * 「这不是它」：把当前绑定的这台**指纹拉黑**，然后继续找别的。
   *
   * **只在这台是靠名字猜出来的情况下提供**（`matchedByName`）—— 那才是可能猜错的场景：
   * 地址直配成功时，地址相等就是同一台设备，用户说「不是」意味着认领错了设备，
   * 该改的是档案而不是指纹（那种情况请用「结束寻找」回列表重选）。
   *
   * 拉黑的指纹存在**档案**上（文档落地点五）：同一个「别人的同款耳机」以后不会再被认成我的。
   */
  private excludeCurrent(): void {
    const hits: Sighting[] = fieldwatchApplication.getState().sightings.filter(
      (item: Sighting): boolean => item.key === this.boundKey);
    if (hits.length > 0) {
      const probe = probeOf(hits[0]);
      const entry: OwnDeviceFingerprint = new OwnDeviceFingerprint();
      entry.name = probe.name;
      entry.manufacturerDataHex = probe.manufacturerDataHex;
      entry.serviceUuids = probe.serviceUuids;
      entry.signatureIds = probe.signatureIds;
      // 指纹全空就没有拉黑的意义（会退化成「把任何设备都当黑名单」）。
      if (entry.name.length > 0 || entry.manufacturerDataHex.length > 0) {
        this.device.denyFingerprints.push(entry);
        void this.repository.save(this.device);
      }
    }
    this.excluded = true;
    this.matchedByName = false;
    this.boundKey = '';
    this.shakeResolvedKey = '';
    this.sameNameCount = 0;
    this.sameNameSightings = [];
    this.hasSamples = false;
    this.startedAt = Date.now();
    this.startSession();
  }

  private toggleBeep(): void {
    this.beep = !this.beep;
    fieldwatchApplication.setHuntBeep(this.beep);
    if (this.beep) void this.feedback.prepare();
  }

  private toggleVibrate(): void {
    this.vibrate = !this.vibrate;
    fieldwatchApplication.setHuntVibrate(this.vibrate);
  }

  /**
   * 提示文案的资源键。
   *
   * 「非常近」那句默认是给**随身设备**写的（「就在你身上或包里」）—— 路由器、
   * 停着的车这类**不随身**的目标上它不成立（真机上给路由器加温到 VERY_CLOSE 时
   * 就显示了这句话）。所以只对这一种组合换文案，其余状态沿用同一套。
   */
  private hintKey(): string {
    if (this.cue === HuntCue.VERY_CLOSE && this.device.kind !== RadioKind.BLE) {
      return 'app.string.fieldwatch_find_hint_very_close_fixed';
    }
    return 'app.string.fieldwatch_find_hint_' + huntCueKey(this.cue);
  }

  /** 动态资源键解析（与专业 Hunt 页同一写法）。 */
  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private cueColor(): string {
    const level: number = huntCueLevel(this.cue);
    if (level >= 3) return FieldwatchPaletteHolder.get().huntVeryClose;
    if (level === 2) return FieldwatchPaletteHolder.get().huntCloser;
    if (level === 1) return FieldwatchPaletteHolder.get().warn;
    return FieldwatchPaletteHolder.get().huntFar;
  }

  /** 还没收到过任何包、且已经等了够久 —— 展开排查卡而不是让用户干等。 */
  private showHelp(): boolean {
    return !this.hasSamples && this.elapsedMs >= FIND_HELP_AFTER_MS;
  }

  build() {
    Column({ space: 16 }) {
      this.buildHeader()
      this.buildHeat()
      this.buildCue()
      if (this.showHelp()) this.buildHelpCard()
      if (this.staticSuspect) this.buildStaticSuspectHint()
      if (this.matchedByName) this.buildAddrChangedHint()
      if (this.showShakeCard) this.buildShakeCard()
      if (this.cue === HuntCue.GONE && this.lastSeenAt > 0) this.buildLastSeenCard()
      this.buildToggles()
      this.buildActions()
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    // 「非常近」时整屏变色（§7.2）：颜色本身就是一通道提示，不依赖读字。
    .backgroundColor(huntCueLevel(this.cue) >= 3
      ? FieldwatchPaletteHolder.get().huntVeryClose + '1A'
      : FieldwatchPaletteHolder.get().night)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildHeader() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.device.displayName.length > 0 ? this.device.displayName : fieldwatchText('app.string.fieldwatch_find_unnamed'))
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
        if (this.connected) {
          Text(fieldwatchText('app.string.fieldwatch_find_sub_connected')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().accent)
        }
        if (this.excluded) {
          Text(fieldwatchText('app.string.fieldwatch_find_excluded')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().warn)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      // 只有「靠名字猜中的」才给纠错入口：地址直配成功时不存在猜错的可能。
      if (this.matchedByName) {
        Text(fieldwatchText('app.string.fieldwatch_find_not_it')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().warn)
          .padding(8)
          .onClick((): void => { this.excludeCurrent(); })
      }
      Text(fieldwatchText('app.string.fieldwatch_find_close')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
        .padding(8)
        .onClick((): void => { this.finish(false); })
    }.width('100%').alignItems(VerticalAlign.Center)
  }

  /**
   * 热度：**用圈数表示强弱，不出现任何数字**（文档 §7.2 明确要求 CLOSER/FURTHER 不用数字）。
   *
   * 之前中心是一个 1/2/3 的阿拉伯数字 —— 那会被当成测量值读（「2 是什么意思」）。
   * 现在换成同心圆：热度越高，点亮的圈越多。
   *
   * 中心再叠一个**方向箭头**：方向原本只靠颜色区分，而颜色对色盲用户不友好；
   * 箭头把方向变成**形状**通道，与颜色、字号、声震并行（§7.4 三通道）。
   */
  @Builder
  private buildHeat() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(180).height(180)
        .fill(this.cueColor() + '22')
        .stroke(this.cueColor())
        .strokeWidth(2)
        .scale({ x: this.pulseScale, y: this.pulseScale })
      // 圈数 = 热度档位（1~3 圈），从外到内逐层点亮。
      //
      // 写成三个显式 `if` 而不是 `ForEach` 里套条件：列表内的条件渲染在这个仓库里
      // 没有真机验证过的先例，而三档本来就是固定的 —— 拆开更直观也更容易在真机上确认。
      if (huntCueLevel(this.cue) > 0) {
        Circle().width(140).height(140).fill(this.cueColor() + '66')
      }
      if (huntCueLevel(this.cue) > 1) {
        Circle().width(110).height(110).fill(this.cueColor() + '55')
      }
      if (huntCueLevel(this.cue) > 2) {
        Circle().width(80).height(80).fill(this.cueColor() + '44')
      }
      if (this.directionSymbol().length > 0) {
        SymbolGlyph($r(this.directionSymbol())).fontSize(46)
          .fontColor([FieldwatchPaletteHolder.get().onAccent])
      }
    }
    .width('100%').height(200).layoutWeight(0)
  }

  /** 方向符号：更近=上箭头、更远=下箭头、没变=等号；其余状态不显示（没有方向可言）。 */
  private directionSymbol(): string {
    if (this.cue === HuntCue.CLOSER) return 'sys.symbol.arrow_up';
    if (this.cue === HuntCue.FURTHER) return 'sys.symbol.arrow_down';
    if (this.cue === HuntCue.SAME) return 'sys.symbol.equal';
    return '';
  }

  @Builder
  private buildCue() {
    Column({ space: 8 }) {
      // 「非常近」用更大的字（§7.2：整屏变色 + 长震 + 大字）—— 它是唯一需要一眼扫到的状态。
      Text(this.text('app.string.fieldwatch_find_cue_' + huntCueKey(this.cue)))
        .fontSize(this.cue === HuntCue.VERY_CLOSE ? 38 : 30).fontWeight(FontWeight.Bold)
        .fontColor(this.cueColor())
      Text(this.text(this.hintKey()))
        .fontSize(15).textAlign(TextAlign.Center)
        .fontColor(FieldwatchPaletteHolder.get().text)
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  /** 排查卡：最多 3 条，按目标类型给可执行动作。 */
  @Builder
  private buildHelpCard() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_help_title')).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      ForEach(this.helpItems(), (item: ResourceStr): void => {
        Row({ space: 8 }) {
          Text('·').fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim)
          Text(item).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      }, (item: ResourceStr, index: number): string => index.toString())
    }
    .width('100%').padding(14).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 排查项：**最多 3 条**，按目标类型给动作。
   *
   * 第 3 条只在「曾经见到过」时才有意义 —— 没见过就无从「回到上次的地方」。
   */
  private helpItems(): ResourceStr[] {
    const items: ResourceStr[] = [];
    if (this.device.kind === RadioKind.BLE) {
      items.push(fieldwatchText('app.string.fieldwatch_find_help_wake'));
    } else {
      items.push(fieldwatchText('app.string.fieldwatch_find_help_wake_any'));
    }
    items.push(fieldwatchText('app.string.fieldwatch_find_help_power'));
    if (this.lastSeenAt > 0) items.push(fieldwatchText('app.string.fieldwatch_find_help_return'));
    // 纯 BLE 设备只有「在附近 / 上次见到」两态；经典配对设备可能根本不出现在扫描里，
    // 这时最有用的一句是「看它有没有连着这台手机」，而不是继续让他举着手机走。
    if (this.device.kind === RadioKind.BLE && !this.connected) {
      items.push(fieldwatchText('app.string.fieldwatch_find_help_connected'));
    }
    return items.slice(0, 3);
  }

  /**
   * 同名多台的提示。
   *
   * **不替用户猜**：同名设备靠指纹分不出，文档 §7.3 的做法是让用户「拿起目标晃一晃」，
   * 看哪一台的信号跟着动 —— 那个确认环节还没做，这里先如实说明现在有歧义。
   */
  /**
   * 「很强但一直没变化」的提示。
   *
   * 语气是**提示**不是结论：不写「这不是你的设备」，而是把观察说出来 + 给一个动作。
   */
  @Builder
  private buildStaticSuspectHint() {
    Text(fieldwatchText('app.string.fieldwatch_find_static_suspect'))
      .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      .width('100%').padding(12).borderRadius(12)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 地址和配对时不一样、改用名字找它了 —— 如实说明，不假装什么都没发生。 */
  @Builder
  private buildAddrChangedHint() {
    Text(fieldwatchText('app.string.fieldwatch_find_help_addr_changed'))
      .fontSize(12).fontColor(FieldwatchPaletteHolder.get().accent)
      .width('100%').padding(12).borderRadius(12)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /**
   * 「晃一晃」确认卡（文档 §7.3）。
   *
   * **不给用户看地址**（术语验收禁止 MAC 出现在日常页），也不让他对着尾号猜：
   * 他只需要拿起自己要找的那台晃一晃，动得最明显的那台会被打勾并自动成为目标。
   * 动感指示用**三条竖条**（长度 + 颜色两条通道），不显示任何数字。
   */
  @Builder
  private buildShakeCard() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_shake_title')).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text($r('app.string.fieldwatch_find_shake_hint', this.shakeRows.length))
        .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      ForEach(this.shakeRows, (row: ShakeCandidate, index: number): void => {
        this.buildShakeRow(row, index);
      }, (row: ShakeCandidate): string => row.key)
    }
    .width('100%').padding(14).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .border({ width: 1, color: FieldwatchPaletteHolder.get().warn })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildShakeRow(row: ShakeCandidate, index: number) {
    Row({ space: 10 }) {
      Text($r('app.string.fieldwatch_find_shake_row', index + 1)).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
      // 三条竖条：极差越大亮得越多（-1 = 还不能判断 → 全灭）。
      Row({ space: 3 }) {
        ForEach([0, 1, 2], (bar: number): void => {
          Row().width(4).height(8 + bar * 6).borderRadius(2)
            .backgroundColor(this.shakeLevel(row.spread) > bar
              ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().rssiTrack)
        }, (bar: number): string => bar.toString())
      }
      if (row.key === this.shakeResolvedKey) {
        // 勾是**无字**的，配一句话说清楚结果 —— 这条文案本来就是为了这个状态写的，
        // 但一直没接上（静态审计发现它是「没人引用的死资源」）。
        Text(fieldwatchText('app.string.fieldwatch_find_shake_confirmed')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().accent)
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(16)
          .fontColor([FieldwatchPaletteHolder.get().accent])
      }
    }
    .width('100%').constraintSize({ minHeight: 34 }).alignItems(VerticalAlign.Center)
  }

  /** 极差 → 亮几条竖条（0~3）。阈值与领域层同源，避免两处各写一套。 */
  private shakeLevel(spread: number): number {
    if (spread < 0) return 0;
    if (spread >= SHAKE_MIN_SPREAD_DB + 6) return 3;
    if (spread >= SHAKE_MIN_SPREAD_DB) return 2;
    if (spread >= SHAKE_MIN_SPREAD_DB / 2) return 1;
    return 0;
  }

  @Builder
  private buildLastSeenCard() {
    Column({ space: 4 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_last_seen_title')).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      Text(this.agoText(this.lastSeenAt)).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
    }
    .width('100%').padding(14).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .alignItems(HorizontalAlign.Start)
  }

  /** 声震开关：找的过程中唯一可选项，默认全开（§7.1）。 */
  @Builder
  private buildToggles() {
    Row({ space: 10 }) {
      this.buildToggle(fieldwatchText('app.string.fieldwatch_find_sound'), this.beep, (): void => { this.toggleBeep(); })
      this.buildToggle(fieldwatchText('app.string.fieldwatch_find_vibrate'), this.vibrate, (): void => { this.toggleVibrate(); })
    }.width('100%')
  }

  @Builder
  private buildToggle(label: ResourceStr, on: boolean, onTap: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph($r(on ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.circle'))
        .fontSize(16).fontColor([on ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
      Text(label).fontSize(13)
        .fontColor(on ? FieldwatchPaletteHolder.get().text : FieldwatchPaletteHolder.get().textDim)
    }
    .layoutWeight(1).constraintSize({ minHeight: 40 }).justifyContent(FlexAlign.Center)
    .borderRadius(10).backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => { onTap(); })
  }

  @Builder
  private buildActions() {
    Row({ space: 12 }) {
      FieldwatchButton({
        label: fieldwatchText('app.string.fieldwatch_find_found'),
        tone: FieldwatchButtonTone.PRIMARY,
        onTap: (): void => { this.finish(true); }
      })
    }.width('100%')
  }

  private agoText(at: number): string {
    const seconds: number = Math.max(0, Math.round((Date.now() - at) / 1000));
    if (seconds < 60) return this.text('app.string.fieldwatch_find_seen_just_now');
    if (seconds < 3600) return this.text('app.string.fieldwatch_find_seen_minutes').replace('%d', Math.round(seconds / 60).toString());
    if (seconds < 86400) return this.text('app.string.fieldwatch_find_seen_hours').replace('%d', Math.round(seconds / 3600).toString());
    return this.text('app.string.fieldwatch_find_seen_days').replace('%d', Math.round(seconds / 86400).toString());
  }
}
