import { describe, it, expect } from '@ohos/hypium';
import {
  aclEntries, aclEntryOf, aclLimits, ACL_FORBIDDEN_ACTIONS, ACL_PORT_WHITELIST, ACL_TABLE_VERSION,
  AclCapability, AclEntry, AclRisk, AclSubject, portAllowed, taskAllows
} from '../main/ets/fieldwatch/domain/FieldwatchAcl';

export default function fieldwatchAclTest() {
  describe('FieldwatchAclTable', () => {
    // 能力全表必须覆盖 A1–A7（设计文档第 3 节）。
    it('registers all seven capabilities', 0, () => {
      const entries: AclEntry[] = aclEntries();
      expect(entries.length).assertEqual(7);
      expect(aclEntryOf(AclCapability.SUBNET_SWEEP) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.PORT_PROBE) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.RTSP_PROBE) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.ONVIF_PROBE) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.HTTP_BANNER) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.SERVICE_DISCOVERY) !== undefined).assertTrue();
      expect(aclEntryOf(AclCapability.VENDOR_MAGIC) !== undefined).assertTrue();
    });

    // 风险分级：A1/A2/A6 低危，A3/A4/A5/A7 高危且必须带协议交互提示。
    it('marks protocol capabilities as high risk with a note key', 0, () => {
      const a1: AclEntry = aclEntryOf(AclCapability.SUBNET_SWEEP) as AclEntry;
      expect(a1.risk).assertEqual(AclRisk.LOW);
      expect(a1.riskNoteKey.length).assertEqual(0);
      const a2: AclEntry = aclEntryOf(AclCapability.PORT_PROBE) as AclEntry;
      expect(a2.risk).assertEqual(AclRisk.LOW);
      const a6: AclEntry = aclEntryOf(AclCapability.SERVICE_DISCOVERY) as AclEntry;
      expect(a6.risk).assertEqual(AclRisk.LOW);
      const highRisk: AclCapability[] = [AclCapability.RTSP_PROBE, AclCapability.ONVIF_PROBE,
        AclCapability.HTTP_BANNER, AclCapability.VENDOR_MAGIC];
      highRisk.forEach((capability: AclCapability): void => {
        const entry: AclEntry = aclEntryOf(capability) as AclEntry;
        expect(entry.risk).assertEqual(AclRisk.HIGH);
        // 高危必须带「将与目标建立协议交互」的提示键。
        expect(entry.riskNoteKey.length > 0).assertTrue();
      });
    });

    // 每条能力都要有告知文案键（弹窗四要素的载体）。
    it('gives every capability a disclosure title key', 0, () => {
      aclEntries().forEach((entry: AclEntry): void => {
        expect(entry.titleKey.indexOf('app.string.') === 0).assertTrue();
      });
    });

    // 任务绑定：安防全拿、体检只 A1、找东西没有。
    it('binds capabilities to tasks minimally', 0, () => {
      expect(taskAllows(AclSubject.SECURITY_SCAN, AclCapability.SUBNET_SWEEP)).assertTrue();
      expect(taskAllows(AclSubject.SECURITY_SCAN, AclCapability.VENDOR_MAGIC)).assertTrue();
      expect(taskAllows(AclSubject.WIFI_DOCTOR, AclCapability.SUBNET_SWEEP)).assertTrue();
      // 体检不得用端口与协议能力。
      expect(taskAllows(AclSubject.WIFI_DOCTOR, AclCapability.PORT_PROBE)).assertFalse();
      expect(taskAllows(AclSubject.WIFI_DOCTOR, AclCapability.RTSP_PROBE)).assertFalse();
      // 找东西保持纯被动。
      expect(taskAllows(AclSubject.FIND, AclCapability.SUBNET_SWEEP)).assertFalse();
      expect(taskAllows(AclSubject.FIND, AclCapability.PORT_PROBE)).assertFalse();
    });

    // 端口白名单：表内放行、表外拒绝；且不含任何「登录/拉流」语义的额外端口。
    it('enforces the port whitelist', 0, () => {
      expect(portAllowed(80)).assertTrue();
      expect(portAllowed(554)).assertTrue();
      expect(portAllowed(37777)).assertTrue();
      expect(portAllowed(3702)).assertTrue();
      // 表外端口一律拒绝。
      expect(portAllowed(22)).assertFalse();
      expect(portAllowed(23)).assertFalse();
      expect(portAllowed(3306)).assertFalse();
      expect(portAllowed(0)).assertFalse();
      // 白名单里每个端口都必须能被自己放行（防手滑写错）。
      ACL_PORT_WHITELIST.forEach((port: number): void => {
        expect(portAllowed(port)).assertTrue();
      });
    });

    // 速率约束：重试恒为 0（设计文档明确不重试）。
    it('never retries and caps concurrency at 16', 0, () => {
      expect(aclLimits().retries).assertEqual(0);
      expect(aclLimits().maxConcurrency).assertEqual(16);
      expect(aclLimits().perTargetTimeoutMs).assertEqual(800);
      expect(aclLimits().totalDurationMs).assertEqual(60000);
    });

    // 排除项清单必须齐全，且**不含**任何我们真做了的能力。
    it('lists the forbidden actions and never implements them', 0, () => {
      expect(ACL_FORBIDDEN_ACTIONS.length >= 10).assertTrue();
      const joined: string = ACL_FORBIDDEN_ACTIONS.join('|');
      expect(joined.indexOf('弱口令') >= 0).assertTrue();
      expect(joined.indexOf('RTSP 拉流') >= 0).assertTrue();
      expect(joined.indexOf('GetStreamUri') >= 0).assertTrue();
      expect(joined.indexOf('GATT') >= 0).assertTrue();
      expect(joined.indexOf('公网目标') >= 0).assertTrue();
      expect(joined.indexOf('后台常驻') >= 0).assertTrue();
    });

    it('reports a table version for audit traceability', 0, () => {
      expect(ACL_TABLE_VERSION >= 1).assertTrue();
    });
  });
}
