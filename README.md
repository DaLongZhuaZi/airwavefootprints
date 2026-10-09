# 电波足迹 / Airwave Footprints

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![HarmonyOS SDK](https://img.shields.io/badge/HarmonyOS_SDK-26.0.0_(API_26)-blue.svg)](https://developer.harmonyos.com/)
[![Language](https://img.shields.io/badge/Language-ArkTS-orange.svg)]()

**🌐 语言 / Language:** 中文 | [English](README.en.md)

---

## 这是什么

电波足迹是一款 **HarmonyOS 被动无线电观测工具**：只接收附近设备主动广播的内容，
把「谁在广播、叫什么、属于哪一类」显示出来，供现场排查、设备自查和学习研究使用。

它基于本仓库内的 NGF（Neon Genesis Framework）开发：`entry/` 是应用，`ngf_framework/` 是框架。

- **版本**：1.0.0（versionCode 1000000）
- **包名**：`com.dlzz.airwavefootprints`
- **目标平台**：HarmonyOS 6.0 / API 26

---

## 设计底线

这四条不是宣传语，是代码里真实执行的约束：

| 底线 | 落地方式 |
|---|---|
| **只接收，不连接** | 只监听广播；不配对、不注入、不发送探测帧。BLE / 星闪 / Wi-Fi 三条扫描链路均为被动模式。 |
| **严格离线** | 应用无任何后台网络行为。只有你在「特征库 → 更多 → 更新内置目录」里主动点击时才会访问网络。 |
| **数据只在本机** | 观测、关注列表、自定义特征、设置全部存在应用沙箱内；卸载即删除，我们没有副本。 |
| **只申请两项权限** | 「设备发现和连接」与「位置」。位置仅在你打开「记录手机听到设备的位置」后使用，不做后台定位。 |

Wi-Fi 扫描由系统自动授予，不需要你操作。

---

## 功能

### 五个标签页

| 标签 | 内容 |
|---|---|
| **实时** | 雷达视图 + 强度 / 时间线 / 信号轨迹 / 分类四种列表视图；暂停显示（不等于停止扫描）；进入设备详情、Hunt。 |
| **筛选** | 预设、信号种类、与你同行、新出现的、长时间在附近、分类与精细筛选；AND / OR 逻辑；保存与删除预设。 |
| **特征库** | 浏览、搜索、编辑签名目录；从观测设备反推创建特征；导入导出；更新内置目录。 |
| **记录** | 命名观测时段（Sit）、轨迹、时段报告、导出（含 AI 导出）、设备对比、日志。 |
| **设置** | 扫描、权限、实时雷达显示、显示、位置与隐私、通知与语音、关注列表、数据、关于应用。 |

### 子页面

- **设备详情** —— 无线电事实、品牌与类别推断、匹配到的特征、观测统计与趋势、位置标记、备注与自定义名称。
- **特征编辑器** —— 身份 / 匹配 / 颜色 / 规则 / 解码字段五组配置。
- **Hunt** —— 单目标追踪，带蜂鸣与语音反馈。

### 首次启动引导

首次启动依次说明：应用用途 → 不需要任何权限也能用的功能 → 逐条解释两项权限的用途。
**引导完成前不申请任何权限。** 之后可在「设置 → 数据」里重看。

---

## 权限

| 权限 | 用途 | 拒绝后 |
|---|---|---|
| **设备发现和连接**<br>`ACCESS_BLUETOOTH` + `ACCESS_NEARLINK` | 接收附近 BLE 与星闪设备的广播（耳机、手环、追踪器、信标等）。只读广播内容，不建立连接、不配对。 | 实时页显示受限卡片，其余功能不受影响。 |
| **位置**<br>`APPROXIMATELY_LOCATION` | 只在你打开「记录手机听到设备的位置」后使用，给观测打位置标记并绘制本机轨迹。不做后台定位。 | 观测照常进行，只是不带位置。 |

应用商店要求「请求前先说明用途」，因此权限说明写在启动引导与设置页里，而不是直接弹系统框。

---

## 内置特征目录

- `entry/src/main/resources/rawfile/fieldwatch-signatures-v2.json` —— **304 条特征**，`catalogVersion: 89`
- 厂商前缀（OUI）来自 IEEE 公开注册表，离线打包
- 目录随应用离线提供，可导出查看，也可用你自己的规则覆盖

---

## 工程结构

```
entry/src/main/ets/
├── entryability/          EntryAbility（主入口）+ MultitonEntryAbility
├── pages/
│   ├── fieldwatch/        应用页面
│   │   ├── FieldwatchPage.ets                五个标签页 + 实时雷达（主体）
│   │   ├── FieldwatchDeviceDetailPage.ets    设备详情
│   │   ├── FieldwatchSignatureEditorPage.ets 特征编辑器
│   │   ├── FieldwatchSignaturesPage.ets      特征库
│   │   ├── FieldwatchHuntPage.ets            单目标追踪
│   │   └── FieldwatchOnboardingPage.ets      首次启动引导
│   └── ngf/               NGF 框架演示与验证页
└── fieldwatch/
    ├── application/       应用状态与用例编排
    ├── data/              目录 / 观测 / 设置三个仓储
    ├── domain/            模型、解析、推断、过滤、候选、导出、厂商库
    │   └── signatures/    特征目录、匹配引擎、模型
    ├── platform/          文件网关、PDF、Hunt 反馈、关注告警
    ├── radio/             BLE / 星闪 / Wi-Fi 扫描与协调器
    └── ui/                调色板、按钮、芯片、雷达聚合、信号行等
```

---

## 构建与运行

用 DevEco Studio 打开仓库根目录即可。命令行：

```powershell
# 设置 SDK 根目录（换成你机器上的实际路径）
$env:DEVECO_SDK_HOME='<DevEco Studio>/sdk'

# 调试包
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' assembleHap --no-daemon

# 发布包
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=release --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`

> 本机实测路径与设备 target 记录在 `.local-rules/build-commands.local.md` 与
> `.local-rules/device-hdc.local.md`，不要把机器相关事实写进本文件。

---

## 测试

```powershell
& '<DevEco Studio>/tools/hvigor/bin/hvigorw.bat' test --no-daemon
```

测试位于 `entry/src/test/`，共 20 个用例文件；其中 `Fieldwatch*` 覆盖领域逻辑：
解析、过滤、候选、特征匹配、厂商库、关注告警、隐私导出、设置备份、权限、主题等。

> ⚠️ **重要**：`hvigorw test` 在有用例失败时**仍然输出 `BUILD SUCCESSFUL`**。
> 必须同时断言 `> hvigor ERROR: Error in ` 的行数为 0，否则会漏掉失败。

---

## 已知边界

- 信号强度、厂商推断、特征匹配与设备解释都是**基于广播内容的推测**，
  不构成对设备身份、归属或意图的确认，不应作为取证或决策的唯一依据。
- 内置特征目录整理自公开资料，覆盖面有限；**匹配不到是正常结果**，不代表设备异常。
- 可用性依赖系统是否向应用暴露广播内容，不同机型与系统版本表现可能不同。

---

## 相关文档

| 文档 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 本仓库的代理工作规范（架构分层、ArkTS 硬性规则、交付流程） |
| [.rules/README.md](.rules/README.md) | 技能规则索引 |
| [docs/Fieldwatch功能完整清单.md](docs/Fieldwatch功能完整清单.md) | 功能基线与验收清单 |
| [docs/Fieldwatch鸿蒙能力映射.md](docs/Fieldwatch鸿蒙能力映射.md) | Android → HarmonyOS 能力映射 |
| [docs/Fieldwatch鸿蒙验收矩阵.md](docs/Fieldwatch鸿蒙验收矩阵.md) | 验收矩阵 |

---

## License

[MIT](LICENSE)
