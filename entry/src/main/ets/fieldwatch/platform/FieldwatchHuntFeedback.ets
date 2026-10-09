import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';
import { logger, uiContextManager } from 'ngf_framework';

const TAG: string = 'FieldwatchHuntFeedback';
const TICK_RAWFILE: string = 'fieldwatch-tick.wav';
const MAX_STREAMS: number = 4;

/** 现场搜寻的短促反馈；具体实现可替换，领域层不依赖系统包。 */
export interface IFieldwatchHuntFeedback {
  prepare(): Promise<void>;
  hapticAvailable(): boolean;
  soundAvailable(): boolean;
  tick(durationMs: number): void;
  release(): void;
}

/**
 * Geiger tick 的触感实现。
 * 设备不支持触感或调用失败时静默降级，不影响搜寻的视觉反馈。
 */
export class FieldwatchHuntHapticFeedback {
  private supported: boolean = false;
  private busy: boolean = false;

  constructor() {
    try {
      this.supported = vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_SHARP);
    } catch (error) {
      this.supported = false;
      logger.warn(TAG, '触感能力查询失败，节拍降级为纯视觉: ' + this.errorMessage(error));
    }
  }

  available(): boolean { return this.supported; }

  tick(durationMs: number): void {
    if (!this.supported || this.busy) return;
    const duration: number = durationMs <= 0 ? 20 : (durationMs > 60 ? 60 : durationMs);
    this.busy = true;
    try {
      const effect: vibrator.VibrateEffect = { type: 'time', duration: duration };
      const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'alarm' };
      vibrator.startVibration(effect, attribute)
        .then((): void => { this.busy = false; })
        .catch((error: Object): void => { this.busy = false; logger.debug(TAG, '节拍振动失败: ' + this.errorMessage(error)); });
    } catch (error) {
      this.busy = false;
      logger.debug(TAG, '节拍振动异常: ' + this.errorMessage(error));
    }
  }

  release(): void {
    try {
      void vibrator.stopVibration(vibrator.VibratorStopMode.VIBRATOR_STOP_MODE_TIME).catch((): void => {});
    } catch (error) {
      logger.debug(TAG, '停止振动异常: ' + this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/**
 * Geiger tick 的音频实现。
 * 资源随应用打包（rawfile），不联网；加载失败时整体降级，不影响搜寻。
 *
 * **关注列表的双响告警复用本类**（`FieldwatchWatchAlert`）：两者共用同一份音频资源，
 * 靠节奏区分 —— Hunt 是单次 tick，关注告警是两声短促。
 */
export class FieldwatchHuntSoundFeedback {
  private pool: media.SoundPool | undefined = undefined;
  private soundId: number = -1;
  private preparing: boolean = false;
  private failed: boolean = false;

  available(): boolean { return this.soundId >= 0; }

  async prepare(): Promise<boolean> {
    if (this.soundId >= 0) return true;
    if (this.failed || this.preparing) return false;
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return false;
    this.preparing = true;
    try {
      const info: audio.AudioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION, rendererFlags: 0 };
      const pool: media.SoundPool = await media.createSoundPool(MAX_STREAMS, info);
      const descriptor = await context.resourceManager.getRawFd(TICK_RAWFILE);
      const id: number = await pool.load(descriptor.fd, descriptor.offset, descriptor.length);
      await context.resourceManager.closeRawFd(TICK_RAWFILE);
      this.pool = pool;
      this.soundId = id;
      this.preparing = false;
      logger.info(TAG, 'Geiger tick 音频已加载: soundId=' + id.toString());
      return true;
    } catch (error) {
      this.preparing = false;
      this.failed = true;
      logger.warn(TAG, 'Geiger tick 音频加载失败，节拍降级为触感/视觉: ' + this.errorMessage(error));
      return false;
    }
  }

  play(): void {
    const pool: media.SoundPool | undefined = this.pool;
    if (pool === undefined || this.soundId < 0) return;
    try {
      const params: media.PlayParameters = { loop: 0, rate: 1, leftVolume: 0.9, rightVolume: 0.9, priority: 0 };
      void pool.play(this.soundId, params).catch((error: Object): void => { logger.debug(TAG, 'tick 播放失败: ' + this.errorMessage(error)); });
    } catch (error) {
      logger.debug(TAG, 'tick 播放异常: ' + this.errorMessage(error));
    }
  }

  release(): void {
    const pool: media.SoundPool | undefined = this.pool;
    this.pool = undefined;
    this.soundId = -1;
    if (pool === undefined) return;
    try {
      void pool.release().catch((): void => {});
    } catch (error) {
      logger.debug(TAG, '释放音频池异常: ' + this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/**
 * 组合反馈：音频与触感同时给出，任一不可用都不影响另一个。
 * 关注列表的双响提示与 Hunt 的短促 tick 是两套独立告警，本类只负责 Hunt。
 */
export class FieldwatchHuntCombinedFeedback implements IFieldwatchHuntFeedback {
  private readonly haptic: FieldwatchHuntHapticFeedback = new FieldwatchHuntHapticFeedback();
  private readonly sound: FieldwatchHuntSoundFeedback = new FieldwatchHuntSoundFeedback();

  async prepare(): Promise<void> {
    await this.sound.prepare();
  }

  hapticAvailable(): boolean { return this.haptic.available(); }
  soundAvailable(): boolean { return this.sound.available(); }

  tick(durationMs: number): void {
    this.haptic.tick(durationMs);
    this.sound.play();
  }

  release(): void {
    this.haptic.release();
    this.sound.release();
  }
}
