# NGF 项目专属规则登记册

本登记册只记录无法自然归入根 `AGENTS.md`、`.rules/` 或 `.local-rules/` 的当前工作区规则。所有 `active` 条目都必须在任务执行中遵守；`candidate` 条目仅用于后续验证，不能约束实现。

## Active Rules

### PR-001 项目专属规则的自动治理与执行

**状态**：active
**范围**：当前 NGF 工作区，以及后续在本仓库内创建或长期维护的 NGF 应用模块。
**指令**：当用户表达持续适用的非敏感偏好，或任务产生有充分证据支持的项目/App 稳定模式、Harness 改进时，Agent 必须按 `.rules/skill-project-rule-governance.md` 提炼并写入正确层级；执行源码任务前必须读取并遵守所有 `active` 项目规则和不冲突的本地偏好。一次性判断保持为 `candidate` 或任务状态，除非用户提出相反要求。
**来源**：用户关于“使用 NGF 创建新 App 时，Agent 应精心收集、提炼并遵守项目专属规则、Harness 和个人偏好”的明确长期指令。
**证据**：根 `AGENTS.md` 的 `1.3`、`5.4`、`5.6.3` 与 `.rules/skill-project-rule-governance.md` 已建立相应读取、提炼、冲突处理和验证流程。
**验证**：每次中等及以上任务在评估、实现、复核和交付前检查有效规则；交付时说明本次新增、修订、保留为候选或未沉淀的结论。
**更新时间**：2026-08-13

### PR-002 NGF 项目的 CI 云端构建约定

