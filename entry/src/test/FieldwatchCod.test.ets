import { describe, it, expect } from '@ohos/hypium';
import {
  COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_CAMCORDER, COD_MINOR_AV_MICROPHONE, COD_MINOR_AV_VIDEO_CAMERA,
  COD_MINOR_AV_VIDEO_CONFERENCING, CodClass, codLooksLikeCamera, codLooksLikeMicrophone, parseCod,
  SecurityEvidenceKind
} from '../main/ets/fieldwatch/domain/FieldwatchSecurityPassive';

/** 按 Bluetooth SIG Class of Device 布局拼一个 24 位值：major 在 bit8..12，minor 在 bit2..7。 */
function codOf(major: number, minor: number): number {
  return ((major & 0x1F) << 8) | ((minor & 0x3F) << 2);
}

export default function fieldwatchCodTest() {
  describe('FieldwatchCodSignals', () => {
    // 解析：major / minor 各归各位；没有 CoD 时是 -1 而不是 0。
    it('parses major and minor out of the class of device', 0, () => {
      const cam: CodClass = parseCod(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_VIDEO_CAMERA));
      expect(cam.major).assertEqual(COD_MAJOR_AUDIO_VIDEO);
      expect(cam.minor).assertEqual(COD_MINOR_AV_VIDEO_CAMERA);
      // 0 与「不知道」必须分开：0 是合法的 Miscellaneous。
      expect(parseCod(0).major).assertEqual(-1);
      expect(parseCod(0).minor).assertEqual(-1);
      expect(parseCod(-5).major).assertEqual(-1);
    });

    // AV_MICROPHONE → 疑似拾音。
    it('recognises the microphone minor class', 0, () => {
      expect(codLooksLikeMicrophone(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_MICROPHONE))).assertTrue();
      // 其他大类同号小类不算。
      expect(codLooksLikeMicrophone(codOf(0x01, COD_MINOR_AV_MICROPHONE))).assertFalse();
      // 音视频大类但别的小类。
      expect(codLooksLikeMicrophone(codOf(COD_MAJOR_AUDIO_VIDEO, 0x01))).assertFalse();
      expect(codLooksLikeMicrophone(0)).assertFalse();
    });

    // 三种拍摄类小类都要认出。
    it('recognises the camera-like minor classes', 0, () => {
      expect(codLooksLikeCamera(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_VIDEO_CAMERA))).assertTrue();
      expect(codLooksLikeCamera(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_CAMCORDER))).assertTrue();
      expect(codLooksLikeCamera(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_VIDEO_CONFERENCING))).assertTrue();
      // 麦克风不算摄像头。
      expect(codLooksLikeCamera(codOf(COD_MAJOR_AUDIO_VIDEO, COD_MINOR_AV_MICROPHONE))).assertFalse();
      // 耳机（0x01 Wearable Headset 不在 AV 大类）不算。
      expect(codLooksLikeCamera(codOf(0x04, 0x01))).assertFalse();
      expect(codLooksLikeCamera(0)).assertFalse();
    });

    // 文档硬要求：单独命中只作弱信号，绝不能升到「可疑」。
    it('exposes a distinct evidence kind for class-of-device signals', 0, () => {
      // 独立类别，不与厂商混算，否则「独立证据」计数会被污染。
      expect(String(SecurityEvidenceKind.DEVICE_CLASS)).assertEqual('device_class');
      expect(String(SecurityEvidenceKind.DEVICE_CLASS) === String(SecurityEvidenceKind.VENDOR_OUI)).assertFalse();
    });
  });
}
