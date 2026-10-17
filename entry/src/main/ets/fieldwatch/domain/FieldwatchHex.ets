import { logger } from 'ngf_framework';

/**
 * 字节 ↔ 十六进制互转的快速实现（P8）。
 *
 * ## 为什么单独抽一层
 *
 * 广播解析是每秒上百次的路径：一条 BLE 广播包里外要转 3~8 次十六进制。
 * 原来的写法是 `bytes[i].toString(16).toUpperCase()` 加 `result += ...`：
 * **每个字节 2~3 次临时字符串分配**，字符串拼接本身还是 O(n²) 拷贝。
 * 能量录制里 `hexOfBytes` + `bytesHex` + `bytesOfHex` 合计占 4.1% 单核，就是这么来的。
 *
 * 这里改成「256 项查表 + 数组 join」：分配次数从 O(n) 降到 2 次，复杂度回到 O(n)。
 * 三个扫码器（BLE / Wi-Fi / 星闪）共用同一份实现，避免各写一份又各自走样。
 */
const HEX_DIGITS: string = '0123456789ABCDEF';
const BYTE_HEX: string[] = buildByteHex();

function buildByteHex(): string[] {
  const table: string[] = [];
  for (let value: number = 0; value < 256; value += 1) {
    table.push(HEX_DIGITS.charAt((value >> 4) & 0x0F) + HEX_DIGITS.charAt(value & 0x0F));
  }
  return table;
}

/** 整段字节 → 大写十六进制。空数组返回空串。 */
export function bytesToHex(bytes: Uint8Array): string {
  const length: number = bytes.length;
  if (length === 0) return '';
  const parts: string[] = [];
  for (let index: number = 0; index < length; index += 1) parts.push(BYTE_HEX[bytes[index]]);
  return parts.join('');
}

/**
 * 取 [start, end) 区间的十六进制，**不复制子数组**。
 *
 * AD 解析里每个字段都是「一段连续字节」，原来写 `hexOfBytes(payload.slice(a, b))`：
 * 先分配一个子 `Uint8Array`，再逐字节拼串 —— 两次分配。区间版只剩最终字符串一次。
 */
export function bytesRangeToHex(bytes: Uint8Array, start: number, end: number): string {
  const from: number = start < 0 ? 0 : start;
  const to: number = end > bytes.length ? bytes.length : end;
  if (to <= from) return '';
  const parts: string[] = [];
  for (let index: number = from; index < to; index += 1) parts.push(BYTE_HEX[bytes[index]]);
  return parts.join('');
}

/**
 * 十六进制串 → 字节。忽略 `:` 分隔符；非法字符按 0 处理（与原实现保持一致，不抛错）。
 */
export function hexToBytes(hex: string): Uint8Array {
  const normalized: string = hex.indexOf(':') >= 0 ? hex.replace(/:/g, '') : hex;
  const length: number = Math.floor(normalized.length / 2);
  if (length === 0) return new Uint8Array(0);
  const bytes: Uint8Array = new Uint8Array(length);
  for (let index: number = 0; index < length; index += 1) {
    const parsed: number = parseInt(normalized.substring(index * 2, index * 2 + 2), 16);
    bytes[index] = Number.isNaN(parsed) ? 0 : parsed;
  }
  return bytes;
}

/** 单字节 → 两位大写十六进制（用于拼接少量固定宽度的字段，如公司 ID）。 */
export function byteToHex(value: number): string {
  if (value < 0 || value > 255) {
    logger.warn('FieldwatchHex', 'byteToHex 越界: ' + value.toString());
    return '00';
  }
  return BYTE_HEX[value];
}
