import { logger, ngfRdbManager } from 'ngf_framework';
import { SecuritySummary } from '../domain/FieldwatchSecurityScan';

// hilog 标签上限 31 字符，超了会被系统拒绝（真机验证过）。
const TAG: string = 'FieldwatchSecurityHistory';

/**
 * 一次安防扫描的历史记录（P3-2 第 1 项）。
 *
 * 只存**汇总级**数据（时间、总数、可疑数、确认数），不存逐台设备：
 * 用户点进去要看的是「那次扫了多少、几台可疑」，而不是重放一遍原始观测。
 * 逐台设备的证据在当时的实时列表里，历史只负责给出那次的结论。
 */
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
    + 'suspicious_count INTEGER NOT NULL DEFAULT 0)';

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
      this.initialized = true;
      return true;
    } catch (error) {
      logger.warn(TAG, '安防历史表初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 保存一次扫描结果，并顺手裁掉过老的记录。 */
  async save(summary: SecuritySummary): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql(
        'INSERT OR REPLACE INTO fieldwatch_security_scans '
        + '(record_id, started_at, ended_at, total, ble, wifi, near_link, new_faces, follow_score, confirmed_count, suspicious_count) '
        + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [this.recordIdOf(summary.endedAt), summary.startedAt, summary.endedAt, summary.total, summary.ble,
          summary.wifi, summary.nearLink, summary.newFaces, summary.followScore,
          summary.confirmedCount, summary.suspiciousCount]
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
        + 'confirmed_count, suspicious_count FROM fieldwatch_security_scans ORDER BY ended_at DESC LIMIT ?', [limit]);
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
        if (record.id.length > 0) result.push(record);
      });
    } catch (error) {
      logger.warn(TAG, '读取安防历史失败: ' + this.errorMessage(error));
    }
    return result;
  }

  private recordIdOf(endedAt: number): string { return 'scan-' + endedAt.toString(); }

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
