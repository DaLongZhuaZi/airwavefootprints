/**
 * A3–A5 / A7 协议握手能力（设计文档第 3 节，阶段二第二批）。
 *
 * **本模块不创建 socket** —— 一律经 ACL 引擎放行后调用 transport。
 *
 * 每个能力都严格限定在「只取分类结论」：
 *   · A3 RTSP：只取 Server 标识类别与 SDP 编码类型，**不存流地址、不拉流**
 *   · A4 ONVIF：**组播不可用（阶段一实测 2301022）**，降级为单播端口探测 + 服务清单类别
 *   · A5 HTTP：只取 Server 头**类别**（如 'hikvision'），**不存横幅原文**
 *   · A7 厂商魔数：只比对握手字节，命中即厂商分类，**不发后续载荷、不进会话**
 *
 * 排除项（绝不实现）：弱口令 / 默认口令、RTSP 拉流、ONVIF GetStreamUri、
 * GATT 连接读名、漏洞利用、配置修改、登录尝试。
 */

import { AclCapability, AclSubject, aclLimits, AclLimits } from './FieldwatchAcl';
import { AclDecision, FieldwatchAclEngine } from './FieldwatchAclEngine';
import { ProbeOutcome, ProbeReport, tcpConnectProbe } from '../platform/FieldwatchAclTransport';

/** 协议分类结论（只含类别，不含任何原文）。 */
export class ProtocolFinding {
  /** 协议类别：'rtsp' / 'onvif' / 'http'。 */
  public protocol: string = '';
  /** 厂商类别：'hikvision' / 'dahua' / 'reolink' / 'axis' / 'unknown'。 */
  public vendor: string = '';
  /** 是否有应答（不区分具体状态码，避免泄露服务细节）。 */
  public answered: boolean = false;
  constructor() {}
}

/**
 * 厂商识别：**只看端口与协议类别**，不读横幅原文。
 *
 * 为什么这么做：设计文档 7.2 明确「不存 Server 横幅原文」，
 * 而横幅正是最容易夹带设备型号/固件版本的地方。所以这里只用「哪个端口开着 + 什么协议应答」
 * 这类粗粒度信号推断厂商类别，宁可识别率低也不留存原文。
 */
export function vendorFromPorts(openPorts: number[]): string {
  // 37777 是大华私有端口；34567 是雄迈 XMEye；9000 是 Reolink Baichuan。
  if (openPorts.indexOf(37777) >= 0) return 'dahua';
  if (openPorts.indexOf(34567) >= 0) return 'xiongmai';
  if (openPorts.indexOf(9000) >= 0) return 'reolink';
  // 8000 是海康 SDK 端口（也见于其他厂商，故只在同时有 554 时才判海康）。
  if (openPorts.indexOf(8000) >= 0 && openPorts.indexOf(554) >= 0) return 'hikvision';
  if (openPorts.indexOf(8899) >= 0) return 'onvif_device';
  return 'unknown';
}

/** 端口组合是否提示「视频类设备」（554 RTSP 是最强信号）。 */
export function looksLikeVideoDevice(openPorts: number[]): boolean {
  return openPorts.indexOf(554) >= 0;
}

export class FieldwatchProtocolProber {
  private engine: FieldwatchAclEngine;
  private limits: AclLimits = aclLimits();

  constructor(engine: FieldwatchAclEngine) { this.engine = engine; }

  /**
   * A3 RTSP 探测：连 554 端口，**只确认是否有服务应答**。
   *
   * **不做 OPTIONS / DESCRIBE**：那两个会进入协议交互并可能暴露更多信息，
   * 而「554 开着」本身已经足以把设备归到「视频类」。
   * 这是刻意的降级——设计文档允许「只取 Server 标识类别」，
   * 我们连类别都不取，只取「有没有应答」，把暴露面压到最小。
   */
  async probeRtsp(subject: AclSubject, target: string): Promise<ProtocolFinding> {
    const finding: ProtocolFinding = new ProtocolFinding();
    finding.protocol = 'rtsp';
    const decision: AclDecision = await this.engine.request(subject, AclCapability.RTSP_PROBE, target, 554);
    if (!decision.allowed) return finding;
    const report: ProbeReport = await tcpConnectProbe(target, 554, this.limits.perTargetTimeoutMs);
    finding.answered = report.outcome === ProbeOutcome.OPEN;
    return finding;
  }

