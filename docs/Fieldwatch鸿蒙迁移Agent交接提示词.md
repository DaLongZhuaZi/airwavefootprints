# Fieldwatch 鸿蒙迁移 Agent 接手提示词

> 用法：把本文完整复制给接手的 Agent。本文是当前工作区的交接提示词，不替代源码、测试输出或 API26 真机证据。接手后必须以当前源码和命令结果复核事实，不能只相信本文件。

你正在接手 `F:\DevEcoStudioProject\airwavefootprints` 中的 Fieldwatch 鸿蒙迁移。项目是 NGF 框架验证工程中的 Fieldwatch 应用模块：NGF 共享层保持通用能力，Fieldwatch 业务实现放在 `entry/src/main/ets/fieldwatch` 和 `entry/src/main/ets/pages/fieldwatch`。不要把项目误改造成 `ngf_framework` 的业务特化实现。

## 1. 总目标和已经确认的产品边界

持续完成 Fieldwatch Android 基线到 HarmonyOS API26 的迁移，并逐项取得“源码实现、静态检查、LocalUnit、构建、API26 真机、内容/视觉/生命周期/性能”证据。优先顺序固定为：

1. 先功能等价，再做鸿蒙原生增强。
2. API26 MatePad Mini 真机是最终证据，模拟器只作补充。
3. 首个可交付范围是 BLE + Wi-Fi 被动 Live、过滤、设备详情、关注列表、本地日志、基础位置标记、设置和隐私模式。
4. 严格离线。网络只允许用户主动点击更新 Catalog；不得自动更新、上传观测或接入 Fieldwatch 后端。
5. 只被动监听，不主动连接、控制、攻击、干扰或上传被观测设备数据。
6. 普通路由器是 Wi-Fi 主验收环境，U30 热点只是兼容性场景。
7. Wi-Fi 失败必须独立进入可恢复状态，BLE 继续扫描和记录。
8. 未取得 API26 真机证据的系统能力保持“真机待验”，不能写成完成。

用户已经明确的 UI/UX 方向：

- 学习原版 Fieldwatch 的信息密度和雷达表达；参考原版源码、术语表和设计图片。
- 实时雷达页无论竖屏还是横屏都以整屏雷达为主，点位显示真实设备信息，点位距离由 RSSI 映射，不能用静态装饰点冒充观测。
- 竖屏（包括平板竖屏）使用 HDS 底部 Tab；只有横屏才使用左右分区/侧栏。
- 完全去掉应用标题栏，顶部和底部系统区域做沉浸式处理，不能遮挡内容和点击区域。
- 点位第一次点击/鼠标悬停显示靠近点位的浮动预览；再次点击预览才打开完整详情 Sheet；Sheet 初始 `SheetSize.MEDIUM` 半屏，可上拉到 `SheetSize.LARGE`。
- 遵循鸿蒙 HDS、系统 Symbol、NGF facade、动态安全区和中英文资源规范。不要新增 Emoji 作为 UI 图标。

## 2. 接手第一步：必须重新读取的规则和事实

在读取或修改源码前，按 UTF-8 完整读取：

```text
AGENTS.md
.rules/README.md
.local-rules/README.md
.local-rules/base-local-rules.md
.local-rules/device-hdc.local.md
.agent-rules/README.md
.agent-rules/project-rules.md（全部 active 条目）
.agent-state/fieldwatch-migration.local.md
```

按实际任务命中并完整阅读技能文件：

- 基线/NGF：`skill-llm-onboarding.md`、`skill-local-rules.md`、`skill-ngf-app-harness.md`、`skill-project-rule-governance.md`、`skill-component-reuse.md`。
- ArkTS/ArkUI：`skill-arkts-standards.md`、`skill-arkts-types.md`、`skill-arkui-knowledge.md`。
- HDS/UI：`skill-hds-page-design.md`、`skill-hds-tab.md`、`skill-i18n.md`、`skill-ui-symbols.md`、涉及主题时 `skill-manager-apis.md`。
- 系统能力：涉及后台/通知时 `skill-system-tasks.md`，涉及子窗口时 `skill-window-management.md`。
- 测试/真机：`skill-automation-test.md`、`skill-device-hdc-debug.md`；涉及运行时故障时再读 `skill-arkts-debug.md` 和 `skill-arkts-runtime-fix.md`。

