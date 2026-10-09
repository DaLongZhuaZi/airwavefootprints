import { FileUtils, logger, ngfNetworkClient, uiContextManager } from 'ngf_framework';
import { util } from '@kit.ArkTS';
import { RadioKind, SignatureClass } from '../domain/FieldwatchModels';
import {
  SignatureFleet, SignaturePack, SignatureRule, SignatureRuleKind, signatureClassOf, signatureHexOnly
} from '../domain/signatures/FieldwatchSignatureModels';
import {
  SignatureImportResult, SignaturePackError, StockCatalogUpdateResult, encodeSignaturePack, mergeSignatureFleets,
  overlayStockFleets, parseSignaturePack
} from '../domain/signatures/FieldwatchSignatureCatalog';

const TAG: string = 'FieldwatchCatalogRepository';
const CATALOG_URL: string = 'https://raw.githubusercontent.com/DaLongZhuaZi/Fieldwatch/main/dist/fieldwatch-signatures-v2.json';
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
  private legacyMigrated: boolean = false;

  getStockVersion(): number { return this.stockVersion; }

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
    const content: string = FileUtils.readText(CATALOG_FILE);
    if (content.length > 0) {
      const parsed = parseSignaturePack(content);
      if (parsed.error === SignaturePackError.NONE) return parsed.pack.fleets;
      logger.warn(TAG, '本地 Catalog 解析失败，回退到内置目录: ' + parsed.error);
      return [];
    }
    const legacy: SignatureFleet[] = this.loadLegacyCatalog();
    if (legacy.length > 0) {
      this.save(legacy);
      logger.info(TAG, '旧版 Catalog 已迁移: ' + legacy.length.toString() + ' 条');
      return legacy;
    }
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

  save(fleets: SignatureFleet[]): boolean {
    FileUtils.createDirectory('fieldwatch');
    return FileUtils.writeText(CATALOG_FILE, encodeSignaturePack(new SignaturePack(fleets, 0, 'harmonyos')));
  }

  /** 用户主动更新：拉取 stock 包并覆盖 stock 行，保留用户状态、额外规则和自定义签名。 */
  async updateStockCatalog(current: SignatureFleet[]): Promise<StockCatalogUpdateResult> {
    try {
      const response = await ngfNetworkClient.get(CATALOG_URL);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return new StockCatalogUpdateResult(0, 0, 0, 0, SignaturePackError.MALFORMED);
      }
      const parsed = parseSignaturePack(response.body);
      if (parsed.error !== SignaturePackError.NONE) return new StockCatalogUpdateResult(0, 0, 0, parsed.skippedDecode, parsed.error);
      parsed.pack.fleets.forEach((fleet: SignatureFleet): void => { fleet.builtIn = true; });
      const before: number = current.length;
      const merged: SignatureFleet[] = overlayStockFleets(current, parsed.pack.fleets);
      const added: number = merged.length - before;
      const saved: boolean = this.save(merged);
      logger.info(TAG, 'Catalog 更新完成: added=' + added.toString() + ', version=' + parsed.pack.catalogVersion.toString() + ', saved=' + saved.toString());
      return new StockCatalogUpdateResult(added < 0 ? 0 : added, before, parsed.pack.catalogVersion, parsed.skippedDecode, SignaturePackError.NONE);
    } catch (error) {
      logger.warn(TAG, 'Catalog 更新失败，保留旧目录: ' + this.errorMessage(error));
      return new StockCatalogUpdateResult(0, 0, 0, 0, SignaturePackError.MALFORMED);
    }
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
    return encodeSignaturePack(new SignaturePack(fleets, 0, 'harmonyos'));
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
    this.save(restored);
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
