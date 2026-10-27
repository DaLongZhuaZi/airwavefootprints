/**
 * 图鉴网格的数据源（P3-1 第 4 项性能修复）。
 *
 * 为什么需要它：原来 Grid 用 `ForEach` 渲染 611 个格子 —— 进页时一次性全部建出来，
 * 首帧就要实例化六百多个组件，肉眼可见地卡。改成 `LazyForEach` 后只建视口内的。
 *
 * 数据源本身只做「按下标给条目」，不含任何业务判断 ——
 * 排序与稀有度都由 `FieldwatchDex` 算好，这里只负责搬运。
 */

import { DexEntry } from '../domain/FieldwatchDex';

/** IDataSource 的最小实现（ArkUI 要求 notifyDataReload 等四个通知方法）。 */
export class DexEntryDataSource implements IDataSource {
  private entries: DexEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.entries.length; }

  getData(index: number): DexEntry {
    return this.entries[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  /** 整份替换并通知刷新（图鉴是整体重算的，没有增量更新的必要）。 */
  reset(entries: DexEntry[]): void {
    this.entries = entries;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }

  /** 当前条目数（页面用于判断空态）。 */
  size(): number { return this.entries.length; }
}
