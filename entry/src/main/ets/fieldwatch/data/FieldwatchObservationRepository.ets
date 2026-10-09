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

export class FieldwatchObservationRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined;
  private writeChain: Promise<void> = Promise.resolve();
  private writeCount: number = 0;

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  async append(observation: ScanObservation): Promise<void> {
    this.writeChain = this.writeChain.then(async (): Promise<void> => {
      if (!await this.initialize()) return;
      try {
        await ngfRdbManager.executeSql(
          'INSERT INTO fieldwatch_observations (observation_key, kind, address, name, rssi, seen_at, ssid, frequency_mhz, band, channel_width, security_type, fresh) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [observation.key, observation.kind, observation.address, observation.name, observation.rssi, observation.seenAt, observation.facts.ssid, observation.facts.frequencyMhz, observation.facts.band, observation.facts.channelWidth, observation.facts.securityType, observation.fresh]
        );
        this.writeCount += 1;
        if (this.writeCount % 100 === 0) await this.prune();
      } catch (error) {
        logger.warn(TAG, '保存观测失败: ' + this.errorMessage(error));
      }
    });
    await this.writeChain;
  }

  async flush(): Promise<void> {
    await this.writeChain;
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
