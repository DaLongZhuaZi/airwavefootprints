import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { IBackgroundTaskManager } from '../contracts/IBackgroundTaskManager';
import { uiContextManager } from '../../platformOhos/UIContextManager';
import { logger } from '../../utils/Logger';
import { ngfSystemNotificationManager } from './SystemNotificationManagerFacade';
import { NGFNotificationRequest, NGFNotificationType } from '../contracts/ISystemNotificationManager';

const TAG: string = 'BackgroundTaskManagerFacade';
/**
 * 后台长时任务通知的固定 ID。
 *
 * 鸿蒙要求长时任务必须伴随一条**用户可见的通知** —— 系统据此让用户知道
 * 「这个应用正在后台持续运行」，也是系统允许其存活的前提。
 * 用固定 ID 是为了让后续刷新覆盖同一条通知，而不是堆出一串。
 */
const CONTINUOUS_TASK_NOTIFICATION_ID: number = 100001;

class BackgroundTaskManagerFacade implements IBackgroundTaskManager {
  async startContinuousTask(taskId: string, title: string, content: string): Promise<boolean> {
    const context = uiContextManager.getFullAbilityContext();
    if (!context) {
      logger.error(TAG, '无 UIAbilityContext，无法启动后台长时任务');
      return false;
    }
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: context.abilityInfo.bundleName,
            abilityName: context.abilityInfo.name
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const wa: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      
      await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wa);
      // 官方设计要求：长时任务必须发一条常驻通知，告知用户应用正在后台运行。
      // 此前这里收了 title/content 却完全没用，等于「静默保活」—— 既不符合规范，
      // 用户也无从知道应用还在跑。
      await this.publishStateNotification(title, content);
      logger.info(TAG, '后台长时任务已启动: TaskID=' + taskId);
      return true;
    } catch (e) {
      logger.error(TAG, '启动后台长时任务失败: ' + this.describe(e));
      return false;
    }
  }

  /**
   * 发布/刷新常驻状态通知。
   *
   * 使用固定 ID，因此重复调用是「覆盖更新」而不是新增，
   * 调用方可以按任意节奏刷新内容（例如每秒更新一次观测计数）。
   */
  async publishStateNotification(title: string, content: string): Promise<void> {
    const request: NGFNotificationRequest = new NGFNotificationRequest(
      CONTINUOUS_TASK_NOTIFICATION_ID, title, content, NGFNotificationType.BASIC);
    await ngfSystemNotificationManager.publish(request);
  }
  /** 把平台异常转成可读文本；直接拼对象只会得到「[object Object]」。 */
  private describe(e: Object): string {
    const business: BusinessError = e as BusinessError;
    if (business !== undefined && business.code !== undefined) {
      return business.code.toString() + ' ' + business.message;
    }
    return String(e);
  }
  async stopContinuousTask(): Promise<boolean> {
    const context = uiContextManager.getFullAbilityContext();
    if (!context) {
      logger.error(TAG, '无 UIAbilityContext，无法停止后台长时任务');
      return false;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      logger.info(TAG, '后台长时任务已停止');
      return true;
    } catch (e) {
      // 「本来就没在运行」是正常状态而不是故障：调用方会在启动时无条件同步一次，
      // 此时任务尚未启动，stop 必然抛错。按错误上报只会制造假告警。
      const message: string = this.describe(e);
      // 实测错误码 9800005：'The application has not applied for a continuous task.'
      // 即「本来就没申请过长时任务」，属于正常状态，不应报错。
      if (message.indexOf('9800005') >= 0 || message.indexOf('not running') >= 0
        || message.indexOf('No running') >= 0 || message.indexOf('not applied') >= 0
        || message.indexOf('not start') >= 0 || message.indexOf('16000011') >= 0) {
        logger.info(TAG, '后台长时任务本就未运行，无需停止');
        return true;
      }
      logger.warn(TAG, '停止后台长时任务失败: ' + message);
      return false;
    }
  }
}

export const ngfBackgroundTaskManager: IBackgroundTaskManager = new BackgroundTaskManagerFacade();