不要因为本文已经总结过规则而跳过再次读取。发生上下文压缩、交接、目标切换或新增报错时，重新执行这一步。

## 3. 当前工程和入口事实

以源码为准复核下列事实：

| 项目 | 当前事实 |
|---|---|
| 工作区 | `F:\DevEcoStudioProject\airwavefootprints` |
| Android 原版 | `G:\Github\Fieldwatch` |
| bundle | `com.dlzz.airwavefootprints` |
| module | `entry` |
| Ability | `EntryAbility` |
| target/compatible SDK | `26.0.0` / `26.0.0` |
| 产品入口 | `entry/src/main/resources/base/profile/main_pages.json` 中的 `pages/fieldwatch/FieldwatchPage` |
| NGF 演示入口 | `pages/ngf/MainMenuPage`，保留用于框架演示，不作为 Fieldwatch 首屏 |
| HAP | `entry/build/default/outputs/default/entry-default-signed.hap` |
| HDC | `G:\DevEco Studio 26\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe` |
| 当前真机 | MatePad Mini `MLR-AL10`，API 26 |
| 当前真机 HDC target | `192.168.0.36:40835`；2026-10-06 已实测 TCP Connected |
| 历史端口 | `192.168.0.36:35573`，保留为历史记录，当前 Offline |

多设备时所有 HDC 命令显式使用 `-t 192.168.0.36:40835`，不要依赖默认 target。用户已授权本项目的安装、启动、日志和 UI 自动化调试，但仍要避免无关破坏性命令。

## 4. 当前工作区状态：不要回滚

工作区已有大量用户和历史迁移修改，当前 `git status` 存在修改和新增文件。禁止 `git reset --hard`、无差别清理、回滚他人修改或删除未跟踪的业务文件。每次修改前先执行：

```powershell
git status --short
git diff --stat
```

不要提交以下本地文件和产物：`.local-rules/*.local.md`、`.agent-state/*.local.md`、构建缓存、临时截图、控件树 JSON、bugreport、设备临时文件和证书私密材料。

## 5. 进度文档和设计资料：以这些文件为准

### 迁移和验收文档

- `docs/Fieldwatch鸿蒙迁移任务计划.md`：阶段、任务 ID、源码范围、技能、当前状态和验收条件。
- `docs/Fieldwatch鸿蒙能力映射.md`：Android 能力到 HarmonyOS/NGF API/facade 的映射、权限、生命周期、降级和证据。
- `docs/Fieldwatch鸿蒙验收矩阵.md`：构建、领域、运行、内容、视觉、生命周期、性能、真机矩阵证据。
- `docs/Fieldwatch功能完整清单.md`：Fieldwatch Android 1.1.17 功能基线和鸿蒙平台差异。
- `.agent-state/fieldwatch-migration.local.md`：跨会话恢复检查点，只是辅助状态，必须以当前源码和命令结果复核。

每完成一组相关源码/测试，必须同步上述四份文档和 `.agent-state`；状态只能沿着：

```text
未开始 -> 调查中 -> 实现中 -> 静态通过 -> 单测通过 -> 真机待验 -> 真机通过 / 阻塞
```

### 原版 Fieldwatch 学习资料

- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\FieldwatchAppUi.kt`
- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\screen\LiveScreens.kt`
- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\screen\FiltersScreen.kt`
- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\screen\ReportsScreen.kt`
- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\screen\SettingsScreen.kt`
- `G:\Github\Fieldwatch\app\src\main\java\app\fieldwatch\ui\screen\DeviceDetailScreen.kt`
- `G:\Github\Fieldwatch\docs\i18n\glossary-zh-Hans.md`
- 设计参考图：`F:\Downloads-E\1791131591607.jpg`（雷达全屏、目标标签、状态栏/控制栏和移动端目标卡片的视觉参考；图片只是设计输入，不是功能证据）

### 当前鸿蒙实现关键文件

```text
entry/src/main/ets/fieldwatch/domain/FieldwatchModels.ets
entry/src/main/ets/fieldwatch/domain/FieldwatchDomainService.ets
entry/src/main/ets/fieldwatch/domain/FieldwatchParsers.ets
entry/src/main/ets/fieldwatch/domain/FieldwatchExportSerializer.ets
entry/src/main/ets/fieldwatch/radio/FieldwatchRadioScanner.ets
entry/src/main/ets/fieldwatch/radio/FieldwatchBleScanner.ets
entry/src/main/ets/fieldwatch/radio/FieldwatchWifiScanner.ets
entry/src/main/ets/fieldwatch/radio/FieldwatchObservationCoordinator.ets
entry/src/main/ets/fieldwatch/data/FieldwatchObservationRepository.ets
entry/src/main/ets/fieldwatch/data/FieldwatchSettingsRepository.ets
entry/src/main/ets/fieldwatch/data/FieldwatchCatalogRepository.ets
entry/src/main/ets/fieldwatch/application/FieldwatchApplication.ets
entry/src/main/ets/fieldwatch/ui/FieldwatchUiState.ets
entry/src/main/ets/fieldwatch/ui/FieldwatchRoutes.ets
entry/src/main/ets/fieldwatch/ui/FieldwatchDeviceTypeIcon.ets
entry/src/main/ets/pages/fieldwatch/FieldwatchPage.ets
entry/src/main/ets/entryability/EntryAbility.ets
entry/src/test/FieldwatchDomain.test.ets
entry/src/test/FieldwatchRadio.test.ets
entry/src/test/FieldwatchWifiScanner.test.ets
entry/src/test/List.test.ets
entry/src/main/resources/base/element/string.json
entry/src/main/resources/en_US/element/string.json
entry/src/main/resources/base/media/fieldwatch_*.svg
```

## 6. 当前完成情况（不能扩大证据边界）

### Phase 0：迁移骨架

FW-001~FW-004 已建立迁移文档、能力映射、验收矩阵、检查点、domain/radio/data 边界和统一扫描协调器，属于已落地但生命周期完整设备回归仍需补证。

### Phase 1：纯领域能力

- 已有无线电、设备、RSSI、签名、过滤、日志、sit、位置和隐私模型。
- `FieldwatchParsers.ets` 已覆盖 BLE AD 基础长度/type/payload、Service UUID、Local Name、Manufacturer Company ID；Wi-Fi IE TLV；Fast Pair、DULT、OpenDroneID 的结构识别。
- 签名匹配支持地址、Manufacturer Data、SSID、名称、厂商、Service UUID、无线电类型，并返回匹配字段、原因和优先级。
- RSSI 最近样本、平均值和趋势；过滤支持 Wi-Fi/BLE、最小 RSSI、签名、关注、重点、fresh/cache、AND/OR、清除和预设。
- `FieldwatchExportSerializer.ets` 已提供 CSV、JSONL、GPX、KML、WiGLE 和隐私掩码副本。
- 相关 LocalUnit 已通过。
- 仍待：生产协议深度解码、完整真机原始 IE/Manufacturer Data 样本、路径/移动伴随和完整字段解释。

### Phase 2：BLE/Wi-Fi 观测闭环

- BLE 和 Wi-Fi 独立扫描；Wi-Fi 有权限、Wi-Fi STA、系统位置总开关前置检查。
- Wi-Fi 状态机具备单飞、回调注册顺序、回调 1 才读取结果、回调 0/异常分类、8/16/32/45 秒退避、30/45/60 秒周期、`nextAttemptAt`、缓存/fresh、空结果不覆盖、stop 后忽略回调。
- BLE/Wi-Fi 失败互不覆盖；RDB 观测、最近 500 条恢复、5000 条容量控制、schema 3 sit `device_keys` 迁移路径已接入。
- LocalUnit 已覆盖权限拒绝、Wi-Fi/位置关闭、801/201/2501000/2501001 分类路径、重复订阅、停止解绑、回调忽略、异常退避、立即重试、缓存/fresh、空结果和 BLE/Wi-Fi 独立运行。
- 最新 HAP 真机立即重试证据：`wifiScanStateChange=1`、成功 AP 49 条；同一约 12 秒窗口 BLE 343 条观测、错误 0。
- 仍待：普通路由器 5 分钟连续矩阵、位置关闭/权限拒绝/重新授权、前后台恢复、请求计数、旧 schema 现场迁移和功耗。

### Phase 3：Live/Filters/Detail/Settings

- HDS 四 Tab：实时、筛选、报告、设置；竖屏 Tab，横屏侧栏；`hideTitleBar(true)`；顶部/底部沉浸和安全区处理已接入。
- Live 有全屏 Canvas 雷达、扫束、稳定 key/角度、RSSI 半径、Wi-Fi/BLE 色彩、名称/SSID/RSSI/频率标签和高密度标签避让。
- Live 有雷达、强度、时间线、分类四视图；暂停显示冻结显示快照但继续扫描。
- 点位预览/二次点击 Sheet 已接入，默认 `MEDIUM`，可上拉 `LARGE`；八类可着色 SVG 设备图标已接入，导航图标使用 `sys.symbol`。
- Filters 已接入无线电、类别、签名、RSSI、关注/重点、fresh/cache、AND/OR、保存/恢复/清除。
- Reports 基础 sit、Debrief、Compare、Path、CSV/JSONL/GPX/KML/WiGLE 入口已接入；未验证能力用禁用/待验证状态表达。
- Settings 已接入扫描强度、Wi-Fi ready/最近成功/倒计时、BLE、暂停、常亮、位置、隐私、备份恢复、Catalog、关注通知、后台扫描、跟随系统/浅色/深色主题。
- 已取得 API26 Settings 控件树、深浅主题截图、高密度雷达截图和页面启动证据。
- 仍待：点位命中坐标矩阵、浮窗真实靠点、手机/平板全方向视觉回归、跨重启预设、详情字段完整绑定。

### Phase 4：位置、Named sit、Reports、导出

- 位置门面、15 秒位置缓存/单飞、Named sit 保存/删除、结束时 RDB flush、设备 key 快照和 Compare 集合计算已接入。
- 最新真机 Reports 重新加载显示 sit radioCount `259、156、136`；ShareKit 文本样本包含 `Shared: 156`、`Added: 0`、`Removed: 103`、`Difference: -103 radios`。
- 应用沙箱设置备份/恢复、当前数据保存和系统 ShareKit 文本分享已接入。
- 仍待：位置权限/位置服务关闭真机矩阵、真实位置/Path 内容、公共文件夹保存、全部格式外发样本、Catalog 网络成功/失败、schema 3 旧库现场迁移。

### Phase 5：鸿蒙原生增强

- 关注通知设置/授权入口、进程内去重/取消和后台被动扫描开关/Ability 生命周期门面已接入。
- 后台连续运行/保活/功耗、关注通知真实系统栏内容仍待真机验证。
- 实况窗、桌面卡片、跨设备流转、Fieldwatch 子窗口、多实例详情和生物识别保护均未完成，不得宣称完成。

## 7. 已验证证据摘要

最近一次完整 LocalUnit：

```powershell
$hv='G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
$env:DEVECO_SDK_HOME='G:\DevEco Studio 26\DevEco Studio\sdk'
& $hv test --no-daemon --stacktrace
```

结果：`BUILD SUCCESSFUL`，无测试失败；覆盖解析器、签名解释、RSSI、过滤、Compare、Catalog 合并、设置、Wi-Fi 状态机、退避、缓存/fresh、倒计时和 UI 状态映射。

最近一次构建：

```powershell
& $hv assembleHap --no-daemon --stacktrace
```

结果：`BUILD SUCCESSFUL`；HAP 为 `entry/build/default/outputs/default/entry-default-signed.hap`。

最近已取得的 API26 真机证据：

- HAP 安装、Ability 启动、进程 FOREGROUND、BLE 持续观测、无崩溃。
- Wi-Fi 立即重试收到状态回调 1、49 条 AP，BLE 同时持续观测。
- Settings 显示 Wi-Fi `ready`、最近成功、动态下一次尝试倒计时。
- 浅色/深色主题截图显示背景、系统栏和材质同步变化，之后恢复跟随系统。
- Reports 从 RDB reload 后显示 `259/156/136` 三个 sit 计数，Compare 和 ShareKit 可用。
- 高密度雷达截图显示真实点位、RSSI/频率标签和标签避让。

这些证据只覆盖当时安装的 HAP 和对应场景，不能自动外推到尚未安装验证的新改动，也不能把 U30 成功外推成普通路由器长期通过。

## 8. 下一阶段执行顺序

设备已经恢复到新端口后，先使用 `192.168.0.36:40835` 重新确认连接，再按以下顺序推进：

1. **设备和最新 HAP**：`list targets -v`、型号/API、安装最新 HAP、冷启动、`pidof`、`aa dump -l`、HiLog。
2. **暂停显示闭环**：进入 Live，记录显示设备/观测数量；点击暂停；确认 BLE/Wi-Fi 日志仍增长而可见快照不变；恢复后确认列表刷新。
3. **Wi-Fi 主验收**：普通路由器、位置开启，记录状态回调原值、请求次数、结果数、fresh、`nextAttemptAt`、SSID/BSSID/RSSI/频率字段；连续至少 5 分钟。
4. **Wi-Fi 失败矩阵**：位置关闭、Wi-Fi 关闭、权限拒绝后重新授权、系统节流、手动立即重试；每种情况确认 BLE 仍工作。
5. **生命周期**：页面销毁重进、前后台切换、后台开关、停止/恢复订阅；记录资源解绑、扫描次数、观测连续性和功耗/内存。
6. **schema 3 迁移**：准备可安全恢复的旧数据库场景，验证旧表缺 `device_keys` 时幂等迁移，确认设置、签名、日志和 sit 不被误删。
7. **Reports/位置/导出**：位置开启/关闭、真实 Path、Debrief/Compare、CSV/JSONL/GPX/KML/WiGLE 内容和隐私掩码；确认 ShareKit 外发样本；公共文件夹能力只能在 API26 官方能力或真机 Picker 证据确认后实现。
8. **Catalog**：只在用户明确点击时测试网络成功/失败；失败必须保留旧目录，用户签名不能丢失。
9. **详情和视觉**：点位坐标命中、悬浮预览靠近点位、二次点击才开 Sheet、默认半屏；手机竖屏、MatePad 竖屏、横屏、深浅主题和底部安全区截图回归。
10. **鸿蒙增强**：最后再做后台长时、通知真实内容、卡片、流转、子窗口、生物识别；每项先验证真实系统能力再改状态。

## 9. 真机调试命令模板

```powershell
$HDC='G:\DevEco Studio 26\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$TARGET='192.168.0.36:40835'
$BUNDLE='com.dlzz.airwavefootprints'

