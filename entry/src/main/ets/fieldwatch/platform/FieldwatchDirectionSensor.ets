import sensor from '@ohos.sensor';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchDirectionSensor';
const SAMPLE_INTERVAL_NS: number = 100000000;

export interface IFieldwatchDirectionSensorListener {
  onHeading(heading: number): void;
  onRotation(rateRadiansPerSecond: number): void;
  onSensorError(message: string): void;
}

export class FieldwatchDirectionSensorListener implements IFieldwatchDirectionSensorListener {
  private readonly headingHandler: (heading: number) => void;
  private readonly rotationHandler: (rateRadiansPerSecond: number) => void;
  private readonly errorHandler: (message: string) => void;

  constructor(headingHandler: (heading: number) => void, rotationHandler: (rateRadiansPerSecond: number) => void,
    errorHandler: (message: string) => void) {
    this.headingHandler = headingHandler;
    this.rotationHandler = rotationHandler;
    this.errorHandler = errorHandler;
  }

  onHeading(heading: number): void { this.headingHandler(heading); }
  onRotation(rateRadiansPerSecond: number): void { this.rotationHandler(rateRadiansPerSecond); }
  onSensorError(message: string): void { this.errorHandler(message); }
}

/** Short-lived sensor bridge used only while a single target is being tracked. */
export class FieldwatchDirectionSensor {
  private listener: IFieldwatchDirectionSensorListener | undefined = undefined;
  private active: boolean = false;

  private readonly headingCallback = (data: sensor.OrientationResponse): void => {
    const listener: IFieldwatchDirectionSensorListener | undefined = this.listener;
    if (this.active && Number.isFinite(data.alpha) && listener !== undefined) listener.onHeading(data.alpha);
  };

  private readonly gyroCallback = (data: sensor.GyroscopeResponse): void => {
    if (!this.active) return;
    const rate: number = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
    const listener: IFieldwatchDirectionSensorListener | undefined = this.listener;
    if (Number.isFinite(rate) && listener !== undefined) listener.onRotation(rate);
  };

  start(listener: IFieldwatchDirectionSensorListener): boolean {
    if (this.active) return true;
    this.listener = listener;
    try {
      sensor.on(sensor.SensorId.ORIENTATION, this.headingCallback, { interval: SAMPLE_INTERVAL_NS });
      sensor.on(sensor.SensorId.GYROSCOPE, this.gyroCallback, { interval: SAMPLE_INTERVAL_NS });
      this.active = true;
      logger.info(TAG, '相对测向传感器已启动');
      return true;
    } catch (error) {
      this.stop();
      const message: string = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, '相对测向不可用: ' + message);
      listener.onSensorError(message);
      return false;
    }
  }

  stop(): void {
    this.active = false;
    try { sensor.off(sensor.SensorId.ORIENTATION, this.headingCallback); } catch (error) {
      logger.debug(TAG, '停止方向传感器失败: ' + String(error));
    }
    try { sensor.off(sensor.SensorId.GYROSCOPE, this.gyroCallback); } catch (error) {
      logger.debug(TAG, '停止陀螺仪失败: ' + String(error));
    }
    this.listener = undefined;
  }
}
