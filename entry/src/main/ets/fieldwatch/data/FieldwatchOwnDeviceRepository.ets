import { logger, ngfRdbManager } from 'ngf_framework';
import { GpsSample, RadioKind } from '../domain/FieldwatchModels';
import { SignatureClass } from '../domain/FieldwatchModels';
import { OwnDevice, OwnDeviceFingerprint } from '../domain/FieldwatchOwnDevice';

const TAG: string = 'FieldwatchOwnDeviceRepository';

/** 本仓储负责的表；表名与文档落地点五一致。 */
const TABLE: string = 'fieldwatch_own_devices';

/**
 * 自有设备档案的落库映射。
 *
 * **为什么单独抽一层**：`ngfRdbManager.querySql` 回来的是
 * `Record<string, string | number | boolean>`（弱类型），而 RDB 里没有布尔、
 * 也没有嵌套对象 —— 布尔要存 0/1，指纹要存 JSON 文本，位置要拆成 lat/lon +
 * 「有没有位置」标志。这些转换是**纯函数**，可以在 LocalUnit 里逐字段钉住；
 * 仓储本身只负责 SQL 与生命周期。
 */
export class OwnDeviceRecord {
  public id: string = '';
  public displayName: string = '';
  public kind: string = '';
  public virtualAddress: string = '';
  /** 0/1。 */
  public addressStable: number = 0;
  public category: string = '';
  /** 指纹 JSON 文本。 */
  public fingerprint: string = '';
  /** 拉黑指纹 JSON 数组文本。 */
  public denyFingerprints: string = '[]';
  public lastSeenAt: number = 0;
  /** 位置：`hasLocation = 0` 时 lat/lon 无意义（RDB 里没有 undefined）。 */
  public hasLocation: number = 0;
  public lastLat: number = 0;
  public lastLon: number = 0;
  public createdAt: number = 0;
  public claimSource: string = '';
}

function fingerprintJson(fingerprint: OwnDeviceFingerprint): string {
  try {
    return JSON.stringify(fingerprint);
  } catch (error) {
    logger.warn(TAG, '序列化指纹失败: ' + String(error));
    return '{}';
  }
}

function parseFingerprint(text: string): OwnDeviceFingerprint {
  const fingerprint: OwnDeviceFingerprint = new OwnDeviceFingerprint();
  if (text.length === 0) return fingerprint;
  try {
    const raw: OwnDeviceFingerprint = JSON.parse(text) as OwnDeviceFingerprint;
    if (raw === null || raw === undefined) return fingerprint;
    // 逐字段拷贝而不是直接使用解析结果：旧版本档案可能没有新字段，
    // 漏掉的那部分要拿到构造默认值，而不是 undefined。
    fingerprint.name = raw.name === undefined ? '' : raw.name;
    fingerprint.manufacturerDataHex = raw.manufacturerDataHex === undefined ? '' : raw.manufacturerDataHex;
    fingerprint.serviceUuids = raw.serviceUuids === undefined ? [] : raw.serviceUuids;
    fingerprint.signatureIds = raw.signatureIds === undefined ? [] : raw.signatureIds;
  } catch (error) {
    logger.warn(TAG, '解析指纹失败（按空指纹处理）: ' + String(error));
  }
  return fingerprint;
}

function parseDenyList(text: string): OwnDeviceFingerprint[] {
  const out: OwnDeviceFingerprint[] = [];
  if (text.length === 0) return out;
  try {
    const raw: OwnDeviceFingerprint[] = JSON.parse(text) as OwnDeviceFingerprint[];
    if (raw === null || raw === undefined) return out;
    raw.forEach((item: OwnDeviceFingerprint): void => {
      const fingerprint: OwnDeviceFingerprint = new OwnDeviceFingerprint();
      fingerprint.name = item.name === undefined ? '' : item.name;
      fingerprint.manufacturerDataHex = item.manufacturerDataHex === undefined ? '' : item.manufacturerDataHex;
      fingerprint.serviceUuids = item.serviceUuids === undefined ? [] : item.serviceUuids;
      fingerprint.signatureIds = item.signatureIds === undefined ? [] : item.signatureIds;
      out.push(fingerprint);
    });
  } catch (error) {
    logger.warn(TAG, '解析拉黑指纹失败（按空列表处理）: ' + String(error));
  }
  return out;
}

/**
 * 落库字符串 → 类别。
 *
 * **ArkTS 不做字符串到枚举的隐式转换**（与观测仓储处理 `kind` 的写法同源）：
 * 只能逐值比对；认不出来的落 `OTHER` —— 宁可显示通用图标，也不猜类别。
 */
