/**
 * 人工排查清单（P3-2 第 3 项）。纯逻辑 + 可单测。
 *
 * 为什么需要它：扫描只能发现「正在广播且特征明显」的设备。
 * 不联网 / 纯本地存储 / 关机 / 走 GSM 的设备原理上扫不到 ——
 * 那部分只能靠人看。文档 3.3 明确要求「扫不出来的部分由人工清单补」。
 *
 * 清单按**房间**组织、逐项打勾：用户在酒店房间里照着走一遍，比看一堆免责声明有用。
 */

/** 一条排查项。 */
export class ManualCheckItem {
  /** 稳定 id（落库与打勾状态用）。 */
  public id: string = '';
  /** 文案资源键。 */
  public labelKey: string = '';
  /** 一句怎么做（资源键）；空串表示不需要说明。 */
  public howKey: string = '';
  constructor(id: string = '', labelKey: string = '', howKey: string = '') {
    this.id = id;
    this.labelKey = labelKey;
    this.howKey = howKey;
  }
}

/** 一组排查项（一个检查主题）。 */
export class ManualCheckGroup {
  public id: string = '';
  public titleKey: string = '';
  public items: ManualCheckItem[] = [];
  constructor(id: string = '', titleKey: string = '') { this.id = id; this.titleKey = titleKey; }
}

/**
 * 内置排查清单。
 *
 * 覆盖文档 3.3 点名的四类手法：镜头反光、异常安装点、断电后残电/发热、夜视红外。
 * **全部是「看得见 / 摸得到」的物理检查**，不需要任何权限，也不联网。
 */
export function manualCheckGroups(): ManualCheckGroup[] {
  const groups: ManualCheckGroup[] = [];

  const lens: ManualCheckGroup = new ManualCheckGroup('lens', 'app.string.fieldwatch_check_lens_title');
  lens.items.push(new ManualCheckItem('lens_dark', 'app.string.fieldwatch_check_lens_dark',
    'app.string.fieldwatch_check_lens_dark_how'));
  lens.items.push(new ManualCheckItem('lens_reflect', 'app.string.fieldwatch_check_lens_reflect',
    'app.string.fieldwatch_check_lens_reflect_how'));
  lens.items.push(new ManualCheckItem('lens_smoke', 'app.string.fieldwatch_check_lens_smoke', ''));
  lens.items.push(new ManualCheckItem('lens_socket', 'app.string.fieldwatch_check_lens_socket', ''));
  lens.items.push(new ManualCheckItem('lens_mirror', 'app.string.fieldwatch_check_lens_mirror',
    'app.string.fieldwatch_check_lens_mirror_how'));
  lens.items.push(new ManualCheckItem('lens_vent', 'app.string.fieldwatch_check_lens_vent', ''));
  groups.push(lens);

  const power: ManualCheckGroup = new ManualCheckGroup('power', 'app.string.fieldwatch_check_power_title');
  power.items.push(new ManualCheckItem('power_heat', 'app.string.fieldwatch_check_power_heat',
    'app.string.fieldwatch_check_power_heat_how'));
  power.items.push(new ManualCheckItem('power_ir', 'app.string.fieldwatch_check_power_ir',
    'app.string.fieldwatch_check_power_ir_how'));
  power.items.push(new ManualCheckItem('power_standby', 'app.string.fieldwatch_check_power_standby', ''));
  groups.push(power);

  const network: ManualCheckGroup = new ManualCheckGroup('network', 'app.string.fieldwatch_check_network_title');
  network.items.push(new ManualCheckItem('network_unknown', 'app.string.fieldwatch_check_network_unknown',
    'app.string.fieldwatch_check_network_unknown_how'));
  network.items.push(new ManualCheckItem('network_router', 'app.string.fieldwatch_check_network_router', ''));
  groups.push(network);

  return groups;
}

/** 全部条目 id（用于打勾状态的完整集合）。 */
export function allCheckIds(): string[] {
  const ids: string[] = [];
  manualCheckGroups().forEach((group: ManualCheckGroup): void => {
    group.items.forEach((item: ManualCheckItem): void => { ids.push(item.id); });
  });
  return ids;
}

/** 进度：已勾 / 总数。 */
export function checkProgress(done: string[]): number[] {
  const ids: string[] = allCheckIds();
  let doneCount: number = 0;
  ids.forEach((id: string): void => {
    if (done.indexOf(id) >= 0) doneCount += 1;
  });
  return [doneCount, ids.length];
}

/**
 * 打勾状态编解码（落设置存储用）。
 *
 * 用换行分隔的 id 列表而不是 JSON：条目 id 都是短的 ASCII，
 * 换行分隔既省字节又不必处理转义；坏数据自然退化成「一条都没勾」。
 */
export function encodeChecks(done: string[]): string {
  return done.join('\n');
}

export function decodeChecks(text: string): string[] {
  if (text.length === 0) return [];
  return text.split('\n').filter((item: string): boolean => item.trim().length > 0);
}

/** 切换一项的勾选状态，返回新数组（不改入参，便于 UI 判断是否需要落盘）。 */
export function toggleCheck(done: string[], id: string): string[] {
  const next: string[] = [];
  let found: boolean = false;
  done.forEach((item: string): void => {
    if (item === id) { found = true; return; }
    next.push(item);
  });
  if (!found) next.push(id);
  return next;
}
