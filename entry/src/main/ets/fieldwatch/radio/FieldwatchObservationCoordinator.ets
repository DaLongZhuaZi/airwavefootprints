import { logger } from 'ngf_framework';
import { RadioKind, RadioSourceSnapshot, ScanObservation, ScanState } from '../domain/FieldwatchModels';
import { IFieldwatchRadioScanner } from './FieldwatchRadioScanner';

const TAG: string = 'FieldwatchObservationCoordinator';

/** Coordinates independent passive radio sources without coupling domain code to OS APIs. */
export class FieldwatchObservationCoordinator {
  private readonly scanners: Array<IFieldwatchRadioScanner>;
  private sourceStates: Map<RadioKind, ScanState> = new Map();
  private sourceSnapshots: Map<RadioKind, RadioSourceSnapshot> = new Map();
  private currentState: ScanState = ScanState.IDLE;

  constructor(scanners: Array<IFieldwatchRadioScanner>) {
    this.scanners = scanners;
    scanners.forEach((scanner: IFieldwatchRadioScanner): void => {
      this.sourceStates.set(scanner.kind, scanner.state);
      this.sourceSnapshots.set(scanner.kind, scanner.getSnapshot());
    });
  }

  get state(): ScanState {
    return this.currentState;
  }

  getSnapshot(kind: RadioKind): RadioSourceSnapshot {
    const snapshot: RadioSourceSnapshot | undefined = this.sourceSnapshots.get(kind);
    return snapshot === undefined ? new RadioSourceSnapshot(kind) : snapshot;
  }

  getSnapshots(): Array<RadioSourceSnapshot> {
    const snapshots: Array<RadioSourceSnapshot> = [];
    this.sourceSnapshots.forEach((snapshot: RadioSourceSnapshot): void => { snapshots.push(snapshot); });
    return snapshots;
  }

  retry(kind: RadioKind): void {
    this.scanners.forEach((scanner: IFieldwatchRadioScanner): void => {
      if (scanner.kind === kind) scanner.retryNow();
    });
  }

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string, kind: RadioKind) => void, onStateChange?: (snapshot: RadioSourceSnapshot) => void): void {
    this.currentState = ScanState.IDLE;
    const errors: Array<string> = [];
    this.scanners.forEach((scanner: IFieldwatchRadioScanner): void => {
      scanner.start(onObservation, (message: string): void => {
        this.sourceStates.set(scanner.kind, scanner.state);
        this.sourceSnapshots.set(scanner.kind, scanner.getSnapshot());
        errors.push(message);
        onError(message, scanner.kind);
        this.refreshState();
      }, (snapshot: RadioSourceSnapshot): void => {
        this.sourceStates.set(scanner.kind, scanner.state);
        this.sourceSnapshots.set(scanner.kind, snapshot);
        if (onStateChange !== undefined) onStateChange(snapshot);
        this.refreshState();
      });
      this.sourceStates.set(scanner.kind, scanner.state);
      this.sourceSnapshots.set(scanner.kind, scanner.getSnapshot());
    });
    this.refreshState();
    if (errors.length > 0) {
      logger.warn(TAG, '所有无线电源均不可用');
    }
  }

  stop(): void {
    this.scanners.forEach((scanner: IFieldwatchRadioScanner): void => {
      scanner.stop();
      this.sourceStates.set(scanner.kind, scanner.state);
      this.sourceSnapshots.set(scanner.kind, scanner.getSnapshot());
    });
    this.currentState = ScanState.IDLE;
  }

  private refreshState(): void {
    let scanning: boolean = false;
    let hasError: boolean = false;
    this.sourceStates.forEach((state: ScanState): void => {
      if (state === ScanState.SCANNING) {
        scanning = true;
      }
      if (state === ScanState.ERROR) {
        hasError = true;
      }
    });
    this.currentState = scanning ? ScanState.SCANNING : hasError ? ScanState.ERROR : ScanState.IDLE;
  }
}
