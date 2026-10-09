import { describe, expect, it } from '@ohos/hypium';
import { mergeScanError } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { AppSettings, GpsSample, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { FieldwatchExportSerializer } from '../main/ets/fieldwatch/domain/FieldwatchExportSerializer';
import { FieldwatchPrivacyService } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';

/** 造一个带定位的信号源，用于检查各导出格式的脱敏。 */
function locatedSighting(): Sighting {
  const observation: ScanObservation = new ScanObservation(
    'ble:mask', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Tag', -40, 1700000000,
    undefined, new GpsSample(22.543210, 114.065432, 1700000000));
  return Sighting.fromObservation(observation);
}

/** 造一个带定位的 **Wi-Fi** 信号源（WiGLE 只吃 Wi-Fi）。 */
function wifiSighting(): Sighting {
  const observation: ScanObservation = new ScanObservation(
    'wifi:mask', RadioKind.WIFI, 'AA:BB:CC:DD:EE:FF', 'AP', -40, 1700000000,
    undefined, new GpsSample(22.543210, 114.065432, 1700000000));
  return Sighting.fromObservation(observation);
}

export default function fieldwatchPrivacyExportTest() {
  // §12.1「显示扫描错误、扫描器不可用和系统节流状态」。
  // 这段逻辑此前内联在页面刷新里且**结果从未被渲染**，
  // 抽成纯函数后才能锁住「什么时候应该提示、提示哪一条」。
  describe('FieldwatchScanError', () => {
    it('returns empty when both radios are healthy', 0, () => {
      expect(mergeScanError('', '')).assertEqual('');
      // 纯空白不算错误 —— 否则会出现一条空白的提示条。
      expect(mergeScanError('   ', '\t')).assertEqual('');
    });

    it('surfaces whichever channel reported a problem', 0, () => {
      expect(mergeScanError('蓝牙未开启', '')).assertEqual('蓝牙未开启');
      expect(mergeScanError('', '系统暂时拒绝或节流 Wi-Fi 扫描'))
        .assertEqual('系统暂时拒绝或节流 Wi-Fi 扫描');
    });

    it('joins both channels with the BLE error first', 0, () => {
      const merged: string = mergeScanError('蓝牙未开启', 'Wi-Fi 被节流');
      // BLE 的错误更根本，排在前面；Wi-Fi 多是临时节流。
      expect(merged).assertEqual('蓝牙未开启 · Wi-Fi 被节流');
      const ble: number = merged.indexOf('蓝牙未开启');
      const wifi: number = merged.indexOf('Wi-Fi 被节流');
      expect(ble >= 0 && wifi > ble).assertTrue();
    });

    it('trims padding before deciding whether a channel is empty', 0, () => {
      expect(mergeScanError('  蓝牙未开启  ', '')).assertEqual('蓝牙未开启');
      expect(mergeScanError('蓝牙', '  ')).assertEqual('蓝牙');
    });
  });

  describe('FieldwatchPrivacyExport', () => {

    it('keeps the vendor prefix and masks exactly the last three octets', 0, () => {
      // 原版语义：OUI（前三段）保留，用来判断厂商；后三段是设备身份，必须抹掉。
      const privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();
      expect(privacy.maskAddress('AA:BB:CC:DD:EE:FF', true)).assertEqual('AA:BB:CC:**:**:**');
      // 连字符写法同样处理
      expect(privacy.maskAddress('AA-BB-CC-DD-EE-FF', true)).assertEqual('AA-BB-CC-**-**-**');
    });

    it('leaves the address alone when privacy is off', 0, () => {
      // 反向必须成立：掩码恒开会让导出数据静默失真。
      const privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();
      expect(privacy.maskAddress('AA:BB:CC:DD:EE:FF', false)).assertEqual('AA:BB:CC:DD:EE:FF');
    });

    it('does not mangle short or non-MAC identifiers', 0, () => {
      // 短标识（星闪的匿名 ID 之类）不是 MAC，按段掩码会得到无意义的残片。
      const privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();
      expect(privacy.maskAddress('abc', true)).assertEqual('abc');
      // 两段式标识既不像 MAC 也无法按段掩码，统一返回 '***'（不泄露原值）。
      expect(privacy.maskAddress('AB:CD', true)).assertEqual('***');
    });

    it('rounds coordinates to about a kilometre when privacy is on', 0, () => {
      const privacy: FieldwatchPrivacyService = new FieldwatchPrivacyService();
      const location: GpsSample = new GpsSample(22.543210, 114.065432, 0);
      const masked: string = privacy.maskLocation(location, true);
      expect(masked).assertEqual('22.54, 114.07');
      const exact: string = privacy.maskLocation(location, false);
      expect(exact).assertEqual('22.543210, 114.065432');
    });

    it('masks the address in CSV but keeps the vendor-visible prefix', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const csv: string = new FieldwatchExportSerializer().serializeCsv([locatedSighting()], settings);
      expect(csv.indexOf('AA:BB:CC:**:**:**') >= 0).assertTrue();
      expect(csv.indexOf('DD:EE:FF') >= 0).assertFalse();
    });

    it('masks the address in JSONL under privacy mode', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const jsonl: string = new FieldwatchExportSerializer().serializeJsonl([locatedSighting()], settings);
      expect(jsonl.indexOf('AA:BB:CC:**:**:**') >= 0).assertTrue();
      // 精确坐标不能出现在 JSONL 里
      expect(jsonl.indexOf('22.543210') >= 0).assertFalse();
    });

    it('truncates GPX coordinates to two decimals when privacy is on', 0, () => {
      // GPX 天然携带精确坐标，是脱敏最容易被漏掉的一路。
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const gpx: string = new FieldwatchExportSerializer().serializeGpx([locatedSighting()], settings);
      expect(gpx.indexOf('22.54') >= 0).assertTrue();
      expect(gpx.indexOf('22.543210') >= 0).assertFalse();
      expect(gpx.indexOf('114.065432') >= 0).assertFalse();
    });

    it('keeps full GPX precision when privacy is off', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = false;
      const gpx: string = new FieldwatchExportSerializer().serializeGpx([locatedSighting()], settings);
      expect(gpx.indexOf('22.543210') >= 0).assertTrue();
    });

    it('truncates KML coordinates to two decimals when privacy is on', 0, () => {
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const kml: string = new FieldwatchExportSerializer().serializeKml([locatedSighting()], settings);
      expect(kml.indexOf('22.543210') >= 0).assertFalse();
      expect(kml.indexOf('114.065432') >= 0).assertFalse();
      expect(kml.indexOf('22.54') >= 0).assertTrue();
    });

    it('masks the address in WiGLE CSV under privacy mode', 0, () => {
      // WiGLE 是 Wi-Fi 专用格式：serializeWigle 只输出 kind=wifi 的行，
      // 所以这条必须用 Wi-Fi 设备造样本，用 BLE 会得到空表。
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const wigle: string = new FieldwatchExportSerializer().serializeWigle([wifiSighting()], settings);
      expect(wigle.indexOf('DD:EE:FF') >= 0).assertFalse();
      expect(wigle.indexOf('AA:BB:CC') >= 0).assertTrue();
    });

    it('omits BLE radios from the WiGLE export entirely', 0, () => {
      // 反向断言：WiGLE 里出现 BLE 行会让导入工具困惑，必须整行不出现。
      const settings: AppSettings = new AppSettings();
      const wigle: string = new FieldwatchExportSerializer().serializeWigle([locatedSighting()], settings);
      expect(wigle.indexOf('"WIFI"')).assertEqual(-1);
    });
  });
}