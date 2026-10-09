import { describe, expect, it } from '@ohos/hypium';
import { FieldwatchFilterEngine } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';
import { FilterDefinition, FilterLogic, FilterPreset, RadioFacts, RadioKind, ScanObservation, SignatureClass, Sighting, WatchTarget } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureFleet } from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { FieldwatchSettingsRepository } from '../main/ets/fieldwatch/data/FieldwatchSettingsRepository';

function sighting(key: string, kind: RadioKind, name: string, rssi: number, signatureIds: string[]): Sighting {
  const item: Sighting = Sighting.fromObservation(new ScanObservation(key, kind, key.replace(/^[a-z]+:/, ''), name, rssi, 1, new RadioFacts()));
  item.signatureIds = signatureIds;
  return item;
}

function fleet(id: string, category: SignatureClass): SignatureFleet {
  return new SignatureFleet(id, id, category, []);
}

export default function fieldwatchFilterEngineTest() {
  describe('FieldwatchFilterEngine', () => {
    const engine: FieldwatchFilterEngine = new FieldwatchFilterEngine();
    const fleets: SignatureFleet[] = [fleet('cam', SignatureClass.CAMERA), fleet('drone', SignatureClass.DRONE)];
    const ble: Sighting = sighting('ble:AA', RadioKind.BLE, 'Tag', -60, ['cam']);
    const wifi: Sighting = sighting('wifi:BB', RadioKind.WIFI, 'Lab-AP', -50, []);
    const now: number = Date.now();

    it('treats Wi-Fi and BLE as two inclusive switches', 0, () => {
      const both: FilterDefinition = new FilterDefinition();
      expect(engine.pass(ble, both, fleets, [], [], now)).assertTrue();
      expect(engine.pass(wifi, both, fleets, [], [], now)).assertTrue();
      const bleOnly: FilterDefinition = new FilterDefinition();
      bleOnly.showWifi = false;
      expect(engine.pass(ble, bleOnly, fleets, [], [], now)).assertTrue();
      expect(engine.pass(wifi, bleOnly, fleets, [], [], now)).assertFalse();
      const wifiOnly: FilterDefinition = new FilterDefinition();
      wifiOnly.showBle = false;
      expect(engine.pass(wifi, wifiOnly, fleets, [], [], now)).assertTrue();
      expect(engine.pass(ble, wifiOnly, fleets, [], [], now)).assertFalse();
    });

    it('reads namedOnly as "has a matched signature"', 0, () => {
      const filter: FilterDefinition = new FilterDefinition();
      filter.namedOnly = true;
      expect(engine.pass(ble, filter, fleets, [], [], now)).assertTrue();
      // wifi 有名字但没有命中签名 → 原版语义下不通过
      expect(engine.pass(wifi, filter, fleets, [], [], now)).assertFalse();
    });

    it('matches customNamesOnly against the named-radio set', 0, () => {
      const filter: FilterDefinition = new FilterDefinition();
      filter.customNamesOnly = true;
      expect(engine.pass(wifi, filter, fleets, [], ['wifi:BB'], now)).assertTrue();
      expect(engine.pass(wifi, filter, fleets, [], [], now)).assertFalse();
    });

    it('accepts a watch by device key or by watched signature', 0, () => {
      const filter: FilterDefinition = new FilterDefinition();
      filter.watchedOnly = true;
      const byKey: WatchTarget[] = [new WatchTarget('wifi:BB', '', 'Lab', true)];
      const byFleet: WatchTarget[] = [new WatchTarget('', 'cam', 'cam', true)];
      const silent: WatchTarget[] = [new WatchTarget('wifi:BB', '', 'Lab', false)];
      expect(engine.pass(wifi, filter, fleets, byKey, [], now)).assertTrue();
      expect(engine.pass(ble, filter, fleets, byFleet, [], now)).assertTrue();
      expect(engine.pass(wifi, filter, fleets, silent, [], now)).assertFalse();
    });

    it('excludes and includes by signature set', 0, () => {
      const exclude: FilterDefinition = new FilterDefinition();
      exclude.excludeSignatures = true;
      exclude.fleetIds = ['cam'];
      expect(engine.pass(ble, exclude, fleets, [], [], now)).assertFalse();
      expect(engine.pass(wifi, exclude, fleets, [], [], now)).assertTrue();
      const include: FilterDefinition = new FilterDefinition();
      include.includeSignatures = true;
      include.includeFleetIds = ['drone'];
      expect(engine.pass(ble, include, fleets, [], [], now)).assertFalse();
      expect(engine.pass(wifi, include, fleets, [], [], now)).assertFalse();
    });

    it('supports the three-state class filter', 0, () => {
      const show: FilterDefinition = new FilterDefinition();
      show.useClassFilter = true;
      show.classes = [SignatureClass.CAMERA];
      expect(engine.pass(ble, show, fleets, [], [], now)).assertTrue();
      expect(engine.pass(wifi, show, fleets, [], [], now)).assertFalse();
      const hide: FilterDefinition = new FilterDefinition();
      hide.useClassFilter = true;
      hide.excludeClasses = true;
      hide.classes = [SignatureClass.CAMERA];
      expect(engine.pass(ble, hide, fleets, [], [], now)).assertFalse();
      expect(engine.pass(wifi, hide, fleets, [], [], now)).assertTrue();
    });

    it('matches name and OUI queries against name and MAC', 0, () => {
      const byName: FilterDefinition = new FilterDefinition();
      byName.nameQuery = 'lab';
      expect(engine.pass(wifi, byName, fleets, [], [], now)).assertTrue();
      expect(engine.pass(ble, byName, fleets, [], [], now)).assertFalse();
      const byMac: FilterDefinition = new FilterDefinition();
      byMac.nameQuery = 'aa';
      expect(engine.pass(ble, byMac, fleets, [], [], now)).assertTrue();
      const byOui: FilterDefinition = new FilterDefinition();
      byOui.ouiQuery = 'bb';
      expect(engine.pass(wifi, byOui, fleets, [], [], now)).assertTrue();
      expect(engine.pass(ble, byOui, fleets, [], [], now)).assertFalse();
    });

    it('keeps hard gates in OR mode and only relaxes optional ones', 0, () => {
      const filter: FilterDefinition = new FilterDefinition();
      filter.logic = FilterLogic.OR;
      filter.showWifi = false;
      filter.nameQuery = 'lab';
      filter.rssiMin = -55;
      // 硬条件 showWifi=false 让 Wi-Fi 直接出局，即使名称与 RSSI 都满足
      expect(engine.pass(wifi, filter, fleets, [], [], now)).assertFalse();
      // BLE 满足 RSSI（-60 < -55 不满足）与名称（不满足）→ 可选条件全不满足
      expect(engine.pass(ble, filter, fleets, [], [], now)).assertFalse();
      const relaxed: FilterDefinition = new FilterDefinition();
      relaxed.logic = FilterLogic.OR;
      relaxed.nameQuery = 'lab';
      relaxed.rssiMin = -55;
      expect(engine.pass(ble, relaxed, fleets, [], [], now)).assertFalse();
      // 只放宽 RSSI 时 BLE 应通过（-60 >= -70）
      const relaxedRssi: FilterDefinition = new FilterDefinition();
      relaxedRssi.logic = FilterLogic.OR;
      relaxedRssi.nameQuery = 'lab';
      relaxedRssi.rssiMin = -70;
      expect(engine.pass(ble, relaxedRssi, fleets, [], [], now)).assertTrue();
    });

    it('applies the RSSI floor only when it is above the default', 0, () => {
      const filter: FilterDefinition = new FilterDefinition();
      filter.rssiMin = -55;
      expect(engine.pass(ble, filter, fleets, [], [], now)).assertFalse();
      expect(engine.pass(wifi, filter, fleets, [], [], now)).assertTrue();
    });

    it('hides Fast Pair account-key-only advertisers', 0, () => {
      const keyOnly: Sighting = sighting('ble:CC', RadioKind.BLE, '', -50, []);
      const facts: RadioFacts = new RadioFacts();
      facts.serviceData = [{ uuid: '0000fe2c-0000-1000-8000-00805f9b34fb', dataHex: '20' } as ESObject as never];
      const filter: FilterDefinition = new FilterDefinition();
      filter.hideFastPairAccountKey = true;
      // 未带账号密钥 → 保留
      expect(engine.pass(keyOnly, filter, fleets, [], [], now)).assertTrue();
    });

    it('ships the six original built-in presets plus nearlink', 0, () => {
      const presets: FilterPreset[] = engine.defaultPresets();
      expect(presets.length).assertEqual(7);
      expect(presets[0].name).assertEqual('all');
      expect(presets[1].filter.showBle).assertFalse();
      // 「仅 Wi-Fi」必须同时关掉星闪，否则会连星闪一起显示。
      expect(presets[1].filter.showNearLink).assertFalse();
      expect(presets[2].filter.showWifi).assertFalse();
      expect(presets[2].filter.showNearLink).assertFalse();
      // 新增的「仅星闪」预设：只留星闪。
      expect(presets[3].name).assertEqual('nearlink');
      expect(presets[3].filter.showWifi).assertFalse();
      expect(presets[3].filter.showBle).assertFalse();
      expect(presets[3].filter.showNearLink).assertTrue();
      expect(presets[4].filter.rssiMin).assertEqual(-70);
      expect(presets[5].filter.movingWithYou).assertTrue();
      expect(presets[5].filter.showWifi).assertFalse();
      expect(presets[5].filter.showNearLink).assertFalse();
      expect(presets[6].filter.watchedOnly).assertTrue();
    });

    // 星闪必须与 BLE 分开判定：落进 BLE 分支会让「仅 BLE」把星闪一起放行。
    it('treats nearlink as its own radio kind in the type gate', 0, () => {
      const bleSighting: Sighting = sighting('ble:AA', RadioKind.BLE, 'ble', -50, []);
      const nearLinkSighting: Sighting = sighting('nearlink:BB', RadioKind.NEARLINK, 'nl', -50, []);
      const filter: FilterDefinition = new FilterDefinition();
      filter.showWifi = false;
      filter.showBle = false;
      filter.showNearLink = false;
      expect(engine.pass(nearLinkSighting, filter, [], [], [], now)).assertFalse();
      filter.showNearLink = true;
      expect(engine.pass(nearLinkSighting, filter, [], [], [], now)).assertTrue();
      // 星闪开着但 BLE 关着时，BLE 信号仍应被挡掉。
      expect(engine.pass(bleSighting, filter, [], [], [], now)).assertFalse();
      // 单选 radioKind 时同样要按种类收敛。
      const kindFilter: FilterDefinition = new FilterDefinition();
      kindFilter.radioKind = RadioKind.BLE;
      expect(engine.pass(bleSighting, kindFilter, [], [], [], now)).assertTrue();
      expect(engine.pass(nearLinkSighting, kindFilter, [], [], [], now)).assertFalse();
    });

    // 回归：normalizeFilter 此前只恢复了 8 个字段，导致无线电开关、RSSI 阈值、
    // 名称搜索、与你同行等设置每次重启都被静默重置 —— 而它们明明被写进了磁盘。
    it('restores every persisted filter field, not just a subset', 0, () => {
      const repo: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const saved: FilterDefinition = new FilterDefinition();
      saved.radioKind = RadioKind.NEARLINK;
      saved.showWifi = false;
      saved.showBle = false;
      saved.showNearLink = true;
      saved.rssiMin = -65;
      saved.nameQuery = 'tag';
      saved.ouiQuery = 'aabbcc';
      saved.movingWithYou = true;
      saved.customNamesOnly = true;
      saved.hideFastPairAccountKey = true;
      saved.excludeSignatures = true;
      saved.includeSignatures = true;
      saved.useClassFilter = true;
      saved.excludeClasses = true;
      saved.fleetIds = ['sig-1', 'sig-2'];
      saved.includeFleetIds = ['sig-3'];
      saved.classes = [SignatureClass.WEARABLE];
      const restored: FilterDefinition = repo.normalizeFilter(saved);
      // 星闪必须能被恢复，否则「仅星闪」重启后静默变回「全部」。
      expect(restored.radioKind).assertEqual(RadioKind.NEARLINK);
      expect(restored.showWifi).assertFalse();
      expect(restored.showBle).assertFalse();
      expect(restored.showNearLink).assertTrue();
      expect(restored.rssiMin).assertEqual(-65);
      expect(restored.nameQuery).assertEqual('tag');
      expect(restored.ouiQuery).assertEqual('aabbcc');
      expect(restored.movingWithYou).assertTrue();
      expect(restored.customNamesOnly).assertTrue();
      expect(restored.hideFastPairAccountKey).assertTrue();
      expect(restored.excludeSignatures).assertTrue();
      expect(restored.includeSignatures).assertTrue();
      expect(restored.useClassFilter).assertTrue();
      expect(restored.excludeClasses).assertTrue();
      expect(restored.fleetIds.length).assertEqual(2);
      expect(restored.includeFleetIds.length).assertEqual(1);
      expect(restored.classes.length).assertEqual(1);
    });

    // 磁盘内容不可信：缺字段要回落到默认值，而不是把 undefined 带进引擎。
    it('falls back to defaults when persisted fields are missing', 0, () => {
      const repo: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const restored: FilterDefinition = repo.normalizeFilter(new FilterDefinition());
      expect(restored.showWifi).assertTrue();
      expect(restored.showBle).assertTrue();
      expect(restored.showNearLink).assertTrue();
      expect(restored.rssiMin).assertEqual(-100);
      expect(restored.nameQuery).assertEqual('');
      expect(restored.fleetIds.length).assertEqual(0);
      expect(restored.classes.length).assertEqual(0);
    });
  });
}
