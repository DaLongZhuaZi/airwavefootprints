import { describe, it, expect } from '@ohos/hypium';
import {
  activeEvidenceOf, ActiveEvidenceKind, looksLikeVideoDevice, vendorFromPorts
} from '../main/ets/fieldwatch/domain/FieldwatchProtocolProber';

export default function fieldwatchProtocolProberTest() {
  describe('FieldwatchProtocolProber', () => {
    // A7 厂商识别：只看端口组合，不读任何横幅原文。
    it('identifies vendors from port combinations only', 0, () => {
      expect(vendorFromPorts([37777])).assertEqual('dahua');
      expect(vendorFromPorts([34567])).assertEqual('xiongmai');
      expect(vendorFromPorts([9000])).assertEqual('reolink');
      // 海康要求 8000 与 554 同时开（8000 单开也可能是别的服务）。
      expect(vendorFromPorts([8000, 554])).assertEqual('hikvision');
      expect(vendorFromPorts([8000])).assertEqual('unknown');
      expect(vendorFromPorts([8899])).assertEqual('onvif_device');
      expect(vendorFromPorts([80, 443])).assertEqual('unknown');
      expect(vendorFromPorts([])).assertEqual('unknown');
    });

    // 视频类判定：554 RTSP 是最强信号。
    it('treats an open RTSP port as a video signal', 0, () => {
      expect(looksLikeVideoDevice([554])).assertTrue();
      expect(looksLikeVideoDevice([80, 443, 554])).assertTrue();
      expect(looksLikeVideoDevice([80, 443])).assertFalse();
      expect(looksLikeVideoDevice([])).assertFalse();
    });

    // 主动证据只回类别，不回任何原文。
    it('derives active evidence kinds from open ports', 0, () => {
      expect(activeEvidenceOf([554]).indexOf(ActiveEvidenceKind.VIDEO_PORT) >= 0).assertTrue();
      expect(activeEvidenceOf([37777]).indexOf(ActiveEvidenceKind.VENDOR_PORT) >= 0).assertTrue();
      expect(activeEvidenceOf([34567]).indexOf(ActiveEvidenceKind.VENDOR_PORT) >= 0).assertTrue();
      expect(activeEvidenceOf([9000]).indexOf(ActiveEvidenceKind.VENDOR_PORT) >= 0).assertTrue();
      expect(activeEvidenceOf([8899]).indexOf(ActiveEvidenceKind.ONVIF_PORT) >= 0).assertTrue();
      expect(activeEvidenceOf([3702]).indexOf(ActiveEvidenceKind.ONVIF_PORT) >= 0).assertTrue();
      // 普通 HTTP 端口不产生主动证据（避免噪声）。
      expect(activeEvidenceOf([80, 443]).length).assertEqual(0);
    });

    // 多端口时证据可叠加。
    it('accumulates multiple evidence kinds', 0, () => {
      const kinds: ActiveEvidenceKind[] = activeEvidenceOf([554, 37777, 8899]);
      expect(kinds.length).assertEqual(3);
      expect(kinds.indexOf(ActiveEvidenceKind.VIDEO_PORT) >= 0).assertTrue();
      expect(kinds.indexOf(ActiveEvidenceKind.VENDOR_PORT) >= 0).assertTrue();
      expect(kinds.indexOf(ActiveEvidenceKind.ONVIF_PORT) >= 0).assertTrue();
    });
  });
}
