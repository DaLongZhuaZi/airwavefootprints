import { describe, expect, it } from '@ohos/hypium';
import { clearLocallyAdministered, FieldwatchRadioDb, isLocallyAdministered, isPhoneHouseVendor } from '../main/ets/fieldwatch/domain/FieldwatchRadioDb';
import { FieldwatchFilterEngine } from '../main/ets/fieldwatch/domain/FieldwatchDomainService';
import { FilterDefinition, RadioFacts, RadioKind, ScanObservation, Sighting } from '../main/ets/fieldwatch/domain/FieldwatchModels';

/**
 * 两条目的样本。必须有 >=2 条：只有一条时「key/idx 交替存放」与「先 key 后 idx」
 * 解析结果完全相同，无法暴露布局错误（这是真实踩过的坑）。
 */
function buildTwo(ouiA: number, nameA: string, ouiB: number, nameB: string): Uint8Array {
  const a: Uint8Array = new Uint8Array(nameA.length);
  for (let index: number = 0; index < nameA.length; index += 1) a[index] = nameA.charCodeAt(index);
  const b: Uint8Array = new Uint8Array(nameB.length);
  for (let index: number = 0; index < nameB.length; index += 1) b[index] = nameB.charCodeAt(index);
  const malAt: number = 40;
  const malSize: number = 4 + 2 * 4 + 2 * 2;
  const noffAt: number = malAt + malSize;
  const noffSize: number = 4 + 3 * 4;
  const nstrAt: number = noffAt + noffSize;
  const total: number = nstrAt + a.length + b.length;
  const buffer: ArrayBuffer = new ArrayBuffer(total);
  const bytes: Uint8Array = new Uint8Array(buffer);
  const view: DataView = new DataView(buffer);
  bytes[0] = 0x53; bytes[1] = 0x50; bytes[2] = 0x4C; bytes[3] = 0x4B;
  view.setUint16(4, 1, true);
  view.setUint16(6, 0, true);
  view.setInt32(8, 20260824, true);
  view.setInt32(12, 3, true);
  const tags: string[] = ['mal', 'noff', 'nstr'];
  const offs: number[] = [malAt, noffAt, nstrAt];
  for (let index: number = 0; index < 3; index += 1) {
    const at: number = 16 + index * 8;
    bytes[at] = tags[index].charCodeAt(0);
    bytes[at + 1] = tags[index].charCodeAt(1);
    bytes[at + 2] = tags[index].charCodeAt(2);
    bytes[at + 3] = tags[index].charCodeAt(3);
    view.setInt32(at + 4, offs[index], true);
  }
  view.setInt32(malAt, 2, true);
  view.setInt32(malAt + 4, ouiA, true);
  view.setInt32(malAt + 8, ouiB, true);
  view.setInt16(malAt + 12, 0, true);
  view.setInt16(malAt + 14, 1, true);
  view.setInt32(noffAt, 2, true);
  view.setInt32(noffAt + 4, 0, true);
  view.setInt32(noffAt + 8, a.length, true);
  view.setInt32(noffAt + 12, a.length + b.length, true);
  for (let index: number = 0; index < a.length; index += 1) bytes[nstrAt + index] = a[index];
  for (let index: number = 0; index < b.length; index += 1) bytes[nstrAt + a.length + index] = b[index];
  return bytes;
}


/**
 * 合成一个含 `long` 段（8 字节键）的 radiodb。
 *
 * `long` 段的键布局是 `(位宽 << 56) | 前缀值`，而 `36 << 56` 超出 JS 安全整数，
 * 所以**按两个 32 位半字写入**（与读取端一致）：低 32 位是值，高 32 位的高字节是位宽。
 * 键必须整体有序，而 0x1C 块（MA-M）天然排在 0x24 块（MA-S）之前，故先写 MA-M。
 */
