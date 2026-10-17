# 功能一「找东西」深度落地文档

> 来源：由开发者在会话中给定的设计文档（2026-10-12），本文件是「找东西」功能的权威依据。
> 依据：af-app 仓库实查 + HarmonyOS 官方 API 参考（`@ohos.bluetooth.connection` / `access` / `wifiManager` 等模块文档，含华为文档镜像站核对）。
> 凡文档没写死、只能靠真机回答的问题，统一收进第八节验证清单，不在正文里假装确定。

---

## 〇、结论速览：四个「能不能」

| 问题 | 结论 | 关键依据 |
|---|---|---|
| 能否拿到系统已配对蓝牙设备来认人？ | **能**，而且是本功能的主锚 | `connection.getPairedDevices()` 返回已配对设备地址数组；另有 `getRemoteDeviceName(地址)`、`getRemoteDeviceClass(地址)` 可补名称与设备类别。只需 ACCESS_BLUETOOTH，已在册 |
| 能否知道某台设备当前正连着手机？ | **能（按 Profile 查）** | A2DP/HFP/HID 等 Profile 对象提供已连接设备查询与 `connectionStateChange` 事件；连接状态可让目标列表显示「正在使用中」并免认领 |
| 能否拿到 Wi-Fi 已连接/曾连接信息？ | **当前连接能，曾连接列表不能** | `wifiManager.getConnectedInfo()` 给当前 AP 的 SSID/BSSID/信号/频段；官方 `wifiManager` 公开接口里没有「已保存网络列表」，只有本应用自己添加的候选配置可查。对「找东西」影响不大（见落地点三） |
| 能否拿到星闪已配对列表？ | **未证实，按「拿不到」设计** | 星闪是华为专有 Kit，公开镜像文档里未见配对列表接口；仓库现用 manager/scan 只有扫描。开工前在本机 API 26 SDK 的类型定义里核实一次（方法见第八节 V5），v1 星闪目标一律走「现扫现认」 |

**此外还有一个贯穿全篇的官方事实，先说透：** `getPairedDevices()` 给的不是真实 MAC，而是系统分配的**虚拟 MAC**。官方文档口径：配对关系存续期间该地址不变；取消配对、或蓝牙关闭后重新获取，地址可能变更；如需持久化标识，可用 `access.addPersistentDeviceId` 为设备生成持久 ID。这决定了身份设计不能只存一个地址了事 —— 落地点五专门处理。

---

## 一、落地点一：已配对蓝牙设备 = 认领名单（核心）

**仓库现状**：全仓 grep 确认，目前没有任何代码调用配对/连接类 API —— `FieldwatchBleScanner.ets` 只做 `ble.startBLEScan` + `BLEDeviceFind`，注释里也写明了 `ScanResult` 只有 `deviceId/rssi/data/deviceName` 等字段。也就是说今天用户想找自己的耳机，只能在一两百个广播里靠名字肉眼认。这是日常用户流失的第一道坎，配对名单正是解法。

**接入设计**：

新增平台层网关 `platform/FieldwatchPairedDevices.ets`（沿仓库 platform 层惯例），封装三件事：拉配对地址列表 → 逐个补 `getRemoteDeviceName` / `getRemoteDeviceClass` → 输出统一的 `PairedDeviceInfo{ virtualAddress, name, deviceClass, profiles[] }`。名称查不到时回退为空，UI 显示「未命名设备」并允许用户改名（改名只存本机档案，不回写系统）。

**认领动作 = 一次点击**：找东西页顶部固定一区「你的设备（系统已配对）」，列出配对名单（带类别图标，DeviceClass 映射到现有 `FieldwatchDeviceTypeIcon`），用户点一台即完成认领并直接进入寻找向导 —— 不需要先扫描、不需要从广播列表里找。耳机、手表、音箱、车载蓝牙这类「正经配过对」的自有设备，全走这条路，覆盖日常找东西的绝大多数场景。

配对名单同时给 Watchlist 输血：现有 `WatchTarget` 支持 `deviceKey` 与 `signatureId` 双锚，认领时把虚拟地址写进 `deviceKey` 体系（key 格式沿用 `ble:<deviceId>` 的既有拼法，保证与 `Sighting` 体系同构）。

**必须正视的缝**：配对名单给的是虚拟地址，扫描给的是 `ScanResult.deviceId` —— 两者在真机上是否同一个值，文档没有一句话写死（文档只保证配对地址自身稳定；dev.to 上华为工程师的实操文章里，是用配对后的虚拟地址与 BLE 侧地址做匹配来建经典蓝牙连接的，暗示同值，但那是连接场景不是扫描场景）。所以第八节 **V1 是整个功能的头号验证项**，且落地点五的指纹兜底就是为「万一不同值」准备的 —— 设计上不把命押在一个未证实的等式上。

---

## 二、落地点二：当前连接状态（零成本的确定性）

对已认领设备，用其支持的 Profile（A2DP 耳机音箱、HFP 车载、HID 键鼠手柄）查连接状态并订阅 `connectionStateChange`：目标卡片因此有三态 ——

