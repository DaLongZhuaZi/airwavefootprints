import { RadioKind } from '../domain/FieldwatchModels';
import { FieldwatchRadarPoint } from './FieldwatchUiState';

/**
 * 雷达上的一个显示节点：要么是单个信号，要么是一个聚合气泡。
 *
 * **关键约束：位移只影响显示，不影响真实位置。**
 * `originX/originY` 是该信号按真实强度算出的归一化坐标（决定它在哪一圈），
 * `x/y` 是力导向去重叠之后的显示坐标。
 * 半径仍然只由强度决定 —— 否则「离圆心越近信号越强」这条语义就被破坏了。
 */
export class FieldwatchRadarNode {
  public key: string;
  /** 显示坐标（归一化），力导向松弛后可能偏离原始位置。 */
  public x: number;
  public y: number;
  /** 原始坐标（归一化），由真实强度决定，用于体现圈层语义。 */
  public originX: number;
  public originY: number;
  /** 聚合数量；1 表示单点。 */
  public count: number;
  /** 单点的原始数据（聚合时为第一个成员，仅用于取种类/颜色）。 */
  public sample: FieldwatchRadarPoint;
  /** 成员 key，点击气泡时展开。 */
  public memberKeys: string[];
  /** 气泡标题，如「5GHz WiFi」；单点为空。 */
  public clusterLabel: string;

  constructor(key: string, x: number, y: number, count: number, sample: FieldwatchRadarPoint) {
    this.key = key;
    this.x = x;
    this.y = y;
    this.originX = x;
    this.originY = y;
    this.count = count;
    this.sample = sample;
    this.memberKeys = [];
    this.clusterLabel = '';
  }
  isCluster(): boolean { return this.count > 1; }
}

/** 把强度映射到圈层序号（与 buildRadarPoints 的半径映射一致）。 */
function ringOf(point: FieldwatchRadarPoint): number {
  const normalized: number = Math.max(0, Math.min(1, (-30 - point.rssi) / 70));
  const distance: number = 0.12 + normalized * 0.88;
  return Math.max(0, Math.min(7, Math.floor(distance / 0.125)));
}

/** 频段/种类的可读名称，用于气泡标题。 */
function bucketLabel(point: FieldwatchRadarPoint): string {
  if (point.kind === RadioKind.WIFI) {
    return point.frequencyMhz >= 5000 ? '5GHz Wi-Fi' : '2.4GHz Wi-Fi';
  }
  return 'BLE';
}

/**
 * 力导向聚类。
 *
 * 1. **分箱**：按（圈层, 角度扇区, 种类与频段）分箱 —— 同一箱代表
 *    「同一信号区间里的同类设备」，这是用户说的「多设备在同一信号区间密集」。
 * 2. 箱内成员数 >= minClusterSize 时聚合成一个气泡，显示 `[+N 台] <标签>`。
 *    **门槛是 2 而不是 3** —— 2 个同圈同扇区同频段的设备几乎必然完全重叠，
    此时合成一个「+2 台」气泡远比两个图标压在一起可读（实测反馈）。
 * 3. **力导向去重叠**：其余单点两两之间若距离小于 minGap，沿连线互相推开，
 *    迭代若干次。纯聚类不够 —— 不同箱但不属于同类的点仍可能重叠。
 *
 * 去重叠只写 `x/y`，`originX/originY` 保持不变，因此圈层语义不受影响。
 */
export function buildRadarNodes(points: Array<FieldwatchRadarPoint>, minClusterSize: number = 2): Array<FieldwatchRadarNode> {
  const sectors: number = 12;
  const buckets: Map<string, Array<FieldwatchRadarPoint>> = new Map();
  points.forEach((point: FieldwatchRadarPoint): void => {
    const angle: number = Math.atan2(point.y - 0.5, point.x - 0.5);
    const sector: number = Math.floor(((angle + Math.PI) / (Math.PI * 2)) * sectors) % sectors;
    const bucketKey: string = ringOf(point).toString() + '|' + sector.toString() + '|' + bucketLabel(point);
    const list: Array<FieldwatchRadarPoint> | undefined = buckets.get(bucketKey);
    if (list === undefined) {
      const created: Array<FieldwatchRadarPoint> = [];
      created.push(point);
      buckets.set(bucketKey, created);
    } else {
      list.push(point);
    }
  });
  const nodes: Array<FieldwatchRadarNode> = [];
  buckets.forEach((members: Array<FieldwatchRadarPoint>, bucketKey: string): void => {
    if (members.length >= minClusterSize) {
      let sumX: number = 0;
      let sumY: number = 0;
      members.forEach((item: FieldwatchRadarPoint): void => { sumX += item.x; sumY += item.y; });
      const node: FieldwatchRadarNode = new FieldwatchRadarNode(
        'cluster:' + bucketKey, sumX / members.length, sumY / members.length, members.length, members[0]);
      members.forEach((item: FieldwatchRadarPoint): void => { node.memberKeys.push(item.key); });
      node.clusterLabel = bucketLabel(members[0]);
      nodes.push(node);
    } else {
      members.forEach((item: FieldwatchRadarPoint): void => {
        const node: FieldwatchRadarNode = new FieldwatchRadarNode(item.key, item.x, item.y, 1, item);
        node.memberKeys.push(item.key);
        nodes.push(node);
      });
    }
  });
  const merged: Array<FieldwatchRadarNode> = mergeNearbySingles(nodes);
  relaxNodes(merged);
  return merged;
}

