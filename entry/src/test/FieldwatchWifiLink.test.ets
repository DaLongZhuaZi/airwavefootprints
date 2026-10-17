import { describe, it, expect } from '@ohos/hypium';
import {
  FieldwatchWifiLink, IFieldwatchWifiLinkPlatform, WifiCurrentAp
} from '../main/ets/fieldwatch/radio/FieldwatchWifiLink';

class FakeWifiLinkPlatform implements IFieldwatchWifiLinkPlatform {
  public active: boolean = true;
  public ap: WifiCurrentAp = new WifiCurrentAp();
  public reads: number = 0;
  isWifiActive(): boolean { return this.active; }
  readLinkedInfo(): WifiCurrentAp { this.reads += 1; return this.ap; }
}

function ap(ssid: string, bssid: string): WifiCurrentAp {
  const item: WifiCurrentAp = new WifiCurrentAp();
  item.ssid = ssid;
  item.bssid = bssid;
  item.rssi = -42;
  item.band = 5180;
  return item;
}

export default function fieldwatchWifiLinkTest() {
  describe('FieldwatchWifiLink', () => {
    it('returns the current AP when connected', 0, () => {
      const platform: FakeWifiLinkPlatform = new FakeWifiLinkPlatform();
      platform.ap = ap('客厅-5G', 'AA:BB:CC:DD:EE:01');
      const link: FieldwatchWifiLink = new FieldwatchWifiLink(platform);
      const current: WifiCurrentAp | undefined = link.current();
      expect(current !== undefined).assertTrue();
      if (current !== undefined) {
        expect(current.ssid).assertEqual('客厅-5G');
        expect(current.rssi).assertEqual(-42);
        expect(current.band).assertEqual(5180);
        // 已核实：没有 GET_WIFI_PEERS_MAC 时系统返回随机 bssid，不能当长期锚。
        expect(current.bssidStable).assertFalse();
      }
    });

    it('returns undefined when Wi-Fi is off without reading', 0, () => {
      const platform: FakeWifiLinkPlatform = new FakeWifiLinkPlatform();
      platform.active = false;
      const link: FieldwatchWifiLink = new FieldwatchWifiLink(platform);
      expect(link.current() === undefined).assertTrue();
      expect(platform.reads).assertEqual(0);
    });

    it('treats an empty SSID as not available', 0, () => {
      // SSID 被系统置空时不能凭空名字做认领 —— 那会把用户带到认不出的目标上。
      const platform: FakeWifiLinkPlatform = new FakeWifiLinkPlatform();
      platform.ap = ap('', 'AA:BB:CC:DD:EE:01');
      const link: FieldwatchWifiLink = new FieldwatchWifiLink(platform);
      expect(link.current() === undefined).assertTrue();
    });
  });
}
