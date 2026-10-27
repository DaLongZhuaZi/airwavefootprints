import { PairedDeviceInfo } from '../radio/FieldwatchPairedDevices';
import { WifiCurrentAp } from '../radio/FieldwatchWifiLink';
import { RadioKind, Sighting } from './FieldwatchModels';
import { SignatureClass } from './FieldwatchModels';
import { OwnDevice, OwnDeviceFingerprint } from './FieldwatchOwnDevice';
import { NameInputs } from './FieldwatchDeviceNaming';

/**
 * 自有设备**认领候选**的领域模型。
 *
 * 把「认领区该显示什么、哪条已经认领过、点下去对应哪个观测 key」从页面里抽出来，
 * 页面只负责画。这样认领逻辑可以单测，也避免把「已认领判定」写在 UI 分支里。
 */

export enum FindClaimSource {
  /** 系统已配对蓝牙名单（主锚）。 */
  PAIRED = 'paired',
  /** 当前连着的 Wi-Fi AP（捷径卡）。 */
  CURRENT_AP = 'current_ap',
  /** 扫描列表里当场点选（星闪、纯 BLE 手选）。 */
  SCAN = 'scan'
}

/**
 * 配对名单里的地址能否当长期锚。**按无线电种类分别判定** —— 三种系统的证据完全不同：
 *
 * - **蓝牙：可以**。文档 §八 V1 已在真机上证实「配对虚拟地址 == 扫描 deviceId」
 *   （两条独立证据：会话只在与 key 逐字相等的观测上拿到样本；观测回写按地址相等写进了库）。
 *   所以认领后下次照样能靠地址认出它，不该再显示「稳定性未确认」。
 * - **星闪：还不可以**。V5 只确认了「有配对列表接口」，**没**验证它的地址是否与扫描同源。
 * - **Wi-Fi：不可以**。V6-b 已核实：没有 `GET_WIFI_PEERS_MAC` 时系统返回随机 bssid。
 */
export function pairedAddressStable(kind: RadioKind): boolean {
  return kind === RadioKind.BLE;
}

/**
 * 建议的观测 key。
 *
 * 必须与三个扫描器的拼法**逐字一致**（`radio/FieldwatchBleScanner.ets:167`、
 * `FieldwatchNearLinkScanner.ets:136`、`FieldwatchWifiScanner.ets:288`）——
 * 寻找会话跟踪的就是这个 key，拼错一个字符就会「一直在等信号」。
 */
export function claimKeyOf(kind: RadioKind, address: string): string {
  if (kind === RadioKind.WIFI) return 'wifi:' + address;
  if (kind === RadioKind.NEARLINK) return 'nearlink:' + address;
  return 'ble:' + address;
}

/** 一条可以认领的目标。 */
export class FindClaimCandidate {
  public source: FindClaimSource = FindClaimSource.PAIRED;
  public kind: RadioKind = RadioKind.BLE;
  public address: string = '';
  public key: string = '';
  /** 主标题（设备名；空名由 UI 显示「未命名设备」）。 */
  public title: string = '';
  /**
   * 副标题**文案键**（不是显示文本）：
   *
   * `'connected'` / `'paired'` / `'current_ap'`，由页面翻成资源字符串。
   * 领域层不写用户可见文案 —— 否则 i18n 会被绕过，且文案改动要动领域模型。
   */
  public subtitle: string = '';
  public category: SignatureClass = SignatureClass.OTHER;
  /** 星闪原生类别（用于更精确的图标）；-1 表示非星闪或没取到。 */
  public nearLinkDeviceClass: number = -1;
  /**
   * 认领那一刻的广播指纹快照。
   *
   * 配对名单路径拿不到广播，所以它是空的（事后由向导回填）；**扫描列表路径能当场填满** ——
   * 这正是文档落地点五要的「认领那一刻的广播指纹」。
   */
  public fingerprint: OwnDeviceFingerprint = new OwnDeviceFingerprint();
  /** 仅扫描路径：用于排序的信号强度（平滑后的显示值）。 */
  public strength: number = 0;
  public connected: boolean = false;
  public addressStable: boolean = false;
  /** 是否已经在自有设备档案里（UI 显示「已认领」而不是可点）。 */
  public alreadyClaimed: boolean = false;
  /**
   * 命名回退链的输入（P3-1 第 2 项）。
   *
   * UI 不再用 `title` 直接当显示名，而是走 `resolveDeviceName(nameInputs)`：
   * `title` 只有一级回退（空即「未命名设备」），用不上配对名 / 厂商 / 类别。
   * 命名决策交给纯函数，因此可单测；这里只负责把链上每一级的原料带上。
   */
  public nameInputs: NameInputs = new NameInputs();
}

