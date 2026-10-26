import { describe, it, expect } from '@ohos/hypium';
import { HuntSample, huntRecentSpread } from '../main/ets/fieldwatch/domain/FieldwatchHunt';
import {
  FIND_TROUBLE_AFTER_MS, FindCandidate, findTroubleKeys, mergeFindCandidates, resolveLiveKey
} from '../main/ets/fieldwatch/domain/FieldwatchFindModel';
import { OwnDeviceFingerprint, OwnDeviceKind, OwnDeviceProfile } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';

function samples(base: number, values: number[]): HuntSample[] {
  return values.map((value: number, index: number): HuntSample => new HuntSample(value, base + index * 100));
}

export default function fieldwatchFindModelTest() {
  describe('FieldwatchFindModel', () => {
    // 「晃一晃确认」的判据：拿起来晃动会让最近几秒的强度极差明显变大，
    // 静止设备不会。这里钉住三件事：窗口外的样本不算、少于两条不算、未测量值不算。
    it('measures spread only inside the window and only on measured samples', 0, () => {
      const now: number = 1000000;
      // 窗口内：-80 → -70，极差 10。
      const moving: HuntSample[] = samples(now - 1500, [-80, -75, -70]);
      expect(huntRecentSpread(moving, now, 3000)).assertEqual(10);
      // 窗口外的老样本（更早的大起伏）不能算进本次晃动。
      const stale: HuntSample[] = [new HuntSample(-120, now - 10000), new HuntSample(-70, now - 500)];
      expect(huntRecentSpread(stale, now, 3000)).assertEqual(0);
      // 未测量值（127）必须被排除，否则极差会变成 200 以上。
      const withSentinel: HuntSample[] = [new HuntSample(127, now - 600), new HuntSample(-70, now - 500)];
      expect(huntRecentSpread(withSentinel, now, 3000)).assertEqual(0);
      // 只有一条样本谈不上起伏。
      expect(huntRecentSpread([new HuntSample(-60, now - 100)], now, 3000)).assertEqual(0);
    });

    it('keeps the claim (and trouble) timing constant explicit', 0, () => {
      // 10 秒是 A.4 写死的「WAITING 超 10 秒自动展开排查卡」。
      // 数值改了就等于改验收标准，所以钉在单测里。
      expect(FIND_TROUBLE_AFTER_MS).assertEqual(10000);
    });

    it('gives three trouble keys and varies the third by device kind', 0, () => {
      const headphones: string[] = findTroubleKeys('headphones');
      expect(headphones.length).assertEqual(3);
      const other: string[] = findTroubleKeys('other');
      expect(other.length).assertEqual(3);
      // 耳机/音箱的第三条讲「放回盒里会静音」，其它设备换成「从贴着的东西上取下来」。
      expect(headphones[2] === other[2]).assertFalse();
    });

    it('merges claimed, paired and scanned without duplicating by address', 0, () => {
      const claimed: FindCandidate[] = [new FindCandidate('ble:AA:BB:CC:DD:EE:FF', 'AA:BB:CC:DD:EE:FF', '我的耳机', 'own-1', 'own', false, 5)];
      // 同一台同时出现在配对名单里：必须被去重掉，否则列表里会出现两个「我的耳机」。
      const paired: FindCandidate[] = [
        new FindCandidate('ble:aa-bb-cc-dd-ee-ff', 'aa-bb-cc-dd-ee-ff', 'Buddy', '', 'paired', false, 0),
        new FindCandidate('ble:11:22:33:44:55:66', '11:22:33:44:55:66', '音箱', '', 'paired', true, 0)
      ];
      const scanned: FindCandidate[] = [new FindCandidate('ble:11:22:33:44:55:66', '11:22:33:44:55:66', '音箱(扫描)', '', 'scan', false, 9)];
      const merged: FindCandidate[] = mergeFindCandidates(claimed, paired, scanned);
      expect(merged.length).assertEqual(2);
      // 已认领的排第一（再次找的点击预算是 2 次，它必须一眼可见）。
      expect(merged[0].profileId).assertEqual('own-1');
      expect(merged[0].claimed()).assertTrue();
      // 配对名单里的那台保留 inUse 标记。
      expect(merged[1].inUse).assertTrue();
      expect(merged[1].source).assertEqual('paired');
    });

    it('resolves the live key of a claimed profile by address fallback', 0, () => {
      const profile: OwnDeviceProfile = new OwnDeviceProfile('own-2', '', 'AA:BB:CC:DD:EE:FF', 'ble:AA:BB:CC:DD:EE:FF',
        '我的手表', OwnDeviceKind.WATCH, -1, OwnDeviceFingerprint.empty(), 'scan');
      // 键完全一致：直接命中。
      expect(resolveLiveKey(profile, ['ble:AA:BB:CC:DD:EE:FF', 'ble:11:22:33:44:55:66'])).assertEqual('ble:AA:BB:CC:DD:EE:FF');
      // 档案里的键过期了（重新配对后地址变了）：按地址在新列表里找回来。
      const moved: OwnDeviceProfile = new OwnDeviceProfile('own-3', '', 'aa-bb-cc-dd-ee-ff', 'ble:OLD:OLD',
        '我的手表', OwnDeviceKind.WATCH, -1, OwnDeviceFingerprint.empty(), 'scan');
      expect(resolveLiveKey(moved, ['ble:aa:bb:cc:dd:ee:ff'])).assertEqual('ble:aa:bb:cc:dd:ee:ff');
      // 都不在列表里：返回空串，调用方据此显示「现在还没听到它」。
      expect(resolveLiveKey(moved, ['ble:11:22:33:44:55:66'])).assertEqual('');
    });
  });
}
