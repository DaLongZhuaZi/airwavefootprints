/** 编辑器路由参数：fleetId 为空表示新建，fromDeviceKey 非空表示从该设备反推。 */
export class FieldwatchSignatureEditorParam {
  public fleetId: string;
  public fromDeviceKey: string;
  constructor(fleetId: string = '', fromDeviceKey: string = '') { this.fleetId = fleetId; this.fromDeviceKey = fromDeviceKey; }
}

/** Hunt 路由参数：目标设备键。 */
export class FieldwatchHuntParam {
  public targetKey: string;
  constructor(targetKey: string = '') { this.targetKey = targetKey; }
}

export class FieldwatchRouteName {
  static readonly LIVE: string = 'fieldwatch.live';
  static readonly FILTERS: string = 'fieldwatch.filters';
  static readonly REPORTS: string = 'fieldwatch.reports';
  static readonly SETTINGS: string = 'fieldwatch.settings';
  static readonly DEVICE_DETAIL: string = 'fieldwatch.device_detail';
  static readonly SIT_DETAIL: string = 'fieldwatch.sit_detail';
  static readonly EXPORT: string = 'fieldwatch.export';
  static readonly SIGNATURE_CATALOG: string = 'fieldwatch.signatures';
  /** 横屏右栏的特征详情；竖屏不用它（竖屏走底部 sheet）。 */
  static readonly SIGNATURE_DETAIL: string = 'fieldwatch.signature_detail';
  static readonly SIGNATURE_EDITOR: string = 'fieldwatch.signature_editor';
  /** 关注列表：从特征库进入，也在卡片点击时直达。 */
  static readonly WATCHLIST: string = 'fieldwatch.watchlist';
  /** 反馈中心：设置页入口 + 深度链接直达。 */
  static readonly FEEDBACK: string = 'fieldwatch.feedback';
  static readonly HUNT: string = 'fieldwatch.hunt';
  // 日常首屏（daily）、找东西日常版（find）、我的设备看板（board）三条路由
  // **本次合并暂不注册**：它们指向的页面都依赖 feat 的 OwnDeviceProfile 体系，
  // 而那套体系已随「找东西专题」一并暂缓。留着常量会引用不存在的页面，编译必然断裂。
  /** 一键安防扫描（60 秒 → 汇总 → 分享卡）。 */
  static readonly SECURITY: string = 'fieldwatch.security';
  /** Wi-Fi 体检（信道结论 + 房间版）。 */
  static readonly WIFI_DOCTOR: string = 'fieldwatch.wifi_doctor';
  /** 设备图鉴（按 fleet 聚合历史）。 */
  static readonly DEX: string = 'fieldwatch.dex';
  /** 新面孔清单。 */
  static readonly NEW_FACES: string = 'fieldwatch.new_faces';
}
