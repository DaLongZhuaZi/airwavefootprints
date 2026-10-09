import { RadioKind, RadioSourceSnapshot, ScanObservation, ScanState } from '../domain/FieldwatchModels';

export interface IFieldwatchRadioScanner {
  readonly state: ScanState;
  readonly kind: RadioKind;
  getSnapshot(): RadioSourceSnapshot;
  retryNow(): void;
  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void;
  stop(): void;
}

export class FieldwatchSimulatedScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  public readonly kind: RadioKind = RadioKind.BLE;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;
  private stateHandler: ((snapshot: RadioSourceSnapshot) => void) | undefined;

  getSnapshot(): RadioSourceSnapshot { return new RadioSourceSnapshot(this.kind, this.state); }
  retryNow(): void { this.state = ScanState.SCANNING; this.publishState(); }

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void {
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    this.stateHandler = onStateChange;
    this.state = ScanState.SCANNING;
    this.publishState();
  }

  stop(): void {
    this.state = ScanState.IDLE;
    this.observationHandler = undefined;
    this.errorHandler = undefined;
    this.stateHandler = undefined;
    this.publishState();
  }

  emit(observation: ScanObservation): void {
    if (this.state === ScanState.SCANNING && this.observationHandler !== undefined) this.observationHandler(observation);
  }

  fail(message: string): void {
    this.state = ScanState.ERROR;
    this.publishState(message);
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }

  private publishState(message: string = ''): void {
    if (this.stateHandler !== undefined) this.stateHandler(new RadioSourceSnapshot(this.kind, this.state, 0, 0, false, 0, message));
  }
}