- **正在连着手机**（多半在你身上/手边，文案直接点破：「它正连着这台手机，先摸摸口袋」）
- **在附近**（扫得到广播）
- **上次见到**（时间 + 大致场景）

「正在连着」还有一个隐藏价值：**断开时刻就是最可信的 `lastSeen`**。耳机放下摘除、车熄火断开的瞬间记一条带 `Sighting.location` 的记录，「上次见到」从此是事件级的，不是扫描碰运气。这条数据顺手喂给后续的找车/看板功能（上一份文档的功能四/五），本期只落库、先不在找东西页展示。

**注意边界**：Profile 查询只覆盖经典蓝牙与双模设备的经典侧；纯 BLE 设备（防丢器、部分手环）的连接由各自 App 的 GATT 维持，系统不提供「任意 App 的 BLE 连接清单」给第三方 —— 这类设备只有「在附近/上次见到」两态，文案不要许诺第三态。

本节所有接口在 API 26 SDK 中的确切签名与返回值，开工第一天先在类型定义里逐个核对再写网关（与 V5 同批做，半天内完成）。

---

## 三、落地点三：Wi-Fi 侧 —— 只做「找路由器」，且锚意外地稳

找东西页的 Wi-Fi 目标只有一个合理形态：**家里的路由器/AP**（比如确认路由器还活着、找弱电箱里的 AP 位置）。它的身份锚是 **BSSID** —— 路由器不玩随机地址，BSSID 长期稳定，是所有目标里最好认的一个。

**认领捷径**：用户在家连着自家 Wi-Fi 时，`getConnectedInfo()` 直接给出当前 AP 的 SSID/BSSID/频段，认领页此时多一张卡：「你现在连着的『客厅-5G』是你家路由器吗？」一点即认领，连从扫描列表里挑都省了。仓库 `FieldwatchWifiScanner.ets` 已有 `getScanInfoList` 的完整管线，只需在 platform 层给它加一个 `getConnectedInfo` 的薄封装。

认领之后走现有 Wi-Fi 扫描 + Hunt 同款冷热逻辑（Hunt 领域逻辑与 kind 无关，Wi-Fi 的 RSSI 同样适用）。

「曾连接网络列表」拿不到这件事在本功能里无实际损失，不要为它去申请任何系统权限硬凑 —— 文档结论就写「不支持从系统导入历史 Wi-Fi」，靠上面这条当前连接捷径 + 扫描列表手选覆盖。

---

## 四、落地点四：星闪 —— 只走「现扫现认」

星闪目标（星闪耳机、车钥匙类）v1 不做配对导入：认领方式只有在扫描列表里当场点选（星闪设备本来就少，列表短，肉眼认名的成本可接受），认领档案只存当次 `deviceId` + 名称 + 签名命中信息，并在档案上明示「星闪设备的地址稳定性未经确认，下次可能需要重新认领」—— 若 V5 在 SDK 里查到 manager 的配对列表接口，再按落地点一的同构方式补导入，不改上层。
>
> **已落地（2026-10-16，V5 有惊喜）**：`@ohos.nearlink.manager.getPairedDevices(): string[]`（权限 `ACCESS_NEARLINK`，本 App 已在册）确实存在，**且 `RemoteDevice` 还提供 `getDeviceName()` / `getDeviceClass()` / `getConnectionState()`** —— 名称、类别、连接态三样都能拿到，比预期更好。已按落地点一的同构方式接入：
> - `radio/FieldwatchNearLinkPaired.ets`（独立接口 `IFieldwatchNearLinkPairedPlatform` + `HarmonyNearLinkPairedPlatform` + `nearLinkCategoryOf` 粗映射）；
> - `FieldwatchPairedDevices` 构造注入两条平台（蓝牙 / 星闪），`PairedDeviceInfo` 增加 `kind` 与 `nearLinkDeviceClass`，`list()` 合并两源；
> - 认领模型按 `kind` 生成 `nearlink:<地址>` 前缀的 key，走与蓝牙完全相同的认领与向导路径；
> - 图标用应用既有的 `nearLinkClassSymbol`（比粗映射精确，能分出鼠标/触控板/手写笔）。
>
> **仍未证实的一项**：星闪配对地址与扫描 `deviceId` 是否同构（原 V5 只确认「有接口」，没确认「地址同源」）—— 在没有星闪设备之前，星闪档案的 `addressStable` 保持 false，UI 继续如实提示「下次可能需要重新认领」。

---

## 五、落地点五：身份档案 —— 认领到底存什么

新增领域模型 `domain/FieldwatchOwnDevice.ets`（或扩 `WatchTarget` 字段，二选一，**推荐新建模型**、`WatchTarget` 只存引用，避免把关注体系搅浑），每条档案字段：

| 字段 | 来源 | 用途 |
|---|---|---|
| `persistentId` | `access.addPersistentDeviceId`（认领时对目标调一次） | 跨蓝牙开关/重扫的持久锚，文档明确为此设计 |
| `virtualAddress` | `getPairedDevices` / 扫描 `deviceId` | 当前配对期内的快速匹配锚 |
| `displayName` | `getRemoteDeviceName` / 广播名 / 用户改名 | 展示与搜索 |
| `deviceClass` → 图标 | `getRemoteDeviceClass` / 签名分类 | 列表图标（复用现有 `DeviceTypeIcon` + `ClassLabels`） |
| `fingerprint` 快照 | 认领那一刻的广播：名称、厂商数据键、服务 UUID 集、命中 `signatureId` | 锚失效时的兜底匹配（下述） |
| `lastSeenAt` / `lastLocation` | 观测管线回写 | 「上次见到」 |