function buildWithLong(malKey: number, malName: string, mamKey: number, mamName: string, masKey: number, masName: string): Uint8Array {
  const names: string[] = [malName, mamName, masName];
  const blobs: Uint8Array[] = [];
  for (let index: number = 0; index < names.length; index += 1) {
    const text: string = names[index];
    const blob: Uint8Array = new Uint8Array(text.length);
    for (let at: number = 0; at < text.length; at += 1) blob[at] = text.charCodeAt(at);
    blobs.push(blob);
  }
  const malAt: number = 48;
  const malSize: number = 4 + 1 * 4 + 1 * 2;
  const longAt: number = malAt + malSize;
  const longSize: number = 4 + 2 * 8 + 2 * 2;
  const noffAt: number = longAt + longSize;
  const noffSize: number = 4 + 4 * 4;
  const nstrAt: number = noffAt + noffSize;
  let nameTotal: number = 0;
  for (let index: number = 0; index < blobs.length; index += 1) nameTotal += blobs[index].length;
  const buffer: ArrayBuffer = new ArrayBuffer(nstrAt + nameTotal);
  const bytes: Uint8Array = new Uint8Array(buffer);
  const view: DataView = new DataView(buffer);
  bytes[0] = 0x53; bytes[1] = 0x50; bytes[2] = 0x4C; bytes[3] = 0x4B;
  view.setUint16(4, 1, true);
  view.setUint16(6, 0, true);
  view.setInt32(8, 20260824, true);
  view.setInt32(12, 4, true);
  const tags: string[] = ['mal', 'long', 'noff', 'nstr'];
  const offs: number[] = [malAt, longAt, noffAt, nstrAt];
  for (let index: number = 0; index < 4; index += 1) {
    const at: number = 16 + index * 8;
    bytes[at] = tags[index].charCodeAt(0);
    bytes[at + 1] = tags[index].charCodeAt(1);
    bytes[at + 2] = tags[index].charCodeAt(2);
    bytes[at + 3] = tags[index].charCodeAt(3);
    view.setInt32(at + 4, offs[index], true);
  }
  // mal：单条
  view.setInt32(malAt, 1, true);
  view.setInt32(malAt + 4, malKey, true);
  view.setInt16(malAt + 8, 0, true);
  // long：MA-M 在前（0x1C），MA-S 在后（0x24）
  view.setInt32(longAt, 2, true);
  const keyAt: number = longAt + 4;
  writeLongKey(view, keyAt, 28, mamKey);
  writeLongKey(view, keyAt + 8, 36, masKey);
  view.setInt16(keyAt + 16, 1, true);
  view.setInt16(keyAt + 18, 2, true);
  // noff / nstr
  view.setInt32(noffAt, 3, true);
  view.setInt32(noffAt + 4, 0, true);
  view.setInt32(noffAt + 8, blobs[0].length, true);
  view.setInt32(noffAt + 12, blobs[0].length + blobs[1].length, true);
  view.setInt32(noffAt + 16, nameTotal, true);
  let cursor: number = nstrAt;
  for (let index: number = 0; index < blobs.length; index += 1) {
    for (let at: number = 0; at < blobs[index].length; at += 1) bytes[cursor + at] = blobs[index][at];
    cursor += blobs[index].length;
  }
  return bytes;
}

/** 写入 8 字节键：低 32 位是前缀值，高 32 位的高字节是位宽（28 / 36）。 */
function writeLongKey(view: DataView, at: number, width: number, value: number): void {
  view.setInt32(at, value % 4294967296, true);
  view.setInt32(at + 4, (width << 24) | Math.floor(value / 4294967296), true);
}

