/**
 * ACL 传输层：**全仓唯一允许创建 socket 的地方**。
 *
 * 设计文档 2.3 / 2.4 的门禁：除 ACL 引擎模块外，代码中不得出现 socket 创建调用。
 * 因此 `constructTCPSocketInstance` / `constructUDPSocketInstance` / `constructMulticastSocketInstance`
 * 只允许出现在本文件（以及阶段一诊断模块，后者阶段二结束时删除）。
 *
 * 本层只做「按已放行的申请发包并取最小结论」，不做任何策略判断 ——
 * 策略全在 `FieldwatchAclEngine`，这里拿到的每一条都已经过五步核对。
 *
 * 数据红线（设计文档 7.2）：
 *   · 只回传「open / closed / timeout」「协议类别」「厂商类目」这类**结论**；
 *   · 不保存、不打印报文载荷、Server 横幅原文、流地址、完整设备描述文档。
 */

import { socket } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchAclTransport';

/**
 * 本机网络信息（网段推导用）。
 *
 * **放在 transport 而不是单独的诊断模块**：读 `linkAddresses` 不创建 socket，
 * 但与主动扫描同属「网络信息获取」，集中在一处便于门禁核对。
 */
export class LocalNetworkInfo {
  /** 本机 IPv4，点分十进制；空串表示未取到。 */
  public ip: string = '';
  /** 前缀长（如 24）；0 表示未取到。 */
  public prefixLength: number = 0;
  /** 网关 IPv4；空串表示未取到。 */
  public gateway: string = '';
  /** 是否成功从 linkAddresses 推导（false 则必须降级拒绝，见 AclScope）。 */
  public fromLinkAddresses: boolean = false;
  constructor() {}
}

/** 32 位整数 IP → 点分十进制。 */
export function intToIpv4(value: number): string {
  if (!(value > 0)) return '';
  return ((value >>> 24) & 0xFF).toString() + '.' + ((value >>> 16) & 0xFF).toString() + '.'
    + ((value >>> 8) & 0xFF).toString() + '.' + (value & 0xFF).toString();
}

/**
 * 读本机网络信息：**只用 linkAddresses 的前缀长**，拿不到就标 `fromLinkAddresses=false`。
 *
 * 真机实测（阶段一）：`linkAddresses` 给出 `prefix=24` 与网关 `192.168.5.1`，可信。
 * `getIpInfo` 没有前缀长，无法用于本设计 —— 所以**不做 /24 猜测降级**，
 * 由 `scopeFromLocal` 直接拒绝执行（设计文档第 5 节降级方案 b）。
 */
export function readLocalNetwork(): LocalNetworkInfo {
  const info: LocalNetworkInfo = new LocalNetworkInfo();
  try {
    const handle: connection.NetHandle = connection.getDefaultNetSync();
    const props: connection.ConnectionProperties = connection.getConnectionPropertiesSync(handle);
    props.linkAddresses.forEach((link: connection.LinkAddress): void => {
      if (info.fromLinkAddresses) return;
      const raw: string = String(link.address.address);
      if (raw.indexOf(':') >= 0) return;
      if (link.prefixLength <= 0) return;
      info.ip = raw;
      info.prefixLength = link.prefixLength;
      info.fromLinkAddresses = info.ip.length > 0;
    });
    if (props.routes.length > 0) {
      // 网关：优先默认路由，否则取任一 IPv4 网关（真机上 isDefaultRoute 可能全为 false）。
      props.routes.forEach((route: connection.RouteInfo): void => {
        if (info.gateway.length > 0) return;
        if (!route.isDefaultRoute) return;
        const gw: string = String(route.gateway.address);
        if (gw.indexOf(':') >= 0) return;
        info.gateway = gw;
      });
      if (info.gateway.length === 0) {
        props.routes.forEach((route: connection.RouteInfo): void => {
          if (info.gateway.length > 0) return;
          const gw: string = String(route.gateway.address);
          if (gw.length === 0 || gw === '0.0.0.0') return;
          if (gw.indexOf(':') >= 0) return;
          info.gateway = gw;
        });
      }
    }
  } catch (error) {
    logger.warn(TAG, '读取本机网络信息失败（可能缺 GET_NETWORK_INFO）');
  }
  return info;
}

/** 探测结论。 */
export enum ProbeOutcome {
  /** 端口开放 / 有服务应答。 */
  OPEN = 'open',
  /** 明确被拒（RST）。 */
  CLOSED = 'closed',
  /** 超时或无应答。 */
  TIMEOUT = 'timeout',
  /** 出错（含被取消）。 */
  ERROR = 'error'
}

