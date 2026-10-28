import { FileUtils, logger, NGFNetworkRequest, ngfNetworkClient, uiContextManager } from 'ngf_framework';
import { util } from '@kit.ArkTS';
import { RadioKind, SignatureClass } from '../domain/FieldwatchModels';
import {
  SignatureFleet, SignaturePack, SignatureRule, SignatureRuleKind, signatureClassOf, signatureHexOnly
} from '../domain/signatures/FieldwatchSignatureModels';
import {
  SignatureImportResult, SignaturePackError, SignaturePackParseResult, StockCatalogUpdateResult, encodeSignaturePack,
  mergeSignatureFleets, overlayStockFleets, parseSignaturePack
} from '../domain/signatures/FieldwatchSignatureCatalog';

const TAG: string = 'FieldwatchCatalogRepository';
/** 特征数据仓 airwave-signatures 的发布地址；按顺序尝试，首个可用镜像为准（raw 在国内不稳定，jsDelivr 兜底）。 */
const CATALOG_URLS: string[] = [
  'https://raw.githubusercontent.com/DaLongZhuaZi/airwave-signatures/main/dist/fieldwatch-signatures-v2.json',
  'https://cdn.jsdelivr.net/gh/DaLongZhuaZi/airwave-signatures@main/dist/fieldwatch-signatures-v2.json'
];
const CATALOG_REQUEST_TIMEOUT_MS: number = 15000;
const STOCK_RAWFILE: string = 'fieldwatch-signatures-v2.json';
const CATALOG_FILE: string = 'fieldwatch/signatures.json';
const LEGACY_CATALOG_FILE: string = 'fieldwatch/catalog.json';

/** 旧版（精简模型）目录文件的形状，仅用于一次性迁移。 */
interface LegacySignatureDefinition {
  id?: string; name?: string; kind?: string; category?: string; matchText?: string; extraAttention?: boolean; stock?: boolean;
}

export class FieldwatchCatalogImportOutcome {
  public fleets: SignatureFleet[] = [];
  public result: SignatureImportResult = new SignatureImportResult();
  constructor(fleets: SignatureFleet[], result: SignatureImportResult) { this.fleets = fleets; this.result = result; }
}

export class FieldwatchCatalogRepository {
  private stockCache: SignatureFleet[] | undefined = undefined;
  private stockVersion: number = 0;
  private savedVersion: number = 0;
  private legacyMigrated: boolean = false;
  /** 本地目录文件存在但解析失败：此时**不得**用 stock 覆盖，否则销毁用户签名。 */
  private savedCorrupt: boolean = false;

  getStockVersion(): number { return this.stockVersion; }
  getSavedVersion(): number { return this.savedVersion; }
  /** 上次读取本地目录时是否遇到损坏文件（供启动流程决定是否允许落盘覆盖）。 */
  wasSavedCorrupt(): boolean { return this.savedCorrupt; }

