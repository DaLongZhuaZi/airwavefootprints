# Fieldwatch 鸿蒙能力映射

| Android 能力 | HarmonyOS/NGF 目标 | 当前状态 | 证据或阻塞 |
|---|---|---|---|
| BLE 被动扫描 | `@kit.ConnectivityKit` + `FieldwatchBleScanner` | 部分完成 | API26 真机可持续产生观测；BLE AD 长度/type/payload、Service UUID、Local Name 和 Manufacturer Company ID 的基础解析已通过 LocalUnit；生命周期、生产原始字段样本和完整回归仍待补 |
| Wi-Fi 被动扫描 | `@kit.ConnectivityKit` 的 `wifiManager`：`startScan` / `getScanInfoList` / `wifiScanStateChange` | 适配器、状态机、缓存和退避已实现，普通路由器真机待验 | API26 SDK 声明已确认；LocalUnit 已覆盖权限/Wi-Fi/位置前置、单飞、解绑、异常退避和重试；最新 HAP U30 重试已取得 `wifiScanStateChange=1`、49 条 AP 结果和 BLE 并行证据；Wi-Fi IE TLV 基础结构解析和单测已通过 |
| 设备聚合与过滤 | Fieldwatch domain 层 | 部分完成 | 已有 key 聚合、RSSI、签名/关注/重点目标/fresh/缓存 AND-OR 过滤；LocalUnit 已通过；RSSI 平均/趋势已实现；完整类别和解码字段待补 |
| 设置 | `ngfSettingsStoreFacade` + `ngfThemeManagerFacade` | 部分完成 | 扫描强度、暂停显示、屏幕常亮、位置标记、隐私模式、关注通知、后台扫描、筛选预设、关注列表、应用沙箱备份恢复、Catalog 状态和跟随系统/浅色/深色主题入口已接入；LocalUnit/真机控件已覆盖主要边界；主题视觉、备份跨重启和公共文件能力仍待补 |
| 日志/Named sit | `ngfRdbManager` + `FieldwatchObservationRepository` | 观测日志闭环、sit 存储和设备快照基础接口 | API26 真机重启后恢复 500 条观测；Compare 设备集合纯逻辑已通过 LocalUnit；schema 3 设备快照迁移和 Reports 真机操作仍待验收 |
| 位置 | `ngfLocationManagerFacade` | 部分完成 | 开启位置标记后，观测通过 NGF 位置门面附加手机当前位置；15 秒缓存/单飞保护已实现，权限和位置关闭仍待真机验收 |
| 系统分享 | `ngfSystemShareFacade` | 部分完成 | Reports 已接入 CSV/JSONL/GPX/KML/WiGLE/Debrief 文本分享入口；应用沙箱保存已接入。API26 本地 SDK 未发现可确认的 DocumentSavePicker/公共文件写入声明，公共文件夹另存为保持待验，不能宣称完成 |
| Catalog | `ngfNetworkClient` + `FieldwatchCatalogRepository` | 部分完成 | 内置/本地目录、用户主动 GitHub 更新、stock 替换和失败保留旧目录已实现；stock 替换且保留用户签名的纯逻辑契约已通过 LocalUnit；网络真机证据和完整字段解码待验收 |
| 后台扫描 | `ngfSystem` / `ngfBackgroundTaskManager` | 部分完成 | Settings 显式开关、Ability 前后台/销毁生命周期和连续任务门面已接入；系统保活、功耗和长期运行待真机验证 |
| 通知 | `ngfSystemNotificationManager` | 部分完成 | Settings 开关、按需权限申请、关注设备首次出现触发、进程内去重和关闭时取消已接入；API26 已验证原生授权对话框，实际通知内容和后台行为待验 |
| 实况窗 | `ngfLiveViewManagerFacade` | 仅内存状态 | 当前不能作为系统实况窗完成证据 |
| 桌面卡片 | `ngfWidgetManagerFacade` | 框架门面已有 | 需 provider 和 API26 真机验证 |
| 跨设备流转 | `ngfContinuationManagerFacade` | EntryAbility 已接入 | Fieldwatch 上下文尚未定义 |
| 多窗口 | `MultitonEntryAbility` / NGF window facade | 框架演示已有 | Fieldwatch 页面尚未接入 |
| 隐私保护 | Fieldwatch domain mask + 可选生物识别 | 地址/坐标掩码已有 | 生物识别和完整导出保护待实现 |

## 特征库（签名目录）映射