**匹配管线**（写进 `domain/FieldwatchOwnDeviceMatcher.ets`，纯逻辑 + 单测）：实时 `Sighting` 进来后按序判定 ——

1. **地址直配**（`virtualAddress`/`persistentId` 命中，最高置信）→
2. **指纹打分**（名称全等 +3、厂商数据键命中 +2、服务 UUID 集包含 +2、签名命中 +2，**≥5 分**认作同一台）→
3. 都不过则不是自有设备。

阈值集中成常量，真机阶段用自有设备组调。**认错的代价不对称**（把邻居的耳机当自己的会闹笑话），阈值宁高勿低，且档案卡上保留「这不是我的设备」一键纠错，纠错即把该指纹拉黑名单（档案加 `denyFingerprints` 数组）。

落库走现有 RDB 方式（`ObservationRepository` 同款建表迁移），表名 `fieldwatch_own_devices`。

---

## 六、落地点六：寻找向导 —— 直接复用 Hunt 的全部家底

这是本功能最省力的一节，因为仓库的 Hunt 不是半成品，是完成度很高的领域实现，实查到的可直接复用项：

- **状态机现成**：`huntCue()` 已产出七态（VERY_CLOSE / CLOSER / FURTHER / SAME / WAITING / QUIET / GONE），判定用 2 秒近窗 vs 3.5–8 秒远窗的均值差（阈值 3 dB），日常文案与七态一一映射即可，判定逻辑零重写。
- **盖革滴答现成**：`huntTickIntervalMs` 已把响度映射到 90–1400ms 的滴答间隔（-40dBm 最急、-90dBm 最缓），且安静/消失态自动静默 —— 这是最像「金属探测器」的体感来源，`FieldwatchHuntFeedback.ets` 的声音（AudioKit 渲染器）与震动（SensorServiceKit，含效果支持检测与停止逻辑）都已封装好。
- **「非常近」阈值现成**：`HUNT_VERY_CLOSE_DBM = -45`，且注释写明与 `DeviceExplain` 的「非常强」同义（口袋/手持/同一背包量级）—— 日常文案「就在你身上或包里，先摸一摸」正好落在这个量级上。
- **会话记录现成**：`HuntRecord`/`HuntStats` 可直接给「找到了」收尾与历史用。

新写的只有页面：`pages/fieldwatch/FieldwatchFindPage.ets`，它消费 `HuntSession` + `HuntCue`，做三件 UI 的事：大号热度可视化（用 cue + 近窗均值，**不显示 dBm**）、状态文案、声震开关。原专业 `HuntPage` 保持不动，日常页是它的「翻译版」，两页共用领域层 —— 以后调阈值一处生效。

---

## 七、落地点七：怎么确保「确实足够简单好用」

不喊口号，定成可验收的硬指标。

### 7.1 点击预算（上线门禁，逐项实测）

- **首次认领（已配对设备）**：从日常首页起 **≤3 次点击**（找东西 → 点设备名 → 进入向导，认领与进入合并为一步，不设独立「先认领再使用」的流程）。
- **再次找已认领设备**：**≤2 次点击**（首页卡片 → 点设备 → 已在向导中自动开扫）。
- **找的过程中**：零决策点，直到「找到了」为止用户不需要做任何选择；声震开关是唯一可选项且默认全开。

### 7.2 状态与文案（每态一句人话，进资源文件走现有 i18n 方式）

- `WAITING` 超 10 秒无任何包 → 自动展开**排查卡**（最多 3 条，按目标类型生成：「打开耳机盒盖」「设备可能没电了，先充 5 分钟」「离上次见到太远？先回上次出现的地方」）。
- `QUIET` → 「暂时听不到它了，可能被金属/墙体挡住，换个方向慢慢走」；`GONE` → 不说「丢失」，说「它不在附近，先看看上次见到是几点、在哪」并给 `lastSeen` 卡。
- `VERY_CLOSE` → 整屏变色 + 长震 + 大字「就在附近！」；`CLOSER`/`FURTHER` 用箭头与颜色，**不用任何数字**。

### 7.3 防呆设计两条

- **同名多台**（家里两副同型号耳机）：认领/寻找时若有两台以上同名候选，给「拿起你的那台晃一晃」确认法 —— 让用户晃动目标，信号出现特征波动的那台在列表里自动高亮打勾。这是利用现有采样流就能做的判定（短窗方差突增），比让用户对着地址尾号猜强得多；做进 Matcher 的可选确认环节，纯逻辑可测。
- **认错纠正**：任何档案卡长按有「这不是我的」；寻找中若信号行为明显不符（比如纹丝不动的最强信号贴在墙上），不自动断言，只提示「最强的信号在那边，但一直没变化，也可能是别的同款设备」。

