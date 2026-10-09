import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { logger, uiContextManager } from 'ngf_framework';
import { FieldwatchHuntSoundFeedback } from './FieldwatchHuntFeedback';

const TAG: string = 'FieldwatchWatchAlert';
/** 双响的两声间隔，取自原版 Alerter 的 PIP_MS(85) + GAP_MS(55)。 */
const PIP_MS: number = 85;
const GAP_MS: number = 55;

/**
 * 语音内容选项。对应原版 `AlertVoiceWhat`（CLASS / SIGNATURE / CLASS_SIGNATURE）。
 * 取值用字符串而非数字，便于直接进设置备份（§12.7）。
 */
export enum FieldwatchAlertVoiceWhat {
  CLASS = 'class',
  SIGNATURE = 'signature',
  CLASS_SIGNATURE = 'classSignature'
}

export function parseVoiceWhat(text: string): FieldwatchAlertVoiceWhat {
  if (text === 'signature') return FieldwatchAlertVoiceWhat.SIGNATURE;
  if (text === 'classSignature') return FieldwatchAlertVoiceWhat.CLASS_SIGNATURE;
  return FieldwatchAlertVoiceWhat.CLASS;
}

/**
 * 关注列表的可听告警。
 *
 * **与 Hunt 的 geiger tick 是两套独立告警**（§7.2 明确要求区分）：
 * Hunt 是随接近程度变化的**单次**短促 tick；这里是设备出现时的**双响**提示。
 * 两者共用同一份音频资源，靠**节奏**而不是音色区分 —— 原版用 `AudioTrack`
 * 程序化合成音调（`res/raw` 为空、不引用 `R.raw.*`），我们复用已打包的 wav。
 *
 * 任一能力不可用都静默降级，不影响视觉告警与通知。
 */
export class FieldwatchWatchAlert {
  private readonly sound: FieldwatchHuntSoundFeedback = new FieldwatchHuntSoundFeedback();
  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private voicePreparing: boolean = false;
  private voiceFailed: boolean = false;

  /** 预热音频与语音引擎；首响前调用，避免第一次告警是哑的。 */
  async prepare(wantVoice: boolean): Promise<void> {
    await this.sound.prepare();
    if (wantVoice) this.ensureVoice();
  }

  soundAvailable(): boolean { return this.sound.available(); }
  voiceAvailable(): boolean { return this.engine !== undefined; }

  /**
   * 关注设备出现时的双响提示。
   * 两声短促之间留 `PIP_MS + GAP_MS`，与原版节奏一致。
   */
  doublePip(): void {
    this.sound.play();
    setTimeout((): void => { this.sound.play(); }, PIP_MS + GAP_MS);
  }

  /** 按所选内容朗读。`className` 与 `signatureName` 空着时自动降级为可用的那一项。 */
  speak(className: string, signatureName: string, what: FieldwatchAlertVoiceWhat): void {
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    if (engine === undefined) return;
    const hasClass: boolean = className.length > 0;
    const hasSignature: boolean = signatureName.length > 0;
    let text: string = '';
    if (what === FieldwatchAlertVoiceWhat.SIGNATURE) text = hasSignature ? signatureName : className;
    else if (what === FieldwatchAlertVoiceWhat.CLASS_SIGNATURE) {
      text = hasClass && hasSignature ? className + '，' + signatureName : (hasClass ? className : signatureName);
    } else text = hasClass ? className : signatureName;
    if (text.length === 0) return;
    try {
      engine.speak(text, this.speakParams());
      logger.debug(TAG, '语音告警: ' + text);
    } catch (error) {
      logger.warn(TAG, '语音播报失败: ' + this.errorMessage(error));
    }
  }

  release(): void {
    this.sound.release();
    const engine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    this.engine = undefined;
    if (engine === undefined) return;
    try {
      engine.shutdown();
    } catch (error) { logger.debug(TAG, '关闭语音引擎异常: ' + this.errorMessage(error)); }
  }

  /** 惰性创建语音引擎；失败只记一次，不反复重试拖慢告警。 */
  private ensureVoice(): void {
    if (this.engine !== undefined || this.voicePreparing || this.voiceFailed) return;
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return;
    this.voicePreparing = true;
    try {
      const params: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: { 'style': 'interaction-broadcast', 'locate': 'CN', 'name': 'EngineMandarin' }
      };
      textToSpeech.createEngine(params, (err: Object, engine: textToSpeech.TextToSpeechEngine): void => {
        this.voicePreparing = false;
        if (err !== null && err !== undefined) {
          this.voiceFailed = true;
          logger.warn(TAG, '语音引擎不可用，关注告警降级为双响: ' + String(err));
          return;
        }
        this.engine = engine;
        logger.info(TAG, '语音引擎已就绪');
      });
    } catch (error) {
      this.voicePreparing = false;
      this.voiceFailed = true;
      logger.warn(TAG, '语音引擎创建异常: ' + this.errorMessage(error));
    }
  }

  private speakParams(): textToSpeech.SpeakParams {
    return { requestId: 'fw-alert-' + Date.now().toString(), extraParams: {} };
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}