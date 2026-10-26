import { describe, it, expect } from '@ohos/hypium';
import {
  OwnDeviceCandidate, OwnDeviceFingerprint, OwnDeviceKind, OwnDeviceProfile, OwnMatchReason, OwnMatchResult,
  deviceAddressOfKey, kindFromDeviceClass, normalizeDeviceAddress
} from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';
import {
  FieldwatchOwnDeviceMatcher, OWN_MATCH_THRESHOLD, ownFingerprintDenied, ownFingerprintScore
} from '../main/ets/fieldwatch/domain/FieldwatchOwnDeviceMatcher';

/** 指纹快照的简写构造，省得每个用例都写四个空数组。 */
function fp(name: string, manufacturers: number[], uuids: string[], signatures: string[]): OwnDeviceFingerprint {
  return new OwnDeviceFingerprint(name, manufacturers, uuids, signatures);
}

/** 只有指纹的档案：id 与指纹，其余锚留空。 */
function profileOf(id: string, fingerprint: OwnDeviceFingerprint): OwnDeviceProfile {
  return new OwnDeviceProfile(id, '', '', 'ble:00:00:00:00:00:00', '', OwnDeviceKind.OTHER, -1, fingerprint, 'scan');
}

/** 带地址的档案。 */
function profileAt(id: string, address: string, fingerprint: OwnDeviceFingerprint): OwnDeviceProfile {
  return new OwnDeviceProfile(id, '', address, 'ble:' + address, '', OwnDeviceKind.OTHER, -1, fingerprint, 'paired');
}

/** 只带指纹的候选：地址与持久锚都留空，确保结论只可能来自指纹。 */
function candidateOf(fingerprint: OwnDeviceFingerprint): OwnDeviceCandidate {
  return new OwnDeviceCandidate('', '', '', fingerprint);
}

