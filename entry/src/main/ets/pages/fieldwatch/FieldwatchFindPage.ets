import { logger } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { FieldwatchOwnDeviceRepository } from '../../fieldwatch/data/FieldwatchOwnDeviceRepository';
import { OwnDeviceStamp, ownDeviceIdForAddress, ownDevicesToStamp } from '../../fieldwatch/domain/FieldwatchOwnDeviceTracker';
import {
  GpsSample, RadioFacts, ScanObservation, Sighting
} from '../../fieldwatch/domain/FieldwatchModels';
import { ngfLocationManagerFacade } from 'ngf_framework';
import {
  claimKeyOf, currentApCandidate, FindClaimCandidate, FindClaimSource, ownDeviceFromCandidate, pairedCandidates,
  refreshAddressStability, scanCandidates
} from '../../fieldwatch/domain/FieldwatchFindClaim';
import { SignatureClass } from '../../fieldwatch/domain/FieldwatchModels';
import { OwnDevice } from '../../fieldwatch/domain/FieldwatchOwnDevice';
import { FieldwatchPairedDevices, PairedDeviceInfo } from '../../fieldwatch/radio/FieldwatchPairedDevices';
import { FieldwatchWifiLink, WifiCurrentAp } from '../../fieldwatch/radio/FieldwatchWifiLink';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';
import { deviceClassSymbol, nearLinkClassSymbol } from '../../fieldwatch/ui/FieldwatchDeviceTypeIcon';
import { RadioKind } from '../../fieldwatch/domain/FieldwatchModels';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { fieldwatchText } from '../../fieldwatch/ui/FieldwatchResText';
import { FIELDWATCH_TAB_BAR_RESERVE } from '../../fieldwatch/ui/FieldwatchLayout';

const TAG: string = 'FieldwatchFindPage';

/**
 * 平台查询（蓝牙/星闪配对名单、Wi-Fi 当前连接）之间的最短间隔。
 *
 * **为什么必须缓存、不能在定时器里直接问**：这些接口都是**同步**系统调用，
 * 跑在 UI 线程上。蓝牙/星闪服务忙的时候（尤其是连接状态正准备变化的那一刻）
 * 单次调用可能阻塞很久 —— 原来每 2 秒问一轮，正好在服务最忙时把 UI 线程堵死，
 * 真机现象就是「整页卡住、整个应用点不动」。
 *
 * 名单本身变化很慢：连接事件会立刻把缓存标脏，再加 30 秒兜底已经足够新鲜。
 */
/** 未测得强度（与专业页同一约定：127 = 没有有效测量值）。 */
const RSSI_UNMEASURED: number = 127;

const PLATFORM_REFRESH_MS: number = 30000;
/** 展开「附近的设备」时重算候选的间隔；太勤会让顺序随信号抖动来回跳。 */
const SCAN_REFRESH_MS: number = 5000;

/**
 * 找东西 —— 「我的东西在哪里」的认领区。
 *
 * 依据：`docs/Fieldwatch找东西深度落地.md`（落地点一 / 三 / 五 / 七）。
 *
 * **三条只读边界**（与 App「只接收不连接」的底线一致）：
 * 1. 只读系统已配对名单与 Profile 连接状态，**不发起任何配对或连接**；
 * 2. 不申请新权限（ACCESS_BLUETOOTH 与 GET_WIFI_INFO 已在册；
 *    `PERSISTENT_BLUETOOTH_PEERS_MAC` / `GET_WIFI_PEERS_MAC` 是 system_basic，不用）；
 * 3. 认领只写本机 RDB，不回写系统名单。
 *
 * **点击预算**（文档 §7.1）：认领与进入向导合并为一步 —— 点一台设备即完成认领并进向导，
 * 不给用户「先认领、再使用」的两段式流程。所以本页的认领回调直接交给父层开向导。
 */
