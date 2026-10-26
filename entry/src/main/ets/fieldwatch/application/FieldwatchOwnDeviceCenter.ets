import { logger } from 'ngf_framework';
import { RadioFacts, RadioKind, Sighting } from '../domain/FieldwatchModels';
import {
  OwnDeviceCandidate, OwnDeviceFingerprint, OwnDeviceKind, OwnDeviceProfile,
  deviceAddressOfKey, kindFromDeviceClass, normalizeDeviceAddress
} from '../domain/FieldwatchOwnDevice';
import { FieldwatchOwnDeviceMatcher, OWN_MATCH_THRESHOLD, ownFingerprintScore } from '../domain/FieldwatchOwnDeviceMatcher';
import { FindCandidate, mergeFindCandidates, resolveLiveKey } from '../domain/FieldwatchFindModel';
import { FieldwatchOwnDeviceRepository } from '../data/FieldwatchOwnDeviceRepository';
import { FieldwatchPairedDevices, PairedDeviceEntry, fieldwatchPairedDevices } from '../platform/FieldwatchPairedDevices';

const TAG: string = 'FieldwatchOwnDeviceCenter';
/** 从扫描列表里能认出几台「最近听到」的候选。再多用户也不会看。 */
const SCAN_CANDIDATE_LIMIT: number = 12;
/** 「最近听到」要求这次进程里确实听到过（时间窗与在场判定同一量级）。 */
const SCAN_CANDIDATE_FRESH_MS: number = 5 * 60 * 1000;

/**
 * 自有设备的编排层。
 *
 * 职责边界：
 *   - `FieldwatchOwnDevice` / `FieldwatchOwnDeviceMatcher` 是纯逻辑（可单测）；
 *   - `FieldwatchOwnDeviceRepository` 只管落库；
 *   - `FieldwatchPairedDevices` 只管读系统配对名单；
 *   - **本类把四者接起来**，并把「实时 Sighting」翻译成 matcher 要的候选。
 *
 * 为什么单独成类而不是塞进 `FieldwatchApplication`：应用层那个文件已经承担了扫描、
 * 导出、隐私、通知等十几件事，再塞一套认领/纠错/回写会把它的职责彻底糊掉；
 * 而这里每一处都能被单独调用与替换（例如将来换掉配对名单实现）。
 */
export class FieldwatchOwnDeviceCenter {
  private readonly repository: FieldwatchOwnDeviceRepository = new FieldwatchOwnDeviceRepository();
  private readonly matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
  private readonly paired: FieldwatchPairedDevices = fieldwatchPairedDevices;
  private profiles: OwnDeviceProfile[] = [];
  /**
   * 全局拉黑名单（「这不是我的设备」留下的广播长相）。
   *
   * 为什么要独立于档案存在：纠错会把这台设备从「我的设备」里**移出**，
   * 档案一删，它自己身上的 `denyFingerprints` 就跟着没了 ——
   * 下次再认领时又会把它当成新的、重新认回来。
   * 所以黑名单必须活在档案之外，落库到设置里（条目很少，不值得单开一张表）。
   */
  private denyList: OwnDeviceFingerprint[] = [];
  private ready: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private lastPersistAt: number = 0;

  /** 从落库恢复。多次调用只会真正执行一次。 */
  async ensureLoaded(): Promise<void> {
    if (this.ready) return;
    const pending: Promise<void> | undefined = this.loading;
    if (pending !== undefined) { await pending; return; }
    const task: Promise<void> = this.loadAll();
    this.loading = task;
    try { await task; } finally { this.loading = undefined; }
  }

  private async loadAll(): Promise<void> {
    try {
      this.profiles = await this.repository.loadAll();
      this.ready = true;
      logger.info(TAG, '自有设备档案已载入: ' + this.profiles.length.toString() + ' 台');
    } catch (error) {
      // 落库失败不能把功能锁死：内存里继续可用，只是重启后要重新认领。
      logger.warn(TAG, '自有设备档案载入失败: ' + this.errorMessage(error));
      this.profiles = [];
      this.ready = true;
    }
  }

  loaded(): boolean { return this.ready; }

  all(): OwnDeviceProfile[] { return this.profiles; }

  /** 把一批拉黑指纹灌进来（设置里恢复备份/首启读盘时用）。 */
  setDenyList(list: OwnDeviceFingerprint[]): void { this.denyList = list; }

  getDenyList(): OwnDeviceFingerprint[] { return this.denyList; }

