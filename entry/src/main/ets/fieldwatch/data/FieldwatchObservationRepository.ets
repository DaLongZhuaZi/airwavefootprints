import { logger, ngfRdbManager } from 'ngf_framework';
import { RadioKind, ScanObservation, SitSummary } from '../domain/FieldwatchModels';

const TAG: string = 'FieldwatchObservationRepository';

export class FieldwatchStoredObservation {
  public key: string = '';
  public kind: RadioKind = RadioKind.BLE;
  public address: string = '';
  public name: string = '';
  public rssi: number = 0;
  public seenAt: number = 0;
  public ssid: string = '';
  public frequencyMhz: number = 0;
  public band: number = 0;
  public channelWidth: number = 0;
  public securityType: number = 0;
  public fresh: boolean = false;
}

export class FieldwatchStoredSit extends SitSummary {
  constructor(id: string, name: string, startedAt: number, endedAt: number, radioCount: number, deviceKeys: string[] = []) {
    super(id, name, startedAt, endedAt, radioCount, deviceKeys);
  }
}

/** 批量插入的列前缀与单行占位符；行数可变，串在运行时拼。 */
const OBSERVATION_INSERT_PREFIX: string =
  'INSERT INTO fieldwatch_observations (observation_key, kind, address, name, rssi, seen_at, ssid, '
  + 'frequency_mhz, band, channel_width, security_type, fresh) VALUES ';
const OBSERVATION_ROW_PLACEHOLDER: string = '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