& $HDC list targets -v
& $HDC -t $TARGET shell param get const.product.model
& $HDC -t $TARGET shell param get const.ohos.apiversion
& $HDC -t $TARGET install -r 'entry/build/default/outputs/default/entry-default-signed.hap'
& $HDC -t $TARGET shell aa force-stop $BUNDLE
& $HDC -t $TARGET shell aa start -a EntryAbility -b $BUNDLE -m entry
& $HDC -t $TARGET shell pidof $BUNDLE
& $HDC -t $TARGET shell aa dump -l
& $HDC -t $TARGET shell hilog -T wwssadad
& $HDC -t $TARGET shell uitest dumpLayout -p /data/local/tmp/fieldwatch-layout.json
& $HDC -t $TARGET shell uitest screenCap -p /data/local/tmp/fieldwatch-screen.png
```

如果 target 消失，先执行：

```powershell
Test-NetConnection 192.168.0.36 -Port 40835
& $HDC tconn 192.168.0.36:40835
& $HDC list targets -v
```

UI 自动化坐标使用 `dumpLayout` 和截图的物理像素坐标；不要凭屏幕比例猜坐标。设备锁屏可能导致 `aa start` 返回 `10106102`，先解锁再继续。

## 10. 实现方法和禁止事项

### 架构

- domain 不导入 HarmonyOS 系统包；平台能力只通过 radio/data/application 适配进入。
- 优先复用 `ngf_framework` 已公开的 settings、RDB、logger、permission、theme、device adaptation、system share、background task、notification 和 i18n facade。
- 不在业务层手写通用 Dialog、Toast、Logger、哈希、系统 Intent、标题栏或平行基础设施。
- 不修改 `ngf_framework` 承载 Fieldwatch 专属业务；只有确认能力对多个 App 通用时才考虑框架改动。

### ArkTS/UI

- 任何 `.ets` 修改前读取 ArkTS、ArkUI、类型规则；禁止新增 `any`、`unknown`、动态属性访问、未类型化对象和硬编码用户可见文案。
- `ForEach` 使用稳定 key；`aboutToAppear`/`aboutToDisappear` 对称管理订阅、定时器、Canvas 动画和扫描生命周期。
- 页面文本进入 `base` 和 `en_US` 资源，使用 `resolveResourceString`；图标优先 `sys.symbol`，设备类型使用现有可着色 SVG。
- `HdsNavigation`/`HdsTabs` 必须考虑动态安全区。顶部状态栏和底部操作栏不能覆盖雷达点击层或标签；标题栏保持隐藏。
- 雷达点位必须由真实 `Sighting` 计算：稳定 key 决定稳定角度，RSSI 决定距离/半径；空数据不生成点，暂停只冻结显示快照，不停止扫描。
- 详情交互必须维持“两级”：点位命中 -> 附近浮窗；再次点击浮窗 -> MEDIUM Sheet；不要单击点位直接打开 Sheet。

### Wi-Fi/数据

- 注册状态回调后再调用 `startScan()`，只有状态 1 才调用 `getScanInfoList()`。
- 同时最多一个主动请求；未到 `nextAttemptAt` 不调用系统 API；失败按 8/16/32/45 秒退避；空结果不覆盖已有缓存。
- 只有成功回调读取的结果 `fresh=true`；缓存显示必须明确标记；BSSID 为空的结果丢弃并记录计数。
- 保留原始广播/IE 在本地；隐私模式只影响显示和外发副本，不改原始日志。
- 任何网络调用必须是用户主动触发 Catalog 更新；禁止后台联网、默认上传和账号体系。

### 验证和文档

- 构建成功不等于功能完成；自动点击成功不等于业务效果完成；系统 facade 返回成功不等于系统 UI/通知真实出现。
- 每个批次记录：源码文件、技能、命令、结果、失败原因、真机日志、控件树、截图和未验证边界。
- 修改后先做静态复核；涉及测试时运行 LocalUnit；涉及真机功能时用最新 HAP 安装后再采证。
- 每个批次同步：迁移任务计划、能力映射、验收矩阵、功能完整清单和 `.agent-state/fieldwatch-migration.local.md`。
- 重复同一失败且没有新证据/新代码/新根因假设最多三次，之后标记阻塞并等待外部条件，不要空转。

## 11. 接手后的第一条工作记录

开始工作时先在评论/检查点中写明：

1. 当前目标和本轮范围。
2. 实际读取的规则和适用的 active 项目规则。
3. 当前 `git status`，不回滚已有修改。
4. 当前 HDC target 是否为 `192.168.0.36:40835` Connected。
5. 本轮修改文件和验收条件。
6. 运行前/构建前/真机前的风险和未确认项。

然后从“最新 HAP 安装启动 + 暂停显示闭环 + 普通路由器 Wi-Fi 5 分钟矩阵”开始，不要重新实现已经有 LocalUnit 和真机证据的功能。完成一批后先更新文档和 `.agent-state`，再进入下一批。
