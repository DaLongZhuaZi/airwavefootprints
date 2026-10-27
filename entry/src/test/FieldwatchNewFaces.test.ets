import { describe, it, expect } from '@ohos/hypium';
import {
  baselineUsable, NEW_FACE_LIMIT, NEW_FACE_MIN_HITS, NEW_FACE_MIN_RSSI, NewFaceEntry, newFacesOf
} from '../main/ets/fieldwatch/domain/FieldwatchNewFaces';
import { RadioFacts, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';

function sightingOf(key: string, rssi: number, count: number): Sighting {
  const observation: ScanObservation = new ScanObservation(key, RadioKind.BLE, key, 'dev', rssi, 1000, new RadioFacts());
  const sighting: Sighting = Sighting.fromObservation(observation);
  sighting.count = count;
  sighting.rssi = rssi;
  return sighting;
}

function noNames(sighting: Sighting): string { return ''; }

export default function fieldwatchNewFacesTest() {
  describe('FieldwatchNewFaces', () => {
    // 三个条件缺一不可：从未见过 + 信号较强 + 持续出现。
    it('requires unseen, strong enough, and repeated', 0, () => {
      const list: Sighting[] = [
        sightingOf('ble:good', -60, NEW_FACE_MIN_HITS),
        sightingOf('ble:weak', NEW_FACE_MIN_RSSI - 1, 10),
        sightingOf('ble:once', -50, NEW_FACE_MIN_HITS - 1),
        sightingOf('ble:known', -50, 10)
      ];
      const entries: NewFaceEntry[] = newFacesOf(list, ['ble:known'], [], noNames);
      expect(entries.length).assertEqual(1);
      expect(entries[0].deviceKey).assertEqual('ble:good');
    });

    // 未测量的 RSSI（127 这个哨兵）绝不能被当成「很强」。
    it('never treats the unmeasured sentinel as a strong signal', 0, () => {
      const list: Sighting[] = [sightingOf('ble:sentinel', 127, 10)];
      expect(newFacesOf(list, [], [], noNames).length).assertEqual(0);
    });

    // 「这是我家的」移出的设备不再出现。
    it('honours the manual exclusion list', 0, () => {
      const list: Sighting[] = [sightingOf('ble:home', -50, 10)];
      expect(newFacesOf(list, [], [], noNames).length).assertEqual(1);
      expect(newFacesOf(list, [], ['ble:home'], noNames).length).assertEqual(0);
    });

    it('sorts by persistence then by signal strength', 0, () => {
      const list: Sighting[] = [
        sightingOf('ble:a', -50, 5),
        sightingOf('ble:b', -50, 20),
        sightingOf('ble:c', -70, 20)
      ];
      const entries: NewFaceEntry[] = newFacesOf(list, [], [], noNames);
      expect(entries[0].deviceKey).assertEqual('ble:b');
      expect(entries[1].deviceKey).assertEqual('ble:c');
      expect(entries[2].deviceKey).assertEqual('ble:a');
    });

    it('caps the list so it cannot flood the page', 0, () => {
      const list: Sighting[] = [];
      for (let i: number = 0; i < NEW_FACE_LIMIT + 10; i += 1) {
        list.push(sightingOf('ble:' + i.toString(), -50, 5));
      }
      expect(newFacesOf(list, [], [], noNames).length).assertEqual(NEW_FACE_LIMIT);
    });

    // 空基线不能当「全是新面孔」：刚装完打开就会被几十条淹没。
    it('refuses to run against an empty baseline', 0, () => {
      expect(baselineUsable([])).assertFalse();
      expect(baselineUsable(['ble:x'])).assertTrue();
    });
  });
}
