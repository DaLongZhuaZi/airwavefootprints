# Fieldwatch 鸿蒙迁移任务计划

**基线**：Fieldwatch Android 1.1.17；HarmonyOS API 26；NGF 本地 HAR。  
**首个交付**：BLE + Wi-Fi 被动 Live、过滤、设备详情、关注列表、本地日志、基础位置标记、设置和隐私模式。  
**数据边界**：严格离线；网络只允许用户主动更新 catalog。  
**最终证据**：API26 真机优先，模拟器只作补充。

**Agent 交接**：当前目标、已验证证据、设计资料、调试方法和下一阶段顺序汇总在 [`Fieldwatch鸿蒙迁移Agent交接提示词.md`](./Fieldwatch鸿蒙迁移Agent交接提示词.md)。接手 Agent 仍必须以源码、命令输出和本文件中的验收状态为准，不得把交接提示词替代为功能证据。

## 当前实现总览（2026-10-06）

状态含义：`已完成` 表示源码、必要测试和对应证据齐备；`部分完成` 表示已有可用实现但仍缺测试、页面接入或真机证据；`未开始` 表示尚未进入实现。

| 阶段/任务 | 当前状态 | 已落地内容 | 尚未满足的验收 |
|---|---|---|---|
| FW-001~FW-004 迁移骨架 | 已完成/部分完成 | 迁移文档、能力映射、验收矩阵、`.agent-state`、domain/radio/data 边界和统一扫描协调器已建立 | 生命周期和重复订阅仍需完整设备回归 |
| FW-101 | 部分完成 | 无线电、RSSI、签名、过滤、日志、sit、GPS、隐私基础模型已存在；RSSI 改为保留最近 40 条带时间的有效样本，并恢复均值/趋势契约；移动伴随筛选按原版补入 BLE hear-time GPS/RSSI 轨迹与路径判定 | 本轮 LocalUnit 已在 DevEco 26.0 工具链通过；RSSI UI 与真实定位行走场景仍待用户 API26 验收 |
| FW-102 | 部分完成 | BLE 广播解析器现在校验 AD 长度/type/payload，提取 Service UUID、Local Name、Manufacturer Company ID；Fast Pair、DULT、OpenDroneID 使用结构化 service UUID 识别；Wi-Fi IE 按 TLV 校验并输出 IE 数量/ID/长度；有效、截断和未知结构 LocalUnit 已通过 | 生产帧的完整协议字段解码和 API26 真机原始字段样本仍待补 |
| FW-103 | 部分完成 | 签名按地址、Manufacturer Data、SSID、名称、厂商和无线电类型匹配；返回匹配字段、原因和优先级，LocalUnit 已通过 | Catalog 字段解码和页面解释结果展示仍待补 |
| FW-104 | 部分完成 | RSSI、无线电、签名、关注、重点目标、fresh/缓存的 AND/OR 过滤、基础地理距离和 RSSI 样本平均/趋势已实现；本轮计时趋势和移动候选 LocalUnit 已在 DevEco 26.0 工具链通过 | 路径报告、移动伴随 GPS 行走和分类筛选 UI 仍待用户验收 |
| FW-105~FW-106 | 部分完成 | 新增 CSV/JSONL/GPX/KML/WiGLE 领域序列化器，并沿用地址/坐标掩码；设置备份、筛选预设和关注列表边界已有 LocalUnit 覆盖；设置备份经 DocumentViewPicker 保存/恢复已在 API26 真机验证；观测 CSV 导出到用户选定位置已取得真机文件样本（163 行、含 signatures/decoded 列），并修复保存选择器默认后缀不匹配文件类型的缺陷 | 其他分享格式（JSONL/GPX/KML/WiGLE）的实际外发样本仍未闭环 |
| FW-201~FW-206 | 部分完成 | BLE/Wi-Fi 独立扫描、Wi-Fi 前置检查、单飞、状态机、30/45/60 秒周期、8/16/32/45 秒退避、缓存/fresh、RDB schema v3（含 sit 设备快照）、5000 条保留、最近 500 条恢复已实现；LocalUnit 已覆盖权限拒绝、Wi-Fi/位置关闭、重复订阅、停止解绑、回调忽略、异常退避和立即重试；API26 最新 HAP 立即重试已取得回调 1/49 条 AP/BLE 并行证据；2026-10-06 在 U30 环境取得 6 分 31 秒连续矩阵（9 次请求、9 次 `wifiScanStateChange=1`、0 失败、25–34 条/批、间隔 46.3–46.5 秒，同窗口 BLE 13338 条、0 告警）与请求计数日志，以及逐周期 `scanning/fresh=false → ready/fresh=true` 切换证据 | 普通路由器主环境 5 分钟、位置关闭/权限拒绝/前后台真机矩阵仍未完成 |
| FW-301~FW-305 | 部分完成 | Fieldwatch 直达入口、HDS 四 Tab、横屏侧栏、沉浸式全屏雷达、真实 Wi-Fi/BLE 点位、点位标签、详情预览/半屏 Sheet、分类筛选 Chip、筛选预设、强度/时间线/分类列表排序、Settings 动态 Wi-Fi 重试倒计时、NGF 跟随系统/浅色/深色主题控件、可操作 Filters/Reports/Settings 基础分区和中英文资源已接入；API26 真机已显示 Filters 类别/预设控件、Settings 倒计时和主题控件；2026-10-05 高密度雷达标签避让已真机截图验证；2026-10-06 真机补齐点位命中→浮动预览→半屏 Sheet 两级交互和强度/时间线/分类排序矩阵，并修复详情字段绑定（新增名称/位置行、地址行改为纯地址、位置缺失显示本地化“无”、BLE 的 Wi-Fi 专属字段显示“不适用”）、时间线 epoch 毫秒显示（改为 `HH:mm:ss` + 本地化“N 次观测”）和浮动预览卡跨视图残留 | 跨重启预设恢复已闭环（2026-10-11：保存自定义预设 → 重启仍在 → 点按恢复仅 BLE → 长按删除后 preferences 清空）；浅色主题下雷达与信号轨迹画布已核实为随主题自适应（原「硬编码深色」结论作废）；完整报告动作与手机/横竖屏回归未完成 |
| FW-401~FW-407 | 部分完成 | Named sit 删除、位置采样缓存、sit 设备快照、结束时 RDB flush、真实 shared/added/removed Compare 统计、Debrief/Path 文本或 GPX 生成、CSV/JSONL/GPX/KML/WiGLE 分享入口、应用沙箱导出、设置备份恢复、筛选预设/关注列表持久化和用户主动 Catalog 更新入口已接入；Compare 集合契约已通过 LocalUnit；最新 schema 3 HAP 真机 Reports 重载显示 sit 计数 259/156/136，ShareKit 面板实际输出 Shared 156、Added 0、Removed 103、Difference -103；Catalog 两个镜像请求现各有 15 秒连接/传输超时，超时后继续回退下一个镜像；Catalog 网络更新成功与幂等路径已取得 API26 真机证据（显示「目录已更新」，版本 102/611 不变）；观测导出经系统选择器写入公共 Download 目录已真机闭环 | 位置权限/服务关闭矩阵、schema 3 旧数据库现场迁移和 Catalog 断网失败路径尚未形成闭环 |
| FW-501~FW-508 | 部分完成 | 关注目标通知、通知去重/取消、后台保持被动扫描开关和 Ability 前后台/销毁生命周期门面已接入；Fieldwatch 服务卡片已有状态模型、表单登记/清理、数据推送和独立心跳实现；API26 真机已显示相关 Settings 控件 | 后台连续运行/保活/功耗、关注设备实际通知内容、卡片刷新/心跳、实况窗、流转、子窗口和生物识别均未完成完整验证 |

