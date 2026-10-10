import { ngfSettingsStoreFacade, logger } from 'ngf_framework';
import { AppSettings, FilterDefinition, FilterLogic, FilterPreset, RadioKind, SignatureClass, WatchTarget, foldedSignatureClass } from '../domain/FieldwatchModels';
import { signatureClassOf } from '../domain/signatures/FieldwatchSignatureModels';

const TAG: string = 'FieldwatchSettingsRepository';
const PRESETS_KEY: string = 'fieldwatch.filterPresets';
const FILTER_KEY: string = 'fieldwatch.filter';
const WATCHLIST_KEY: string = 'fieldwatch.watchlist';

export class FieldwatchSettingsRepository {
  load(): AppSettings {
    const settings: AppSettings = new AppSettings();
    settings.displayPaused = ngfSettingsStoreFacade.getBoolean('fieldwatch.displayPaused', settings.displayPaused);
    settings.darkMode = ngfSettingsStoreFacade.getBoolean('fieldwatch.darkMode', settings.darkMode);
    settings.keepScreenOn = ngfSettingsStoreFacade.getBoolean('fieldwatch.keepScreenOn', settings.keepScreenOn);
    settings.locationTagging = ngfSettingsStoreFacade.getBoolean('fieldwatch.locationTagging', settings.locationTagging);
    settings.privacyMode = ngfSettingsStoreFacade.getBoolean('fieldwatch.privacyMode', settings.privacyMode);
    settings.watchNotifications = ngfSettingsStoreFacade.getBoolean('fieldwatch.watchNotifications', settings.watchNotifications);
    settings.watchBeep = ngfSettingsStoreFacade.getBoolean('fieldwatch.watchBeep', settings.watchBeep);
    settings.watchVoice = ngfSettingsStoreFacade.getBoolean('fieldwatch.watchVoice', settings.watchVoice);
    settings.watchVoiceWhat = ngfSettingsStoreFacade.getString('fieldwatch.watchVoiceWhat', settings.watchVoiceWhat);
    settings.huntBeep = ngfSettingsStoreFacade.getBoolean('fieldwatch.huntBeep', settings.huntBeep);
    settings.huntVibrate = ngfSettingsStoreFacade.getBoolean('fieldwatch.huntVibrate', settings.huntVibrate);
    settings.showRssiBar = ngfSettingsStoreFacade.getBoolean('fieldwatch.showRssiBar', settings.showRssiBar);
    settings.showFleetName = ngfSettingsStoreFacade.getBoolean('fieldwatch.showFleetName', settings.showFleetName);
    settings.showFrequency = ngfSettingsStoreFacade.getBoolean('fieldwatch.showFrequency', settings.showFrequency);
    settings.showSeenTimes = ngfSettingsStoreFacade.getBoolean('fieldwatch.showSeenTimes', settings.showSeenTimes);
    settings.listCompactRows = ngfSettingsStoreFacade.getBoolean('fieldwatch.listCompactRows', settings.listCompactRows);
    settings.logLevel = ngfSettingsStoreFacade.getNumber('fieldwatch.logLevel', settings.logLevel);
    settings.backgroundScanning = ngfSettingsStoreFacade.getBoolean('fieldwatch.backgroundScanning', settings.backgroundScanning);
    settings.scanIntensity = ngfSettingsStoreFacade.getString('fieldwatch.scanIntensity', settings.scanIntensity);
    settings.liveMode = ngfSettingsStoreFacade.getString('fieldwatch.liveMode', settings.liveMode);
    settings.radarLabelFields = ngfSettingsStoreFacade.getString('fieldwatch.radarLabelFields', settings.radarLabelFields);
    settings.radarLabelFontSize = ngfSettingsStoreFacade.getNumber('fieldwatch.radarLabelFontSize', settings.radarLabelFontSize);
    settings.radarIconSize = ngfSettingsStoreFacade.getNumber('fieldwatch.radarIconSize', settings.radarIconSize);
    logger.debug(TAG, 'Fieldwatch 设置已加载');
    return settings;
  }

