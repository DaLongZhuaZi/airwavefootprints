import { logger, ngfRdbManager } from 'ngf_framework';
import { OwnDeviceFingerprint, OwnDeviceKind, OwnDeviceProfile } from '../domain/FieldwatchOwnDevice';

const TAG: string = 'FieldwatchOwnDeviceRepository';

/**
 * 与 `FieldwatchObservationRepository` **共用同一个库文件**。
 *
 * 不新建第二个库的理由：`ngfRdbManager` 是单例门面，`init()` 在已初始化时会直接
 * 返回 true（见 RdbManagerFacade）。两个库名并存意味着两份 StoreConfig、两套版本号、
 * 两条初始化时序，而这个功能的数据量只有几十行 —— 为一个档案表再开一个库，
 * 收益为零、出错面翻倍。
 *
 * 当前 schema 版本仍由观测侧维护（fieldwatch_schema），本文件**不改版本号**：
 * 追加一张表用 `CREATE TABLE IF NOT EXISTS` 就够了，动别人的版本号只会制造迁移歧义。
 */
const DB_NAME: string = 'fieldwatch.db';
const DB_SECURITY_LEVEL: number = 1;

const CREATE_TABLE_SQL: string =
  'CREATE TABLE IF NOT EXISTS fieldwatch_own_devices ('
  + 'profile_id TEXT PRIMARY KEY, '
  + 'persistent_id TEXT NOT NULL DEFAULT \'\', '
  + 'virtual_address TEXT NOT NULL DEFAULT \'\', '
  + 'device_key TEXT NOT NULL DEFAULT \'\', '
  + 'display_name TEXT NOT NULL DEFAULT \'\', '
  + 'custom_name TEXT NOT NULL DEFAULT \'\', '
  + 'kind TEXT NOT NULL DEFAULT \'other\', '
  + 'device_class INTEGER NOT NULL DEFAULT -1, '
  + 'fingerprint TEXT NOT NULL DEFAULT \'{}\', '
  + 'deny_fingerprints TEXT NOT NULL DEFAULT \'[]\', '
  + 'last_seen_at INTEGER NOT NULL DEFAULT 0, '
  + 'last_latitude REAL NOT NULL DEFAULT 0, '
  + 'last_longitude REAL NOT NULL DEFAULT 0, '
  + 'claimed_at INTEGER NOT NULL DEFAULT 0, '
  + 'source TEXT NOT NULL DEFAULT \'\')';

/**
 * 索引建在 `last_seen_at` 上，与索引名一致。
 *
 * `loadAll()` 的排序键是 `claimed_at DESC`（认领先后才是用户感知的顺序），
 * 但档案总数是「用户亲手认领过的设备」量级 —— 实测不会有几十行，
 * 排序开销可以忽略；反过来，「上次见到是什么时候」才是将来看板要频繁扫的列。
 * 为一个几十行的表再建第二个索引，属于用不上还拖慢写入的优化。
 */
const CREATE_INDEX_SQL: string =
  'CREATE INDEX IF NOT EXISTS idx_fieldwatch_own_devices_last_seen ON fieldwatch_own_devices (last_seen_at DESC)';

const UPSERT_SQL: string =
  'INSERT OR REPLACE INTO fieldwatch_own_devices ('
  + 'profile_id, persistent_id, virtual_address, device_key, display_name, custom_name, '
  + 'kind, device_class, fingerprint, deny_fingerprints, last_seen_at, last_latitude, '
  + 'last_longitude, claimed_at, source'
  + ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

const SELECT_ALL_SQL: string =
  'SELECT profile_id, persistent_id, virtual_address, device_key, display_name, custom_name, '
  + 'kind, device_class, fingerprint, deny_fingerprints, last_seen_at, last_latitude, '
  + 'last_longitude, claimed_at, source '
  + 'FROM fieldwatch_own_devices ORDER BY claimed_at DESC';

/**
 * 「我的设备」档案的持久化仓储。
 *
 * 写路径全部串在 `writeChain` 上（与观测仓储同一套做法）：
 * RDB 的 executeSql 虽然是异步的，但多条写并行发出时顺序由系统调度决定，
 * 「先认领后改名」这类连续操作可能落地成「先改名后认领」，把用户改的名字冲掉。
 * 串行化保证「调用顺序 = 落盘顺序」，代价只是几十毫秒的排队。
 */
export class FieldwatchOwnDeviceRepository {
  private initialized: boolean = false;
  private initializing: Promise<boolean> | undefined = undefined;
  private writeChain: Promise<void> = Promise.resolve();