| FW-601~FW-606 特征库 | 部分完成 | 新增 `fieldwatch/domain/signatures/`：21 类签名类别（BODYWORN/ROUTER 折叠）、11 种匹配规则、解码字段模型（来源/偏移/长度/字节序/位域/缩放/取模/命名值/Strong/live/门控）、pack 编解码（未知键忽略、未知解码来源只丢弃解码映射）、导入合并（指纹去重、重名改名）、stock 覆盖（保留用户停用状态、额外规则与自定义行）、OUI 索引匹配引擎（含 cluster 与目录级仲裁）、字段解码器；当前内置 stock catalog 源文件为 v102、611 条签名；`FieldwatchBleAdvertisementDecoder` 按 AD 结构解码 Flags / 16-32-128 位 Service UUID / Local Name / TX Power / Service Data / Manufacturer Data；BLE 扫描器改用 `manufacturerDataMap`/`serviceDataMap`（API 22+）并保留原始包回退；Wi-Fi 扫描器提取厂商 IE OUI；新增 HDS 特征库页面（搜索、20 类筛选、启用停用、详情 Sheet、导出/导入/更新/恢复默认）和 Settings 入口，设备详情显示命中签名与解码字段；新增用户签名编辑器页面（名称/类别/启停/任一或全部规则、11 种规则增删改、解码来源与字段增删改）并从特征库页与设备详情进入；Live 列表行显示 live 解码 chip，Debrief 增加签名命中与解码统计，Compare 增加共享签名，CSV/JSONL 导出增加 signatures/decoded 列；编辑器补齐门控（eq/neq/mask/nmask/len + 一层 and）与命名值（原始值/显示文本/强提示/说明）编辑；雷达点位与列表图标按签名 colorIndex 着色（9 色调色板），无命中退回无线电类型颜色；雷达标签在无名称/SSID 时回退显示签名名；设备详情新增「签名依据」；特征库页显示每个签名当前命中设备数；实现「关注整个签名/产品族」（基线 §7.1 一直缺失）；过滤器新增「仅已匹配签名 / 仅含解码值 / 仅含位置」；新增 `scripts/audit-signature-catalog.ps1` 对真实 stock 目录做契约审计 | 用户文件通道已接入（API26 `DocumentViewPicker` 已确认存在，此前「未确认」的结论已作废）；**v102 / 611 条真机加载与类别筛选交互已复验**（无人机 13/611 与目录审计一致）；真机视觉与交互矩阵（滚动性能、详情 Sheet、编辑器）未做；stock 目录的 cluster 字段（minPeers/clusterByOui/sequentialMac）在 stock 中全为 0，只对用户签名生效 |

