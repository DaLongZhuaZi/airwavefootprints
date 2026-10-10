import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
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

/**
 * 申请长时任务时使用的用途字符串。
 *
 * **必须与 `entry/src/main/module.json5` 的 `backgroundModes` 一致**，
 * 否则申请会被系统拒绝（`9800005 Continuous task verification failed`）。
 *
 * 为什么是 `bluetoothInteraction` 而不是 `dataTransfer`：
 * 本应用是**被动无线电扫描**（BLE 为主），不是上传下载。
 * `dataTransfer` 的官方要求是「必须用 live view 通知持续更新进度，
 * 超过 10 分钟不更新就会被系统取消」（`SYSTEM_CANCEL_DATA_TRANSFER_NOT_UPDATE`）——
 * 我们的场景既没有进度可报，也不该被按传输速率考核。
 *
 * 另外两个候选都用不了：`taskKeeping` 限 PC/2in1 或需受限 ACL 权限，
 * `specialScenarioProcessing` 同样需要受限权限，普通应用申请不到。
 */
const CONTINUOUS_TASK_MODES: string[] = ['bluetoothInteraction'];

class BackgroundTaskManagerFacade implements IBackgroundTaskManager {
  /** 系统分配的伴随通知 id；-1 表示当前没有长时任务。 */
  private notificationId: number = -1;
  /** 系统要求的通知通道类型；发伴随通知时必须带上。 */
  private slotType: number = 0;
  private running: boolean = false;

  async startContinuousTask(taskId: string, title: string, content: string): Promise<boolean> {
    const context = uiContextManager.getFullAbilityContext();
    if (!context) {
      logger.error(TAG, '无 UIAbilityContext，无法启动后台长时任务');
      return false;
    }
    // 已在运行：只刷新伴随通知内容，**不要重复申请**（重复申请会再起一个长时任务）。
    if (this.running) {
      await this.publishStateNotification(title, content);
      return true;
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
      
      // **必须用「返回 ContinuousTaskNotification」的重载。**
      //
      // 旧的三参重载（`bgMode, wantAgent`）返回 `void`，**拿不到系统分配的通知 id 与 slot** ——
      // 应用只能自己拍一个 id 去发普通通知，而那条通知不是长时任务伴随通知：
      // 用户能把它划掉，也会被「清除全部」清掉。这正是「通知不是常驻」的根因。
      //
      // 顺带记一笔：`isOngoing` / `isUnremovable` 在 API 26 的声明里都标注
      // 「Not supported currently.」—— 置上它们不会有任何效果，别再往那个方向查。
      const info: backgroundTaskManager.ContinuousTaskNotification =
        await backgroundTaskManager.startBackgroundRunning(context, CONTINUOUS_TASK_MODES, wa);
      this.notificationId = info.notificationId;
      this.slotType = info.slotType as number;
      this.running = true;
      await this.ensureSlot();
      // 官方设计要求：长时任务必须发一条用户可见的伴随通知。
      // 此前这里收了 title/content 却完全没用，等于「静默保活」—— 既不符合规范，
      // 用户也无从知道应用还在跑。
      await this.publishStateNotification(title, content);
      logger.info(TAG, '后台长时任务已启动: TaskID=' + taskId + ' 伴随通知 id=' + this.notificationId.toString()
        + ' slot=' + this.slotType.toString());
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
    // 优先用**系统分配的伴随通知 id**：只有带上它 + 对应 slot，
    // 这条通知才是「长时任务通知」，用户划不掉、也不会被「清除全部」清掉。
    // 没有长时任务时（异常路径）退回固定 id，仍然发得出去，只是不常驻。
    const id: number = this.notificationId >= 0 ? this.notificationId : CONTINUOUS_TASK_NOTIFICATION_ID;
    const request: NGFNotificationRequest = new NGFNotificationRequest(id, title, content, NGFNotificationType.BASIC);
    request.isOngoing = true;
    request.slotType = this.slotType;
    await ngfSystemNotificationManager.publish(request);
  }

  /**
   * 按系统要求的类型建通知通道。
   *
   * 通道已存在时 `addSlot` 会抛错 —— 那是正常状态（重复调用不该当成故障），
   * 因此按 debug 记录而不是告警。
   */
  private async ensureSlot(): Promise<void> {
    try {
      await notificationManager.addSlot(this.slotType as notificationManager.SlotType);
    } catch (e) {
      logger.debug(TAG, '通知通道已存在或无需新建: ' + this.describe(e));
    }
  }
  /** 撤销伴随通知并复位内部状态；没有伴随通知时是空操作。 */
  private async cancelCompanion(): Promise<void> {
    if (this.notificationId >= 0) {
      await ngfSystemNotificationManager.cancel(this.notificationId);
      this.notificationId = -1;
    }
    this.running = false;
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
      // 系统会随任务一起撤掉伴随通知；仍显式 cancel 一次，
      // 避免出现「任务已停、通知还挂在通知栏」的残留。
      await this.cancelCompanion();
      logger.info(TAG, '后台长时任务已停止，伴随通知已撤销');
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
        // 任务不在，但可能还留着上一次的伴随通知：一并清掉。
        await this.cancelCompanion();
        return true;
      }
      logger.warn(TAG, '停止后台长时任务失败: ' + message);
      return false;
    }
  }
}

export const ngfBackgroundTaskManager: IBackgroundTaskManager = new BackgroundTaskManagerFacade();
