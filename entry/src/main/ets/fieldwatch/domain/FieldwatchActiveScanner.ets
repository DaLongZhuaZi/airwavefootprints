/**
 * 主动扫描执行器：A1 / A2 / A6（枚举与发现，设计文档第 5 节阶段二第一批）。
 *
 * **本模块不创建任何 socket** —— 一律经 `FieldwatchAclEngine.request()` 放行后，
 * 再调 `FieldwatchAclTransport` 的探测函数。这样门禁成立：
 * 没有放行就没有发包。
 *
 * 数据红线：只回传存活/端口/服务类别结论，不存载荷。
 */

import { logger } from 'ngf_framework';
import { AclCapability, AclSubject, aclLimits, AclLimits } from '../domain/FieldwatchAcl';
import { AclDecision, FieldwatchAclEngine } from '../domain/FieldwatchAclEngine';
import { candidateTargets, AclScope } from '../domain/FieldwatchAclScope';
import { multicastProbe, ProbeOutcome, ProbeReport, tcpConnectProbe, udpQueryProbe } from '../platform/FieldwatchAclTransport';

const TAG: string = 'FieldwatchActiveScan';

/** 一台存活主机的结论。 */
export class ActiveHost {
  public address: string = '';
  /** 开放端口（只记 open，不记 closed）。 */
  public openPorts: number[] = [];
  /** 服务发现是否应答（A6）。 */
  public serviceAnswered: boolean = false;
  constructor() {}
}

/** 一次主动扫描的结果。 */
export class ActiveScanResult {
  public hosts: ActiveHost[] = [];
  /** 实际探测的目标数。 */
  public probed: number = 0;
  /** 是否因范围不可用而未执行。 */
  public skippedByScope: boolean = false;
  /** 是否被取消。 */
  public cancelled: boolean = false;
  constructor() {}
}

/** A2 用的探测端口（从白名单里挑与摄像头/媒体最相关的几个，不是全白名单）。 */
export const ACTIVE_PORT_CANDIDATES: number[] = [80, 443, 554, 8000, 8899, 37777, 34567, 9000];

export class FieldwatchActiveScanner {
  private engine: FieldwatchAclEngine;
  private limits: AclLimits = aclLimits();
  private cancelled: boolean = false;

  constructor(engine: FieldwatchAclEngine) { this.engine = engine; }

  /** 用户取消：置标记，后续申请会被引擎拒绝，在途探测自然结束。 */
  cancel(): void {
    this.cancelled = true;
    this.engine.endSession(true);
  }

  /**
   * 执行 A1（存活）+ A2（端口）+ A6（服务发现）。
   *
   * 顺序即设计文档第 5 节「先接 A1 + A2 + A6」：先用 A1 找出活着的主机，
   * 再对存活主机做 A2/A6 —— 不对全网段盲目打端口，这既是礼貌也是速率约束。
   */
  async run(scope: AclScope, subject: AclSubject, targetLimit: number): Promise<ActiveScanResult> {
    const result: ActiveScanResult = new ActiveScanResult();
    if (!scope.usable) {
      result.skippedByScope = true;
      logger.info(TAG, '范围不可用，主动扫描未执行（失败关闭）');
      return result;
    }
    const targets: string[] = candidateTargets(scope, targetLimit);
    if (targets.length === 0) {
      result.skippedByScope = true;
      return result;
    }
    const startedAt: number = Date.now();
    // ── A1：并发存活探测 ──
    const alive: string[] = [];
    for (let index: number = 0; index < targets.length; index += this.limits.maxConcurrency) {
      if (this.cancelled) { result.cancelled = true; break; }
      if (Date.now() - startedAt > this.limits.totalDurationMs) break;
      const batch: string[] = targets.slice(index, index + this.limits.maxConcurrency);
      const probes: Promise<boolean>[] = [];
      batch.forEach((target: string): void => { probes.push(this.sweepOne(subject, target)); });
      const outcomes: boolean[] = await Promise.all(probes);
      for (let i: number = 0; i < batch.length; i += 1) {
        if (outcomes[i]) alive.push(batch[i]);
        result.probed += 1;
      }
    }
    // ── A2 + A6：只对存活主机做，且同样受总时长约束 ──
    for (let i: number = 0; i < alive.length; i += 1) {
      if (this.cancelled) { result.cancelled = true; break; }
      if (Date.now() - startedAt > this.limits.totalDurationMs) break;
      const host: ActiveHost = new ActiveHost();
      host.address = alive[i];
      for (let p: number = 0; p < ACTIVE_PORT_CANDIDATES.length; p += 1) {
        if (this.cancelled) break;
        if (Date.now() - startedAt > this.limits.totalDurationMs) break;
        const port: number = ACTIVE_PORT_CANDIDATES[p];
        const ok: boolean = await this.portOne(subject, host.address, port);
        if (ok) host.openPorts.push(port);
      }
      // A6：只对有 UPnP 端口开着的主机发 M-SEARCH（避免无谓发包）。
      if (host.openPorts.indexOf(1900) >= 0 || host.openPorts.indexOf(3702) >= 0) {
        host.serviceAnswered = await this.discoveryOne(subject, host.address);
      }
      result.hosts.push(host);
    }
    logger.info(TAG, '主动扫描结束: 探测=' + result.probed.toString() + ' 存活=' + result.hosts.length.toString());
    return result;
  }