| FW-607 Hunt 目标搜寻 | 已完成（真机待验） | 新增 `domain/FieldwatchHunt.ets`：7 种提示状态（非常近/更近/更远/基本没变/聆听/安静/消失）、最近与更早窗口比较（2s / 3.5–8s、3 dB 阈值、8s 安静判定、-45 dBm 非常近）、geiger tick 间隔映射（-40→90ms，-90→1400ms）、会话样本上限 240 与峰值/区间/均值统计；新增 `platform/FieldwatchHuntFeedback.ets` 触感节拍（`vibrator.HapticFeedback.EFFECT_SHARP` 能力检测 + 静默降级）并声明 `ohos.permission.VIBRATE`；应用层单会话管理 + ingest 采样 + missing 判定；新增 `pages/fieldwatch/FieldwatchHuntPage.ets`（状态/提示/当前/峰值/区间/均值/样本、脉冲动画、节拍开关、免责声明、停止）与设备详情入口；LocalUnit 新增 7 个用例 | 音频节拍已实现：内置 40ms 2.2kHz tick（`rawfile/fieldwatch-tick.wav`，3572 字节）经 `media.createSoundPool` + `getRawFd` 加载，与触感组成组合反馈，任一不可用不影响另一个；真机触感/音频与实际接近判断仍待验证 |
| FW-608 目录与关注完善 | 已完成（真机待验） | 目录排序（按名称/按类别，基线 `SignatureListSort`）；过滤预设删除与默认预设；新增「仅已命名设备」过滤；关注列表支持观察者备注、内置关注项（Extra attention 签名 + 无人机类签名）与 Settings 列表移除；修复两个真缺陷：预设往返丢失 20 类中的 16 类、签名级关注重启后被丢弃 | 多预设已实现（具名保存/同名覆盖/载入/删除 + 旧单预设自动迁移）；用户文件通道已实现（`DocumentViewPicker` 导出到用户选择位置、从用户选择的签名包导入）；预览卡与详情图标已按签名 colorIndex 统一着色；修复内置目录在 Ability 上下文就绪前静默为空的问题（页面出现时重试）；真机视觉与交互矩阵未做 |

当前交付边界：可继续验收 BLE + Wi-Fi 被动观测、缓存/fresh、Wi-Fi 独立错误、RDB 恢复、HDS Live 雷达和基础导航；特征库领域、数据与基础 UI 已落地但真机未验收；不能宣称完整 Fieldwatch 功能或鸿蒙增强阶段完成。

