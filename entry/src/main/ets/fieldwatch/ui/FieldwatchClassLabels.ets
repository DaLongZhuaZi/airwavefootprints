import { SignatureClass } from '../domain/FieldwatchModels';

/** 签名类别的本地化标签；折叠别名（BODYWORN/ROUTER）在调用前折叠。 */
export function signatureClassLabel(category: SignatureClass): Resource {
  if (category === SignatureClass.FINDER) return $r('app.string.fieldwatch_class_finder');
  if (category === SignatureClass.BEACON) return $r('app.string.fieldwatch_class_beacon');
  if (category === SignatureClass.SIGNAGE) return $r('app.string.fieldwatch_class_signage');
  if (category === SignatureClass.WEARABLE) return $r('app.string.fieldwatch_class_wearable');
  if (category === SignatureClass.SURVEILLANCE) return $r('app.string.fieldwatch_class_surveillance');
  if (category === SignatureClass.DRONE) return $r('app.string.fieldwatch_class_drone');
  if (category === SignatureClass.HACKING) return $r('app.string.fieldwatch_class_hacking');
  if (category === SignatureClass.LAW_ENFORCEMENT) return $r('app.string.fieldwatch_class_law_enforcement');
  if (category === SignatureClass.VEHICLE) return $r('app.string.fieldwatch_class_vehicle');
  if (category === SignatureClass.GLASSES) return $r('app.string.fieldwatch_class_glasses');
  if (category === SignatureClass.AUDIO) return $r('app.string.fieldwatch_class_audio');
  if (category === SignatureClass.CAMERA) return $r('app.string.fieldwatch_class_camera');
  if (category === SignatureClass.THERMOSTAT) return $r('app.string.fieldwatch_class_thermostat');
  if (category === SignatureClass.LOCK) return $r('app.string.fieldwatch_class_lock');
  if (category === SignatureClass.HEALTH) return $r('app.string.fieldwatch_class_health');
  if (category === SignatureClass.HOME) return $r('app.string.fieldwatch_class_home');
  if (category === SignatureClass.ISP) return $r('app.string.fieldwatch_class_isp');
  if (category === SignatureClass.MESH) return $r('app.string.fieldwatch_class_mesh');
  if (category === SignatureClass.PHONE) return $r('app.string.fieldwatch_class_phone');
  return $r('app.string.fieldwatch_class_other');
}
