import { describe, expect, it } from '@ohos/hypium';
import { FieldwatchAlertVoiceWhat, parseVoiceWhat } from '../main/ets/fieldwatch/platform/FieldwatchWatchAlert';
import { FieldwatchSettingsRepository } from '../main/ets/fieldwatch/data/FieldwatchSettingsRepository';
import { AppSettings } from '../main/ets/fieldwatch/domain/FieldwatchModels';

export default function fieldwatchWatchAlertTest() {
  describe('FieldwatchWatchAlert', () => {
    // §12.3 要求「语音内容选择：Class / Signature / Class + signature」，
    // 对应原版 alert/Alerter.kt 的 AlertVoiceWhat。
    // 此前这块完全没有实现 —— 只有系统通知，没有蜂鸣也没有语音。

    it('parses every voice content choice and defaults to class', 0, () => {
      expect(parseVoiceWhat('class')).assertEqual(FieldwatchAlertVoiceWhat.CLASS);
      expect(parseVoiceWhat('signature')).assertEqual(FieldwatchAlertVoiceWhat.SIGNATURE);
      expect(parseVoiceWhat('classSignature')).assertEqual(FieldwatchAlertVoiceWhat.CLASS_SIGNATURE);
      // 旧备份或手改文件里的未知值必须收敛到默认，而不是抛错。
      expect(parseVoiceWhat('')).assertEqual(FieldwatchAlertVoiceWhat.CLASS);
      expect(parseVoiceWhat('nonsense')).assertEqual(FieldwatchAlertVoiceWhat.CLASS);
    });

    it('ships audible-alert defaults that keep the feature reachable', 0, () => {
      const settings: AppSettings = new AppSettings();
      // 蜂鸣默认开、语音默认关：与原版一致 —— 语音会念出设备类别，
      // 现场使用需要用户显式开启，避免默认就外放。
      expect(settings.watchBeep).assertTrue();
      expect(settings.watchVoice).assertFalse();
      expect(settings.watchVoiceWhat).assertEqual('class');
    });

    it('persists the hunt tick switches and defaults them off', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const defaults: AppSettings = new AppSettings();
      // 原版 `huntBeep` / `huntVibrate` 默认都是 false（注释：Off by default）。
      // 我们此前是页面局部 `@State = true` —— 默认相反且**不持久化**，用户关不掉。
      expect(defaults.huntBeep).assertFalse();
      expect(defaults.huntVibrate).assertFalse();
      const settings: AppSettings = new AppSettings();
      settings.huntBeep = true;
      settings.huntVibrate = true;
      repository.save(settings);
      // 真正落盘：重新 load 必须拿到刚写进去的值，而不是回到默认。
      const reloaded: AppSettings = repository.load();
      expect(reloaded.huntBeep).assertTrue();
      expect(reloaded.huntVibrate).assertTrue();
      // 两个开关彼此独立：可以只振动不出声。
      settings.huntBeep = false;
      repository.save(settings);
      const mixed: AppSettings = repository.load();
      expect(mixed.huntBeep).assertFalse();
      expect(mixed.huntVibrate).assertTrue();
      // 复原，避免影响同批其他用例。
      settings.huntBeep = false; settings.huntVibrate = false;
      repository.save(settings);
    });

    it('persists the four list display switches and defaults them on', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const defaults: AppSettings = new AppSettings();
      // 原版这四个默认都是 true（列表默认显示全）。
      expect(defaults.showRssiBar).assertTrue();
      expect(defaults.showFleetName).assertTrue();
      expect(defaults.showFrequency).assertTrue();
      expect(defaults.showSeenTimes).assertTrue();
      const settings: AppSettings = new AppSettings();
      settings.showRssiBar = false;
      settings.showFleetName = false;
      settings.showFrequency = false;
      settings.showSeenTimes = false;
      repository.save(settings);
      // 落盘后重新 load 必须拿到全 false —— 否则等于开关记不住。
      const reloaded: AppSettings = repository.load();
      expect(reloaded.showRssiBar).assertFalse();
      expect(reloaded.showFleetName).assertFalse();
      expect(reloaded.showFrequency).assertFalse();
      expect(reloaded.showSeenTimes).assertFalse();
      // 反向再写一次，确认不是单向卡死。
      settings.showFrequency = true;
      repository.save(settings);
      const mixed: AppSettings = repository.load();
      expect(mixed.showFrequency).assertTrue();
      expect(mixed.showRssiBar).assertFalse();
      // 复原，避免影响同批其他用例。
      const clean: AppSettings = new AppSettings();
      repository.save(clean);
    });

    it('carries the display switches through a backup round trip', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const settings: AppSettings = new AppSettings();
      settings.showRssiBar = false;
      settings.showSeenTimes = false;
      repository.save(settings);
      const backup: string = repository.exportBackup(settings);
      expect(backup.indexOf('showRssiBar=false') >= 0).assertTrue();
      expect(backup.indexOf('showSeenTimes=false') >= 0).assertTrue();
      expect(backup.indexOf('showFleetName=true') >= 0).assertTrue();
      const clean: AppSettings = new AppSettings();
      repository.save(clean);
      expect(repository.importBackup(backup)).assertTrue();
      const restored: AppSettings = repository.load();
      expect(restored.showRssiBar).assertFalse();
      expect(restored.showSeenTimes).assertFalse();
      repository.save(clean);
    });

    it('round trips the audible-alert settings through a backup', 0, () => {
      const repository: FieldwatchSettingsRepository = new FieldwatchSettingsRepository();
      const settings: AppSettings = new AppSettings();
      settings.watchBeep = false;
      settings.watchVoice = true;
      settings.watchVoiceWhat = 'classSignature';
      repository.save(settings);
      const backup: string = repository.exportBackup(settings);
      expect(backup.indexOf('watchBeep=false') >= 0).assertTrue();
      expect(backup.indexOf('watchVoice=true') >= 0).assertTrue();
      expect(backup.indexOf('watchVoiceWhat=classSignature') >= 0).assertTrue();
      // 破坏本地值后确认恢复真的来自备份。
      settings.watchBeep = true;
      settings.watchVoice = false;
      settings.watchVoiceWhat = 'class';
      repository.save(settings);
      expect(repository.importBackup(backup)).assertTrue();
      const restored: AppSettings = repository.load();
      expect(restored.watchBeep).assertFalse();
      expect(restored.watchVoice).assertTrue();
      expect(restored.watchVoiceWhat).assertEqual('classSignature');
    });
  });
}