## 2026-10-11 后续验收补充

以下记录更新 2026-10-06 基线之后取得的证据，不覆盖仍未完成的迁移任务：

- **单目标相对测向**：在寻线页使用方向与陀螺仪传感器，以 16 个扇区聚合转动期间 RSSI；16/16 的 API26 真机样本未形成可靠峰值，页面未输出方向。该能力只提供相对提示，不提供绝对方位或坐标。
- **设置备份外部文件**：使用 `DocumentViewPicker` 将 `.fieldwatch` 备份保存到用户选定目录，并从选定文件恢复；API26 真机完成实际保存、恢复和设置值核对。取消保存不会回退写入 Downloads。
- **仍未闭环**：迁移任务表中普通路由器长时扫描、权限弹窗人工操作、位置开关矩阵、旧 RDB schema 迁移、Catalog 断网失败路径、手机布局与剩余鸿蒙增强项仍须逐项取证；本补充不将它们改记为完成。（原列的「通用观测导出公共文件样本」与「Catalog 网络成功」已分别于 2026-10-11 取得真机证据。）
- **移动伴随筛选**：按 Android `CoTravel.withYou` 契约恢复 BLE-only 判定，使用最近 90 秒内最多 40 条 hear-time 手机位置/RSSI 样本，验证手机移动距离、设备轨迹跨度/长度、近时观测、信号强度与设备末次位置距手机路径的速度容差；Wi-Fi AP 一律排除。中英文标签已改为“可能同行 / Possible Co-Travel”，并说明是启发式而非跟踪确认。新增 LocalUnit 覆盖有效随行、静止/远离/过期目标、Wi-Fi 排除和轨迹上限；已通过 API26 配套 Hvigor 的 LocalUnit，真实定位行走场景待用户验收。
- **用户签名数据丢失（已修复，2026-10-12）**：真机复现「新建自定义签名 → 重启 → 签名消失、目录回到内置 611 条」。根因两层：`FileUtils.readText` 单次 `readSync` 未读满即解码（大文件截断成非法 JSON）；构造期沙箱基础目录未就绪时读取返回空串，`loadSaved` 把「读空」当成「无本地目录」，启动流程随即用内置目录落盘覆盖。修复为分块循环读、以 `exists()` 区分「无文件/读不出」、损坏时拒绝落盘并在页面出现时补读。修复后同场景重启文件字节数与 mtime 不变、界面 612/612、签名在列；删除路径复核回落 611/611。规则沉淀为 PR-007。
- **导出后缀契约**：新增 `fieldwatch/domain/FieldwatchExportNaming.ets`，把「文件名 → 保存选择器默认后缀」做成纯函数；`FieldwatchCatalogFileGateway` 改为调用它。新增 LocalUnit `FieldwatchExportNaming.test.ets`（5 用例）锁定七种文件名（五种导出格式 + 签名包 + 设置备份）的首项后缀、候选完整性与边界；真机回归确认 CSV 默认后缀仍为 `.csv` 并成功写出 181 行文件。
- **RSSI 时间趋势**：用带时刻的最近 40 条有效 RSSI 样本恢复 Android 基线的滚动平均与 12 样本前后半段趋势，阈值为 ±3 dB / ±8 dB；少于 4 个有效样本时不显示方向标记。实时轨迹列表用绿色/红色/中性色及快慢字号展示趋势，Hunt 初始样本沿用真实时间戳。均值窗口、趋势分类、无效值和样本上限 LocalUnit 已通过；默认和 release HAP 编译通过，API26 实际数据/视觉仍待用户验收。

## 执行约束

- Fieldwatch 业务代码只放在 `entry/src/main/ets/fieldwatch`；`ngf_framework` 只承载跨应用通用能力。
- 领域层不得导入 HarmonyOS 系统包；系统能力通过 `radio`、`data` 和平台适配接口进入。
- 不主动连接、控制或上传被观测设备数据。
- 每个任务按“调查中 -> 实现中 -> 静态通过 -> 单测通过 -> 真机待验 -> 真机通过/阻塞”推进。
- 每个任务交付源码、测试和文档状态；未验证的系统能力不得标记完成。

