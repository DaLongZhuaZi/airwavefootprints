import { SignatureClass, Sighting } from '../domain/FieldwatchModels';

/** 分类视图里一行是什么。 */
export enum ClassRowKind {
  /** 类别（可展开/收起）。 */
  CLASS = 0,
  /** 类别下的品牌小标题。 */
  BRAND = 1,
  /** 品牌下的设备。 */
  DEVICE = 2
}

/**
 * 分类视图的扁平化行。
 *
 * **为什么要扁平化**：原实现是三层嵌套的 `ForEach`（类别 -> 品牌 -> 设备），
 * 而且整个树挂在 `Scroll` + `Column` 下 —— 展开一个类别就把它的设备**全部构建**，
 * 且每次渲染都重建（`filteredClasses()` 返回新数组，`ForEach` 的 diff 失效）。
 * 而观测数据每秒都在变，于是整棵树每秒重建一次（实测反馈：分类页卡顿严重）。
 *
 * 扁平成一维之后交给 `LazyForEach`，可视区之外的行根本不构建。
 */
export class ClassRow {
  public kind: ClassRowKind;
  /** LazyForEach 的 key：必须唯一且稳定。 */
  public key: string;
  public cls: SignatureClass;
  /** 仅 BRAND / DEVICE 行有值。 */
  public brand: string;
  /** 仅 CLASS / BRAND 行有值。 */
  public count: number;
  /** 仅 DEVICE 行有值。 */
  public item: Sighting | undefined;

  constructor(kind: ClassRowKind, key: string, cls: SignatureClass, brand: string, count: number,
    item: Sighting | undefined) {
    this.kind = kind;
    this.key = key;
    this.cls = cls;
    this.brand = brand;
    this.count = count;
    this.item = item;
  }
}

/**
 * 分类行的数据源。
 *
 * 与 `SightingDataSource` 同一套思路：顺序没变就逐项 `onDataChange`（原地重画），
 * 顺序变了才整体 `onDataReloaded`。分类视图的分组很少变，
 * 于是每秒的观测刷新基本都走「逐项」这条便宜路径。
 */
export class ClassRowDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: ClassRow[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): ClassRow { return this.items[index]; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) this.listeners.splice(at, 1);
  }

  apply(next: ClassRow[]): void {
    if (this.sameKeys(next)) {
      this.items = next;
      this.listeners.forEach((listener: DataChangeListener): void => {
        for (let i: number = 0; i < this.items.length; i += 1) listener.onDataChange(i);
      });
      return;
    }
    this.items = next;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }

  private sameKeys(next: ClassRow[]): boolean {
    if (next.length !== this.items.length) return false;
    for (let i: number = 0; i < next.length; i += 1) {
      if (next[i].key !== this.items[i].key) return false;
    }
    return true;
  }
}