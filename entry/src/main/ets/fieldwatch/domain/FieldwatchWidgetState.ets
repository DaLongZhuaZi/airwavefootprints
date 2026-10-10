/**
 * 卡片要显示的状态快照。
 *
 * **应用侧写、FormExtensionAbility 侧读**，两侧共用这一个定义 ——
 * 卡片数据是跨进程的，形状写两遍必然漂移。
 *
 * 为什么方向是「应用写、卡片侧拉」：`formProvider` 没有「列出本应用全部卡片」的接口，
 * 主应用拿不到自己的 formId；而 FormExtensionAbility 天然拿得到 formId。
 */
export class FieldwatchWidgetState {
  /** 允许后台运行 **且** 应用确实在后台。前台时为 false，卡片显示「app 未运行」。 */
  public running: boolean = false;
  /** 心跳（epoch 毫秒）。应用被杀后心跳会停，卡片据此判超时。 */
  public heartbeatAt: number = 0;
  public paused: boolean = false;
  public ble: number = 0;
  public wifi: number = 0;
  public nearLink: number = 0;
  /** 大卡片：最近一次命中的关注目标。 */
  public watchLabel: string = '';
  public watchRssi: number = 0;
  public watchAgeSec: number = -1;
  /** 大卡片：最近一次命中的特征族。 */
  public familyLabel: string = '';
  public familyAgeSec: number = -1;
}

/** 心跳超过这个秒数就认为应用已不在运行。15 秒一次心跳，给足 6 倍余量。 */
export const WIDGET_HEARTBEAT_TIMEOUT_SEC: number = 90;

/**
 * 解析卡片状态。**任何异常都退回默认值**（`running = false`）。
 *
 * 卡片侧绝不能因为一段坏 JSON 就渲染失败 —— 那会显示成一张空白卡片，
 * 比显示「app 未运行」糟糕得多。
 */
export function parseWidgetState(json: string): FieldwatchWidgetState {
  const state: FieldwatchWidgetState = new FieldwatchWidgetState();
  if (json.length === 0) return state;
  try {
    const raw: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    state.running = raw.running === true;
    state.heartbeatAt = typeof raw.heartbeatAt === 'number' ? raw.heartbeatAt as number : 0;
    state.paused = raw.paused === true;
    state.ble = typeof raw.ble === 'number' ? raw.ble as number : 0;
    state.wifi = typeof raw.wifi === 'number' ? raw.wifi as number : 0;
    state.nearLink = typeof raw.nearLink === 'number' ? raw.nearLink as number : 0;
    state.watchLabel = typeof raw.watchLabel === 'string' ? raw.watchLabel as string : '';
    state.watchRssi = typeof raw.watchRssi === 'number' ? raw.watchRssi as number : 0;
    state.watchAgeSec = typeof raw.watchAgeSec === 'number' ? raw.watchAgeSec as number : -1;
    state.familyLabel = typeof raw.familyLabel === 'string' ? raw.familyLabel as string : '';
    state.familyAgeSec = typeof raw.familyAgeSec === 'number' ? raw.familyAgeSec as number : -1;
  } catch (error) {
    return new FieldwatchWidgetState();
  }
  return state;
}

/** 心跳是否仍然新鲜；不新鲜说明应用已经不在运行。 */
export function widgetHeartbeatFresh(state: FieldwatchWidgetState, nowMs: number): boolean {
  if (state.heartbeatAt <= 0) return false;
  return (nowMs - state.heartbeatAt) <= WIDGET_HEARTBEAT_TIMEOUT_SEC * 1000;
}
/** 卡片数据里用到的键；两侧共用，避免字符串写两遍。 */
export class FieldwatchWidgetKeys {
  static readonly DIMENSION: string = 'dimension';
  static readonly RUNNING: string = 'running';
  static readonly STATUS: string = 'statusText';
  static readonly DETAIL: string = 'detailText';
  static readonly UPDATED: string = 'updatedText';
}