## Phase 0：迁移骨架

| ID | 任务 | 目标范围 | 技能 | 验收 |
|---|---|---|---|---|
| FW-001 | 建立迁移文档和检查点 | 本文、能力映射、验收矩阵、`.agent-state` | onboarding、local-rules、project-governance | 每个后续任务都有 ID、路径、技能和验证方式 |
| FW-002 | 建立 Android -> NGF 分层映射 | `docs/Fieldwatch功能完整清单.md`、`entry/fieldwatch` | ngf-app-harness、component-reuse | 不把业务逻辑移入框架层 |
| FW-003 | 固定平台边界 | domain/radio/data 接口 | arkts-standards、arkts-types | 领域层无系统包导入 |
| FW-004 | 固定扫描生命周期 | `FieldwatchRadioScanner` 及协调器 | arkts-standards、arkts-runtime-fix | 启动、停止、错误、重复订阅和页面销毁可验证 |

## Phase 1：纯领域能力

| ID | 任务 | 目标范围 | 技能 | 验收 |
|---|---|---|---|---|
| FW-101 | 扩展领域模型 | `fieldwatch/domain/FieldwatchModels.ets` | arkts-standards、arkts-types | 无线电、RSSI、签名、日志、sit、位置模型可独立测试 |
| FW-102 | 广播和 IE 解析 | 新增 `fieldwatch/domain/parsers/` | arkts-standards | 有效、截断、未知、重复帧测试通过 |
| FW-103 | 签名和字段解码 | `FieldwatchDomainService.ets` 及 catalog 模型 | arkts-standards | BLE/Wi-Fi 多规则匹配可解释 |
| FW-104 | 过滤、地理和移动候选 | domain 服务 | arkts-standards | AND/OR、RSSI、路径和隐私测试通过 |
| FW-105 | 导出序列化 | 新增 `fieldwatch/domain/export/` | arkts-standards | CSV/JSONL/GPX/KML/WiGLE 输出稳定 |
| FW-106 | 隐私外发策略 | domain 服务 | arkts-standards | 掩码只影响展示和外发，不改原始日志 |

## Phase 2：BLE + Wi-Fi 观测闭环

| ID | 任务 | 目标范围 | 技能 | 验收 |
|---|---|---|---|---|
| FW-201 | 治理 BLE 生命周期 | `FieldwatchBleScanner.ets` | arkts-standards、arkts-runtime-fix | 回调对称解绑、错误可恢复 |
| FW-202A | Wi-Fi 前置检查 | `FieldwatchWifiScanner.ets`、权限/位置适配 | manager-apis、arkts-debug | 权限、Wi-Fi STA、位置总开关按固定顺序分类 |
| FW-202B | Wi-Fi 状态机和单飞 | `FieldwatchWifiScanner.ets`、`FieldwatchRadioScanner.ets` | arkts-standards、arkts-types | 状态回调订阅在请求前完成，同一时间最多一个请求 |
| FW-202C | Wi-Fi 退避和周期 | `FieldwatchWifiScanner.ets`、`FieldwatchApplication.ets` | arkts-debug、arkts-runtime-fix | 30/45/60 秒周期，8/16/32/45 秒退避，暴露 nextAttemptAt |
| FW-202D | Wi-Fi 结果模型和缓存 | `FieldwatchModels.ets`、`FieldwatchWifiScanner.ets` | arkts-standards、arkts-types | 成功回调才 fresh，缓存不覆盖，空结果不覆盖已有结果 |
| FW-202E | API26 真机矩阵 | `docs/Fieldwatch鸿蒙验收矩阵.md`、`.local-rules/device-hdc.local.md` | device-hdc-debug、automation-test | 普通路由器为主验收，U30 作为兼容性场景 |
| FW-203 | 合并观测源 | 新增协调器和统一源接口 | arkts-standards、arkts-types | BLE/Wi-Fi 事件统一进入聚合 |
| FW-204 | 本地设备和日志存储 | `fieldwatch/data/FieldwatchObservationRepository.ets`、`FieldwatchApplication.ets` | component-reuse、arkts-standards | NGF RDB 保存观测关键字段，重启后恢复最近 500 条 |
| FW-205 | 数据库迁移 | `fieldwatch/data/FieldwatchObservationRepository.ets` | component-reuse、arkts-error-fixes | schema version=3、观测表/索引/sit 表及 `device_keys` 字段幂等创建/迁移；观测上限 5000 条 |
| FW-206 | 权限和能力状态 | `module.json5`、权限门面、Live 状态区 | manager-apis、arkts-runtime-fix、i18n | 拒绝、关闭、节流、不支持、扫描强度和恢复入口可见 |