**状态**：active
**范围**：NGF 仓库的 GitHub Actions 云端构建、镜像消费、自动发布；以及在本仓库内新建/维护应用模块时的构建交付。
**指令**：
1. NGF 消费镜像 `ghcr.io/dalongzhuazi/harmonyos-ci:api26`（command-line-tools 26.0.0.461，HarmonyOS 26.0.0 / API 26 Beta1）；镜像构建/维护统一在 [harmonyos-ci](https://github.com/DaLongZhuaZi/harmonyos-ci) 仓库，不要在本仓库重新引入 docker-image 构建。
2. 涉及 CI、云端构建、镜像、automation、自动发布、免 DevEco 构建时，先读 `.rules/skill-ci-build.md`（通用技能）+ `docs/CI_Guide.md`/`docs/CI_Guide.en.md`（本项目双语完整步骤）。
3. 消费方只需维护 `.github/workflows/build.yml`（构建+自动滚动 nightly Release）、`.github/workflows/sign-and-release.yml`（tag 签名发布，未配 Secrets 时自动跳过）、`.github/scripts/strip_signing.py`（剥离本机签名配置产出未签名 HAP）。
4. 签名材料（证书/密钥/口令）只走 repository secrets，绝不入库；`.gitignore` 已拦截证书类文件。
**来源**：用户明确要求将 HarmonyOS CI 云端构建纳入本项目 agent 规则库、并同步 NGF 项目。
**证据**：`.github/workflows/build.yml`、`.github/workflows/sign-and-release.yml`、`.github/scripts/strip_signing.py`、`docs/CI_Guide.md`；镜像 `ghcr.io/dalongzhuazi/harmonyos-ci:api26` 已云端验证构建通过。
**验证**：交付前回看本条；涉及 CI/构建/镜像时实际引用 `.rules/skill-ci-build.md` 与 `docs/CI_Guide.md`；证书类文件不进入工作区提交。
**更新时间**：2026-08-17

### PR-003 NGF 自动化测试与回归测试 harness 约定

**状态**：active
**范围**：NGF 仓库的单元测试、集成测试与回归测试；新增测试用例、搭建测试环境、维护测试目录。
**指令**：
1. 测试框架统一用 `@ohos/hypium`（配套 `@ohos/hamock`），依赖已在根 `oh-package.json5` 的 devDependencies 就绪（1.0.25 / 1.0.0）。
2. 目录结构：本地单元测试放 `entry/src/test/`（`List.test.ets` 为聚合入口 `export default function testsuite()`）；设备集成测试放 `entry/src/ohosTest/`（含 `module.json5` + `OpenHarmonyTestRunner`）。
3. 涉及测试时先读 `.rules/skill-automation-test.md`；参考已落地案例 `F:\DevEcoStudioProject\Coder` 与 `F:\DevEcoStudioProject\manxia` 的 `entry/src/test` / `entry/src/ohosTest`。
4. 在 IDE 外搭建/补齐测试环境时，从下载 devecotesting-hypium 工具包开始（API 26 用 26.0.0.400、API 23/24 用 6.1.0.210），注意官方直链带时效签名（约 2 小时）。
5. 回归测试围绕「已稳定契约」写断言，引用主代码路径 `../main/ets/...`，改动后重跑确保不破坏既有行为。
**来源**：用户要求参考 Coder/manxia 的 hypium 实际案例，在 NGF 建立自动化测试、回归测试流程与 harness。
**证据**：`@ohos/hypium`/`@ohos/hamock` 已在 oh-package.json5；Coder（30+ LocalUnit + Ability.test）、manxia（LocalUnit + Legado 一致性/回归测试）已验证。
**验证**：交付前回看本条；新增测试按 §4/§5 结构落地；测试用例 import `@ohos/hypium` 且入口正确聚合。
**更新时间**：2026-08-18

### PR-004 API26 组件级沉浸光感与 HdsColorPicker 接入约定

**状态**：active
**范围**：NGF 仓库 HDS 展示页（`pages/ngf/HdsNavigationOfficialShowcasePage.ets`）及后续新建/改造 HDS 页面时，涉及 API26 组件级沉浸光感、`HdsColorPicker`、`ImmersiveMaterial`、`hdsEffect` 点光/按压阴影的接入。
**指令**：
1. 能力分层互斥：使用 `.systemMaterial(ImmersiveMaterial{interactive:true, lightEffect})` 接管按压反馈后，不要再叠加 `.visualEffect(hdsEffect 链)`，两者会重复渲染按压反馈，导致性能下降且视觉异常。
2. `HdsColorPicker` 选中颜色必须存到 `@State` 变量，再由该变量驱动 `VisualEffect` 重建；颜色注入通过修改 `NGFHdsPointLightPresetSpec.color` 后调用 `basePreset.buildVisualEffect()` 走工厂方法，不要在页面层直接 `new hdsEffect.HdsEffectBuilder()`。
3. `ngfVisualEffectsFacade.buildImmersiveMaterialForTabs()` 返回 `uiMaterial.ImmersiveMaterial | undefined`，调用方需做空值兼容（返回 `undefined` 表示设备/策略不支持）。
4. 三档 `MaterialLevel`（GENTLE/SMOOTH/EXQUISITE）的视觉差异由 `SystemMaterialParams.materialLevel` 驱动，系统材质引擎按设备算力自动适配模糊/高光/阴影，不需要手写 `linearGradient` + `shadow` + `border` 模拟材质层次。
5. `NGFHdsPointLightPresetSpec` 已纳入 `ngf_framework` 的 `uiShell/index.ets` barrel 导出，页面层可 `import { NGFHdsPointLightPresetSpec } from 'ngf_framework'`。
**来源**：用户要求针对新增的 API26 优化内容完成文档与技能修改。
**证据**：`entry/src/main/ets/pages/ngf/HdsNavigationOfficialShowcasePage.ets` 的 `buildColorPickerSection`/`buildCustomPointLightVisualEffect`/`buildMaterialPanelContent`；`ngf_framework/src/main/ets/uiShell/index.ets` 新增 `NGFHdsPointLightPresetSpec` 导出；`hvigorw assembleHap` → BUILD SUCCESSFUL。
**验证**：交付前回看本条；HDS 页面涉及 API26 光感/材质/颜色选择器时，实际引用 `.rules/skill-hds-page-design.md` §8 与 `.rules/skill-arkui-knowledge.md` §10。
**更新时间**：2026-08-28

### PR-005 电波足迹鸿蒙原生能力优先

**状态**：active
**范围**：`entry` 下 Fieldwatch 应用模块的后续功能设计、迁移和体验优化。
**指令**：在保持 Fieldwatch 离线、被动观测和隐私边界的前提下，后续功能应优先采用 HarmonyOS 官方能力与 NGF 已有门面，充分利用系统级权限、后台任务、通知、位置、设备感知、窗口/多端流转、文件分享和 HDS/ArkUI 交互能力；跨平台业务逻辑继续保持可替换、低耦合，不把鸿蒙特性硬编码进领域规则。
**来源**：用户明确要求将 Fieldwatch 重新实现为鸿蒙平台版本，并尽可能结合更多鸿蒙特性提升可用性。
**证据**：当前 `entry/src/main/module.json5` 已声明蓝牙、手势、运动、后台运行、通知、生物识别、加速度计和位置权限；`ngf_framework` 已提供 `hardware`、`systemTasks`、`deviceAwareness`、`interconnect`、`uiShell`、`data` 等对应能力模块。
**验证**：新增或迁移功能时，交付前说明使用的 HarmonyOS/NGF 能力、权限与生命周期边界，并确认领域层仍可通过接口替换平台实现；涉及官方 API 时先核对 API 26 官方声明与权限要求。
**更新时间**：2026-10-04

### PR-006 应用内自动化验收的时序、模态与坐标规则

**状态**：active
**范围**：本仓库 Fieldwatch 页面与系统文件选择器/分享面板的 uitest 自动验收（模拟点击、截图判定、控件树 dump）。
**指令**：
1. **不要用点击后立即截图的结果判定失败**：芯片选中态高亮、系统选择器窗口都可能延迟数秒到十几秒才出现；**系统文件选择器实测可延迟到约 70 秒**（2026-10-12 受控实验：点击 14:07:14 → 14:08:2x 才截到面板），因此保存类流程要么等足 ≥75 秒，要么用 `hilog` 观察 `filePicker` 服务的拉起与销毁（`InitSourceTask` / `FilePickerUIExtAbility onDestroy finish`）来判定状态，不要靠短等待截图下结论。
2. **模态 AlertDialog 会吞掉落在其外的点击**：对话框未关闭前不要点击页面控件，否则点击静默丢弃，看起来像按钮坏了。
3. **系统文件选择器不出现在 uitest dumpLayout 的控件树里**（分栏页面下 dump 甚至只返回状态栏）；定位控件坐标要用截图加像素聚类（例如按强调色绿色 3DFF9A 找按钮），不要依赖 dump。**左侧导航的可点区域只是图标加文字（x≈30–200）**，胶囊视觉范围更宽，点 x≈243 的空白处不会切页；应点标签文字（x≈150）。
4. **坐标必须从当前截图实测**：卡片高度会随内容与选中态变化（同一按钮在不同滚动/选中状态下 y 可相差数百像素），禁止沿用上一屏坐标；**分栏模式下控件会比全屏更窄，全屏坐标会落到控件之外**；**模态面板（分享面板 / 文件选择器 / AlertDialog）的开合会改变页面布局**（实测位移约 60 px），面板前后的坐标不可复用 —— 每次点击前用最新截图重测；面板自身的关闭按钮位置也随其内容高度变化（分享面板的 ✕ 在面板底部右侧，不是屏幕右上角）。
5. **高负载页面（如 Live 扫描列表每秒按 RSSI 重排）点击后要等 15–30 秒再判定**，否则会把延迟当成「按钮失效」。
6. **性能类验收要用设备自带 SmartPerf 采样并配对照基线**：`SP_daemon -N <n> -PKG <bundle> -f -OUT <csv>`（1 Hz，只统计应用实际产帧，静态页面为 0），采样窗口必须覆盖滑动过程，并另采一条简单页面基线；单看绝对帧率会把设备/注入管线限制误判成列表性能问题。
**来源**：本轮真机自动验收中反复出现并被逐一定位（用户要求仅在 app 内操作的验证流程自动完成编译安装与验收）。
**证据**：2026-10-11 自动验收：① 点击分享 JSONL 后 2 秒截图仍显示旧选中态，稍后截图已正确切换；② 保存到文件点击后约 10 到 15 秒选择器才出现（7 秒截图判定为未打开属误判）；③ 取消选择器弹出的模态对话框吞掉了随后的芯片点击；④ 该页 dumpLayout 返回空壳，改用像素聚类定位到保存按钮 (2010,623)/(2010,1230) 后成功。
**验证**：执行应用内自动验收时按上述六条操作；交付说明中区分程序化检测确认与仅截图目视。
**更新时间**：2026-10-12

### PR-007 本地读取失败时禁止用内置数据覆盖用户持久化文件

**状态**：active
**范围**：Fieldwatch（及后续 App）所有「内置数据 + 用户沙箱数据」合并并落盘的启动流程，尤其是特征目录、设置、关注列表等用户可编辑内容。
**指令**：启动或任何后台流程在判定「本地数据不存在 / 为空」前，必须先区分三种情况：① 文件确实不存在；② 文件存在但读不出来（IO 失败、沙箱基础目录未就绪导致相对路径解析失败、大文件单次读被截断）；③ 文件存在且解析失败。**只有 ① 才允许写入内置默认数据**；②③ 必须保留原文件、拒绝落盘覆盖，并记录 error 级日志。相应地，纯文本读取必须分块循环读到 EOF，不得假定单次 `readSync` 读满。
**来源**：2026-10-12 真机复现的用户数据丢失缺陷（用户自定义签名在重启后被静默销毁）。
**证据**：`FileUtils.readText` 原先 `readSync` 一次即解码；`FieldwatchCatalogRepository.loadSaved` 原先把「读空」与「无文件」都当作无本地目录，`FieldwatchApplication.loadBundledCatalog` 遂在 `stockVersion > savedVersion` 时用内置目录落盘。真机两次复现：创建自定义签名后重启，沙箱 `signatures.json` 由 2258417 字节回落为 2258081 字节、用户签名条目归零。修复（分块读 + `exists()` 区分 + 损坏时拒绝落盘 + 页面兜底重读）后同一场景重启，文件字节数与 mtime 均不变、界面 612/612 且用户签名在列。
**验证**：涉及持久化的改动，交付前必须复现「写入用户数据 → 冷启动 → 数据仍在」，并确认启动路径未重写该文件（比对大小与 mtime）。
**更新时间**：2026-10-12

## Candidate Rules

当前没有待验证的候选规则。

## Open Decisions

当前没有需要在实现前决定的项目级事项。

## 条目格式

### PR-001 规则名称

**状态**：active / candidate / deprecated
**范围**：模块、页面、功能或交付场景
**指令**：满足什么条件时必须做什么，以及不适用的边界。
**来源**：用户长期指令 / 配置 / 已验证源码 / 官方文档。
**证据**：精确文件、命令输出或重复验证模式。
**验证**：交付时如何检查遵守情况。
**更新时间**：YYYY-MM-DD
### PR-008 外发内容必须整体脱敏，不能只掩展示字段

**状态**：active
**范围**：Fieldwatch 所有对外输出（导出文件、分享面板、报告文本、剪贴板）中承载设备标识的字段。
**指令**：隐私模式开启时，**任何内嵌设备地址的字段都必须与 `address` 同策略脱敏**——典型是 `key`（形如 `ble:<MAC>` / `wifi:<BSSID>`）。脱敏测试必须断言「输出中不存在完整 MAC」这类**否定式不变量**（正则 `[0-9A-F]{2}(:[0-9A-F]{2}){5}`），而不是只断言「存在 `**:**:**`」；后者在新增字段泄漏时不会失败。
**来源**：2026-10-12 真机导出样本发现隐私模式下 `key` 列仍为完整 MAC。
**证据**：修复前 `fieldwatch-log-2026-10-12-06-37-51.jsonl` 行为 `{"key":"ble:F0:07:1C:43:04:07","address":"F0:07:1C:**:**:**"}`；修复后 `fieldwatch-log-2026-10-12-06-55-36.jsonl` 114 行全部为 `"key":"ble:2C:13:7C:**:**:**"`，完整 MAC 残留 0 行。
**验证**：`hvigorw test` 新增用例覆盖 CSV 与 JSONL 的否定式断言；改动导出字段时先跑该用例。注意 `hvigorw test` 断言失败**不会**让退出码非零，必须检查日志里的 `> hvigor ERROR: Error in` 行。
**更新时间**：2026-10-12
### PR-009 目录/设置等「整份文档」落盘必须写全量，禁止只写子集

**状态**：active
**范围**：Fieldwatch 及后续 App 中所有把「内存中的完整集合」序列化落盘的路径（特征目录、设置、关注列表、会话列表）。
**指令**：落盘时**必须写内存中的完整集合**；任何「只写用户新增部分」的写法都必须同时保证「下次启动能把另一部分重新合并回来」，否则视为缺陷。判定合并能否补回时，**不能只看版本号或长度**：要显式检查「另一部分是否真的还在」，例如「保存的目录里是否含内置项」。
**来源**：2026-10-12 真机复现的内置目录丢失（候选特征「添加到目录」后 611 → 4）。
**证据**：`addCandidateToCatalog` 原传 `signatures.filter(!builtIn)` → 文件 2258081 B → 1656 B，只剩 4 条用户签名；因文件 `catalogVersion` 仍为 stock 版本、且 `ensureCatalogLoaded` 只看长度，内置目录在重启后也无法回来。修复后同一操作：文件 2259968 B、内置 611 / 用户 5、界面 616，重启持久。
**验证**：改动任何落盘路径后，必须复现「写入 → 冷启动 → 内容仍在且完整」；对「部分写入」的怀疑项，用「文件条数 / 内置项计数 / 界面总数」三者对照。
**更新时间**：2026-10-12
### PR-010 真机自动化交互全面失效时，先排查设备状态

**状态**：active
**范围**：Fieldwatch 及任何真机 UI 自动化验收流程。
**指令**：当一批注入点击/滑动**突然集体无响应**（而不是个别点击失败）时，先按顺序排查：① 设备是否进入低电量应急模式或省电策略；② 目标应用进程是否还活着（`hdc shell pidof <bundle>`）；③ 是否有残留模态对话框挡住页面；④ 再怀疑坐标或控件本身。**不要在设备侧原因未排除前，把现象定性为「应用控件不响应」并据此记录缺陷。**
**来源**：2026-10-12 真机复现：KML 芯片卡在按下态、保存到文件无反应，实为设备低电量应急模式杀掉了应用。
**证据**：应急模式界面截图（仅电话/信息 + 「可能因电量过低导致直接关机」）+ `pidof` 为空；代码核对确认格式芯片无 disabled 逻辑。
**验证**：设备充电、应用可正常启动后，用同一组坐标复验同一操作；若此时正常，则先前现象按设备侧原因归档。
**更新时间**：2026-10-12

### PR-011 ArkUI `ForEach` 的 key 必须包含所有会变化的渲染字段

**状态**：active
**范围**：`entry` 层所有 `ForEach` / `LazyForEach` 列表（实时列表、找东西认领列表与「我的东西」、特征库、记录、会话列表）。
**指令**：key **不能只写身份字段**（id、地址、key）。凡是行内会变化的内容（计数、连接状态、「已认领」徽标、「上次见到」时间、稳定性提示）都必须一并编进 key；否则 ArkUI 会判定「同一个 key = 同一行」，**复用旧行、不重绘**，界面停在旧值。
**来源**：同一类缺陷在本项目已出现两次 —— ① 实时列表「会话结束计数不刷新」（key 由 `item.id` 改为 `item.id + ':' + item.name + ':' + item.radioCount`）；② 找东西页删掉档案后，已配对行仍显示「已认领」（key 由 `source:key` 改为再带 `alreadyClaimed` 与 `connected`），同时「我的东西」行 key 补上 `lastSeenAt` 与 `addressStable`。
**证据**：2026-10-16 真机：点「这不是我的」移除档案后，提示行显示「已移除「YUANDAO OriG in」」、直读设备 RDB 也确认只剩 2 条档案，但该行徽标持续 2 分钟以上仍为「已认领」；把状态字段编进 key 后重新装包，同一行立即显示「认领」。
**验证**：任何「数据变了但界面没变」的怀疑，先看对应 `ForEach` 的 key 是否覆盖了变化的字段；改动列表行渲染内容时，同步检查 key。
**更新时间**：2026-10-16

### PR-012 资源键完整性必须双向核对（字面量 / 动态前缀 / module.json5）

**状态**：active
**范围**：`entry/src/main/resources/{base,en_US}/element/string.json` 与所有引用它们的 `.ets`、`module.json5`。
**指令**：改动或新增资源键后，必须双向核对：① 代码里引用但资源缺失（会显示空白或抛异常）；② 资源存在但没人引用（死资源，说明功能没接上或有拼写错误）。核对时**三种引用方式都要算**：`$r('app.string.X')` 字面量、`'app.string.X_' + 后缀` 动态前缀（取资源时要按前缀展开）、以及 `module.json5` 里的 `$string:X`（权限 reason、Ability label/description —— 这类**只有 base 有、en_US 没有**时，英文用户会看到中文或空白）。两语言文件键数应当相等。
**来源**：2026-10-16 对全仓 1168 个字面量键 + 6 个动态前缀做了一次完整核对。
**证据**：核对出并修掉 4 处：① `fieldwatch_restricted_enable_nl`（星闪权限按钮文案）只有中文，英文用户会看到空白；② `fieldwatch_find_shake_confirmed`「就是这台」是死资源 —— 「晃一晃」确认后只显示一个无字勾，说明这条文案当初就没接上，现已接进确认行；③④ `bluetooth_scan_reason`（**权限弹窗给用户看的理由**）与 `MultitonEntryAbility_label/_desc` 只有中文（由 `module.json5` 引用，纯 `.ets` 扫描看不到）。修完两语言键数均为 2416。
**验证**：任何新增/改名资源键的改动后，跑一次「引用集（字面量 ∪ 按前缀展开 ∪ module.json5 的 $string） vs 两语言键集」的差集检查，两侧都应为空；`find/own` 前缀下不允许存在未被引用的键。
**更新时间**：2026-10-16

### PR-013 `hvigorw test` 不编译 UI 层：UI 改动必须用 `assembleHap` 验证编译

**状态**：active
**范围**：所有 `.ets` 修改，尤其是 `entry/src/main/ets/pages/**` 与 `entry/src/main/ets/fieldwatch/ui/**`。
**指令**：`hvigorw test` 只编译**测试及其依赖图**（主要是 `fieldwatch/domain/**` 等纯逻辑），**不覆盖页面与 UI 组件**。因此 UI 侧的类型错误、悬空引用在 `test` 里看不到。**只要改了 UI 层，就必须跑 `assembleHap` 并检查退出码**，不能拿「测试通过」当作「编译通过」。
**来源**：2026-10-17 删除工具箱内联追踪面板时，`hvigorw test` 报 BUILD SUCCESSFUL，而 `assembleHap` 失败两次（`buildMetricCell` 被反追踪段共用；`drawHuntTrend` 仍有调用点）。
**证据**：同一次改动下 `hvigorw test` ERROR_LINES=0 且 BUILD SUCCESSFUL，`assembleHap` 打印 `Error Message: Property 'drawHuntTrend' does not exist on type 'FieldwatchToolboxPage'` 并 `BUILD FAILED`；更危险的是**失败后 `hdc install` 装的是上一次构建的旧 HAP**，界面看起来「没变化」，容易被误判成逻辑问题。
**验证**：改动 UI 后固定执行：`hvigorw assembleHap --no-daemon`，确认 `BUILD SUCCESSFUL` 与退出码 0，再安装。
**更新时间**：2026-10-17

### PR-014 匹配热路径禁止逐字符拼串与运行期重复归一化

**状态**：active
**范围**：`entry/src/main/ets/fieldwatch/domain/signatures/**` 及其任何「每条扫描观测都会走一遍」的代码路径（`ingestNow`、`matchContext`、`decodeFields`、列表行 builder、雷达几何重建）。
**指令**：
1. 字符级规范化（十六进制 / 大小写 / 前缀比较）**禁止**用 `result += ch.toUpperCase()` 这类逐字符拼接；用查表 + 数组 `join`，并为「已是目标形态」的入参保留零分配快路径。
2. 同一个字段的规范化**每条观测只能算一次**：把结果缓存在 `SignatureMatchContext` 的字段里（`addressHex()` / `manufacturerDataHexNormalized()` / `serviceUuidAliasesAt()` / `serviceDataHexAt()` / `vendorIeHexAt()`），规则侧只读缓存；**规则常量**在 `compile()` 期归一化一次，匹配期不得再调 `signatureHexOnly(rule.text)`。
3. 已知输入不变时不要重算：可复用的结论用「输入指纹」做键（匹配结果用 `matchFingerprint()`，雷达几何用点数 + 缩放 + 量化 RSSI）。指纹必须覆盖**所有参与判定的字段**，否则会出现「结果不更新」。
4. 列表行 builder、雷达几何、`explain()` 这类会被每帧调用的方法，**禁止**在其内部对目录数组做 `find` / `filter`；一律走 `fleetById()` 索引或预计算 `Map`。
5. 高频小写入（观测落库）必须批量：单条多行 `INSERT`，不要逐条 `executeSql`；也**不要**在共享 `ngfRdbManager` 上开显式事务（其他仓库的写入会被卷进同一事务）。
**来源**：2026-10-17 能量录制分析（`docs/性能分析_20261017_Energy_profiler.md`）：主线程 Running 86.5%、App 1.48 核、GC 39.5% 单核、出帧 16.7 fps。
**证据**：hiperf JS 归因显示 `signatureHexOnly` 单函数占 **45.6%** 的已归因 JS CPU，根因是「逐字符 `+=` 拼接」叠加「观测侧归一化按规则数重复计算」；RDB 侧 `H:VerifyPermission` 8.6 万次/44s 对应逐条 `executeSql`。按本条规定改造后（见 `docs/性能优化实施方案_20261017.md`），四轮 `assembleHap` + 安装均通过，安装后粗略读数从 148% 单核降到约 53% 单核。
**验证**：改动了上述任何文件或路径时，交付前自查：① 是否新增了字符级拼串；② 是否在 `hits()` 里对 context 或规则常量重新归一化；③ 是否在 builder 里对目录/观测数组做线性扫描；④ 新增的高频写入是否批量。
**更新时间**：2026-10-17


### PR-016 新增子页必须同时具备横屏右栏分栏与自绘入场/退场动画

**状态**：active
**范围**：`entry/src/main/ets/pages/fieldwatch/` 下所有通过 `pathStack.pushPathByName` 打开的子页，以及 `FieldwatchPage.topRouteUsesSplit()` 白名单。
**指令**：

1. **每个新子页必须在 `topRouteUsesSplit()` 白名单里登记**。漏登记时该页在横屏会整屏铺开，
   而既有详情页是「左列表 + 右详情」，同一个 App 出现两套观感。
2. **打开方法必须同时设 `subPageOpen = true` 再 push**（或走 `openSubPage()`），
   顺序不能反：先立分栏边界再压栈，否则详情会先以全屏出现再被推向右。
3. **子页根节点（`HdsNavDestination`）必须自绘入场/退场动画**，照抄
   `FieldwatchDeviceDetailPage` 的 `enterShift` / `enterAlpha` / `leaving` 三件套：
   - `@State enterShift = 40`、`@State enterAlpha = 0`、`leaving = false`
   - 根节点 `.translate({ x: this.enterShift }).opacity(this.enterAlpha)`
   - `aboutToAppear()` 调 `playEnter()`（240ms FastOutSlowIn → 0 / 1）
   - 返回与 `onBackPressed` 走 `leaveThenClose()`（200ms，**出栈挂在 `onFinish`**）
   - **不要用 `.systemTransition(SLIDE_RIGHT)` 替代**
4. **动画必须加在 `HdsNavDestination` 根节点上**，不能只加在内层内容上。
   退出时 `pop()` 会让 `subPageOpen` 变 false、模式从 Split 翻回 Stack，右栏从约 33% 拉伸到 100%；
   若只有内容淡出，根节点的不透明背景仍在，用户看到的是「一整块实心空白面板在拉伸」。
5. **位移用 vp 不用百分比**：百分比随容器宽度变化，分栏收起时位移量跟着放大，读作「被拉伸」。
6. **作为 Tab 页内容传给子组件的布局开关必须是 `@Prop`**（如 `twoColumn`）。
   普通字段只在首次渲染取值，父组件在「进子页/出子页」时翻转它，子页收不到更新 ——
   横屏分栏时左侧窄栏会一直保持双列，卡片被挤成「信道分/析」这种断行。

**来源**：2026-10-28 用户反馈「刚刚新建的几乎所有页面都缺少正确的横屏分栏设计和相应的动画设计，
必须严格按照已有的特征详情页面进行重新设计」，点名 9 个页面：
新面孔、WiFi 体检、信道分析、设备图鉴、安防扫描、找东西、主动扫描授权、寻踪、反追踪。

**证据**：核查确认 `topRouteUsesSplit()` 当时只登记了 6 个既有路由（详情、特征编辑器、搜寻、
监控名单、反馈），上述 9 个新路由全部不在名单内 —— 横屏下它们整屏铺开而非进入右栏；
同时这 9 个页面用的是 `.systemTransition(SLIDE_RIGHT)`，与参照页的自绘动画不一致。
补齐白名单 + `twoColumn` 改 `@Prop` + 批量套用参照页动画后，真机横屏截图确认：
左侧 Rail + 工具箱单列 + 右侧子页，与既有详情页分栏行为一致。

**验证**：新增或改动子页后，交付前自查：
① 路由名是否已加入 `topRouteUsesSplit()`；
② 打开方法是否先 `subPageOpen = true`；
③ 根节点是否有 `translate` + `opacity` 且 `playEnter()` / `leaveThenClose()` 成对；
④ 是否残留 `.systemTransition`；
⑤ 布局开关是否 `@Prop`。
横屏验证方法：临时在 `aboutToAppear` 插 `window.setPreferredOrientation(LANDSCAPE)`，
打包后截图确认「左栏保留入口 + 右栏显示子页」，验完**必须删除临时代码并重新打包确认**。

**更新时间**：2026-10-28