export default function fieldwatchOwnDeviceTest() {
  describe('FieldwatchOwnDevice', () => {
    it('normalizes addresses to upper case colon pairs', 0, () => {
      expect(normalizeDeviceAddress('aa:bb:cc:dd:ee:ff')).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(normalizeDeviceAddress(' AA-BB-CC-DD-EE-FF ')).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(normalizeDeviceAddress('aabbccddeeff')).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(normalizeDeviceAddress('AA BB CC DD EE FF')).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(normalizeDeviceAddress('  ')).assertEqual('');
      // 非十六进制串（持久 ID 一类）只大写了事，不能被按字节重排成 MAC。
      expect(normalizeDeviceAddress('dev-7F3A')).assertEqual('DEV-7F3A');
    });

    it('extracts the address from a scan key', 0, () => {
      expect(deviceAddressOfKey('ble:AA:BB:CC:DD:EE:FF')).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(deviceAddressOfKey('nearlink:AA:BB')).assertEqual('AA:BB');
      // 没有前缀的裸地址不能被当成「前缀:地址」切掉第一段。
      expect(deviceAddressOfKey('AA:BB:CC')).assertEqual('AA:BB:CC');
      expect(deviceAddressOfKey('aabbcc')).assertEqual('aabbcc');
    });

    it('maps class of device to own device kinds', 0, () => {
      // 音频/视频大类（0x04）：可穿戴耳机、免提、头戴耳机都算耳机。
      expect(kindFromDeviceClass(0x04, 0x01)).assertEqual(OwnDeviceKind.HEADPHONES);
      expect(kindFromDeviceClass(0x04, 0x02)).assertEqual(OwnDeviceKind.HEADPHONES);
      expect(kindFromDeviceClass(0x04, 0x05)).assertEqual(OwnDeviceKind.HEADPHONES);
      // 扬声器、便携音频、HiFi 都算音箱；车载音响单独算车。
      expect(kindFromDeviceClass(0x04, 0x04)).assertEqual(OwnDeviceKind.SPEAKER);
      expect(kindFromDeviceClass(0x04, 0x06)).assertEqual(OwnDeviceKind.SPEAKER);
      expect(kindFromDeviceClass(0x04, 0x09)).assertEqual(OwnDeviceKind.SPEAKER);
      expect(kindFromDeviceClass(0x04, 0x07)).assertEqual(OwnDeviceKind.CAR);
      // 可穿戴大类（0x07）只有腕表；计算机大类下的可穿戴计算机也算手表。
      expect(kindFromDeviceClass(0x07, 0x01)).assertEqual(OwnDeviceKind.WATCH);
      expect(kindFromDeviceClass(0x07, 0x03)).assertEqual(OwnDeviceKind.OTHER);
      expect(kindFromDeviceClass(0x01, 0x06)).assertEqual(OwnDeviceKind.WATCH);
      // 手机、网卡等与「找东西」无关的类别，以及未知 CoD（-1），一律 OTHER。
      expect(kindFromDeviceClass(0x02, 0x03)).assertEqual(OwnDeviceKind.OTHER);
      expect(kindFromDeviceClass(-1, -1)).assertEqual(OwnDeviceKind.OTHER);
    });

    it('labels a profile with a three level fallback', 0, () => {
      const profile: OwnDeviceProfile = profileAt('p1', 'AA:BB:CC:DD:EE:FF', OwnDeviceFingerprint.empty());
      profile.displayName = 'FreeBuds';
      expect(profile.label()).assertEqual('FreeBuds');
      profile.customName = '我的耳机';
      expect(profile.label()).assertEqual('我的耳机');
      profile.customName = '   ';
      profile.displayName = '  ';
      // 领域层不塞默认文案，空串留给 UI 走资源键。
      expect(profile.label()).assertEqual('');
      // 构造时已归一化地址，调用方不用自己再转一次。
      expect(profile.virtualAddress).assertEqual('AA:BB:CC:DD:EE:FF');
    });

    it('scores name, manufacturer, service uuid and signature independently', 0, () => {
      const empty: OwnDeviceFingerprint = OwnDeviceFingerprint.empty();
      expect(ownFingerprintScore(fp('Buds', [], [], []), fp('  buds ', [], [], []))).assertEqual(3);
      expect(ownFingerprintScore(fp('', [76], [], []), fp('', [117, 76], [], []))).assertEqual(2);
      expect(ownFingerprintScore(fp('', [], ['U1'], []), fp('', [], ['U1'], []))).assertEqual(2);
      expect(ownFingerprintScore(fp('', [], [], ['fleet_a']), fp('', [], [], ['FLEET_A']))).assertEqual(2);
      // 双方都得有值：空名对空名、空集对空集都不构成证据。
      expect(ownFingerprintScore(empty, empty)).assertEqual(0);
      expect(ownFingerprintScore(fp('', [], ['U1'], []), empty)).assertEqual(0);
      // 0 是「厂商未知」哨兵，不能靠它凑出一个毫无信息量的交集。
      expect(ownFingerprintScore(fp('', [0], [], []), fp('', [0], [], []))).assertEqual(0);
    });

    it('requires every claimed service uuid before giving the point', 0, () => {
      const claimed: OwnDeviceFingerprint = fp('', [], ['0000180F-0000-1000-8000-00805F9B34FB', '0000FE2C-0000-1000-8000-00805F9B34FB'], []);
      const partial: OwnDeviceFingerprint = fp('', [], ['0000180F-0000-1000-8000-00805F9B34FB'], []);
      const full: OwnDeviceFingerprint = fp('', [], ['0000180F-0000-1000-8000-00805F9B34FB', '0000FE2C-0000-1000-8000-00805F9B34FB'], []);
      // 部分包含不加分：通用 GATT 服务几乎每台设备都有，交集式判定会乱配对。
      expect(ownFingerprintScore(claimed, partial)).assertEqual(0);
      expect(ownFingerprintScore(claimed, full)).assertEqual(2);
      // 当前广播比认领时多一个服务（固件升级）不影响；大小写与分隔符写法也不影响。
      expect(ownFingerprintScore(fp('', [], ['0000180f00001000800000805f9b34fb'], []), full)).assertEqual(2);
    });

    it('matches by address even when the fingerprint is completely different', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const profile: OwnDeviceProfile = profileAt('mine', 'AA:BB:CC:DD:EE:FF', fp('FreeBuds', [76], ['U1'], ['fleet_a']));
      const candidate: OwnDeviceCandidate = new OwnDeviceCandidate('ble:aa-bb-cc-dd-ee-ff', 'aa:bb:cc:dd:ee:ff', '',
        fp('Neighbour Speaker', [117], ['U9'], ['fleet_z']));
      const result: OwnMatchResult = matcher.match([profile], candidate);
      expect(result.matched).assertTrue();
      expect(result.reason).assertEqual(OwnMatchReason.ADDRESS);
      expect(result.profileId).assertEqual('mine');
      // 档位分只用于排序，不代表相似度。
      expect(result.score).assertEqual(90);
    });

    it('prefers the persistent id over the address', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const byAddress: OwnDeviceProfile = profileAt('addr-only', 'AA:BB:CC:DD:EE:FF', OwnDeviceFingerprint.empty());
      const byPersistent: OwnDeviceProfile = new OwnDeviceProfile('persistent', 'persist-01', '11:22:33:44:55:66',
        'ble:11:22:33:44:55:66', '', OwnDeviceKind.OTHER, -1, OwnDeviceFingerprint.empty(), 'paired');
      const candidate: OwnDeviceCandidate = new OwnDeviceCandidate('ble:AA:BB:CC:DD:EE:FF', 'AA:BB:CC:DD:EE:FF', 'persist-01',
        OwnDeviceFingerprint.empty());
      const result: OwnMatchResult = matcher.match([byAddress, byPersistent], candidate);
      expect(result.reason).assertEqual(OwnMatchReason.PERSISTENT);
      expect(result.profileId).assertEqual('persistent');
      expect(result.score).assertEqual(100);
      const winner: OwnDeviceProfile | undefined = matcher.best([byAddress, byPersistent], candidate);
      expect(winner !== undefined ? winner.id : '').assertEqual('persistent');
    });

    it('matches on name plus manufacturer at the threshold', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const profile: OwnDeviceProfile = profileOf('buds', fp('FreeBuds Pro', [76], [], []));
      const candidate: OwnDeviceCandidate = candidateOf(fp(' freebuds pro ', [76, 117], [], []));
      expect(ownFingerprintScore(profile.fingerprint, candidate.fingerprint)).assertEqual(OWN_MATCH_THRESHOLD);
      const result: OwnMatchResult = matcher.match([profile], candidate);
      expect(result.matched).assertTrue();
      expect(result.reason).assertEqual(OwnMatchReason.FINGERPRINT);
      expect(result.score).assertEqual(OWN_MATCH_THRESHOLD);
    });

    it('does not match on the name alone', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const profile: OwnDeviceProfile = profileOf('buds', fp('FreeBuds Pro', [], [], []));
      const candidate: OwnDeviceCandidate = candidateOf(fp('FreeBuds Pro', [117], ['U9'], []));
      expect(ownFingerprintScore(profile.fingerprint, candidate.fingerprint)).assertEqual(3);
      const result: OwnMatchResult = matcher.match([profile], candidate);
      expect(result.matched).assertFalse();
      expect(result.reason).assertEqual(OwnMatchReason.NONE);
      expect(result.score).assertEqual(0);
      expect(result.profileId).assertEqual('');
    });

    it('matches on name plus signature', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const profile: OwnDeviceProfile = profileOf('buds', fp('FreeBuds Pro', [], [], ['huawei_freebuds']));
      const candidate: OwnDeviceCandidate = candidateOf(fp('FREEBUDS PRO', [], [], ['huawei_freebuds']));
      const result: OwnMatchResult = matcher.match([profile], candidate);
      expect(result.matched).assertTrue();
      expect(result.reason).assertEqual(OwnMatchReason.FINGERPRINT);
      expect(result.score).assertEqual(5);
    });

    it('denies a fingerprint match that the deny list blocks', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const observed: OwnDeviceFingerprint = fp('FreeBuds Pro', [76], [], []);
      const profile: OwnDeviceProfile = profileOf('buds', observed);
      // 用户点过一次「这不是我的设备」，同一个形态被拉黑。
      profile.denyFingerprints.push(fp('FreeBuds Pro', [76], [], []));
      expect(ownFingerprintDenied(profile, observed)).assertTrue();
      const result: OwnMatchResult = matcher.match([profile], candidateOf(observed));
      expect(result.matched).assertFalse();
      expect(result.reason).assertEqual(OwnMatchReason.DENIED);
      // 被否决的候选不能靠分数混进下游排序。
      expect(result.score).assertEqual(0);
      expect(matcher.best([profile], candidateOf(observed))).assertUndefined();
      // 黑名单只否决「达到阈值」的形态，差得远的观测仍可正常认领。
      expect(ownFingerprintDenied(profile, fp('Sound X', [], [], []))).assertFalse();
    });

    it('keeps address matches despite the deny list', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const observed: OwnDeviceFingerprint = fp('FreeBuds Pro', [76], [], []);
      const profile: OwnDeviceProfile = profileAt('buds', 'AA:BB:CC:DD:EE:FF', observed);
      profile.denyFingerprints.push(observed);
      const candidate: OwnDeviceCandidate = new OwnDeviceCandidate('ble:AA:BB:CC:DD:EE:FF', 'AA:BB:CC:DD:EE:FF', '', observed);
      const result: OwnMatchResult = matcher.match([profile], candidate);
      // 地址是「设备本身」的标识，黑名单只否决「长相」，不否决最强证据。
      expect(result.matched).assertTrue();
      expect(result.reason).assertEqual(OwnMatchReason.ADDRESS);
      expect(result.profileId).assertEqual('buds');
    });

    it('picks the highest scoring profile', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const weak: OwnDeviceProfile = profileOf('weak', fp('FreeBuds Pro', [], [], []));
      const strong: OwnDeviceProfile = profileOf('strong', fp('FreeBuds Pro', [76], [], []));
      const candidate: OwnDeviceCandidate = candidateOf(fp('FreeBuds Pro', [76], [], []));
      const winner: OwnDeviceProfile | undefined = matcher.best([weak, strong], candidate);
      expect(winner !== undefined ? winner.id : '').assertEqual('strong');
      expect(matcher.match([weak, strong], candidate).score).assertEqual(5);
    });

    it('keeps the first profile on a score tie', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const first: OwnDeviceProfile = profileOf('first', fp('FreeBuds Pro', [76], [], []));
      const second: OwnDeviceProfile = profileOf('second', fp('FreeBuds Pro', [76], [], []));
      const candidate: OwnDeviceCandidate = candidateOf(fp('FreeBuds Pro', [76], [], []));
      const firstWinner: OwnDeviceProfile | undefined = matcher.best([first, second], candidate);
      expect(firstWinner !== undefined ? firstWinner.id : '').assertEqual('first');
      expect(matcher.match([first, second], candidate).profileId).assertEqual('first');
      // 换一下顺序就换一台会说明「同分取先出现」没实现；这里顺带钉住它。
      const reversedWinner: OwnDeviceProfile | undefined = matcher.best([second, first], candidate);
      expect(reversedWinner !== undefined ? reversedWinner.id : '').assertEqual('second');
    });

    it('returns NONE for an empty profile list', 0, () => {
      const matcher: FieldwatchOwnDeviceMatcher = new FieldwatchOwnDeviceMatcher();
      const candidate: OwnDeviceCandidate = candidateOf(fp('FreeBuds Pro', [76], ['U1'], ['fleet_a']));
      const result: OwnMatchResult = matcher.match([], candidate);
      expect(result.matched).assertFalse();
      expect(result.reason).assertEqual(OwnMatchReason.NONE);
      expect(result.profileId).assertEqual('');
      expect(result.score).assertEqual(0);
      expect(matcher.best([], candidate)).assertUndefined();
    });
  });
}
