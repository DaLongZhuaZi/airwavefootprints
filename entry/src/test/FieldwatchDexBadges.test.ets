import { describe, it, expect } from '@ohos/hypium';
import {
  consecutiveDays, dexBadges, DexBadge, dexLevels, DexLevel, dexScore, entryScore, levelOf,
  levelProgress, DexLevelProgress, startOfDay
} from '../main/ets/fieldwatch/domain/FieldwatchDexBadges';
import { DexEntry, DexRarity } from '../main/ets/fieldwatch/domain/FieldwatchDex';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';

function entry(id: string, rarity: DexRarity, seen: boolean): DexEntry {
  const item: DexEntry = new DexEntry(id, id);
  item.rarity = rarity;
  item.seen = seen;
  item.category = SignatureClass.OTHER;
  return item;
}

const DAY: number = 24 * 60 * 60 * 1000;

export default function fieldwatchDexBadgesTest() {
  describe('FieldwatchDexBadges', () => {
    // 稀有度口径不变（库内同类数量），因此分数必须只由稀有度决定。
    it('scores only by rarity, never by name or category', 0, () => {
      expect(entryScore(entry('a', DexRarity.COMMON, true))).assertEqual(1);
      expect(entryScore(entry('b', DexRarity.UNCOMMON, true))).assertEqual(2);
      expect(entryScore(entry('c', DexRarity.RARE, true))).assertEqual(4);
      expect(entryScore(entry('d', DexRarity.EPIC, true))).assertEqual(8);
      // 未点亮不计分。
      expect(entryScore(entry('e', DexRarity.EPIC, false))).assertEqual(0);
    });

    it('sums the score over unlocked entries only', 0, () => {
      const entries: DexEntry[] = [
        entry('a', DexRarity.COMMON, true),
        entry('b', DexRarity.RARE, true),
        entry('c', DexRarity.EPIC, false)
      ];
      expect(dexScore(entries)).assertEqual(5);
    });

    // 四级等级：观察者 → 探索者 → 猎手 → 大师。
    it('maps score onto four levels', 0, () => {
      const levels: DexLevel[] = dexLevels();
      expect(levels.length).assertEqual(4);
      expect(levels[0].titleKey.indexOf('observer') > 0).assertTrue();
      expect(levels[1].titleKey.indexOf('explorer') > 0).assertTrue();
      expect(levels[2].titleKey.indexOf('hunter') > 0).assertTrue();
      expect(levels[3].titleKey.indexOf('master') > 0).assertTrue();
      // 门槛递增。
      expect(levels[0].threshold < levels[1].threshold).assertTrue();
      expect(levels[1].threshold < levels[2].threshold).assertTrue();
      expect(levels[2].threshold < levels[3].threshold).assertTrue();
    });

    it('reports the current level and what is left to the next', 0, () => {
      expect(levelOf(0).level).assertEqual(1);
      expect(levelOf(29).level).assertEqual(1);
      expect(levelOf(30).level).assertEqual(2);
      expect(levelOf(90).level).assertEqual(3);
      expect(levelOf(200).level).assertEqual(4);
      const progress: DexLevelProgress = levelProgress(10);
      expect(progress.current.level).assertEqual(1);
      expect(progress.isMax()).assertFalse();
      expect(progress.remain).assertEqual(20);
      // 满级时没有下一级，剩余为 0。
      const maxed: DexLevelProgress = levelProgress(500);
      expect(maxed.isMax()).assertTrue();
      expect(maxed.remain).assertEqual(0);
    });

    // 四枚勋章。
    it('awards the four badges from catalog data', 0, () => {
      const empty: DexBadge[] = dexBadges([], 0);
      expect(empty.length).assertEqual(4);
      empty.forEach((badge: DexBadge): void => { expect(badge.earned).assertFalse(); });
      // 极稀有勋章：点亮一条 EPIC 即可。
      const epicEntries: DexEntry[] = [entry('a', DexRarity.EPIC, true)];
      const epicBadges: DexBadge[] = dexBadges(epicEntries, 0);
      expect(epicBadges[1].id).assertEqual('first_epic');
      expect(epicBadges[1].earned).assertTrue();
      // 连续 7 天。
      expect(dexBadges([], 7)[3].earned).assertTrue();
      expect(dexBadges([], 6)[3].earned).assertFalse();
    });

    // 集齐一类：需要该类全部点亮。
    it('awards the full-class badge only when a whole class is unlocked', 0, () => {
      const partial: DexEntry[] = [entry('a', DexRarity.COMMON, true), entry('b', DexRarity.COMMON, false)];
      expect(dexBadges(partial, 0)[2].earned).assertFalse();
      const full: DexEntry[] = [entry('a', DexRarity.COMMON, true), entry('b', DexRarity.COMMON, true)];
      expect(dexBadges(full, 0)[2].earned).assertTrue();
    });

    // 连续天数：允许今天还没打开（从昨天算），断一天必须归零。
    it('counts consecutive discovery days honestly', 0, () => {
      const now: number = new Date(2026, 9, 27, 15, 0, 0).getTime();
      const today: number = startOfDay(now);
      // 今天 + 昨天 + 前天 = 3。
      expect(consecutiveDays([today - 2 * DAY, today - DAY, today], now)).assertEqual(3);
      // 今天还没打开，但从昨天起连续 2 天。
      expect(consecutiveDays([today - 2 * DAY, today - DAY], now)).assertEqual(2);
      // 断一天：只有前天有记录 → 0。
      expect(consecutiveDays([today - 2 * DAY], now)).assertEqual(0);
      // 空集合。
      expect(consecutiveDays([], now)).assertEqual(0);
      // 7 天连续。
      const week: number[] = [];
      for (let i: number = 0; i < 7; i += 1) week.push(today - i * DAY);
      expect(consecutiveDays(week, now)).assertEqual(7);
    });
  });
}