  async initialize(): Promise<boolean> {
    if (this.initialized) return true;
    if (this.initializing !== undefined) return await this.initializing;
    this.initializing = this.initializeStore();
    const result: boolean = await this.initializing;
    this.initializing = undefined;
    return result;
  }

  /**
   * 把一次写操作排进写队列，并返回队尾。
   *
   * 末尾那个 `catch` 不是多余的：Promise 链一旦进入 rejected 状态，
   * 后续所有 `.then` 都会被直接跳过 —— 一次意外异常就会让写队列**永久卡死**，
   * 之后每次保存都静默失败。这里把它兜回 resolved，让下一个写操作仍有成功机会，
   * 本次失败由调用方按返回值（false）感知。
   */
  private queue(work: () => Promise<void>): Promise<void> {
    this.writeChain = this.writeChain.then(async (): Promise<void> => {
      await work();
    }).catch((error: Object): void => {
      logger.warn(TAG, '我的设备写队列异常: ' + this.errorMessage(error));
    });
    return this.writeChain;
  }

  /** 写入一份档案（按 profile_id 覆盖）。id 为空直接拒绝：主键为空的行取不回来。 */
  async save(profile: OwnDeviceProfile): Promise<boolean> {
    let saved: boolean = false;
    await this.queue(async (): Promise<void> => {
      saved = await this.writeProfile(profile);
    });
    return saved;
  }

  /**
   * 批量写入。整批串成一次任务，不做事务 ——
   * 单条 INSERT OR REPLACE 本身是原子的，中途失败只会留下「已写的那几条」，
   * 而档案是幂等的覆盖写，下次认领会自动补齐，没有需要回滚的中间态。
   */
  async saveAll(profiles: OwnDeviceProfile[]): Promise<boolean> {
    if (profiles.length === 0) return true;
    let allSaved: boolean = true;
    await this.queue(async (): Promise<void> => {
      for (let index: number = 0; index < profiles.length; index += 1) {
        const ok: boolean = await this.writeProfile(profiles[index]);
        if (!ok) allSaved = false;
      }
    });
    return allSaved;
  }

  /** 按认领时间倒序读取全部档案。坏行逐条跳过，不因为一行脏数据让整个列表变空。 */
  async loadAll(): Promise<OwnDeviceProfile[]> {
    const result: OwnDeviceProfile[] = [];
    if (!await this.initialize()) return result;
    try {
      const rows: Array<Record<string, string | number | boolean>> = await ngfRdbManager.querySql(SELECT_ALL_SQL);
      rows.forEach((row: Record<string, string | number | boolean>): void => {
        const profile: OwnDeviceProfile | undefined = this.readProfile(row);
        if (profile !== undefined) result.push(profile);
      });
    } catch (error) {
      logger.warn(TAG, '读取我的设备档案失败: ' + this.errorMessage(error));
    }
    return result;
  }

  /** 删除一份档案（删的是「我认为这台是我的」这条记录，不碰设备本身）。 */
  async remove(profileId: string): Promise<boolean> {
    const id: string = profileId.trim();
    if (id.length === 0) return false;
    let removed: boolean = false;
    await this.queue(async (): Promise<void> => {
      if (!await this.initialize()) return;
      try {
        await ngfRdbManager.executeSql('DELETE FROM fieldwatch_own_devices WHERE profile_id = ?', [id]);
        removed = true;
      } catch (error) {
        logger.warn(TAG, '删除我的设备档案失败: ' + this.errorMessage(error));
      }
    });
    return removed;
  }

  /** 清空全部档案（设置页的「清空我的设备」）。 */
  async clear(): Promise<boolean> {
    let cleared: boolean = false;
    await this.queue(async (): Promise<void> => {
      if (!await this.initialize()) return;
      try {
        await ngfRdbManager.executeSql('DELETE FROM fieldwatch_own_devices');
        cleared = true;
      } catch (error) {
        logger.warn(TAG, '清空我的设备档案失败: ' + this.errorMessage(error));
      }
    });
    return cleared;
  }

