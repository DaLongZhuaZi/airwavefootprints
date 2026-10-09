import { SignatureFleet } from '../domain/signatures/FieldwatchSignatureModels';

/**
 * 特征库列表的数据源，供 `LazyForEach` 使用。
 *
 * **为什么需要它**：原实现用 `Scroll` + `ForEach`，内置目录 244 条会**一次性全部构建**，
 * 每个行节点都带图标、多处文本和启用开关，首屏开销与滚动掉帧都很明显。
 * `LazyForEach` 只构建可视区内的行，滚动时才按需创建。
 *
 * 筛选/排序变化时调用 `reload()` 触发整体重载 —— 条数少（几百）时
 * 直接 `onDataReloaded` 比逐条 diff 更简单且开销可忽略。
 */
export class SignatureFleetDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: SignatureFleet[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): SignatureFleet { return this.items[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) this.listeners.splice(at, 1);
  }

  /** 用新的列表内容整体替换并通知刷新。 */
  reload(next: SignatureFleet[]): void {
    this.items = next;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}