| Android 能力 | HarmonyOS / NGF 实现 | 当前状态 |
|---|---|---|
| `SignatureClass`（21 类，BODYWORN 折叠到 WEARABLE） | `FieldwatchModels.SignatureClass` + `foldedSignatureClass` / `visibleSignatureClasses` | 已实现；ROUTER 作为历史值折叠到 ISP |
| `MatchRule` / `RuleKind`（11 种） | `signatures/FieldwatchSignatureModels.SignatureRule` | 已实现，含 `couldMatchBle` |
| `Fleet`（matchAny/colorIndex/minPeers/clusterByOui/sequentialMac/notes/attentionNote/decode） | `SignatureFleet` | 已实现 |
| `DecodeSource/Type/Endian/WhenOp/When/DecodeField/FleetDecode` | 同名模型 + `FieldwatchSignatureFieldDecoder` | 已实现，含位域、缩放、取模、命名值、Strong 与门控 |
| `SignatureEngine`（OUI 索引、快速规则、cluster、仲裁） | `FieldwatchSignatureEngine` | 已实现，含 Tesla/iBeacon、Osmo/DJI、Meraki/Cisco、AirTag/Apple 仲裁 |
| `SignatureExchange`（pack 编解码、merge、overlayStock、fingerprint） | `FieldwatchSignatureCatalog` | 已实现；错误以错误码返回，文案由 UI 本地化 |
| `DefaultCatalog`（编译期内置目录） | `rawfile/fieldwatch-signatures-v2.json` + `FieldwatchCatalogRepository.loadStock()` | 已实现；异步加载避免阻塞首帧 |
| `ConfigStore.overlayStockCatalog` | `loadBundledCatalog()` = 沙箱用户目录 + 内置 stock 覆盖 | 已实现 |
| `CatalogRemote`（GitHub 更新） | `updateStockCatalog()` 经 `ngfNetworkClient` | 已实现；仅用户主动点击时发起 |
| `FleetsScreen` / `DecodeFieldsScreen` | `pages/fieldwatch/FieldwatchSignaturesPage.ets` | 已实现搜索、类别筛选、启停、详情、导出/导入/更新/恢复默认；系统文件选择器导入导出未接入 |
| 签名编辑器 | `pages/fieldwatch/FieldwatchSignatureEditorPage.ets` | 已实现名称/类别/启停/任一或全部规则、11 种规则增删改、解码来源与字段增删改，以及门控（5 种 op + 一层 and）与命名值（原始值/显示文本/强提示/说明）编辑 |
| 签名可视化 | `SIGNATURE_COLOR_PALETTE` / `signatureColorIndex` / `buildRadarPoints` | 雷达点位与列表图标按签名 `colorIndex`（0..8）着色，无命中退回无线电类型色；雷达标签在无名称/SSID 时回退为签名名 |
| 关注整个签名/产品族 | `FieldwatchApplication.watchTargetHits` / `toggleSignatureWatch`、`WatchTarget.signatureId` | 已实现；设备键关注与签名关注共用同一命中判定，`watchedOnly` 过滤同样生效 |
| 过滤器签名条件 | `FilterDefinition.matchedOnly/decodedOnly/locatedOnly/namedOnly` | 已实现，对应基线 §5.1 的「是否已匹配签名 / 是否包含解码值 / 是否包含位置 / 是否为已命名设备」 |
| Hunt 目标搜寻（§6） | `domain/FieldwatchHunt.ets` + `platform/FieldwatchHuntFeedback.ets` + `pages/fieldwatch/FieldwatchHuntPage.ets` | 状态机、tick 间隔与会话统计已实现并测试；触感节拍走 `vibrator`，音频节拍走 `media.createSoundPool` + 内置 wav，两者组合且各自静默降级 |
| 目录文件导入导出（§11） | `platform/FieldwatchCatalogFileGateway.ets` | 经 `picker.DocumentViewPicker` 导出到用户选择位置、从用户选择的签名包导入；只在用户点击时调用 |
| 具名过滤预设（§5.2） | `FilterPreset` + `FieldwatchSettingsRepository` 多预设 API | 保存/同名覆盖/载入/删除 + 旧单预设自动迁移 |
| 目录排序与关注列表（§7/§11） | `sortSignatureFleets`、`FieldwatchSettingsRepository` 预设 API、`WatchTarget.note` + `seedBuiltInWatchTargets` | 排序、预设删除/默认预设、观察者备注、内置关注项已实现 |
| Live 行解码 chip / Debrief / Compare / 导出 | `FieldwatchUiState.liveDecodeLabels`、`signatureHitCounts`、`FieldwatchApplication.buildDebrief`、`FieldwatchExportSerializer` | 已实现；Live 行显示 live 解码值，Debrief 统计签名命中与解码值，Compare 增加共享签名，CSV/JSONL 增加 signatures/decoded 列 |
| 旧版精简 `SignatureDefinition` 目录文件 | `loadLegacyCatalog()` 一次性迁移到新模型 | 已实现，用户自定义签名不丢失 |

## HDS UI 映射

