import { logger, ngfRdbManager } from 'ngf_framework';
import { SecuritySummary } from '../domain/FieldwatchSecurityScan';
import { SecurityEvidence, SuspectDevice } from '../domain/FieldwatchSecurityPassive';

// hilog 标签上限 31 字符，超了会被系统拒绝（真机验证过）。
const TAG: string = 'FieldwatchSecurityHistory';

/**
 * 一次安防扫描的历史记录。
 *
 * P3-2 只存汇总；**P3-3 起追加可疑清单快照**（`snapshot_json` 列），
 * 以便点进历史能回放当次的判定结果。
 * 迁移策略：列用 `ALTER TABLE ADD COLUMN` 补（SQLite 对已存在表加列是 O(1)），
 * 老行的 snapshot_json 为 NULL → 读出时 `hasSnapshot=false`，不回填、不猜测。
 */
/**
 * 可疑设备的快照（P3-3 第 3 项：历史回放要能看当次的可疑清单与证据分项）。
 *
 * 只存**展示所需**的字段：名称 / 地址 / 档位 / 证据文案键。
 * 不存 Sighting 全量 —— 几百台 × 完整 facts 会让历史表体积失控，
 * 而回放要看的是「当时判定了什么」，不是重算一遍。
 */
export class SuspectSnapshot {
  public label: string = '';
  public address: string = '';
  public verdict: string = '';
  /** 证据的 detailKey 列表（如 'oui' / 'name' / 'cod_mic'）。 */
  public evidenceKeys: string[] = [];
  constructor() {}
}

export class SecurityScanRecord {
  public id: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public total: number = 0;
  public ble: number = 0;
  public wifi: number = 0;
  public nearLink: number = 0;
  public newFaces: number = 0;
  public followScore: number = 0;
  public confirmedCount: number = 0;
  public suspiciousCount: number = 0;
  /**
   * 可疑清单快照（P3-3 新增）。
   *
   * **P3-2 写下的老记录没有这一列**：读出来是空数组 + `hasSnapshot=false`，
   * 回放页据此明示「该次记录无快照」，而不是显示成「当时没有可疑设备」——
   * 这两种情况对用户意义完全不同，不能混为一谈。
   */
  public suspects: SuspectSnapshot[] = [];
  /** 该记录是否带快照（区分「无快照」与「当时确实没有」）。 */
  public hasSnapshot: boolean = false;
  constructor() {}
  durationMs(): number { return this.endedAt - this.startedAt; }
}

/**
 * 安防扫描历史的持久化。
 *
 * 与房间体检同一套模式：共用 fieldwatch.db、initialize 后用 IF NOT EXISTS 再建一次表
 * （`ngfRdbManager.init` 只在 store.version===0 时建表，老用户的库已是 1，新表不会自动创建）。
 */
export class FieldwatchSecurityHistoryRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined = undefined;
  /** 只保留最近 N 次：历史是给人看的，几十条足够，多了白占空间。 */
  private static readonly KEEP_RECORDS: number = 30;

  private static readonly CREATE_TABLE: string =
    'CREATE TABLE IF NOT EXISTS fieldwatch_security_scans ('
    + 'record_id TEXT PRIMARY KEY, '
    + 'started_at INTEGER NOT NULL DEFAULT 0, '
    + 'ended_at INTEGER NOT NULL DEFAULT 0, '
    + 'total INTEGER NOT NULL DEFAULT 0, '
    + 'ble INTEGER NOT NULL DEFAULT 0, '
    + 'wifi INTEGER NOT NULL DEFAULT 0, '
    + 'near_link INTEGER NOT NULL DEFAULT 0, '
    + 'new_faces INTEGER NOT NULL DEFAULT 0, '
    + 'follow_score INTEGER NOT NULL DEFAULT 0, '
    + 'confirmed_count INTEGER NOT NULL DEFAULT 0, '
    + 'suspicious_count INTEGER NOT NULL DEFAULT 0, '
    // P3-3：可疑清单快照。存 JSON 字符串而不是再开一张表 ——
    // 快照只跟着记录走、从不单独查询，扁平存最省事也最少连接。
    + 'snapshot_json TEXT)';

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  private async initializeStore(): Promise<boolean> {
    try {
      await ngfRdbManager.init({ name: 'fieldwatch.db', securityLevel: 1 }, []);
      await ngfRdbManager.executeSql(FieldwatchSecurityHistoryRepository.CREATE_TABLE);
      // P3-3 迁移：P3-2 已建过这张表的老库没有 snapshot_json，
      // CREATE TABLE IF NOT EXISTS 不会补列，必须显式 ALTER。
      await this.ensureSnapshotColumn();
      this.initialized = true;
      return true;
    } catch (error) {
      logger.warn(TAG, '安防历史表初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /**
   * 补 `snapshot_json` 列（P3-3 迁移）。
   *
   * 加列之前先用 PRAGMA 看一遍，避免重复 ALTER 报错：
   * SQLite 的 ADD COLUMN 没有 IF NOT EXISTS 形式，重复加会抛「duplicate column」。
   * 失败只记日志不阻断 —— 老库即使补列失败，汇总数据仍然可读。
   */
  private async ensureSnapshotColumn(): Promise<void> {
    try {
      const columns: Array<Record<string, string | number | boolean>> =
        await ngfRdbManager.querySql('PRAGMA table_info(fieldwatch_security_scans)');
      let exists: boolean = false;
      columns.forEach((row: Record<string, string | number | boolean>): void => {
        if (String(row['name'] ?? '') === 'snapshot_json') exists = true;
      });
      if (exists) return;
      await ngfRdbManager.executeSql(
        'ALTER TABLE fieldwatch_security_scans ADD COLUMN snapshot_json TEXT');
      logger.info(TAG, '已为历史表补 snapshot_json 列（P3-3 迁移）');
    } catch (error) {
      logger.warn(TAG, '补 snapshot_json 列失败（老记录将显示为无快照）: ' + this.errorMessage(error));
    }
  }

  /** 保存一次扫描结果，并顺手裁掉过老的记录。 */
  async save(summary: SecuritySummary): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql(
        'INSERT OR REPLACE INTO fieldwatch_security_scans '
        + '(record_id, started_at, ended_at, total, ble, wifi, near_link, new_faces, follow_score, '
        + 'confirmed_count, suspicious_count, snapshot_json) '
        + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [this.recordIdOf(summary.endedAt), summary.startedAt, summary.endedAt, summary.total, summary.ble,
          summary.wifi, summary.nearLink, summary.newFaces, summary.followScore,
          summary.confirmedCount, summary.suspiciousCount, this.encodeSuspects(summary)]
      );
      await this.prune();
      return true;
    } catch (error) {
      logger.warn(TAG, '保存安防历史失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 读最近若干次（新→旧）。 */
  async loadRecent(limit: number = 10): Promise<SecurityScanRecord[]> {
    const result: SecurityScanRecord[] = [];
    if (!await this.initialize()) return result;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT record_id, started_at, ended_at, total, ble, wifi, near_link, new_faces, follow_score, '
        + 'confirmed_count, suspicious_count, snapshot_json FROM fieldwatch_security_scans '
        + 'ORDER BY ended_at DESC LIMIT ?', [limit]);
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const record: SecurityScanRecord = new SecurityScanRecord();
        record.id = String(row['record_id'] ?? '');
        record.startedAt = Number(row['started_at'] ?? 0);
        record.endedAt = Number(row['ended_at'] ?? 0);
        record.total = Number(row['total'] ?? 0);
        record.ble = Number(row['ble'] ?? 0);
        record.wifi = Number(row['wifi'] ?? 0);
        record.nearLink = Number(row['near_link'] ?? 0);
        record.newFaces = Number(row['new_faces'] ?? 0);
        record.followScore = Number(row['follow_score'] ?? 0);
        record.confirmedCount = Number(row['confirmed_count'] ?? 0);
        record.suspiciousCount = Number(row['suspicious_count'] ?? 0);
        // P3-2 写下的老记录没有 snapshot_json（列是后来 ALTER 补的），
        // 这里如实标成「无快照」，回放页据此明示，不伪造空清单。
        const rawSnapshot: string = row['snapshot_json'] === undefined || row['snapshot_json'] === null
          ? '' : String(row['snapshot_json']);
        if (rawSnapshot.length > 0) {
          record.suspects = this.decodeSuspects(rawSnapshot);
          record.hasSnapshot = true;
        }
        if (record.id.length > 0) result.push(record);
      });
    } catch (error) {
      logger.warn(TAG, '读取安防历史失败: ' + this.errorMessage(error));
    }
    return result;
  }

  private recordIdOf(endedAt: number): string { return 'scan-' + endedAt.toString(); }

  /**
   * 把可疑清单序列化成 JSON（P3-3）。
   *
   * 用**通用对象**而不是直接 JSON.stringify(SuspectDevice[])：
   * 领域对象里有 `verdict` 枚举与 `evidence` 对象，存原样会把内部结构钉进存储，
   * 以后改领域模型就得写数据迁移。这里先降成扁平的快照结构。
   */
  private encodeSuspects(summary: SecuritySummary): string {
    const snapshots: Array<Record<string, string | string[]>> = [];
    summary.suspects.forEach((item: SuspectDevice): void => {
      const keys: string[] = [];
      item.evidence.forEach((ev: SecurityEvidence): void => { keys.push(ev.detailKey); });
      const row: Record<string, string | string[]> = {};
      row['label'] = item.label;
      row['address'] = item.address;
      row['verdict'] = String(item.verdict);
      row['evidence'] = keys;
      snapshots.push(row);
    });
    return JSON.stringify(snapshots);
  }

  /** 反序列化快照；坏数据返回空数组而不是抛异常（历史页不能因为一条坏记录崩掉）。 */
  private decodeSuspects(raw: string): SuspectSnapshot[] {
    const out: SuspectSnapshot[] = [];
    if (raw.length === 0) return out;
    try {
      const parsed: Array<Record<string, string | string[]>> = JSON.parse(raw) as Array<Record<string, string | string[]>>;
      parsed.forEach((row: Record<string, string | string[]>): void => {
        const snapshot: SuspectSnapshot = new SuspectSnapshot();
        snapshot.label = String(row['label'] ?? '');
        snapshot.address = String(row['address'] ?? '');
        snapshot.verdict = String(row['verdict'] ?? '');
        const keys: string[] = [];
        const rawKeys: string | string[] | undefined = row['evidence'];
        if (rawKeys !== undefined && rawKeys instanceof Array) {
          rawKeys.forEach((key: string): void => { keys.push(String(key)); });
        }
        snapshot.evidenceKeys = keys;
        out.push(snapshot);
      });
    } catch (error) {
      logger.warn(TAG, '快照解析失败，按无快照处理: ' + this.errorMessage(error));
    }
    return out;
  }

  /** 只保留最近 KEEP_RECORDS 条。 */
  private async prune(): Promise<void> {
    try {
      await ngfRdbManager.executeSql(
        'DELETE FROM fieldwatch_security_scans WHERE record_id NOT IN (SELECT record_id FROM fieldwatch_security_scans ORDER BY ended_at DESC LIMIT ?)',
        [FieldwatchSecurityHistoryRepository.KEEP_RECORDS]
      );
    } catch (error) {
      logger.debug(TAG, '裁剪安防历史跳过: ' + this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