/**
 * 把**互相贴得很近的单点**也并成气泡。
 *
 * ## 为什么还需要这一道
 *
 * 分箱是按「圈层 × 12 扇区 × 种类频段」做的 —— 每个扇区 30°。
 * 两台设备只要**跨在扇区边界两侧**，哪怕几乎重叠也永远分不到同一箱，
 * 于是画面上一堆信号挤在一起却一个气泡都没有（实测反馈「聚合点不是很聚合」）。
 *
 * 这一道按**实际距离**合并，与分箱无关，正好补上边界情形。
 *
 * 阈值取 `minGap` 的 0.7 倍：比「判为重叠」的距离略小，
 * 避免把视觉上分得开的点也吞进气泡 —— 那会让用户觉得气泡在乱吸。
 */
export function mergeNearbySingles(nodes: Array<FieldwatchRadarNode>): Array<FieldwatchRadarNode> {
  const threshold: number = 0.085 * 0.7;
  const used: boolean[] = [];
  for (let i: number = 0; i < nodes.length; i += 1) used.push(false);
  const out: Array<FieldwatchRadarNode> = [];
  for (let i: number = 0; i < nodes.length; i += 1) {
    if (used[i]) continue;
    const head: FieldwatchRadarNode = nodes[i];
    // 气泡本身不再吸收别人：否则会在一次刷新里滚雪球，把半个屏幕并成一个球。
    if (head.isCluster()) { out.push(head); used[i] = true; continue; }
    const group: Array<FieldwatchRadarNode> = [];
    group.push(head);
    used[i] = true;
    for (let j: number = i + 1; j < nodes.length; j += 1) {
      if (used[j]) continue;
      const other: FieldwatchRadarNode = nodes[j];
      if (other.isCluster()) continue;
      const dx: number = other.x - head.x;
      const dy: number = other.y - head.y;
      if (Math.sqrt(dx * dx + dy * dy) > threshold) continue;
      group.push(other);
      used[j] = true;
    }
    if (group.length < 2) { out.push(head); continue; }
    let sumX: number = 0;
    let sumY: number = 0;
    group.forEach((node: FieldwatchRadarNode): void => { sumX += node.x; sumY += node.y; });
    const merged: FieldwatchRadarNode = new FieldwatchRadarNode(
      'near:' + head.key, sumX / group.length, sumY / group.length, group.length, head.sample);
    group.forEach((node: FieldwatchRadarNode): void => {
      node.memberKeys.forEach((key: string): void => { merged.memberKeys.push(key); });
    });
    merged.clusterLabel = bucketLabel(head.sample);
    out.push(merged);
  }
  return out;
}

/**
 * 力导向去重叠：重叠的节点互相推开，迭代收敛。
 *
 * 只改显示坐标；同时把偏移限制在一个上限内，避免把点推到完全错误的圈层上。
 */
export function relaxNodes(nodes: Array<FieldwatchRadarNode>, passes: number = 28): void {
  const minGap: number = 0.085;
  // 偏移上限从 0.06 放宽到 0.11：原来两点几乎重合时推不开（位移上限太小），
  // 表现就是「两个图标完全叠在一起」。放宽后仍不至于跑出本圈层 ——
  // 圈层间距是 0.125，0.11 以内不会跨圈。
  const maxDrift: number = 0.11;
  // 均匀网格加速：只有落在相邻格子里的点才可能重叠。
  // 朴素两两比较是 O(passes × n²) —— 138 个点、28 轮 = 每秒 53 万次开方，
  // 全部跑在 UI 线程上，是雷达卡顿的主要来源之一。
  const cell: number = minGap;
  for (let pass: number = 0; pass < passes; pass += 1) {
    const grid: Map<string, number[]> = new Map();
    for (let index: number = 0; index < nodes.length; index += 1) {
      const key: string = Math.floor(nodes[index].x / cell).toString() + ',' + Math.floor(nodes[index].y / cell).toString();
      const bucket: number[] | undefined = grid.get(key);
      if (bucket === undefined) grid.set(key, [index]); else bucket.push(index);
    }
    let moved: boolean = false;
    for (let i: number = 0; i < nodes.length; i += 1) {
      const a: FieldwatchRadarNode = nodes[i];
      const cx: number = Math.floor(a.x / cell);
      const cy: number = Math.floor(a.y / cell);
      for (let ox: number = -1; ox <= 1; ox += 1) {
        for (let oy: number = -1; oy <= 1; oy += 1) {
          const bucket: number[] | undefined = grid.get((cx + ox).toString() + ',' + (cy + oy).toString());
          if (bucket === undefined) continue;
          for (let bi: number = 0; bi < bucket.length; bi += 1) {
            const j: number = bucket[bi];
            if (j <= i) continue;
            const b: FieldwatchRadarNode = nodes[j];
            let dx: number = b.x - a.x;
            let dy: number = b.y - a.y;
            let distance: number = Math.sqrt(dx * dx + dy * dy);
            if (distance >= minGap) continue;
            if (distance < 0.0001) { dx = 0.001; dy = 0.001; distance = 0.0014; }
            const push: number = (minGap - distance) / 2;
            const ux: number = dx / distance;
            const uy: number = dy / distance;
            a.x -= ux * push;
            a.y -= uy * push;
            b.x += ux * push;
            b.y += uy * push;
            moved = true;
          }
        }
      }
    }
    // 一整轮都没有任何点需要移动，说明已经收敛，提前结束。
    if (!moved) break;
  }
  // 收敛后把位移钳制在允许范围内，保证节点不会跑到与强度无关的位置。
  nodes.forEach((node: FieldwatchRadarNode): void => {
    node.x = node.originX + Math.max(-maxDrift, Math.min(maxDrift, node.x - node.originX));
    node.y = node.originY + Math.max(-maxDrift, Math.min(maxDrift, node.y - node.originY));
  });
}