  /** 这次观测是否已被拉黑。用于「认领」入口：拉黑过的不再出现在可认领列表里。 */
  denied(fingerprint: OwnDeviceFingerprint): boolean {
    let hit: boolean = false;
    this.denyList.forEach((deny: OwnDeviceFingerprint): void => {
      if (hit) return;
      if (ownFingerprintScore(deny, fingerprint) >= OWN_MATCH_THRESHOLD) hit = true;
    });
    return hit;
  }

  /** 由一条实时观测构造匹配候选（指纹只取这台设备**此刻**广播出来的东西）。 */
  static candidateOfSighting(sighting: Sighting): OwnDeviceCandidate {
    return new OwnDeviceCandidate(sighting.key, sighting.address, '', FieldwatchOwnDeviceCenter.fingerprintOfFacts(sighting.name, sighting.facts, sighting.signatureIds));
  }

  /** 由广播事实构造指纹快照。配对名单来的设备没有广播，只填名字。 */
  static fingerprintOfFacts(name: string, facts: RadioFacts, signatureIds: string[]): OwnDeviceFingerprint {
    const manufacturers: number[] = [];
    if (facts.manufacturerId > 0) manufacturers.push(facts.manufacturerId);
    const uuids: string[] = [];
    facts.serviceUuids.forEach((uuid: string): void => { uuids.push(uuid); });
    facts.serviceUuids128.forEach((uuid: string): void => { uuids.push(uuid); });
    return new OwnDeviceFingerprint(name, manufacturers, uuids, signatureIds);
  }

  /** 在实时列表里找出属于某份档案的那一条（地址 → 指纹，走 matcher）。 */
  liveSightingOf(profile: OwnDeviceProfile, sightings: Sighting[]): Sighting | undefined {
    for (let index: number = 0; index < sightings.length; index += 1) {
      const candidate: OwnDeviceCandidate = FieldwatchOwnDeviceCenter.candidateOfSighting(sightings[index]);
      const result = this.matcher.match([profile], candidate);
      if (result.matched) return sightings[index];
    }
    return undefined;
  }

  /**
   * 认领一台设备。
   *
   * 已认领过（同一地址/同一指纹）就直接返回既有档案，不重复建 ——
   * 「点两下建出两条一模一样的档案」会让找东西列表里出现两个同名条目。
   */
  /**
   * 认领一台设备（**同步返回结果**，落库在后台继续）。
   *
   * 为什么不做成 async 让页面 await：认领是「点一下就该立刻看到我在找它」的动作，
   * 等一次 RDB 写入会把向导页推迟几十毫秒甚至更久（首次建库还要更长时间）。
   * 内存先落位、UI 立刻可用，落库失败最多是重启后重认一次 —— 这个代价可以接受，
   * 而「点了没反应」不可接受。
   */
  claim(deviceKey: string, address: string, name: string, fingerprint: OwnDeviceFingerprint): OwnDeviceProfile | undefined {
    const normalized: string = normalizeDeviceAddress(address.length > 0 ? address : deviceAddressOfKey(deviceKey));
    const existing: OwnDeviceProfile | undefined = this.profiles.find((item: OwnDeviceProfile): boolean => {
      if (normalized.length > 0 && item.virtualAddress === normalized) return true;
      return item.deviceKey.length > 0 && item.deviceKey === deviceKey;
    });
    if (existing !== undefined) return existing;
    if (this.denied(fingerprint)) {
      logger.info(TAG, '认领被拉黑名单拦下: ' + deviceKey);
      return undefined;
    }
    const profile: OwnDeviceProfile = new OwnDeviceProfile(
      'own-' + Date.now().toString() + '-' + this.profiles.length.toString(),
      '',
      normalized,
      deviceKey,
      name,
      kindFromFacts(fingerprint),
      -1,
      fingerprint,
      deviceKey.length > 0 ? 'scan' : 'paired'
    );
    profile.claimedAt = Date.now();
    this.profiles.push(profile);
    void this.repository.save(profile);
    logger.info(TAG, '已认领设备: ' + deviceKey + ' 名称=' + name);
    return profile;
  }

