import { describe, it, expect } from '@ohos/hypium';
import {
  candidateTargets, intToIpv4, ipv4ToInt, isPrivateIpv4, scopeFromLocal, SubnetSource, targetVerdict, TargetVerdict
} from '../main/ets/fieldwatch/domain/FieldwatchAclScope';
import { LocalNetworkInfo } from '../main/ets/fieldwatch/platform/FieldwatchAclTransport';

function netInfo(ip: string, prefix: number, gateway: string, fromLink: boolean): LocalNetworkInfo {
  const info: LocalNetworkInfo = new LocalNetworkInfo();
  info.ip = ip;
  info.prefixLength = prefix;
  info.gateway = gateway;
  info.fromLinkAddresses = fromLink;
  return info;
}

export default function fieldwatchAclScopeTest() {
  describe('FieldwatchAclScope', () => {
    it('converts IPv4 both ways', 0, () => {
      expect(ipv4ToInt('192.168.5.125')).assertEqual(3232236925);
      expect(intToIpv4(3232236925)).assertEqual('192.168.5.125');
      expect(ipv4ToInt('0.0.0.0')).assertEqual(0);
      expect(ipv4ToInt('bad')).assertEqual(0);
      expect(ipv4ToInt('256.1.1.1')).assertEqual(0);
    });

    // 只认 RFC1918 + 链路本地；公网一律 false。
    it('recognises private addresses only', 0, () => {
      expect(isPrivateIpv4('10.0.0.1')).assertTrue();
      expect(isPrivateIpv4('172.16.0.1')).assertTrue();
      expect(isPrivateIpv4('172.31.255.254')).assertTrue();
      expect(isPrivateIpv4('192.168.1.1')).assertTrue();
      expect(isPrivateIpv4('169.254.1.1')).assertTrue();
      // 公网与边界。
      expect(isPrivateIpv4('8.8.8.8')).assertFalse();
      expect(isPrivateIpv4('172.32.0.1')).assertFalse();
      expect(isPrivateIpv4('172.15.0.1')).assertFalse();
      expect(isPrivateIpv4('1.1.1.1')).assertFalse();
    });

    // **降级方案 (b)：推导失败就拒绝执行，不静默猜网段。**
    it('refuses to scan when the prefix length is not authoritative', 0, () => {
      const guessed: LocalNetworkInfo = netInfo('192.168.5.125', 24, '192.168.5.1', false);
      const scope = scopeFromLocal(guessed);
      expect(scope.usable).assertFalse();
      expect(scope.source).assertEqual(SubnetSource.UNKNOWN);
      // 不可用时不得生成任何候选目标。
      expect(candidateTargets(scope, 100).length).assertEqual(0);
    });

    it('builds a usable scope from authoritative link addresses', 0, () => {
      const info: LocalNetworkInfo = netInfo('192.168.5.125', 24, '192.168.5.1', true);
      const scope = scopeFromLocal(info);
      expect(scope.usable).assertTrue();
      expect(scope.source).assertEqual(SubnetSource.LINK_ADDRESSES);
      expect(scope.subnetText).assertEqual('192.168.5.0/24');
    });

    // 非私网本机地址（蜂窝/异常网络）同样不可用。
    it('refuses a non-private local address', 0, () => {
      const cellular: LocalNetworkInfo = netInfo('100.64.0.5', 24, '', true);
      expect(scopeFromLocal(cellular).usable).assertFalse();
      const publicIp: LocalNetworkInfo = netInfo('8.8.8.8', 24, '', true);
      expect(scopeFromLocal(publicIp).usable).assertFalse();
    });

    // 目标判定：本机、网关、公网、越界全部拒绝。
    it('rejects local, gateway, public and out-of-subnet targets', 0, () => {
      const scope = scopeFromLocal(netInfo('192.168.5.125', 24, '192.168.5.1', true));
      expect(targetVerdict(scope, '192.168.5.50')).assertEqual(TargetVerdict.ALLOWED);
      expect(targetVerdict(scope, '192.168.5.125')).assertEqual(TargetVerdict.LOCAL_ADDRESS);
      expect(targetVerdict(scope, '192.168.5.1')).assertEqual(TargetVerdict.GATEWAY);
      expect(targetVerdict(scope, '8.8.8.8')).assertEqual(TargetVerdict.PUBLIC_ADDRESS);
      expect(targetVerdict(scope, '10.0.0.5')).assertEqual(TargetVerdict.OUT_OF_SUBNET);
      expect(targetVerdict(scope, '192.168.6.5')).assertEqual(TargetVerdict.OUT_OF_SUBNET);
      expect(targetVerdict(scope, 'not-an-ip')).assertEqual(TargetVerdict.INVALID);
    });

    // 范围不可用时，任何目标都不放行。
    it('rejects every target when the scope is unknown', 0, () => {
      const scope = scopeFromLocal(netInfo('192.168.5.125', 24, '', false));
      expect(targetVerdict(scope, '192.168.5.50')).assertEqual(TargetVerdict.SCOPE_UNKNOWN);
      expect(targetVerdict(scope, '8.8.8.8')).assertEqual(TargetVerdict.SCOPE_UNKNOWN);
    });

    // 候选目标：排除网络/广播/本机/网关，且遵守上限。
    it('generates candidates excluding local and gateway', 0, () => {
      const scope = scopeFromLocal(netInfo('192.168.5.125', 24, '192.168.5.1', true));
      const targets: string[] = candidateTargets(scope, 300);
      // /24 可用主机 254，扣除本机与网关 = 252。
      expect(targets.length).assertEqual(252);
      expect(targets.indexOf('192.168.5.125') < 0).assertTrue();
      expect(targets.indexOf('192.168.5.1') < 0).assertTrue();
      expect(targets.indexOf('192.168.5.0') < 0).assertTrue();
      expect(targets.indexOf('192.168.5.255') < 0).assertTrue();
      expect(targets.indexOf('192.168.5.2') >= 0).assertTrue();
      // 上限生效。
      expect(candidateTargets(scope, 10).length).assertEqual(10);
    });

    // /16 这种大网段必须被上限截断，不能一次生成 6 万条。
    it('caps candidate generation for large subnets', 0, () => {
      const scope = scopeFromLocal(netInfo('10.1.2.3', 16, '10.1.0.1', true));
      expect(candidateTargets(scope, 500).length).assertEqual(500);
    });
  });
}