/** 秒数 -> 「N 秒前 / N 分钟前 / N 小时前」。 */
function ageText(seconds: number): string {
  if (seconds < 0) return '—';
  if (seconds < 60) return seconds.toString() + ' 秒前';
  if (seconds < 3600) return Math.round(seconds / 60).toString() + ' 分钟前';
  return Math.round(seconds / 3600).toString() + ' 小时前';
}

/** epoch 毫秒 -> 「HH:MM」。 */
function clockText(nowMs: number): string {
  const now: Date = new Date(nowMs);
  const hh: string = now.getHours().toString().padStart(2, '0');
  const mm: string = now.getMinutes().toString().padStart(2, '0');
  return hh + ':' + mm;
}

/**
 * 由状态快照算出卡片要显示的**全部文本**。
 *
 * **放在共享层而不是卡片扩展里**：应用侧也要用它 ——
 * 应用能主动 `updateForm` 时（拿到扩展登记的 formId 之后），
 * 它必须产出与扩展**完全相同**的数据；
 * 两边各算一份必然漂移（这正是本仓库反复踩的「写两遍」）。
 */
export function buildWidgetCardData(state: FieldwatchWidgetState, dimension: string, nowMs: number): Record<string, string> {
  const fresh: boolean = state.running && widgetHeartbeatFresh(state, nowMs);
  const data: Record<string, string> = {};
  data[FieldwatchWidgetKeys.DIMENSION] = dimension;
  data[FieldwatchWidgetKeys.RUNNING] = fresh ? 'true' : 'false';
  data[FieldwatchWidgetKeys.UPDATED] = clockText(nowMs);
  if (!fresh) {
    data[FieldwatchWidgetKeys.STATUS] = 'app 未运行';
    data[FieldwatchWidgetKeys.DETAIL] = '开启后台运行并切到后台后，这里会显示扫描情况';
    return data;
  }
  let status: string = 'BLE ' + state.ble.toString() + ' · Wi-Fi ' + state.wifi.toString()
    + ' · 星闪 ' + state.nearLink.toString();
  if (state.paused) status += ' · 已暂停';
  data[FieldwatchWidgetKeys.STATUS] = status;
  const parts: string[] = [];
  if (state.watchLabel.length > 0) {
    parts.push('关注 · ' + state.watchLabel + ' ' + state.watchRssi.toString() + ' dBm · ' + ageText(state.watchAgeSec));
  }
  if (state.familyLabel.length > 0) {
    parts.push('特征族 · ' + state.familyLabel + ' · ' + ageText(state.familyAgeSec));
  }
  data[FieldwatchWidgetKeys.DETAIL] = parts.length > 0 ? parts.join('\n') : '尚未命中关注目标或特征族';
  return data;
}
/** 扩展登记的卡片条目：formId 与它的尺寸。 */
export class FieldwatchWidgetForm {
  public id: string = '';
  public dimension: string = '2*2';
  constructor(id: string = '', dimension: string = '2*2') { this.id = id; this.dimension = dimension; }
}

/** 卡片登记表在设置存储里的键。 */
export const WIDGET_FORMS_KEY: string = 'fieldwatch.widgetForms';

/** 编码成 `formId|dimension` 逐行文本（**不用 JSON 对象**，避免 ArkTS 动态键访问）。 */
export function encodeWidgetForms(forms: FieldwatchWidgetForm[]): string {
  const lines: string[] = [];
  forms.forEach((form: FieldwatchWidgetForm): void => { lines.push(form.id + '|' + form.dimension); });
  return lines.join('\n');
}

export function parseWidgetForms(text: string): FieldwatchWidgetForm[] {
  const result: FieldwatchWidgetForm[] = [];
  if (text.length === 0) return result;
  text.split('\n').forEach((line: string): void => {
    const at: number = line.indexOf('|');
    if (at <= 0) return;
    result.push(new FieldwatchWidgetForm(line.substring(0, at), line.substring(at + 1)));
  });
  return result;
}
