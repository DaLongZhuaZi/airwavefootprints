/**
 * 设备命名回退链（P3-1 第 2 项）。
 *
 * 为什么需要它：main 的 `FindPage.titleOf` 与 `FindClaim` 只有**一级回退** ——
 * 名字为空就显示「未命名设备」。而名字来源只有两条，且两条都经常为空：
 *   · BLE 广播名：很多设备广播里根本不带名字。要名字得连 GATT 读 0x2A00，
 *     那是主动连接，违背「只接收不连接」底线，**不做**；
 *   · 系统配对名：`getRemoteDeviceName` 对纯 BLE 配对经常不响应。
 * 于是无名条目越积越多，用户看到一屏「未命名设备」，会以为是 bug。
 *
 * 本模块把手头已有的**弱身份**串成一条回退链，让无名率大幅下降。
 * 它是纯逻辑：不读系统、不碰 UI，所有输入由调用方传入，因此每一级都能单测。
 *
 * 段位顺序（从强到弱，**不可随意调换**）：
 *   ① 自定义名 / 认领名  —— 用户亲手起的，最强
 *   ② 系统配对名          —— 系统里真实存在的名字（BLE + 星闪双通道）
 *   ③ 广播名 / Wi-Fi SSID —— 设备自己声明的
 *   ④ 特征库 fleet 名     —— 我们从广播特征认出的型号
 *   ⑤ CoD 通用名          —— 蓝牙类别（蓝牙耳机 / 智能手表…）
 *   ⑥ 厂商名 + 类别       —— 「华为 · 蓝牙耳机」
 *   ⑦ 兜底「未命名设备 · 尾号 XXXX」—— 用地址后 4 位区分多台无名设备
 *
 * **为什么兜底必须带尾号**：一屏出现三台「未命名设备」时，用户无法区分、
 * 也无法据此认领；尾号至少让他能在系统蓝牙列表里对上号。
 */

import { RadioKind } from './FieldwatchModels';

/** 命名来源，用于 UI 解释「这个名字是怎么来的」与单测断言。 */
export enum NameSource {
  /** 用户自定义 / 认领时起的名字。 */
  CUSTOM = 'custom',
  /** 系统配对名（BLE 或星闪）。 */
  PAIRED = 'paired',
  /** 广播名或 Wi-Fi SSID。 */
  BROADCAST = 'broadcast',
  /** 特征库 fleet 名。 */
  SIGNATURE = 'signature',
  /** Class of Device 推出的通用名。 */
  DEVICE_CLASS = 'device_class',
  /** 厂商名 + 类别。 */
  VENDOR = 'vendor',
  /** 兜底：未命名设备 · 尾号。 */
  FALLBACK = 'fallback'
}

/** 命名结果：名字 + 来源（UI 可据此加一句说明）。 */
export class NamedDevice {
  public label: string;
  public source: NameSource;
  constructor(label: string = '', source: NameSource = NameSource.FALLBACK) {
    this.label = label;
    this.source = source;
  }
  /** 是否只是兜底（UI 需要额外解释「该设备广播里没有名字」）。 */
  isFallback(): boolean { return this.source === NameSource.FALLBACK; }
}

/**
 * 命名所需的一切实力输入。
 *
 * 全部字段都可为空 —— 这正是回退链存在的理由；空值一律跳过该级。
 */
export class NameInputs {
  /** 用户自定义 / 认领名。 */
  public customName: string = '';
  /** 系统配对名（BLE + 星闪双通道查回来的那个）。 */
  public pairedName: string = '';
  /** 广播名（BLE）或 SSID（Wi-Fi）。 */
  public broadcastName: string = '';
  /** 命中的特征库 fleet 名（首个命中即可）。 */
  public fleetName: string = '';
  /** Class of Device 推出的通用名，如「蓝牙耳机」。 */
  public deviceClassLabel: string = '';
  /** 厂商名，如「华为」。 */
  public vendorName: string = '';
  /** 类别名，如「蓝牙耳机」（与 deviceClassLabel 同源或由签名类别翻译）。 */
  public categoryLabel: string = '';
  /** 设备地址（用于兜底尾号）。 */
  public address: string = '';
  public kind: RadioKind = RadioKind.BLE;
  constructor() {}
}