function categoryOf(stored: string): SignatureClass {
  const values: SignatureClass[] = [
    SignatureClass.FINDER, SignatureClass.BEACON, SignatureClass.SIGNAGE, SignatureClass.WEARABLE,
    SignatureClass.SURVEILLANCE, SignatureClass.DRONE, SignatureClass.HACKING, SignatureClass.BODYWORN,
    SignatureClass.LAW_ENFORCEMENT, SignatureClass.VEHICLE, SignatureClass.GLASSES, SignatureClass.AUDIO,
    SignatureClass.CAMERA, SignatureClass.THERMOSTAT, SignatureClass.LOCK, SignatureClass.HEALTH,
    SignatureClass.HOME, SignatureClass.ISP, SignatureClass.ROUTER, SignatureClass.MESH,
    SignatureClass.PHONE, SignatureClass.OTHER
  ];
  let found: SignatureClass = SignatureClass.OTHER;
  values.forEach((value: SignatureClass): void => {
    if (value === stored) found = value;
  });
  return found;
}

/** 落库字符串 → 无线电种类（必须显式识别星闪，否则重启后会被当成 BLE）。 */
function kindOf(stored: string): RadioKind {
  if (stored === RadioKind.WIFI) return RadioKind.WIFI;
  if (stored === RadioKind.NEARLINK) return RadioKind.NEARLINK;
  return RadioKind.BLE;
}

/** 档案 → 落库视图（纯函数）。 */
export function recordOf(device: OwnDevice): OwnDeviceRecord {
  const record: OwnDeviceRecord = new OwnDeviceRecord();
  record.id = device.id;
  record.displayName = device.displayName;
  record.kind = device.kind;
  record.virtualAddress = device.virtualAddress;
  record.addressStable = device.addressStable ? 1 : 0;
  record.category = device.category;
  record.fingerprint = fingerprintJson(device.fingerprint);
  record.denyFingerprints = JSON.stringify(device.denyFingerprints);
  record.lastSeenAt = device.lastSeenAt;
  const location: GpsSample | undefined = device.lastLocation;
  record.hasLocation = location === undefined ? 0 : 1;
  record.lastLat = location === undefined ? 0 : location.latitude;
  record.lastLon = location === undefined ? 0 : location.longitude;
  record.createdAt = device.createdAt;
  record.claimSource = device.claimSource;
  return record;
}

/** 落库视图 → 档案（纯函数）。 */
export function deviceOf(record: OwnDeviceRecord): OwnDevice {
  const device: OwnDevice = new OwnDevice();
  device.id = record.id;
  device.displayName = record.displayName;
  device.kind = kindOf(record.kind);
  device.virtualAddress = record.virtualAddress;
  device.addressStable = record.addressStable === 1;
  device.category = categoryOf(record.category);
  device.fingerprint = parseFingerprint(record.fingerprint);
  device.denyFingerprints = parseDenyList(record.denyFingerprints);
  device.lastSeenAt = record.lastSeenAt;
  device.lastLocation = record.hasLocation === 1 ? new GpsSample(record.lastLat, record.lastLon, record.lastSeenAt) : undefined;
  device.createdAt = record.createdAt;
  device.claimSource = record.claimSource;
  return device;
}

/**
 * 自有设备档案仓储（表 `fieldwatch_own_devices`）。
 *
 * 与 `FieldwatchObservationRepository` 同一套 RDB 用法（`ngfRdbManager` + 幂等建表），
 * 但**不与它共用写队列**：档案是低频、用户主动触发的写入，没必要排进观测那条每秒级的链。
 */
export class FieldwatchOwnDeviceRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined;

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  /** 新增或覆盖一台档案。 */
  async save(device: OwnDevice): Promise<boolean> {
    if (!await this.initialize()) return false;
    const record: OwnDeviceRecord = recordOf(device);
    try {
      await ngfRdbManager.executeSql(
        'INSERT OR REPLACE INTO ' + TABLE + ' (device_id, display_name, kind, virtual_address, address_stable,'
        + ' category, fingerprint, deny_fingerprints, last_seen_at, has_location, last_lat, last_lon, created_at, claim_source)'
        + ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [record.id, record.displayName, record.kind, record.virtualAddress, record.addressStable,
          record.category, record.fingerprint, record.denyFingerprints, record.lastSeenAt,
          record.hasLocation, record.lastLat, record.lastLon, record.createdAt, record.claimSource]
      );
      return true;
    } catch (error) {
      logger.warn(TAG, '保存自有设备失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 全部档案，最近认领的在前。 */
  async loadAll(): Promise<OwnDevice[]> {
    const out: OwnDevice[] = [];
    if (!await this.initialize()) return out;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(
        'SELECT device_id, display_name, kind, virtual_address, address_stable, category, fingerprint,'
        + ' deny_fingerprints, last_seen_at, has_location, last_lat, last_lon, created_at, claim_source'
        + ' FROM ' + TABLE + ' ORDER BY created_at DESC');
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        out.push(deviceOf(this.readRow(row)));
      });
    } catch (error) {
      logger.warn(TAG, '读取自有设备失败: ' + this.errorMessage(error));
    }
    return out;
  }

  /** 删除一台档案（用户「这不是我的」到彻底移除时用）。 */
  async remove(id: string): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM ' + TABLE + ' WHERE device_id = ?', [id]);
      return true;
    } catch (error) {
      logger.warn(TAG, '删除自有设备失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /**
   * 回写「上次见到」。
   *
   * 这是唯一会被观测流高频调用的方法（每命中一次自有设备就写一行时间），
   * 所以只更新两列；位置为空时**保留原有位置**而不是清掉 —— 用户上次在哪里见到过，
   * 比「这次没带位置信息」更有价值。
   */
  async updateLastSeen(id: string, seenAt: number, location: GpsSample | undefined): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      if (location === undefined) {
        await ngfRdbManager.executeSql('UPDATE ' + TABLE + ' SET last_seen_at = ? WHERE device_id = ?', [seenAt, id]);
      } else {
        await ngfRdbManager.executeSql(
          'UPDATE ' + TABLE + ' SET last_seen_at = ?, has_location = 1, last_lat = ?, last_lon = ? WHERE device_id = ?',
          [seenAt, location.latitude, location.longitude, id]);
      }
      return true;
    } catch (error) {
      logger.warn(TAG, '回写上次见到失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 清空全部档案（设置页「清除自有设备」）。 */
  async clear(): Promise<boolean> {
    if (!await this.initialize()) return false;
    try {
      await ngfRdbManager.executeSql('DELETE FROM ' + TABLE);
      return true;
    } catch (error) {
      logger.warn(TAG, '清空自有设备失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private async initializeStore(): Promise<boolean> {
    try {
      await ngfRdbManager.executeSql(
        'CREATE TABLE IF NOT EXISTS ' + TABLE + ' (device_id TEXT PRIMARY KEY, display_name TEXT NOT NULL,'
        + ' kind TEXT NOT NULL, virtual_address TEXT NOT NULL DEFAULT \'\', address_stable INTEGER NOT NULL DEFAULT 0,'
        + ' category TEXT NOT NULL DEFAULT \'other\', fingerprint TEXT NOT NULL DEFAULT \'{}\','
        + ' deny_fingerprints TEXT NOT NULL DEFAULT \'[]\', last_seen_at INTEGER NOT NULL DEFAULT 0,'
        + ' has_location INTEGER NOT NULL DEFAULT 0, last_lat REAL NOT NULL DEFAULT 0, last_lon REAL NOT NULL DEFAULT 0,'
        + ' created_at INTEGER NOT NULL DEFAULT 0, claim_source TEXT NOT NULL DEFAULT \'\')');
      // 版本下限抬到 4：观测仓储只读自己的两张表，`fieldwatch_schema` 全仓只写不读，
      // 抬升不会影响它的 `UPDATE ... WHERE version < 3`（4 不小于 3，天然是 no-op）。
      await ngfRdbManager.executeSql('UPDATE fieldwatch_schema SET version = 4 WHERE version < 4');
      this.initialized = true;
      return true;
    } catch (error) {
      logger.warn(TAG, '建表失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /** 弱类型行 → 落库视图（唯一需要按列名取值的地方）。 */
  private readRow(row: Record<string, string | number | boolean>): OwnDeviceRecord {
    const record: OwnDeviceRecord = new OwnDeviceRecord();
    record.id = String(row['device_id'] ?? '');
    record.displayName = String(row['display_name'] ?? '');
    record.kind = String(row['kind'] ?? '');
    record.virtualAddress = String(row['virtual_address'] ?? '');
    record.addressStable = Number(row['address_stable'] ?? 0);
    record.category = String(row['category'] ?? 'other');
    record.fingerprint = String(row['fingerprint'] ?? '{}');
    record.denyFingerprints = String(row['deny_fingerprints'] ?? '[]');
    record.lastSeenAt = Number(row['last_seen_at'] ?? 0);
    record.hasLocation = Number(row['has_location'] ?? 0);
    record.lastLat = Number(row['last_lat'] ?? 0);
    record.lastLon = Number(row['last_lon'] ?? 0);
    record.createdAt = Number(row['created_at'] ?? 0);
    record.claimSource = String(row['claim_source'] ?? '');
    return record;
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