  /**
   * 从系统配对名单认领（只读名单，不发起任何配对/连接）。
   *
   * 名单里拿不到广播事实，指纹只有一个名字；地址直配仍是主锚，
   * 所以这里如实建一份「只有名字」的档案，不假装有厂商/服务信息。
   */
  claimPaired(entry: PairedDeviceEntry): OwnDeviceProfile | undefined {
    const deviceKey: string = 'ble:' + entry.address;
    const fingerprint: OwnDeviceFingerprint = new OwnDeviceFingerprint(entry.name, [], [], []);
    const profile: OwnDeviceProfile | undefined = this.claim(deviceKey, entry.address, entry.name, fingerprint);
    if (profile !== undefined) {
      profile.kind = kindOfClass(entry.majorClass, entry.majorMinorClass);
      profile.deviceClass = entry.deviceClass;
      profile.source = 'paired';
      void this.repository.save(profile);
    }
    return profile;
  }

  /**
   * 「这不是我的设备」：把这次的长相拉黑，并把档案移出。
   *
   * 两步都要做。只拉黑不移出，它仍然占着「我的设备」；只移出不拉黑，
   * 下次扫描又会被认领回来 —— 用户会认为这个按钮没生效。
   */
  deny(profile: OwnDeviceProfile, fingerprint: OwnDeviceFingerprint): void {
    if (!this.denied(fingerprint)) this.denyList.push(fingerprint);
    const index: number = this.profiles.indexOf(profile);
    if (index >= 0) this.profiles.splice(index, 1);
    void this.repository.remove(profile.id);
    logger.info(TAG, '已移出并拉黑: ' + profile.deviceKey);
  }

  /** 回写「上次见到」（由应用层每 5 秒调一次，走 matcher 认人）。 */
  refreshSeen(sightings: Sighting[], now: number): boolean {
    let changed: boolean = false;
    this.profiles.forEach((profile: OwnDeviceProfile): void => {
      const live: Sighting | undefined = this.liveSightingOf(profile, sightings);
      if (live === undefined) return;
      if (live.lastSeen > profile.lastSeenAt) { profile.lastSeenAt = live.lastSeen; changed = true; }
      if (live.location !== undefined) {
        profile.lastLatitude = live.location.latitude;
        profile.lastLongitude = live.location.longitude;
      }
    });
    // 落库按分钟节流：lastSeen 每次都在变，5 秒一写会把 RDB 打满。
    if (changed && now - this.lastPersistAt >= 60000) {
      this.lastPersistAt = now;
      void this.repository.saveAll(this.profiles);
    }
    return changed;
  }

  /**
   * 「找东西」列表的三批候选。
   *
   * 顺序固定为：已认领 → 系统配对名单 → 最近听到。
   * 已认领排第一是因为**再次找**的点击预算是 2 次，它必须一眼可见。
   */
  candidates(sightings: Sighting[], now: number): FindCandidate[] {
    const liveKeys: string[] = [];
    sightings.forEach((item: Sighting): void => { liveKeys.push(item.key); });

    const claimed: FindCandidate[] = [];
    this.profiles.forEach((profile: OwnDeviceProfile): void => {
      const liveKey: string = resolveLiveKey(profile, liveKeys);
      const key: string = liveKey.length > 0 ? liveKey : profile.deviceKey;
      const label: string = profile.label();
      claimed.push(new FindCandidate(key, profile.virtualAddress, label.length > 0 ? label : profile.displayName,
        profile.id, 'own', false, profile.lastSeenAt));
    });

    const paired: FindCandidate[] = [];
    if (this.paired.available()) {
      this.paired.list().forEach((entry: PairedDeviceEntry): void => {
        const address: string = normalizeDeviceAddress(entry.address);
        const alreadyClaimed: boolean = this.profiles.some((profile: OwnDeviceProfile): boolean => profile.virtualAddress === address);
        if (alreadyClaimed) return;
        paired.push(new FindCandidate('ble:' + address, address, entry.name, '', 'paired', entry.inUse, 0));
      });
    }

    const scanned: FindCandidate[] = [];
    const sorted: Sighting[] = sightings.slice().sort((a: Sighting, b: Sighting): number => b.lastSeen - a.lastSeen);
    for (let index: number = 0; index < sorted.length && scanned.length < SCAN_CANDIDATE_LIMIT; index += 1) {
      const sighting: Sighting = sorted[index];
      // 「最近听到」只收**还在广播、且这次进程里确实新鲜**的设备：
      // 把几分钟前扫到的残影列进来，点进去一定找不到，用户会认为功能坏了。
      if (now - sighting.lastSeen > SCAN_CANDIDATE_FRESH_MS) continue;
      if (sighting.kind === RadioKind.WIFI) continue;
      const candidate: OwnDeviceCandidate = FieldwatchOwnDeviceCenter.candidateOfSighting(sighting);
      if (this.denied(candidate.fingerprint)) continue;
      const matched: boolean = this.matcher.match(this.profiles, candidate).matched;
      if (matched) continue;
      scanned.push(new FindCandidate(sighting.key, sighting.address, sighting.name, '', 'scan', false, sighting.lastSeen));
    }

    return mergeFindCandidates(claimed, paired, scanned);
  }