  save(settings: AppSettings): void {
    ngfSettingsStoreFacade.setBoolean('fieldwatch.displayPaused', settings.displayPaused);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.darkMode', settings.darkMode);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.keepScreenOn', settings.keepScreenOn);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.locationTagging', settings.locationTagging);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.privacyMode', settings.privacyMode);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.watchNotifications', settings.watchNotifications);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.watchBeep', settings.watchBeep);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.watchVoice', settings.watchVoice);
    ngfSettingsStoreFacade.setString('fieldwatch.watchVoiceWhat', settings.watchVoiceWhat);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.huntBeep', settings.huntBeep);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.huntVibrate', settings.huntVibrate);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.showRssiBar', settings.showRssiBar);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.showFleetName', settings.showFleetName);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.showFrequency', settings.showFrequency);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.showSeenTimes', settings.showSeenTimes);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.listCompactRows', settings.listCompactRows);
    ngfSettingsStoreFacade.setNumber('fieldwatch.logLevel', settings.logLevel);
    ngfSettingsStoreFacade.setBoolean('fieldwatch.backgroundScanning', settings.backgroundScanning);
    ngfSettingsStoreFacade.setString('fieldwatch.scanIntensity', settings.scanIntensity);
    ngfSettingsStoreFacade.setString('fieldwatch.liveMode', settings.liveMode);
    ngfSettingsStoreFacade.setString('fieldwatch.radarLabelFields', settings.radarLabelFields);
    ngfSettingsStoreFacade.setNumber('fieldwatch.radarLabelFontSize', settings.radarLabelFontSize);
    ngfSettingsStoreFacade.setNumber('fieldwatch.radarIconSize', settings.radarIconSize);
    logger.debug(TAG, 'Fieldwatch 设置已保存');
  }

  /**
   * 导出设置备份。
   *
   * **按 §12.7 补齐四类内容**：设置开关、当前过滤器、过滤预设、命名设备与签名关注项。
   * 此前只导出了 9 个开关，另外三类虽然在本地各有独立存储键，却没进备份 ——
   * 用户导出再导入会**静默丢掉**过滤器、预设和整个关注列表。
   *
   * 格式保持逐行 `key=value`；JSON 值由 `JSON.stringify` 产出（不含换行，安全）。
   * 解析用 `indexOf('=')`（取第一个），因此值里含 `=` 也不会截断。
   * **不含** catalog、日志与 GPS 记录（§12.7 明确排除）。
   */
  exportBackup(settings: AppSettings): string {
    let text: string = 'fieldwatch_settings_v1\n' +
      'displayPaused=' + settings.displayPaused.toString() + '\n' +
      'darkMode=' + settings.darkMode.toString() + '\n' +
      'keepScreenOn=' + settings.keepScreenOn.toString() + '\n' +
      'locationTagging=' + settings.locationTagging.toString() + '\n' +
      'privacyMode=' + settings.privacyMode.toString() + '\n' +
      'watchNotifications=' + settings.watchNotifications.toString() + '\n' +
      'watchBeep=' + settings.watchBeep.toString() + '\n' +
      'watchVoice=' + settings.watchVoice.toString() + '\n' +
      'watchVoiceWhat=' + settings.watchVoiceWhat + '\n' +
      'huntBeep=' + settings.huntBeep.toString() + '\n' +
      'huntVibrate=' + settings.huntVibrate.toString() + '\n' +
      'showRssiBar=' + settings.showRssiBar.toString() + '\n' +
      'showFleetName=' + settings.showFleetName.toString() + '\n' +
      'showFrequency=' + settings.showFrequency.toString() + '\n' +
      'showSeenTimes=' + settings.showSeenTimes.toString() + '\n' +
      'listCompactRows=' + settings.listCompactRows.toString() + '\n' +
      'logLevel=' + settings.logLevel.toString() + '\n' +
      'backgroundScanning=' + settings.backgroundScanning.toString() + '\n' +
      'scanIntensity=' + settings.scanIntensity + '\n' +
      'liveMode=' + settings.liveMode + '\n';
    text += 'radarLabelFields=' + settings.radarLabelFields + '\n';
    text += 'radarLabelFontSize=' + settings.radarLabelFontSize.toString() + '\n';
    text += 'radarIconSize=' + settings.radarIconSize.toString() + '\n';
    const filter: string = ngfSettingsStoreFacade.getString(FILTER_KEY, '');
    if (filter.length > 0) text += 'filter=' + filter + '\n';
    const presets: string = ngfSettingsStoreFacade.getString(PRESETS_KEY, '');
    if (presets.length > 0) text += 'presets=' + presets + '\n';
    const watchlist: string = ngfSettingsStoreFacade.getString(WATCHLIST_KEY, '');
    if (watchlist.length > 0) text += 'watchlist=' + watchlist + '\n';
    return text;
  }

  importBackup(content: string): boolean {
    const lines: string[] = content.split('\n');
    if (lines.length === 0 || lines[0].trim() !== 'fieldwatch_settings_v1') return false;
    const settings: AppSettings = this.load();
    lines.forEach((line: string): void => {
      const separator: number = line.indexOf('=');
      if (separator <= 0) return;
      const key: string = line.substring(0, separator);
      const value: string = line.substring(separator + 1);
      if (key === 'displayPaused') settings.displayPaused = value === 'true';
      else if (key === 'darkMode') settings.darkMode = value === 'true';
      else if (key === 'keepScreenOn') settings.keepScreenOn = value === 'true';
      else if (key === 'locationTagging') settings.locationTagging = value === 'true';
      else if (key === 'privacyMode') settings.privacyMode = value === 'true';
      else if (key === 'watchNotifications') settings.watchNotifications = value === 'true';
      else if (key === 'watchBeep') settings.watchBeep = value === 'true';
      else if (key === 'watchVoice') settings.watchVoice = value === 'true';
      else if (key === 'watchVoiceWhat') settings.watchVoiceWhat = value;
      else if (key === 'huntBeep') settings.huntBeep = value === 'true';
      else if (key === 'huntVibrate') settings.huntVibrate = value === 'true';
      else if (key === 'showRssiBar') settings.showRssiBar = value === 'true';
      else if (key === 'showFleetName') settings.showFleetName = value === 'true';
      else if (key === 'showFrequency') settings.showFrequency = value === 'true';
      else if (key === 'showSeenTimes') settings.showSeenTimes = value === 'true';
    else if (key === 'listCompactRows') settings.listCompactRows = value === 'true';
    else if (key === 'logLevel') {
      // 内联解析：这个文件没有 toInt 助手，也不想为一行引入依赖。
      // 解析失败退回 2（WARN）—— 与 `AppSettings.logLevel` 的默认值同口径。
      const parsed: number = parseInt(value, 10);
      settings.logLevel = isNaN(parsed) ? 2 : parsed;
    }
      else if (key === 'backgroundScanning') settings.backgroundScanning = value === 'true';
      else if (key === 'scanIntensity') settings.scanIntensity = value;
      else if (key === 'liveMode') settings.liveMode = value;
      else if (key === 'radarLabelFields') settings.radarLabelFields = value;
      else if (key === 'radarLabelFontSize') settings.radarLabelFontSize = Number.parseFloat(value);
      else if (key === 'radarIconSize') settings.radarIconSize = Number.parseFloat(value);
      // 三类结构化内容：**先校验再落盘**，坏数据不应该污染本地设置。
      // 旧版备份里没有这三行，缺失时保持本地原值不动。
      else if (key === 'filter') { if (this.isJsonObject(value)) ngfSettingsStoreFacade.setString(FILTER_KEY, value); }
      else if (key === 'presets') { if (this.isJsonArray(value)) ngfSettingsStoreFacade.setString(PRESETS_KEY, value); }
      else if (key === 'watchlist') { if (this.isJsonArray(value)) ngfSettingsStoreFacade.setString(WATCHLIST_KEY, value); }
    });
    this.save(settings);
    return true;
  }

  /** 只在能解析成对象时才接受，避免把半截 JSON 写进设置。 */
  private isJsonObject(text: string): boolean {
    try { const parsed: Object = JSON.parse(text) as Object; return parsed !== null && parsed !== undefined; }
    catch (error) { logger.warn(TAG, '备份中的对象字段无法解析，已跳过'); return false; }
  }

  /** 只在能解析成数组时才接受。 */
  private isJsonArray(text: string): boolean {
    try { const parsed: Object = JSON.parse(text) as Object; return Array.isArray(parsed); }
    catch (error) { logger.warn(TAG, '备份中的数组字段无法解析，已跳过'); return false; }
  }

  /** 当前生效的筛选（重启后恢复）。 */
  saveFilterState(filter: FilterDefinition): void {
    ngfSettingsStoreFacade.setString(FILTER_KEY, JSON.stringify(filter));
  }
  loadFilterState(): FilterDefinition | undefined {
    const content: string = ngfSettingsStoreFacade.getString(FILTER_KEY, '');
    if (content.length === 0) return undefined;
    try {
      return this.normalizeFilter(JSON.parse(content) as FilterDefinition);
    } catch (error) {
      logger.warn(TAG, '读取当前筛选失败: ' + String(error));
      return undefined;
    }
  }  /** 首次启动引导是否已完成。 */
  /**
   * 卡片状态：应用写、FormExtensionAbility 读。
   *
   * 放在设置存储里而不是另开一份文件：两侧本来就读同一个 preferences，
   * 复用它可以少一条「两个沙箱路径是否一致」的不确定性。
   */
  saveWidgetState(json: string): void { ngfSettingsStoreFacade.setString('fieldwatch.widgetState', json); }
  loadWidgetState(): string { return ngfSettingsStoreFacade.getString('fieldwatch.widgetState', ''); }
  /** 卡片清单：FormExtensionAbility 登记，主应用读来主动推送。 */
  loadWidgetForms(): string { return ngfSettingsStoreFacade.getString('fieldwatch.widgetForms', ''); }

  loadOnboardingSeen(): boolean { return ngfSettingsStoreFacade.getBoolean('fieldwatch.onboardingSeen', false); }
  saveOnboardingSeen(value: boolean): void { ngfSettingsStoreFacade.setBoolean('fieldwatch.onboardingSeen', value); }
  /** 用户主动选择「先用基础功能」后不再自动弹权限说明。 */
  loadPermissionPromptDismissed(): boolean { return ngfSettingsStoreFacade.getBoolean('fieldwatch.permissionPromptDismissed', false); }
  savePermissionPromptDismissed(value: boolean): void { ngfSettingsStoreFacade.setBoolean('fieldwatch.permissionPromptDismissed', value); }
  listFilterPresets(): FilterPreset[] {
    const content: string = ngfSettingsStoreFacade.getString(PRESETS_KEY, '');
    if (content.length > 0) {
      try {
        const values: FilterPreset[] = JSON.parse(content) as FilterPreset[];
        const result: FilterPreset[] = [];
        values.forEach((item: FilterPreset): void => {
          if (item === undefined || item === null || item.name === undefined || item.name.length === 0) return;
          result.push(new FilterPreset(item.name, this.normalizeFilter(item.filter)));
        });
        return result;
      } catch (error) {
        logger.warn(TAG, '读取筛选预设列表失败: ' + String(error));
        return [];
      }
    }
    const legacy: FilterDefinition | undefined = this.readLegacyPreset();
    if (legacy === undefined) return [];
    const migrated: FilterPreset[] = [new FilterPreset('预设 1', legacy)];
    this.writePresets(migrated);
    logger.info(TAG, '旧版单预设已迁移为具名预设');
    return migrated;
  }

  saveFilterPreset(name: string, filter: FilterDefinition): boolean {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) return false;
    const presets: FilterPreset[] = this.listFilterPresets();
    const next: FilterPreset[] = presets.filter((item: FilterPreset): boolean => item.name !== trimmed);
    next.push(new FilterPreset(trimmed, filter));
    this.writePresets(next);
    return true;
  }

  deleteFilterPreset(name: string): void {
    const presets: FilterPreset[] = this.listFilterPresets();
    this.writePresets(presets.filter((item: FilterPreset): boolean => item.name !== name));
  }

  hasFilterPreset(name: string): boolean {
    return this.listFilterPresets().some((item: FilterPreset): boolean => item.name === name);
  }

  loadFilterPreset(name: string): FilterDefinition | undefined {
    const found: FilterPreset | undefined = this.listFilterPresets().find((item: FilterPreset): boolean => item.name === name);
    return found === undefined ? undefined : found.filter;
  }

  private writePresets(presets: FilterPreset[]): void {
    ngfSettingsStoreFacade.setString(PRESETS_KEY, JSON.stringify(presets));
  }

  private readLegacyPreset(): FilterDefinition | undefined {
    const content: string = ngfSettingsStoreFacade.getString('fieldwatch.filterPreset', '');
    if (content.length === 0) return undefined;
    try {
      return this.normalizeFilter(JSON.parse(content) as FilterDefinition);
    } catch (error) {
      logger.warn(TAG, '旧版筛选预设解析失败: ' + String(error));
      return undefined;
    }
  }

  /** 默认预设：只看已匹配签名且强度不差的目标，作为现场起步条件。 */
  loadDefaultPreset(): FilterDefinition {
    const filter: FilterDefinition = new FilterDefinition();
    filter.minimumRssi = -85;
    filter.namedOnly = true;
    return filter;
  }

  /** 只保留字符串元素；磁盘内容不可信，非字符串一律丢弃。 */
  private static stringList(source: string[] | undefined): string[] {
    const result: string[] = [];
    if (source === undefined || source === null) return result;
    for (let index: number = 0; index < source.length; index += 1) {
      const item: string = source[index];
      if (typeof item === 'string' && item.length > 0) result.push(item);
    }
    return result;
  }
  /** 类别列表同样走统一映射，避免出现无法识别的类别字符串。 */
  private static classList(source: SignatureClass[] | undefined): SignatureClass[] {
    const result: SignatureClass[] = [];
    if (source === undefined || source === null) return result;
    for (let index: number = 0; index < source.length; index += 1) {
      const raw: string = String(source[index]);
      if (raw.length === 0) continue;
      const folded: SignatureClass = foldedSignatureClass(signatureClassOf(raw));
      if (result.indexOf(folded) < 0) result.push(folded);
    }
    return result;
  }
  /** 把任意来源的过滤定义收敛成完整对象；缺字段一律按默认值补齐。 */
  normalizeFilter(value: FilterDefinition): FilterDefinition {
    {
      const filter: FilterDefinition = new FilterDefinition();
      filter.logic = value.logic === FilterLogic.OR ? FilterLogic.OR : FilterLogic.AND;
      // 三种无线电种类都要能恢复；漏掉星闪会让「仅星闪」在重启后静默变回「全部」。
      filter.radioKind = value.radioKind === RadioKind.WIFI ? RadioKind.WIFI
        : (value.radioKind === RadioKind.BLE ? RadioKind.BLE
          : (value.radioKind === RadioKind.NEARLINK ? RadioKind.NEARLINK : undefined));
      filter.minimumRssi = value.minimumRssi;
      filter.signatureId = value.signatureId || '';
      // 类别有 20 个，必须走统一映射，否则预设会静默丢掉类别。
      const rawClass: string = value.signatureClass === undefined || value.signatureClass === null ? '' : String(value.signatureClass);
      filter.signatureClass = rawClass.length === 0 ? undefined : foldedSignatureClass(signatureClassOf(rawClass));
      filter.watchedOnly = value.watchedOnly === true;
      filter.attentionOnly = value.attentionOnly === true;
      filter.freshOnly = value.freshOnly === true;
      filter.cachedOnly = value.cachedOnly === true;
      filter.namedOnly = value.namedOnly === true;
      filter.decodedOnly = value.decodedOnly === true;
      filter.locatedOnly = value.locatedOnly === true;
      // ── 以下字段此前全部没有恢复 ──
      // 结果是「仅 BLE」「RSSI 阈值」「名称搜索」「与你同行」等设置每次重启都被静默重置，
      // 而 saveFilterState 明明把它们写进了磁盘。这里逐字段补齐。
      // 无线电开关三态：缺省按「全开」，与 FilterDefinition 的默认值一致。
      filter.showWifi = value.showWifi !== false;
      filter.showBle = value.showBle !== false;
      filter.showNearLink = value.showNearLink !== false;
      filter.customNamesOnly = value.customNamesOnly === true;
      filter.excludeSignatures = value.excludeSignatures === true;
      filter.includeSignatures = value.includeSignatures === true;
      filter.useClassFilter = value.useClassFilter === true;
      filter.excludeClasses = value.excludeClasses === true;
      filter.hideFastPairAccountKey = value.hideFastPairAccountKey === true;
      filter.movingWithYou = value.movingWithYou === true;
      filter.fleetIds = FieldwatchSettingsRepository.stringList(value.fleetIds);
      filter.includeFleetIds = FieldwatchSettingsRepository.stringList(value.includeFleetIds);
      filter.classes = FieldwatchSettingsRepository.classList(value.classes);
      filter.rssiMin = typeof value.rssiMin === 'number' ? value.rssiMin : -100;
      filter.nameQuery = typeof value.nameQuery === 'string' ? value.nameQuery : '';
      filter.ouiQuery = typeof value.ouiQuery === 'string' ? value.ouiQuery : '';
      return filter;
    }
  }

  saveWatchlist(watchlist: Array<WatchTarget>): void {
    ngfSettingsStoreFacade.setString(WATCHLIST_KEY, JSON.stringify(watchlist));
  }

  loadWatchlist(): Array<WatchTarget> {
    const content: string = ngfSettingsStoreFacade.getString(WATCHLIST_KEY, '');
    if (content.length === 0) return [];
    try {
      const values: Array<WatchTarget> = JSON.parse(content) as Array<WatchTarget>;
      const result: Array<WatchTarget> = [];
      for (let index: number = 0; index < values.length; index += 1) {
        const value: WatchTarget = values[index];
        // 签名级关注的 deviceKey 为空，不能按设备键过滤掉。
        if (value.deviceKey === undefined || value.signatureId === undefined) continue;
        const target: WatchTarget = new WatchTarget(value.deviceKey, value.signatureId, value.label, value.alert, value.note === undefined ? '' : value.note);
        if (!target.valid()) continue;
        result.push(target);
      }
      return result;
    } catch (error) {
      logger.warn(TAG, '读取关注列表失败: ' + String(error));
      return [];
    }
  }
}