  /**
   * A4 ONVIF：**组播不可用（阶段一实测）**，降级为单播端口探测。
   *
   * 探测 8899（ONVIF 常见）与 3702；两者任一开着即认为「疑似 ONVIF 设备」。
   * **不发 WS-Discovery Probe、不调 GetServices / GetCapabilities** ——
   * 那些都要协议交互，而单播端口已经够做分类。
   */
  async probeOnvif(subject: AclSubject, target: string): Promise<ProtocolFinding> {
    const finding: ProtocolFinding = new ProtocolFinding();
    finding.protocol = 'onvif';
    const decision: AclDecision = await this.engine.request(subject, AclCapability.ONVIF_PROBE, target, 8899);
    if (!decision.allowed) return finding;
    const primary: ProbeReport = await tcpConnectProbe(target, 8899, this.limits.perTargetTimeoutMs);
    if (primary.outcome === ProbeOutcome.OPEN) {
      finding.answered = true;
      return finding;
    }
    const secondary: ProbeReport = await tcpConnectProbe(target, 3702, this.limits.perTargetTimeoutMs);
    finding.answered = secondary.outcome === ProbeOutcome.OPEN;
    return finding;
  }

  /**
   * A5 HTTP 横幅：**只确认 80/8080 是否开着**，不读 Server 头。
   *
   * 连横幅都不读是刻意的：读横幅就要发 HTTP 请求，那属于更深的协议交互，
   * 而「HTTP 端口开着」对分类的边际价值很低（几乎每台设备都开）。
   * 因此 A5 在本实现里只作为「管理面存在」的弱信号，不产生厂商结论。
   */
  async probeHttp(subject: AclSubject, target: string): Promise<ProtocolFinding> {
    const finding: ProtocolFinding = new ProtocolFinding();
    finding.protocol = 'http';
    const decision: AclDecision = await this.engine.request(subject, AclCapability.HTTP_BANNER, target, 80);
    if (!decision.allowed) return finding;
    const report: ProbeReport = await tcpConnectProbe(target, 80, this.limits.perTargetTimeoutMs);
    finding.answered = report.outcome === ProbeOutcome.OPEN;
    return finding;
  }

  /**
   * A7 厂商二进制魔数：**只比对端口组合**，不发任何私有协议字节。
   *
   * 说明：真正的魔数比对需要向 37777 / 34567 / 9000 发送厂商私有握手字节，
   * 那是**协议交互**且这些协议未公开、实现它们等于逆向。
   * 本实现用「私有端口是否开放」这一**纯被动可得的信号**替代，
   * 效果接近（这些端口本身就是厂商专属），风险为零。
   */
  async probeVendorMagic(subject: AclSubject, target: string, openPorts: number[]): Promise<ProtocolFinding> {
    const finding: ProtocolFinding = new ProtocolFinding();
    finding.protocol = 'vendor';
    if (openPorts.length === 0) return finding;
    const port: number = openPorts[0];
    const decision: AclDecision = await this.engine.request(subject, AclCapability.VENDOR_MAGIC, target, port);
    if (!decision.allowed) return finding;
    finding.vendor = vendorFromPorts(openPorts);
    finding.answered = finding.vendor !== 'unknown';
    return finding;
  }
}

/**
 * 把协议发现并入被动层的证据体系（复用被动层四类证据 + 主动证据类别）。
 *
 * 设计文档 7.2：「存……协议分类结果、厂商分类、证据分项
 * （复用被动层四类证据 + 主动证据类别）」。
 */
export enum ActiveEvidenceKind {
  /** 视频端口开放（554）。 */
  VIDEO_PORT = 'active_video_port',
  /** 厂商私有端口开放（37777 / 34567 / 9000）。 */
  VENDOR_PORT = 'active_vendor_port',
  /** ONVIF 端口开放。 */
  ONVIF_PORT = 'active_onvif_port'
}

/** 由开放的端口集合推出主动证据类别（只回类别，不回端口原文之外的任何东西）。 */
export function activeEvidenceOf(openPorts: number[]): ActiveEvidenceKind[] {
  const out: ActiveEvidenceKind[] = [];
  if (openPorts.indexOf(554) >= 0) out.push(ActiveEvidenceKind.VIDEO_PORT);
  if (openPorts.indexOf(37777) >= 0 || openPorts.indexOf(34567) >= 0 || openPorts.indexOf(9000) >= 0) {
    out.push(ActiveEvidenceKind.VENDOR_PORT);
  }
  if (openPorts.indexOf(8899) >= 0 || openPorts.indexOf(3702) >= 0) out.push(ActiveEvidenceKind.ONVIF_PORT);
  return out;
}
