/**
 * ACL 审计的记录持久化（设计文档 7.2：只存本地、可查、可删）。
 *
 * 与观测仓储同一套模式：共用 fieldwatch.db，`init()` 之后再 `CREATE TABLE IF NOT EXISTS`
 * （`ngfRdbManager.init` 只在 store.version===0 时建表，老库已是 1，新表不会自动创建）。
 *
 * 字段严格按 7.2 限定：时间、任务、能力、目标范围、结果数、成功/失败、表版本。
 * **不存任何目标逐台地址、报文内容、认证信息**。
 */

import { logger, ngfRdbManager } from 'ngf_framework';
import { AclAuditRecord, IAclAuditSink } from '../domain/FieldwatchAclEngine';

const TAG: string = 'FieldwatchAclAuditRepo';
const EMPTY: string = String.fromCharCode(39) + String.fromCharCode(39);

export class FieldwatchAclAuditRepository implements IAclAuditSink {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined = undefined;
  /** 只保留最近 N 条：审计是给人查的，几百条足够。 */
  private static readonly KEEP_RECORDS: number = 500;

  private static readonly CREATE_TABLE: string =
    'CREATE TABLE IF NOT EXISTS fieldwatch_acl_audit ('
    + 'record_id TEXT PRIMARY KEY, '
    + 'at INTEGER NOT NULL DEFAULT 0, '
    + 'subject TEXT NOT NULL DEFAULT ' + EMPTY + ', '
    + 'capability TEXT NOT NULL DEFAULT ' + EMPTY + ', '
    + 'scope TEXT NOT NULL DEFAULT ' + EMPTY + ', '
    + 'result_count INTEGER NOT NULL DEFAULT 0, '
    + 'success INTEGER NOT NULL DEFAULT 0, '
    + 'deny_reason TEXT NOT NULL DEFAULT ' + EMPTY + ', '
    + 'table_version INTEGER NOT NULL DEFAULT 0)';

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
      await ngfRdbManager.executeSql(FieldwatchAclAuditRepository.CREATE_TABLE);
      this.initialized = true;
      return true;
    } catch (error) {
      logger.warn(TAG, '审计表初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 写一条审计。返回 false 时引擎会**失败关闭**（不放行）。 */
  async append(record: AclAuditRecord): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql(
        'INSERT OR REPLACE INTO fieldwatch_acl_audit '
        + '(record_id, at, subject, capability, scope, result_count, success, deny_reason, table_version) '
        + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [record.id, record.at, record.subject, record.capability, record.scope,
          record.resultCount, record.success ? 1 : 0, record.denyReason, record.tableVersion]
      );
      await this.prune();
      return true;
    } catch (error) {
      logger.warn(TAG, '写审计失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 读最近若干条（新→旧），设置页展示用。 */
  async loadRecent(limit: number = 50): Promise<AclAuditRecord[]> {
    const out: AclAuditRecord[] = [];
    if (!await this.initialize()) return out;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT record_id, at, subject, capability, scope, result_count, success, deny_reason, table_version '
        + 'FROM fieldwatch_acl_audit ORDER BY at DESC LIMIT ?', [limit]);
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const record: AclAuditRecord = new AclAuditRecord();
        record.id = row['record_id'] === undefined ? '' : String(row['record_id']);
        record.at = Number(row['at'] ?? 0);
        record.subject = row['subject'] === undefined ? '' : String(row['subject']);
        record.capability = row['capability'] === undefined ? '' : String(row['capability']);
        record.scope = row['scope'] === undefined ? '' : String(row['scope']);
        record.resultCount = Number(row['result_count'] ?? 0);
        record.success = Number(row['success'] ?? 0) === 1;
        record.denyReason = row['deny_reason'] === undefined ? AclDenyReasonNone() : String(row['deny_reason']);
        record.tableVersion = Number(row['table_version'] ?? 0);
        if (record.id.length > 0) out.push(record);
      });
    } catch (error) {
      logger.warn(TAG, '读审计失败: ' + this.errorMessage(error));
    }
    return out;
  }

  /** 删除全部审计（设置页「删除记录」）。 */
  async clearAll(): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM fieldwatch_acl_audit');
      return true;
    } catch (error) {
      logger.warn(TAG, '清空审计失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private async prune(): Promise<void> {
    try {
      await ngfRdbManager.executeSql(
        'DELETE FROM fieldwatch_acl_audit WHERE record_id NOT IN '
        + '(SELECT record_id FROM fieldwatch_acl_audit ORDER BY at DESC LIMIT ?)',
        [FieldwatchAclAuditRepository.KEEP_RECORDS]
      );
    } catch (error) {
      logger.debug(TAG, '裁剪审计跳过: ' + this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/** 枚举的「无拒绝」值，避免在仓储里再导一次枚举造成循环依赖。 */
function AclDenyReasonNone(): string { return 'none'; }
