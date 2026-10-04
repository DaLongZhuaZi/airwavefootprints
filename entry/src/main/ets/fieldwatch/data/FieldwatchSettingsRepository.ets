import { ngfSettingsStoreFacade, logger } from 'ngf_framework';
import { AppSettings } from '../domain/FieldwatchModels';

const TAG: string = 'FieldwatchSettingsRepository';

export class FieldwatchSettingsRepository {
  load(): AppSettings {
    const settings: AppSettings = new AppSettings();
    settings.displayPaused = ngfSettingsStoreFacade.getBoolean('fieldwatch.displayPaused', settings.displayPaused);
    settings.darkMode = ngfSettingsStoreFacade.getBoolean('fieldwatch.darkMode', settings.darkMode);
    settings.keepScreenOn = ngfSettingsStoreFacade.getBoolean('fieldwatch.keepScreenOn', settings.keepScreenOn);
    settings.locationTagging = ngfSettingsStoreFacade.getBoolean('fieldwatch.locationTagging', settings.locationTagging);
    settings.privacyMode = ngfSettingsStoreFacade.getBoolean('fieldwatch.privacyMode', settings.privacyMode);
    settings.scanIntensity = ngfSettingsStoreFacade.getString('fieldwatch.scanIntensity', settings.scanIntensity);
    logger.debug(TAG, 'Fieldwatch 设置已加载');
    return settings;
  }

  save(settings: AppSettings): void {
    ngfSettingsStoreFacade.setBoolean('fieldwatch.displayPaused', settings.displayPaused);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.darkMode', settings.darkMode);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.keepScreenOn', settings.keepScreenOn);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.locationTagging', settings.locationTagging);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.privacyMode', settings.privacyMode);
    ngfSettingsStoreFacade.setString('fieldwatch.scanIntensity', settings.scanIntensity);
    logger.debug(TAG, 'Fieldwatch 设置已保存');
  }
}
