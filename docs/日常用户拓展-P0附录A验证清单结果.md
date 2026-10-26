# P0 附录 A.5 验证清单（V1–V6）核实结果

> 记录时间：2026-10-27。核实方式：**本机 API 26 SDK 类型定义静态核对** + 现有仓库实现比对。
> **凡标「待真机」的条目一律未验证** —— 没有连接任何设备（`hdc list targets` 为空），不编造结果。
> 本文件是 P0 交付的一部分：V1–V6 的结论决定「地址直配 vs 指纹兜底」谁是主路径。

## 结论速览

| # | 问题 | 静态结论 | 真机状态 |
|---|---|---|---|
| V1 | 扫描 deviceId 与 getPairedDevices 虚拟地址是否同值 | **无法静态判定** | 待真机 |
| V2 | addPersistentDeviceId 的持久性边界 | **本权限等级不可用** → 永久降级 | 无需真机（结论已确定）|
| V3 | getRemoteDeviceName 对纯 BLE 配对设备是否给名 | 接口存在（含 alias 重载），**能否给名取决于对端** | 待真机 |
| V4 | Profile 连接状态在 API 26 的确切接口与语义 | **语义与文档 A.1 描述不一致，已按实际实现** | 部分待真机 |
| V5 | 星闪 manager 是否有配对列表接口 | **有**（`manager.getPairedDevices(): string[]`）| 待真机（需星闪设备）|
| V6 | getConnectedInfo 在当前机型的字段完整性 | **该接口不存在**（只有 `getLinkedInfo`）| 待真机 |

---

## V1 扫描 deviceId 与配对虚拟地址是否同值 → **待真机**

**能静态确认的**：
- `ble.ScanResult.deviceId: string`，扫描侧 `FieldwatchBleScanner` 把它直接拼成 `'ble:' + deviceId` 作为 `Sighting.key`（见该文件 167 行）。
- `connection.getPairedDevices(): Array<string>` 给出的是**虚拟地址**（API 26：只有持有 `GET_BLUETOOTH_PEERS_MAC` 才是真 MAC，而本应用不申请该权限）。

**静态无法判定的**：这两个字符串在运行时究竟是不是同一份虚拟地址 —— 取决于系统是否对「扫描到的设备」和「配对名单里的设备」分配同一个虚拟地址。**这必须真机打印比对**。

**当前代码的应对（不赌 V1）**：`FieldwatchOwnDeviceMatcher` 的顺序是「persistentId → 地址 → 指纹」，
地址直配**不是唯一路径**：地址对不上时会自动落到指纹打分（阈值 5）。因此 V1 无论结论如何，功能都成立；
区别只在「多数设备走地址直配」还是「多数走指纹」。**这正是文档 A.5 要求的「不同值 → 指纹兜底升为主路径」的降级形态，已经内置。**

**真机步骤（需要用户配合）**：
1. 手机与一副蓝牙耳机配对并连接过。
2. 打开应用进「找东西」页，记录已配对列表里耳机的地址（显示名旁的长按/详情可见，或看 hilog 里 `FieldwatchPairedDevices` 的调用）。
3. 在同一页面看「最近听到」列表里同一条耳机的键。
4. 两者地址逐字比对（注意大小写、分隔符已由 `normalizeDeviceAddress` 归一化）。

---

## V2 addPersistentDeviceId 的持久性 → **结论已确定：不可用**

**SDK 事实**（`@ohos.bluetooth.access.d.ts:168`）：
```
@permission ohos.permission.ACCESS_BLUETOOTH and ohos.permission.PERSISTENT_BLUETOOTH_PEERS_MAC
function addPersistentDeviceId(deviceId: string): Promise<void>;
```
- `PERSISTENT_BLUETOOTH_PEERS_MAC` 在 `PermissionDefinitions.json` 里是 **`grantMode: system_grant` + `availableLevel: system_basic`**（第 4340 行）。
- 普通应用（normal APL）**拿不到**，只能走 ACL 加签 —— 那会把应用的权限面整体抬高。
- 另外注意它返回 `Promise<void>`，**不返回 ID**：文档 A.2 里「认领时对目标调一次拿 persistentId」的写法与真实签名不符。

