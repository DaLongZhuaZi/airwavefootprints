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
  static readonly SIGNATURE_EDITOR: string = 'fieldwatch.signature_editor';
  static readonly HUNT: string = 'fieldwatch.hunt';
}
