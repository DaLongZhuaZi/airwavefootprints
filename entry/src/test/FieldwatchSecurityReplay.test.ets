import { describe, it, expect } from '@ohos/hypium';
import { SecurityScanRecord, SuspectSnapshot } from '../main/ets/fieldwatch/data/FieldwatchSecurityHistoryRepository';

export default function fieldwatchSecurityReplayTest() {
  describe('FieldwatchSecurityReplay', () => {
    // 老记录（P3-2 写入）没有快照列：必须能区分「无快照」与「当时确实没有可疑」。
    it('flags legacy records as having no snapshot', 0, () => {
      const legacy: SecurityScanRecord = new SecurityScanRecord();
      legacy.id = 'scan-1000';
      legacy.total = 120;
      legacy.confirmedCount = 0;
      legacy.suspiciousCount = 2;
      // 老记录：默认值 —— 空清单 + hasSnapshot=false。
      expect(legacy.hasSnapshot).assertFalse();
      expect(legacy.suspects.length).assertEqual(0);
      // 关键：汇总里说「2 台可疑」，但清单为空，回放页必须按「无快照」处理，
      // 不能显示成「当时没有可疑设备」（两者意义相反）。
      expect(legacy.suspiciousCount > 0).assertTrue();
      expect(legacy.suspects.length === 0 && !legacy.hasSnapshot).assertTrue();
    });

    // 新记录：有快照，能逐条回放档位与证据。
    it('replays a snapshot with verdicts and evidence', 0, () => {
      const record: SecurityScanRecord = new SecurityScanRecord();
      record.id = 'scan-2000';
      record.hasSnapshot = true;
      const first: SuspectSnapshot = new SuspectSnapshot();
      first.label = 'IPCAM-1';
      first.address = 'B0:C5:54:11:22:33';
      first.verdict = 'confirmed';
      first.evidenceKeys.push('oui');
      first.evidenceKeys.push('name');
      const second: SuspectSnapshot = new SuspectSnapshot();
      second.label = '';
      second.address = 'EC:71:DB:00:00:01';
      second.verdict = 'suspicious';
      second.evidenceKeys.push('oui');
      record.suspects.push(first);
      record.suspects.push(second);
      expect(record.hasSnapshot).assertTrue();
      expect(record.suspects.length).assertEqual(2);
      expect(record.suspects[0].verdict).assertEqual('confirmed');
      expect(record.suspects[0].evidenceKeys.length).assertEqual(2);
      // 空名设备回放时用地址展示（不显示空白）。
      expect(record.suspects[1].label.length).assertEqual(0);
      expect(record.suspects[1].address.length > 0).assertTrue();
    });

    // 快照里的档位字符串必须仍是三档口径，绝不出现 safe/excluded。
    it('keeps the three-verdict vocabulary in snapshots', 0, () => {
      const allowed: string[] = ['confirmed', 'suspicious', 'none'];
      const record: SecurityScanRecord = new SecurityScanRecord();
      record.hasSnapshot = true;
      const one: SuspectSnapshot = new SuspectSnapshot();
      one.verdict = 'confirmed';
      record.suspects.push(one);
      record.suspects.forEach((item: SuspectSnapshot): void => {
        expect(allowed.indexOf(item.verdict) >= 0).assertTrue();
      });
      expect(allowed.indexOf('safe')).assertEqual(-1);
      expect(allowed.indexOf('excluded')).assertEqual(-1);
    });

    // 时长计算：老记录字段缺失时不能算出负数。
    it('computes duration without going negative', 0, () => {
      const record: SecurityScanRecord = new SecurityScanRecord();
      record.startedAt = 1000;
      record.endedAt = 61000;
      expect(record.durationMs()).assertEqual(60000);
      const broken: SecurityScanRecord = new SecurityScanRecord();
      broken.startedAt = 0;
      broken.endedAt = 0;
      expect(broken.durationMs()).assertEqual(0);
    });
  });
}