@Component
export struct FieldwatchFindPage {
  /** 顶部安全区（沉浸式）。 */
  topInset: number = 0;
  /** 底部安全区高度（系统导航条）；与 FieldwatchLayout 的预留常量叠加使用。 */
  @Prop bottomInset: number = 0;
  /**
   * 认领完成后立刻进入寻找向导。
   *
   * 向导**渲染在本页内**（而不是压栈到新路由）：这样「认领 → 开找」是一步、
   * 返回就在原处，也满足「再次找已认领设备 ≤2 次点击」（点一下档案行即开找）。
   */
  @State private huntStarted: boolean = false;
  /** 当前目标是否正连着这台手机（向导据此多一句可靠提示）。 */

  @State private paired: FindClaimCandidate[] = [];
  @State private wifiCard: FindClaimCandidate | undefined = undefined;
  @State private owned: OwnDevice[] = [];
  @State private bluetoothOn: boolean = true;
  @State private loaded: boolean = false;
  /**
   * 行内提示——不用 Toast，避免打断与遮挡。
   *
   * 拆成「失败标志 + 被移除的名字」两个字段而不是拼一个字符串：
   * `$r()` 只接受字面量键，动态文案必须由资源 + 参数渲染（i18n 规范）。
   */
  @State private noticeSaveFailed: boolean = false;
  @State private noticeRemovedName: string = '';
  /** 扫描列表认领路径：候选与展开状态（文档落地点一/四的「当场点选」）。 */
  @State private scanning: FindClaimCandidate[] = [];
  @State private scanOpen: boolean = false;

  private readonly pairedGateway: FieldwatchPairedDevices = new FieldwatchPairedDevices();
  private readonly wifiLink: FieldwatchWifiLink = new FieldwatchWifiLink();
  private readonly repository: FieldwatchOwnDeviceRepository = new FieldwatchOwnDeviceRepository();
  private refreshTimer: number = -1;
  /** 平台查询缓存的时间戳与脏标记（见 `PLATFORM_REFRESH_MS` 的说明）。 */
  private platformAt: number = 0;
  private platformDirty: boolean = true;
  /**
   * 平台快照：配对名单与当前 Wi-Fi 连接。
   *
   * 候选列表（含「已认领 / 正连着」徽标）由**快照 + 档案**在每次轻刷新时重算 ——
   * 这样徽标随档案即时更新，又不必为了刷新徽标去碰同步 IPC。
   */
  private pairedSnapshot: PairedDeviceInfo[] = [];
  private wifiSnapshot: WifiCurrentAp | undefined = undefined;
  /** 扫描列表上次重算的时间戳。 */
  private scanAt: number = 0;
  /** 刷新是否正在进行：慢调用**不许叠**，否则一次卡顿会被下一拍继续放大。 */
  private refreshing: boolean = false;

  aboutToAppear(): void {
    void this.refresh();
    // 连接状态会变（耳机摘下、车熄火），2 秒一次的轻刷新足够；
    // 与工具箱其它页同频，避免多套节奏互相打架。
    this.refreshTimer = setInterval((): void => { void this.refresh(); }, 2000);
    this.pairedGateway.subscribe((deviceId: string, connected: boolean): void => {
      logger.info(TAG, '配对设备连接状态变化: ' + deviceId + (connected ? ' 已连接' : ' 已断开'));
      // **断开时刻就是最可信的 lastSeen**（文档落地点二的隐藏价值）：
      // 经典蓝牙设备连着时通常不广播，观测回写采不到它 —— 断开那一瞬间才是事件级证据。
      if (!connected) void this.stampDisconnect(deviceId);
      // 只标脏，**不在事件回调里直接问平台**：蓝牙状态刚变的一瞬间正是同步 IPC 最慢的时候，
      // 在这里再发起一轮查询，等于自己往堵点上撞。交给下一拍定时器去处理。
      this.platformDirty = true;
    });
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    // 必须成对取消：页面离开后还回调会写已释放的状态变量。
    this.pairedGateway.unsubscribe();
  }

