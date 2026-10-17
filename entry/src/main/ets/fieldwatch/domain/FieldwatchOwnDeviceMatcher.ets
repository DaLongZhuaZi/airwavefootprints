import { logger } from 'ngf_framework';
import { RadioKind, Sighting } from './FieldwatchModels';
import { OwnDevice, OwnDeviceFingerprint } from './FieldwatchOwnDevice';

const TAG: string = 'FieldwatchOwnDeviceMatcher';

/* ── 指纹打分权重与阈值（文档落地点五的取值，集中成常量便于真机阶段调）──
 * **宁高勿低**：把邻居的同款耳机当成自己的会闹笑话，而漏认一台的代价只是用户多点一次。
 * 单一维度最高 3 分（名称），任何单维都不足以越过阈值 5 —— 至少要有两个维度互相印证。 */
export const FINGERPRINT_SCORE_NAME: number = 3;
export const FINGERPRINT_SCORE_MANUFACTURER_DATA: number = 2;
export const FINGERPRINT_SCORE_SERVICE_UUID: number = 2;
export const FINGERPRINT_SCORE_SIGNATURE: number = 2;
export const FINGERPRINT_MATCH_THRESHOLD: number = 5;
/** 地址命中：高于任何可能的指纹分（3+2+2+2=9），保证它在排序里永远第一。 */
export const ADDRESS_MATCH_SCORE: number = 100;

export enum OwnDeviceMatchReason {
  /** 地址直配：最高置信。 */
  ADDRESS = 'address',
  /** 指纹打分过阈值。 */
  FINGERPRINT = 'fingerprint',
  NONE = 'none'
}

export class OwnDeviceMatch {
  public deviceId: string = '';
  public reason: OwnDeviceMatchReason = OwnDeviceMatchReason.NONE;
  public score: number = 0;

  isMatch(): boolean { return this.reason !== OwnDeviceMatchReason.NONE; }
}

/**
 * 匹配只需要观测的一小部分 —— 抽成独立结构后，Matcher 可以脱离 `Sighting` 单测。
 */
export class OwnDeviceProbe {
  public kind: RadioKind = RadioKind.BLE;
  public address: string = '';
  public name: string = '';
  public manufacturerDataHex: string = '';
  /** BLE 服务 UUID 集；Wi-Fi 走厂商 IE OUI，也塞进这里（都是「这台设备的特征集合」）。 */
  public serviceUuids: string[] = [];
  public signatureIds: string[] = [];
}

/** 从观测抽匹配视图。 */
export function probeOf(sighting: Sighting): OwnDeviceProbe {
  const probe: OwnDeviceProbe = new OwnDeviceProbe();
  probe.kind = sighting.kind;
  probe.address = sighting.address;
  probe.name = sighting.name;
  probe.manufacturerDataHex = sighting.facts.manufacturerDataHex;
  probe.serviceUuids = sighting.facts.serviceUuids.length > 0 ? sighting.facts.serviceUuids : sighting.facts.vendorIeOuis;
  probe.signatureIds = sighting.signatureIds;
  return probe;
}

/** 目标集合是否被观测集合完全包含（设备可能裁剪广播内容，所以是「包含」而不是相等）。 */
function containsAll(observed: string[], required: string[]): boolean {
  let ok: boolean = true;
  required.forEach((item: string): void => {
    if (!observed.includes(item)) ok = false;
  });
  return ok;
}

function intersects(left: string[], right: string[]): boolean {
  let hit: boolean = false;
  left.forEach((item: string): void => {
    if (right.includes(item)) hit = true;
  });
  return hit;
}

/**
 * 指纹得分（纯函数）。
 *
 * 每个维度都要求**目标侧非空**：认领时没拿到的信息不能凭空加分，
 * 否则一台「名字空、厂商数据空」的档案会与任何同样空的观测互相命中。
 */
export function fingerprintScore(target: OwnDeviceFingerprint, probe: OwnDeviceProbe): number {
  let score: number = 0;
  if (target.name.length > 0 && target.name === probe.name) score += FINGERPRINT_SCORE_NAME;
  if (target.manufacturerDataHex.length > 0 && target.manufacturerDataHex === probe.manufacturerDataHex) {
    score += FINGERPRINT_SCORE_MANUFACTURER_DATA;
  }
  if (target.serviceUuids.length > 0 && containsAll(probe.serviceUuids, target.serviceUuids)) {
    score += FINGERPRINT_SCORE_SERVICE_UUID;
  }
  if (target.signatureIds.length > 0 && intersects(target.signatureIds, probe.signatureIds)) {
    score += FINGERPRINT_SCORE_SIGNATURE;
  }
  return score;
}

/**
 * 自有设备匹配器。
 *
 * 判定顺序（文档落地点五）：
 * 1. **地址直配** —— `virtualAddress` 非空且相等，最高置信，直接返回；
 * 2. **指纹打分** —— 过阈值 5 分认作同一台，多台命中取最高分；
 * 3. 都不过 → 不是自有设备。
 *
 * **拉黑只挡指纹、不挡地址直配**：用户点「这不是我的」纠正的是「同款设备被指纹误认」，
 * 而地址相等就是同一台设备本身 —— 若连地址都挡掉，用户会看到自己的设备被系统「遗忘」，
 * 那比误认更糟。这条不对称规则是刻意的，单测钉着它。
 */
export class FieldwatchOwnDeviceMatcher {
  /** 对一条观测，判断它属于哪台自有设备。 */
  match(probe: OwnDeviceProbe, devices: OwnDevice[]): OwnDeviceMatch {
    const byAddress: OwnDeviceMatch = this.matchByAddress(probe, devices);
    if (byAddress.isMatch()) return byAddress;
    return this.matchByFingerprint(probe, devices);
  }

  /** 地址直配。 */
  private matchByAddress(probe: OwnDeviceProbe, devices: OwnDevice[]): OwnDeviceMatch {
    const result: OwnDeviceMatch = new OwnDeviceMatch();
    if (probe.address.length === 0) return result;
    devices.forEach((device: OwnDevice): void => {
      if (result.isMatch()) return;
      if (device.virtualAddress.length > 0 && device.virtualAddress === probe.address) {
        result.deviceId = device.id;
        result.reason = OwnDeviceMatchReason.ADDRESS;
        result.score = ADDRESS_MATCH_SCORE;
      }
    });
    return result;
  }

  /** 指纹打分；跳过被拉黑的指纹。 */
  private matchByFingerprint(probe: OwnDeviceProbe, devices: OwnDevice[]): OwnDeviceMatch {
    const result: OwnDeviceMatch = new OwnDeviceMatch();
    devices.forEach((device: OwnDevice): void => {
      if (this.isDenied(device, probe)) {
        logger.debug(TAG, '指纹被拉黑，跳过: ' + device.id);
        return;
      }
      const score: number = fingerprintScore(device.fingerprint, probe);
      if (score < FINGERPRINT_MATCH_THRESHOLD) return;
      // 严格大于才替换：分数相同时保留先出现的那台，保证顺序确定（可测）。
      if (score > result.score) {
        result.deviceId = device.id;
        result.reason = OwnDeviceMatchReason.FINGERPRINT;
        result.score = score;
      }
    });
    return result;
  }

  /** 该观测是否命中了这台设备的某条拉黑指纹。 */
  private isDenied(device: OwnDevice, probe: OwnDeviceProbe): boolean {
    let denied: boolean = false;
    device.denyFingerprints.forEach((entry: OwnDeviceFingerprint): void => {
      if (fingerprintScore(entry, probe) >= FINGERPRINT_MATCH_THRESHOLD) denied = true;
    });
    return denied;
  }
}
