import { describe, it, expect } from '@ohos/hypium';
import { FieldwatchCompareService, FieldwatchFilterEngine, FieldwatchGeoService, FieldwatchPrivacyService, FieldwatchSignatureEngine } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';
import { FieldwatchBleAdvertisementParser, FieldwatchFastPairParser, FieldwatchWifiInformationElementParser } from '../main/ets/fieldwatch/domain/FieldwatchParsers';
import { FieldwatchExportSerializer } from '../main/ets/fieldwatch/domain/FieldwatchExportSerializer';
import { ExplainConfidence, FieldwatchDeviceExplain } from '../main/ets/fieldwatch/domain/FieldwatchDeviceExplain';
import { AppSettings, countSightingsByKind, FilterDefinition, FilterPreset, GpsSample, isRadioPhaseActive, PresenceSpan, WifiScanPhase, RadioFacts, RadioKind, ScanObservation, SignatureClass, Sighting, WatchTarget } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureFleet, SignatureRule, SignatureRuleKind } from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels';
import { effectivePeerWindowSec, needsCluster } from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine';
import { FieldwatchSettingsRepository } from '../main/ets/fieldwatch/data/FieldwatchSettingsRepository';
import { FieldwatchRadarNode, mergeNearbySingles } from '../main/ets/fieldwatch/ui/FieldwatchRadarCluster';
import { FieldwatchLiveMode, FieldwatchRadarPoint, formatClockTime, groupByBrand, planRadarLabels, presenceTrackCommands, RadarLabelPlan, sparkRangeOf, SparkRange, TrendGeometry, trendGeometry, wifiPhaseNeedsAction, remainingAttemptSeconds, sortSightingsForLiveMode, sparklineCommands, visibleSightingsAfterPause, wifiFactValue } from '../main/ets/fieldwatch/ui/FieldwatchUiState';

/** 造一个雷达点，供标签排布用例使用。 */
function radarPoint(key: string, rssi: number, kind: RadioKind): FieldwatchRadarPoint {
  const point: FieldwatchRadarPoint = new FieldwatchRadarPoint(key, 0.5, 0.5, 10, kind, key, rssi);
  point.address = 'AA:BB:CC:DD:EE:FF';
  return point;
}