### 7.4 无障碍与体感

热度不能只靠颜色（色盲不友好）—— 颜色 + 字号 + 声震三通道并行（家底里的声震反馈正好派上用场）；全部文案过一遍大字体模式不溢出；震动强度给一档设置（老人/敏感用户可关震留声）。

### 7.5 简单性验收清单（发版前逐项打勾，写进测试记录）

术语 grep 验收（日常页资源文案中不得出现 RSSI/dBm/MAC/广播/签名等词）、点击预算实测、找一位没用过本 App 的人实测「找耳机」全流程不求助完成（可用性测试哪怕只做 1 人，也比自测强）。

---

## 八、真机验证清单（开工第一周内清掉，决定设计分支）

| # | 问题 | 验证方法 | 通过标准 / 分支 |
|---|---|---|---|
| **V1** | 扫描的 `deviceId` 与 `getPairedDevices` 的虚拟地址是否同值 | 拿已配对耳机，打印两边地址逐字比对（临时调试页或日志） | 同值 → 地址直配成立；不同值 → 指纹兜底升为主路径，地址直配只用于配对名单内部 |
| **V2** | `addPersistentDeviceId` 的持久性边界 | 认领后依次：关开蓝牙、重启手机、隔天再扫 | 三种情况都能找回同一 `persistentId` 才把它当主锚，否则降为辅助 |
| **V3** | `getRemoteDeviceName` 对纯 BLE 配对设备（如手环）是否给名 | 用一台 BLE-only 设备实测 | 给名 → 名单可读；不给 → 该类设备认领时引导用户在广播列表里对一次名（认领向导加一步） |
| **V4** | Profile 连接状态在 API 26 的确切接口与语义 | 查本机 SDK 类型定义（a2dp/hfp/hid 模块）+ 耳机连/断实测事件 | 事件可靠 → 上「正在使用中」态；不可靠 → 只显示在附近/上次见到两态 |
| **V5** | 星闪 manager 是否有配对列表接口 | 查本机 SDK `@kit.ConnectivityKit` 中 nearlink manager 的类型定义全文 | 有 → 补星闪导入；无 → 维持现扫现认并在帮助页注明 |
| **V6** | `getConnectedInfo` 在当前机型的字段完整性（SSID 是否需位置权限配合） | 在已连 Wi-Fi 下实测返回值 | SSID/BSSID 齐全 → 上认领捷径卡；SSID 被置空 → 捷径卡降级为「从扫描列表选你家路由器」 |

### 真机结论（MatePad Mini MLR-AL10，设备时间 2026-10-16，APK 1000003 实机运行）

取证方式：装包后用 `aa start --ps targetTab toolbox-find` 直达找东西页（绕开注入点击的不确定性），截图 + 点选真实已配对设备。

| # | 结论 | 真机证据 | 对设计的影响 |
|---|---|---|---|
| **V1** | ✅ **同值**（配对虚拟地址 == 扫描 deviceId） | 认领真实耳机「FreeClip」后，向导会话的 targetKey 是 `ble:<配对虚拟地址>`。① **超过 10 秒没有展开排查卡** → 会话里已有样本（`FieldwatchApplication` 只在 `observation.key === session.targetKey` 时喂样本）；② **没有出现「已改用名字找它」提示** → 不是走同名兜底路径。两条合起来只能是：存在 key **逐字相等**的观测 | **地址直配成立**，指纹兜底降为备用路径（两条都已实现，故本次结论不需要改代码）。`addressStable` 仍保持 false —— 那是 V2（跨蓝牙开关/重启）的问题，而 V2 依赖的 `addPersistentDeviceId` 权限是 system_basic，取不到 |
| **V6-c** | ✅ SSID 可取 | 捷径卡显示真实 SSID「**DLZZ_5G**」，未触发「空名则降级」分支 | 认领捷径卡可用；BSSID 仍不可用作长期锚（V6-b） |
| **V3** | 🟡 部分通过 | 两台真实配对设备（**FreeClip**、**YUANDAO OriG in**）都取到了可读名称，且 `DeviceClass → SignatureClass.AUDIO` 映射正确（列表图标是耳机） | 认领名单可读；纯 BLE-only 设备（手环）仍未验证 |
| **V4-事件** | ⏳ 未测 | 需要耳机连/断各一次 | 三态文案先按已连接/未连接实现 |
| **V6-d** | 🟡 **部分结论：BSSID 确被遮蔽/随机化，且会话内稳定** | 直接读设备库 `fieldwatch_observations`（43 条 Wi-Fi 观测）：① 同一 SSID **只对应 1 个地址**（表内未见换地址）→ 会话内稳定；② 地址的**本地管理位置位**情况混合：`5c:27:fb`/`ec:e2:43`/`78:b0:ec` 像真实 MAC，而**用户自家路由器 DLZZ_5G 的地址 `12:a1:84`** 与 `26:fd:4a`/`16:30:8e`/`6a:18:09` 都是本地管理地址 —— 真实路由器的 BSSID 通常全局唯一，因此这正是「系统返回随机/遮蔽 bssid」的直接物证；③ `getLinkedInfoSync` 与 `getScanInfoList` 在同一会话内给出同一地址 | 设计不变（Wi-Fi 只按 SSID 认、BSSID 不作跨会话锚）；**时间粒度已测到「跨应用重启仍稳定」**（2026-10-16 两次采样：应用重启 + 95 秒扫描后，`DLZZ_5G` 仍为 `12:a1:84…`、`DLZZ` 仍为 `5c:27:fb…`，Wi-Fi 行数 43 → 70 但**没有出现同一 SSID 的第二个地址**）→ 因此本功能的 Wi-Fi 匹配改为**「地址或名字，命中其一即可」**（地址可用时更精确，地址变了由名字兜住）；跨**系统重启**是否变仍未知，故不是「只用地址」 |
| **V5-同构** | ⏳ 未测 | 手上没有已配对星闪设备 | 星闪仍走「现扫现认 + 有名单可导入」两可状态 |

