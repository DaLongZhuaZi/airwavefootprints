# 性能分析报告：nova 12 Ultra / airwavefootprints（Energy 录制 2026-10-17 20:23）

> 数据来源：`Energy_ADA-AL00U_com.dlzz.airwavefootprints_Main Process_20261017T202333.insight`
> 设备：HUAWEI nova 12 Ultra（ADA-AL00U），HarmonyOS 7.0.0.109，API 26，120Hz 屏
> 录制模板：Energy（ftrace + hiperf + CPU/能耗/温度采样），标称 60s
> 解析方式：解包后 `htrace` 用 HiSmartPerf 自带 `trace_streamer`（wasm）转为 SQLite；`perf.data` 直接按 PERFILE2 格式解析并做 JS 符号归因
> **有效数据窗口：44.1s**（ftrace/sched/perf 均止于 +44.08s，最后约 12s 只有能耗采样，无调度数据）

---

## 一、结论速览

| 指标 | 实测 | 判定 |
|---|---|---|
| App 总 CPU | 65.1s / 44.1s = **1.48 核** | 严重超标（纯监听+雷达页不该超过 0.2 核） |
| 主线程（UI 线程）Running | 38.1s / 44.1s = **86.5%** | **主线程几乎 100% 打满**，这是卡顿/冻屏/发烫的直接来源 |
| GC 线程（4 条）CPU | 17.4s = **39.5% 单核** | 分配风暴：每秒生成数百 MB 级短命对象 |
| render_service CPU | 37.1s = **0.84 核** | 排在其后，被 App 帧率驱动 |
| App 窗口出帧数 | 737 帧 / 44.1s = **16.7 fps** | 目标 60（期望帧间隔 8.3ms，即 120Hz）；分桶后在 4.2–30.6 fps 间抖动 |
| 单帧最长耗时 | 87.6 ms（主线程），帧间隔最长 670 ms | 一次卡顿 ≈ 8 帧丢失，用户可见「冻住不动」 |
| Shell 温度 | 42.0℃ → 42.9℃（录制 44s 内持续爬升，thermal_level=3） | 录之前已经处在 3 级温控，还会继续升 |
| 电池电流 | -1.4 ~ -1.7 A（亮屏） | 典型「亮屏重度游戏」级别，非工具类 App 应有水平 |

**一句话**：UI 线程被「十六进制字符串归一化」这个纯字符串处理函数吃掉了 45% 的 JS CPU，并被每一条扫描回调（约 122 次/秒）反复触发；它同时制造了 39.5% 单核的 GC 开销。热量、卡顿、冻屏都是这条链路的后果。

---

## 二、perf 归因：CPU 到底花在哪

hiperf 以 2000Hz 采样（`isRecordJsStack: true`），共 189,837 个 App 采样，其中 92,208 个（48.6%）成功归因到 JS 函数（其余为 ArkVM/GC/native）。**这些 JS 采样中约 95% 落在主线程 tid=63157 上**——即所有重活都在 UI 线程跑。

### 2.1 按函数聚合（合并同一函数的多个内联点）