## Phase 3：基础产品 UI

| ID | 任务 | 目标范围 | 技能 | 验收 |
|---|---|---|---|---|
| FW-301 | HDS 导航壳 | Fieldwatch 页面和路由 | hds-page-design、hds-tab、arkui-knowledge | Live/Filters/Detail/Settings 可导航 |
| FW-302 | Live/Filters/Detail | `fieldwatch/ui` 及页面路由 | arkts-standards、arkts-types、component-reuse | 稳定 key、无数据和错误状态完整 |
| FW-303 | 关注和显示控制 | application/ui | manager-apis、arkui-knowledge | 暂停显示不停止扫描，关注状态可恢复 |
| FW-304 | 设置和隐私 | settings repository/ui | manager-apis、i18n | 设置持久化、主题和屏幕常亮可用 |
| FW-305 | 中英文资源 | `base/en_US/element/string.json` | i18n、ui-symbols | 无硬编码用户文案 |

### HDS UI/UX 交付拆分

| ID | 任务 | 目标范围 | 技能 | 当前状态 |
|---|---|---|---|---|
| FW-301A | HDS 根导航壳 | `pages/fieldwatch/FieldwatchPage.ets`、Fieldwatch 路由 | hds-page-design、hds-tab、arkui-knowledge | 已实现；紧凑标题模式与安全区修复已通过 API26 点击验收 |
| FW-301B | 手机/竖屏 Tab、横屏侧栏 | `FieldwatchPage.ets`、`ngfDeviceAdaptationFacade` | manager-apis、hds-tab | 竖屏统一使用 HDS Tab，只有横屏使用左右分区；标题栏已移除 |
| FW-302A | Live 经典雷达 | ArkUI Canvas、雷达点位映射 | arkui-knowledge、arkts-types | Canvas 雷达、扫描束、Wi-Fi/BLE 点位已实现 |
| FW-302B | Live 多视图 | 雷达/强度/时间线/分类切换 | hds-tab、i18n | 强度按 RSSI、时间线按最近发现、分类按稳定设备 key 排序并展示对应摘要；排序契约已通过 LocalUnit，真机视觉/操作矩阵待补 |
| FW-302C | 设备详情 | 雷达点位命中、悬浮预览卡、NGF Material Sheet | hds-page-design、arkui-knowledge | 预览卡、二次点击 Sheet 和半屏 detent 已实现；真机点位命中与坐标校准待补 |
| FW-303A | Filters | 信号源、RSSI、类别 Chip、签名、关注/重点、fresh/缓存、AND/OR、保存/恢复预设、清除筛选已接入 | hds-tab、arkui-knowledge | API26 真机已显示类别和预设控件；**跨重启预设恢复已闭环**（保存自定义预设 → 重启 → 预设仍在 → 点按恢复「仅 BLE」→ 长按确认删除后 preferences 清空）；完整视觉矩阵待补 |
| FW-403A | Reports 骨架 | sit 开始/结束/删除、Debrief、Compare 和 Path 条件化动作、多格式分享入口已接入 | hds-page-design、i18n | 真机实际分享内容、第二 sit 对比数据和位置样本验收待补 |
| FW-304A | Settings | 扫描强度、隐私和显示入口 | manager-apis、i18n | 扫描强度、Wi-Fi 状态/最近成功/下一次尝试、动态倒计时、暂停、常亮、位置、隐私、跟随系统/浅色/深色主题、备份和 catalog 入口已接入；主题控件、浅色/深色截图及设置备份外部文件保存/恢复 API26 已验，Catalog 网络结果仍待补 |

## Phase 4：日志、位置、报告和导出

