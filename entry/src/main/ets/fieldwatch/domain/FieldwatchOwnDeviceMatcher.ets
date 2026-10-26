/**
 * 自有设备匹配管线（找东西 P0-2）。
 *
 * 输入是一次实时观测的「认身份」切片（`OwnDeviceCandidate`），
 * 输出是「这是不是我的哪台设备」。纯函数 + 纯逻辑，不 import 系统包、不碰 UI。
 *
 * 为什么阈值要集中成常量：A.2 明确写了「阈值宁高勿低，真机阶段用自有设备组调」。
 * 散落在各个 if 里的魔法数没法一次性调，也没法在单测里引用同一个真值。
 */

import {
  OwnDeviceCandidate, OwnDeviceFingerprint, OwnDeviceProfile, OwnMatchReason, OwnMatchResult,
  deviceAddressOfKey, normalizeDeviceAddress
} from './FieldwatchOwnDevice';

/** 广播名全等（去空白、忽略大小写）。名字是最强的单条软证据：用户能看懂、能改名、误报也最容易被解释。 */
export const OWN_MATCH_NAME_SCORE: number = 3;
/** 厂商 Company ID 有交集。厂商是「批量同款」，单凭它认不出个体，所以只值 2。 */
export const OWN_MATCH_MANUFACTURER_SCORE: number = 2;
/** 认领时的服务 UUID 集被当前广播全包含。全集包含比「有交集」严得多，值 2。 */
export const OWN_MATCH_SERVICE_UUID_SCORE: number = 2;
/** 命中同一批特征库 fleetId。同一款产品共享签名，同样只值 2。 */
export const OWN_MATCH_SIGNATURE_SCORE: number = 2;
/**
 * 认作同一台的门槛。
 *
 * 5 分的含义：**至少两条独立证据**（例如 名称 + 厂商），或者一条 3 分加一条 2 分。
 * 单靠名称（3）或单靠签名（2）都不够 —— 隔壁工位同型号耳机会和你的一模一样，
 * 认错的代价是「找东西」把你导到别人的设备上，比「认不出、请你自己在列表里点」
 * 糟糕得多。真机阶段按 A.5 的自有设备组回调这个数，但只在 4~6 之间动。
 */
export const OWN_MATCH_THRESHOLD: number = 5;

/**
 * 持久 ID 直配的置信分。
 *
 * 不用「把各条证据加起来」的方式给分：持久 ID 是系统级锚，
 * 它命中时其他证据是否一致根本不影响结论（关掉蓝牙再开、重扫一遍，
 * 广播内容会变，锚不会）。分值只为让 UI 能按「锚 → 地址 → 指纹」排序。
 */
const OWN_MATCH_PERSISTENT_SCORE: number = 100;
const OWN_MATCH_ADDRESS_SCORE: number = 90;

/** UUID 比较键：大写、去掉分隔符。'0000180F-0000-…' 与 '0000180F0000…' 是同一个服务。 */
function uuidKey(value: string): string {
  return value.trim().toUpperCase().replace(/[^0-9A-Z]/g, '');
}

function hasNonEmptyText(values: string[]): boolean {
  let found: boolean = false;
  values.forEach((item: string): void => {
    if (item.trim().length > 0) found = true;
  });
  return found;
}

/** 名称全等：双方都得有名字。空名对空名不算证据 —— 否则两台「没广播名字」的设备会互认。 */
function ownNameEqual(claimed: string, observed: string): boolean {
  const left: string = claimed.trim();
  const right: string = observed.trim();
  if (left.length === 0 || right.length === 0) return false;
  return left.toLowerCase() === right.toLowerCase();
}

/**
 * Company ID 交集。
 *
 * 0 是「未知」哨兵（见 `RadioFacts.manufacturerId`），必须排除：
 * 两台都没带厂商数据的设备会构成一个毫无信息量的「假交集」，
 * 光这一条就能把 5 分门槛削掉一半。
 */
function ownManufacturerShared(claimed: number[], observed: number[]): boolean {
  if (claimed.length === 0 || observed.length === 0) return false;
  let shared: boolean = false;
  claimed.forEach((id: number): void => {
    if (id <= 0 || shared) return;
    if (observed.indexOf(id) >= 0) shared = true;
  });
  return shared;
}

/**
 * 服务 UUID：认领时的那一集必须**全部**出现在当前广播里。
 *
 * 为什么不是「有交集就加分」：通用 GATT 服务（0x1800 / 0x1801 / 0x180A / 0x180F）
 * 几乎每台 BLE 设备都有，交集式判定会把任意两台耳机配成一对。
 * 反方向（observed 比 claimed 多）是允许的：固件升级后多广播一个服务很常见，
 * 认领那一刻已经存在的服务才是身份特征。
 */