export class FieldwatchObservationRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined;
  private writeChain: Promise<void> = Promise.resolve();
  private writeCount: number = 0;
  // ── 批量写入缓冲 ──
  //
  // **为什么不能逐条写**：高密度环境下观测可达 100+ 条/秒，逐条 executeSql 等于每秒
  // 上百次独立事务提交，每次都要走一遍权限校验 + fsync。能量录制里 RDB 侧
  // H:VerifyPermission 被调用 8.6 万次/44s、executeSql 占 1.7% CPU，就是这条路。
  // 改成「内存排队 + 单条多行 INSERT」后写放大从 O(观测数) 降到 O(批次)。
  private pending: ScanObservation[] = [];
  private flushTimer: number = -1;
  private static readonly BATCH_ROWS: number = 24;
  private static readonly FLUSH_DELAY_MS: number = 400;

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  /**
   * 观测入队。
   *
   * 攒够 BATCH_ROWS 条立即落库，否则等 FLUSH_DELAY_MS 再落库；调用方（采集回调）
   * 不再逐条等待事务提交。
   */
  async append(observation: ScanObservation): Promise<void> {
    this.pending.push(observation);
    if (this.pending.length >= FieldwatchObservationRepository.BATCH_ROWS) {
      this.cancelFlushTimer();
      await this.writePending();
      return;
    }
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.flushTimer >= 0) return;
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      void this.writePending();
    }, FieldwatchObservationRepository.FLUSH_DELAY_MS);
  }

  private cancelFlushTimer(): void {
    if (this.flushTimer < 0) return;
    clearTimeout(this.flushTimer);
    this.flushTimer = -1;
  }

  /** 把缓冲区一次性写成一条多行 INSERT；串行执行，避免与自己的上一次写入交错。 */
  private writePending(): Promise<void> {
    this.writeChain = this.writeChain.then(async (): Promise<void> => {
      if (this.pending.length === 0) return;
      const batch: ScanObservation[] = this.pending;
      this.pending = [];
      if (!await this.initialize()) return;
      const placeholders: string[] = [];
      const args: Array<string | number | boolean> = [];
      for (let index: number = 0; index < batch.length; index += 1) {
        const observation: ScanObservation = batch[index];
        placeholders.push(OBSERVATION_ROW_PLACEHOLDER);
        args.push(observation.key);
        args.push(observation.kind);
        args.push(observation.address);
        args.push(observation.name);
        args.push(observation.rssi);
        args.push(observation.seenAt);
        args.push(observation.facts.ssid);
        args.push(observation.facts.frequencyMhz);
        args.push(observation.facts.band);
        args.push(observation.facts.channelWidth);
        args.push(observation.facts.securityType);
        args.push(observation.fresh);
      }
      try {
        await ngfRdbManager.executeSql(OBSERVATION_INSERT_PREFIX + placeholders.join(', '), args);
        this.writeCount += batch.length;
        if (this.writeCount >= 100) {
          this.writeCount = 0;
          await this.prune();
        }
      } catch (error) {
        logger.warn(TAG, '批量保存观测失败(' + batch.length.toString() + ' 条): ' + this.errorMessage(error));
      }
    });
    return this.writeChain;
  }

  /** 立刻把缓冲区写盘（切后台 / 退出前调用）。 */
  async flush(): Promise<void> {
    this.cancelFlushTimer();
    await this.writePending();
  }

  async loadRecent(limit: number = 500): Promise<Array<FieldwatchStoredObservation>> {
    const result: Array<FieldwatchStoredObservation> = [];
    if (!await this.initialize()) return result;
    try {
      // **按设备取最新一行，而不是取最新的 N 行原始记录。**
      //
      // 原版 `LogStore.readRadios()` 的注释是「One unique radio collapsed from many log rows」——
      // 恢复要的是「有哪些设备」，不是「最近几秒的原始流水」。
      //
      // 旧写法 `ORDER BY seen_at DESC LIMIT 500` 有两个问题（真机实测）：
      //   ① BLE 约 54 行/秒，500 行只覆盖 **约 9 秒** 的历史；
      //   ② 于是窗口被 BLE 独占 —— 实测最新 500 行 **ble 500 / wifi 0**，
      //      而库里明明有 64 台 Wi-Fi 设备。
      // 改成每 key 取最新一行后，实测可覆盖全部 **149 台（ble 85 / wifi 64）**。
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT observation_key, kind, address, name, rssi, seen_at, ssid, frequency_mhz, band, channel_width, security_type, fresh '
        + 'FROM fieldwatch_observations '
        + 'WHERE id IN (SELECT MAX(id) FROM fieldwatch_observations GROUP BY observation_key) '
        + 'ORDER BY seen_at DESC LIMIT ?', [limit]);
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const item: FieldwatchStoredObservation = new FieldwatchStoredObservation();
        item.key = String(row['observation_key'] ?? '');
        // 必须显式识别星闪，否则持久化的星闪观测重启后会被当成 BLE。
        const storedKind: string = String(row['kind'] ?? '');
        item.kind = storedKind === RadioKind.WIFI ? RadioKind.WIFI
          : (storedKind === RadioKind.NEARLINK ? RadioKind.NEARLINK : RadioKind.BLE);
        item.address = String(row['address'] ?? '');
        item.name = String(row['name'] ?? '');
        item.rssi = Number(row['rssi'] ?? 0);
        item.seenAt = Number(row['seen_at'] ?? 0);
        item.ssid = String(row['ssid'] ?? '');
        item.frequencyMhz = Number(row['frequency_mhz'] ?? 0);
        item.band = Number(row['band'] ?? 0);
        item.channelWidth = Number(row['channel_width'] ?? 0);
        item.securityType = Number(row['security_type'] ?? 0);
        item.fresh = this.readBoolean(row['fresh']);
        if (item.key.length > 0) result.push(item);
      });
    } catch (error) {
      logger.warn(TAG, '读取观测失败: ' + this.errorMessage(error));
    }
    return result;
  }

  async loadObservationKeysBetween(startedAt: number, endedAt: number): Promise<Array<string>> {
    const keys: Array<string> = [];
    if (!await this.initialize()) return keys;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT DISTINCT observation_key FROM fieldwatch_observations WHERE seen_at >= ? AND seen_at <= ?',
        [startedAt, endedAt]
      );
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const key: string = String(row['observation_key'] ?? '');
        if (key.length > 0) keys.push(key);
      });
    } catch (error) {
      logger.warn(TAG, '读取 sit 观测设备失败: ' + this.errorMessage(error));
    }
    return keys;
  }

  async saveSit(summary: SitSummary, deviceKeys: string[] = summary.deviceKeys): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('INSERT OR REPLACE INTO fieldwatch_sits (sit_id, name, started_at, ended_at, radio_count, device_keys) VALUES (?, ?, ?, ?, ?, ?)', [summary.id, summary.name, summary.startedAt, summary.endedAt, summary.radioCount, JSON.stringify(deviceKeys)]);
      return true;
    } catch (error) {
      logger.warn(TAG, '保存 sit 失败: ' + this.errorMessage(error));
      return false;
    }
  }

  async loadSits(): Promise<Array<FieldwatchStoredSit>> {
    const result: Array<FieldwatchStoredSit> = [];
    if (!await this.initialize()) return result;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql('SELECT sit_id, name, started_at, ended_at, radio_count, device_keys FROM fieldwatch_sits ORDER BY started_at DESC');
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const deviceKeys: string[] = this.readDeviceKeys(row['device_keys']);
        result.push(new FieldwatchStoredSit(String(row['sit_id'] ?? ''), String(row['name'] ?? ''), Number(row['started_at'] ?? 0), Number(row['ended_at'] ?? 0), Number(row['radio_count'] ?? 0), deviceKeys));
      });
    } catch (error) {
      logger.warn(TAG, '读取 sit 失败: ' + this.errorMessage(error));
    }
    return result;
  }

  async deleteSit(id: string): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM fieldwatch_sits WHERE sit_id = ?', [id]);
      return true;
    } catch (error) {
      logger.warn(TAG, '删除 sit 失败: ' + this.errorMessage(error));
      return false;
    }
  }

  async clearObservations(): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM fieldwatch_observations');
      this.writeCount = 0;
      return true;
    } catch (error) {
      logger.warn(TAG, '清理观测失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private async initializeStore(): Promise<boolean> {
    try {
      const created: boolean = await ngfRdbManager.init({ name: 'fieldwatch.db', securityLevel: 1 }, [
        'CREATE TABLE IF NOT EXISTS fieldwatch_observations (id INTEGER PRIMARY KEY AUTOINCREMENT, observation_key TEXT NOT NULL, kind TEXT NOT NULL, address TEXT NOT NULL, name TEXT, rssi REAL, seen_at INTEGER NOT NULL, ssid TEXT, frequency_mhz REAL, band INTEGER, channel_width INTEGER, security_type INTEGER, fresh INTEGER)',
        'CREATE INDEX IF NOT EXISTS idx_fieldwatch_observations_seen_at ON fieldwatch_observations (seen_at DESC)',
        'CREATE TABLE IF NOT EXISTS fieldwatch_sits (sit_id TEXT PRIMARY KEY, name TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, radio_count INTEGER NOT NULL, device_keys TEXT NOT NULL DEFAULT \'[]\')',
        'CREATE TABLE IF NOT EXISTS fieldwatch_schema (version INTEGER NOT NULL)'
      ]);
      this.initialized = created;
      // Execute the schema contract for both first install and existing stores.
      await ngfRdbManager.executeSql('CREATE TABLE IF NOT EXISTS fieldwatch_observations (id INTEGER PRIMARY KEY AUTOINCREMENT, observation_key TEXT NOT NULL, kind TEXT NOT NULL, address TEXT NOT NULL, name TEXT, rssi REAL, seen_at INTEGER NOT NULL, ssid TEXT, frequency_mhz REAL, band INTEGER, channel_width INTEGER, security_type INTEGER, fresh INTEGER)');
      await ngfRdbManager.executeSql('CREATE INDEX IF NOT EXISTS idx_fieldwatch_observations_seen_at ON fieldwatch_observations (seen_at DESC)');
      await ngfRdbManager.executeSql('CREATE TABLE IF NOT EXISTS fieldwatch_sits (sit_id TEXT PRIMARY KEY, name TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, radio_count INTEGER NOT NULL, device_keys TEXT NOT NULL DEFAULT \'[]\')');
      await ngfRdbManager.executeSql('CREATE TABLE IF NOT EXISTS fieldwatch_schema (version INTEGER NOT NULL)');
      await ngfRdbManager.executeSql('INSERT INTO fieldwatch_schema (version) SELECT 3 WHERE NOT EXISTS (SELECT 1 FROM fieldwatch_schema)');
      await ngfRdbManager.executeSql('UPDATE fieldwatch_schema SET version = 3 WHERE version < 3');
      await this.ensureSitDeviceKeysColumn();
      if (!created) logger.warn(TAG, 'Fieldwatch RDB 初始化返回 false');
      return created;
    } catch (error) {
      logger.warn(TAG, 'Fieldwatch RDB 初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private errorMessage(error: Object): string { return error instanceof Error ? error.message : String(error); }
  private async prune(): Promise<void> {
    try {
      await ngfRdbManager.executeSql('DELETE FROM fieldwatch_observations WHERE id NOT IN (SELECT id FROM fieldwatch_observations ORDER BY seen_at DESC LIMIT 5000)');
    } catch (error) {
      logger.warn(TAG, '清理旧观测失败: ' + this.errorMessage(error));
    }
  }
  private readBoolean(value: string | number | boolean | undefined): boolean {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    return value === '1' || value === 'true';
  }

  private readDeviceKeys(value: string | number | boolean | undefined): string[] {
    if (typeof value !== 'string' || value.length === 0) return [];
    try {
      const parsed: string[] = JSON.parse(value) as string[];
      return parsed.filter((key: string): boolean => key.length > 0);
    } catch (error) {
      logger.warn(TAG, '读取 sit 设备快照失败: ' + this.errorMessage(error));
      return [];
    }
  }

  private async ensureSitDeviceKeysColumn(): Promise<void> {
    try {
      await ngfRdbManager.executeSql('ALTER TABLE fieldwatch_sits ADD COLUMN device_keys TEXT NOT NULL DEFAULT \'[]\'');
    } catch (error) {
      // Existing API26 databases already have the column; duplicate-column is harmless.
      logger.debug(TAG, 'sit 设备快照字段已存在或无需迁移: ' + this.errorMessage(error));
    }
  }
}
