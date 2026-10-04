import { ScanObservation, ScanState } from '../domain/FieldwatchModels';

export interface IFieldwatchRadioScanner {
  readonly state: ScanState;
  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void): void;
  stop(): void;
}

export class FieldwatchSimulatedScanner implements IFieldwatchRadioScanner {
  public state: ScanState = ScanState.IDLE;
  private observationHandler: ((observation: ScanObservation) => void) | undefined;
  private errorHandler: ((message: string) => void) | undefined;

  start(onObservation: (observation: ScanObservation) => void, onError: (message: string) => void): void {
    this.observationHandler = onObservation;
    this.errorHandler = onError;
    this.state = ScanState.SCANNING;
  }

  stop(): void {
    this.state = ScanState.IDLE;
    this.observationHandler = undefined;
    this.errorHandler = undefined;
  }

  emit(observation: ScanObservation): void {
    if (this.state === ScanState.SCANNING && this.observationHandler !== undefined) this.observationHandler(observation);
  }

  fail(message: string): void {
    this.state = ScanState.ERROR;
    if (this.errorHandler !== undefined) this.errorHandler(message);
  }
}