/**
 * 兜底尾号的长度。
 *
 * 取 4 位：太短（2 位）在十几台设备时就可能撞号，太长（6 位）又不像人能读的编号。
 * 4 位十六进制 = 65536 种，足够区分一屏里的无名设备。
 */
export const NAME_TAIL_LENGTH: number = 4;

/**
 * 从地址取尾号。
 *
 * 地址可能是 `AA:BB:CC:DD:EE:FF` 也可能是 `ble:AA:BB:...` 或 Wi-Fi 的 BSSID，
 * 统一先剥掉非十六进制字符再取末尾，保证三种来源尾号口径一致。
 * 空地址返回空串（调用方据此不拼尾号）。
 */
export function addressTail(address: string): string {
  const hexOnly: string = address.replace(/[^0-9A-Fa-f]/g, '').toUpperCase();
  if (hexOnly.length === 0) return '';
  if (hexOnly.length <= NAME_TAIL_LENGTH) return hexOnly;
  return hexOnly.substring(hexOnly.length - NAME_TAIL_LENGTH);
}

/**
 * 非空即采用：回退链每一级的共同判据。
 *
 * 单独抽出来是为了让「空串与纯空白都算没有」这条规则只写一遍 ——
 * 曾经出现过只判 `length > 0` 而把 " "（一个空格）当成有效名字的情况。
 */
function usable(value: string): boolean {
  return value.trim().length > 0;
}

/**
 * 按回退链算出一个可显示的名字。
 *
 * 返回 `NamedDevice` 而不是裸字符串：UI 需要知道这是不是兜底值，
 * 兜底时要额外说明「该设备广播里没有名字」，否则用户会以为是 bug。
 */
export function resolveDeviceName(inputs: NameInputs): NamedDevice {
  if (usable(inputs.customName)) return new NamedDevice(inputs.customName.trim(), NameSource.CUSTOM);
  if (usable(inputs.pairedName)) return new NamedDevice(inputs.pairedName.trim(), NameSource.PAIRED);
  if (usable(inputs.broadcastName)) return new NamedDevice(inputs.broadcastName.trim(), NameSource.BROADCAST);
  if (usable(inputs.fleetName)) return new NamedDevice(inputs.fleetName.trim(), NameSource.SIGNATURE);
  if (usable(inputs.deviceClassLabel)) return new NamedDevice(inputs.deviceClassLabel.trim(), NameSource.DEVICE_CLASS);
  // 厂商 + 类别：两者都有才拼（只给厂商名「华为」对区分帮助不大，只给类别又太泛）。
  if (usable(inputs.vendorName) && usable(inputs.categoryLabel)) {
    return new NamedDevice(inputs.vendorName.trim() + ' · ' + inputs.categoryLabel.trim(), NameSource.VENDOR);
  }
  // 只剩厂商名时仍然比「未命名设备」有用（能立刻知道是哪家）。
  if (usable(inputs.vendorName)) return new NamedDevice(inputs.vendorName.trim(), NameSource.VENDOR);
  return new NamedDevice(fallbackLabel(inputs.address), NameSource.FALLBACK);
}

/**
 * 兜底名：`未命名设备 · 尾号 XXXX`。
 *
 * 不带尾号时返回的是**不含编号的兜底键**（由 UI 翻译成「未命名设备」）——
 * 领域层不写中文文案，这里返回的是结构化标记，具体拼法见 `fallbackDisplay`。
 */
export function fallbackLabel(address: string): string {
  const tail: string = addressTail(address);
  return tail.length > 0 ? 'unnamed:' + tail : 'unnamed';
}

/** 兜底标记是否带尾号。 */
export function fallbackHasTail(label: string): boolean {
  return label.startsWith('unnamed:');
}

/** 从兜底标记里取尾号；没有尾号返回空串。 */
export function fallbackTail(label: string): string {
  if (!fallbackHasTail(label)) return '';
  return label.substring('unnamed:'.length);
}