export default function fieldwatchRadioDbTest() {
  describe('FieldwatchRadioDb', () => {
    it('多条目索引：key 与 idx 必须分段存放（回归）', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      expect(db.load(buildTwo(0x001122, 'Alpha Corp', 0x334455, 'Beta Ltd'))).assertTrue();
      expect(db.vendorForOui24('00:11:22')).assertEqual('Alpha Corp');
      expect(db.vendorForOui24('33:44:55')).assertEqual('Beta Ltd');
      expect(db.vendorForOui24('99:99:99')).assertEqual('');
    });

    it('单条目也能查中（基础路径）', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      expect(db.load(buildTwo(0xAABBCC, 'ACME Networks', 0xDDEEFF, 'Other Inc'))).assertTrue();
      expect(db.vendorForOui24('AA:BB:CC')).assertEqual('ACME Networks');
      expect(db.vendorForOui24('aabbcc')).assertEqual('ACME Networks');
    });

    // `long` 段（MA-M 28 位 / MA-S 36 位）此前**从未被读取**：
    // 它一直在 bin 里（13713 条），而 `mal` 只覆盖 24 位 MA-L，
    // 于是 MA-M / MA-S 地址的设备解析不出厂商名。
    // IEEE 把 MA-M / MA-S 子块从 MA-L 块里划出，**子块所有者常与父块不同**，
    // 所以顺序必须是 MA-S -> MA-M -> MA-L，越具体越优先。
    it('MA-S / MA-M / MA-L 三级优先：越具体越优先', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      // 父块 OUI 0xAABBCC；其下 MA-M 子块 0xAABBCCD；再下 MA-S 子块 0xAABBCCDD0
      const raw: Uint8Array = buildWithLong(0xAABBCC, 'Parent OUI Corp',
        0xAABBCCD, 'Sub Block M', 0xAABBCCDD0, 'Sub Block S');
      expect(db.load(raw)).assertTrue();
      // 同时命中三级 -> 取最具体的 MA-S
      expect(db.vendorForOui24('AA:BB:CC:DD:00:01')).assertEqual('Sub Block S');
      // 只命中 MA-M 与 MA-L -> 取 MA-M
      expect(db.vendorForOui24('AA:BB:CC:D0:00:01')).assertEqual('Sub Block M');
      // 三级都不命中 MA-M/MA-S -> 回退到 MA-L
      expect(db.vendorForOui24('AA:BB:CC:00:00:01')).assertEqual('Parent OUI Corp');
      // 只给 6 位 OUI 时行为与从前一致（纯 MA-L）
      expect(db.vendorForOui24('AA:BB:CC')).assertEqual('Parent OUI Corp');
      expect(db.vendorForOui24('aabbcc')).assertEqual('Parent OUI Corp');
      // 完全查不到
      expect(db.vendorForOui24('11:22:33:44:55:66')).assertEqual('');
    });

    // 36 位键超出 32 位，读取端要按两个半字拼；这条用例专门覆盖**值 > 2^32** 的情形，
    // 否则「低 32 位就够用」的错觉会掩盖拼接错误。
    it('MA-S 键值超过 2^32 时仍能拼对', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      const bigKey: number = 0x70B3D5000; // > 2^32，必须走高低半字拼接
      expect(bigKey > 4294967296).assertTrue();
      const raw: Uint8Array = buildWithLong(0x70B3D5, 'IEEE Registration Authority',
        0x70B3D50, 'MA-M Holder', bigKey, 'MA-S Holder');
      expect(db.load(raw)).assertTrue();
      expect(db.vendorForOui24('70:B3:D5:00:00:01')).assertEqual('MA-S Holder');
    });

    it('magic 不匹配时拒绝载入', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      const bad: Uint8Array = buildTwo(0xAABBCC, 'A', 0xDDEEFF, 'B');
      bad[0] = 0x58;
      expect(db.load(bad)).assertFalse();
      expect(db.isReady()).assertFalse();
    });

    // 端到端：OUI 查询必须同时匹配 MAC 与**厂商名**。
    // 这条链路此前虽然写好了，但 facts.manufacturer 从未被填充，
    // 因此依赖它的地方（含候选引擎的厂商排除）都是静默失效的。
    it('OUI 筛选同时匹配 MAC 与厂商名', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      expect(db.load(buildTwo(0x001B63, 'Apple, Inc.', 0xAABBCC, 'ACME Networks'))).assertTrue();
      FieldwatchFilterEngine.setRadioDb(db);
      const engine: FieldwatchFilterEngine = new FieldwatchFilterEngine();
      const facts: RadioFacts = new RadioFacts();
      facts.manufacturer = db.vendorForOui24('00:1B:63');
      expect(facts.manufacturer).assertEqual('Apple, Inc.');
      const observation: ScanObservation = new ScanObservation('ble:00:1B:63:11:22:33', RadioKind.BLE, '00:1B:63:11:22:33', 'Some Device', -60, 1000, facts);
      const item: Sighting = Sighting.fromObservation(observation);
      const byVendor: FilterDefinition = new FilterDefinition();
      byVendor.ouiQuery = 'apple';
      expect(engine.pass(item, byVendor, [], [], [], 2000)).assertTrue();
      const byMac: FilterDefinition = new FilterDefinition();
      byMac.ouiQuery = '00:1b:63';
      expect(engine.pass(item, byMac, [], [], [], 2000)).assertTrue();
      const noMatch: FilterDefinition = new FilterDefinition();
      noMatch.ouiQuery = 'nonexistent-vendor';
      expect(engine.pass(item, noMatch, [], [], [], 2000)).assertFalse();
    });

    it('未载入时所有查询都安全返回空串', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      expect(db.isReady()).assertFalse();
      expect(db.vendorForOui24('AA:BB:CC')).assertEqual('');
      expect(db.company(0x004C)).assertEqual('');
    });

    // ── 随机 / 虚拟 MAC 的厂商还原（对齐原版 MacUtil + RadioDb.vendorForMac）──
    // 这是「我们识别不出品牌、原版能」的主因：
    // 访客 / Mesh / 附加 SSID 的 BSSID 常是「厂商前缀 + 本地管理位置 1」，
    // 直接拿原地址查 OUI 必然落空。

    it('本地管理地址判定：置 LA 位且非多播才算随机', 0, () => {
      // 图1 里带 rand 标记的那个 MAC
      expect(isLocallyAdministered('8E:1E:CF:AE:BC:ED')).assertTrue();
      expect(isLocallyAdministered('8E1ECFAEBCED')).assertTrue();
      // 多播位也置 -> 不是设备地址，不算随机
      expect(isLocallyAdministered('8F:1E:CF:AE:BC:ED')).assertFalse();
      // 常规（全局唯一）地址
      expect(isLocallyAdministered('68:81:E0:D0:57:EC')).assertFalse();
      expect(isLocallyAdministered('E0:00:84:F9:FB:80')).assertFalse();
      expect(isLocallyAdministered('')).assertFalse();
      // 只给前两字节也要能判：0x8E 的 LA 位已置
      expect(isLocallyAdministered('8E')).assertTrue();
    });

    it('清掉本地管理位能还原厂商前缀', 0, () => {
      // 0x8E & 0xFD = 0x8C —— 清掉 0x02 位，其余原样保留
      expect(clearLocallyAdministered('8E:1E:CF:AE:BC:ED')).assertEqual('8C1ECFAEBCED');
      // 不是本地管理地址时原样返回（调用方无需分支）
      expect(clearLocallyAdministered('68:81:E0:D0:57:EC')).assertEqual('6881E0D057EC');
      // 多播地址也原样返回
      expect(clearLocallyAdministered('8F:1E:CF:AE:BC:ED')).assertEqual('8F1ECFAEBCED');
    });

    it('手机大厂 OUI 不当作品牌显示', 0, () => {
      expect(isPhoneHouseVendor('Apple, Inc.')).assertTrue();
      expect(isPhoneHouseVendor('Google LLC')).assertTrue();
      expect(isPhoneHouseVendor('Samsung Electronics Co.,Ltd')).assertTrue();
      expect(isPhoneHouseVendor('Microsoft Corporation')).assertTrue();
      // 有辨识度的厂商照常显示
      expect(isPhoneHouseVendor('HUAWEI TECHNOLOGIES CO.,LTD')).assertFalse();
      expect(isPhoneHouseVendor('UNIONMAN TECHNOLOGY CO.,LTD')).assertFalse();
      expect(isPhoneHouseVendor('')).assertFalse();
    });

    it('vendorForMac 对随机 MAC 还原后查得到厂商', 0, () => {
      // 合成库：8C:1E:CF 是厂商前缀，8E:1E:CF 是它在访客 SSID 上的虚拟 BSSID
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      // 注意：buildTwo 的两个 OUI 必须**升序**，否则二分查找失效（这是踩过的坑）
      expect(db.load(buildTwo(0x6881E0, 'HUAWEI TECHNOLOGIES CO.,LTD', 0x8C1ECF, 'UNIONMAN TECHNOLOGY CO.,LTD'))).assertTrue();
      // 随机地址：直接查落空，还原后命中
      expect(db.vendorForOui24('8E:1E:CF:AE:BC:ED')).assertEqual('');
      expect(db.vendorForMac('8E:1E:CF:AE:BC:ED')).assertEqual('UNIONMAN TECHNOLOGY CO.,LTD');
      // 常规地址照常
      expect(db.vendorForMac('68:81:E0:D0:57:EC')).assertEqual('HUAWEI TECHNOLOGIES CO.,LTD');
    });

    it('vendorForMac 过滤手机大厂（仅作用于还原路径）', 0, () => {
      const db: FieldwatchRadioDb = new FieldwatchRadioDb();
      // 用 0xA8（LA 位 = 0）而不是 0xAA —— 0xAA 的 LA 位已置，会走还原路径。
      // 0xAA 正是 0xA8 在虚拟 SSID 上的变体（置上 LA 位）。
      expect(db.load(buildTwo(0xA8BBCC, 'Apple, Inc.', 0xDDEEFF, 'Other Inc'))).assertTrue();
      // 真实地址上的 Apple 照常显示（原版行为）
      expect(db.vendorForMac('A8:BB:CC:11:22:33')).assertEqual('Apple, Inc.');
      // 还原路径上的 Apple 被过滤为空
      expect(db.vendorForMac('AA:BB:CC:11:22:33')).assertEqual('');
    });
  });
}