/** 已认领判定：地址优先；**Wi-Fi 只能按名字**（见下）。 */
export function isAlreadyClaimed(candidate: FindClaimCandidate, claimed: OwnDevice[]): boolean {
  let found: boolean = false;
  claimed.forEach((device: OwnDevice): void => {
    if (found) return;
    if (device.kind !== candidate.kind) return;
    if (candidate.kind === RadioKind.WIFI) {
      // V6-b 已核实：没有 GET_WIFI_PEERS_MAC 时系统返回**随机 bssid**，
      // 所以 Wi-Fi 的地址比对毫无意义 —— 只能按 SSID 判，并在 UI 上如实说明
      // 「同名网络无法区分」。
      if (device.displayName.length > 0 && device.displayName === candidate.title) found = true;
      return;
    }
    if (device.virtualAddress.length > 0 && device.virtualAddress === candidate.address) found = true;
  });
  return found;
}

/** 系统已配对名单 → 认领候选（正在连着手机的排最前，沿用网关的排序）。 */
export function pairedCandidates(devices: PairedDeviceInfo[], claimed: OwnDevice[]): FindClaimCandidate[] {
  const out: FindClaimCandidate[] = [];
  devices.forEach((device: PairedDeviceInfo): void => {
    const candidate: FindClaimCandidate = new FindClaimCandidate();
    candidate.source = FindClaimSource.PAIRED;
    // 蓝牙与星闪走同一条认领路径（落地点四的同构要求）：类别与 key 前缀由 kind 决定。
    candidate.kind = device.kind;
    candidate.address = device.virtualAddress;
    candidate.key = claimKeyOf(device.kind, device.virtualAddress);
    candidate.title = device.name;
    candidate.nameInputs.pairedName = device.name;
    candidate.nameInputs.address = device.virtualAddress;
    candidate.nameInputs.kind = device.kind;
    candidate.category = device.category;
    candidate.nearLinkDeviceClass = device.nearLinkDeviceClass;
    candidate.connected = device.connected;
    candidate.addressStable = pairedAddressStable(device.kind);
    // 副标题只说用户能立刻验证的事：是不是正连着这台手机。
    candidate.subtitle = device.connected ? 'connected' : 'paired';
    candidate.alreadyClaimed = isAlreadyClaimed(candidate, claimed);
    out.push(candidate);
  });
  return out;
}

/** 当前 AP → 认领捷径卡；没连 Wi-Fi 或已认领过则返回 undefined（UI 不画这张卡）。 */
export function currentApCandidate(ap: WifiCurrentAp | undefined, claimed: OwnDevice[]): FindClaimCandidate | undefined {
  if (ap === undefined || ap.ssid.length === 0) return undefined;
  const candidate: FindClaimCandidate = new FindClaimCandidate();
  candidate.source = FindClaimSource.CURRENT_AP;
  candidate.kind = RadioKind.WIFI;
  candidate.address = ap.bssid;
  candidate.key = claimKeyOf(RadioKind.WIFI, ap.bssid);
  candidate.title = ap.ssid;
  candidate.nameInputs.broadcastName = ap.ssid;
  candidate.nameInputs.address = ap.bssid;
  candidate.nameInputs.kind = RadioKind.WIFI;
  candidate.category = SignatureClass.ROUTER;
  candidate.connected = true;
  // bssidStable 恒 false（V6-b）：认领后也只能靠 SSID 认它。
  candidate.addressStable = ap.bssidStable;
  candidate.subtitle = 'current_ap';
  candidate.alreadyClaimed = isAlreadyClaimed(candidate, claimed);
  return candidate;
}

/**
 * 用当前证据重新判定一条档案的地址稳定性（旧档案自愈）。
 *
 * 为什么需要自愈：`addressStable` 是**认领当时**写进库的判断。V1（配对虚拟地址 == 扫描 deviceId）
 * 的结论是后来才拿到的，此前认领的蓝牙设备库里存的是 false —— 不重判的话，
 * 那些设备会一直显示「稳定性未确认」，而证据其实已经变了。
 *
 * 只处理「来自配对名单的蓝牙设备」：星闪没验证同源、Wi-Fi 被系统随机化，都不该自愈。
 *
 * @returns 是否发生了改动（调用方负责落库）
 */
export function refreshAddressStability(device: OwnDevice): boolean {
  if (device.kind !== RadioKind.BLE) return false;
  if (device.claimSource !== FindClaimSource.PAIRED) return false;
  if (device.addressStable) return false;
  device.addressStable = pairedAddressStable(device.kind);
  return device.addressStable;
}

