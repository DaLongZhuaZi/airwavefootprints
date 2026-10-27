import { describe, it, expect } from '@ohos/hypium';
import {
  assessSighting, CAMERA_COMPANY_IDS, CAMERA_OUI_PREFIXES, capabilityBoundaryKeys, companyIdLooksLikeCamera,
  countVerdicts, nameLooksLikeCamera, ouiLooksLikeCamera, ouiLooksLikeChipset, SecurityEvidence, SecurityEvidenceKind,
  SecurityVerdict, suspectListOf, SuspectDevice, verdictOf
} from '../main/ets/fieldwatch/domain/FieldwatchSecurityPassive';
import { RadioFacts, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';

function sightingOf(address: string, name: string, ssid: string = '', companyId: number = 0): Sighting {
  const facts: RadioFacts = new RadioFacts();
  facts.ssid = ssid;
  facts.manufacturerId = companyId;
  const observation: ScanObservation = new ScanObservation('ble:' + address, RadioKind.BLE, address, name, -60, 1000, facts);
  const sighting: Sighting = Sighting.fromObservation(observation);
  return sighting;
}

function evidence(kind: SecurityEvidenceKind): SecurityEvidence {
  return new SecurityEvidence(kind, 'x');
}

export default function fieldwatchSecurityPassiveTest() {
  describe('FieldwatchSecurityPassive', () => {
    // 结论只有三档，且**绝不含「安全 / 已排除」**（文档 3.3 口径）。
    it('has exactly three verdicts and never claims safety', 0, () => {
      expect(String(SecurityVerdict.CONFIRMED)).assertEqual('confirmed');
      expect(String(SecurityVerdict.SUSPICIOUS)).assertEqual('suspicious');
      expect(String(SecurityVerdict.NONE)).assertEqual('none');
      // 枚举里不存在 safe / excluded 之类的取值。
      const all: string[] = [String(SecurityVerdict.CONFIRMED), String(SecurityVerdict.SUSPICIOUS), String(SecurityVerdict.NONE)];
      expect(all.indexOf('safe')).assertEqual(-1);
      expect(all.indexOf('excluded')).assertEqual(-1);
    });

    // 确认 = **独立类别** ≥2；同类别多条不算多信号印证。
    it('requires independent evidence kinds for a confirmed verdict', 0, () => {
      expect(verdictOf([])).assertEqual(SecurityVerdict.NONE);
      expect(verdictOf([evidence(SecurityEvidenceKind.VENDOR_OUI)])).assertEqual(SecurityVerdict.SUSPICIOUS);
      // 同类三条 → 仍然是「可疑」（名字像摄像头只是同一件事）。
      const sameKind: SecurityEvidence[] = [
        evidence(SecurityEvidenceKind.NAME_PATTERN),
        evidence(SecurityEvidenceKind.NAME_PATTERN),
        evidence(SecurityEvidenceKind.NAME_PATTERN)
      ];
      expect(verdictOf(sameKind)).assertEqual(SecurityVerdict.SUSPICIOUS);
      // 不同类两条 → 确认。
      const crossKind: SecurityEvidence[] = [
        evidence(SecurityEvidenceKind.VENDOR_OUI),
        evidence(SecurityEvidenceKind.MEDIA_SERVICE)
      ];
      expect(verdictOf(crossKind)).assertEqual(SecurityVerdict.CONFIRMED);
    });

    // 名称特征：词表命中；裸 cam 要词边界，不能误伤 Camry。
    it('matches camera-like names without false positives', 0, () => {
      expect(nameLooksLikeCamera('IPCAM-001')).assertTrue();
      expect(nameLooksLikeCamera('My_IP_Camera')).assertTrue();
      expect(nameLooksLikeCamera('NVR-8CH')).assertTrue();
      expect(nameLooksLikeCamera('Reolink-E1')).assertTrue();
      // 词边界：'cam' 独立成词才算。
      expect(nameLooksLikeCamera('front cam')).assertTrue();
      expect(nameLooksLikeCamera('Cam')).assertTrue();
      // 误伤防护。
      expect(nameLooksLikeCamera('Camry-2019')).assertFalse();
      expect(nameLooksLikeCamera('camping')).assertFalse();
      expect(nameLooksLikeCamera('')).assertFalse();
    });

    it('recognises camera vendor OUIs', 0, () => {
      expect(ouiLooksLikeCamera('B0:C5:54:11:22:33')).assertTrue();
      expect(ouiLooksLikeCamera('EC:71:DB:00:00:01')).assertTrue();
      // Espressif 属于**通用芯片方案商**，不再算强信号（真机实测误报大量插座/体重秤）。
      expect(ouiLooksLikeCamera('A0:02:DC:AA:BB:CC')).assertFalse();
      expect(ouiLooksLikeChipset('A0:02:DC:AA:BB:CC')).assertTrue();
      // 非摄像头厂商。
      expect(ouiLooksLikeCamera('AA:BB:CC:DD:EE:FF')).assertFalse();
      expect(ouiLooksLikeCamera('')).assertFalse();
      // 表中每个前缀都能被自己命中（防手滑写错格式）。
      CAMERA_OUI_PREFIXES.forEach((oui: string): void => {
        expect(ouiLooksLikeCamera(oui + ':00:00:00')).assertTrue();
      });
    });

    // **真机回归教训**：通用芯片方案商的 OUI 单独命中不能产生任何结论。
    // 修复前一次扫描报出 6 台「可疑」，全部只是因为在用 Espressif/Tuya 芯片。
    it('does not flag devices merely for using a generic chipset', 0, () => {
      const espressif: Sighting = sightingOf('A0:02:DC:11:22:33', 'KitchenPlug');
      expect(assessSighting(espressif, false, false).verdict).assertEqual(SecurityVerdict.NONE);
      const tuya: Sighting = sightingOf('B4:5D:50:11:22:33', 'BodyScale');
      expect(assessSighting(tuya, false, false).verdict).assertEqual(SecurityVerdict.NONE);
      // 但配合另一类证据时，它可以作为辅助印证。
      // `IPCAM-1` 同时命中「名称像摄像头」+「芯片商辅助」→ 两类独立证据 → 确认。
      // 这正是设计意图：芯片商单独不够，但它确实提高了置信度。
      const chipPlusName: Sighting = sightingOf('A0:02:DC:11:22:33', 'IPCAM-1');
      expect(assessSighting(chipPlusName, false, false).verdict).assertEqual(SecurityVerdict.CONFIRMED);
      // 名称命中但**不是**芯片商时只有一类证据 → 可疑（对照组）。
      const nameOnly: Sighting = sightingOf('AA:BB:CC:11:22:33', 'IPCAM-1');
      expect(assessSighting(nameOnly, false, false).verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
    });

    // 专用摄像头厂商（海康/大华等）仍然是强信号。
    it('still flags dedicated camera vendors as suspicious', 0, () => {
      const hik: Sighting = sightingOf('B0:C5:54:11:22:33', 'LivingRoom');
      expect(assessSighting(hik, false, false).verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
    });

    it('recognises camera company ids', 0, () => {
      CAMERA_COMPANY_IDS.forEach((id: number): void => {
        expect(companyIdLooksLikeCamera(id)).assertTrue();
      });
      expect(companyIdLooksLikeCamera(12345)).assertFalse();
    });

    // 单强信号 → 可疑；多信号 → 确认。
    it('assesses a sighting with vendor plus name as confirmed', 0, () => {
      const hit: Sighting = sightingOf('B0:C5:54:11:22:33', 'IPCAM-1');
      const suspect: SuspectDevice = assessSighting(hit, false, false);
      expect(suspect.verdict).assertEqual(SecurityVerdict.CONFIRMED);
      expect(suspect.evidence.length).assertEqual(2);
      // 只有厂商命中 → 可疑。
      const vendorOnly: Sighting = sightingOf('B0:C5:54:11:22:33', 'LivingRoom');
      expect(assessSighting(vendorOnly, false, false).verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
      // 什么都没有 → 未发现。
      const plain: Sighting = sightingOf('AA:BB:CC:DD:EE:FF', 'Speaker');
      expect(assessSighting(plain, false, false).verdict).assertEqual(SecurityVerdict.NONE);
    });

    // Wi-Fi 用 SSID 判定（广播名对 Wi-Fi 不适用）。
    it('uses the SSID for Wi-Fi devices', 0, () => {
      const facts: RadioFacts = new RadioFacts();
      facts.ssid = 'IPCAM_8888';
      const observation: ScanObservation = new ScanObservation('wifi:AA:BB:CC:DD:EE:FF', RadioKind.WIFI, 'AA:BB:CC:DD:EE:FF', '', -55, 1000, facts);
      const sighting: Sighting = Sighting.fromObservation(observation);
      const suspect: SuspectDevice = assessSighting(sighting, false, false);
      expect(suspect.verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
    });

    // 特征库命中与媒体服务宣告也各算一类独立证据。
    it('counts catalog hits and media service announcements', 0, () => {
      const plain: Sighting = sightingOf('AA:BB:CC:DD:EE:FF', 'Speaker');
      expect(assessSighting(plain, true, false).verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
      expect(assessSighting(plain, true, true).verdict).assertEqual(SecurityVerdict.CONFIRMED);
    });

    it('lists only suspects, confirmed first', 0, () => {
      const confirmed: SuspectDevice = assessSighting(sightingOf('B0:C5:54:11:22:33', 'IPCAM-1'), false, false);
      const suspicious: SuspectDevice = assessSighting(sightingOf('EC:71:DB:00:00:01', 'LivingRoom'), false, false);
      const none: SuspectDevice = assessSighting(sightingOf('AA:BB:CC:DD:EE:FF', 'Speaker'), false, false);
      const list: SuspectDevice[] = suspectListOf([none, suspicious, confirmed]);
      expect(list.length).assertEqual(2);
      expect(list[0].verdict).assertEqual(SecurityVerdict.CONFIRMED);
      expect(list[1].verdict).assertEqual(SecurityVerdict.SUSPICIOUS);
      const counts: number[] = countVerdicts(list);
      expect(counts[0]).assertEqual(1);
      expect(counts[1]).assertEqual(1);
    });

    // 能力边界：四条必须齐全（不联网/关机/客户端隔离/GSM）。
    it('exposes all four capability boundaries', 0, () => {
      const keys: string[] = capabilityBoundaryKeys();
      expect(keys.length).assertEqual(4);
      expect(keys[0].indexOf('local_only') > 0).assertTrue();
      expect(keys[1].indexOf('powered_off') > 0).assertTrue();
      expect(keys[2].indexOf('client_isolation') > 0).assertTrue();
      expect(keys[3].indexOf('gsm') > 0).assertTrue();
    });
  });
}