function ownServiceUuidsContained(claimed: string[], observed: string[]): boolean {
  if (!hasNonEmptyText(claimed) || !hasNonEmptyText(observed)) return false;
  const observedKeys: string[] = [];
  observed.forEach((item: string): void => {
    const key: string = uuidKey(item);
    if (key.length > 0) observedKeys.push(key);
  });
  let allFound: boolean = true;
  let compared: number = 0;
  claimed.forEach((item: string): void => {
    const key: string = uuidKey(item);
    if (key.length === 0) return;
    compared += 1;
    if (observedKeys.indexOf(key) < 0) allFound = false;
  });
  // compared 为 0 说明认领时的 UUID 集其实全是空串，这一条不该白送分。
  return compared > 0 && allFound;
}

/** 签名 id 交集：fleetId 是特征库内部标识，大小写不算语义，统一小写比。 */
function ownSignatureShared(claimed: string[], observed: string[]): boolean {
  if (claimed.length === 0 || observed.length === 0) return false;
  const observedKeys: string[] = [];
  observed.forEach((item: string): void => {
    const key: string = item.trim().toLowerCase();
    if (key.length > 0) observedKeys.push(key);
  });
  let shared: boolean = false;
  claimed.forEach((item: string): void => {
    const key: string = item.trim().toLowerCase();
    if (key.length === 0 || shared) return;
    if (observedKeys.indexOf(key) >= 0) shared = true;
  });
  return shared;
}

/** 两条指纹的相似分（0~9）。只做加权，不设门槛 —— 门槛由调用方用 OWN_MATCH_THRESHOLD 判断。 */
export function ownFingerprintScore(claimed: OwnDeviceFingerprint, observed: OwnDeviceFingerprint): number {
  let score: number = 0;
  if (ownNameEqual(claimed.name, observed.name)) score += OWN_MATCH_NAME_SCORE;
  if (ownManufacturerShared(claimed.manufacturerIds, observed.manufacturerIds)) score += OWN_MATCH_MANUFACTURER_SCORE;
  if (ownServiceUuidsContained(claimed.serviceUuids, observed.serviceUuids)) score += OWN_MATCH_SERVICE_UUID_SCORE;
  if (ownSignatureShared(claimed.signatureIds, observed.signatureIds)) score += OWN_MATCH_SIGNATURE_SCORE;
  return score;
}

/**
 * 这次观测是否落在档案的黑名单里。
 *
 * 用「任一条 deny 达标即否决」而不是「取最高分比对」：
 * 黑名单是多条不同形态的记录，命中任何一条都说明用户明确否认过这台。
 */
export function ownFingerprintDenied(profile: OwnDeviceProfile, observed: OwnDeviceFingerprint): boolean {
  let denied: boolean = false;
  profile.denyFingerprints.forEach((deny: OwnDeviceFingerprint): void => {
    if (denied) return;
    if (ownFingerprintScore(deny, observed) >= OWN_MATCH_THRESHOLD) denied = true;
  });
  return denied;
}

/**
 * `match()` 与 `best()` 共用的一次求值结果。
 *
 * 不让 `best()` 拿 `match()` 的 profileId 再回数组里 find 一遍：
 * 落库回来的档案 id 可能存在空串或重复，二次查找会把「认出了哪一台」
 * 悄悄换成另一台。这里直接把选中的对象带出来。
 */
class OwnMatchOutcome {
  public profile: OwnDeviceProfile | undefined;
  public result: OwnMatchResult;
  constructor(profile: OwnDeviceProfile | undefined, result: OwnMatchResult) {
    this.profile = profile;
    this.result = result;
  }
}

/**
 * 匹配器。
 *
 * **管线顺序不可调换**，理由是证据强度单调递减：
 *  ① persistentId —— 系统级锚。关开蓝牙、重新配对、虚拟地址轮换都不影响它，
 *     是全流程唯一能跨「今天/明天」认出来的东西。
 *  ② 地址 —— 只在配对关系存续期内稳定（A.1：取消配对或蓝牙重开后虚拟地址可能变）。
 *     但两侧都来自系统时它是精确等值，强于任何指纹。
 *  ③ 指纹 —— 启发式。广播内容会随固件、配对状态、电量策略变化，
 *     所以它排在前两根锚都失效之后，且必须先过黑名单。
 *  ④ 都不满足 —— 不是自有设备。
 *
 * 注意 ①② **不看黑名单**：地址与持久 ID 是「这台设备本身」的标识，
 * 指纹是「它当时长什么样」。用户点错一次「这不是我的设备」不代表
 * 这台设备不是他的，只是那次广播形态认错了人；拿黑名单去堵最强证据，
 * 结果是用户的耳机再也认不回来，只能手动重认 —— 所以拉黑只作用于 ③。
 *
 * **多档案同分取数组里先出现的那个**：调用方的数组顺序（列表顺序 / 落库顺序）
 * 是稳定且可解释的；若改成「≥ 时更新」，同一份数据换个排列就换一台设备，
 * 界面上表现为「找 A 结果进了 B 的向导」，而且单测也不稳。
 */