| ID | 任务 | 目标范围 | 技能 | 验收 |
|---|---|---|---|---|
| FW-401 | 位置和路径 | location adapter、sit 数据 | manager-apis、arkts-runtime-fix | 明确标注为手机听到位置 |
| FW-402 | Named sit | `fieldwatch/data/FieldwatchObservationRepository.ets`、`FieldwatchApplication.ets`、Reports | component-reuse、arkts-standards | 开始、结束、保存、读取、删除接口已落地；**Reports 页面已接入并真机闭环**（记录页会话卡片显示名称与 radioCount、重命名、删除、「删除全部会话」；结束后计数即时刷新缺陷已修复并复验）；**schema 3 旧库现场迁移仍待补** |
| FW-403 | Debrief/Compare/Path | Reports 页面 | hds-page-design、i18n | 无网络可生成结构化报告 |
| FW-404 | 文件导出 | domain/export、系统文件能力 | component-reuse、system-tasks | CSV/JSONL/GPX/KML/WiGLE 可保存或分享 |
| FW-405 | 设置备份 | settings repository | component-reuse、i18n | 应用沙箱备份/恢复和 DocumentViewPicker 用户选址另存为均已实现；API26 真机完成外部文件保存、读取恢复与值核对；不包含日志、catalog、GPS |
| FW-406 | 系统分享 | `ngfSystemShareFacade` | component-reuse | 外发内容遵守隐私策略 |
| FW-407 | Catalog 更新 | contentSource/network 适配 | component-reuse | 仅用户主动联网；stock 替换/用户签名保留契约已通过 LocalUnit；更新失败保留旧目录；网络成功/失败真机证据待验 |

## Phase 5：鸿蒙原生增强

| ID | 任务 | NGF 能力 | 技能 | 验收 |
|---|---|---|---|---|
| FW-501 | 后台扫描 | `ngfSystem`、`ngfBackgroundTaskManager` | system-tasks、manager-apis | 用户显式开关和 Ability 生命周期接入；连续运行、系统保活、功耗和停止释放待真机验证 |
| FW-502 | 关注/异常通知 | `ngfSystemNotificationManager` | system-tasks、i18n | Settings 开关、按需权限、原生授权流程、进程内通知去重和关闭时取消已实现；关注设备实际弹出内容和系统栏取消待真机验证 |
| FW-503 | 实况窗能力验证 | `ngfLiveViewManagerFacade` | system-tasks | 未接入系统 API 时保持未完成 |
| FW-504 | 桌面卡片验证 | `ngfWidgetManagerFacade` | system-tasks | 状态渲染、2*2/2*4 尺寸、后台心跳、计数刷新与停止状态须经 API26 真机验收；验收步骤见 `docs/Fieldwatch鸿蒙验收矩阵.md` |
| FW-505 | 跨设备流转 | `ngfContinuationManagerFacade` | manager-apis | 参数和恢复状态可验证 |
| FW-506 | 多实例/子窗口 | `MultitonEntryAbility`、窗口门面 | window-management | 不直接调用原生 createSubWindow |
| FW-507 | 现场交互优化 | 握持感知、屏幕常亮、设备适配 | manager-apis | 不支持设备有降级 |
| FW-508 | 敏感数据保护 | 生物识别门面 | manager-apis、arkts-runtime-fix | 只保护报告、坐标和原始导出 |

## 验证门槛

每项任务分别记录构建、领域测试、运行、内容、视觉、生命周期和性能证据。API26 真机是最终依据，模拟器只能补充；编译成功不能替代运行、内容或视觉验收。FW-202 在普通路由器真机闭环前保持“真机待验”。

## 当前收尾状态与待办（2026-10-12）

> 本节是「还差什么、卡在哪、需要谁做什么」的汇总；逐项证据见 `docs/Fieldwatch鸿蒙验收矩阵.md`。

### A. 设备侧阻塞（需先给平板充电）

2026-10-12 晚，真机（MatePad Mini MLR-AL10）进入**系统「低电量应急模式」**，界面只剩电话/信息并提示「可能因电量过低导致直接关机」，`pidof com.dlzz.airwavefootprints` 为空 —— Fieldwatch 进程已被系统杀掉。当时的注入点击「按下无响应」由此而来，**不是应用缺陷**。

设备恢复后需继续的真机项：

