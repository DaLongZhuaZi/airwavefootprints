import { describe, it, expect } from '@ohos/hypium';
import {
  FieldwatchPairedDevices, IFieldwatchPairedPlatform, PairedClassFacts, PairedDeviceInfo,
  PairedProfileKind, pairedCategoryOf
} from '../main/ets/fieldwatch/radio/FieldwatchPairedDevices';
import { RadioKind, SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { IFieldwatchNearLinkPairedPlatform } from '../main/ets/fieldwatch/radio/FieldwatchNearLinkPaired';

/** 一条假设备：地址 + 名称 + 两个类别字段。 */
class FakeDevice {
  public address: string;
  public name: string;
  public major: number;
  public minor: number;
  constructor(address: string, name: string, major: number, minor: number) {
    this.address = address;
    this.name = name;
    this.major = major;
    this.minor = minor;
  }
}

/** 星闪假平台：真实现会碰 SDK，测试必须注入假的（否则单测会去连真设备）。 */
class FakeNearLinkPlatform implements IFieldwatchNearLinkPairedPlatform {
  public supported: boolean = true;
  public devices: FakeNearLinkDevice[] = [];
  isSupported(): boolean { return this.supported; }
  getPairedDevices(): string[] {
    if (!this.supported) return [];
    const out: string[] = [];
    this.devices.forEach((device: FakeNearLinkDevice): void => { out.push(device.address); });
    return out;
  }
  getDeviceName(address: string): string {
    const found: FakeNearLinkDevice | undefined = this.devices.find((d: FakeNearLinkDevice): boolean => d.address === address);
    return found === undefined ? '' : found.name;
  }
  getDeviceClass(address: string): number {
    const found: FakeNearLinkDevice | undefined = this.devices.find((d: FakeNearLinkDevice): boolean => d.address === address);
    return found === undefined ? -1 : found.deviceClass;
  }
  isConnected(address: string): boolean {
    const found: FakeNearLinkDevice | undefined = this.devices.find((d: FakeNearLinkDevice): boolean => d.address === address);
    return found === undefined ? false : found.connected;
  }
}

class FakeNearLinkDevice {
  public address: string;
  public name: string;
  public deviceClass: number;
  public connected: boolean;
  constructor(address: string, name: string, deviceClass: number, connected: boolean) {
    this.address = address;
    this.name = name;
    this.deviceClass = deviceClass;
    this.connected = connected;
  }
}

/** 假平台：不碰系统，逐项可断言调用次数。 */
class FakePairedPlatform implements IFieldwatchPairedPlatform {
  public bluetoothOn: boolean = true;
  public devices: FakeDevice[] = [];
  /** 三个 Profile 面的已连接地址：下标 = PairedProfileKind。 */
  public connectedByKind: string[][] = [[], [], []];
  /** 这些地址在查名字时抛错（模拟遍历期间被取消配对）。 */
  public throwOnName: string[] = [];
  public listedCalls: number = 0;
  public subscribeCalls: number = 0;
  public unsubscribeCalls: number = 0;
  private callbacks: ((deviceId: string, connected: boolean) => void)[] = [];

  isBluetoothOn(): boolean { return this.bluetoothOn; }

  getPairedDevices(): string[] {
    this.listedCalls += 1;
    const out: string[] = [];
    this.devices.forEach((device: FakeDevice): void => { out.push(device.address); });
    return out;
  }

  getRemoteDeviceName(deviceId: string): string {
    if (this.throwOnName.includes(deviceId)) throw new Error('unpaired mid-iteration');
    const found: FakeDevice | undefined = this.devices.find((device: FakeDevice): boolean => device.address === deviceId);
    return found === undefined ? '' : found.name;
  }

  getRemoteDeviceClass(deviceId: string): PairedClassFacts {
    const facts: PairedClassFacts = new PairedClassFacts();
    const found: FakeDevice | undefined = this.devices.find((device: FakeDevice): boolean => device.address === deviceId);
    if (found !== undefined) {
      facts.majorClass = found.major;
      facts.minorClass = found.minor;
    }
    return facts;
  }

  getConnectedDevices(kind: PairedProfileKind): string[] { return this.connectedByKind[kind as number]; }

  onConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void {
    this.subscribeCalls += 1;
    this.callbacks.push(callback);
  }

  offConnectionStateChange(kind: PairedProfileKind, callback: (deviceId: string, connected: boolean) => void): void {
    this.unsubscribeCalls += 1;
  }

  /** 测试驱动：模拟一次连接状态变化。 */
  emit(deviceId: string, connected: boolean): void {
    this.callbacks.forEach((callback: (deviceId: string, connected: boolean) => void): void => callback(deviceId, connected));
  }
}

export default function fieldwatchPairedDevicesTest() {
  describe('FieldwatchPairedDevices', () => {
    it('maps device class to app category', 0, () => {
      // 耳机 / 音箱 / 可穿戴耳机都归 AUDIO，车载归 VEHICLE（找东西时是两种目标）。
      expect(pairedCategoryOf(0x0400, 0x0418)).assertEqual(SignatureClass.AUDIO);
      expect(pairedCategoryOf(0x0400, 0x0414)).assertEqual(SignatureClass.AUDIO);
      expect(pairedCategoryOf(0x0400, 0x0404)).assertEqual(SignatureClass.AUDIO);
      expect(pairedCategoryOf(0x0400, 0x0420)).assertEqual(SignatureClass.VEHICLE);
      expect(pairedCategoryOf(0x0700, 0x0704)).assertEqual(SignatureClass.WEARABLE);
      expect(pairedCategoryOf(0x0900, 0x0904)).assertEqual(SignatureClass.HEALTH);
      expect(pairedCategoryOf(0x0200, 0x0200)).assertEqual(SignatureClass.PHONE);
      expect(pairedCategoryOf(0x0600, 0x0600)).assertEqual(SignatureClass.CAMERA);
      // 外设（键盘）、计算机、未知主类都落 OTHER：宁可用通用图标，也不猜错类别。
      expect(pairedCategoryOf(0x0500, 0x0540)).assertEqual(SignatureClass.OTHER);
      expect(pairedCategoryOf(0x0100, 0x0100)).assertEqual(SignatureClass.OTHER);
      expect(pairedCategoryOf(0x1F00, 0x0000)).assertEqual(SignatureClass.OTHER);
    });

    it('lists paired devices with name and category', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      platform.devices = [new FakeDevice('AA:BB:CC:00:00:01', '客厅音箱', 0x0400, 0x0414)];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      const list: PairedDeviceInfo[] = gateway.list();
      expect(list.length).assertEqual(1);
      expect(list[0].name).assertEqual('客厅音箱');
      expect(list[0].virtualAddress).assertEqual('AA:BB:CC:00:00:01');
      expect(list[0].category).assertEqual(SignatureClass.AUDIO);
      expect(list[0].connected).assertFalse();
    });

    it('puts the connected device first', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      platform.devices = [
        new FakeDevice('AA:BB:CC:00:00:01', 'A 音箱', 0x0400, 0x0414),
        new FakeDevice('AA:BB:CC:00:00:02', 'B 耳机', 0x0400, 0x0418)
      ];
      // 耳机正连着（A2DP 面）：找东西时它应该排第一 —— 用户多半就是在找它。
      platform.connectedByKind[PairedProfileKind.AUDIO as number] = ['AA:BB:CC:00:00:02'];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      const list: PairedDeviceInfo[] = gateway.list();
      expect(list[0].virtualAddress).assertEqual('AA:BB:CC:00:00:02');
      expect(list[0].connected).assertTrue();
      expect(list[0].profiles.length).assertEqual(1);
      expect(list[1].connected).assertFalse();
    });

    it('keeps an unnamed device instead of dropping it', 0, () => {
      // 名称查不到（纯 BLE 配对设备、或查名抛错）时**不能把这条丢掉**：
      // 丢掉等于用户找不到自己的设备，UI 显示「未命名设备」并允许改名即可。
      const platform: FakePairedPlatform = new FakePairedPlatform();
      platform.devices = [
        new FakeDevice('AA:BB:CC:00:00:03', '', 0x0000, 0x0000),
        new FakeDevice('AA:BB:CC:00:00:04', '照旧', 0x0700, 0x0704)
      ];
      platform.throwOnName = ['AA:BB:CC:00:00:04'];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      const list: PairedDeviceInfo[] = gateway.list();
      expect(list.length).assertEqual(2);
    });

    it('returns nothing and does not query when bluetooth is off', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      platform.bluetoothOn = false;
      platform.devices = [new FakeDevice('AA:BB:CC:00:00:01', '耳机', 0x0400, 0x0418)];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      expect(gateway.list().length).assertEqual(0);
      expect(platform.listedCalls).assertEqual(0);
    });

    it('subscribes three profile faces and releases them', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      let seen: string = '';
      gateway.subscribe((deviceId: string, connected: boolean): void => {
        seen = deviceId + (connected ? ':on' : ':off');
      });
      expect(platform.subscribeCalls).assertEqual(3);
      platform.emit('AA:BB:CC:00:00:02', false);
      expect(seen).assertEqual('AA:BB:CC:00:00:02:off');
      gateway.unsubscribe();
      expect(platform.unsubscribeCalls).assertEqual(3);
      // 取消后不再回调：页面离开后还写 UI 状态会报「状态变量已释放」。
      platform.emit('AA:BB:CC:00:00:02', true);
      expect(seen).assertEqual('AA:BB:CC:00:00:02:off');
    });

    it('merges near link paired devices with their native class', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      const nearLink: FakeNearLinkPlatform = new FakeNearLinkPlatform();
      nearLink.devices = [new FakeNearLinkDevice('11:22:33:44:55:66', '星闪耳机', 0x000801, true)];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, nearLink);
      const list: PairedDeviceInfo[] = gateway.list();
      expect(list.length).assertEqual(1);
      expect(list[0].kind).assertEqual(RadioKind.NEARLINK);
      expect(list[0].name).assertEqual('星闪耳机');
      // 原生类别要原样带出去：UI 靠它分出鼠标/触控板/手写笔（比粗映射精确）。
      expect(list[0].nearLinkDeviceClass).assertEqual(0x000801);
      // 粗映射只用于档案图标：可穿戴音频 → AUDIO。
      expect(list[0].category).assertEqual(SignatureClass.AUDIO);
      expect(list[0].connected).assertTrue();
    });

    it('lists nothing from near link when the device does not support it', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      const nearLink: FakeNearLinkPlatform = new FakeNearLinkPlatform();
      nearLink.supported = false;
      nearLink.devices = [new FakeNearLinkDevice('11:22:33:44:55:66', '星闪耳机', 0x000801, false)];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, nearLink);
      expect(gateway.list().length).assertEqual(0);
    });

    it('reports whether an address is currently connected', 0, () => {
      const platform: FakePairedPlatform = new FakePairedPlatform();
      platform.connectedByKind[PairedProfileKind.HANDSFREE as number] = ['AA:BB:CC:00:00:09'];
      const gateway: FieldwatchPairedDevices = new FieldwatchPairedDevices(platform, new FakeNearLinkPlatform());
      expect(gateway.isConnected('AA:BB:CC:00:00:09')).assertTrue();
      expect(gateway.isConnected('AA:BB:CC:00:00:08')).assertFalse();
    });
  });
}