  /** 实际写一行；调用方必须已经在 writeChain 里，这里不再排队。 */
  private async writeProfile(profile: OwnDeviceProfile | undefined | null): Promise<boolean> {
    if (profile === undefined || profile === null) return false;
    if (!await this.initialize()) return false;
    try {
      const id: string = profile.id.trim();
      if (id.length === 0) {
        // 主键为空写进去也读不回来（主键覆盖与将来按 id 更新都靠它），索性不写。
        logger.warn(TAG, '拒绝保存没有 id 的设备档案');
        return false;
      }
      await ngfRdbManager.executeSql(UPSERT_SQL, [
        id,
        profile.persistentId,
        profile.virtualAddress,
        profile.deviceKey,
        profile.displayName,
        profile.customName,
        String(profile.kind),
        profile.deviceClass,
        this.writeFingerprint(profile.fingerprint),
        this.writeFingerprints(profile.denyFingerprints),
        profile.lastSeenAt,
        profile.lastLatitude,
        profile.lastLongitude,
        profile.claimedAt,
        profile.source
      ]);
      return true;
    } catch (error) {
      logger.warn(TAG, '保存我的设备档案失败: ' + this.errorMessage(error));
      return false;
    }
  }

  private async initializeStore(): Promise<boolean> {
    try {
      const created: boolean = await ngfRdbManager.init(
        { name: DB_NAME, securityLevel: DB_SECURITY_LEVEL },
        [CREATE_TABLE_SQL, CREATE_INDEX_SQL]
      );
      if (!created) {
        // init() 返回 false 只有一种含义：库没打开（通常是还没有 UIAbilityContext，
        // 或首次取库失败）。此时 executeSql 必然抛「尚未初始化」，不必再试一遍。
        logger.warn(TAG, '我的设备 RDB 初始化返回 false');
        return false;
      }
      this.initialized = true;
      // 与观测仓储同样的道理：init() 只在 store.version === 0 时执行建表语句，
      // 而本表是**后加**的 —— 老用户的库里 version 已经是 1，init() 会直接返回 true，
      // 一条建表语句都不会执行。所以这里无条件再跑一遍 IF NOT EXISTS。
      await ngfRdbManager.executeSql(CREATE_TABLE_SQL);
      await ngfRdbManager.executeSql(CREATE_INDEX_SQL);
      return true;
    } catch (error) {
      logger.warn(TAG, '我的设备 RDB 初始化失败: ' + this.errorMessage(error));
      return false;
    }
  }

  /**
   * 一行 → 一份档案。任何字段读坏都只让**这一行**被跳过（返回 undefined），
   * 绝不让脏数据把整个列表带崩 —— 用户的档案丢了比列表暂时少一台更难受。
   */
  private readProfile(row: Record<string, string | number | boolean>): OwnDeviceProfile | undefined {
    const id: string = this.readText(row['profile_id']).trim();
    if (id.length === 0) return undefined;
    const fingerprint: OwnDeviceFingerprint | undefined = this.readFingerprint(row['fingerprint']);
    if (fingerprint === undefined) return undefined;
    const profile: OwnDeviceProfile = new OwnDeviceProfile(
      id,
      this.readText(row['persistent_id']),
      this.readText(row['virtual_address']),
      this.readText(row['device_key']),
      this.readText(row['display_name']),
      this.readKind(row['kind']),
      this.readNumber(row['device_class'], -1),
      fingerprint,
      this.readText(row['source'])
    );
    // 构造函数会重置这几项，必须在其后回填。
    profile.customName = this.readText(row['custom_name']);
    profile.denyFingerprints = this.readFingerprints(row['deny_fingerprints']);
    profile.lastSeenAt = this.readNumber(row['last_seen_at'], 0);
    profile.lastLatitude = this.readNumber(row['last_latitude'], 0);
    profile.lastLongitude = this.readNumber(row['last_longitude'], 0);
    profile.claimedAt = this.readNumber(row['claimed_at'], 0);
    return profile;
  }

  /** 指纹 → JSON。空指纹也照常写 `{}`，读回时会被还原成 empty()，不引入 NULL 分支。 */
  private writeFingerprint(fingerprint: OwnDeviceFingerprint | undefined | null): string {
    if (fingerprint === undefined || fingerprint === null) return '{}';
    try {
      return JSON.stringify(fingerprint);
    } catch (error) {
      logger.warn(TAG, '序列化指纹失败: ' + this.errorMessage(error));
      return '{}';
    }
  }

  private writeFingerprints(fingerprints: OwnDeviceFingerprint[] | undefined | null): string {
    if (fingerprints === undefined || fingerprints === null || fingerprints.length === 0) return '[]';
    try {
      return JSON.stringify(fingerprints);
    } catch (error) {
      logger.warn(TAG, '序列化指纹黑名单失败: ' + this.errorMessage(error));
      return '[]';
    }
  }

