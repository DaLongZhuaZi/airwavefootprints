export enum NGFNotificationType {
  BASIC = 0,
  LONG_TEXT = 1,
  MULTILINE = 2,
  PICTURE = 3,
  PROGRESS = 4,
  CUSTOM = 5
}

export class NGFNotificationRequest {
  id: number;
  title: string;
  content: string;
  type: NGFNotificationType;
  
  progressValue: number;
  progressMax: number;
  isOngoing: boolean;
  /**
   * 通知通道类型，取 `notificationManager.SlotType` 的**数值**；0 表示交给系统默认通道。
   *
   * 用数值而不是 kit 里的枚举：契约层不引入 `@kit.NotificationKit` 依赖。
   *
   * **长时任务的伴随通知必须带上系统给的那个 slot** —— `startBackgroundRunning` 返回的
   * `ContinuousTaskNotification.slotType` 就是它。通道对不上时，系统不把这条通知
   * 当作长时任务通知，用户仍然可以把它划掉。
   */
  slotType: number = 0;

  // 扩展属性
  longText?: string;
  lines?: Array<string>;
  templateName?: string;
  templateData?: Record<string, Object>;
  
  constructor(
    id: number, 
    title: string, 
    content: string, 
    type: NGFNotificationType = NGFNotificationType.BASIC,
    progressValue: number = 0, 
    progressMax: number = 0, 
    isOngoing: boolean = false
  ) {
    this.id = id;
    this.title = title;
    this.content = content;
    this.type = type;
    this.progressValue = progressValue;
    this.progressMax = progressMax;
    this.isOngoing = isOngoing;
  }
}

export interface ISystemNotificationManager {
  requestPermission(): Promise<boolean>;
  /** 通知是否已启用；UI 用它显示真实状态（用户可能在系统设置里随时关掉）。 */
  isEnabled(): Promise<boolean>;
  publish(request: NGFNotificationRequest): Promise<void>;
  cancel(id: number): Promise<void>;
  /**
   * 撤销**本应用的全部通知**。
   *
   * 用于启动期清理。进程被杀时（崩溃 / 强制停止 / 从最近任务划掉），
   * 上一次运行留下的通知不会被撤销：
   *   - 关注告警的 id 只存在内存 Map 里，重启后连「要撤哪些 id」都无从知道；
   *   - 运行状态通知的伴随 id 由系统每次申请时分配，上一个 id 同样没有持久化。
   * 于是旧通知会一直挂在通知栏，与新会话的通知并存。
   *
   * **只能在启动期、任何 publish 之前调用** —— 它不分 id，会连同本次刚发的通知一起清掉。
   */
  cancelAll(): Promise<void>;
}
