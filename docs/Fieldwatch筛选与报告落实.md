# Fieldwatch 筛选与报告落实文档

> 规格来源（唯一权威）：`G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\`
> - `domain/FilterEngine.kt`（筛选判定与内置预设）
> - `domain/Models.kt`（`FilterState` 字段定义）
> - `ui/screen/FiltersScreen.kt` / `ui/screen/ReportsScreen.kt`（界面结构）
> - `ui/component/*`（SectionCard / FieldwatchFilterChip / FieldwatchSwitch / FieldwatchSlider / FieldwatchDropdownField / FieldwatchOutlinedField / FieldwatchActionButton）
> - `domain/SitExport.kt` / `domain/DebriefReport.kt` / `domain/SitDiff.kt` / `domain/SignatureCandidates.kt` / `data/LogStore.kt` / `data/DebriefPdf.kt`
>
> 判定标准：**功能真的生效**，不是"界面上有这个控件"。每一项都要有 ① 代码路径 ② LocalUnit 断言 ③ 真机可观察结果。

---

## 一、筛选页（FiltersScreen）

### 1.1 筛选引擎字段对照

| # | 原版 FilterState 字段 | 语义（原版 FilterEngine.kt） | 我们现状 | 待办 |
|---|---|---|---|---|
| F1 | `logic` | `AND`：全部条件与；`OR`：**只对可选条件**（includeSignatures / 仅显示类别 / nameQuery / ouiQuery / rssiMin>-100）取任一，其余硬条件仍与 | 有 `logic` 但 OR 语义不对 | 按原版重写 OR 分支 |
| F2 | `showWifi` / `showBle` | **包含式双开关**，两个都开=都看 | 只有 `radioKind` 单选 | 改成两个布尔 |
| F3 | `namedOnly` | 设备**有命中签名**（`fleetIds.isNotEmpty()`） | 有，但语义是"有名字" | 改为"有命中签名" |
| F4 | `customNamesOnly` | 设备 key 在**用户自定义命名**集合里 | 缺 | 新增 + 接 RadioBookmarks |
| F5 | `watchedOnly` | key 在告警设备集合，或任一 fleetId 在关注签名集合 | 有 | 核对两个来源都要算 |
| F6 | `excludeSignatures` + `fleetIds` | 命中任一被排除签名 → 不通过 | 缺 | 新增集合 |
| F7 | `includeSignatures` + `includeFleetIds` | 非空时要求命中其中之一 | 缺 | 新增集合 |
| F8 | `useClassFilter` + `excludeClasses` + `classes` | 三态：不用 / 仅显示这些类 / 隐藏这些类 | 只有单个 `signatureClass` | 改为集合 + 三态 |
| F9 | `rssiMin` | `device.rssi >= rssiMin` | 有 `minimumRssi` | 统一命名与默认值 |
| F10 | `nameQuery` | 模糊匹配 **name 或 mac** | 缺 | 新增 |
| F11 | `ouiQuery` | 模糊匹配 **mac 或 vendor** | 缺 | 新增 |
| F12 | `hideFastPairAccountKey` | `FastPair.isAccountKeyOnly(device)` → 不通过 | 缺 | 需要 FastPair 判定（见 F12 子任务） |
| F13 | `movingWithYou` | `CoTravel.withYou(device, travel, now)`：与手机一起移动的设备 | 缺 | 需要 GPS 轨迹 + 同游判定 |

### 1.2 内置预设（FilterEngine.defaultPresets）

| 预设 | 原版取值 | 待办 |
|---|---|---|
| All traffic | `FilterState()` 全默认 | 实现 |
| Wi-Fi only | `showBle=false` | 实现 |
| BLE only | `showWifi=false` | 实现 |
| Strong signal | `rssiMin=-70` | 实现 |
| Moving with you | `movingWithYou=true, showWifi=false` | 依赖 F13 |
| Watched only | `watchedOnly=true` | 实现 |

**预设交互（原版）**：点按=替换整个筛选；长按=删除；「将当前保存为...」+ 保存 添加自定义；删除的内置芯片可由「设置 → 恢复默认特征库与预设」找回。

### 1.3 界面分区（对照截图）

| 分区 | 内容 | 待办 |
|---|---|---|
| 预设 | 芯片网格 + 保存输入行 | 重做 |
| 信号类型 | 两者 / 仅 Wi-Fi / 仅 BLE 三选（映射 F2 两个布尔） | 重做 |
| 与你同行 | 开关 + GPS 轨迹状态说明（"目前 GPS 轨迹 0 米。继续移动（约 50 米）…"） | 依赖 F13 |
| 新发现 | 开关 + 说明 | 我们有 `freshOnly`，需核对语义 |
| 常驻设备 | 仅特征（隐藏未匹配）/ 仅关注的 / 仅已命名信号源 / 隐藏 Fast Pair 账号密钥 | 前三个部分有，第四个缺 |
| 特征分类 | 「仅显示 / 隐藏这些」+ 20 类图标芯片网格 | 重做 |
| 已选特征 | 仅显示选中的特征 / 隐藏选中的特征 | 缺 |
| 精细筛选 | 最低 RSSI 滑块 + 名称/MAC 包含 + OUI/厂商包含 + 且/或 + 重置筛选 | 大部分缺 |

---

## 二、报告页（ReportsScreen）

| # | 分区 | 原版功能 | 我们现状 | 待办 |
|---|---|---|---|---|
| R1 | 观测记录 | 「开始观测」/「结束观测」按钮 + 状态文案（未开始 / 进行中 / 已保存 N 个） | 有 Sit 概念但无开始/结束入口 | 实现会话式观测 |
| R2 | 轨迹 | 本机轨迹绘制（起点黑、当前位置蓝、分类图标、粗绿=停留） | 缺 | 实现轨迹画布 |
| R3 | 观测报告 | 复盘（文本）/ 复盘（PDF）+ 「显示未匹配的轮换 BLE」开关 + AI 导出 | 只有文本复盘 | 补 PDF 与开关与 AI 导出 |
| R4 | 观测导出 | 格式下拉（CSV/JSON 行/GPX/KML/WiGLE）+ 信号源单选（两者/仅 Wi-Fi/仅 BLE）+ 分享 + 保存到 SD 卡 | 有 CSV/JSONL，无 GPX/KML/WiGLE，无分享/另存 | 补格式与文件通道 |
| R5 | 对比观测 | 对比（文本）/ 对比（PDF）+ AI 导出 + 说明 | 有 Compare 文本 | 补 PDF 与 AI 导出 |
| R6 | 目录 | 「候选特征」入口 + 说明 | 有候选概念？需核对 | 核对并接入口 |
| R7 | 记录导出 | 「本次会话 N 行 · 磁盘占用 N KB」+ 格式下拉 + 信号源 + 分享 + 保存到 SD 卡 + 「重置/清空记录」 | 有日志与清空 | 补占用统计/分享/另存 |

---

## 三、推进顺序

1. **筛选模型与引擎**（F1–F11 是纯逻辑，先做，配 LocalUnit）
2. **筛选页 UI 重做**（按分区，用 SectionCard + 芯片 + 开关 + 滑块）
3. **F12 FastPair / F13 CoTravel**（依赖域能力，单独一轮）
4. **报告页 R1–R3**（观测会话 + 复盘）
5. **报告页 R4–R7**（导出通道 + 对比 + 记录）
6. **文档与验收同步**

---

## 四、逐项状态

> 状态取值：`未开始` / `进行中` / `已实现待验证` / `已验证`

| 项 | 状态 | 证据 |
|---|---|---|
| F1 OR 语义 | 已验证（LocalUnit） | |
| F2 showWifi/showBle | 已验证（LocalUnit） | |
| F3 namedOnly 语义 | 已验证（LocalUnit） | |
| F4 customNamesOnly | 已验证（LocalUnit） | |
| F5 watchedOnly 双来源 | 已验证（LocalUnit） | |
| F6/F7 签名包含排除集合 | 已验证（LocalUnit） | |
| F8 类别三态集合 | 已验证（LocalUnit） | |
| F9 rssiMin | 已验证（LocalUnit） | |
| F10 nameQuery | 已验证（LocalUnit） | |
| F11 ouiQuery | 已验证：MAC 匹配（LocalUnit）+ **厂商名匹配已移植**（原版 assets/lookups/radiodb.bin 1.3MB 二进制库，SPLK 格式六段索引；真机载入 MA-L 39995 条 / 名称 34781 个）；**真机自检通过：00:1B:63 -> Apple, Inc. / 公司 0x004C -> Apple, Inc.**（名称库载入后自动自检，索引与名称池均正确）；「输入厂商名过滤」的 UI 端到端取证仍待补（真机 inputText 通道不稳） | |
| F12 FastPair 账号密钥 | 已完成：按原版 FastPair.kt 修正语义（非配对模式 + 命中 fleet-fast-pair + 仅此一个特征），7 条 LocalUnit 覆盖配对模式/账号密钥/多特征/无特征/短写 UUID/非 FE2C/关开关；真机开关状态已确认可切换并持久化；「Live 行数前后差异」取证未取到（Tab 导航坐标不稳） | |
| F13 movingWithYou | 引擎已验证（LocalUnit）；定位源已接通（ingestWithLocation → recordTravelSample → 引擎），但需真机走动 ≥50m 才能端到端验证 | |
| P1 六个内置预设 | 已验证（LocalUnit） | |
| P2 预设点按/长按/另存/恢复 | 已验证（点按替换整个筛选、长按删除带确认弹窗、另存输入行；「恢复默认」在设置页） | |
| U1 预设分区 | 已验证（真机截图 + 写入通道持久化） | |
| U2 信号类型分区 | 已验证（真机截图 + 写入通道持久化） | |
| U3 与你同行分区 | 已验证（真机截图 + 写入通道持久化） | |
| U4 新发现分区 | 已验证（真机截图 + 写入通道持久化） | |
| U5 常驻设备分区 | 已验证（真机截图 + 写入通道持久化） | |
| U6 特征分类分区 | 已验证（真机截图 + 写入通道持久化） | |
| U7 已选特征分区 | 已验证（真机截图 + 写入通道持久化） | |
| U8 精细筛选分区 | 已验证（真机截图 + 写入通道持久化） | |
| R1 观测会话 | 已验证（真机：开始/结束观测 + 已保存观测列表 + 重命名/删除/删除全部） | |
| R2 轨迹画布 | 已验证（真机渲染 + 空状态；有轨迹时的折线/起点/当前点/信号源点待走动验证） | |
| R3 复盘 + PDF + AI 导出 | 部分：文本复盘 + AI 导出 + **PDF 复盘已真机生成成功（19461 字节、含 /Font、1 页）**（按原版 DebriefPrompt.kt：11 条约束 + 5 段输出要求 + 采集上下文 + 15/5 分钟计数 + 双 RSSI 分带 + 轨迹 + 额外关注 + 防丢器行，90000 字符上限）；**PDF 对比也已真机生成（3846 字节）** | |
| R4 观测导出通道 | 部分：**格式（5 种）+ 信号源（两者/仅 Wi-Fi/仅 BLE）+ 分享 + 保存到文件 已按原版 GeoExport.kt 的 LogExportKind / LogExportRadios 结构重做并真机验证**（真机控件树 + 保存选择器截图，文件名 fieldwatch-log-<时间戳>.csv 正确预填）；**选择器保存已确认可正常拉起**（真机截图：选择路径对话框、文件名预填、仅可访问所选文件），但自动化点确认返回 0 URI（疑为 uitest 注入 UIExtension 窗口的局限，待人工确认）；DOWNLOAD 免交互通道已接入但写入失败（返回目录 URI，其中创建文件报 No such file or directory） | |
| R5 对比观测 | 部分：文本对比 + **AI 导出已实现**（按原版 SitDiffPrompt.kt 的约束与要点格式）；**PDF 对比也已真机生成（3846 字节）** | |
| R6 候选特征 | 已完成：按原版 SignatureCandidates.kt 移植聚类引擎（指纹提取/分桶/重叠合并60%/家用与随机过滤/常量表），新增 FieldwatchCandidateEngine.ets + 9 条 LocalUnit；真机显示 64 台信号源·未匹配 53·跳过随机 9，识别出 WHQ(33台)/UUID FDAA 等候选族，每族可「添加到目录」写入用户目录 | |
| R7 记录导出 | 部分：会话行数 + **磁盘占用 KB 已接且修正为递归统计**（真机 5053 行 · 1416 KB）+ 清空日志确认；分享/另存未做 | |
