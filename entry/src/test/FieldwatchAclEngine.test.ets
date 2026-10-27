import { describe, it, expect } from '@ohos/hypium';
import {
  AclAuditRecord, AclDecision, AclDenyReason, AclSession, FieldwatchAclEngine, IAclAuditSink
} from '../main/ets/fieldwatch/domain/FieldwatchAclEngine';
import { AclCapability, AclSubject } from '../main/ets/fieldwatch/domain/FieldwatchAcl';
import { AclScope, scopeFromLocal } from '../main/ets/fieldwatch/domain/FieldwatchAclScope';
import { LocalNetworkInfo } from '../main/ets/fieldwatch/platform/FieldwatchAclTransport';

/** 假审计：记录所有写入，可指定「写入失败」以测失败关闭。 */
class FakeAudit implements IAclAuditSink {
  public records: AclAuditRecord[] = [];
  public failNext: boolean = false;
  async append(record: AclAuditRecord): Promise<boolean> {
    if (this.failNext) return false;
    this.records.push(record);
    return true;
  }
}

function scope(): AclScope {
  const info: LocalNetworkInfo = new LocalNetworkInfo();
  info.ip = '192.168.5.125';
  info.prefixLength = 24;
  info.gateway = '192.168.5.1';
  info.fromLinkAddresses = true;
  return scopeFromLocal(info);
}

function engineWithScope(): FieldwatchAclEngine {
  const engine: FieldwatchAclEngine = new FieldwatchAclEngine(new FakeAudit());
  engine.setScope(scope());
  return engine;
}

export default function fieldwatchAclEngineTest() {
  describe('FieldwatchAclEngine', () => {
    // ① 未授权会话 → 一律拒绝（拒绝时零发包由 transport 不被调用来保证）。
    it('denies everything without a session grant', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.NO_SESSION_GRANT);
    });

    // ② 任务绑定：体检不能用端口探针。
    it('denies a capability the task is not bound to', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      const decision: AclDecision = await engine.request(AclSubject.WIFI_DOCTOR,
        AclCapability.PORT_PROBE, '192.168.5.50', 80);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.TASK_NOT_ALLOWED);
    });

    // ③ 超范围目标零放行。
    it('denies out-of-scope targets', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      // 公网。
      let decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '8.8.8.8', 0);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.TARGET_OUT_OF_SCOPE);
      // 本机。
      decision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.125', 0);
      expect(decision.allowed).assertFalse();
      // 网关。
      decision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.1', 0);
      expect(decision.allowed).assertFalse();
      // 别的网段。
      decision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '10.0.0.9', 0);
      expect(decision.allowed).assertFalse();
    });

    // ④ 范围推导失败 → 失败关闭，任何目标都不放行。
    it('fails closed when the scope is unknown', 0, async () => {
      const engine: FieldwatchAclEngine = new FieldwatchAclEngine(new FakeAudit());
      const guessed: LocalNetworkInfo = new LocalNetworkInfo();
      guessed.ip = '192.168.5.125';
      guessed.prefixLength = 24;
      guessed.fromLinkAddresses = false;
      engine.setScope(scopeFromLocal(guessed));
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.TARGET_OUT_OF_SCOPE);
    });

    // ⑤ 正常放行。
    it('allows an in-scope target after granting', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP, AclCapability.PORT_PROBE]);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.PORT_PROBE, '192.168.5.50', 80);
      expect(decision.allowed).assertTrue();
      expect(decision.reason).assertEqual(AclDenyReason.NONE);
    });

    // ⑥ 端口白名单。
    it('denies ports outside the whitelist', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.PORT_PROBE]);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.PORT_PROBE, '192.168.5.50', 22);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.PORT_NOT_ALLOWED);
    });

    // ⑦ 会话内只授了 A1，就不能用 A2。
    it('only allows capabilities granted in this session', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.PORT_PROBE, '192.168.5.50', 80);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.NO_SESSION_GRANT);
    });

    // ⑧ 会话结束后授权失效（仅本会话有效）。
    it('revokes the grant when the session ends', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      let decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertTrue();
      engine.endSession(false);
      decision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.NO_SESSION_GRANT);
    });

    // ⑨ 取消后立刻拒绝。
    it('denies after cancellation', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      engine.endSession(true);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
    });

    // ⑩ 设置页关闭某项能力后立即生效。
    it('honours the per-capability disable switch', 0, async () => {
      const engine: FieldwatchAclEngine = engineWithScope();
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      engine.setCapabilityDisabled(AclCapability.SUBNET_SWEEP, true);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
      expect(decision.reason).assertEqual(AclDenyReason.CAPABILITY_DISABLED);
      // 一键关闭全部。
      engine.setCapabilityDisabled(AclCapability.SUBNET_SWEEP, false);
      engine.disableAll([AclCapability.SUBNET_SWEEP, AclCapability.PORT_PROBE]);
      expect(engine.isDisabled(AclCapability.SUBNET_SWEEP)).assertTrue();
      expect(engine.isDisabled(AclCapability.PORT_PROBE)).assertTrue();
    });

    // ⑪ 审计：放行与拒绝都记账，且记录带表版本；只记网段不记逐台地址。
    it('audits both grants and denials with the table version', 0, async () => {
      const audit: FakeAudit = new FakeAudit();
      const engine: FieldwatchAclEngine = new FieldwatchAclEngine(audit);
      engine.setScope(scope());
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      await engine.request(AclSubject.SECURITY_SCAN, AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      await engine.request(AclSubject.SECURITY_SCAN, AclCapability.PORT_PROBE, '192.168.5.50', 80);
      expect(audit.records.length).assertEqual(2);
      expect(audit.records[0].success).assertTrue();
      expect(audit.records[1].success).assertFalse();
      expect(audit.records[1].denyReason.length > 0).assertTrue();
      // 表版本必须记下来（事后追溯当时按哪版规则放行）。
      expect(audit.records[0].tableVersion >= 1).assertTrue();
      // 只记网段，不记逐台目标地址。
      expect(audit.records[0].scope).assertEqual('192.168.5.0/24');
    });

    // ⑫ **失败关闭**：审计写失败时不得放行。
    it('fails closed when the audit sink fails', 0, async () => {
      const audit: FakeAudit = new FakeAudit();
      audit.failNext = true;
      const engine: FieldwatchAclEngine = new FieldwatchAclEngine(audit);
      engine.setScope(scope());
      engine.grantSession([AclCapability.SUBNET_SWEEP]);
      const decision: AclDecision = await engine.request(AclSubject.SECURITY_SCAN,
        AclCapability.SUBNET_SWEEP, '192.168.5.50', 0);
      expect(decision.allowed).assertFalse();
    });
  });
}