  /** A1 单目标存活判定（经引擎放行后才发包）。 */
  private async sweepOne(subject: AclSubject, target: string): Promise<boolean> {
    const decision: AclDecision = await this.engine.request(subject, AclCapability.SUBNET_SWEEP, target, 0);
    if (!decision.allowed) return false;
    const report: ProbeReport = await tcpConnectProbe(target, 80, this.limits.perTargetTimeoutMs);
    if (report.outcome === ProbeOutcome.OPEN) return true;
    // 80 不通不代表不在线：再用 443 试一次（**不是重试同一端口**，是换一个探测点）。
    const second: ProbeReport = await tcpConnectProbe(target, 443, this.limits.perTargetTimeoutMs);
    return second.outcome === ProbeOutcome.OPEN;
  }

  /** A2 单端口探测。 */
  private async portOne(subject: AclSubject, target: string, port: number): Promise<boolean> {
    const decision: AclDecision = await this.engine.request(subject, AclCapability.PORT_PROBE, target, port);
    if (!decision.allowed) return false;
    const report: ProbeReport = await tcpConnectProbe(target, port, this.limits.perTargetTimeoutMs);
    return report.outcome === ProbeOutcome.OPEN;
  }

  /** A6 服务发现：向目标的 UPnP 端口发 M-SEARCH（主动）。 */
  private async discoveryOne(subject: AclSubject, target: string): Promise<boolean> {
    const decision: AclDecision = await this.engine.request(subject, AclCapability.SERVICE_DISCOVERY, target, 1900);
    if (!decision.allowed) return false;
    const payload: string = buildMSearch();
    const report: ProbeReport = await udpQueryProbe(target, 1900, payload, this.limits.perTargetTimeoutMs);
    return report.outcome === ProbeOutcome.OPEN;
  }

  /** A4 用组播 WS-Discovery Probe（阶段二第二批接入，这里先留入口）。 */
  async multicastDiscovery(subject: AclSubject, group: string, representative: string): Promise<boolean> {
    const decision: AclDecision = await this.engine.request(subject, AclCapability.ONVIF_PROBE, group, 3702);
    if (!decision.allowed) return false;
    const payload: string = buildWsDiscoveryProbe();
    const report: ProbeReport = await multicastProbe(group, 3702, payload, this.limits.perTargetTimeoutMs);
    return report.outcome === ProbeOutcome.OPEN;
  }
}

/**
 * 构造 M-SEARCH 报文（A6）。
 *
 * 身份最小化（设计文档 7.3）：不写 App 名、版本号、设备名。
 */
function buildMSearch(): string {
  const lines: string[] = [
    'M-SEARCH * HTTP/1.1',
    'HOST: 239.255.255.250:1900',
    'MAN: "ssdp:discover"',
    'MX: 1',
    'ST: urn:schemas-upnp-org:device:DigitalSecurityCamera:1',
    '', ''
  ];
  return lines.join('\r\n');
}

/** 构造 ONVIF WS-Discovery Probe（A4），只查 NetworkVideoTransmitter。 */
function buildWsDiscoveryProbe(): string {
  const lines: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"',
    '  xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"',
    '  xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"',
    '  xmlns:dn="http://www.onvif.org/ver10/network/wsdl">',
    '  <e:Header>',
    '    <w:MessageID>uuid:' + '00000000-0000-0000-0000-000000000000' + '</w:MessageID>',
    '    <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>',
    '    <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>',
    '  </e:Header>',
    '  <e:Body>',
    '    <d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe>',
    '  </e:Body>',
    '</e:Envelope>'
  ];
  return lines.join('\r\n');
}