**真机暴露的一条工程事实**：应用日志**不进系统 hilog**（NGF 的 `Logger` 默认也会写 hilog，但本次 9.5 MB 抓包里没有任何应用行）——所以现场取证要靠**界面本身可观察的行为**，而不是翻日志。这也是我把「是否走了名字兜底」做成界面提示的原因之一。

### 验收记录（2026-10-16 真机 + 静态）

| 验收项（文档 §7） | 结论 | 证据 |
|---|---|---|
| 点击预算·**再次找已认领设备 ≤2** | ✅ **实测 2 次** | 首页「找东西」卡（1）→ 点「FreeClip」（2）→ **向导已开扫**（截图 fw-budget-1 / fw-budget-2b） |
| 点击预算·**首次认领 ≤3** | ✅ **实测 2 次** | 首页「找东西」卡（1）→ 点未认领设备（2）→ 认领并入向导（截图 fw-find-2 / fw-find-3）。为达成此项新增了日常页直达卡：没有它要先切工具箱再点工具页，实测是 3 次（超预算） |
| 术语 grep | ✅ **0 命中** | 28 个 `fieldwatch_find*` 键前缀、实际 70+ 条文案中 `RSSI/dBm/dB/MAC/广播/签名/信道/频段` 命中数为 0 |
| 三通道热度（色盲友好） | ✅ 实现 | 颜色（`huntCueLevel` → 4 档调色板）+ 字号（44→64）+ 声震（`huntTickIntervalMs` 驱动）；不出现任何数字 |
| 深色模式 | ✅ 真机当前态 | 新 UI 两个文件**硬编码颜色 0 处**，全部走 `FieldwatchPaletteHolder`（与仓库既有页面同一套） |
| **大字体不溢出** | 🟡 **静态加固完成，真机待用户复看** | 本机无法用命令行改系统字号（`param get persist.sys.font.scale` 无此键、无 `settings` 命令）。已完成静态加固：`FieldwatchButton` 由固定 `height` 改 `constraintSize({minHeight})`；工具箱四标签加 `minFontSize(9)`；晃一晃行与声震开关改 `minHeight`。**数值审计（2026-10-16）**：把新增的 60 条文案按 1.75× 最大字号逐条算渲染宽度、与容器可用宽度（卡片内 300vp／行内文本列 226vp）比对 —— 15 条需要 2 行、**3 条需要 3 行**，其中恰好一条落在设了 `maxLines(2)` 的容器里（日常页「找东西」卡提示，683vp ÷ 300vp ≈ 3 行）→ **已去掉该 maxLines** 并在注释里写下这段算术；另两条（无配对设备空态、晃一晃说明）所在容器本就不限行数。**复看方法**：设置 → 显示和亮度 → 字体大小调到最大 → 按上面点击预算路径看「找东西」页与向导是否有裁字 |
| 浅色模式 | 🟡 结构上支持，未真机切换 | 同上：无硬编码颜色即随主题；建议连同大字体一次复看 |
| **Wi-Fi 认领路径（落地点三）** | ✅ **真机通过** | 点「就是它，认领」→ 向导以路由器名 `DLZZ_5G` 为标题打开（截图 fw-r11-c）；重启后卡片变「已认领」、「我的东西」出现该路由器且显示「**刚刚见到**」（截图 fw-r11-d）→ **观测回写的 Wi-Fi 分支（按名字匹配）真机生效** |
| **地址稳定性按种类判定 + 旧档案自愈** | ✅ 真机通过 | V1 已证实蓝牙地址可用 → `pairedAddressStable(BLE)=true`（星闪 false：未验证同源；Wi-Fi false：V6-b）。同一屏里 FreeClip 的「稳定性未确认」提示消失、路由器的保留（截图 fw-r11-d）——两个判定各自正确。旧档案由 `refreshAddressStability()` 按当前证据自愈（认领时写的是旧判断） |
| 可用性测试（找一位没用过的人实测） | ⏳ 需真人 | 文档 §7.5 明确「哪怕只做 1 人」 |

---

## 九、实施顺序