**实现处置**：
- `PairedDeviceEntry.persistentId` **恒为空串**，并在注释里写明原因。
- `OwnDeviceProfile.persistentId` 字段保留（类型层面显式表达「拿不到」），但本项目里长期为空。
- 匹配管线的第 ① 步（persistentId）因此**实际上不会命中**，主路径是 ② 地址 → ③ 指纹。
  **这不是降级缺陷，而是按真实权限等级做的正确设计**：把不可用的锚删掉会让将来万一拿到权限时要重写管线。

**对文档的修正建议**：A.1「如需持久化标识，可用 access.addPersistentDeviceId」应改为「需 system_basic 权限，本项目不可用；持久性只能靠指纹快照」。

---

## V3 getRemoteDeviceName 对纯 BLE 配对设备是否给名 → **待真机**

**静态事实**：
- `connection.getRemoteDeviceName(deviceId: string): string`（API 10 起）。
- `connection.getRemoteDeviceName(deviceId: string, alias?: boolean): string`（API 16 起，可要别名）。

**静态无法判定的**：纯 BLE 配对设备（手环）是否响应名称读取。**必须真机**。

**当前代码的应对**：
- `fetchName` 失败时返回空串并 warn，**不缓存失败**（缓存只写成功结果，含「查到了但确实是空名」）。
- UI 侧 `FindCandidate.name` 为空时显示资源键 `fieldwatch_find_unnamed`（「未命名的设备」），
  **不会退化成显示地址**（地址在日常页属于禁用的术语）。
- 若 V3 结论是「不给名」，认领向导需要**再加一步「在广播列表里对一次名」** —— 这一步尚未实现，
  属于 **P0 遗留待补**（等 V3 真机结论决定要不要做）。

**真机步骤**：拿一台纯 BLE 配对的手环，配对后打开「找东西」，看它是否显示名字。

---

## V4 Profile 连接状态在 API 26 的接口与语义 → **语义与文档不一致，已按实际实现**

**SDK 事实**（`@ohos.bluetooth.connection.d.ts:106`）：
```
function getProfileConnectionState(profileId?: ProfileId): ProfileConnectionState;
```
- **没有 `deviceId` 参数。** 它只回答「某个 Profile 此刻有没有连着设备」，**无法归属到具体某一台**。
- 逐设备的真实接口在 `baseProfile.BaseProfile` 上（`getConnectionState(deviceId)` / `getConnectedDevices()`），
  但要用它必须 `createA2dpSrcProfile()` 之类**自建 Profile 对象** —— 属于连接侧动作，与「绝不发起连接」相悖，**未采用**。
- `constant.ProfileId` 全系统只有 4 个值：`A2DP_SOURCE=1` / `HANDSFREE_AUDIO_GATEWAY=4` / `HID_HOST=6` / `PAN_NETWORK=7`。
- `constant.ProfileConnectionState`：`DISCONNECTED=0` / `CONNECTING=1` / `CONNECTED=2` / `DISCONNECTING=3`。

**实现处置（保守近似）**：
- `inUse` 按**设备家族**归属（音频 0x04 / 外设 0x05 / 网络 0x03），
- 且**仅当该家族在配对名单里恰好只有一台**时才可能为 `true`；同族有两台（两副耳机）一律 `false`。
- 只认 `STATE_CONNECTED`，不认过渡态（否则列表会在连接瞬间闪一下）。

**文案口径**：UI 写「手机上已配对 · 正在使用中」，**不承诺精确归属**。

**对文档的修正建议**：A.1 该行应改为「只能得到家族级近似，无法精确到设备；精确判定需要自建 Profile（不符合只接收底线）」。
V4 的「通过标准」也应从「事件可靠 → 上『正在使用中』态」改成「家族级近似可靠 → 上『正在使用中』态；否则只显示在附近/上次见到两态」。

---

## V5 星闪 manager 是否有配对列表接口 → **有，静态已确认**