  /**
   * 把「刚刚断开」记成上次见到（尽量带位置）。
   *
   * 只对**来自配对名单的蓝牙档案**生效：只有经典侧能拿到连接事件。
   * 位置取不到（未授权/未开启）时传 undefined —— 仓储会**保留原有位置**而不是清掉它。
   */
  private async stampDisconnect(deviceId: string): Promise<void> {
    const id: string = ownDeviceIdForAddress(this.owned, RadioKind.BLE, deviceId);
    if (id.length === 0) return;
    const location: GpsSample | undefined = await this.currentLocation();
    const saved: boolean = await this.repository.updateLastSeen(id, Date.now(), location);
    logger.info(TAG, '断开即上次见到：已记录=' + (saved ? '是' : '否') + '，带位置=' + (location !== undefined ? '是' : '否'));
    await this.refresh();
  }

  /** 当前手机位置；未开启定位或读取失败都返回 undefined。 */
  private async currentLocation(): Promise<GpsSample | undefined> {
    try {
      if (!ngfLocationManagerFacade.isLocationEnabled()) return undefined;
      const location = await ngfLocationManagerFacade.getCurrentLocation();
      return location === null ? undefined : new GpsSample(location.latitude, location.longitude, Date.now());
    } catch (error) {
      return undefined;
    }
  }

