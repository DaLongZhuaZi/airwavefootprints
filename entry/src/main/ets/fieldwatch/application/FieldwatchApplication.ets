import { logger } from 'ngf_framework';
import { AppSettings, FilterDefinition, LogEntry, RadioFacts, RadioKind, ScanObservation, ScanState, SignatureClass, SignatureDefinition, Sighting, WatchTarget } from '../domain/FieldwatchModels';
import { FieldwatchFilterEngine, FieldwatchPrivacyService, FieldwatchSignatureEngine } from '../domain/FieldwatchDomainService';
import { FieldwatchSettingsRepository } from '../data/FieldwatchSettingsRepository';
import { FieldwatchBleScanner } from '../radio/FieldwatchBleScanner';
import { IFieldwatchRadioScanner } from '../radio/FieldwatchRadioScanner';

const TAG: string = 'FieldwatchApplication';

export class FieldwatchApplicationState {
  public scanState: ScanState = ScanState.IDLE;
  public errorMessage: string = '';
  public sightings: Sighting[] = [];
  public logs: LogEntry[] = [];
  public signatures: SignatureDefinition[] = [];
  public watchlist: WatchTarget[] = [];
  public filter: FilterDefinition = new FilterDefinition();
  public settings: AppSettings = new AppSettings();
}

export class FieldwatchApplication {
  private readonly state: FieldwatchApplicationState = new FieldwatchApplicationState();
  private readonly signatureEngine: FieldwatchSignatureEngine = new FieldwatchSignatureEngine();
  private readonly filterEngine: FieldwatchFilterEngine = new FieldwatchFilterEngine();
  private readonly privacyService: FieldwatchPrivacyService = new FieldwatchPrivacyService();
  private readonly settingsRepository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
  private readonly radioScanner: IFieldwatchRadioScanner = new FieldwatchBleScanner();
  private sequence: number = 0;

  constructor() { this.state.signatures = this.defaultSignatures(); this.state.settings = this.settingsRepository.load(); }
  getState(): FieldwatchApplicationState { return this.state; }

  startBleScan(): void {
    this.state.errorMessage = '';
    this.radioScanner.start((observation: ScanObservation): void => { this.ingest(observation); }, (message: string): void => {
      this.state.errorMessage = message;
      this.state.scanState = ScanState.ERROR;
    });
    this.state.scanState = this.radioScanner.state;
  }
  stopBleScan(): void { this.radioScanner.stop(); this.state.scanState = ScanState.IDLE; logger.info(TAG, 'BLE 扫描已停止'); }
  setDisplayPaused(paused: boolean): void { this.state.settings.displayPaused = paused; this.settingsRepository.save(this.state.settings); this.state.scanState = paused ? ScanState.PAUSED : ScanState.SCANNING; }
  filteredSightings(): Sighting[] { return this.state.sightings.filter((sighting: Sighting): boolean => this.filterEngine.pass(sighting, this.state.filter, this.state.signatures, this.state.watchlist)); }
  describe(sighting: Sighting): string { return this.privacyService.describe(sighting, this.state.settings); }

  toggleWatch(sighting: Sighting): void {
    const existing: WatchTarget | undefined = this.state.watchlist.find((target: WatchTarget): boolean => target.deviceKey === sighting.key);
    if (existing !== undefined) { this.state.watchlist = this.state.watchlist.filter((target: WatchTarget): boolean => target !== existing); return; }
    this.state.watchlist.push(new WatchTarget(sighting.key, '', sighting.name, true));
  }

  private ingest(observation: ScanObservation): void {
    const matched: string[] = this.signatureEngine.match(observation, this.state.signatures);
    const existing: Sighting | undefined = this.state.sightings.find((item: Sighting): boolean => item.key === observation.key);
    if (existing === undefined) { const sighting: Sighting = Sighting.fromObservation(observation); sighting.signatureIds = matched; this.state.sightings.push(sighting); }
    else { existing.ingest(observation); existing.signatureIds = matched; }
    this.sequence += 1;
    this.state.logs.push(new LogEntry('log-' + this.sequence.toString(), observation, matched));
  }

  private defaultSignatures(): SignatureDefinition[] {
    return [
      new SignatureDefinition('sig-find-hub', 'Google Find Hub', RadioKind.BLE, SignatureClass.FINDER, 'find hub'),
      new SignatureDefinition('sig-dult', 'DULT tracker', RadioKind.BLE, SignatureClass.FINDER, 'fcb2'),
      new SignatureDefinition('sig-remote-id', 'Remote ID', RadioKind.BLE, SignatureClass.DRONE, 'remote id', true),
      new SignatureDefinition('sig-router', 'RouterLab', RadioKind.WIFI, SignatureClass.ROUTER, 'router')
    ];
  }
}

export const fieldwatchApplication: FieldwatchApplication = new FieldwatchApplication();
