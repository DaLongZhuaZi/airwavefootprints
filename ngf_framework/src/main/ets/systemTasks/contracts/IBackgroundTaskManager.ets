export interface IBackgroundTaskManager {
  startContinuousTask(taskId: string, title: string, content: string): Promise<boolean>;
  /**
   * 发布/刷新常驻状态通知。
   *
   * 长时任务必须伴随用户可见的通知（鸿蒙官方设计要求）。固定 ID，重复调用为覆盖更新，
   * 因此调用方可以按需刷新内容。
   */
  publishStateNotification(title: string, content: string): Promise<void>;
  stopContinuousTask(): Promise<boolean>;
}