  /** 读取打包在 rawfile 里的 stock 目录；结果缓存，避免重复解析 2 MB JSON。 */
  async loadStock(): Promise<SignatureFleet[]> {
    const cached: SignatureFleet[] | undefined = this.stockCache;
    if (cached !== undefined) return cached;
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '读取内置 Catalog 失败：没有 Ability 上下文');
      return [];
    }
    try {
      const raw: Uint8Array = await context.resourceManager.getRawFileContent(STOCK_RAWFILE);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const content: string = decoder.decodeToString(raw);
      const parsed = parseSignaturePack(content);
      if (parsed.error !== SignaturePackError.NONE) {
        logger.warn(TAG, '内置 Catalog 解析失败: ' + parsed.error);
        return [];
      }
      parsed.pack.fleets.forEach((fleet: SignatureFleet): void => { fleet.builtIn = true; });
      this.stockCache = parsed.pack.fleets;
      this.stockVersion = parsed.pack.catalogVersion;
      logger.info(TAG, '内置 Catalog 已加载: ' + this.stockCache.length.toString() + ' 条, version=' + parsed.pack.catalogVersion.toString());
      return this.stockCache;
    } catch (error) {
      logger.warn(TAG, '读取内置 Catalog 异常: ' + this.errorMessage(error));
      return [];
    }
  }

  /** 读取应用沙箱里的用户目录（含用户新增/编辑与 stock 覆盖结果）。 */
  loadSaved(): SignatureFleet[] {
    // **构造期上下文还没绑定**：这时沙箱基础目录为空，任何读写都会退化成相对路径、
    // 一定失败。与其刷一条「沙箱未设置 + readText 失败」的假故障，不如直接跳过；
    // `ensureCatalogLoaded()` 会在上下文就绪后补读。
    if (!FileUtils.isSandboxReady()) {
      return [];
    }
    const present: boolean = FileUtils.exists(CATALOG_FILE);
    const content: string = present ? FileUtils.readText(CATALOG_FILE) : '';
    // **文件在、但读不出来**：典型情形是构造期沙箱基础目录尚未就绪，
    // `resolvePath` 退化成相对路径导致 open 失败。此时若当作「没有本地目录」，
    // 启动流程会用 stock 落盘覆盖，用户自定义签名被静默销毁（真机复现两次）。
    if (present && content.length === 0) {
      logger.error(TAG, '本地 Catalog 存在但读取为空，保留原文件不落盘');
      this.savedCorrupt = true;
      this.savedVersion = 0;
      return [];
    }
    if (content.length > 0) {
      let parsed: SignaturePackParseResult;
      try {
        parsed = parseSignaturePack(content);
      } catch (error) {
        // 解析器在真实数据上抛异常时同样按「文件损坏」处理：
        // 旧实现让异常冒到调用方，目录被判为空并落盘覆盖，用户签名直接消失。
        logger.error(TAG, '本地 Catalog 解析抛异常，保留原文件不落盘: ' + this.errorMessage(error));
        this.savedCorrupt = true;
        this.savedVersion = 0;
        return [];
      }
      if (parsed.error === SignaturePackError.NONE) {
        this.savedCorrupt = false;
        this.savedVersion = parsed.pack.catalogVersion;
        return parsed.pack.fleets;
      }
      logger.warn(TAG, '本地 Catalog 解析失败，回退到内置目录: ' + parsed.error);
      this.savedCorrupt = true;
      this.savedVersion = 0;
      return [];
    }
    // 走 legacy 迁移分支：文件确实不存在。
    // **这是首跑的正常状态，不是错误**：本地目录还没有，稍后由 `ensureCatalogLoaded()`
    // 从内置目录种子化一次；已有本地文件时绝不覆写（保护用户签名）。
    logger.info(TAG, '首次运行：本地 Catalog 不存在，将从内置目录种子化一次');
    this.savedCorrupt = false;
    const legacy: SignatureFleet[] = this.loadLegacyCatalog();
    if (legacy.length > 0) {
      this.save(legacy);
      logger.info(TAG, '旧版 Catalog 已迁移: ' + legacy.length.toString() + ' 条');
      return legacy;
    }
    this.savedVersion = 0;
    return [];
  }

  /** 旧版精简模型（单个 matchText）转换为新模型，保证用户自定义签名不丢失。 */
  private loadLegacyCatalog(): SignatureFleet[] {
    if (this.legacyMigrated) return [];
    this.legacyMigrated = true;
    const content: string = FileUtils.readText(LEGACY_CATALOG_FILE);
    if (content.length === 0) return [];
    try {
      const saved: LegacySignatureDefinition[] = JSON.parse(content) as LegacySignatureDefinition[];
      const result: SignatureFleet[] = [];
      saved.forEach((item: LegacySignatureDefinition): void => {
        const id: string = item.id === undefined ? '' : item.id;
        if (id.length === 0) return;
        const name: string = item.name === undefined ? id : item.name;
        const matchText: string = item.matchText === undefined ? '' : item.matchText;
        const kind: string = item.kind === undefined ? 'ble' : item.kind;
        const radio: RadioKind = kind === 'wifi' ? RadioKind.WIFI : RadioKind.BLE;
        const rules: SignatureRule[] = [new SignatureRule(SignatureRuleKind.NAME_CONTAINS, matchText, 0, '', radio)];
        const hex: string = signatureHexOnly(matchText);
        if (hex.length >= 2 && hex.length === matchText.length) rules.push(new SignatureRule(SignatureRuleKind.MANUFACTURER_DATA, '', 0, hex, radio));
        const fleet: SignatureFleet = new SignatureFleet(id, name, signatureClassOf(item.category === undefined ? '' : item.category), rules, item.stock === true);
        fleet.attentionNote = item.extraAttention === true ? name : '';
        result.push(fleet);
      });
      return result;
    } catch (error) {
      logger.warn(TAG, '旧版 Catalog 迁移失败: ' + this.errorMessage(error));
      return [];
    }
  }

  save(fleets: SignatureFleet[], catalogVersion?: number): boolean {
    FileUtils.createDirectory('fieldwatch');
    const version: number = catalogVersion === undefined ? this.savedVersion : catalogVersion;
    const saved: boolean = FileUtils.writeText(CATALOG_FILE,
      encodeSignaturePack(new SignaturePack(fleets, version, 'harmonyos')));
    if (saved) this.savedVersion = version;
    return saved;
  }

  /** 用户主动更新：按镜像顺序拉取 stock 包并覆盖 stock 行，保留用户状态、额外规则和自定义签名。 */
  async updateStockCatalog(current: SignatureFleet[]): Promise<StockCatalogUpdateResult> {
    if (this.stockVersion <= 0) await this.loadStock();
    const minimumVersion: number = Math.max(this.stockVersion, this.savedVersion);
    let lastError: SignaturePackError = SignaturePackError.MALFORMED;
    let lastSkippedDecode: number = 0;
    let sawOutdated: boolean = false;
    for (let index: number = 0; index < CATALOG_URLS.length; index++) {
      const url: string = CATALOG_URLS[index];
      try {
        const request: NGFNetworkRequest = {
          url: url,
          method: 'GET',
          timeoutMs: CATALOG_REQUEST_TIMEOUT_MS
        };
        const response = await ngfNetworkClient.request(request);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          logger.warn(TAG, 'Catalog 镜像 HTTP 失败: ' + url + ' status=' + response.statusCode.toString());
          continue;
        }
        const parsed = parseSignaturePack(response.body);
        if (parsed.error !== SignaturePackError.NONE) {
          lastError = parsed.error;
          lastSkippedDecode = parsed.skippedDecode;
          continue;
        }
        if (parsed.pack.catalogVersion < minimumVersion) {
          // 版本守卫：更新源低于内置或本地保存版本时拒绝覆盖，防止数据源回滚；
          // 继续尝试下一个镜像（CDN 缓存可能滞后），全部过旧才报 OUTDATED。
          logger.warn(TAG, 'Catalog 版本过旧已拒绝: remote=' + parsed.pack.catalogVersion.toString() + ', local=' + minimumVersion.toString() + ', url=' + url);
          sawOutdated = true;
          continue;
        }
        parsed.pack.fleets.forEach((fleet: SignatureFleet): void => { fleet.builtIn = true; });
        const before: number = current.length;
        const merged: SignatureFleet[] = overlayStockFleets(current, parsed.pack.fleets);
        const added: number = merged.length - before;
        const saved: boolean = this.save(merged, parsed.pack.catalogVersion);
        logger.info(TAG, 'Catalog 更新完成: added=' + added.toString() + ', version=' + parsed.pack.catalogVersion.toString() + ', saved=' + saved.toString() + ', url=' + url);
        if (!saved) return new StockCatalogUpdateResult(0, before, parsed.pack.catalogVersion,
          parsed.skippedDecode, SignaturePackError.SAVE_FAILED);
        this.stockVersion = Math.max(this.stockVersion, parsed.pack.catalogVersion);
        return new StockCatalogUpdateResult(added < 0 ? 0 : added, before, parsed.pack.catalogVersion, parsed.skippedDecode, SignaturePackError.NONE);
      } catch (error) {
        logger.warn(TAG, 'Catalog 镜像请求异常: ' + url + ' ' + this.errorMessage(error));
      }
    }
    if (sawOutdated) return new StockCatalogUpdateResult(0, 0, 0, lastSkippedDecode, SignaturePackError.OUTDATED);
    logger.warn(TAG, 'Catalog 更新失败，保留旧目录');
    return new StockCatalogUpdateResult(0, 0, 0, lastSkippedDecode, lastError);
  }

  /** 从文件导入：追加规则、按指纹跳过重复，不删除现有目录。 */
  importPack(current: SignatureFleet[], text: string): FieldwatchCatalogImportOutcome {
    const parsed = parseSignaturePack(text);
    if (parsed.error !== SignaturePackError.NONE) {
      return new FieldwatchCatalogImportOutcome(current, new SignatureImportResult(0, 0, 0, 0, parsed.error));
    }
    const stockIds: Set<string> = new Set<string>();
    current.forEach((fleet: SignatureFleet): void => { if (fleet.builtIn) stockIds.add(fleet.id); });
    const before: number = current.length;
    const merged: SignatureFleet[] = mergeSignatureFleets(current, parsed.pack.fleets, stockIds);
    const added: number = merged.length - before;
    const skipped: number = parsed.pack.fleets.length - added;
    const saved: boolean = this.save(merged);
    logger.info(TAG, 'Catalog 导入完成: added=' + added.toString() + ', skipped=' + skipped.toString() + ', saved=' + saved.toString());
    return new FieldwatchCatalogImportOutcome(merged, new SignatureImportResult(added < 0 ? 0 : added, 0, skipped < 0 ? 0 : skipped, 0, SignaturePackError.NONE));
  }

  /** 导出完整目录（stock + 用户内容）文本；写盘由平台文件通道负责。 */
  exportText(fleets: SignatureFleet[]): string {
    return encodeSignaturePack(new SignaturePack(fleets, this.savedVersion, 'harmonyos'));
  }

  /** 恢复默认目录：只保留内置 stock，清除用户新增与编辑。调用方必须先取得用户确认。 */
  async restoreDefaults(): Promise<SignatureFleet[]> {
    const stock: SignatureFleet[] = await this.loadStock();
    const restored: SignatureFleet[] = [];
    stock.forEach((fleet: SignatureFleet): void => {
      const copy: SignatureFleet = new SignatureFleet(fleet.id, fleet.name, fleet.category, fleet.rules.slice(), true);
      copy.enabled = fleet.enabled;
      copy.matchAny = fleet.matchAny;
      copy.colorIndex = fleet.colorIndex;
      copy.minPeers = fleet.minPeers;
      copy.peerWindowSec = fleet.peerWindowSec;
      copy.clusterByOui = fleet.clusterByOui;
      copy.sequentialMac = fleet.sequentialMac;
      copy.notes = fleet.notes;
      copy.attentionNote = fleet.attentionNote;
      copy.decode = fleet.decode;
      restored.push(copy);
    });
    this.save(restored, this.stockVersion);
    return restored;
  }

  /** 供 UI 显示的统计，不包含任何用户可见文案。 */
  countByClass(fleets: SignatureFleet[]): Map<SignatureClass, number> {
    const counts: Map<SignatureClass, number> = new Map<SignatureClass, number>();
    fleets.forEach((fleet: SignatureFleet): void => {
      const current: number | undefined = counts.get(fleet.category);
      counts.set(fleet.category, current === undefined ? 1 : current + 1);
    });
    return counts;
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