  /**
   * JSON → 指纹，**逐字段校验**。返回 undefined 表示这一行不可用。
   *
   * 为什么不直接 `JSON.parse(text) as OwnDeviceFingerprint` 就完事：
   * 解析出来的是普通对象，不带类的构造函数与清洗逻辑，字段可能是 null、
   * 可能少一个、数组里还可能混进字符串。直接当指纹用，坏数据会一路带进匹配器，
   * 在那边抛出的错离现场太远，排查时根本看不出是这一行脏了。
   */
  private readFingerprint(value: string | number | boolean | undefined | null): OwnDeviceFingerprint | undefined {
    const text: string = this.readText(value);
    if (text.length === 0) return OwnDeviceFingerprint.empty();
    try {
      const raw: OwnDeviceFingerprint | undefined | null = JSON.parse(text) as OwnDeviceFingerprint;
      if (raw === undefined || raw === null) return undefined;
      return new OwnDeviceFingerprint(
        this.readText(raw.name),
        this.readNumberList(raw.manufacturerIds),
        this.readTextList(raw.serviceUuids),
        this.readTextList(raw.signatureIds)
      );
    } catch (error) {
      logger.warn(TAG, '读取指纹快照失败: ' + this.errorMessage(error));
      return undefined;
    }
  }

  /** JSON → 指纹数组。单个元素坏掉只丢弃该元素，整行仍然可用。 */
  private readFingerprints(value: string | number | boolean | undefined | null): OwnDeviceFingerprint[] {
    const result: OwnDeviceFingerprint[] = [];
    const text: string = this.readText(value);
    if (text.length === 0) return result;
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (!Array.isArray(parsed)) return result;
      const values: OwnDeviceFingerprint[] = parsed as OwnDeviceFingerprint[];
      for (let index: number = 0; index < values.length; index += 1) {
        const item: OwnDeviceFingerprint | undefined | null = values[index];
        if (item === undefined || item === null) continue;
        result.push(new OwnDeviceFingerprint(
          this.readText(item.name),
          this.readNumberList(item.manufacturerIds),
          this.readTextList(item.serviceUuids),
          this.readTextList(item.signatureIds)
        ));
      }
    } catch (error) {
      logger.warn(TAG, '读取指纹黑名单失败: ' + this.errorMessage(error));
    }
    return result;
  }

  /** kind 是字符串枚举，只接受已知成员；库里出现别的一律当 OTHER。 */
  private readKind(value: string | number | boolean | undefined | null): OwnDeviceKind {
    const text: string = this.readText(value);
    if (text === OwnDeviceKind.HEADPHONES) return OwnDeviceKind.HEADPHONES;
    if (text === OwnDeviceKind.WATCH) return OwnDeviceKind.WATCH;
    if (text === OwnDeviceKind.SPEAKER) return OwnDeviceKind.SPEAKER;
    if (text === OwnDeviceKind.CAR) return OwnDeviceKind.CAR;
    if (text === OwnDeviceKind.TRACKER) return OwnDeviceKind.TRACKER;
    return OwnDeviceKind.OTHER;
  }

  /** 列值 → 字符串。querySql 把列以字符串返回，这里只兜「空/异常类型」。 */
  private readText(value: string | number | boolean | undefined | null): string {
    if (value === undefined || value === null) return '';
    if (typeof value === 'string') return value;
    return String(value);
  }

  /** 列值 → 数字。非数字（含 NaN）回落到 fallback，避免 NaN 一路传到 UI。 */
  private readNumber(value: string | number | boolean | undefined | null, fallback: number): number {
    if (value === undefined || value === null) return fallback;
    if (typeof value === 'number') return Number.isNaN(value) ? fallback : value;
    if (typeof value === 'boolean') return value ? 1 : 0;
    const parsed: number = Number(value);
    return Number.isNaN(parsed) ? fallback : parsed;
  }

  /** 任意 JSON 值 → string[]，丢掉非字符串与空串。 */
  private readTextList(source: string[] | undefined | null): string[] {
    const result: string[] = [];
    if (source === undefined || source === null) return result;
    if (!Array.isArray(source)) return result;
    for (let index: number = 0; index < source.length; index += 1) {
      const item: string = source[index];
      if (typeof item !== 'string') continue;
      const text: string = item.trim();
      if (text.length > 0) result.push(text);
    }
    return result;
  }

  /** 任意 JSON 值 → number[]，丢掉非数字与非有限值（NaN / Infinity）。 */
  private readNumberList(source: number[] | undefined | null): number[] {
    const result: number[] = [];
    if (source === undefined || source === null) return result;
    if (!Array.isArray(source)) return result;
    for (let index: number = 0; index < source.length; index += 1) {
      const item: number = source[index];
      if (typeof item !== 'number') continue;
      if (!Number.isFinite(item)) continue;
      result.push(item);
    }
    return result;
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}