| 采样 | 占已归因 | 函数 | 位置 |
|---:|---:|---|---|
| **42,075** | **45.6%** | `signatureHexOnly` | [FieldwatchSignatureModels.ets:53](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels.ets#L53-L64) |
| 10,149 | 11.0% | `anonymous`（List 行构建 lambda） | `FieldwatchPage.ets` builder 内联 |
| 6,064 | 6.6% | `fleetHits` | [FieldwatchSignatureEngine.ets:690](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L685-L720) |
| 4,039 | 4.4% | `serviceDataHits` | [FieldwatchSignatureEngine.ets:159](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L159-L193) |
| 4,019 | 4.4% | `signatureUuidAliases` | [FieldwatchSignatureModels.ets:83](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels.ets#L83-L95) |
| 3,472 | 3.8% | `__getResourceId__` | ArkUI `jsUIContext_ohos.js`（`$r()` 解析，build 频次指标） |
| 2,846 | 3.1% | `hits` | [FieldwatchSignatureEngine.ets:275](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L275) |
| 2,557 | 2.8% | `categoryFor` | [FieldwatchPage.ets:2419](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L2419-L2424) |
| 1,568 | 1.7% | `executeSql` | [RdbManagerFacade.ets:46](ngf_framework/src/main/ets/data/rdb/facades/RdbManagerFacade.ets#L46) |
| 1,546 | 1.7% | `radioOk` | SignatureEngine |
| 1,468 | 1.6% | `matchOne` | SignatureEngine |
| 1,316 | 1.4% | `drawRadar` | [FieldwatchPage.ets:4120](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L4120) |
| 708 | 0.8% | `uuidHits` / 691 `relaxNodes` / 611 `ouiHits` / 417 `append` | 见下 |

### 2.2 按文件聚合

| 采样 | 占比 | 文件 |
|---:|---:|---|
| 46,417 | 50.3% | `domain/signatures/FieldwatchSignatureModels.ets` |
| 18,020 | 19.5% | `domain/signatures/FieldwatchSignatureEngine.ets` |
| 12,049 | 13.1% | `pages/fieldwatch/FieldwatchPage.ets` |
| 3,482 | 3.8% | ArkUI `jsUIContext_ohos.js`（`$r()`） |
| 2,750 | 3.0% | `application/FieldwatchApplication.ets` |
| 2,421 | 2.6% | ArkUI `stateMgmt.js`（状态派发） |
| 1,588 | 1.7% | `ngf_framework/.../RdbManagerFacade.ets` |

**特征库相关代码合计 ≈ 70% 的已归因 JS CPU**，UI 构建 ≈ 17%，DB 写入 ≈ 2%。

---

## 三、根因分析（按影响排序）

### P0-1 `signatureHexOnly()`：逐字符字符串拼接，且被放在最热的循环里

```ts
// FieldwatchSignatureModels.ets:53
export function signatureHexOnly(raw: string): string {
  if (raw.length === 0) return raw;
  let result: string = '';
  for (let index = 0; index < raw.length; index += 1) {
    const code: number = raw.charCodeAt(index);
    const isDigit: boolean = code >= 48 && code <= 57;
    const isUpper: boolean = code >= 65 && code <= 70;
    const isLower: boolean = code >= 97 && code <= 102;
    if (isDigit || isUpper || isLower) result += raw.charAt(index).toUpperCase();  // ← 每个字符一次分配
  }
  return result;
}
```

三重问题叠加：

1. **算法层面**：`result += c` 在 ArkTS/V8 语义下是「新建字符串 + 拷贝」，n 个字符 → n 次分配、O(n²) 拷贝；外加每字符 `charAt()`（1 个字符串）与 `toUpperCase()`（再 1 个字符串）。归一化一条 32 字符的 MAC/UUID ≈ **~100 次对象分配**。
2. **调用频次层面**：它没有被缓存，而是在「每条规则 × 每条观测 × 每次匹配」里实时计算。典型放大路径：
   - `matchesPrefix()`（[Engine:98-103](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L98-L103)）对 **规则常量** `prefix` 每次匹配都重新归一化一次；
   - `ouiHits()` / `vendorIeHitsOui()` / `serviceDataHits()` 同样对规则常量反复归一化；
   - `addressHex()`（[Engine:38](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L38)）是 getter，每次调用重算，而 `applyClusters()` 里对每一对 (候选, peer) 都要调用两次 → **O(N²) 次归一化**；
   - `signatureUuidAliases()`（[Models:83](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureModels.ets#L83-L95)）内部先调 `signatureHexOnly`，再建数组，一次调用 = 一次归一化 + 1~3 个字符串。
3. **最致命的一层：context 的归一化没有缓存，被「每条规则」重复做了一遍。**
   规则本身在 `compile()` 里已经预编译（`SignatureUuidRule`/`SignatureManufacturerDataRule` 构造函数只归一化一次），但**观测侧（context）的归一化发生在`hits()` 内部**：

   - [`SignatureManufacturerDataRule.hits`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L238-L244)：`payloadPrefixHits(signatureHexOnly(context.manufacturerDataHex), ...)` —— 每条 MANUFACTURER_DATA 规则都把同一份负载重算一次；
   - [`SignatureUuidRule.hits`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L214-L218) → `uuidHits(context, this.aliases[0])` → [`uuidHits`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L105-L117) 内部又对**已归一化的 `this.aliases[0]`** 再调一次 `signatureUuidAliases()`，并对 `context.serviceUuids[]`、`context.serviceData[].uuid` 逐个重算别名 —— 每条 UUID 规则 × 每个 UUID 一次归一化；
   - [`CompiledSignatureIndex.ouiHits`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L315-L352)：`context.addressHex()` 是**每次重算的 getter**，`signatureHexOnly(context.vendorIeOuis[i])` 在 longOui 循环里被重复调用 N 次；
   - [`serviceDataHits`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L159-L193)：`signatureUuidAliases(record.uuid)` + `signatureHexOnly(record.dataHex)` 在规则循环内重复。

   结论：一次观测本应做 **1 次** context 归一化，实际做了 **O(命中规则数 × 字段数)** 次；乘以 `ingestNow` 的每秒 100+ 次调用，就是你看到的 42,075 个采样。

4. **触发源层面**：`ingestNow()`（[Application:2361](entry/src/main/ets/fieldwatch/application/FieldwatchApplication.ets#L2361-L2379)）对**每一条扫描观测**都执行：

```ts
const context = signatureContextOfObservation(observation);
const matched = this.fleetEngine.matchContext(context, this.state.signatures);  // 全量特征匹配
const decoded = this.decodeFields(matched, context);
...
this.state.sightings.find(...)          // O(N) 线性查找
this.appendLogEntry(...)                 // 每条观测都进环形日志
void this.observationRepository.append(observation);   // 每条观测一次 DB 写
```

而 Wi-Fi 扫描回调在 trace 里是 **5,404 次 / 44s ≈ 122 次/秒**（`H:OnScanCallback` 累计 25.5s）。Wi-Fi 一次扫描带回几十条 BSS，每条都要过一遍全量特征库 → 归一化调用量 = 规则数 × 观测数 × 每秒次数，量级到 10⁵–10⁶/秒。

### P0-2 GC 风暴：39.5% 单核的 `OS_GC_Thread`

4 条 GC 线程 17.4s / 44.1s。trace 里 App 侧 `H:VerifyPermission` 被调用 **86,610 次**、`H:Cancelable Event callback` 3,718 次、`H:Native async work execute` 5,934 次——这些是 ArkTS 侧的分配/回调风暴的外显。结合 P0-1 的「每字符一分配」，GC 开销是它的直接产物。GC 又会反向抢占主线程的 CPU 时间片（主线程 8,098 次调度切片，平均每 5.4ms 被切一次），加剧掉帧。

### P0-3 `categoryFor()` 与 List 行构建：在 build 里做 O(特征库) 查找

```ts
// FieldwatchPage.ets:2419
private categoryFor(sighting: Sighting): SignatureClass {
  const state = fieldwatchApplication.getState();
  const signatureId = sighting.signatureIds.length > 0 ? sighting.signatureIds[0] : '';
  const signature = state.signatures.find((item) => item.id === signatureId);   // 每次线性扫描
  return signature === undefined ? SignatureClass.OTHER : foldedSignatureClass(signature.category);
}
```

它在行构建里被调用（[2290](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L2290)、[2622](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L2622)、[2910](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L2910)、[2949](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L2949)），叠加 `classCount()` 的 filter 统计，构成 13.1% 的页面侧开销 + 3.8% 的 `$r()` 解析开销。行构建 lambda（`anonymous` 11%）本身就是「列表被高频重建」的证据。

### P1-1 每秒一次的重算链（雷达几何）

`refresh()`（[Page:1107-1168](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L1107-L1168)）每 1s 无条件重算：

```
sightings.slice() → filteredSightings().slice() → refreshLiveSource()
→ buildRadarPoints(全部观测) → rebuildRadarRank() → rebuildRadarGeometry()
     └─ buildRadarNodes() → mergeNearbySingles(O(N²)) → relaxNodes(28 遍)
```

`relaxNodes(nodes, 28, zoom)`（[RadarCluster:181](entry/src/main/ets/fieldwatch/ui/FieldwatchRadarCluster.ets#L181)）默认 28 轮迭代。这部分在 perf 里只占 `relaxNodes` 0.7%、`drawRadar` 1.4%，**不是当前第一瓶颈**，但它与 16ms 定时器一样属于「无条件每秒/每帧重算」，是设备热起来的持续底噪。

### P1-2 60fps 定时器 + 画布重绘

`startTimers()`（[Page:1059-1069](entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets#L1059-L1069)）用 `setInterval(16ms)` 驱动扫描线，`advanceSweep()` 每 tick 改 `@State radarAngle` 并 `drawRadar()`。在 120Hz 设备上 16ms 本身就是错配（应为 8.3ms 或被 vsync 驱动），且 JS 定时器抖动会直接变成画面抖动。代码里已有关注前台的 `isAppForeground()` 早退，这点保留。

### P1-3 每条观测一次 DB 写 + 每条观测一次权限校验

`executeSql` 1,568 采样（1.7%），对应 trace 中 `H:VerifyPermission` 86,610 次、`H:GetCallingName` 8,368 次——RDB 每次操作都要走一次权限校验与调用者解析。按观测逐条 append 会在高密度环境把这条路径放大到每秒上百次。

### P2 其它观测

- trace 中 `H:getframe` 296 次、累计 41.8s（均值 141ms）——若归属 App UI 线程，则意味着 **UI 线程有 95% 的时间卡在「等下一帧」的同步等待里**；该 slice 的线程归属在导出的 DB 中丢失，需在 DevEco 里人工确认后再作为结论使用。
- `H:DE:TriggerOnce` 2,124 次、累计 90.3s（20–35s 区间内 5s 桶出现 52.9s 累计，说明高度嵌套/并行），归属同样待确认。
- `H:JSPandaFileExecutor::Execute` 55 次 3.55s、`H:SourceTextModule::Evaluate` 88 次 3.26s → 模块加载/字节码执行占 ~6.8s，属冷启动路径，与本次稳态卡顿无关，但会影响首次进入页面的体感。

---

## 四、修复方案

### 第 1 步（收益最大，改动最小）：重写 `signatureHexOnly` 并加缓存

```ts
// 建议：单次扫描 + 查表 + 数组 join，禁止逐字符 +=
private static readonly HEX_UPPER: string[] = buildHexUpperTable(); // '0'..'9','A'..'F'，非法字符为 ''
export function signatureHexOnly(raw: string): string {
  if (raw.length === 0) return raw;
  const out: string[] = [];
  for (let i = 0; i < raw.length; i += 1) {
    const mapped: string = SignatureHexTable.HEX_UPPER[raw.charCodeAt(i)];
    if (mapped.length > 0) out.push(mapped);
  }
  return out.join('');
}
```

- 预期：该函数自身 CPU 下降 70% 以上（避开 `toUpperCase` 与逐字符 concat），GC 分配量同比例下降。
- 更进一步：`signatureHexOnly(rule.dataPrefixHex)`、`signatureHexOnly(prefix)` 这类**入参是规则常量**的调用，应当在 `CompiledSignatureIndex` 编译期算一次并存字段，匹配期直接读——当前是每次匹配重算，这是「同一份常量被归一化上百万次」。

### 第 2 步：把 context 归一化「一次算好」，匹配期只读字段

这是把 45.6% 降到个位数的关键；**规则侧已经预编译，缺的是观测侧**。

1. `SignatureMatchContext` 增加一次性缓存字段（在 `signatureContextOfObservation()` 里算好）：
   - `addressHex`（现在每次调用重算，[Engine:38](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L38)）；
   - `manufacturerDataHex` 的归一化结果；
   - `serviceUuids[]` / `serviceData[].uuid` 的 `aliases` 数组（现在是每个 UUID 规则重算一次）；
   - `serviceData[].dataHex`、`vendorIeOuis[]` 的归一化结果。
2. `uuidHits(context, text)` 改为 `uuidHits(context, wantAliases: string[])`，**直接接收已归一化的别名数组**，内部对 `context` 只读缓存字段；这样 `SignatureUuidRule` 只要在构造时把 `aliases` 传进去，匹配期就是纯数组比较。
3. `SignatureManufacturerDataRule.hits` / `serviceDataHits` / `ouiHits` 里的所有 `signatureHexOnly(context.*)` 改为读缓存字段。
4. `ingestNow()` 对同一设备的**重复观测做去抖**：同一 `observation.key` 在 1–2s 内的匹配结果可复用（观测值变了只更新 RSSI），不必每条回调都跑全量匹配。
5. 顺手修掉 [`containsIgnoreCase`](entry/src/main/ets/fieldwatch/domain/signatures/FieldwatchSignatureEngine.ets#L93-L96)：它每次调用都对两侧 `toLowerCase()`，在 `SignatureContainsRule` 里属于「规则常量针」反复小写化，应在编译期小写化 `needle`。

### 第 3 步：把匹配与列表构建移出 UI 线程 / 降低频次

1. `matchContext()` 与 `decodeFields()` 是纯 CPU、无 UI 依赖 → 用 `taskpool` 或 NGF 的 FFRT 任务池下发，结果回主线程只做状态赋值（注意 `SignatureFleet[]` 需可序列化，或只在 worker 内返回 `{key, matchedIds, decoded}`）。
2. `categoryFor()` / `classCount()` / `brandOf()` 改为**预计算映射**：在 `state.signatures` 变更时构建 `Map<signatureId, SignatureClass>`，行构建里只做 `map.get(id)`。
3. 列表行 builder 内禁止调用任何会遍历 `state.signatures` 的方法（当前 `categoryFor`、`previewHint`、`signatureText`、`signatureReasonText` 都在 build 里）。

### 第 4 步：雷达几何与重绘

1. `refresh()` 的几何重建改为**脏检查**：只有当「可见点集签名」或 `zoom`/`mode` 变化时才重算 `buildRadarPoints/rebuildRadarGeometry`；数据没变就跳过。
2. `relaxNodes(nodes, 28)` 降到 8–12 轮首帧 + 后续增量收敛（或改为每帧只处理上帧未收敛的节点）。
3. 16ms 定时器改为 `displaySync`/vsync 回调驱动，帧间隔跟随屏幕刷新率；或在无数据变化时暂停扫描线动画。

### 第 5 步：I/O 合并

1. `observationRepository.append()` 改为**批量写入**（例如 500ms 或 20 条合并一次），减少 RDB 事务与权限校验次数（对应 `H:VerifyPermission` 8.6 万次）。
2. `appendLogEntry()` 只在 UI 需要时生成，或在内存里按 key 覆盖而不是每条新增（当前每条观测一个 `LogEntry` 对象）。

---

## 五、验收方式（复测时按此比对）

1. 同一台机、同一模板再录一次 60s，重点看：
   - 主线程 `Running / 窗口` 从 **86.5%** 降到 **< 30%**；
   - App 总 CPU 从 **1.48 核** 降到 **< 0.5 核**；
   - GC 线程 CPU 从 **39.5%** 降到 **< 8%**；
   - App 窗口出帧 **≥ 55 fps**（帧间隔 P90 < 16.7ms）；
   - 44s 内 shell 温升 < 0.5℃。
2. 用 `hdc shell hiprofiler_cmd` 或 HiProfiler 的「ArkTS/HiPerf」单元复查 `signatureHexOnly` 是否已跌出 Top10。
3. 静态检查：`grep -n "signatureHexOnly(" ` 应只出现在初始化/编译期路径与少量入口，不出现在匹配循环内。

---

## 六、本次分析的边界

- 有效 ftrace/sched/perf 数据只覆盖前 **44.08s**；最后约 12s 仅有能耗采样（无调度、无帧），因此「末段是否冻屏」无法从该记录判定。
- `H:getframe`、`H:DE:TriggerOnce` 的线程归属在 `trace_streamer` 导出的 DB 中未保留（`callstack` 表无 itid），已在报告中标注为「待确认」，不作为定论。
- JS 归因覆盖率 48.6%（未归因为 ArkVM/GC/native 帧），因此百分比是「相对已归因量」的口径；但 `signatureHexOnly` 单函数独占 45.6%，即使考虑未归因部分，其绝对量级也不容置疑。
- 未执行构建/运行验证（按仓库规则，本次为静态分析与日志分析任务）。
