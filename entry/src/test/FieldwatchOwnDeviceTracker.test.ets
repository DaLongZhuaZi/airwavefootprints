import { describe, it, expect } from '@ohos/hypium';
import {
  OWN_DEVICE_STAMP_MIN_GAP_MS, OwnDeviceStamp, ownDeviceIdForAddress, ownDevicesToStamp
} from '../main/ets/fieldwatch/domain/FieldwatchOwnDeviceTracker';
import { OwnDevice } from '../main/ets/fieldwatch/domain/FieldwatchOwnDevice';
import { GpsSample, RadioFacts, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';

function device(id: string, kind: RadioKind, address: string, name: string, lastSeenAt: number): OwnDevice {
  const entry: OwnDevice = new OwnDevice();
  entry.id = id;
  entry.kind = kind;
  entry.virtualAddress = address;
  entry.displayName = name;
  entry.category = SignatureClass.AUDIO;
  entry.lastSeenAt = lastSeenAt;
  return entry;
}

function sighting(kind: RadioKind, address: string, name: string, lastSeen: number): Sighting {
  const facts: RadioFacts = new RadioFacts();
  const observation: ScanObservation = new ScanObservation(
    (kind === RadioKind.WIFI ? 'wifi:' : (kind === RadioKind.NEARLINK ? 'nearlink:' : 'ble:')) + address,
    kind, address, name, -55, lastSeen, facts);
  const item: Sighting = Sighting.fromObservation(observation);
  item.lastSeen = lastSeen;
  return item;
}

const NOW: number = 1000000;

export default function fieldwatchOwnDeviceTrackerTest() {
  describe('FieldwatchOwnDeviceTracker', () => {
    it('stamps a claimed device when its address is observed', 0, () => {
      const mine: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', 0);
      const stamps: OwnDeviceStamp[] = ownDevicesToStamp([mine], [sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW - 1000)], NOW);
      expect(stamps.length).assertEqual(1);
      expect(stamps[0].deviceId).assertEqual('a');
      expect(stamps[0].seenAt).assertEqual(NOW - 1000);
    });

    it('carries the location of the observation', 0, () => {
      const mine: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', 0);
      const hit: Sighting = sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW - 500);
      hit.location = new GpsSample(31.23, 121.47, NOW - 500);
      const stamps: OwnDeviceStamp[] = ownDevicesToStamp([mine], [hit], NOW);
      expect(stamps.length).assertEqual(1);
      expect(stamps[0].location !== undefined).assertTrue();
    });

    it('never moves last seen backwards', 0, () => {
      // 乱序到达的旧观测不能让「上次见到」倒退。
      const mine: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', NOW - 100);
      const stamps: OwnDeviceStamp[] = ownDevicesToStamp(
        [mine], [sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW - 5000)], NOW);
      expect(stamps.length).assertEqual(0);
    });

    it('throttles writes for an archive that was just stamped', 0, () => {
      const fresh: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', NOW - 2000);
      // 刚写过（2 秒前）→ 不重复写。
      expect(ownDevicesToStamp([fresh], [sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW)], NOW).length).assertEqual(0);
      // 但已经过了节流窗口 → 写。
      const stale: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', NOW - OWN_DEVICE_STAMP_MIN_GAP_MS - 1);
      expect(ownDevicesToStamp([stale], [sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW)], NOW).length).assertEqual(1);
    });

    it('matches Wi-Fi by address or name', 0, () => {
      const router: OwnDevice = device('r', RadioKind.WIFI, 'different-bssid', 'DLZZ_5G', 0);
      // ① 地址变了但名字对得上 → 算见到（跨会话 bssid 可能被换掉）。
      expect(ownDevicesToStamp([router], [sighting(RadioKind.WIFI, 'yet-another-bssid', 'DLZZ_5G', NOW)], NOW).length).assertEqual(1);
      // ② 名字读不到、但地址一致 → 也算见到（真机实测：会话内 bssid 稳定）。
      const byAddress: OwnDevice = device('r2', RadioKind.WIFI, 'stable-bssid', '', 0);
      expect(ownDevicesToStamp([byAddress], [sighting(RadioKind.WIFI, 'stable-bssid', '', NOW)], NOW).length).assertEqual(1);
      // ③ 两者都不符 → 不算见到（同名网络不能乱认）。
      expect(ownDevicesToStamp([router], [sighting(RadioKind.WIFI, 'x', '邻居的网', NOW)], NOW).length).assertEqual(0);
    });

    it('ignores devices of a different radio kind', 0, () => {
      // 同一串地址在 BLE 与 Wi-Fi 是两码事，不能互相认。
      const ble: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', 0);
      expect(ownDevicesToStamp([ble], [sighting(RadioKind.NEARLINK, 'AA:BB:CC:00:00:01', '', NOW)], NOW).length).assertEqual(0);
    });

    it('finds an archive by address for connection events', 0, () => {
      const mine: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', 0);
      const other: OwnDevice = device('b', RadioKind.WIFI, 'AA:BB:CC:00:00:01', '同名地址的网', 0);
      // 连接事件只给地址：命中蓝牙那条。
      expect(ownDeviceIdForAddress([mine, other], RadioKind.BLE, 'AA:BB:CC:00:00:01')).assertEqual('a');
      // 同一串地址在 Wi-Fi 是另一码事。
      expect(ownDeviceIdForAddress([mine, other], RadioKind.WIFI, 'AA:BB:CC:00:00:01')).assertEqual('b');
      expect(ownDeviceIdForAddress([mine], RadioKind.NEARLINK, 'AA:BB:CC:00:00:01')).assertEqual('');
      // 空地址不能把任何档案「认」出来。
      expect(ownDeviceIdForAddress([mine], RadioKind.BLE, '')).assertEqual('');
      expect(ownDeviceIdForAddress([mine], RadioKind.BLE, 'ZZ:ZZ')).assertEqual('');
    });

    it('takes the newest observation when several match', 0, () => {
      const mine: OwnDevice = device('a', RadioKind.BLE, 'AA:BB:CC:00:00:01', '我的耳机', 0);
      const stamps: OwnDeviceStamp[] = ownDevicesToStamp([mine], [
        sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW - 8000),
        sighting(RadioKind.BLE, 'AA:BB:CC:00:00:01', '', NOW - 200)
      ], NOW);
      expect(stamps[0].seenAt).assertEqual(NOW - 200);
    });
  });
}