export class FieldwatchOwnDeviceMatcher {
  /** 只取匹配结论；调用方要拿到档案本身时用 `best()`，不要按 profileId 再查一次。 */
  match(profiles: OwnDeviceProfile[], candidate: OwnDeviceCandidate): OwnMatchResult {
    return this.evaluate(profiles, candidate).result;
  }

  /** 命中的档案；DENIED / NONE 都返回 undefined（被否决不算认出）。 */
  best(profiles: OwnDeviceProfile[], candidate: OwnDeviceCandidate): OwnDeviceProfile | undefined {
    return this.evaluate(profiles, candidate).profile;
  }

  private evaluate(profiles: OwnDeviceProfile[], candidate: OwnDeviceCandidate): OwnMatchOutcome {
    // ① 持久 ID：双方都非空才参与。空串代表「没取得」（权限不可用），
    // 让两个空串相等会把所有没权限的档案一次性认错。
    const persistent: string = candidate.persistentId.trim();
    if (persistent.length > 0) {
      let persistentHit: OwnDeviceProfile | undefined = undefined;
      profiles.forEach((profile: OwnDeviceProfile): void => {
        if (persistentHit !== undefined) return;
        if (profile.persistentId.length > 0 && profile.persistentId === persistent) persistentHit = profile;
      });
      if (persistentHit !== undefined) {
        const hit: OwnDeviceProfile = persistentHit;
        return new OwnMatchOutcome(hit,
          new OwnMatchResult(true, hit.id, OwnMatchReason.PERSISTENT, OWN_MATCH_PERSISTENT_SCORE));
      }
    }

    // ② 地址：候选地址与「键里剥出来的地址」任一对上即可 —— 扫描侧有时只给 key，
    // 配对侧只有地址；两个入口都要能用，否则 V1 结论一变这条锚就整条失效。
    const byAddress: string = normalizeDeviceAddress(candidate.address);
    const byKey: string = normalizeDeviceAddress(deviceAddressOfKey(candidate.deviceKey));
    if (byAddress.length > 0 || byKey.length > 0) {
      let addressHit: OwnDeviceProfile | undefined = undefined;
      profiles.forEach((profile: OwnDeviceProfile): void => {
        if (addressHit !== undefined) return;
        const stored: string = normalizeDeviceAddress(profile.virtualAddress);
        if (stored.length === 0) return;
        if (stored === byAddress || stored === byKey) addressHit = profile;
      });
      if (addressHit !== undefined) {
        const hit: OwnDeviceProfile = addressHit;
        return new OwnMatchOutcome(hit,
          new OwnMatchResult(true, hit.id, OwnMatchReason.ADDRESS, OWN_MATCH_ADDRESS_SCORE));
      }
    }

    // ③ 指纹：取最高分且过门槛的档案。先算分都不够就直接 NONE，
    // 没必要为一条不可能的候选去跑黑名单。
    let topProfile: OwnDeviceProfile | undefined = undefined;
    let topScore: number = 0;
    profiles.forEach((profile: OwnDeviceProfile): void => {
      const score: number = ownFingerprintScore(profile.fingerprint, candidate.fingerprint);
      // 严格大于：同分保留先出现的那个。
      if (score > topScore) {
        topScore = score;
        topProfile = profile;
      }
    });
    if (topProfile === undefined || topScore < OWN_MATCH_THRESHOLD) {
      return new OwnMatchOutcome(undefined, new OwnMatchResult(false, '', OwnMatchReason.NONE, 0));
    }
    const winner: OwnDeviceProfile = topProfile;
    // 黑名单优先于认领：宁可什么都不认，也不要把用户明确否认过的设备再塞回他的清单。
    // DENIED 的 score 固定 0：下游一旦拿 score 排序，被否决的候选不能靠「分数够高」混进去。
    if (ownFingerprintDenied(winner, candidate.fingerprint)) {
      return new OwnMatchOutcome(undefined, new OwnMatchResult(false, winner.id, OwnMatchReason.DENIED, 0));
    }
    return new OwnMatchOutcome(winner,
      new OwnMatchResult(true, winner.id, OwnMatchReason.FINGERPRINT, topScore));
  }
}
