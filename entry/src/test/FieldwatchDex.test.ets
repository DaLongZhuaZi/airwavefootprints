import { describe, it, expect } from '@ohos/hypium';
import {
  buildDex, DexEntry, DexRarity, DEX_COMMON_COUNT, DEX_RARE_COUNT, dexDisplayName, isEpicClass,
  rarityOf, sortDex, summarizeDex
} from '../main/ets/fieldwatch/domain/FieldwatchDex';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureFleet } from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels';

function fleet(id: string, category: SignatureClass, enabled: boolean = true): SignatureFleet {
  const item: SignatureFleet = new SignatureFleet(id, id, category);
  item.enabled = enabled;
  return item;
}

export default function fieldwatchDexTest() {
  describe('FieldwatchDex', () => {
    it('marks professional device classes as epic', 0, () => {
      expect(isEpicClass(SignatureClass.SURVEILLANCE)).assertTrue();
      expect(isEpicClass(SignatureClass.LAW_ENFORCEMENT)).assertTrue();
      expect(isEpicClass(SignatureClass.DRONE)).assertTrue();
      expect(isEpicClass(SignatureClass.HACKING)).assertTrue();
      expect(isEpicClass(SignatureClass.PHONE)).assertFalse();
    });

    it('derives rarity from how many peers share the class', 0, () => {
      const many: SignatureFleet[] = [];
      for (let i: number = 0; i < DEX_COMMON_COUNT; i += 1) many.push(fleet('p' + i.toString(), SignatureClass.PHONE));
      expect(rarityOf(many[0], many)).assertEqual(DexRarity.COMMON);
      const few: SignatureFleet[] = [fleet('a', SignatureClass.LOCK), fleet('b', SignatureClass.LOCK)];
      expect(rarityOf(few[0], few)).assertEqual(DexRarity.RARE);
      const mid: SignatureFleet[] = [];
      for (let i: number = 0; i < DEX_RARE_COUNT + 2; i += 1) mid.push(fleet('m' + i.toString(), SignatureClass.AUDIO));
      expect(rarityOf(mid[0], mid)).assertEqual(DexRarity.UNCOMMON);
    });

    it('skips disabled fleets so no cell can never light up', 0, () => {
      const fleets: SignatureFleet[] = [fleet('on', SignatureClass.PHONE), fleet('off', SignatureClass.PHONE, false)];
      const entries: DexEntry[] = buildDex(fleets, new Map<string, number[]>(), []);
      expect(entries.length).assertEqual(1);
      expect(entries[0].fleetId).assertEqual('on');
    });

    it('lights an entry up only when the history says it was seen', 0, () => {
      const fleets: SignatureFleet[] = [fleet('seen', SignatureClass.PHONE), fleet('unseen', SignatureClass.AUDIO)];
      const stats: Map<string, number[]> = new Map<string, number[]>();
      stats.set('seen', [7, 1793043000000]);
      const entries: DexEntry[] = buildDex(fleets, stats, []);
      const seenEntry: DexEntry = entries[0];
      expect(seenEntry.seen).assertTrue();
      expect(seenEntry.sightings).assertEqual(7);
      expect(seenEntry.lastSeenAt).assertEqual(1793043000000);
      expect(entries[1].seen).assertFalse();
      expect(dexDisplayName(entries[1])).assertEqual('？？？');
      expect(dexDisplayName(seenEntry)).assertEqual('seen');
    });

    it('summarises totals and today counts consistently', 0, () => {
      const fleets: SignatureFleet[] = [
        fleet('a', SignatureClass.PHONE), fleet('b', SignatureClass.AUDIO), fleet('c', SignatureClass.LOCK)
      ];
      const stats: Map<string, number[]> = new Map<string, number[]>();
      stats.set('a', [1, 100]);
      stats.set('b', [2, 200]);
      const entries: DexEntry[] = buildDex(fleets, stats, ['a']);
      const summary = summarizeDex(entries, ['a']);
      expect(summary.total).assertEqual(3);
      expect(summary.seen).assertEqual(2);
      expect(summary.newToday).assertEqual(1);
      expect(summarizeDex([], []).ratio()).assertEqual(0);
    });

    // **已点亮的排前面**：611 条特征库下，把已点亮的埋到页尾等于看不见进度。
    it('sorts unlocked entries first, then by rarity', 0, () => {
      const fleets: SignatureFleet[] = [
        fleet('seen-common', SignatureClass.PHONE),
        fleet('unseen-surv', SignatureClass.SURVEILLANCE),
        fleet('unseen-lock', SignatureClass.LOCK)
      ];
      const stats: Map<string, number[]> = new Map<string, number[]>();
      stats.set('seen-common', [3, 100]);
      const sorted: DexEntry[] = sortDex(buildDex(fleets, stats, []));
      // 已点亮的提到最前；未点亮的按稀有度（极稀有 → 稀有）。
      expect(sorted[0].fleetId).assertEqual('seen-common');
      expect(sorted[1].fleetId).assertEqual('unseen-surv');
      expect(sorted[2].fleetId).assertEqual('unseen-lock');
    });
  });
}
