import { describe, it, expect } from '@ohos/hypium';
import { RadioKind, RadioSourceSnapshot, ScanObservation, ScanState } from '../main/ets/fieldwatch/domain/FieldwatchModels';
import { FieldwatchObservationCoordinator } from '../main/ets/fieldwatch/radio/FieldwatchObservationCoordinator';
import { FieldwatchSimulatedScanner, IFieldwatchRadioScanner } from '../main/ets/fieldwatch/radio/FieldwatchRadioScanner';

class FailingScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  public readonly kind: RadioKind = RadioKind.WIFI;
  getSnapshot(): RadioSourceSnapshot { return new RadioSourceSnapshot(this.kind, this.state); }
  retryNow(): void {}

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void): void {
    this.state = ScanState.ERROR;
    onError('test scanner unavailable');
  }

  stop(): void {
    this.state = ScanState.IDLE;
  }
}

export default function fieldwatchRadioTest() {
  describe('FieldwatchRadio', () => {
    it('keeps BLE scanning when Wi-Fi source fails', 0, () => {
      const ble: FieldwatchSimulatedScanner = new FieldwatchSimulatedScanner();
      const coordinator: FieldwatchObservationCoordinator = new FieldwatchObservationCoordinator([
        ble,
        new FailingScanner()
      ]);
      let errors: number = 0;
      coordinator.start((): void => {}, (): void => { errors += 1; });
      expect(coordinator.state).assertEqual(ScanState.SCANNING);
      expect(errors).assertEqual(1);
      coordinator.stop();
      expect(coordinator.state).assertEqual(ScanState.IDLE);
    });

    it('forwards observations from a source', 0, () => {
      const scanner: FieldwatchSimulatedScanner = new FieldwatchSimulatedScanner();
      const coordinator: FieldwatchObservationCoordinator = new FieldwatchObservationCoordinator([scanner]);
      let received: number = 0;
      coordinator.start((): void => { received += 1; }, (): void => {});
      scanner.emit(new ScanObservation('ble:test', RadioKind.BLE, 'test', 'Test', -40, 1));
      expect(received).assertEqual(1);
    });
  });
}
