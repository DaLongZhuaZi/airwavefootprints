import { describe, expect, it } from '@ohos/hypium';
import { FieldwatchSettingsRepository } from '../main/ets/fieldwatch/data/FieldwatchSettingsRepository';
import { AppSettings } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { FilterDefinition } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { WatchTarget } from '../main/ets/fieldwatch/domain/FieldwatchModels';

export default function fieldwatchSettingsBackupTest() {
  describe('FieldwatchSettingsBackup', () => {
    // §12.7 要求备份包含四类内容：设置开关、当前过滤器、过滤预设、命名设备与签名关注项。
    // 补齐前只导出 9 个开关，导完再导入会**静默丢掉**后三类。

    it('backup carries the structured sections next to the switches', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const settings: AppSettings = new AppSettings();
      settings.scanIntensity = 'saver';
      const backup: string = repository.exportBackup(settings);
      expect(backup.indexOf('fieldwatch_settings_v1') === 0).assertTrue();
      expect(backup.indexOf('scanIntensity=saver') >= 0).assertTrue();
      // 雷达显示设置此前也被漏掉，一并补上。
      expect(backup.indexOf('radarLabelFields=') >= 0).assertTrue();
      expect(backup.indexOf('radarIconSize=') >= 0).assertTrue();
      // 结构化的三行只在本地有内容时才出现，避免写出空壳。
      repository.saveFilterState(new FilterDefinition());
      const withFilter: string = repository.exportBackup(settings);
      expect(withFilter.indexOf('filter=') >= 0).assertTrue();
    });

    it('round trips the current filter through a backup', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const filter: FilterDefinition = new FilterDefinition();
      filter.minimumRssi = -71;
      filter.namedOnly = true;
      repository.saveFilterState(filter);
      const backup: string = repository.exportBackup(new AppSettings());
      // 先破坏本地值，确认恢复确实来自备份而不是残留。
      const cleared: FilterDefinition = new FilterDefinition();
      cleared.minimumRssi = -20;
      repository.saveFilterState(cleared);
      expect(repository.importBackup(backup)).assertTrue();
      const restored: FilterDefinition | undefined = repository.loadFilterState();
      expect(restored !== undefined).assertTrue();
      if (restored !== undefined) {
        expect(restored.minimumRssi).assertEqual(-71);
        expect(restored.namedOnly).assertTrue();
      }
    });

    it('round trips the watchlist through a backup', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const list: Array<WatchTarget> = [];
      list.push(new WatchTarget('ble:AA:BB:CC:DD:EE', 'sig-1', '我的设备', true, '备注'));
      repository.saveWatchlist(list);
      const backup: string = repository.exportBackup(new AppSettings());
      expect(backup.indexOf('watchlist=') >= 0).assertTrue();
      repository.saveWatchlist([]);
      expect(repository.loadWatchlist().length).assertEqual(0);
      expect(repository.importBackup(backup)).assertTrue();
      const restored: Array<WatchTarget> = repository.loadWatchlist();
      expect(restored.length).assertEqual(1);
      expect(restored[0].label).assertEqual('我的设备');
      expect(restored[0].alert).assertTrue();
    });

    it('rejects a backup whose header is not recognised', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      expect(repository.importBackup('something_else_v9\ndarkMode=true\n')).assertFalse();
      expect(repository.importBackup('')).assertFalse();
    });

    it('ignores malformed structured sections instead of poisoning local settings', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const good: FilterDefinition = new FilterDefinition();
      good.minimumRssi = -70;
      repository.saveFilterState(good);
      // 半截 JSON 必须被拒；本地值保持不动。
      expect(repository.importBackup('fieldwatch_settings_v1\nfilter={"logic":\n')).assertTrue();
      const kept: FilterDefinition | undefined = repository.loadFilterState();
      expect(kept !== undefined).assertTrue();
      if (kept !== undefined) expect(kept.minimumRssi).assertEqual(-70);
      // 类型不对（数组写进对象位、对象写进数组位）同样要拒。
      repository.saveWatchlist([new WatchTarget('ble:11:22:33:44:55', 'sig-2', '保留', false, '')]);
      expect(repository.importBackup('fieldwatch_settings_v1\nwatchlist={"a":1}\n')).assertTrue();
      expect(repository.loadWatchlist().length).assertEqual(1);
    });

    it('keeps local structured state when an older backup omits those lines', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      repository.saveWatchlist([new WatchTarget('ble:99:88:77:66:55', 'sig-3', '旧版保留', false, '')]);
      const legacy: string = 'fieldwatch_settings_v1\ndarkMode=true\n';
      expect(repository.importBackup(legacy)).assertTrue();
      // 旧备份没有 watchlist 行 —— 不能把本地关注列表清空。
      expect(repository.loadWatchlist().length).assertEqual(1);
    });
  });
}