import localUnitTest from './LocalUnit.test';
import dependencyContainerTest from './DependencyContainer.test';
import systemIntegrationTest from './SystemIntegrationFacade.test';
import workflowDefinitionTest from './WorkflowDefinitionFacade.test';
import fieldwatchDomainTest from './FieldwatchDomain.test';
import fieldwatchRadioTest from './FieldwatchRadio.test';
import fieldwatchWifiScannerTest from './FieldwatchWifiScanner.test';
import fieldwatchSignatureTest from './FieldwatchSignature.test';
import fieldwatchHuntTest from './FieldwatchHunt.test';

import fieldwatchUiThemeTest from './FieldwatchUiTheme.test';

import fieldwatchFilterEngineTest from './FieldwatchFilterEngine.test';
import fieldwatchCandidateEngineTest from './FieldwatchCandidateEngine.test';

import fieldwatchRadioDbTest from './FieldwatchRadioDb.test';

import fieldwatchFastPairTest from './FieldwatchFastPair.test';
import fieldwatchPermissionsTest from './FieldwatchPermissions.test';
import fieldwatchAdvertisementTest from './FieldwatchAdvertisement.test';
import fieldwatchPrivacyExportTest from './FieldwatchPrivacyExport.test';
import fieldwatchSettingsBackupTest from './FieldwatchSettingsBackup.test';
import fieldwatchWatchAlertTest from './FieldwatchWatchAlert.test';
import fieldwatchToolboxTest from './FieldwatchToolbox.test';
// 测试取并集：main 的找东西/热路径用例全部保留，feat 侧只注册与本次合入功能有关的用例。
// FieldwatchOwnDevice / FieldwatchFindModel / FieldwatchDeviceBoard 三个用例依赖已剪枝的
// feat 版 OwnDeviceProfile 体系，随找东西专题一并暂缓，此处不注册。
import fieldwatchWidgetTest from './FieldwatchWidget.test';
import fieldwatchExportNamingTest from './FieldwatchExportNaming.test';
import fieldwatchPairedDevicesTest from './FieldwatchPairedDevices.test';
import fieldwatchOwnDeviceMatcherTest from './FieldwatchOwnDeviceMatcher.test';
import fieldwatchWifiLinkTest from './FieldwatchWifiLink.test';
import fieldwatchOwnDeviceRepositoryTest from './FieldwatchOwnDeviceRepository.test';
import fieldwatchFindClaimTest from './FieldwatchFindClaim.test';
import fieldwatchShakeConfirmTest from './FieldwatchShakeConfirm.test';
import fieldwatchOwnDeviceTrackerTest from './FieldwatchOwnDeviceTracker.test';
import fieldwatchHuntWindowsTest from './FieldwatchHuntWindows.test';
import fieldwatchUiModeTest from './FieldwatchUiMode.test';
import fieldwatchSecurityScanTest from './FieldwatchSecurityScan.test';
import fieldwatchAntiTrackAlertsTest from './FieldwatchAntiTrackAlerts.test';
import fieldwatchWifiDoctorTest from './FieldwatchWifiDoctor.test';
import fieldwatchWidgetUpgradeTest from './FieldwatchWidgetUpgrade.test';
import fieldwatchScenePacksTest from './FieldwatchScenePacks.test';
import fieldwatchRatingPromptTest from './FieldwatchRatingPrompt.test';
import fieldwatchDexTest from './FieldwatchDex.test';
import fieldwatchBatteryTest from './FieldwatchBattery.test';
import fieldwatchNewFacesTest from './FieldwatchNewFaces.test';
import fieldwatchDeviceNamingTest from './FieldwatchDeviceNaming.test';
import fieldwatchSecurityPassiveTest from './FieldwatchSecurityPassive.test';

export default function testsuite() {
  localUnitTest();
  dependencyContainerTest();
  systemIntegrationTest();
  workflowDefinitionTest();
  fieldwatchDomainTest();
  fieldwatchRadioTest();
  fieldwatchWifiScannerTest();
  fieldwatchSignatureTest();
  fieldwatchHuntTest();
  fieldwatchUiThemeTest();
  fieldwatchFilterEngineTest();
  fieldwatchCandidateEngineTest();
  fieldwatchRadioDbTest();
  fieldwatchFastPairTest();
  fieldwatchPermissionsTest();
  fieldwatchAdvertisementTest();
  fieldwatchPrivacyExportTest();
  fieldwatchSettingsBackupTest();
  fieldwatchWatchAlertTest();
  fieldwatchToolboxTest();
  fieldwatchWidgetTest();
  fieldwatchExportNamingTest();
  fieldwatchPairedDevicesTest();
  fieldwatchOwnDeviceMatcherTest();
  fieldwatchWifiLinkTest();
  fieldwatchOwnDeviceRepositoryTest();
  fieldwatchFindClaimTest();
  fieldwatchShakeConfirmTest();
  fieldwatchOwnDeviceTrackerTest();
  fieldwatchHuntWindowsTest();
  fieldwatchUiModeTest();
  fieldwatchSecurityScanTest();
  fieldwatchAntiTrackAlertsTest();
  fieldwatchWifiDoctorTest();
  fieldwatchWidgetUpgradeTest();
  fieldwatchScenePacksTest();
  fieldwatchRatingPromptTest();
  fieldwatchDexTest();
  fieldwatchBatteryTest();
  fieldwatchNewFacesTest();
  fieldwatchDeviceNamingTest();
  fieldwatchSecurityPassiveTest();
}