| Fieldwatch 页面能力 | HarmonyOS/NGF 实现 | 当前状态 |
|---|---|---|
| 根导航 | `HdsNavigation` + `NavPathStack` + `NGFHdsTitleBarOptionsFactory` | Fieldwatch 首屏已直达，API26 构建通过 |
| 手机主导航 | `HdsTabs` + 浮动沉浸材质 | 四 Tab 已显示：实时/筛选/报告/设置 |
| 平板主导航 | `ngfDeviceAdaptationFacade` + HDS 侧栏布局 | MatePad 截图已验证侧栏和宽内容区 |
| 竖屏/横屏策略 | `ngfDeviceAdaptationFacade.isLandscape()` | 竖屏（含平板竖屏）使用 HDS Tab；仅横屏使用左右分区；根导航通过 `hideTitleBar(true)` 完全移除标题栏 |
| Live 雷达 | ArkUI `Canvas` + `FieldwatchRadarPoint` | 全屏雷达、扫束、稳定角度、RSSI 半径、设备名/SSID、类型、RSSI 和 Wi-Fi 频率标签已实现；四视图切换和详情点击仍待真机补证 |
| 详情路由 | `HdsNavigation.navDestination` + `fieldwatch.device_detail` | 路由目标已注册，完整数据绑定待补 |
| 详情 Sheet | `bindSheet` + `NGFMaterialSheetOptions` + `SheetSize.MEDIUM` | 默认半屏，允许用户上拉展开；设备事实使用 Fieldwatch `Sighting` |
| 设备类型图标 | Fieldwatch SVG + ArkUI `Image.fillColor` | Wi-Fi AP、BLE、手机、追踪器、无人机、摄像头、穿戴、路由器八类资源已创建并接入详情/预览；导航仍使用 `sys.symbol` |
| 主题与材质 | HDS 标题栏、沉浸式顶栏、系统材质、深色资源、`ngfThemeManagerFacade` | Settings 已接入跟随系统/浅色/深色控制并复用系统 ColorMode；API26 控件操作和浅色/深色截图已验证，完整手机/平板主题回归仍待补 |

## 已确认的 API26 Wi-Fi 事实

本机 DevEco SDK 声明确认 `@ohos.wifiManager` 提供：

- `isWifiActive()`。
- `startScan()`。
- `getScanInfoList()`。
- `on('wifiScanStateChange', callback)` 和对应 `off`。
- `WifiScanInfo` 的 SSID、BSSID、capabilities、securityType、RSSI、band、frequency、channelWidth、Information Elements 和 timestamp。

扫描相关权限由官方声明要求 `SET_WIFI_INFO`、`GET_WIFI_INFO`，读取结果还可能需要 `GET_WIFI_PEERS_MAC` 或位置权限。当前生产实现额外检查系统位置总开关并将其作为可恢复前置条件；不自动修改系统设置。

## API26 真机调查证据

- `wifiScanStateChange` 原始值约定为 `0=失败`、`1=成功`；实现只在 `1` 后调用 `getScanInfoList()`。
- MatePad Mini（MLR-AL10/API26）此前通过 U30 热点运行时 `startScan()` 返回过 `2501000 Operation failed`；2026-10-04 新实现现场复测收到 `wifiScanStateChange=1`，`getScanInfoList()` 连续返回 34、31 条。说明 U30 不是稳定复现的硬性限制，仍应保留失败/节流诊断并继续主验收路由器测试。
- 结果保留 SSID、BSSID、RSSI、频率、频段、信道宽度、安全类型、timestamp 和 Information Elements 原始十六进制；空 BSSID 丢弃并记录日志。
- 当前状态：API26 真机切换网络后观察到 AP 数量随网络变化；当日复测结果先后为 24、37 条，并验证 RDB 重启恢复 500 条。
- 2026-10-06 连续矩阵（U30 热点环境，HDC `192.168.0.36:40835`）：6 分 31 秒内 9 次 `startScan()` 请求，间隔 46.3–46.5 秒（45 秒周期 + 约 1.4 秒扫描），9 次 `wifiScanStateChange=1`、0 失败，每批 25/25/31/31/31/31/32/33/34 条；同窗口 BLE 13338 条观测、应用日志 0 告警 0 错误；详情 Sheet 字段样本 SSID `DLZZ_U30`、BSSID `04:b3:2e:b0:fb:b1`、RSSI `-35 dBm`、频率 `2412 MHz`、频段 1、信道宽度 0、安全类型 4。
- 仍未验收：普通路由器主环境连续矩阵、系统位置总开关关闭、权限撤销后重新授权、前后台切换和功耗采样。
- 测试证据边界：`hvigorw test` 的 `BUILD SUCCESSFUL` 不表示测试通过，必须检查 `> hvigor ERROR: Error in ` 行数为 0。