**SDK 事实**（`@ohos.nearlink.manager.d.ts:77`）：
```
@permission ohos.permission.ACCESS_NEARLINK
function getPairedDevices(): string[];
```
- 注释明确：「If the user has the ohos.permission.GET_NEARLINK_PEER_MAC permission, the real device address is returned. Otherwise, a random device address is returned.」
- 与 BLE 侧完全同构：不申请 Mac 权限就是随机/虚拟地址。

**实现处置（本期待定）**：
- P0 **不接入星闪配对名单**。理由：`ACCESS_NEARLINK` 已在册，但星闪设备在本机与用户设备组里尚未确认（无星闪硬件），
  接了也无从验证；而且它与 BLE 侧是两套完全独立的配对体系，混进同一个「我的设备」列表会需要额外的来源标记与去重规则。
- 文档 A.6 原本写「星闪不做导入（V5 有惊喜再说）」—— **V5 确实有惊喜**（接口存在），
  因此记为 **P0 遗留待补 + P1 候选**：接口已确认可用，缺的是真机与产品口径（要不要把星闪设备也列进「我的设备」）。
- 现状：星闪目标维持「现扫现认」——它们会出现在「最近听到」里，可以按扫描键认领，
  只是不走配对名单那条捷径。

**真机步骤**：需要一台支持星闪的设备（`manager.isNearLinkSupported()` 为真）才能验证返回值的实际形态。

---

## V6 getConnectedInfo 字段完整性 → **接口不存在，已改用正确接口**

**SDK 事实**：
- `@ohos.wifiManager.d.ts` 里**没有 `getConnectedInfo`**（全文件 0 命中）。文档 A.1 / A.5 用的这个名字在 API 26 不存在。
- 当前连接信息的正确接口是 `getLinkedInfo(): Promise<WifiLinkedInfo>`（第 533 行），另有 `getLinkedInfoSync()`（第 589 行）。
- `WifiLinkedInfo` 含 `ssid: string`（第 2439 行）、`bssid: string`（第 2453 行）、`rssi: number`（第 2467 行）、`band: number`（第 2474 行）。

**实现处置**：
- P0 的「找东西」**完全没用到这条捷径**：`FieldwatchPairedDevices` 只管蓝牙配对名单；
  路由器目标走「最近听到」列表（Wi-Fi 扫描结果里本来就有 SSID/BSSID），不需要额外查当前连接。
- 因此 **V6 对 P0 交付无阻塞**。文档 A.5 里「SSID/BSSID 齐全 → 上认领捷径卡」这一分支**本期待不做**，记为待补。

**真机步骤（若后续要做捷径卡才需要）**：连上家里 Wi-Fi，调 `wifiManager.getLinkedInfo()`，看 SSID 是否为空（部分机型在无定位权限时会置空）。

---

## 静态核实清单（可复现）

```bash
SDK='/g/DevEco Studio 26/DevEco Studio/sdk/default/openharmony'
# V2 权限等级
grep -n 'PERSISTENT_BLUETOOTH_PEERS_MAC' -A 4 "$SDK/toolchains/lib/PermissionDefinitions.json"
# V4 Profile 接口与枚举
grep -n 'getProfileConnectionState' "$SDK/ets/api/@ohos.bluetooth.connection.d.ts"
grep -n 'enum ProfileId' -A 32 "$SDK/ets/api/@ohos.bluetooth.constant.d.ts"
# V5 星闪配对列表
grep -n 'getPairedDevices' "$SDK/ets/api/@ohos.nearlink.manager.d.ts"
# V6 当前连接信息（getConnectedInfo 不存在）
grep -c 'getConnectedInfo' "$SDK/ets/api/@ohos.wifiManager.d.ts"   # => 0
grep -n 'function getLinkedInfo' "$SDK/ets/api/@ohos.wifiManager.d.ts"
```

## 真机验证总状态

**未进行任何真机验证**：`hdc list targets` 返回空（无设备连接），且用户未委托设备操作。
V1 / V3 / V4 的运行时部分 / V5 / V6 全部**待真机**；V2 结论由权限等级静态确定，无需真机。
