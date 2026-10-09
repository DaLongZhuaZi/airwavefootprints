import { describe, expect, it } from '@ohos/hypium';
import { Permissions } from '@kit.AbilityKit';
import {
  buildPermissionSpecs,
  FIELDWATCH_BASELINE_FEATURE_KEYS,
  FIELDWATCH_BASELINE_SYMBOLS,
  FieldwatchCapabilitySnapshot,
  FieldwatchPermissionKind,
  FieldwatchPermissionSpec
} from '../main/ets/fieldwatch/domain/FieldwatchPermissions';

export default function fieldwatchPermissionsTest() {
  describe('FieldwatchPermissions', () => {
    it('lists exactly the two user-grantable items the system settings show', 0, () => {
      const specs: FieldwatchPermissionSpec[] = buildPermissionSpecs();
      expect(specs.length).assertEqual(2);
      expect(specs[0].kind).assertEqual(FieldwatchPermissionKind.BLUETOOTH);
      expect(specs[1].kind).assertEqual(FieldwatchPermissionKind.LOCATION);
    });

    it('never asks for a system_grant permission', 0, () => {
      // 这三条都是 system_grant：安装即授予，系统设置里**没有**对应开关。
      // 把它们列成待申请权限，用户点了也不会有任何弹窗，属于凭空制造死路。
      const forbidden: Permissions[] = [
        'ohos.permission.GET_WIFI_INFO',
        'ohos.permission.SET_WIFI_INFO',
        'ohos.permission.INTERNET'
      ];
      buildPermissionSpecs().forEach((spec: FieldwatchPermissionSpec): void => {
        spec.permissionIds.forEach((id: Permissions): void => {
          expect(forbidden.indexOf(id)).assertEqual(-1);
        });
      });
    });

    it('covers both bluetooth and nearlink under the single device-discovery item', 0, () => {
      // 系统设置里只有一项「设备发现和连接」，同时管蓝牙与星闪。
      // 应用内因此也只能显示一项，申请时再逐条补齐底层的两条权限。
      const ble: FieldwatchPermissionSpec = buildPermissionSpecs()[0];
      expect(ble.permissionIds.length).assertEqual(2);
      expect(ble.permissionIds.indexOf('ohos.permission.ACCESS_BLUETOOTH')).assertEqual(0);
      expect(ble.permissionIds.indexOf('ohos.permission.ACCESS_NEARLINK')).assertEqual(1);
      // 首条权限名用于 checkAccessTokenSync / requestPermissionsFromUser
      expect(ble.permissionId).assertEqual('ohos.permission.ACCESS_BLUETOOTH');
    });

    it('uses the location permission that matches the system settings label', 0, () => {
      const loc: FieldwatchPermissionSpec = buildPermissionSpecs()[1];
      expect(loc.permissionIds.length).assertEqual(1);
      expect(loc.permissionId).assertEqual('ohos.permission.APPROXIMATELY_LOCATION');
    });

    it('gives every spec a title that is the literal system settings name', 0, () => {
      // 标题必须让用户能在系统设置里按名找到；改成别的说法就等于指错地方。
      expect(buildPermissionSpecs()[0].titleKey).assertEqual('app.string.fieldwatch_perm_ble_title');
      expect(buildPermissionSpecs()[1].titleKey).assertEqual('app.string.fieldwatch_perm_loc_title');
    });

    it('fills every explanation field so no card renders blank', 0, () => {
      buildPermissionSpecs().forEach((spec: FieldwatchPermissionSpec): void => {
        expect(spec.titleKey.length > 0).assertTrue();
        expect(spec.whyKey.length > 0).assertTrue();
        expect(spec.featureKey.length > 0).assertTrue();
        expect(spec.deniedKey.length > 0).assertTrue();
        expect(spec.whereKey.length > 0).assertTrue();
      });
    });

    it('reports ble scanning as available exactly when bluetooth is granted', 0, () => {
      const none: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
      expect(none.canScanBle()).assertFalse();
      expect(none.bleUnavailable()).assertTrue();
      expect(none.grantedCount()).assertEqual(0);

      const bleOnly: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
      bleOnly.bluetooth = true;
      expect(bleOnly.canScanBle()).assertTrue();
      expect(bleOnly.bleUnavailable()).assertFalse();
      // Wi-Fi 不在快照里：它由系统自动授予，始终可用，不构成第三个维度。
      expect(bleOnly.grantedCount()).assertEqual(1);
    });

    it('counts each granted capability once, including nearlink', 0, () => {
      const all: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
      all.bluetooth = true;
      all.location = true;
      all.nearlink = true;
      expect(all.grantedCount()).assertEqual(3);

      const withoutNearLink: FieldwatchCapabilitySnapshot = new FieldwatchCapabilitySnapshot();
      withoutNearLink.bluetooth = true;
      withoutNearLink.location = true;
      expect(withoutNearLink.grantedCount()).assertEqual(2);
      // 没有星闪不影响 BLE 判断
      expect(withoutNearLink.canScanBle()).assertTrue();
    });

    it('keeps the permission-free baseline list and its icons in step', 0, () => {
      // 引导页与受限态共用这份清单；两者长度不一致会直接渲染越界。
      expect(FIELDWATCH_BASELINE_FEATURE_KEYS.length).assertEqual(FIELDWATCH_BASELINE_SYMBOLS.length);
      expect(FIELDWATCH_BASELINE_FEATURE_KEYS.length > 0).assertTrue();
    });
  });
}