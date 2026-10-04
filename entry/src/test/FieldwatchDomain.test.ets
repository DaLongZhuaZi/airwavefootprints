import { describe, it, expect } from '@ohos/hypium';
import { FieldwatchFilterEngine, FieldwatchGeoService, FieldwatchPrivacyService, FieldwatchSignatureEngine } from '../src/main/ets/fieldwatch/domain/FieldwatchDomainService';
import { AppSettings, FilterDefinition, GpsSample, RadioFacts, RadioKind, ScanObservation, SignatureClass, SignatureDefinition, Sighting, WatchTarget } from '../src/main/ets/fieldwatch/domain/FieldwatchModels';

export default function fieldwatchDomainTest() {
  describe('FieldwatchDomain', () => {
    it('matches typed signatures', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Find Hub tag', -40, 1, new RadioFacts('', 'Google'));
      const signatures: SignatureDefinition[] = [new SignatureDefinition('find', 'Find Hub', RadioKind.BLE, SignatureClass.FINDER, 'find hub')];
      const result: string[] = new FieldwatchSignatureEngine().match(observation, signatures);
      expect(result.length).assertEqual(1);
      expect(result[0]).assertEqual('find');
    });

    it('applies watchlist filtering', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Find Hub tag', -40, 1);
      const sighting: Sighting = Sighting.fromObservation(observation);
      sighting.signatureIds = ['find'];
      const filter: FilterDefinition = new FilterDefinition();
      filter.minimumRssi = -50;
      filter.signatureId = 'find';
      filter.watchedOnly = true;
      const watched: WatchTarget[] = [new WatchTarget('demo', '', 'demo', true)];
      const signatures: SignatureDefinition[] = [new SignatureDefinition('find', 'Find Hub', RadioKind.BLE, SignatureClass.FINDER, 'find')];
      expect(new FieldwatchFilterEngine().pass(sighting, filter, signatures, watched)).assertTrue();
    });

    it('calculates a path', 0, () => {
      const first: GpsSample = new GpsSample(22.3, 114.1, 1);
      const second: GpsSample = new GpsSample(22.31, 114.1, 2);
      expect(new FieldwatchGeoService().pathLengthMeters([first, second]) > 1000).assertTrue();
    });

    it('masks privacy fields', 0, () => {
      const observation: ScanObservation = new ScanObservation('demo', RadioKind.BLE, 'AA:BB:CC:DD:EE:FF', 'Demo', -40, 1, new RadioFacts(), new GpsSample(22.3, 114.1, 1));
      const sighting: Sighting = Sighting.fromObservation(observation);
      const settings: AppSettings = new AppSettings();
      settings.privacyMode = true;
      const text: string = new FieldwatchPrivacyService().describe(sighting, settings);
      expect(text.indexOf('**:**:**') >= 0).assertTrue();
      expect(text.indexOf('22.30') >= 0).assertTrue();
    });
  });
}
