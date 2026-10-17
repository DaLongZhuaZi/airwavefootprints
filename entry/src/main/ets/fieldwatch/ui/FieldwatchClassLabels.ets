import { SignatureClass } from '../domain/FieldwatchModels';
import { fieldwatchText } from './FieldwatchResText';

/** 签名类别的本地化标签；折叠别名（BODYWORN/ROUTER）在调用前折叠。 */
export function signatureClassLabel(category: SignatureClass): string {
  if (category === SignatureClass.FINDER) return fieldwatchText('app.string.fieldwatch_class_finder');
  if (category === SignatureClass.BEACON) return fieldwatchText('app.string.fieldwatch_class_beacon');
  if (category === SignatureClass.SIGNAGE) return fieldwatchText('app.string.fieldwatch_class_signage');
  if (category === SignatureClass.WEARABLE) return fieldwatchText('app.string.fieldwatch_class_wearable');
  if (category === SignatureClass.SURVEILLANCE) return fieldwatchText('app.string.fieldwatch_class_surveillance');
  if (category === SignatureClass.DRONE) return fieldwatchText('app.string.fieldwatch_class_drone');
  if (category === SignatureClass.HACKING) return fieldwatchText('app.string.fieldwatch_class_hacking');
  if (category === SignatureClass.LAW_ENFORCEMENT) return fieldwatchText('app.string.fieldwatch_class_law_enforcement');
  if (category === SignatureClass.VEHICLE) return fieldwatchText('app.string.fieldwatch_class_vehicle');
  if (category === SignatureClass.GLASSES) return fieldwatchText('app.string.fieldwatch_class_glasses');
  if (category === SignatureClass.AUDIO) return fieldwatchText('app.string.fieldwatch_class_audio');
  if (category === SignatureClass.CAMERA) return fieldwatchText('app.string.fieldwatch_class_camera');
  if (category === SignatureClass.THERMOSTAT) return fieldwatchText('app.string.fieldwatch_class_thermostat');
  if (category === SignatureClass.LOCK) return fieldwatchText('app.string.fieldwatch_class_lock');
  if (category === SignatureClass.HEALTH) return fieldwatchText('app.string.fieldwatch_class_health');
  if (category === SignatureClass.HOME) return fieldwatchText('app.string.fieldwatch_class_home');
  if (category === SignatureClass.ISP) return fieldwatchText('app.string.fieldwatch_class_isp');
  if (category === SignatureClass.MESH) return fieldwatchText('app.string.fieldwatch_class_mesh');
  if (category === SignatureClass.PHONE) return fieldwatchText('app.string.fieldwatch_class_phone');
  return fieldwatchText('app.string.fieldwatch_class_other');
}