/** 一次探测的结果（只含结论，不含载荷）。 */
export class ProbeReport {
  public outcome: ProbeOutcome = ProbeOutcome.ERROR;
  /** 耗时（毫秒）。 */
  public elapsedMs: number = 0;
  /** 协议类别（如 'rtsp' / 'http' / 'onvif'），空串表示未判定。 */
  public protocolKind: string = '';
  /** 厂商类目（如 'hikvision' / 'dahua'），空串表示未判定。 */
  public vendorKind: string = '';
  constructor() {}
}

/** 全仓唯一的 TCP 连接探测：只 connect + close，**不发送任何应用层数据**。 */
export async function tcpConnectProbe(host: string, port: number, timeoutMs: number): Promise<ProbeReport> {
  const report: ProbeReport = new ProbeReport();
  const started: number = Date.now();
  let tcp: socket.TCPSocket | undefined = undefined;
  try {
    tcp = socket.constructTCPSocketInstance();
    const address: socket.NetAddress = { address: host, port: port };
    const options: socket.TCPConnectOptions = { address: address, timeout: timeoutMs };
    await tcp.connect(options);
    report.outcome = ProbeOutcome.OPEN;
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    // 2301114 / 2301116 一类的超时与拒连都按 TIMEOUT 归档，不区分也不重试。
    report.outcome = failure.code === 2301115 ? ProbeOutcome.CLOSED : ProbeOutcome.TIMEOUT;
  } finally {
    report.elapsedMs = Date.now() - started;
    if (tcp !== undefined) {
      try { await tcp.close(); } catch (error) { /* 关闭失败不影响结论 */ }
    }
  }
  return report;
}

/**
 * 发一个 UDP 报文并等待回包（A6 服务发现查询用）。
 *
 * **只回传「有没有回包」**，不回传内容 —— 内容里可能含设备描述文档，属于不得保存的类别。
 */
export async function udpQueryProbe(host: string, port: number, payload: string,
  timeoutMs: number): Promise<ProbeReport> {
  const report: ProbeReport = new ProbeReport();
  const started: number = Date.now();
  let udp: socket.UDPSocket | undefined = undefined;
  try {
    udp = socket.constructUDPSocketInstance();
    const bindAddress: socket.NetAddress = { address: '0.0.0.0', port: 0 };
    await udp.bind(bindAddress);
    const target: socket.NetAddress = { address: host, port: port };
    const options: socket.UDPSendOptions = { data: payload, address: target };
    await udp.send(options);
    // 等待回包：收到即 OPEN；超时即 TIMEOUT。
    const got: boolean = await waitForMessage(udp, timeoutMs);
    report.outcome = got ? ProbeOutcome.OPEN : ProbeOutcome.TIMEOUT;
  } catch (error) {
    report.outcome = ProbeOutcome.ERROR;
    logger.debug(TAG, 'UDP 查询失败');
  } finally {
    report.elapsedMs = Date.now() - started;
    if (udp !== undefined) {
      try { await udp.close(); } catch (error) { /* ignore */ }
    }
  }
  return report;
}

/** 等一条 UDP 回包，超时返回 false。**不读取、不记录内容**。 */
function waitForMessage(udp: socket.UDPSocket, timeoutMs: number): Promise<boolean> {
  return new Promise<boolean>((resolve: (value: boolean) => void): void => {
    let settled: boolean = false;
    const timer: number = setTimeout((): void => {
      if (settled) return;
      settled = true;
      resolve(false);
    }, timeoutMs);
    udp.on('message', (): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(true);
    });
  });
}

/**
 * 组播加入 + 发 Probe + 等回包（A4 ONVIF WS-Discovery 用）。
 *
 * 键点：`addMembership` 在 `MulticastSocket` 上，不在 `UDPSocket` 上
 * （`interface MulticastSocket extends UDPSocket`），必须用 `constructMulticastSocketInstance()`。
 */
export async function multicastProbe(group: string, port: number, payload: string,
  timeoutMs: number): Promise<ProbeReport> {
  const report: ProbeReport = new ProbeReport();
  const started: number = Date.now();
  let mc: socket.MulticastSocket | undefined = undefined;
  try {
    mc = socket.constructMulticastSocketInstance();
    const bindAddress: socket.NetAddress = { address: '0.0.0.0', port: 0 };
    await mc.bind(bindAddress);
    const groupAddress: socket.NetAddress = { address: group, port: port };
    await mc.addMembership(groupAddress);
    const sendOptions: socket.UDPSendOptions = { data: payload, address: groupAddress };
    await mc.send(sendOptions);
    const got: boolean = await waitForMessage(mc, timeoutMs);
    report.outcome = got ? ProbeOutcome.OPEN : ProbeOutcome.TIMEOUT;
  } catch (error) {
    report.outcome = ProbeOutcome.ERROR;
    logger.debug(TAG, '组播 Probe 失败');
  } finally {
    report.elapsedMs = Date.now() - started;
    if (mc !== undefined) {
      try { await mc.close(); } catch (error) { /* ignore */ }
    }
  }
  return report;
}