1. **验证 Sprint**：V1–V6 全清，结论记入 `.agent-rules` 或开发文档；其中 V1 结果决定 Matcher 主路径。
2. **平台网关**：`FieldwatchPairedDevices.ets`（配对名单 + 名称/类别 + 连接状态）、`WifiScanner` 加 `getConnectedInfo` 封装。
3. **档案与匹配**：`OwnDevice` 模型 + 建表 + Matcher（直配/指纹/拉黑）+ 单测。
4. **找东西页**：认领区 + 向导页（复用 Hunt 全套）+ 状态文案资源 + 排查卡；点击预算与术语验收。
5. **真机回归**：自有设备组（耳机/手表/音箱/车机/防丢器）全流程 + 同名双耳机场景 + 大字体与深色模式。

**明确不做**：不发起任何配对/连接动作（认领只读系统名单，与本 App「只接收不连接」底线一致 —— 特别注意：`getPairedDevices` 等都是只读查询，不在此限）；不承诺 BLE 连接态；不做后台常驻寻找；星闪不做导入（V5 有惊喜再说）。

---

## 八·验证结论（SDK 类型定义部分，2026-10-12 完成）

> 核对对象：本机 API 26 SDK `G:\DevEco Studio 26\DevEco Studio\sdk\default\openharmony\ets\api\`。
> 结论**只写类型定义能回答的部分**；需要真机回答的，明确留到下面「待真机」一节。

### 已定案（不需要真机）

| # | 结论 | 证据 | 对设计的影响 |
|---|---|---|---|
| **V2** | ❌ **`persistentId` 主锚不成立** | `@ohos.bluetooth.access.d.ts:168` `addPersistentDeviceId(deviceId): Promise<void>`，其 `@permission` 为 `ACCESS_BLUETOOTH + PERSISTENT_BLUETOOTH_PEERS_MAC`；后者在 `toolchains/lib/PermissionDefinitions.json` 中为 `grantMode=system_grant / availableLevel=system_basic`（普通应用需 ACL）。`getPersistentDeviceIds(): string[]`（`:199`）同样要求该权限 | 落地点五**去掉 `persistentId` 字段**，主锚改为 `virtualAddress`（配对关系存续期内稳定）+ 指纹兜底。**分支由权限级别触发，与 V1 无关** |
| **V2 语义澄清** | `addPersistentDeviceId` **不返回 ID** | 注释（`:151`）：「Add a persistent **random device address**. Once the randomized address is successfully added, the application can save it for an extended period of time.」 | 它做的是「把随机地址登记为长期保留」，`getPersistentDeviceIds()` 列出已登记地址 —— 不存在「为设备生成一个新 ID」这回事 |
| **V4** | ✅ **Profile 连接状态可用** | `@ohos.bluetooth.baseProfile.d.ts`：`getConnectedDevices(): Array<string>`（`:198`）、`getConnectionState(deviceId): ProfileConnectionState`（`:218`）、`on/off('connectionStateChange', Callback<StateChangeParam>)`（`:239`/`:255`）；入口 `@ohos.bluetooth.a2dp.d.ts:46 createA2dpSrcProfile()`（权限 `ACCESS_BLUETOOTH`，`:58`）；另可用 `@ohos.bluetooth.connection.d.ts:106 getProfileConnectionState(profileId?)` | 「正在连着手机」三态可上；枚举在 `@ohos.bluetooth.constant`：`ProfileId.PROFILE_A2DP_SOURCE = 1`、`PROFILE_HID_HOST = 6`，`ProfileConnectionState.STATE_DISCONNECTED = 0 / STATE_CONNECTED = 2`。**HFP 的 ProfileId 名称需在写网关时再核一次**（本轮 grep 未命中 `PROFILE_HFP*`） |
| **V5** | ✅ **星闪有配对列表接口**（推翻文档假设） | `@ohos.nearlink.manager.d.ts:77 function getPairedDevices(): string[]`，注释「Gets the list of devices that have been paired with the current device. Returns a list of paired devices' address in MAC format」；`@permission ACCESS_NEARLINK`（App 已在册）。同文件另有 `isNearLinkSupported()`、`getState()`、`getLocalName()`、`on/offStateChange()` | 落地点四**升级**：星闪按落地点一同构方式做配对导入，不再只走「现扫现认」 |
| **V6-a** | ⚠️ **接口名不符**：本 SDK 没有 `getConnectedInfo` | `@ohos.wifiManager.d.ts` 中 `getConnectedInfo` 命中 0 次；实际为 `getLinkedInfo(): Promise<WifiLinkedInfo>`（`:533`）、`getLinkedInfoSync(): WifiLinkedInfo`（`:589`） | 落地点三的封装接口名改为 `getLinkedInfo` |
| **V6-b** | ❌ **BSSID 会被随机化，Wi-Fi 长期锚不成立** | `@ohos.wifiManager.d.ts` 多处注释（`:173`/`:510`/`:536`）：「If does't have the permission of `ohos.permission.GET_WIFI_PEERS_MAC`, return **random bssid**」；该权限在 `PermissionDefinitions.json` 中为 `system_grant / system_basic`（普通应用需 ACL），App 的 `module.json5` **未声明**（现只有 `GET_WIFI_INFO`/`SET_WIFI_INFO`，均为 `normal`） | 落地点三「BSSID 长期稳定、最好认」的前提**被推翻**：Wi-Fi 目标退化为 **SSID + 当前连接关系 + RSSI 行为** 识别，且 UI 必须说明「同名网络无法区分」。认领捷径卡（「你现在连着的『客厅-5G』」）仍可行，因为 SSID 只需要 `GET_WIFI_INFO` |

### 待真机（本机无已配对设备/需实物配合）

| # | 问题 | 为什么类型定义答不了 | 备注 |
|---|---|---|---|
| **V1** | 扫描 `deviceId` 与 `getPairedDevices()` 的虚拟地址是否同值 | 两者都是运行期取值，文档只保证配对地址自身稳定 | **头号项**：同值 → 地址直配成立；不同值 → 指纹升为主路径。需要一台已配对耳机 |
| **V3** | `getRemoteDeviceName()` 对纯 BLE 配对设备是否给名 | 签名存在（`connection.d.ts:183/204`，含 `alias?: boolean` 重载），但返回内容取决于设备 | 需要一台 BLE-only 设备（手环/防丢器） |
| **V4-事件** | `connectionStateChange` 事件的可靠性与时序 | 事件只在真机连/断时触发 | 需要耳机连/断各一次 |
| **V6-c** | `getLinkedInfo()` 返回的 SSID 是否完整、是否需要位置权限配合 | 运行期行为 | 已连 Wi-Fi 下打印一次即可 |
| **V6-d（新增，影响既有功能）** | 无 `GET_WIFI_PEERS_MAC` 时同一 AP 的 bssid 是否**每次扫描都变** | 注释说「return random bssid」，但「随机」的粒度（每调用/每会话）未写明 | **若确实每次变**：App 现有 Wi-Fi 观测（会话对比、导出、可能同行）里的 BSSID 也是随机值，需在文档与隐私说明里澄清；同时这意味着 Wi-Fi 侧**无法**做长期识别 |
| **V5-同构** | 星闪配对地址与扫描 `deviceId` 是否同构 | 同 V1 性质 | 需要一台已配对星闪设备 |

---

## 十、交付物与底线审计（2026-10-16）

### 10.1 交付物

**新增（12 个源文件）**

| 文件 | 职责 |
|---|---|
| `radio/FieldwatchPairedDevices.ets` | 系统已配对名单网关（蓝牙）：地址 → 名称/类别/连接态；`pairedCategoryOf` 类别映射 |
| `radio/FieldwatchNearLinkPaired.ets` | 星闪配对网关（落地点四升级）：名称/原生类别/连接态 + `nearLinkCategoryOf` 粗映射 |
| `radio/FieldwatchWifiLink.ets` | 当前 AP 查询（`getLinkedInfoSync`），`bssidStable` 恒 false（V6-b） |
| `domain/FieldwatchOwnDevice.ets` | 自有设备档案（无 persistentId，V2 已核实不可用） |
| `domain/FieldwatchOwnDeviceMatcher.ets` | 地址直配 → 指纹 ≥5 分 → 拉黑（非对称） |
| `domain/FieldwatchOwnDeviceTracker.ets` | 观测驱动的「上次见到」回写（只推进、节流、Wi-Fi 按名字） |
| `domain/FieldwatchFindClaim.ets` | 认领模型：key 拼法、候选生成、已认领判定、地址稳定性按种类 + 自愈 |
| `domain/FieldwatchShakeConfirm.ets` | 同名多台「晃一晃」确认（极差 + 领先阈值，不猜） |
| `data/FieldwatchOwnDeviceRepository.ets` | RDB 表 `fieldwatch_own_devices`（14 列）+ 纯映射（容错解析） |
| `pages/fieldwatch/FieldwatchFindPage.ets` | 找东西页：认领区（配对名单 + Wi-Fi 捷径卡）+「我的东西」 |
| `ui/FieldwatchFindWizard.ets` | 寻找向导：Hunt 七态文案 + 三通道热度 + 排查卡 + 声震开关 + V1 兜底回绑 |
| `ui/FieldwatchButton.ets`（改动） | 固定高度 → `constraintSize({minHeight})`（大字体可长高） |

**改动（6 个文件）**：`FieldwatchPage.ets`（日常页「找东西」直达卡 + 两个构造点接线）、`FieldwatchToolboxPage.ets`（第 4 个工具「找东西」）、`fieldwatchApplication.requestTab`（补 `toolbox-find` 深链）、`FieldwatchButton.ets`、两份 `element/string.json`（base/en_US 各 +58 条）。

**测试**：7 个测试文件、**51 个用例**全部通过（`hvigorw test` ERROR_LINES=0）。

### 10.2 底线审计：「只接收不连接」

对上述 11 个功能文件做正则审计（已排除注释与文档行）：

- 发起类调用命中 **0** 处：`pairDevice` / `startPairing` / `createBond` / `removePair` / `.connect(` / `.disconnect(` / `startScan` / `startBLEScan` / `stopScan` / `enableWifi` / `disableWifi` / `createGattClientDevice` / `addPersistentDeviceId`；
- 实际触碰的 SDK 接口**全部是只读**：`getPairedDevices` / `getRemoteDeviceName` / `getRemoteDeviceClass` / `getConnectedDevices` / `getLinkedInfoSync` / `isWifiActive` / `isNearLinkSupported` / `getDeviceName` / `getDeviceClass` / `getConnectionState`，以及 `on/off('connectionStateChange')` 这类**只监听**的订阅；
- `entry/src/main/module.json5` 与 HEAD **无差异** → 本功能**没有申请任何新权限**（`PERSISTENT_BLUETOOTH_PEERS_MAC` / `GET_WIFI_PEERS_MAC` 都是 system_basic，本就没用）。

### 10.3 仍需外部条件的两项

| 项 | 为什么我做不了 | 标准（已写在上文验收记录里） |
|---|---|---|
| 大字体/浅色真机复看 | 本机无法用命令行改系统字号（`param get persist.sys.font.scale` 无此键、无 `settings` 命令） | 设置 → 显示和亮度 → 字体大小调到最大（顺手切浅色）→ 首页「找东西」→ 点设备 → 看向导 |
| V4 连接事件可靠性 / V6-d bssid 随机化粒度 / V5-同构 | 需要耳机连断、同一 AP 两次扫描、一台星闪设备 | 分别见 §八 待真机表的「验证方法」列 |

### 真机取证的新手段：直接读设备上的 RDB（2026-10-16）

设备上应用的沙箱与数据库**可被 hdc 直接读取**（`/data/app/el2/100/database/com.dlzz.airwavefootprints/entry/rdb/fieldwatch.db`，含 `-wal`），因此可以绕过界面直接核对落库内容。这比看截图强得多，本次据此发现并修掉了一个真实缺口。

**核对结果（`fieldwatch_own_devices`）**：表结构正是设计的 14 列；`fieldwatch_schema` 版本 **4**；观测表 5060 行未受影响。

| 档案 | kind | address_stable | claim_source | category | last_seen_at |
|---|---|---|---|---|---|
| FreeClip | ble | **1** | paired | audio | 已写入（观测回写生效） |
| DLZZ_5G | wifi | **0** | current_ap | router | 已写入 |
| YUANDAO OriG in | ble | 1 | paired | audio | 0（当时没广播） |

`address_stable` 的 1/0 正是「按种类判定 + 旧档案自愈」的结果，`claim_source` 与 `category` 也与认领路径一致。

**据此发现并修掉的缺口**：两条档案的 `fingerprint` **全是空的**。原因是 V1 成立时走地址直配、**不会触发改绑**，而回填只写在改绑路径上 —— 平时看不出问题，但一旦地址变化（V2 未证实 / 系统随机化）就无路可退。修法：向导每次刷新时，只要当前绑定的 key 对应着真观测，就把它的指纹补进档案。

**修复的 before/after 证据（同一张表）**：FreeClip 的服务 UUID 数 **0 → 1**（修复后重新走一遍向导再读库）。YUANDAO 未被回填 —— 因为它当时没有广播、没有任何观测可回填，这是正确行为（不编造指纹）。

**一个副产物提醒**：取证期间本机 **F: 盘只剩 0.10 GB**，`hdc file recv` 因此报 `no space left on device`。已清理 407 个未被文档引用的中间产物（释放约 276 MB，F: 现 0.40 GB）与设备 `/data/local/tmp` 里的截图（667M → 257M）。**建议尽快给 F: 盘腾空间** —— 构建与安装都需要余量。

### 十一、扫描列表认领路径落地（2026-10-16）

文档落地点一/四都要求「**从扫描列表里当场点选**」：星闪 v1 的认领方式、以及「没在系统里配过对的自有设备」的兜底。此前只实现了「已配对名单 + Wi-Fi 捷径卡」两条路，这条是**补实现**。

**领域层**：`FieldwatchFindClaim.scanCandidates(sightings, claimed, limit, resolveCategory)`

- 只列**有名字**的设备（一两百台设备里没名字的那些，用户认不出哪台是自己的，列出来只是噪音）；
- 只列**蓝牙与星闪**（Wi-Fi 目标走捷径卡，把邻居家的 AP 塞进「我的东西」是错的）；
- **按信号强度排序**（近的在前）；
- **认领时当场存下发广播指纹**（名称/厂商数据/服务 UUID/命中签名）—— 这正是落地点五要的「认领那一刻的指纹快照」，比事后回填更完整；
- 类别解析放在排序取前 N **之后**（它要逐个比对几百条特征库，而页面每 2 秒刷新一次，对上百台观测全解析是白烧 CPU）。

**界面**：配对区下方一个默认收起的入口「没找到？从附近的设备里选」，展开后列出候选（图标取签名类别、右侧「认领 / 已认领」），点击复用同一条认领路径。

**真机验证与同轮修掉的文案错误**：展开后两个真实候选（`LYWSD03MMC`、`njcuk.fitting.ad1204`）正常显示并可认领；但**副标题写着「系统里配过对」** —— 那是配对名单路径的文案，扫描来的设备根本没配对，会误导用户。已按 `source` 分流（新增 `fieldwatch_find_sub_nearby`「附近扫到的」）并复验。
