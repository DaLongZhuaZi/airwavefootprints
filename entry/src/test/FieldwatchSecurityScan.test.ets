import { describe, it, expect } from '@ohos/hypium';
import {
  SECURITY_FOLLOW_ATTENTION_SCORE, SECURITY_FOLLOW_SUSPECT_SCORE, SECURITY_NEW_FACE_MIN_HITS,
  SecurityClassCount, SecuritySummary, buildSecuritySummary, countByKind, newFaceCount,
  summaryHeadlineKey, topClassesOf
} from '../main/ets/fieldwatch/domain/FieldwatchSecurityScan';
import { RadioFacts, RadioKind, ScanObservation, SignatureClass, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureFleet } from '../main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels';

/** 造一条设备：key + 类别（通过 signatureIds 注入）。 */
function sightingOf(key: string, kind: RadioKind, signatureIds: string[], count: number = 5): Sighting {
  const observation: ScanObservation = new ScanObservation(key, kind, key, 'dev', -60, 1000, new RadioFacts());
  const sighting: Sighting = Sighting.fromObservation(observation);
  sighting.signatureIds = signatureIds;
  sighting.count = count;
  return sighting;
}

function fleet(id: string, category: SignatureClass): SignatureFleet {
  return new SignatureFleet(id, id, category);
}