  private async refresh(): Promise<void> {
    // 上一拍还没回来就跳过这一拍：慢调用叠起来会把一次卡顿放大成持续卡死。
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      await this.reloadOwnDevices();
      // 先按快照重算（即时、零系统调用），再按需更新快照。
      this.recomputeCandidates();
      this.refreshPlatformIfNeeded(false);
      this.refreshScanList();
      this.loaded = true;
    } finally {
      this.refreshing = false;
    }
  }

  /**
   * 档案部分：读库 + 自愈 + 观测回写。
   *
   * 全是**异步**且数据量小（几条档案），2 秒一拍没有压力 —— 与平台查询分开正是为了这个：
   * 能让 UI 线程卡住的只有平台那几个**同步**接口。
   */
  private async reloadOwnDevices(): Promise<void> {
    let owned: OwnDevice[] = await this.repository.loadAll();
    // 证据更新后让旧档案自愈（V1 结论晚于首次认领的情况）：只重判、不降级。
    let healed: boolean = false;
    for (let i: number = 0; i < owned.length; i += 1) {
      if (refreshAddressStability(owned[i])) {
        await this.repository.save(owned[i]);
        healed = true;
      }
    }
    if (healed) owned = await this.repository.loadAll();
    this.owned = owned;
    await this.stampObserved(owned);
  }

  /** 平台部分：**只在缓存脏了或超过间隔时才真去问系统**（同步 IPC，绝不能上定时器）。 */
  private refreshPlatformIfNeeded(force: boolean): void {
    const now: number = Date.now();
    if (!force && !this.platformDirty && now - this.platformAt < PLATFORM_REFRESH_MS) return;
    this.platformDirty = false;
    this.platformAt = now;
    const bluetoothOn: boolean = this.pairedGateway.isBluetoothOn();
    this.bluetoothOn = bluetoothOn;
    this.pairedSnapshot = bluetoothOn ? this.pairedGateway.list() : [];
    this.wifiSnapshot = this.wifiLink.current();
    this.recomputeCandidates();
  }

  /** 用平台快照 + 最新档案重算候选。**纯计算，不碰系统接口**，所以可以跟着每拍轻刷新走。 */
  private recomputeCandidates(): void {
    this.paired = this.bluetoothOn ? pairedCandidates(this.pairedSnapshot, this.owned) : [];
    this.wifiCard = currentApCandidate(this.wifiSnapshot, this.owned);
  }

  /** 扫描列表：**只在展开时**算，且按 `SCAN_REFRESH_MS` 节流（太勤会让顺序随信号抖动来回跳）。 */
  private refreshScanList(): void {
    if (!this.scanOpen) {
      if (this.scanning.length > 0) this.scanning = [];
      return;
    }
    const now: number = Date.now();
    if (this.scanning.length > 0 && now - this.scanAt < SCAN_REFRESH_MS) return;
    this.scanAt = now;
    this.scanning = scanCandidates(fieldwatchApplication.getState().sightings, this.owned, 20,
      (ids: string[]): SignatureClass => this.categoryOf(ids));
  }

  /**
   * 观测回写「上次见到」（文档落地点二的隐藏价值）。
   *
   * 档案里的时间要由**观测**推出来，而不是只有用户点「找到了」才动 ——
   * 用户没在找的时候，这个时间是 GONE 状态下唯一的线索。节流在领域层（每条档案 10 秒）。
   */
  private async stampObserved(owned: OwnDevice[]): Promise<void> {
    const stamps: OwnDeviceStamp[] = ownDevicesToStamp(owned, fieldwatchApplication.getState().sightings, Date.now());
    if (stamps.length === 0) return;
    for (let i: number = 0; i < stamps.length; i += 1) {
      await this.repository.updateLastSeen(stamps[i].deviceId, stamps[i].seenAt, stamps[i].location);
    }
    // 回读一次：节流是按档案里的时间算的，不重读会在下一轮重复写。
    this.owned = await this.repository.loadAll();
  }

  /** 认领一台目标：写档案 → 立刻进向导（合并为一步）。 */
  private async claim(candidate: FindClaimCandidate): Promise<void> {
    if (candidate.alreadyClaimed) {
      const existing: OwnDevice | undefined = this.findOwned(candidate);
      if (existing !== undefined) {
        this.beginHunt(existing);
        return;
      }
      // 徽标说「已认领」但按地址找不到档案时，**不要静默返回**：
      // 那正是「点了没反应」。按新认领处理（会覆盖同 id 的档案），至少让用户看到结果。
      logger.warn(TAG, '候选标记为已认领但找不到对应档案，按新认领处理: ' + candidate.title);
    }
    const device: OwnDevice = ownDeviceFromCandidate(candidate, Date.now());
    const saved: boolean = await this.repository.save(device);
    if (!saved) {
      this.noticeSaveFailed = true;
      return;
    }
    this.noticeSaveFailed = false;
    this.noticeRemovedName = '';
    await this.refresh();
    this.beginHunt(device);
  }

  /**
   * 开始寻找：**交给现有的「寻线」页**（工具箱 → 信号追踪），这里只负责锁定目标并切过去。
   *
   * 为什么不再自己做一套向导：现有寻线页更完整 —— 相对测向、趋势图、峰值/区间/均值、
   * 搜寻提示音与触感都是它已经在做的；在找东西页重做一遍只会产生两套口径、两处维护。
   */
  private beginHunt(device: OwnDevice): void {
    const key: string = claimKeyOf(device.kind, device.virtualAddress);
    const live: Sighting | undefined = this.sightingOf(key);
    if (live !== undefined) {
      fieldwatchApplication.startHunt(live);
    } else {
      // 目标当前不可见（关机 / 不在附近）也要能开始：用档案信息合成一个目标，
      // 让寻线页先进入「等它出现」的状态，而不是拒绝开始。
      const facts: RadioFacts = new RadioFacts();
      const observation: ScanObservation = new ScanObservation(key, device.kind, device.virtualAddress,
        device.displayName, RSSI_UNMEASURED, Date.now(), facts);
      fieldwatchApplication.startHunt(Sighting.fromObservation(observation));
    }
    // 打开**独立**的「寻踪」页并锁定这台设备（不再是工具箱里的内联标签页）。
    fieldwatchApplication.requestHunt(key);
  }

  /** 实时集合里按 key 找观测（没有就是当前不可见）。 */
  private sightingOf(key: string): Sighting | undefined {
    let found: Sighting | undefined = undefined;
    fieldwatchApplication.getState().sightings.forEach((item: Sighting): void => {
      if (found === undefined && item.key === key) found = item;
    });
    return found;
  }

  /** 已认领档案里对应的那一条（按地址；Wi-Fi 按名字，理由见认领模型）。 */
  private findOwned(candidate: FindClaimCandidate): OwnDevice | undefined {
    let found: OwnDevice | undefined = undefined;
    this.owned.forEach((device: OwnDevice): void => {
      if (found !== undefined) return;
      if (device.kind !== candidate.kind) return;
      const hit: boolean = candidate.kind === 'wifi'
        ? device.displayName === candidate.title
        : device.virtualAddress === candidate.address;
      if (hit) found = device;
    });
    return found;
  }

  /** 移除一台档案（「这不是我的」）。 */
  private async remove(device: OwnDevice): Promise<void> {
    await this.repository.remove(device.id);
    this.noticeRemovedName = device.displayName;
    await this.refresh();
  }

  build() {
    this.buildList()
  }

  @Builder
  private buildList() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildTitle()
        if (this.noticeSaveFailed) this.buildNotice(fieldwatchText('app.string.fieldwatch_find_save_failed'))
        else if (this.noticeRemovedName.length > 0) this.buildNotice($r('app.string.fieldwatch_find_removed', this.noticeRemovedName))
        if (!this.loaded) {
          this.buildLoading()
        } else {
          if (this.wifiCard !== undefined) this.buildWifiCard(this.wifiCard)
          this.buildPairedSection()
          this.buildOwnedSection()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topInset + 12, bottom: this.bottomInset + FIELDWATCH_TAB_BAR_RESERVE })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(FieldwatchPaletteHolder.get().night)
  }

  @Builder
  private buildTitle() {
    Column({ space: 4 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_title')).fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor(FieldwatchPaletteHolder.get().text)
      // 一句人话说清这页干什么，不出现任何术语（文档 §7.5 术语 grep 验收）。
      Text(fieldwatchText('app.string.fieldwatch_find_intro')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNotice(text: ResourceStr) {
    Text(text).fontSize(13).fontColor(FieldwatchPaletteHolder.get().warn)
      .width('100%')
  }

  @Builder
  private buildLoading() {
    Text(fieldwatchText('app.string.fieldwatch_find_loading')).fontSize(14)
      .fontColor(FieldwatchPaletteHolder.get().textDim)
      .padding({ top: 24 })
  }

  /** Wi-Fi 认领捷径卡：你现在连着的这台是不是你家路由器。 */
  @Builder
  private buildWifiCard(candidate: FindClaimCandidate) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r(deviceClassSymbol(candidate.category))).fontSize(20)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text($r('app.string.fieldwatch_find_wifi_card', candidate.title))
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().text)
          .layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Center)
      // 如实说明：名字相同的网络分不出来（bssid 被系统随机化，V6-b 已核实）。
      Text(fieldwatchText('app.string.fieldwatch_find_wifi_hint')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      if (candidate.alreadyClaimed) {
        Text(fieldwatchText('app.string.fieldwatch_find_claimed')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      } else {
        FieldwatchButton({
          label: fieldwatchText('app.string.fieldwatch_find_claim_router'),
          tone: FieldwatchButtonTone.PRIMARY,
          onTap: (): void => { void this.claim(candidate); }
        })
      }
    }
    .width('100%').padding(14).borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .border({ width: 1, color: FieldwatchPaletteHolder.get().outline })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildPairedSection() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_paired_section')).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (!this.bluetoothOn) {
        // 蓝牙关着时给一句可执行的下一步，而不是空白列表。
        this.buildEmptyCard(fieldwatchText('app.string.fieldwatch_find_bluetooth_off'))
      } else if (this.paired.length === 0) {
        this.buildEmptyCard(fieldwatchText('app.string.fieldwatch_find_none_paired'))
      } else {
        Column({ space: 8 }) {
          // key **必须带上会变的字段**：只用「来源:地址」的话，地址没变 → ArkUI 复用旧行、
          // 不重绘，于是连着的状态与「已认领」徽标会永远停在旧值（真机上删掉档案后
          // 那一行仍显示「已认领」）。
          ForEach(this.paired, (candidate: FindClaimCandidate): void => {
            this.buildCandidateRow(candidate);
          }, (candidate: FindClaimCandidate): string =>
            candidate.source + ':' + candidate.key
              + ':' + (candidate.alreadyClaimed ? 'claimed' : 'open')
              + ':' + (candidate.connected ? 'on' : 'off'))
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
    this.buildScanSection()
  }

  /**
   * 「从附近的设备里选」——扫描列表认领路径。
   *
   * 默认收起：它是一条**兜底**路径（没配过对的设备、星闪目标），不该抢主路径的注意力。
   * 展开后只列有名字的设备，按离你最近的排前面。
   */
  @Builder
  private buildScanSection() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r(this.scanOpen ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
          .fontSize(14).fontColor([FieldwatchPaletteHolder.get().textDim])
        Text(fieldwatchText('app.string.fieldwatch_find_scan_open')).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().accent)
      }
      .width('100%').height(40).alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.scanOpen = !this.scanOpen;
        // 展开时立刻算一次（不等下一拍），收起时清掉候选。
        this.scanAt = 0;
        this.refreshScanList();
      })

      if (this.scanOpen) {
        Text(fieldwatchText('app.string.fieldwatch_find_scan_hint')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
        if (this.scanning.length === 0) {
          this.buildEmptyCard(fieldwatchText('app.string.fieldwatch_find_scan_empty'))
        } else {
          Column({ space: 8 }) {
            ForEach(this.scanning, (candidate: FindClaimCandidate): void => {
              this.buildCandidateRow(candidate);
            }, (candidate: FindClaimCandidate): string =>
              'scan:' + candidate.key + ':' + (candidate.alreadyClaimed ? 'claimed' : 'open'))
          }.width('100%')
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildEmptyCard(text: ResourceStr) {
    Text(text).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
      .width('100%').padding(14).borderRadius(12)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  @Builder
  private buildCandidateRow(candidate: FindClaimCandidate) {
    Row({ space: 12 }) {
      SymbolGlyph($r(this.symbolOf(candidate))).fontSize(22)
        .fontColor([candidate.connected ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
      Column({ space: 3 }) {
        Text(this.titleOf(candidate.title)).fontSize(15)
          .fontColor(FieldwatchPaletteHolder.get().text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        // 副标题只说用户能立刻验证的事：是不是正连着这台手机。
        Text(this.subtitleOf(candidate)).fontSize(12)
          .fontColor(candidate.connected ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (candidate.alreadyClaimed) {
        Text(fieldwatchText('app.string.fieldwatch_find_claimed')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      } else {
        Text(fieldwatchText('app.string.fieldwatch_find_claim')).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(FieldwatchPaletteHolder.get().accent)
      }
    }
    .width('100%').padding(14).borderRadius(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .onClick((): void => { void this.claim(candidate); })
  }

  @Builder
  private buildOwnedSection() {
    Column({ space: 8 }) {
      Text(fieldwatchText('app.string.fieldwatch_find_owned_section')).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text)
      if (this.owned.length === 0) {
        this.buildEmptyCard(fieldwatchText('app.string.fieldwatch_find_none_owned'))
      } else {
        Column({ space: 8 }) {
          // 同上：把「上次见到」与稳定性一并编进 key，否则时间文本会停旧。
          ForEach(this.owned, (device: OwnDevice): void => {
            this.buildOwnedRow(device);
          }, (device: OwnDevice): string =>
            device.id + ':' + device.lastSeenAt.toString() + ':' + (device.addressStable ? 'stable' : 'unstable'))
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildOwnedRow(device: OwnDevice) {
    Row({ space: 12 }) {
      SymbolGlyph($r(deviceClassSymbol(device.category))).fontSize(22)
        .fontColor([FieldwatchPaletteHolder.get().textDim])
      Column({ space: 3 }) {
        Text(this.titleOf(device.displayName)).fontSize(15)
          .fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
        Text(this.lastSeenText(device)).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
        // 地址稳定性未经真机证实（V1/V5/V6-b）时如实说明，不让用户以为永远认得出来。
        if (!device.addressStable) {
          Text(fieldwatchText('app.string.fieldwatch_find_unstable_hint')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().warn)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      // 纠错入口做成**可见按钮**而不是长按：文档 §7.3 建议长按，
      // 但日常用户不会去长按一张卡片 —— 纠错入口藏起来等于没有。
      Text(fieldwatchText('app.string.fieldwatch_find_not_mine')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
        .padding({ left: 8, right: 4, top: 6, bottom: 6 })
        .onClick((): void => { void this.remove(device); })
    }
    .width('100%').padding(14).borderRadius(12)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    // 再次找同一台：一次点击直接进向导（文档 §7.1 的 ≤2 次点击）。
    .onClick((): void => { this.beginHunt(device); })
  }

  /**
   * 名称为空时给一个可读的占位名，而不是空白行。
   *
   * 返回 `ResourceStr`（string | Resource）：设备名是**数据**（系统给的，不该翻译），
   * 占位名是**文案**（要走资源）。同一次调用里两者都可能出现，所以用联合类型而不是两套分支。
   */
  /**
   * 候选图标：星闪用它自己的原生类别（能分出鼠标/触控板/手写笔），蓝牙用映射后的应用类别。
   *
   * 两套映射都是应用既有的（nearLinkClassSymbol / deviceClassSymbol），这里只做选择。
   */
  private symbolOf(candidate: FindClaimCandidate): string {
    if (candidate.kind === RadioKind.NEARLINK && candidate.nearLinkDeviceClass >= 0) {
      return nearLinkClassSymbol(candidate.nearLinkDeviceClass);
    }
    return deviceClassSymbol(candidate.category);
  }

  /**
   * 由签名 id 解析设备类别（决定图标）。
   *
   * 特征库在应用状态里，这里取「第一条命中的 fleet 的类别」——与列表页取图标的规则一致。
   */
  private categoryOf(signatureIds: string[]): SignatureClass {
    if (signatureIds.length === 0) return SignatureClass.OTHER;
    let found: SignatureClass = SignatureClass.OTHER;
    const fleets = fieldwatchApplication.getState().signatures;
    for (let i: number = 0; i < fleets.length; i += 1) {
      if (found !== SignatureClass.OTHER) break;
      if (signatureIds.includes(fleets[i].id)) found = fleets[i].category;
    }
    return found;
  }

  private titleOf(name: string): ResourceStr {
    return name.length > 0 ? name : fieldwatchText('app.string.fieldwatch_find_unnamed');
  }

  private subtitleOf(candidate: FindClaimCandidate): ResourceStr {
    if (candidate.connected) return fieldwatchText('app.string.fieldwatch_find_sub_connected');
    if (candidate.source === FindClaimSource.CURRENT_AP) return fieldwatchText('app.string.fieldwatch_find_sub_router');
    // **扫描来的不能说「系统里配过对」**（真机上就出现过这句错文案）：
    // 它根本没配对，用户看到这句会以为系统里有记录。
    if (candidate.source === FindClaimSource.SCAN) return fieldwatchText('app.string.fieldwatch_find_sub_nearby');
    return fieldwatchText('app.string.fieldwatch_find_sub_paired');
  }

  private lastSeenText(device: OwnDevice): ResourceStr {
    if (device.lastSeenAt <= 0) return fieldwatchText('app.string.fieldwatch_find_never_seen');
    const seconds: number = Math.max(0, Math.round((Date.now() - device.lastSeenAt) / 1000));
    if (seconds < 60) return fieldwatchText('app.string.fieldwatch_find_seen_just_now');
    if (seconds < 3600) return $r('app.string.fieldwatch_find_seen_minutes', Math.round(seconds / 60));
    if (seconds < 86400) return $r('app.string.fieldwatch_find_seen_hours', Math.round(seconds / 3600));
    return $r('app.string.fieldwatch_find_seen_days', Math.round(seconds / 86400));
  }
}
