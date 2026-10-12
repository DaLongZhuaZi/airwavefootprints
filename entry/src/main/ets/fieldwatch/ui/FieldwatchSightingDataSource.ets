import { Sighting } from '../domain/FieldwatchModels';

/**
 * 实时列表的数据源，供 `LazyForEach` 使用。
 *
 * **为什么需要它**：实时页的强度 / 时间线 / 信号轨迹三个视图原先是
 * `Scroll` + `Column` + `ForEach`，一次构建**全部**观测行 ——
 * 几百台设备时首屏开销与滚动掉帧都很明显。
 * `LazyForEach` 只构建可视区内的行，滚动时才按需创建。
 *
 * 与 `SignatureFleetDataSource` 同一模式；差别是它每秒都会被 `reload()` 一次
 * （观测数据本来就每秒在变），所以 `getData` 必须保持 O(1)。
 */
export class SightingDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: Sighting[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): Sighting { return this.items[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) this.listeners.splice(at, 1);
  }

  /**
   * 用新的列表内容整体替换并通知刷新。
   *
   * **只在「顺序真的变了、且用户没有正在滑动」时使用。**
   * `onDataReloaded()` 会让 `LazyForEach` 丢弃 key 缓存、把可视行整棵节点树重建，
   * 连带整表重新测量与布局 —— 每秒一次就是滑动掉帧的来源。
   */
  reload(next: Sighting[]): void {
    this.items = next;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }

  /**
   * 更新数据。**「及时刷新」与「滑动流畅」能同时成立，靠的就是这里分三种情况。**
   *
   * 1. **顺序没变**（只有 RSSI / 时间这类值在变）：逐项 `onDataChange`。
   *    它只让对应行**原地重画**，保留节点树与 key 缓存，不触发整表重测量；
   * 2. **顺序变了、但用户正在滑动**：按 key 对齐，**只换值、不改位置**。
   *    行在手指底下跳本身就是要修的体验问题，而且重排必须重建节点；
   *    值仍然每秒刷新 —— 滑完抬手后由第 3 种情况恢复排序；
   * 3. **顺序变了、且没在滑动**：整体 `reload()`。
   *
   * @param freezeOrder 是否冻结顺序（用户正在滑动）
   */
  apply(next: Sighting[], freezeOrder: boolean): void {
    if (this.sameKeys(next)) {
      this.items = next;
      this.notifyEachChanged();
      return;
    }
    if (freezeOrder) {
      this.mergeValuesByKey(next);
      return;
    }
    this.reload(next);
  }

  /** 顺序是否与当前完全一致（长度 + 逐项 key）。 */
  private sameKeys(next: Sighting[]): boolean {
    if (next.length !== this.items.length) return false;
    for (let i: number = 0; i < next.length; i += 1) {
      if (next[i].key !== this.items[i].key) return false;
    }
    return true;
  }

  /** 逐项通知：原地重画，不重建节点树。 */
  private notifyEachChanged(): void {
    this.listeners.forEach((listener: DataChangeListener): void => {
      for (let i: number = 0; i < this.items.length; i += 1) listener.onDataChange(i);
    });
  }

  /** 只换值、不改位置：按 key 把新对象放到原来的下标上。 */
  private mergeValuesByKey(next: Sighting[]): void {
    const byKey: Map<string, Sighting> = new Map<string, Sighting>();
    next.forEach((item: Sighting): void => { byKey.set(item.key, item); });
    this.listeners.forEach((listener: DataChangeListener): void => {
      for (let i: number = 0; i < this.items.length; i += 1) {
        const fresh: Sighting | undefined = byKey.get(this.items[i].key);
        if (fresh === undefined || fresh === this.items[i]) continue;
        this.items[i] = fresh;
        listener.onDataChange(i);
      }
    });
  }
}