import { describe, it, expect } from '@ohos/hypium';
import { Permissions } from '@kit.AbilityKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { IFieldwatchWifiPermissionChecker, IFieldwatchWifiPlatform, FieldwatchWifiScanner } from '../main/ets/fieldwatch/radio/FieldwatchWifiScanner';
import { WifiScanPhase } from '../main/ets/fieldwatch/domain/FieldwatchModels';

class FakeWifiPlatform implements IFieldwatchWifiPlatform {
  public active: boolean = true;
  public location: boolean = true;
  public startCount: number = 0;
  public subscribeCount: number = 0;
  public unsubscribeCount: number = 0;
  public throwOnStart: boolean = false;
  public results: Array<wifiManager.WifiScanInfo> = [];
  private callback: ((state: number) => void) | undefined;
  isWifiActive(): boolean { return this.active; }
  isLocationEnabled(): boolean { return this.location; }
  startScan(): void { this.startCount += 1; if (this.throwOnStart) throw new Error('scan rejected'); }
  getScanInfoList(): Array<wifiManager.WifiScanInfo> { return this.results; }
  onScanStateChange(callback: (state: number) => void): void { this.subscribeCount += 1; this.callback = callback; }
  offScanStateChange(callback: (state: number) => void): void { this.unsubscribeCount += 1; if (this.callback === callback) this.callback = undefined; }
  emit(state: number): void { if (this.callback !== undefined) this.callback(state); }
}

class AllowWifiPermission implements IFieldwatchWifiPermissionChecker {
  public allowed: boolean = true;
  check(permission: Permissions): boolean { return this.allowed; }
}

class DenyWifiPermission implements IFieldwatchWifiPermissionChecker {
  check(permission: Permissions): boolean { return false; }
}

export default function fieldwatchWifiScannerTest() {
  describe('FieldwatchWifiScanner', () => {
    it('classifies location disabled without requesting scan', 0, () => {
      const platform: FakeWifiPlatform = new FakeWifiPlatform();
      platform.location = false;
      const scanner: FieldwatchWifiScanner = new FieldwatchWifiScanner(platform, new AllowWifiPermission(), 30000);
      scanner.start((): void => {}, (): void => {});
      expect(scanner.getSnapshot().phase).assertEqual(WifiScanPhase.LOCATION_DISABLED);
      expect(platform.startCount).assertEqual(0);
      scanner.stop();
    });

    it('allows only one active request and accepts success callback', 0, () => {
      const platform: FakeWifiPlatform = new FakeWifiPlatform();
      const scanner: FieldwatchWifiScanner = new FieldwatchWifiScanner(platform, new AllowWifiPermission(), 30000);
      let observations: number = 0;
      scanner.start((): void => { observations += 1; }, (): void => {});
      scanner.start((): void => { observations += 1; }, (): void => {});
      expect(platform.startCount).assertEqual(1);
      platform.emit(1);
      expect(scanner.getSnapshot().phase).assertEqual(WifiScanPhase.READY);
      expect(observations).assertEqual(0);
      scanner.stop();
    });

    it('enters retry window on system rejection', 0, () => {
      const platform: FakeWifiPlatform = new FakeWifiPlatform();
      const scanner: FieldwatchWifiScanner = new FieldwatchWifiScanner(platform, new AllowWifiPermission(), 30000);
      scanner.start((): void => {}, (): void => {});
      platform.emit(0);
      expect(scanner.getSnapshot().phase).assertEqual(WifiScanPhase.WAITING_FOR_RETRY);
      expect(scanner.getSnapshot().nextAttemptAt > Date.now()).assertTrue();
      scanner.stop();
    });

    it('classifies permission and Wi-Fi disabled before system request', 0, () => {
      const deniedPlatform: FakeWifiPlatform = new FakeWifiPlatform();
      const denied: FieldwatchWifiScanner = new FieldwatchWifiScanner(deniedPlatform, new DenyWifiPermission(), 30000);
      denied.start((): void => {}, (): void => {});
      expect(denied.getSnapshot().phase).assertEqual(WifiScanPhase.PERMISSION_DENIED);
      expect(deniedPlatform.startCount).assertEqual(0);
      denied.stop();

      const disabledPlatform: FakeWifiPlatform = new FakeWifiPlatform();
      disabledPlatform.active = false;
      const disabled: FieldwatchWifiScanner = new FieldwatchWifiScanner(disabledPlatform, new AllowWifiPermission(), 30000);
      disabled.start((): void => {}, (): void => {});
      expect(disabled.getSnapshot().phase).assertEqual(WifiScanPhase.WIFI_DISABLED);
      expect(disabledPlatform.startCount).assertEqual(0);
      disabled.stop();
    });

    it('keeps one subscription and detaches callbacks on stop', 0, () => {
      const platform: FakeWifiPlatform = new FakeWifiPlatform();
      const scanner: FieldwatchWifiScanner = new FieldwatchWifiScanner(platform, new AllowWifiPermission(), 30000);
      let observations: number = 0;
      scanner.start((): void => { observations += 1; }, (): void => {});
      scanner.start((): void => { observations += 1; }, (): void => {});
      expect(platform.subscribeCount).assertEqual(1);
      scanner.stop();
      expect(platform.unsubscribeCount).assertEqual(1);
      platform.emit(1);
      expect(observations).assertEqual(0);
    });

    it('backs off failures on the exact 8/16/32/45 second ladder', 0, () => {
      // 原版契约：连续失败按 min(45s, 8s * 2^(n-1)) 退避。
      expect(FieldwatchWifiScanner.backoffDelayFor(1)).assertEqual(8000);
      expect(FieldwatchWifiScanner.backoffDelayFor(2)).assertEqual(16000);
      expect(FieldwatchWifiScanner.backoffDelayFor(3)).assertEqual(32000);
      // 第 4 次理论值 64000，被 45 秒上限截断
      expect(FieldwatchWifiScanner.backoffDelayFor(4)).assertEqual(45000);
    });

    it('keeps the backoff pinned at the 45 second cap', 0, () => {
      expect(FieldwatchWifiScanner.backoffDelayFor(5)).assertEqual(45000);
      expect(FieldwatchWifiScanner.backoffDelayFor(6)).assertEqual(45000);
      // 无论失败多少次都不允许超过上限，否则系统节流下会彻底静默。
      expect(FieldwatchWifiScanner.backoffDelayFor(40)).assertEqual(45000);
      expect(FieldwatchWifiScanner.BACKOFF_CAP_MS).assertEqual(45000);
    });

    it('never returns a delay below the base, even for a zero count', 0, () => {
      // failureCount 为 0 是「还没有失败」；返回基数而不是 0，
      // 避免调用方拿到 0 之后立刻重试、把系统节流打成死循环。
      expect(FieldwatchWifiScanner.backoffDelayFor(0)).assertEqual(8000);
      expect(FieldwatchWifiScanner.backoffDelayFor(-3)).assertEqual(8000);
    });

    it('backs off a thrown request and retryNow clears the window', 0, () => {
      const platform: FakeWifiPlatform = new FakeWifiPlatform();
      platform.throwOnStart = true;
      const scanner: FieldwatchWifiScanner = new FieldwatchWifiScanner(platform, new AllowWifiPermission(), 30000);
      scanner.start((): void => {}, (): void => {});
      expect(scanner.getSnapshot().nextAttemptAt > Date.now()).assertTrue();
      platform.throwOnStart = false;
      scanner.retryNow();
      expect(platform.startCount).assertEqual(2);
      scanner.stop();
    });
  });
}
