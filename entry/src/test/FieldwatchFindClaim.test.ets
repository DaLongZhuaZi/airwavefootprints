import { describe, it, expect } from '@ohos/hypium';
import {
  claimKeyOf, currentApCandidate, FindClaimCandidate, FindClaimSource, isAlreadyClaimed,
  ownDeviceFromCandidate, pairedAddressStable, pairedCandidates, scanCandidates
} from '../main/ets/fieldwatch/domain/FieldwatchFindClaim';
import { RadioFacts } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { OwnDevice } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';
import { RadioKind, ScanObservation } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { PairedDeviceInfo, PairedProfileKind } from '../main/ets/fieldwatch/radio/FieldwatchPairedDevices';
import { WifiCurrentAp } from '../main/ets/fieldwatch/radio/FieldwatchWifiLink';

function paired(address: string, name: string, connected: boolean, category: SignatureClass): PairedDeviceInfo {
  const info: PairedDeviceInfo = new PairedDeviceInfo();
  info.virtualAddress = address;
  info.name = name;
  info.connected = connected;
  info.category = category;
  if (connected) info.profiles = [PairedProfileKind.AUDIO];
  return info;
}

/** 造一条实时观测（用于扫描认领路径）。 */
const NOW: number = 1700000000000;
function sighting(kind: RadioKind, address: string, name: string, rssi: number): Sighting {
  return sightingWithFacts(kind, address, name, rssi, new RadioFacts());
}

function sightingWithFacts(kind: RadioKind, address: string, name: string, rssi: number, facts: RadioFacts): Sighting {
  const prefix: string = kind === RadioKind.WIFI ? 'wifi:' : (kind === RadioKind.NEARLINK ? 'nearlink:' : 'ble:');
  const observation: ScanObservation = new ScanObservation(prefix + address, kind, address, name, rssi, NOW, facts);
  const item: Sighting = Sighting.fromObservation(observation);
  item.rssiDisplay = rssi;
  return item;
}

function claimedDevice(address: string, name: string, kind: RadioKind): OwnDevice {
  const device: OwnDevice = new OwnDevice();
  device.id = 'own-' + address;
  device.displayName = name;
  device.kind = kind;
  device.virtualAddress = address;
  return device;
}

