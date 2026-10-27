import { logger, ngfRdbManager } from 'ngf_framework';
import { RoomCheck } from '../domain/FieldwatchWifiDoctor';

const TAG: string = 'FieldwatchRoomCheckRepository';

/**
 * 房间体检结果的持久化（P1-7 的 RDB 新表 `fieldwatch_room_checks`）。
 *
 * 与观测仓储**共用 fieldwatch.db**、同一套 initialized/writeChain 模式，
 * 不新建库：房间体检一次只有几个房间，为一个几十行的表再开一个库没有收益。
 */
export class FieldwatchRoomCheckRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined = undefined;

  private static readonly CREATE_TABLE: string =
    'CREATE TABLE IF NOT EXISTS fieldwatch_room_checks ('
    + 'check_id TEXT PRIMARY KEY, '
    + 'sit_id TEXT NOT NULL DEFAULT \'\', '
    + 'room_label TEXT NOT NULL, '
    + 'bssid TEXT NOT NULL DEFAULT \'\', '
    + 'median_rssi REAL NOT NULL DEFAULT 0, '
    + 'channel INTEGER NOT NULL DEFAULT 0, '
    + 'sample_count INTEGER NOT NULL DEFAULT 0, '
    + 'started_at INTEGER NOT NULL DEFAULT 0, '
    + 'ended_at INTEGER NOT NULL DEFAULT 0)';

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  /**
   * 建表。
   *
   * **必须在 `init()` 之后再跑一遍 `CREATE TABLE IF NOT EXISTS`**：
   * `ngfRdbManager.init` 只在 store.version === 0 时执行建表语句，
   * 老用户的库已经是 version 1，新表永远不会被创建（这个坑在 P0 也踩过）。
   */
  private async initializeStore(): Promise<boolean> {
    try {
      const created: boolean = await ngfRdbManager.init({ name: 'fieldwatch.db', securityLevel: 1 }, []);
      await ngfRdbManager.executeSql(FieldwatchRoomCheckRepository.CREATE_TABLE);
      this.initialized = true;
      if (!created) logger.warn(TAG, 'RDB 初始化返回 false，房间表仍按 IF NOT EXISTS 建过');
      return true;
    } catch (error) {
      logger.warn(TAG, '房间体检表初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 保存一个房间的结果（按 check_id 覆盖，便于重测同一房间）。 */
  async save(check: RoomCheck, checkId: string, sitId: string): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql(
        'INSERT OR REPLACE INTO fieldwatch_room_checks '
        + '(check_id, sit_id, room_label, bssid, median_rssi, channel, sample_count, started_at, ended_at) '
        + 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [checkId, sitId, check.label, check.bestBssid, check.medianRssi, check.bestChannel,
          check.sampleCount, check.startedAt, check.endedAt]
      );
      return true;
    } catch (error) {
      logger.warn(TAG, '保存房间体检失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 读取最近一次（按 ended_at 倒序）的全部房间结果。 */
  async loadRecent(limit: number = 20): Promise<RoomCheck[]> {
    const result: RoomCheck[] = [];
    if (!await this.initialize()) return result;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT room_label, bssid, median_rssi, channel, sample_count, started_at, ended_at '
        + 'FROM fieldwatch_room_checks ORDER BY ended_at DESC LIMIT ?', [limit]);
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const room: RoomCheck = new RoomCheck(String(row['room_label'] ?? ''));
        room.bestBssid = String(row['bssid'] ?? '');
        room.medianRssi = Number(row['median_rssi'] ?? 0);
        room.bestChannel = Number(row['channel'] ?? 0);
        room.sampleCount = Number(row['sample_count'] ?? 0);
        room.startedAt = Number(row['started_at'] ?? 0);
        room.endedAt = Number(row['ended_at'] ?? 0);
        result.push(room);
      });
    } catch (error) {
      logger.warn(TAG, '读取房间体检失败: ' + this.errorMessage(error));
    }
    return result;
  }

  async clear(): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM fieldwatch_room_checks');
      return true;
    } catch (error) {
      logger.warn(TAG, '清理房间体检失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