/** 认领候选 → 档案（点下认领时调用）。 */
export function ownDeviceFromCandidate(candidate: FindClaimCandidate, now: number): OwnDevice {
  const device: OwnDevice = new OwnDevice();
  // id 用「来源 + 地址或名字」：同一台设备重复认领时覆盖同一条，而不是堆出多条。
  const identity: string = candidate.address.length > 0 ? candidate.address : candidate.title;
  device.id = candidate.source + ':' + candidate.kind + ':' + identity;
  device.displayName = candidate.title;
  device.kind = candidate.kind;
  device.virtualAddress = candidate.address;
  device.addressStable = candidate.addressStable;
  device.category = candidate.category;
  // 指纹：扫描路径当场带着广播指纹（照抄）；配对路径为空 ——
  // 系统配对名不是广播名，不能用它冒充指纹，那部分由向导在真扫到时回填。
  device.fingerprint = candidate.fingerprint;
  device.createdAt = now;
  device.claimSource = candidate.source;
  return device;
}

/**
 * 认领候选：**从实时扫描列表里挑**（文档落地点一/四的「当场点选」路径）。
 *
 * 什么时候用这条：设备没在系统里配过对（星闪目标 v1 主要靠它；蓝牙里也有临时用别人的
 * 设备、或用户不想配对只想找一下的情况）。
 *
 * 三条刻意的取舍：
 * 1. **只列有名字的**：一两百台设备里没有名字的那些，用户根本认不出哪台是自己的，
 *    列出来只是噪音；
 * 2. **只列蓝牙与星闪**：Wi-Fi 目标走「你现在连着的路由器」捷径卡 —— 把邻居家的 AP 塞进
 *    「我的东西」是错的；
 * 3. **按信号强度排序**：近的在前，用户要找的东西通常就在手边。
 *
 * 认领时会**把这一刻的广播指纹一起存下来**（名称/厂商数据/服务 UUID/命中签名）——
 * 这正是文档落地点五要的「认领那一刻的指纹快照」，比事后回填更完整。
 */
export function scanCandidates(sightings: Sighting[], claimed: OwnDevice[], limit: number,
  resolveCategory: (signatureIds: string[]) => SignatureClass): FindClaimCandidate[] {
  const out: FindClaimCandidate[] = [];
  sightings.forEach((item: Sighting): void => {
    if (item.kind === RadioKind.WIFI) return;
    // **不再丢弃无名设备**（P3-1 第 2 项）：
    // 原来这里写 `if (item.name.length === 0) return;`，于是广播里不带名字的设备
    // 在认领列表里**根本不出现** —— 用户想找它却找不到，比显示「未命名设备」更糟。
    // 现在放行，由命名回退链（配对名 / fleet 名 / CoD / 厂商 / 尾号）补出可读名字。
    const candidate: FindClaimCandidate = new FindClaimCandidate();
    candidate.source = FindClaimSource.SCAN;
    candidate.kind = item.kind;
    candidate.address = item.address;
    candidate.key = claimKeyOf(item.kind, item.address);
    candidate.title = item.name;
    // 命名原料：广播名 + 地址 + 类别；配对名 / 厂商 / fleet 名由调用方补齐
    // （它们要么要查配对名单、要么要查特征库，不适合在纯函数的遍历里做）。
    candidate.nameInputs.broadcastName = item.name;
    candidate.nameInputs.address = item.address;
    candidate.nameInputs.kind = item.kind;
    candidate.subtitle = 'scan';
    candidate.connected = false;
    // 扫描来的地址同样**不当作长期锚**：星闪没验证同源、蓝牙随机地址也可能轮换。
    candidate.addressStable = false;
    candidate.alreadyClaimed = isAlreadyClaimed(candidate, claimed);
    candidate.fingerprint.name = item.name;
    candidate.fingerprint.manufacturerDataHex = item.facts.manufacturerDataHex;
    candidate.fingerprint.serviceUuids = item.facts.serviceUuids.length > 0
      ? item.facts.serviceUuids : item.facts.vendorIeOuis;
    candidate.fingerprint.signatureIds = item.signatureIds;
    candidate.strength = item.rssiDisplay;
    out.push(candidate);
  });
  out.sort((left: FindClaimCandidate, right: FindClaimCandidate): number => right.strength - left.strength);
  // **类别解析放在取前 N 之后**：它要逐个比对特征库（几百条），
  // 而页面每 2 秒刷新一次 —— 对上百台观测全解析是白烧 CPU，只有进列表的才需要图标。
  const top: FindClaimCandidate[] = out.slice(0, limit);
  top.forEach((candidate: FindClaimCandidate): void => {
    // 签名 id 就在指纹里（认领时也要存它），不必再单独带一份。
    candidate.category = resolveCategory(candidate.fingerprint.signatureIds);
  });
  return top;
}