  /** 当前目标的种类（排查卡第三条按它给）。 */
  kindOfKey(deviceKey: string, sightings: Sighting[]): string {
    for (let index: number = 0; index < this.profiles.length; index += 1) {
      if (this.profiles[index].deviceKey === deviceKey) return this.profiles[index].kind;
    }
    for (let index: number = 0; index < sightings.length; index += 1) {
      if (sightings[index].key === deviceKey) {
        // 扫描侧没有 CoD（BLE 广播里只有部分双模芯片才捎带），只能按名字猜。
        const sighting: Sighting = sightings[index];
        return kindFromFacts(FieldwatchOwnDeviceCenter.fingerprintOfFacts(sighting.name, sighting.facts, sighting.signatureIds));
      }
    }
    return OwnDeviceKind.OTHER;
  }

  /** 某台设备上次见到的时间；0 表示没有记录。 */
  lastSeenOf(deviceKey: string, sightings: Sighting[]): number {
    let best: number = 0;
    this.profiles.forEach((profile: OwnDeviceProfile): void => {
      if (profile.deviceKey === deviceKey && profile.lastSeenAt > best) best = profile.lastSeenAt;
    });
    sightings.forEach((item: Sighting): void => {
      if (item.key === deviceKey && item.lastSeen > best) best = item.lastSeen;
    });
    return best;
  }

  /** 档案里是否已有这台设备。 */
  profileOfKey(deviceKey: string): OwnDeviceProfile | undefined {
    return this.profiles.find((item: OwnDeviceProfile): boolean => item.deviceKey === deviceKey);
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/**
 * Class of Device → 种类。
 *
 * 传入的是**拆分后**的主/次类别（第 8–12 位 / 第 2–7 位），口径与
 * `kindFromDeviceClass` 一致；配对名单给的 `majorClass` / `majorMinorClass` 正是这个口径，
 * 不需要再移位。拿不到时主类别传 -1，落到 OTHER。
 *
 * **不要把整包 24 位 CoD 直接传进来**：`kindFromDeviceClass` 内部会再掩一次位，
 * 整包传进去会静默算错（它期望的是已经拆好的两个字段）。
 */
function kindOfClass(majorClass: number, majorMinorClass: number): OwnDeviceKind {
  if (majorClass < 0) return OwnDeviceKind.OTHER;
  return kindFromDeviceClass(majorClass, majorMinorClass);
}

/** 由指纹猜种类：只有名字时按名字里的关键词语义猜，猜不到就 OTHER。 */
function kindFromFacts(fingerprint: OwnDeviceFingerprint): OwnDeviceKind {
  const name: string = fingerprint.name.toLowerCase();
  if (name.indexOf('buds') >= 0 || name.indexOf('headphone') >= 0 || name.indexOf('airpods') >= 0
    || name.indexOf('耳机') >= 0) return OwnDeviceKind.HEADPHONES;
  if (name.indexOf('watch') >= 0 || name.indexOf('band') >= 0 || name.indexOf('手表') >= 0
    || name.indexOf('手环') >= 0) return OwnDeviceKind.WATCH;
  if (name.indexOf('speaker') >= 0 || name.indexOf('sound') >= 0 || name.indexOf('音箱') >= 0) return OwnDeviceKind.SPEAKER;
  if (name.indexOf('car') >= 0 || name.indexOf('车机') >= 0) return OwnDeviceKind.CAR;
  if (name.indexOf('tag') >= 0 || name.indexOf('tracker') >= 0 || name.indexOf('防丢') >= 0) return OwnDeviceKind.TRACKER;
  // 名字里没有任何可辨识的形态词：只能落到 OTHER。
  // **不要根据 deviceKey 去猜** —— 键里只有地址，地址不带任何设备类型信息，
  // 猜出来的种类会直接变成排查建议与看板图标里的错误结论。
  return OwnDeviceKind.OTHER;
}