export default function fieldwatchSecurityScanTest() {
  describe('FieldwatchSecurityScan', () => {
    // 分类型计数是分享卡与汇总页共用的基础数，且**三者之和必须等于总数** ——
    // 曾经在别处踩过「星闪被算进 Wi-Fi，导致分类和总数对不上」的坑。
    it('counts each radio kind and keeps the sum equal to total', 0, () => {
      const list: Sighting[] = [
        sightingOf('ble:1', RadioKind.BLE, []),
        sightingOf('ble:2', RadioKind.BLE, []),
        sightingOf('wifi:1', RadioKind.WIFI, []),
        sightingOf('nearlink:1', RadioKind.NEARLINK, [])
      ];
      const kinds: number[] = countByKind(list);
      expect(kinds[0]).assertEqual(2);
      expect(kinds[1]).assertEqual(1);
      expect(kinds[2]).assertEqual(1);
      expect(kinds[0] + kinds[1] + kinds[2]).assertEqual(list.length);
    });

    // 分类 Top 只取第一命中：一台设备算进两个类会让各类之和超过总数。
    it('counts each device in exactly one category using its first signature', 0, () => {
      const fleets: SignatureFleet[] = [fleet('f-audio', SignatureClass.AUDIO), fleet('f-finder', SignatureClass.FINDER)];
      const list: Sighting[] = [
        sightingOf('ble:1', RadioKind.BLE, ['f-audio', 'f-finder']),
        sightingOf('ble:2', RadioKind.BLE, ['f-finder']),
        sightingOf('ble:3', RadioKind.BLE, [])
      ];
      const rows: SecurityClassCount[] = topClassesOf(list, fleets);
      let total: number = 0;
      rows.forEach((row: SecurityClassCount): void => { total += row.count; });
      expect(total).assertEqual(3);
      // 数量降序：都是 1 台时按类别名排序，音频(audio) 在 finder 前。
      expect(rows[0].category).assertEqual(SignatureClass.AUDIO);
    });

    // 无特征命中的 Wi-Fi 设备归到「网络设备」而不是「其他」：
    // 否则实扫 119 台里 91 台挤在「其他」，分类 Top 等于没分。
    it('falls back to a meaningful class for unmatched Wi-Fi devices', 0, () => {
      const list: Sighting[] = [sightingOf('wifi:1', RadioKind.WIFI, []), sightingOf('wifi:2', RadioKind.WIFI, [])];
      const rows: SecurityClassCount[] = topClassesOf(list, []);
      expect(rows.length).assertEqual(1);
      expect(rows[0].category).assertEqual(SignatureClass.ISP);
      expect(rows[0].count).assertEqual(2);
      // BLE 无命中仍归 OTHER —— 我们确实不知道它是什么。
      const ble: SecurityClassCount[] = topClassesOf([sightingOf('ble:1', RadioKind.BLE, [])], []);
      expect(ble[0].category).assertEqual(SignatureClass.OTHER);
    });

    it('caps the class list at three entries', 0, () => {
      const fleets: SignatureFleet[] = [
        fleet('a', SignatureClass.AUDIO), fleet('b', SignatureClass.FINDER), fleet('c', SignatureClass.CAMERA),
        fleet('d', SignatureClass.LOCK)
      ];
      const list: Sighting[] = [
        sightingOf('ble:1', RadioKind.BLE, ['a']), sightingOf('ble:2', RadioKind.BLE, ['b']),
        sightingOf('ble:3', RadioKind.BLE, ['c']), sightingOf('ble:4', RadioKind.BLE, ['d'])
      ];
      expect(topClassesOf(list, fleets).length).assertEqual(3);
    });

    // 新面孔的基线口径：扫描开始时就存在的设备不算新；只闪一次的也不算。
    it('counts new faces only when unseen before and repeated enough', 0, () => {
      const list: Sighting[] = [
        sightingOf('ble:old', RadioKind.BLE, [], 10),
        sightingOf('ble:new-repeated', RadioKind.BLE, [], SECURITY_NEW_FACE_MIN_HITS),
        sightingOf('ble:new-once', RadioKind.BLE, [], 1)
      ];
      const known: string[] = ['ble:old'];
      expect(newFaceCount(list, known)).assertEqual(1);
      // 基线为空时，两台都会算新（但只闪一次的那台仍被 count 门槛挡住）。
      expect(newFaceCount(list, [])).assertEqual(2);
    });

    // 跟随评分的门槛与反跟随引擎同一口径（70 嫌疑 / 45 关注）。
    it('flags suspicion at 70 and only shows the score from 45', 0, () => {
      const base: Sighting[] = [sightingOf('ble:1', RadioKind.BLE, [])];
      const low: SecuritySummary = buildSecuritySummary(base, [], [], 44, 0, 1000);
      expect(low.followSuspect).assertFalse();
      expect(low.showsFollow()).assertFalse();
      const mid: SecuritySummary = buildSecuritySummary(base, [], [], SECURITY_FOLLOW_ATTENTION_SCORE, 0, 1000);
      expect(mid.followSuspect).assertFalse();
      expect(mid.showsFollow()).assertTrue();
      const high: SecuritySummary = buildSecuritySummary(base, [], [], SECURITY_FOLLOW_SUSPECT_SCORE, 0, 1000);
      expect(high.followSuspect).assertTrue();
    });

    it('never shows a negative or NaN follow score', 0, () => {
      const base: Sighting[] = [sightingOf('ble:1', RadioKind.BLE, [])];
      expect(buildSecuritySummary(base, [], [], -20, 0, 1).followScore).assertEqual(0);
      expect(buildSecuritySummary(base, [], [], NaN, 0, 1).followScore).assertEqual(0);
    });

    // 结论文案的三档：可疑 > 拥挤 > 安静。**没有「安全」这一档**，
    // 因为不广播的设备发现不了，说「安全」是在撒谎。
    it('picks the headline key without ever claiming safety', 0, () => {
      const suspect: Sighting[] = [];
      for (let i: number = 0; i < 30; i += 1) suspect.push(sightingOf('ble:' + i.toString(), RadioKind.BLE, []));
      expect(summaryHeadlineKey(buildSecuritySummary(suspect, [], [], 80, 0, 1)))
        .assertEqual('app.string.fieldwatch_security_headline_suspicious');
      expect(summaryHeadlineKey(buildSecuritySummary(suspect, [], [], 0, 0, 1)))
        .assertEqual('app.string.fieldwatch_security_headline_crowded');
      expect(summaryHeadlineKey(buildSecuritySummary([sightingOf('ble:1', RadioKind.BLE, [])], [], [], 0, 0, 1)))
        .assertEqual('app.string.fieldwatch_security_headline_quiet');
    });

    it('reports an empty scan distinctly from a crowded one', 0, () => {
      const empty: SecuritySummary = buildSecuritySummary([], [], [], 0, 10, 20);
      expect(empty.hasDevices()).assertFalse();
      expect(empty.total).assertEqual(0);
      expect(empty.durationMs()).assertEqual(10);
    });
  });
}
