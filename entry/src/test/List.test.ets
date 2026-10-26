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
import fieldwatchOwnDeviceTest from './FieldwatchOwnDevice.test';
import fieldwatchFindModelTest from './FieldwatchFindModel.test';
import fieldwatchUiModeTest from './FieldwatchUiMode.test';
import fieldwatchSecurityScanTest from './FieldwatchSecurityScan.test';
import fieldwatchAntiTrackAlertsTest from './FieldwatchAntiTrackAlerts.test';
import fieldwatchWifiDoctorTest from './FieldwatchWifiDoctor.test';
import fieldwatchWidgetUpgradeTest from './FieldwatchWidgetUpgrade.test';
import fieldwatchScenePacksTest from './FieldwatchScenePacks.test';
import fieldwatchRatingPromptTest from './FieldwatchRatingPrompt.test';

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
  fieldwatchOwnDeviceTest();
  fieldwatchFindModelTest();
  fieldwatchUiModeTest();
  fieldwatchSecurityScanTest();
  fieldwatchAntiTrackAlertsTest();
  fieldwatchWifiDoctorTest();
  fieldwatchWidgetUpgradeTest();
  fieldwatchScenePacksTest();
  fieldwatchRatingPromptTest();
}