export default function fieldwatchDomainTest() {
  describe('FieldwatchDomain', () => {
    it('applies watchlist filtering', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Find Hub tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['find'];
      const filter: FilterDefinition = new FilterDefinition();
      filter.minimumRssi = -50;
      filter.signatureId = 'find';
      filter.watchedOnly = true;
      const watched: WatchTarget[] = [new WatchTarget('demo', '', 'demo', true)];
      const signatures: SignatureFleet[] = [new SignatureFleet('find', 'Find Hub', SignatureClass.FINDER, [new SignatureRule(SignatureRuleKind.NAME_CONTAINS, 'find', 0, '', RadioKind.BLE)])];
      expect(new FieldwatchFilterEngine().pass(sighting, filter, signatures, watched, [], Date.now())).assertTrue();
    });

    it('calculates a path', 0, () => {
      const first: GpsSample = new GpsSample(22.3, 114.1, 1);
      const second: GpsSample = new GpsSample(22.31, 114.1, 2);
      expect(new FieldwatchGeoService().pathLengthMeters([first, second]) > 1000).assertTrue();
    });

    it('masks privacy fields', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Demo', -40, 1, new RadioFacts(), new GpsSample(22.3, 114.1, 1));
      const sighting: Sighting = Sighting.fromObservation(observation);
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const text: string = new FieldwatchPrivacyService().describe(sighting, settings);
      expect(text.indexOf('**:**:**') >= 0).assertTrue();
      expect(text.indexOf('22.30') >= 0).assertTrue();
    });

    it('parses valid and truncated radio payloads', 0, () => {
      const advertisement = new FieldwatchBleAdvertisementParser().parse('02010603162CFE');
      expect(advertisement.valid).assertTrue();
      expect(advertisement.fields.get('serviceUuid')).assertEqual('FE2C');
      expect(new FieldwatchBleAdvertisementParser().parse('02010604162C').valid).assertFalse();
      const wifiResult = new FieldwatchWifiInformationElementParser().parse('0102:0A0B');
      expect(wifiResult.valid).assertTrue();
      expect(wifiResult.fields.get('ieCount')).assertEqual('1');
      expect(wifiResult.fields.get('ie.0.id')).assertEqual('1');
      expect(new FieldwatchWifiInformationElementParser().parse('0103:0A0B').valid).assertFalse();
      expect(new FieldwatchFastPairParser().parse('03162CFE').valid).assertTrue();
    });

    it('serializes observations with privacy masking', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const observation: ScanObservation = new ScanObservation('wifi:test', RadioKind.WIFI, 'AA:BB:CC:DD:EE:FF', 'AP', -40, 1, new RadioFacts('AP', '', 2412));
      const sighting: Sighting = Sighting.fromObservation(observation);
      const csv: string = new FieldwatchExportSerializer().serializeCsv([sighting], settings);
      expect(csv.indexOf('**:**:**') >= 0).assertTrue();
      expect(csv.indexOf('2412') >= 0).assertTrue();
    });

    it('tracks RSSI samples and trend', 0, () => {
      const engine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
      const sighting: Sighting = Sighting.fromObservation(new ScanObservation('ble:rssi', RadioKind.BLE, 'AA', 'Target', -80, 1));
      sighting.ingest(new ScanObservation('ble:rssi', RadioKind.BLE, 'AA', 'Target', -60, 2));
      sighting.ingest(new ScanObservation('ble:rssi', RadioKind.BLE, 'AA', 'Target', -50, 3));
      expect(engine.rssiAverage(sighting)).assertEqual(-63.333333333333336);
      expect(engine.rssiTrend(sighting)).assertEqual(30);
    });

    it('orders live list modes by their visual contract', 0, () => {
      const weak: Sighting = Sighting.fromObservation(new ScanObservation('weak', RadioKind.BLE, 'AA', 'Weak', -85, 10));
      const strong: Sighting = Sighting.fromObservation(new ScanObservation('strong', RadioKind.WIFI, 'BB', 'Strong', -35, 5));
      const strength: Array<Sighting> = sortSightingsForLiveMode([weak, strong], FieldwatchLiveMode.STRENGTH);
      expect(strength[0].key).assertEqual('strong');
      const timeline: Array<Sighting> = sortSightingsForLiveMode([weak, strong], FieldwatchLiveMode.TIMELINE);
      expect(timeline[0].key).assertEqual('weak');
    });

    it('binds detail fields with localized placeholders', 0, () => {
      const privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();
      const named: Sighting = Sighting.fromObservation(new ScanObservation('ble:named', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1));
      expect(privacy.displayName(named, false)).assertEqual('Tag');
      const ssidOnly: Sighting = Sighting.fromObservation(new ScanObservation('wifi:ap', RadioKind.WIFI, '11:22:33:44:55:66', '', -40, 1, new RadioFacts('Lab-AP')));
      expect(privacy.displayName(ssidOnly, false)).assertEqual('Lab-AP');
      const anonymous: Sighting = Sighting.fromObservation(new ScanObservation('ble:anon', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -40, 1));
      expect(privacy.deviceName(named)).assertEqual('Tag');
      expect(privacy.deviceName(anonymous)).assertEqual('');
      expect(privacy.displayName(anonymous, false)).assertEqual('AA:BB:CC:DD:EE:FF');
      expect(privacy.displayName(anonymous, true)).assertEqual('AA:BB:CC:**:**:**');
      expect(privacy.maskLocation(undefined, false)).assertEqual('');
      expect(privacy.maskLocation(new GpsSample(22.3, 114.1, 1), true)).assertEqual('22.30, 114.10');
      const settings: AppSettings = new AppSettings();
      expect(privacy.describe(anonymous, settings)).assertEqual('AA:BB:CC:DD:EE:FF');
    });

    it('formats live timeline clock and wifi-only facts', 0, () => {
      expect(formatClockTime(0)).assertEqual('');
      const sample: number = new Date(2026, 9, 6, 14, 5, 9).getTime();
      expect(formatClockTime(sample)).assertEqual('14:05:09');
      expect(wifiFactValue(RadioKind.WIFI, 2412, ' MHz', 'N/A')).assertEqual('2412 MHz');
      expect(wifiFactValue(RadioKind.WIFI, 0, '', 'N/A')).assertEqual('0');
      expect(wifiFactValue(RadioKind.BLE, 0, ' MHz', 'N/A')).assertEqual('N/A');
    });

    it('compares named sit device sets', 0, () => {
      const result = new FieldwatchCompareService().compare(['a', 'b'], ['b', 'c']);
      expect(result.sharedKeys.length).assertEqual(1);
      expect(result.sharedKeys[0]).assertEqual('b');
      expect(result.addedKeys[0]).assertEqual('c');
      expect(result.removedKeys[0]).assertEqual('a');
    });

    it('calculates retry countdown with an expired boundary', 0, () => {
      expect(remainingAttemptSeconds(11000, 10000)).assertEqual(1);
      expect(remainingAttemptSeconds(10999, 10000)).assertEqual(1);
      expect(remainingAttemptSeconds(10000, 10000)).assertEqual(0);
      expect(remainingAttemptSeconds(9000, 10000)).assertEqual(0);
    });

    it('freezes the visible snapshot without stopping observation', 0, () => {
      const current: Array<Sighting> = [Sighting.fromObservation(new ScanObservation('current', RadioKind.BLE, 'A', 'Current', -50, 1))];
      const latest: Array<Sighting> = [Sighting.fromObservation(new ScanObservation('latest', RadioKind.BLE, 'B', 'Latest', -40, 2))];
      expect(visibleSightingsAfterPause(true, current, latest)[0].key).assertEqual('current');
      expect(visibleSightingsAfterPause(false, current, latest)[0].key).assertEqual('latest');
    });

    it('filters by folded signature class', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.WIFI, 'AA:BB:CC:DD:EE:FF', 'Lab', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['legacy-router'];
      const filter: FilterDefinition = new FilterDefinition();
      filter.signatureClass = SignatureClass.ISP;
      const signatures: SignatureFleet[] = [new SignatureFleet('legacy-router', 'Legacy router', SignatureClass.ROUTER, [])];
      expect(new FieldwatchFilterEngine().pass(sighting, filter, signatures, [], [], Date.now())).assertTrue();
      filter.signatureClass = SignatureClass.CAMERA;
      expect(new FieldwatchFilterEngine().pass(sighting, filter, signatures, [], [], Date.now())).assertFalse();
    });

    it('exports versioned settings backup content', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.scanIntensity = 'saver';
      settings.watchNotifications = true;
      settings.backgroundScanning = true;
      const backup: string = new FieldwatchSettingsRepository().exportBackup(settings);
      expect(backup.indexOf('fieldwatch_settings_v1') === 0).assertTrue();
      expect(backup.indexOf('scanIntensity=saver') >= 0).assertTrue();
      expect(backup.indexOf('watchNotifications=true') >= 0).assertTrue();
      expect(backup.indexOf('backgroundScanning=true') >= 0).assertTrue();
    });

    it('round trips named filter presets and watchlist settings', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      repository.listFilterPresets().forEach((item: FilterPreset): void => { repository.deleteFilterPreset(item.name); });
      const filter: FilterDefinition = new FilterDefinition();
      filter.radioKind = RadioKind.WIFI;
      filter.minimumRssi = -65;
      filter.cachedOnly = true;
      // 类别扩到 20 类后必须能完整往返，不能只认 4 类。
      filter.signatureClass = SignatureClass.CAMERA;
      filter.namedOnly = true;
      expect(repository.saveFilterPreset('现场 A', filter)).assertTrue();
      const second: FilterDefinition = new FilterDefinition();
      second.namedOnly = true;
      expect(repository.saveFilterPreset('现场 B', second)).assertTrue();
      expect(repository.listFilterPresets().length).assertEqual(2);
      const restored: FilterDefinition | undefined = repository.loadFilterPreset('现场 A');
      expect(restored !== undefined).assertTrue();
      if (restored !== undefined) {
        expect(restored.radioKind).assertEqual(RadioKind.WIFI);
        expect(restored.minimumRssi).assertEqual(-65);
        expect(restored.cachedOnly).assertTrue();
        expect(restored.signatureClass).assertEqual(SignatureClass.CAMERA);
        expect(restored.namedOnly).assertTrue();
      }
      expect(repository.loadFilterPreset('不存在')).assertUndefined();
      repository.deleteFilterPreset('现场 B');
      expect(repository.listFilterPresets().length).assertEqual(1);
      repository.deleteFilterPreset('现场 A');
      expect(repository.listFilterPresets().length).assertEqual(0);
      const watchlist: Array<WatchTarget> = [new WatchTarget('device-1', '', 'Target', true)];
      repository.saveWatchlist(watchlist);
      const restoredWatchlist: Array<WatchTarget> = repository.loadWatchlist();
      expect(restoredWatchlist.length).assertEqual(1);
      expect(restoredWatchlist[0].deviceKey).assertEqual('device-1');
    });

    // ── 实时页头部：工作模式与分无线电计数 ──
    // 这两段逻辑原先内联在页面结构体里，单测够不着；抽成模块级纯函数后才锁得住。

    it('按无线电种类计数时星闪不能被算成 Wi-Fi（回归）', 0, () => {
      // 原实现是 `if (BLE) ble++; else wifi++;` —— 二分法只有两支，
      // 星闪落进 else，于是头部显示的 Wi-Fi 数量实际是「Wi-Fi + 星闪」，星闪自己一个数都没有。
      const items: Sighting[] = [
        Sighting.fromObservation(new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', 'x', -40, 1)),
        Sighting.fromObservation(new ScanObservation('b', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', 'x', -40, 1)),
        Sighting.fromObservation(new ScanObservation('c', RadioKind.WIFI, 'AA:BB:CC:DD:EE:03', 'y', -40, 1)),
        Sighting.fromObservation(new ScanObservation('d', RadioKind.NEARLINK, 'AA:BB:CC:DD:EE:04', 'z', -40, 1)),
        Sighting.fromObservation(new ScanObservation('e', RadioKind.NEARLINK, 'AA:BB:CC:DD:EE:05', 'z', -40, 1)),
        Sighting.fromObservation(new ScanObservation('f', RadioKind.NEARLINK, 'AA:BB:CC:DD:EE:06', 'z', -40, 1)),
      ];
      const counts: number[] = countSightingsByKind(items);
      expect(counts[0]).assertEqual(2);   // BLE
      expect(counts[1]).assertEqual(1);   // Wi-Fi（不能是 4）
      expect(counts[2]).assertEqual(3);   // 星闪
      expect(counts[0] + counts[1] + counts[2]).assertEqual(items.length);
    });

    it('空列表时三类计数都是 0', 0, () => {
      const counts: number[] = countSightingsByKind([]);
      expect(counts[0]).assertEqual(0);
      expect(counts[1]).assertEqual(0);
      expect(counts[2]).assertEqual(0);
    });

    it('工作模式判定：不可用的相位不算在工作', 0, () => {
      // idle 与四类「不可用」都不算
      expect(isRadioPhaseActive('idle')).assertFalse();
      expect(isRadioPhaseActive('unsupported')).assertFalse();
      expect(isRadioPhaseActive('permission_denied')).assertFalse();
      expect(isRadioPhaseActive('wifi_disabled')).assertFalse();
      expect(isRadioPhaseActive('location_disabled')).assertFalse();
      // 扫描器活着的各种相位都算 —— Wi-Fi 会在这些之间循环，
      // 只认 scanning 的话「Wi-Fi+蓝牙+星闪模式」会一闪一闪地跳。
      expect(isRadioPhaseActive('scanning')).assertTrue();
      expect(isRadioPhaseActive('ready')).assertTrue();
      expect(isRadioPhaseActive('waiting_for_retry')).assertTrue();
      expect(isRadioPhaseActive('stale')).assertTrue();
      expect(isRadioPhaseActive('precheck')).assertTrue();
      expect(isRadioPhaseActive('paused')).assertTrue();
    });

    // ── 信号轨迹视图的 sparkline ──
    // commands 串拼错时 Path 会静默什么都不画，界面上只看到空白，所以必须锁住格式。

    it('sparkline：样本不足 2 个时返回空串（不画假直线）', 0, () => {
      expect(sparklineCommands([], 100, 40)).assertEqual('');
      expect(sparklineCommands([-50], 100, 40)).assertEqual('');
    });

    it('sparkline：首尾横坐标落在画框两端，首段用 M 其余用 L', 0, () => {
      const commands: string = sparklineCommands([-100, -50, -35], 100, 40);
      // 第一段必须是 M（否则 Path 画不出来），其余是 L
      expect(commands.startsWith('M')).assertTrue();
      expect(commands.indexOf('M', 1)).assertEqual(-1);
      expect((commands.match(/L/g) || []).length).assertEqual(2);
      // 三个样本：x = 0 / 50 / 100
      expect(commands.indexOf('M0.0 ')).assertEqual(0);
      // indexOf 返回的是数字，assertTrue 只接受布尔，必须显式比较
      expect(commands.indexOf('L50.0 ') > -1).assertTrue();
      expect(commands.indexOf('L100.0 ') > -1).assertTrue();
    });

    it('sparkline：纵轴口径与 RSSI 条一致（-100 底、-35 顶）', 0, () => {
      // -100 -> ratio 0 -> y = height（底部）
      const low: string = sparklineCommands([-100, -100], 100, 40);
      expect(low.indexOf('M0.0 40.0')).assertEqual(0);
      // -35 -> ratio 1 -> y = 0（顶部）
      const high: string = sparklineCommands([-35, -35], 100, 40);
      expect(high.indexOf('M0.0 0.0')).assertEqual(0);
    });

    it('sparkline：超出 -100..-35 的样本被夹紧而不是画出框外', 0, () => {
      const commands: string = sparklineCommands([-200, 0], 100, 40);
      // -200 夹到 0 -> y=40；0 夹到 1 -> y=0
      expect(commands.indexOf('M0.0 40.0')).assertEqual(0);
      expect(commands.indexOf('L100.0 0.0') > -1).assertTrue();
      // 不能出现负数或超出高度
      expect(commands.indexOf('-')).assertEqual(-1);
    });

    // ── 设备解释层（原版 DeviceExplain 的移植）──
    // 它决定详情页最上面那句「很可能是 iPhone、iPad 或 Mac」以及依据，
    // 是加权提示系统而非规则优先级，所以边界必须锁住。

    it('解释层：没有任何线索时退化为「只认得无线电类别」', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 1));
      const guess = explain.guess(item, []);
      expect(guess.generic).assertTrue();
      expect(guess.confidence).assertEqual(ExplainConfidence.LOW);
    });

    it('解释层：签名命中给出高置信度，且措辞是「很可能是」', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 1));
      const guess = explain.guess(item, ['AirTag']);
      expect(guess.generic).assertFalse();
      expect(guess.confidence).assertEqual(ExplainConfidence.HIGH);
      expect(guess.headline.indexOf('很可能是')).assertEqual(0);
      expect(guess.label).assertEqual('AirTag');
    });

    it('解释层：通用兜底签名不算产品类别线索', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 1));
      const guess = explain.guess(item, ['Unknown Signature']);
      expect(guess.generic).assertTrue();
    });

    it('解释层：RSSI 分档与原版阈值一致', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      expect(explain.rssiBand(-40)).assertEqual('很强');
      expect(explain.rssiBand(-45)).assertEqual('很强');
      expect(explain.rssiBand(-46)).assertEqual('强');
      expect(explain.rssiBand(-60)).assertEqual('强');
      expect(explain.rssiBand(-75)).assertEqual('中等');
      expect(explain.rssiBand(-88)).assertEqual('弱');
      expect(explain.rssiBand(-89)).assertEqual('很弱');
      expect(explain.rssiBand(0)).assertEqual('不可用');
    });

    it('解释层：Flags 的 0x04 未置位要说「可能也支持经典蓝牙」', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      // 0x04 = 仅 BLE；未置位反而说明可能支持经典蓝牙 —— 这一位最容易读反
      const bleOnly: string = explain.flagsExplain(0x06);
      expect(bleOnly.indexOf('仅 BLE') >= 0).assertTrue();
      const dual: string = explain.flagsExplain(0x02);
      expect(dual.indexOf('可能也支持经典蓝牙') >= 0).assertTrue();
      expect(dual.indexOf('仅 BLE') >= 0).assertFalse();
    });

    it('解释层：随机地址的说明要点出「不是持久身份」', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 1));
      // 0xAA 的本地管理位已置 -> 随机地址
      const text: string = explain.addressExplain(item);
      expect(text.indexOf('随机') >= 0).assertTrue();
      expect(text.indexOf('不是持久的身份标识') >= 0).assertTrue();
    });

    it('解释层：会话强度范围在单样本时只显示一个值', 0, () => {
      const explain: FieldwatchDeviceExplain = new FieldwatchDeviceExplain();
      expect(explain.sessionRange(-83, -83)).assertEqual('-83 dBm');
      expect(explain.sessionRange(-83, -82)).assertEqual('-83 ~ -82 dBm');
    });

    // ── 在场时间轴（原版 PresenceTrack 的等价物）──
    // 时间段映射错位时图上只是「条画歪了」，肉眼很难判断是数据问题还是映射问题。

    // ── 扫描异常横幅的触发条件 ──
    // 判断写错时界面上只是多一条或漏一条横幅，肉眼很难发现。

    it('扫描异常横幅：系统限频与退避重试不算异常', 0, () => {
      // 这两个是扫描的**正常节律**，应用会自己重试成功。
      // 报成「异常」会让用户以为程序坏了（实测就是这个反馈）。
      expect(wifiPhaseNeedsAction(WifiScanPhase.SYSTEM_REJECTED)).assertFalse();
      expect(wifiPhaseNeedsAction(WifiScanPhase.WAITING_FOR_RETRY)).assertFalse();
    });

    it('扫描异常横幅：正常工作相位不算异常', 0, () => {
      expect(wifiPhaseNeedsAction(WifiScanPhase.IDLE)).assertFalse();
      expect(wifiPhaseNeedsAction(WifiScanPhase.PRECHECK)).assertFalse();
      expect(wifiPhaseNeedsAction(WifiScanPhase.SCANNING)).assertFalse();
      expect(wifiPhaseNeedsAction(WifiScanPhase.READY)).assertFalse();
      expect(wifiPhaseNeedsAction(WifiScanPhase.STALE)).assertFalse();
    });

    it('扫描异常横幅：需要用户处理的才算异常', 0, () => {
      expect(wifiPhaseNeedsAction(WifiScanPhase.WIFI_DISABLED)).assertTrue();
      expect(wifiPhaseNeedsAction(WifiScanPhase.LOCATION_DISABLED)).assertTrue();
      expect(wifiPhaseNeedsAction(WifiScanPhase.PERMISSION_DENIED)).assertTrue();
      expect(wifiPhaseNeedsAction(WifiScanPhase.UNSUPPORTED)).assertTrue();
      expect(wifiPhaseNeedsAction(WifiScanPhase.ERROR)).assertTrue();
    });

    // ── 信号趋势图的坐标映射（对齐原版 Sparkline）──
    // 映射错位时图上只是「线画歪了」，肉眼很难判断是数据问题还是映射问题。

    // ── 雷达标签排布与「降级为小圆点」──
    // 判断写错时界面上只是多几个或少几个点，肉眼很难发现。

    // ── 特征匹配的四个开关必须真的参与判定（不能是占位 UI）──

    it('特征：minPeers/clusterByOui/sequentialMac 会改变判定路径', 0, () => {
      // 这三项若被引擎忽略，界面上的开关就是摆设 ——
      // 用 `fleetUsesPeerMatching` 这个谓词把契约锁住。
      const plain: SignatureFleet = new SignatureFleet('t-plain', 'plain', SignatureClass.OTHER, [], false);
      expect(needsCluster(plain)).assertFalse();
      const peers: SignatureFleet = new SignatureFleet('t-peers', 'peers', SignatureClass.OTHER, [], false);
      peers.minPeers = 3;
      expect(needsCluster(peers)).assertTrue();
      const oui: SignatureFleet = new SignatureFleet('t-oui', 'oui', SignatureClass.OTHER, [], false);
      oui.clusterByOui = true;
      expect(needsCluster(oui)).assertTrue();
      const seq: SignatureFleet = new SignatureFleet('t-seq', 'seq', SignatureClass.OTHER, [], false);
      seq.sequentialMac = true;
      expect(needsCluster(seq)).assertTrue();
    });

    it('特征：peerWindowSec 为 0 或负数时退回 60 秒', 0, () => {
      // 引擎里是 `fleet.peerWindowSec <= 0 ? 60 : fleet.peerWindowSec`，
      // 界面允许填 0，此时必须与目录里的默认口径一致。
      const fleet: SignatureFleet = new SignatureFleet('t-win', 'win', SignatureClass.OTHER, [], false);
      fleet.peerWindowSec = 0;
      expect(effectivePeerWindowSec(fleet)).assertEqual(60);
      fleet.peerWindowSec = 45;
      expect(effectivePeerWindowSec(fleet)).assertEqual(45);
    });

    // ── 折线图纵轴范围（图表与图例必须同源）──

    it('折线范围：覆盖样本极值，两端留余量', 0, () => {
      const range: SparkRange = sparkRangeOf([-40, -60, -50]);
      // 最低 -60、最高 -40，两端各留 3 dB
      expect(range.minDb <= -63).assertTrue();
      expect(range.maxDb >= -37).assertTrue();
    });

    it('折线范围：近距离高强度读数不再被截断', 0, () => {
      // 固定范围 -100~-35 时，-25 会被 clamp 到顶部，折线贴顶成直线，
      // 而旁边写着 -25 dBm —— 这就是「图表和图例对不上」。
      const range: SparkRange = sparkRangeOf([-25, -28, -26]);
      expect(range.maxDb >= -25).assertTrue();
      const commands: string = sparklineCommands([-25, -28, -26], 100, 20, range);
      // 最高的那个点应当落在框内（y > 0），而不是贴顶
      const firstY: number = parseFloat(commands.split(' ')[1]);
      expect(firstY > 0).assertTrue();
    });

    it('折线范围：稳定信号不会被放大成剧烈起伏', 0, () => {
      // ±1 dB 的抖动若按实际极值铺满整框，看起来像剧烈波动，同样是误导。
      const range: SparkRange = sparkRangeOf([-60, -61, -60]);
      expect(range.maxDb - range.minDb >= 10).assertTrue();
    });

    it('折线范围：全为无效样本时退回默认范围', 0, () => {
      const range: SparkRange = sparkRangeOf([0, 0]);
      expect(range.minDb).assertEqual(-100);
      expect(range.maxDb).assertEqual(-35);
    });

    // ── 邻近合并（补分箱的边界情形）──

    it('邻近合并：贴在一起的两个单点并成气泡', 0, () => {
      // 分箱按 12 个扇区（每个 30°）切，跨在边界两侧的两台设备永远分不到同一箱。
      // memberKeys 在真实流程里由 `buildRadarNodes` 填充，手工构造要自己补，
      // 否则合并出来的气泡成员数是 0。
      const a: FieldwatchRadarNode = new FieldwatchRadarNode('a', 0.500, 0.500, 1, radarPoint('a', -60, RadioKind.BLE));
      a.memberKeys.push('a');
      const b: FieldwatchRadarNode = new FieldwatchRadarNode('b', 0.505, 0.500, 1, radarPoint('b', -60, RadioKind.BLE));
      b.memberKeys.push('b');
      const nodes: FieldwatchRadarNode[] = [a, b];
      const out: FieldwatchRadarNode[] = mergeNearbySingles(nodes);
      expect(out.length).assertEqual(1);
      expect(out[0].count).assertEqual(2);
      expect(out[0].memberKeys.length).assertEqual(2);
    });

    it('邻近合并：分得开的点不合并', 0, () => {
      const a: FieldwatchRadarNode = new FieldwatchRadarNode('a', 0.2, 0.2, 1, radarPoint('a', -60, RadioKind.BLE));
      const b: FieldwatchRadarNode = new FieldwatchRadarNode('b', 0.8, 0.8, 1, radarPoint('b', -60, RadioKind.BLE));
      const out: FieldwatchRadarNode[] = mergeNearbySingles([a, b]);
      expect(out.length).assertEqual(2);
    });

    it('邻近合并：已有气泡不再吸收别人', 0, () => {
      // 否则一次刷新里会滚雪球，把半个屏幕并成一个球。
      const cluster: FieldwatchRadarNode = new FieldwatchRadarNode('c', 0.5, 0.5, 3, radarPoint('c', -60, RadioKind.BLE));
      const single: FieldwatchRadarNode = new FieldwatchRadarNode('s', 0.502, 0.5, 1, radarPoint('s', -60, RadioKind.BLE));
      const out: FieldwatchRadarNode[] = mergeNearbySingles([cluster, single]);
      expect(out.length).assertEqual(2);
      expect(out[0].count).assertEqual(3);
    });

    // ── 显示用强度的平滑（EWMA）──
    // 雷达的位置、半径、分圈、显现排名、聚合成箱全部由它派生，
    // 平滑失效时表现为节点跳变/闪烁，很难从画面上反推原因。

    it('强度平滑：首个样本直接落位，不从 0 爬升', 0, () => {
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:01', '', -70, 1000));
      // 不落位的话，新设备会从圆心「飞」到真实位置。
      expect(item.rssiDisplay).assertEqual(-70);
    });

    it('强度平滑：单次大幅波动被显著削弱', 0, () => {
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', '', -60, 1000));
      // 一次 -60 -> -90 的跳变（30 dBm）
      item.ingest(new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:02', '', -90, 2000));
      // 平滑后只走了四分之一：-67.5，而不是直接跳到 -90
      expect(item.rssiDisplay > -69 && item.rssiDisplay < -66).assertTrue();
      // 原始读数仍然是真实的，详情页要显示它
      expect(item.rssi).assertEqual(-90);
    });

    it('强度平滑：持续同向最终会收敛到真实值', 0, () => {
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:03', '', -60, 1000));
      for (let i: number = 0; i < 40; i += 1) {
        item.ingest(new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:03', '', -90, 2000 + i));
      }
      // 平滑不是「压住一切」：真实信号持续变化时必须跟得上，否则用户觉得迟钝。
      expect(Math.abs(item.rssiDisplay - (-90)) < 0.5).assertTrue();
    });

    it('强度平滑：抖动被压到远小于原始波动', 0, () => {
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:04', '', -70, 1000));
      let maxJump: number = 0;
      let prev: number = item.rssiDisplay;
      for (let i: number = 0; i < 20; i += 1) {
        // 原始值在 -70 / -80 之间来回抖
        const raw: number = i % 2 === 0 ? -80 : -70;
        item.ingest(new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:04', '', raw, 2000 + i));
        const jump: number = Math.abs(item.rssiDisplay - prev);
        if (jump > maxJump) maxJump = jump;
        prev = item.rssiDisplay;
      }
      // 原始每次抖 10 dBm；平滑后单步位移必须远小于它，否则雷达仍会跳。
      expect(maxJump < 3).assertTrue();
    });

    // ── 分类页的品牌分组 ──

    it('品牌分组：按数量降序', 0, () => {
      const names: string[] = ['Apple', 'Apple', 'Samsung', 'Huawei', 'Huawei', 'Huawei'];
      const brands: string[] = groupByBrand(names, (n: string): string => n);
      expect(brands[0]).assertEqual('Huawei');
      expect(brands[1]).assertEqual('Apple');
      expect(brands[2]).assertEqual('Samsung');
    });

    it('品牌分组：数量相同时按名称排，顺序稳定', 0, () => {
      // 顺序不稳定的话，分组标题会每次刷新都换位置 —— 会被误读成「界面在抖」。
      const a: string[] = ['B', 'A', 'C'];
      const b: string[] = ['C', 'B', 'A'];
      expect(groupByBrand(a, (n: string): string => n).join(',')).assertEqual('A,B,C');
      expect(groupByBrand(b, (n: string): string => n).join(',')).assertEqual('A,B,C');
    });

    it('品牌分组：空输入返回空', 0, () => {
      expect(groupByBrand([], (n: string): string => n).length).assertEqual(0);
    });

    it('雷达标签：关掉全部字段时不算放不下', 0, () => {
      // 用户主动关掉所有标签字段 —— 图标仍应完整显示，不能降级成圆点。
      const pts: FieldwatchRadarPoint[] = [radarPoint('a', -60, RadioKind.BLE)];
      const plan: RadarLabelPlan = planRadarLabels(pts, 400, 400,
        (nx: number): number => nx * 400, (ny: number): number => ny * 400,
        (p: FieldwatchRadarPoint): number => 10,
        (p: FieldwatchRadarPoint): string => '',
        (p: FieldwatchRadarPoint): string => '', 12, 0, 0);
      expect(plan.labeledKeys.indexOf('|a|') >= 0).assertTrue();
      expect(plan.dotKeys).assertEqual('|');
    });

    it('雷达标签：空间足够时不降级', 0, () => {
      const pts: FieldwatchRadarPoint[] = [radarPoint('a', -60, RadioKind.BLE), radarPoint('b', -80, RadioKind.WIFI)];
      const plan: RadarLabelPlan = planRadarLabels(pts, 1200, 1200,
        (nx: number): number => nx * 1200, (ny: number): number => ny * 1200,
        (p: FieldwatchRadarPoint): number => 10,
        (p: FieldwatchRadarPoint): string => 'dev',
        (p: FieldwatchRadarPoint): string => '', 12, 0, 0);
      expect(plan.labeledKeys.indexOf('|a|') >= 0).assertTrue();
      expect(plan.labeledKeys.indexOf('|b|') >= 0).assertTrue();
      expect(plan.dotKeys).assertEqual('|');
    });

    it('雷达标签：完全重叠时至少有一个降级为圆点', 0, () => {
      // 两个点在同一位置、标签都放不下彼此不重叠的位置 -> 必有一个降级
      const a: FieldwatchRadarPoint = radarPoint('a', -60, RadioKind.BLE);
      const b: FieldwatchRadarPoint = radarPoint('b', -60, RadioKind.BLE);
      b.x = a.x; b.y = a.y;
      const pts: FieldwatchRadarPoint[] = [a, b];
      const plan: RadarLabelPlan = planRadarLabels(pts, 40, 40,
        (nx: number): number => nx * 40, (ny: number): number => ny * 40,
        (p: FieldwatchRadarPoint): number => 10,
        (p: FieldwatchRadarPoint): string => 'verylongdevicename',
        (p: FieldwatchRadarPoint): string => '', 12, 0, 0);
      // 画框只有 40x40，标签宽 100+，两个都放不下
      expect(plan.dotKeys.indexOf('|a|') >= 0).assertTrue();
      expect(plan.dotKeys.indexOf('|b|') >= 0).assertTrue();
    });

    it('趋势图：几何必须铺满传入的宽度（不能只画左侧一小条）', 0, () => {
      // 详情页曾把几何按固定 300 宽算、容器却是全宽（约 1440），
      // 结果网格只占左侧 1/5、末点圆点孤零零飘在右边。
      const wide: TrendGeometry = trendGeometry([-40, -60, -50], 1440, 64);
      expect(wide.dotX).assertEqual(1440);
      // 折线末点的横坐标也要落在右边缘
      const parts: string[] = wide.series.trim().split(' ');
      const lastPair: string = parts[parts.length - 1];
      const lastX: number = parseFloat(parts[parts.length - 2].replace('L', ''));
      expect(lastX > 1430).assertTrue();
      // 刻度线右端同样铺满
      expect(wide.horizontalSolid.indexOf('H1440.0') > -1).assertTrue();
    });

    it('趋势图：无有效样本时不画线也不画点', 0, () => {
      const geo: TrendGeometry = trendGeometry([], 300, 64);
      expect(geo.series).assertEqual('');
      expect(geo.hasDot).assertFalse();
    });

    it('趋势图：刻度网格与标签按原版生成', 0, () => {
      const geo: TrendGeometry = trendGeometry([-60, -70], 300, 64);
      // 8 条水平刻度线，标注的 4 条走实线、其余走虚线
      expect((geo.horizontalSolid.match(/M/g) || []).length).assertEqual(4);
      expect((geo.horizontalDashed.match(/M/g) || []).length).assertEqual(4);
      // 纵轴 + 3 列纵向虚线 = 4 条
      expect((geo.vertical.match(/M/g) || []).length).assertEqual(4);
      // 标签就是标注的那 4 个刻度
      expect(geo.labels.length).assertEqual(4);
      expect(geo.labels[0].text).assertEqual('-30');
      expect(geo.labels[3].text).assertEqual('-100');
    });

    it('趋势图：只有一个样本时只画圆点', 0, () => {
      const geo: TrendGeometry = trendGeometry([-55], 300, 64);
      expect(geo.series).assertEqual('');
      expect(geo.hasDot).assertTrue();
      expect(geo.dotRadius).assertEqual(5);
      // 圆点画在右端，纵向按 -55 映射
      expect(geo.dotX).assertEqual(300);
    });

    it('趋势图：多个样本画折线并在末点加圆点', 0, () => {
      const geo: TrendGeometry = trendGeometry([-40, -60, -50], 300, 64);
      expect((geo.series.match(/M/g) || []).length).assertEqual(1);
      expect((geo.series.match(/L/g) || []).length).assertEqual(2);
      expect(geo.hasDot).assertTrue();
      expect(geo.dotRadius).assertEqual(4.6);
      expect(geo.dotX).assertEqual(300);
    });

    it('趋势图：纵向映射被夹在 [-100,-30] 之内', 0, () => {
      // 原版把 rssi+100 夹到 [0,70]，所以 -30 是顶、-100 是底。
      const top: TrendGeometry = trendGeometry([-30], 300, 64);
      const bottom: TrendGeometry = trendGeometry([-100], 300, 64);
      expect(top.dotY < 0.001).assertTrue();
      expect(Math.abs(bottom.dotY - 64) < 0.001).assertTrue();
      // 超出范围的值被夹住，不会画出画框
      const over: TrendGeometry = trendGeometry([-10], 300, 64);
      expect(over.dotY < 0.001).assertTrue();
      const under: TrendGeometry = trendGeometry([-120], 300, 64);
      expect(Math.abs(under.dotY - 64) < 0.001).assertTrue();
    });

    it('趋势图：无效样本（>=0）被过滤掉', 0, () => {
      // 未测到 RSSI 时原版填 0；0 不是有效测量值，不能参与折线
      const geo: TrendGeometry = trendGeometry([0, 0, -60], 300, 64);
      expect(geo.series).assertEqual('');
      expect(geo.hasDot).assertTrue();
      expect(geo.dotRadius).assertEqual(5);
    });

    it('在场时间轴：空时段不画任何东西', 0, () => {
      expect(presenceTrackCommands([], 1000000, 900000, 300, 18)).assertEqual('');
    });

    it('在场时间轴：窗口外的旧时段被裁掉（设备已走开）', 0, () => {
      // 窗口是 now-900000 到 now；这段完全在窗口之前。
      // **必须传 gone=true** —— 否则末段会被当成「仍在场」而画满整条，
      // 这正是原版 `open = end==null || (!gone && i==last)` 里 gone 的作用。
      const old: PresenceSpan[] = [new PresenceSpan(1000, 2000)];
      expect(presenceTrackCommands(old, 1000000, 900000, 300, 18, true)).assertEqual('');
      // 未走开时同一条数据会被视为仍在场（与原版一致）
      expect(presenceTrackCommands(old, 1000000, 900000, 300, 18, false).length > 0).assertTrue();
    });

    it('走开扫描：超过容忍窗口才关闭时段，且 end 取 lastSeen', 0, () => {
      const item: Sighting = Sighting.fromObservation(
        new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 1000));
      expect(item.gone).assertFalse();
      expect(item.presence.length).assertEqual(1);
      expect(item.presence[0].end === undefined).assertTrue();
      // 窗口内：仍在场，时段保持开放
      item.refreshPresence(40000, 45000);
      expect(item.gone).assertFalse();
      expect(item.presence[0].end === undefined).assertTrue();
      // 超出窗口：走开，时段关闭且 end = lastSeen（不是 now）
      item.refreshPresence(100000, 45000);
      expect(item.gone).assertTrue();
      expect(item.presence[0].end).assertEqual(1000);
      // 再次听到：重开
      item.ingest(new ScanObservation('a', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', '', -60, 200000));
      item.refreshPresence(210000, 45000);
      expect(item.gone).assertFalse();
      expect(item.presence.length).assertEqual(2);
      expect(item.presence[1].end === undefined).assertTrue();
    });

    it('在场时间轴：仍在场的段画到窗口右端', 0, () => {
      const now: number = 1000000;
      // 从窗口起点开始、end 为空 -> 画满整条
      const spans: PresenceSpan[] = [new PresenceSpan(now - 900000, undefined)];
      const commands: string = presenceTrackCommands(spans, now, 900000, 300, 18);
      expect(commands.indexOf('M0.0 ') === 0).assertTrue();
      expect(commands.indexOf('H300.0') > -1).assertTrue();
      // 纵向居中窄条：top = 18*0.25 = 4.5，底 = 18*0.75 = 13.5
      expect(commands.indexOf('V13.5') > -1).assertTrue();
    });

    it('在场时间轴：极短的一段仍有 2px 最小宽度', 0, () => {
      const now: number = 1000000;
      // 只持续 1ms，映射后宽度远小于 1px
      const spans: PresenceSpan[] = [new PresenceSpan(now - 500000, now - 500000 + 1)];
      const commands: string = presenceTrackCommands(spans, now, 900000, 300, 18);
      expect(commands.length > 0).assertTrue();
      // 起止横坐标差必须 >= 2（否则用户以为没记录）
      const m: RegExpMatchArray | null = commands.match(/M([0-9.]+) [0-9.]+ H([0-9.]+)/);
      expect(m !== null).assertTrue();
      if (m !== null) {
        const width: number = parseFloat(m[2]) - parseFloat(m[1]);
        expect(width >= 1.99).assertTrue();
      }
    });

    it('在场时间轴：两段分离的在场各自成条', 0, () => {
      const now: number = 1000000;
      const spans: PresenceSpan[] = [
        new PresenceSpan(now - 800000, now - 700000),
        new PresenceSpan(now - 300000, now - 200000),
      ];
      const commands: string = presenceTrackCommands(spans, now, 900000, 300, 18);
      // 两个 M 命令 = 两条独立的条
      expect((commands.match(/M/g) || []).length).assertEqual(2);
    });
  });
}