| 项 | 现状 | 恢复后怎么做 |
|---|---|---|
| **KML / WiGLE 落盘样本** | 未取得（当时格式停在 CSV） | 导出面板坐标已实测：格式 KML `(2362,739)`、WiGLE `(1646,835)`、分享 `(2011,1123)`、保存到文件… `(2010,1251)`；选中后点保存，等选择器（**可延迟约 70 秒**）再确认 |
| **对比（PDF）** | 未单独验证（需两段观测窗口） | 先连续建两段观测（开始会话 → 确认 → 结束会话），再点「对比（PDF）」，核对沙箱 PDF 与对话框回显 |
| **「存到下载目录」** | 未验证；代码中无隐式回退，该项是**显式**菜单项 | 特征库 → 更多 → 存到下载目录，核对 `/storage/media/100/local/files/Docs/Download` 出现 `fieldwatch-signatures.json` |

### B. 需要你决策的两件事

1. **Catalog 断网失败路径**（FW-407 的网络成功/失败真机证据）：需要临时把设备网络断开或指向不可达地址。是否允许我临时切换设备网络？若不允许，请由你手动断网后告诉我，我再触发「更新内置目录」并取证。
2. **导出标签命名**：同一能力在**设备详情页**叫「AI 导出」，在**记录页两张卡片**上叫「文本导出」，而两者产物都是给 AI 的提示词文档。建议二选一 —— ① 记录页统一改为「AI 导出」；② 保留「文本导出」但在文档首行说明这是 AI 提示词。等你定夺后再改。

### C. 需要你手动执行的一步（自动化驱动不了）

**特征库 → 更多 → 恢复默认目录**：清掉验证流程留下的 5 条用户签名（`CMCC` ×2、`Company 0x027D 10`、`UUID FE95`、`Vendor IE 000005`）。该菜单（`bindMenu`）在页面每秒刷新下会自动关闭，本轮用多种点击间隔（0.3–2.5 秒）均未能命中。

### D. 依赖物理动作 / 现场无线环境（我给出验收标准，等你的结果）

| 项 | 前置条件 | 通过标准 |
|---|---|---|
| 可能同行 | 至少两台设备**同时移动**，且位置标注开启 | 记录页出现「可能同行」分组，组内包含这两台；关闭位置标注后该分组消失 |
| 实时解码值 | 现场存在已适配设备：Aftermarket TPMS / Govee / GoPro / Blue Maestro 等 | 设备详情「解码字段」显示与实物一致的实时值（如 TPMS 胎压、Govee 温湿度），而非占位符 |
| 单目标相对测向 | 手持设备走动，目标为单个稳定信号源 | 工具箱「信号追踪」峰值/区间/均值随走动合理变化，方向提示在可支持设备上出现 |
| 横竖屏与手机端适配 | 手机或旋转平板 | 横竖屏切换后布局不遮挡、侧栏与列表正确重排 |
| 服务卡片 / 实况窗 / 流转 / 子窗口 / 生物识别 | 系统侧入口 | 卡片渲染与计数刷新、实况窗状态、跨设备流转恢复、子窗口多实例、敏感数据解锁各自通过 |
| 权限弹窗取证 | 首次授权 | Wi-Fi/蓝牙/位置/通知授权弹窗文案与本应用说明一致，拒绝后功能降级可解释 |

### E. 本轮会话已闭环的要点（速览）

- **内置特征目录丢失缺陷**（候选「添加到目录」把 611 条内置签名从落盘文件抹掉）—— 已修复 + 启动自愈 + 真机复现与复验；并沉淀规则 PR-009。
- **会话计数/改名不即时刷新** —— `ForEach` key 只用 id 导致原地更新不重绘，已修复并真机复验。
- **隐私模式脱敏漏洞** —— `key` 字段内嵌 MAC 未脱敏，已修复（CSV/JSONL 双格式）+ 负向不变量测试 + 真机 114 行零残留。
- **复盘 PDF** —— 生成、落盘、路径回显与正文内容全部验证（样本 `fw-r24-debrief.pdf`）。
- **工具箱三标签**（信道分析 / 信号追踪 / 反追踪）—— 真机全部验收，含信道拥堵排序与推荐、反追踪评分随伴随时长升级。
- **AI 导出（文本导出）** —— 真机验证产物为 `# Fieldwatch AI 对比补充说明 / Compare addendum`。
- **签名级关注跨重启存活** —— 真机回归通过（此前缺陷确认修复）。