export default function fieldwatchFindClaimTest() {
  describe('FieldwatchFindClaim', () => {
    it('builds observation keys exactly like the scanners do', 0, () => {
      // 与三个扫描器逐字一致：拼错一个字符，寻找会话就会「一直等信号」。
      expect(claimKeyOf(RadioKind.BLE, 'AA:BB:CC:DD:EE:FF')).assertEqual('ble:AA:BB:CC:DD:EE:FF');
      expect(claimKeyOf(RadioKind.WIFI, 'AA:BB:CC:DD:EE:01')).assertEqual('wifi:AA:BB:CC:DD:EE:01');
      expect(claimKeyOf(RadioKind.NEARLINK, '11:22:33:44:55:66')).assertEqual('nearlink:11:22:33:44:55:66');
    });

    it('turns the paired list into claimable candidates', 0, () => {
      const devices: PairedDeviceInfo[] = [
        paired('AA:BB:CC:00:00:01', 'B 音箱', false, SignatureClass.AUDIO),
        paired('AA:BB:CC:00:00:02', 'A 耳机', true, SignatureClass.AUDIO)
      ];
      const candidates: FindClaimCandidate[] = pairedCandidates(devices, []);
      expect(candidates.length).assertEqual(2);
      // 网关已把「正在连着」的排最前，这里保持同样顺序。
      expect(candidates[0].title).assertEqual('B 音箱');
      expect(candidates[0].subtitle).assertEqual('paired');
      expect(candidates[1].subtitle).assertEqual('connected');
      expect(candidates[1].connected).assertTrue();
      expect(candidates[0].key).assertEqual('ble:AA:BB:CC:00:00:01');
      // 蓝牙：V1 已真机证实「配对地址 == 扫描 deviceId」→ 地址可当锚，不再提示「稳定性未确认」。
      expect(candidates[0].addressStable).assertTrue();
      expect(pairedAddressStable(RadioKind.BLE)).assertTrue();
      // 星闪与 Wi-Fi 仍是未知/不可用：一个没验证同源，一个被系统随机化。
      expect(pairedAddressStable(RadioKind.NEARLINK)).assertFalse();
      expect(pairedAddressStable(RadioKind.WIFI)).assertFalse();
    });

    it('marks already claimed devices so the list does not offer them twice', 0, () => {
      const devices: PairedDeviceInfo[] = [paired('AA:BB:CC:00:00:01', '我的耳机', false, SignatureClass.AUDIO)];
      const claimed: OwnDevice[] = [claimedDevice('AA:BB:CC:00:00:01', '我的耳机', RadioKind.BLE)];
      const candidates: FindClaimCandidate[] = pairedCandidates(devices, claimed);
      expect(candidates[0].alreadyClaimed).assertTrue();
    });

    it('does not confuse devices of different kinds that share an address', 0, () => {
      // 同一串地址在 BLE 与 Wi-Fi 是两码事：不能因为字符串相等就判成已认领。
      const candidate: FindClaimCandidate = new FindClaimCandidate();
      candidate.kind = RadioKind.BLE;
      candidate.address = 'AA:BB:CC:00:00:01';
      candidate.title = '我的音箱';
      const wifiDevice: OwnDevice = claimedDevice('AA:BB:CC:00:00:01', '客厅-5G', RadioKind.WIFI);
      expect(isAlreadyClaimed(candidate, [wifiDevice])).assertFalse();
    });

    it('matches a claimed Wi-Fi target by SSID because bssid is randomized', 0, () => {
      // V6-b：拿不到 GET_WIFI_PEERS_MAC 时 bssid 每次都可能不同，
      // 所以 Wi-Fi 的「已认领」只能按 SSID 判。
      const ap: WifiCurrentAp = new WifiCurrentAp();
      ap.ssid = '客厅-5G';
      ap.bssid = 'RANDOMIZED-EACH-CALL';
      const claimed: OwnDevice[] = [claimedDevice('另一个随机值', '客厅-5G', RadioKind.WIFI)];
      const candidate: FindClaimCandidate | undefined = currentApCandidate(ap, claimed);
      expect(candidate !== undefined).assertTrue();
      if (candidate !== undefined) {
        expect(candidate.source).assertEqual(FindClaimSource.CURRENT_AP);
        expect(candidate.category).assertEqual(SignatureClass.ROUTER);
        expect(candidate.alreadyClaimed).assertTrue();
        expect(candidate.addressStable).assertFalse();
      }
    });

    it('builds a near link candidate with its own key prefix and native class', 0, () => {
      // 落地点四的同构要求：星闪走与蓝牙同一条认领路径，只有 key 前缀与类别来源不同。
      const info: PairedDeviceInfo = new PairedDeviceInfo();
      info.kind = RadioKind.NEARLINK;
      info.virtualAddress = '11:22:33:44:55:66';
      info.name = '星闪耳机';
      info.nearLinkDeviceClass = 0x000801;
      info.category = SignatureClass.AUDIO;
      const candidates: FindClaimCandidate[] = pairedCandidates([info], []);
      expect(candidates.length).assertEqual(1);
      expect(candidates[0].key).assertEqual('nearlink:11:22:33:44:55:66');
      expect(candidates[0].kind).assertEqual(RadioKind.NEARLINK);
      expect(candidates[0].nearLinkDeviceClass).assertEqual(0x000801);
    });

    it('lists nearby named devices for claiming from the scan list', 0, () => {
      // 只列有名字的：一两百台设备里没名字的那些，用户认不出哪台是自己的。
      const unnamed: Sighting = sighting(RadioKind.BLE, 'AA:BB:CC:00:00:09', '', -30);
      const weak: Sighting = sighting(RadioKind.BLE, 'AA:BB:CC:00:00:02', '远处的耳机', -80);
      const strong: Sighting = sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '手边的耳机', -45);
      const wifi: Sighting = sighting(RadioKind.WIFI, 'AA:BB:CC:00:00:03', '邻居的网', -40);
      const nearLink: Sighting = sighting(RadioKind.NEARLINK, 'AA:BB:CC:00:00:04', '星闪耳机', -50);
      const candidates: FindClaimCandidate[] = scanCandidates([unnamed, weak, strong, wifi, nearLink], [], 10,
        (ids: string[]): SignatureClass => ids.length > 0 ? SignatureClass.AUDIO : SignatureClass.OTHER);
      // 没名字的被滤掉、Wi-Fi 不在此列（它走捷径卡），剩下蓝牙与星闪。
      expect(candidates.length).assertEqual(3);
      // 按强度排序：手边的（-45）在远处的（-80）前面。
      expect(candidates[0].title).assertEqual('手边的耳机');
      expect(candidates[1].title).assertEqual('星闪耳机');
      expect(candidates[2].title).assertEqual('远处的耳机');
      expect(candidates[0].kind).assertEqual(RadioKind.BLE);
      expect(candidates[1].kind).assertEqual(RadioKind.NEARLINK);
      expect(candidates[1].key).assertEqual('nearlink:AA:BB:CC:00:00:04');
      // 扫描来的地址不作长期锚（星闪没验证同源；蓝牙随机地址也可能轮换）。
      expect(candidates[0].addressStable).assertFalse();
      expect(candidates[0].source).assertEqual(FindClaimSource.SCAN);
    });

    it('carries the broadcast fingerprint captured at claim time', 0, () => {
      // 文档落地点五要的「认领那一刻的指纹快照」——扫描路径能当场拿到。
      const facts: RadioFacts = new RadioFacts();
      facts.manufacturerDataHex = 'AABB';
      facts.serviceUuids = ['fd6f'];
      const item: Sighting = sightingWithFacts(RadioKind.BLE, 'AA:BB:CC:00:00:07', '我的耳机', -55, facts);
      item.signatureIds = ['govee'];
      const candidates: FindClaimCandidate[] = scanCandidates([item], [], 5,
        (ids: string[]): SignatureClass => SignatureClass.AUDIO);
      const device: OwnDevice = ownDeviceFromCandidate(candidates[0], NOW);
      expect(device.fingerprint.name).assertEqual('我的耳机');
      expect(device.fingerprint.manufacturerDataHex).assertEqual('AABB');
      expect(device.fingerprint.serviceUuids.length).assertEqual(1);
      expect(device.fingerprint.signatureIds[0]).assertEqual('govee');
      expect(device.category).assertEqual(SignatureClass.AUDIO);
    });

    it('skips devices that are already claimed and respects the limit', 0, () => {
      const mine: OwnDevice = claimedDevice('AA:BB:CC:00:00:01', '我的耳机', RadioKind.BLE);
      const items: Sighting[] = [
        sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', -40),
        sighting(RadioKind.BLE, 'AA:BB:CC:00:00:02', '别人的耳机', -50),
        sighting(RadioKind.BLE, 'AA:BB:CC:00:00:03', '第三台', -60)
      ];
      const candidates: FindClaimCandidate[] = scanCandidates(items, [mine], 2,
        (ids: string[]): SignatureClass => SignatureClass.OTHER);
      expect(candidates.length).assertEqual(2);
      expect(candidates[0].title).assertEqual('我的耳机');
      expect(candidates[0].alreadyClaimed).assertTrue();
      expect(candidates[1].alreadyClaimed).assertFalse();
    });

    it('hides the shortcut card when not connected to Wi-Fi', 0, () => {
      expect(currentApCandidate(undefined, []) === undefined).assertTrue();
      const empty: WifiCurrentAp = new WifiCurrentAp();
      expect(currentApCandidate(empty, []) === undefined).assertTrue();
    });

    it('builds a stable archive entry from a candidate', 0, () => {
      const candidate: FindClaimCandidate = new FindClaimCandidate();
      candidate.source = FindClaimSource.PAIRED;
      candidate.kind = RadioKind.BLE;
      candidate.address = 'AA:BB:CC:00:00:02';
      candidate.title = '我的耳机';
      candidate.category = SignatureClass.AUDIO;
      candidate.connected = true;
      const device: OwnDevice = ownDeviceFromCandidate(candidate, 1700000000000);
      expect(device.displayName).assertEqual('我的耳机');
      expect(device.virtualAddress).assertEqual('AA:BB:CC:00:00:02');
      expect(device.category).assertEqual(SignatureClass.AUDIO);
      expect(device.createdAt).assertEqual(1700000000000);
      expect(device.claimSource).assertEqual('paired');
      // 指纹留空：系统配对名不是广播名，不能用它冒充指纹（那会污染匹配）。
      expect(device.fingerprint.name).assertEqual('');
      // 同一台设备重复认领要覆盖同一条，而不是堆出多条。
      const again: OwnDevice = ownDeviceFromCandidate(candidate, 1700000009999);
      expect(again.id).assertEqual(device.id);
    });
  });
}
