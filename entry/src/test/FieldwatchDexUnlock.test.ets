import { describe, it, expect } from '@ohos/hypium';
import {
  decodeAnnounced, DexUnlock, encodeAnnounced, pendingUnlock, reconcileAnnounced
} from '../main/ets/fieldwatch/domain/FieldwatchDexUnlock';
import { DexEntry, DexRarity } from '../main/ets/fieldwatch/domain/FieldwatchDex';

function entry(id: string, seen: boolean, lastSeenAt: number): DexEntry {
  const item: DexEntry = new DexEntry(id, id);
  item.seen = seen;
  item.lastSeenAt = lastSeenAt;
  item.rarity = DexRarity.COMMON;
  return item;
}

export default function fieldwatchDexUnlockTest() {
  describe('FieldwatchDexUnlock', () => {
    // 核心：只有**没弹过**的才弹；弹过的不再弹（不得每次进页弹）。
    it('prompts only for entries never announced', 0, () => {
      const entries: DexEntry[] = [entry('a', true, 100), entry('b', true, 200)];
      // 都没弹过 → 弹一个（最近见到的 b）。
      const first: DexEntry[] = pendingUnlock(entries, []);
      expect(first.length).assertEqual(1);
      expect(first[0].fleetId).assertEqual('b');
      // b 弹过之后 → 轮到 a。
      const second: DexEntry[] = pendingUnlock(entries, ['b']);
      expect(second.length).assertEqual(1);
      expect(second[0].fleetId).assertEqual('a');
      // 都弹过 → 不弹。
      expect(pendingUnlock(entries, ['a', 'b']).length).assertEqual(0);
    });

    // 未点亮的条目永远不弹。
    it('never prompts for locked entries', 0, () => {
      const entries: DexEntry[] = [entry('a', false, 100), entry('b', false, 200)];
      expect(pendingUnlock(entries, []).length).assertEqual(0);
    });

    // 同时点亮多台时只弹一个，避免连续打断。
    it('prompts at most once per call', 0, () => {
      const entries: DexEntry[] = [
        entry('a', true, 100), entry('b', true, 200), entry('c', true, 300)
      ];
      expect(pendingUnlock(entries, []).length).assertEqual(1);
    });

    // 关键：老用户升级进本版本时，已有点亮不该集体弹层。
    it('marks existing unlocks as announced on first run', 0, () => {
      const entries: DexEntry[] = [entry('a', true, 100), entry('b', true, 200), entry('c', false, 0)];
      const reconciled: string[] = reconcileAnnounced(entries, []);
      expect(reconciled.length).assertEqual(2);
      expect(reconciled.indexOf('a') >= 0).assertTrue();
      expect(reconciled.indexOf('b') >= 0).assertTrue();
      // 未点亮的不进集合。
      expect(reconciled.indexOf('c')).assertEqual(-1);
      // 对齐之后立刻不该再弹。
      expect(pendingUnlock(entries, reconciled).length).assertEqual(0);
    });

    it('keeps existing marks and adds new ones', 0, () => {
      const entries: DexEntry[] = [entry('a', true, 100), entry('b', true, 200)];
      const merged: string[] = reconcileAnnounced(entries, ['x']);
      expect(merged.indexOf('x') >= 0).assertTrue();
      expect(merged.indexOf('a') >= 0).assertTrue();
      // 不重复。
      const unique: string[] = [];
      merged.forEach((id: string): void => { if (unique.indexOf(id) < 0) unique.push(id); });
      expect(unique.length).assertEqual(merged.length);
    });

    it('round-trips the announced set', 0, () => {
      const ids: string[] = ['a', 'b'];
      const back: string[] = decodeAnnounced(encodeAnnounced(ids));
      expect(back.length).assertEqual(2);
      expect(back[0]).assertEqual('a');
      expect(decodeAnnounced('').length).assertEqual(0);
      expect(decodeAnnounced('\n\n').length).assertEqual(0);
    });

    // 弹层要能表达「积分变化」与「是否升级」。
    it('reports score delta and level change', 0, () => {
      const unlock: DexUnlock = new DexUnlock();
      unlock.scoreBefore = 28;
      unlock.scoreAfter = 31;
      expect(unlock.delta()).assertEqual(3);
      // 同级不报升级。
      unlock.levelBeforeKey = 'app.string.fieldwatch_dex_level_observer';
      unlock.levelAfterKey = 'app.string.fieldwatch_dex_level_observer';
      expect(unlock.leveledUp()).assertFalse();
      // 跨级才报。
      unlock.levelAfterKey = 'app.string.fieldwatch_dex_level_explorer';
      expect(unlock.leveledUp()).assertTrue();
      // 缺键时不报（不做假升级）。
      const blank: DexUnlock = new DexUnlock();
      expect(blank.leveledUp()).assertFalse();
    });
  });
}
