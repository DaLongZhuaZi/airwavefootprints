# Fieldwatch 功能完整清单

> 文档用途：作为 Fieldwatch Android 版本迁移到 HarmonyOS Next / NGF 的功能基线、验收清单和拆分依据。
>
> 梳理范围：`Fieldwatch/` 当前源码、`README.md`、`CHANGELOG.md`、用户手册 PDF 文件以及测试目录。
>
> 版本基线：Fieldwatch `1.1.17`，变更记录日期为 **2026 年 10 月 1 日**。
>
> 说明：本文描述的是 Android 版本已经具备或明确实现的能力，不代表 HarmonyOS 已经实现。HarmonyOS 版本需要基于 NGF 重新实现系统能力、页面和权限流程。

## 1. 产品定位

Fieldwatch 是一个以离线、被动观测为核心的现场无线电观察工具：

- 被动观察手机周围可被系统暴露的 Wi-Fi 接入点和 Bluetooth Low Energy（BLE）广播。
- 不主动连接目标设备，不发送扫描探测数据，不需要账号，也不依赖 Fieldwatch 后端服务。
- 在本机完成设备聚合、信号分析、签名识别、过滤、记录、位置标记和报告生成。
- 允许用户把观测结果导出、分享或发送到外部 TAK / CoT 系统。
- 所有识别、移动伴随、轨迹关联和报告结论都属于线索或假设，不是设备身份或法律结论。

## 2. 用户界面与导航

### 2.1 首次使用

- 展示应用用途和安全/隐私说明。
- 引导申请无线电扫描、位置和通知相关权限。
- 说明应用只进行被动监听，不主动连接或发送无线电数据。
- 权限未授予时展示原因、当前状态和继续操作入口。
- 授权后自动启动扫描或进入实时观测页面。

### 2.2 顶层页面

应用主要由以下功能入口组成：

1. **Live（实时）**
   - 查看当前仍在观察窗口内的 Wi-Fi 和 BLE 设备。
   - 暂停/恢复实时列表显示；暂停显示不等同于停止扫描。
   - 查看 Wi-Fi、BLE 和总设备数量。
   - 进入设备详情、Hunt、过滤器和报告等功能。
2. **Filters（过滤器）**
   - 按无线电类型、信号强度、设备类别、签名、关注状态等条件筛选。
   - 支持 AND / OR 逻辑。
   - 支持保存、使用和删除过滤预设。
3. **Signatures（签名）**
   - 浏览、搜索、编辑和管理设备签名目录。
   - 查看签名类别、匹配规则、额外关注说明和解码字段。
   - 从观测设备创建签名。
   - 编辑解码字段和命名值。
4. **Reports（报告）**
   - 管理 named sit（命名观测时段）。
   - 生成 Debrief、Compare、Path 和各种日志导出。
   - 清除日志和管理已保存的 sit。
5. **Settings（设置）**
   - 管理扫描、显示、关注、位置、TAK / CoT、日志、签名目录、设置备份和隐私选项。

### 2.3 设备详情

- 显示设备的 Wi-Fi / BLE 类型标识。
- 显示 MAC 或设备键、名称、SSID、厂商、设备类别和匹配签名。
- 显示 RSSI、RSSI 强度等级、信道/频率、PHY、Wi-Fi 安全信息等可用无线电事实。
- 显示首次发现、最近发现、出现次数和最近 15 分钟存在情况。
- 显示信号强度趋势图。
- 显示设备的原始广播/信息字段、服务 UUID、制造商数据和十六进制载荷（系统可获得时）。
- 显示签名匹配原因、签名说明、Extra attention 提醒和解码字段。
- 显示位置：听到设备的位置、广播位置、Remote ID 飞行器位置和飞手位置（对应数据存在时）。
- 支持给设备设置自定义名称和观察者备注。
- 支持将设备加入或移出关注列表。
- 支持启动 Hunt。
- 支持从设备创建签名。
- 支持将设备详情作为文本分享。
- 支持生成该设备的 AI Export。

## 3. 实时观测功能

### 3.1 Wi-Fi 被动扫描

- 使用系统 Wi-Fi 扫描结果观察附近接入点。
- 记录 SSID、BSSID/MAC、RSSI、频率/信道、能力和安全信息等系统可用字段。
- 解析 Wi-Fi Information Elements（IE）中的厂商和扩展字段。
- 根据 OUI、名称、SSID、IE 和自定义规则匹配签名。
- 处理系统 Wi-Fi 扫描节流、扫描等待和扫描失败状态。
- 在设置页显示 Wi-Fi 当前状态，例如等待系统、正在扫描、下一次扫描时间等。
- Wi-Fi 接入点不参与“Moving with you”判断，避免车辆经过固定 AP 时产生错误路径结论。

### 3.2 BLE 被动扫描

- 持续接收 BLE 广播结果。
- 解析 Manufacturer Data、Service Data、Service UUID、设备名称、Tx Power、RSSI 和地址类型等字段。
- 兼容 Public / Random 地址类型以及系统可暴露的广播数据。
- 处理 BLE 地址随机化、广播数据变化和重复广播去重。
- 支持 BLE 广播协议与产品族识别，包括 Fast Pair、Remote ID、DULT 等已配置规则。
- 系统无法暴露、设备关闭、设备休眠、仅蜂窝连接或超出系统扫描能力的设备不会出现。

### 3.3 设备聚合与生命周期

- 根据 Wi-Fi BSSID 或 BLE 观测键聚合重复发现。
- 保存首次发现时间、最近发现时间、出现次数、最近 RSSI 和 RSSI 样本。
- 设备离开实时窗口后从当前列表移除，但已经写入的日志和 sit 数据保留。
- 对 BLE 旋转地址尽量使用广播载荷、签名或协议字段辅助关联；不能保证跨地址识别。
- 区分“当前听到的设备”“设备广播的位置”“Remote ID 飞手位置”。
- 支持设备的信号趋势、存在时间和最近活动概览。

### 3.4 实时显示模式

支持以下 Live 显示模式：

- **Classic radar**：雷达式空间显示，包含旋转扫描束、淡出轨迹和被扫描到时的联系人高亮。
- **Strength list**：按信号强弱展示列表。
- **Timeline**：按时间顺序展示设备活动。
- **Hybrid + sparklines**：列表与 RSSI 迷你趋势结合。
- **By class**：按签名类别分组展示。

可选的实时字段包括：

- RSSI 强度条。
- 签名名称。
- 频率/信道。
- 首次发现和最近发现时间。
- Wi-Fi / BLE 类型图标。
- 类别图标和 Extra attention 标识。
- 已解码的现场字段标签和强调值标签。

### 3.5 显示控制

- 暂停/恢复实时列表刷新。
- 扫描继续运行时，仅暂停显示层更新。
- Jump to new watched detection：发现关注目标时跳转或定位到新目标。
- Keep screen on：观测时保持屏幕常亮。
- 深色主题。
- 可配置实时列表排序和显示字段。
- 对新目标进行短暂视觉高亮。

## 4. 分类、签名和识别系统

### 4.1 签名类别

当前可见类别包括：

- Finder tags：查找器/追踪标签。
- Retail beacons：零售信标。
- Signage：数字标牌。
- Wearables：可穿戴设备。
- Surveillance：监控相关设备。
- Drones：无人机。
- Pentest：渗透测试设备。
- Public safety：公共安全设备。
- Vehicle：车辆相关设备。
- Glasses：智能眼镜。
- Audio：音频设备。
- Cameras：摄像机及摄像机无线电。
- Thermostats：恒温器。
- Access control：门禁/门锁读卡器。
- Health：健康设备。
- Home IoT：家庭物联网。
- ISP / routers：运营商和路由器。
- Mesh：网状通信设备。
- Phones / PCs：手机和个人电脑。
- Other：其他设备。

历史配置中还可能存在 `BODYWORN`，当前显示时折叠到 Wearables；旧数据值需要保持兼容。

### 4.2 签名匹配

- 按 Wi-Fi OUI、SSID、BSSID、厂商 IE、名称和其他 Wi-Fi 字段匹配。
- 按 BLE Manufacturer Data、Company ID、Service Data、Service UUID、设备名称和载荷匹配。
- 支持多个匹配规则组合。
- 支持同一设备匹配多个签名。
- 支持签名优先级、类别、颜色和 Extra attention 说明。
- 支持签名的自定义备注、名称、分类和关注设置。
- 同一个签名可绑定解码字段。
- 允许同一目录中保留 stock signatures 和用户自定义 signatures。

### 4.3 解码字段

- 从广播数据按偏移、长度、字节序和匹配条件提取字段。
- 支持制造商数据和 Service Data 两类数据源。
- 支持十六进制、整数、枚举、文本等字段展示形式。
- 支持字段仅在特定值或特定门控条件满足时出现。
- 支持 Named values，将原始值映射为可读文本。
- 支持给特定 Named value 设置更醒目的 Strong 标签。
- 支持配置字段是否显示在实时列表行。
- 支持实时行、设备详情、Debrief 和 Compare 使用同一解码结果。
- 删除解码映射不会删除原始广播数据，只会停止对应字段和代码标记的显示。

### 4.4 当前实现中的协议/产品识别示例

- Apple/Google 等查找标签相关识别。
- Google Fast Pair 模型识别。
- Remote ID / Open Drone ID 广播和位置字段。
- DULT（IETF Detecting Unwanted Location Trackers）相关数据。
- Penguin、TPMS 等特定厂商或协议字段。
- 摄像机、无人机、车辆、路由器、门禁、医疗和家庭 IoT 等产品族。
- 具体识别范围由内置 catalog 和用户导入的签名包决定，不能把签名命中当作绝对身份确认。

## 5. Filters 过滤器

### 5.1 过滤条件

- Wi-Fi / BLE 类型。
- 最小/最大 RSSI 或信号强度范围。
- 签名类别。
- 指定签名。
- 是否已匹配签名。
- 是否属于 Extra attention。
- 是否在关注列表中。
- 是否为已命名设备。
- 是否包含解码值。
- 是否包含位置或 Remote ID 数据。
- 其他当前 FilterEngine 支持的设备字段条件。

### 5.2 过滤行为

- AND：所有启用条件同时满足。
- OR：任意启用条件满足即可。
- 实时应用到 Live 列表。
- 过滤只影响显示，不删除底层日志和 sit 数据。
- 可保存为过滤预设。
- 可加载、覆盖、删除过滤预设。
- 提供默认过滤预设。
- “Moving with you”启用时，Filters 页面限定为 BLE 目标。

## 6. Hunt 目标搜寻

- 从实时设备或设备详情启动 Hunt。
- 以目标设备为中心持续观察 RSSI 变化。
- 显示当前 RSSI、峰值 RSSI、最近样本和信号趋势。
- 提供等待、接近、远离、信号增强/减弱等提示状态。
- 提供短促的“geiger tick”声音反馈。
- 根据目标声音/视觉反馈帮助用户进行现场接近判断。
- Hunt 不提供真正的方向测量，也不等价于测向仪。
- 关注列表的双响提示与 Hunt 的短促提示是两套独立告警。

## 7. Watchlist / 关注列表与告警

### 7.1 关注对象

- 关注具体设备/MAC/设备键。
- 关注整个签名或产品族。
- 给关注对象设置自定义名称。
- 给关注对象添加观察者备注。
- 设定是否启用 Alert。
- 内置关注项包括部分 Extra attention 签名和无人机类签名。

### 7.2 告警方式

- 视觉高亮新出现的关注设备。
- 声音提示/Beep。
- 语音提示。
- 选择语音内容：Class、Signature 或 Class + signature。
- 区分关注列表双响提示和 Hunt geiger tick。
- 可测试当前告警设置。
- 应用通知用于展示关注设备出现等状态。

## 8. 位置、地图与移动关联

### 8.1 位置记录

- 可选使用手机位置作为“hear-here”观测位置。
- 为日志行和 sit 记录观测时的纬度、经度和时间。
- 使用最后一个有效位置；过旧的位置不会继续作为当前有效位置。
- 位置只代表手机听到设备时的位置，不代表设备真实位置。
- 支持记录手机行走路径。
- 可计算路径长度、空间跨度和位置聚类。

### 8.2 Moving with you / 可能伴随

- 主要针对 BLE 目标。
- 根据多个时间点、设备出现持续性、RSSI/位置变化和手机路径进行启发式判断。
- 以“Moving with you”“possible tail”等语言表达为假设性提示。
- 不对 Wi-Fi AP 使用该判断。
- 结果不是跟踪确认、身份确认或法律结论。

### 8.3 Remote ID 与位置来源

- 解析无人机广播中的飞行器位置、UAS ID、飞行状态、运动状态等字段。
- 在数据存在时解析飞手/操作员位置。
- 区分手机听到的位置、广播的飞行器位置和飞手位置。
- 保存同一 UAS ID 的广告位置短轨迹。
- 轨迹与手机路径在距离范围内时可叠加在同一地图上。
- 远离手机路径的飞行器可单独绘制轨迹图。
- 无法解析位置或无有效 UAS ID 时不创建相应轨迹。

### 8.4 地图和路径图

- Reports → Path 显示手机观测路径。
- 以起点、终点/当前点和设备告警点绘制路径。
- MAC 告警和签名告警按最强听到位置绘制。
- 同一位置多个目标可聚合显示数量。
- 支持点击地图图标打开对应设备或聚合列表。
- 广播位置用虚线轨迹显示。
- 飞手位置使用人物图标显示。
- 路径报告保留较小观测范围，短路径也能正常显示。
- Debrief 和 Compare PDF 生成相应的纸张路径图。
- Privacy mode 不隐藏 Path/Debrief/Compare 的地图，但仍掩码 MAC、坐标和街道信息，并暂停 TAK / CoT。

## 9. 日志与本地数据

### 9.1 实时日志

- 记录发现事件和设备聚合数据。
- 记录 Wi-Fi / BLE 类型、时间、设备标识、RSSI 和可用无线电事实。
- 记录匹配签名、Extra attention、解码字段和位置（若开启位置标记）。
- 记录 Remote ID、飞行器轨迹和飞手位置（数据存在时）。
- 设备离开实时列表后仍可在日志和 sit 中保留。
- 支持重放最近日志用于报告和分析。

### 9.2 Named sit

- 可选手动开始一个命名观测时段。
- 开始时设置名称；名称有长度限制和默认名称。
- 开始后持续收集该时段内的设备、路径和位置。
- Debrief 和 AI Export 优先使用当前打开的 sit，而不是默认的最近 15 分钟。
- 可结束当前 sit。
- 可重命名已保存 sit。
- 可打开/选择历史 sit。
- 可删除单个 sit。
- 可删除全部保存的 sit。
- 对单个 sit 的唯一无线电数量有限制，当前版本上限为 6000；低内存保护仍可能提前丢弃数据。
- 未命名的旋转 BLE 设备在低内存或容量保护下优先被丢弃。

### 9.3 日志清理

- Reports 页面提供清除日志/重置能力。
- 清除操作需要确认。
- 清除日志不应误删签名目录、设置备份或已独立保存的 sit（具体行为以当前实现为准）。

## 10. Reports 报告

### 10.1 Debrief

- 根据当前 sit、选中的历史 sit 或最近 15 分钟生成观察总结。
- 生成纯文本/Markdown 风格的 Debrief 内容。
- 汇总观测时间窗口、设备数量、Wi-Fi/BLE 数量、签名类别、关注目标和 Extra attention。
- 汇总设备位置、路径、移动伴随提示和 Remote ID 信息。
- 默认可隐藏未匹配的旋转 BLE 设备，用户可打开“Show unmatched rotating BLE”。
- 保留关注目标、命名签名、书签、载荷位置和 sit 导出中的未匹配设备信息。
- 输出实验性语言和免责声明。
- 支持分享 Debrief 文本。
- 支持生成/分享 Debrief PDF。

### 10.2 Compare

- 选择两个 sit 进行对比。
- 对比两个时段的设备、签名、告警和位置路径。
- 指出设备在两个时段之间的出现、消失或变化。
- 对解码字段值在两个 sit 之间的变化进行描述。
- 生成对比文本和 PDF 图形。
- 第二个 sit 的路径使用独立颜色/虚线展示。

### 10.3 Path

- 生成当前 sit、选中历史 sit 或最近 15 分钟的地图路径报告。
- 显示手机移动路径、告警设备、签名告警和 Remote ID 广播轨迹。
- 支持点击路径上的设备点查看设备信息。
- 支持显示聚合点中的多个设备。
- 使用与 Debrief/Compare 一致的路径数据和图形规则。

### 10.4 AI Export

- 从 Debrief、Compare 或单个设备详情生成面向 AI/分析工具的结构化文本。
- 包含设备、签名、时间、RSSI、位置、轨迹、告警和解码信息。
- 根据 Privacy mode 输出掩码后的可分享内容。
- 支持分享当前 sit、两个 sit 的比较结果或单个设备信息。
- 输出包含实验性结论免责声明，不应被当作自动化身份或法律判断。

### 10.5 Sit 导出

支持导出当前或保存 sit 的：

- CSV。
- JSON Lines（JSONL）。
- GPX。
- KML。
- WiGLE 兼容格式/数据。

Sit 导出可包含：

- 无线电设备记录。
- 匹配签名和 Extra attention 家族名称。
- MAC、RSSI、时间和位置。
- 广播载荷位置、UAS ID 和轨迹相关数据（存在时）。

### 10.6 普通日志导出

- 支持 CSV 和 JSON 两种日志格式。
- 可选择 Wi-Fi radios、BLE radios 或全部 radios。
- 支持分享导出结果。
- 支持保存到系统文件/存储位置。
- 自动生成建议文件名、MIME 类型和分享标题。
- 导出前显示当前日志范围和内容说明。

## 11. 签名目录管理

- 查看当前 Catalog 版本号。
- 内置 stock signatures。
- 导出完整签名目录，包括 stock 和用户新增/编辑内容。
- 将签名保存到文件或系统存储。
- 从文件导入签名。
- 导入时追加新规则，不删除现有目录。
- 相同 ID 或相同匹配规则的签名跳过，支持重复导入同一包。
- 从 GitHub 更新 stock catalog。
- 更新 stock catalog 时替换 stock rows，但保留用户书签、设置和自定义签名。
- GitHub 更新需要网络；无网络时可使用文件导入。
- Restore defaults 可恢复默认目录，但会清除自定义内容（使用前需要明确警告）。
- 新 catalog 可增加解码字段；旧版本导入后会忽略不认识的新键，但基础签名仍可匹配。

## 12. 设置功能

### 12.1 扫描设置

- Wi-Fi 扫描开关/状态。
- BLE 扫描开关/状态。
- 扫描强度：Saver、Balanced、Performance。
- 显示扫描错误、扫描器不可用和系统节流状态。
- 解释系统扫描频率限制和可能的等待时间。
- 扫描持续运行时支持后台任务/前台通知机制（Android 版本通过前台服务实现）。

### 12.2 显示设置

- Live 默认显示模式。
- 显示 RSSI 条。
- 显示签名名称。
- 显示频率/信道。
- 显示 First seen / Last seen。
- 雷达动画与扫描束显示。
- 深色主题。
- 保持屏幕常亮。
- 新关注目标出现时跳转。

### 12.3 关注与声音设置

- Watchlist alerts 总开关。
- Watchlist beep 开关。
- Watchlist voice 开关。
- 语音内容选择：Class / Signature / Class + signature。
- Hunt 声音反馈开关。
- 测试声音/语音。

### 12.4 Location 设置

- 位置标记总开关。
- 使用位置记录日志、sit、Debrief 和导出。
- 说明位置是手机听到无线电时的位置，而非无线电设备位置。
- 位置权限未授权或位置服务关闭时显示状态。
- 支持最近位置、轨迹和地点名称能力。

### 12.5 TAK / CoT 设置

- 开启或关闭 TAK / CoT UDP feed。
- 目标预设：
  - This phone：`127.0.0.1:10011`。
  - LAN multicast：`239.2.3.1:6969`。
  - Custom：用户指定主机和端口。
- 仅支持 UDP；不把 TAK Server TCP `8087` 当作此 feed。
- 显示 pins on feed、最近发送状态、目标地址、错误和时间。
- 发布手机自身位置心跳。
- 发布 hear-here、广告位置和飞手位置标记。
- 对标记生成稳定 UID、callsign、类型、颜色和失效时间。
- hear-here 标记保留最强信号/最近接近点；周期性刷新同一坐标防止 ATAK 认为标记过期。
- Remote ID 飞行器使用稳定 UAS ID，不使用旋转 BLE MAC 作为移动飞行器身份。
- 设备离开后发送删除/过期事件，避免 ATAK 长时间保留旧标记。
- 地图标记可显示简短 remarks 卡片：callsign、无线电类型、MAC、RSSI、位置来源、签名和 Extra attention。
- Privacy mode 开启时暂停 TAK / CoT，避免发送完整 MAC 和坐标。

### 12.6 隐私设置

- Privacy mode。
- 分享文本中掩码 MAC 尾部。
- 分享内容中掩码 GPS 坐标。
- 隐藏街道名称。
- 暂停 TAK / CoT feed。
- 说明：本机日志仍保留完整坐标和原始信息，Privacy mode 主要作用于屏幕显示、报告和外发内容。
- 导出、Debrief、AI Export、设备详情分享和 TAK 外发都可能把信息带离设备，用户需自行负责存储和传播。

### 12.7 设置备份

- 导出设置。
- 将设置保存到文件/存储。
- 从文件导入设置。
- 导出的内容包括：
  - 设置开关。
  - 当前过滤器。
  - 过滤预设。
  - 命名设备。
  - 签名关注项。
- 不包括：catalog、日志和 GPS 记录。
- 导入设置会替换本机对应设置，但不替换 catalog。
- 完成和失败显示确认/错误对话框。

## 13. 数据安全与本地化

- 不依赖 Fieldwatch 云端后端。
- 扫描、聚合、过滤、签名匹配和报告主要在本地完成。
- 位置、日志、sit、设置和签名目录保存在本机。
- 分享、保存和外发由用户主动触发。
- 通过系统分享/文件选择器输出文件。
- 应用使用文件提供器或等价机制安全地向其他应用共享文件。
- 地点名称可能通过系统地理编码服务获取，不代表 Fieldwatch 自有云服务。
- 需要支持旧签名包和旧配置字段的兼容导入。

## 14. Android 版本所需系统能力

Android 实现使用或声明了以下系统能力，HarmonyOS 迁移时需要逐项寻找对应 API 或重新设计：

- Wi-Fi 扫描与 Wi-Fi 状态读取。
- Bluetooth LE 扫描。
- 附近设备相关权限。
- 精确/粗略位置权限。
- 后台持续运行和前台服务通知。
- 通知、振动和音频/语音播报。
- 唤醒锁/保持屏幕常亮。
- 网络访问，用于 catalog 更新和系统地理编码。
- 文件选择、保存和系统分享。
- UDP 网络通信。
- 位置更新与路径记录。
- 电池优化/后台限制提示。

HarmonyOS 版本不得直接照搬 Android Manifest、Foreground Service、FileProvider 或 Compose 实现，而应基于 NGF 和 HarmonyOS 官方能力重新映射。

## 15. 已有领域模块对应关系

Android 源码中的主要能力模块如下，后续可作为鸿蒙业务模块拆分参考：

| Android 模块 | 主要职责 |
|---|---|
| `radio/BleRadio.kt` | BLE 扫描启动、停止、强度和错误状态 |
| `radio/WifiRadio.kt` | Wi-Fi 扫描和结果接收 |
| `radio/BleAdParser.kt` | BLE 广播解析 |
| `radio/WifiIeParser.kt` | Wi-Fi IE 解析 |
| `radio/ScanService.kt` | 扫描生命周期和后台运行 |
| `domain/Models.kt` | 无线电、设备、设置、签名、过滤、日志等模型 |
| `domain/SignatureEngine.kt` | 签名匹配引擎 |
| `domain/SignatureFieldDecoder.kt` | 广播字段解码和 Named values |
| `domain/FilterEngine.kt` | 过滤表达式和默认预设 |
| `domain/DeviceExplain.kt` | 设备信息解释和可读化 |
| `domain/AdvPayloadDecoder.kt` | 广播载荷解码 |
| `domain/OpenDroneId.kt` | Remote ID/Open Drone ID 解析 |
| `domain/FastPair.kt` | Fast Pair 检测 |
| `domain/Hunt.kt` | Hunt 状态和信号逻辑 |
| `domain/Geo.kt` | 距离、路径、网格和地理计算 |
| `domain/Sit.kt` | 命名观测时段和 sit 会话 |
| `domain/SitDiff.kt` | 两个 sit 的差异比较 |
| `domain/SitPathPlot.kt` | 路径图和告警点布局 |
| `domain/AircraftTrail.kt` | 广播飞行器轨迹和飞手标记 |
| `domain/DebriefReport.kt` | Debrief 报告模型和文本 |
| `domain/DebriefPrompt.kt` | Debrief/分析提示文本 |
| `domain/SitExport.kt` | CSV、JSONL、GPX、KML、WiGLE 导出 |
| `domain/TakPublish.kt` | TAK/CoT 标记选择、UID、XML 和 UDP 发布规则 |
| `data/DeviceStore.kt` | 当前设备状态和日志聚合存储 |
| `data/LogStore.kt` | 日志保存、加载和清理 |
| `data/SitStore.kt` | sit 持久化和路径刷盘 |
| `data/ConfigStore.kt` | 设置、过滤器、关注项和签名配置 |
| `data/CatalogRemote.kt` | GitHub stock catalog 更新 |
| `data/PlaceLookup.kt` | 地点名称查询 |
| `data/DebriefPdf.kt` | Debrief/Compare PDF 生成 |
| `data/PathTiles.kt` | 地图/路径底图或切片支持 |
| `alert/Alerter.kt` | 声音、语音、通知和告警反馈 |
| `ui/FieldwatchAppUi.kt` | 顶层导航、权限、导出和页面组合 |
| `ui/FieldwatchViewModel.kt` | UI 状态、扫描状态、导出和业务动作编排 |

## 16. 迁移到 NGF 的功能分层建议

### 16.1 可优先迁移的纯领域能力

以下能力与 Android UI/系统服务耦合较低，适合优先用 ArkTS 重写并加入业务模块：

- 无线电、设备、签名、过滤、日志、sit 等数据模型。
- 签名匹配和字段解码。
- FilterEngine。
- RSSI 分级和趋势计算。
- Geo 距离、路径和聚合计算。
- Hunt 状态机。
- Remote ID / Fast Pair / DULT 等纯数据解析。
- Sit 差异比较。
- CSV/JSONL/GPX/KML/WiGLE 序列化。
- Debrief、AI Export 和隐私掩码规则。
- TAK marker 选择、UID 和 CoT XML 生成。

### 16.2 应复用 NGF 的基础设施

- 设置和持久化：复用 NGF data 层的 Settings/Storage/Database Facade。
- 日志：使用 `import { logger } from 'ngf_framework'` 及 NGF 既有日志风格。
- 网络与 catalog 更新：复用 NGF contentSource/network 能力。
- 后台任务：评估 NGF systemTasks/workflow 能力，不在页面层自建隐式常驻任务。
- 权限、窗口、主题、导航、文件选择和分享：复用 NGF platformOhos/uiShell 能力。
- 测试：遵守 `@ohos/hypium` 和 NGF 的 `entry/src/test`、`entry/src/ohosTest` 约定。

### 16.3 需要重新验证的 HarmonyOS 系统能力

- Wi-Fi 被动扫描 API 是否能提供 Android 版本所需字段和频率。
- BLE 扫描回调、广播原始数据和地址随机化行为。
- 位置权限、后台位置和持续路径记录限制。
- 后台长时任务与通知能力。
- UDP socket 和局域网组播。
- 系统文件选择、保存、分享和 PDF 生成。
- 地图、路径绘制和离线地图方案。
- 语音播报、声音、振动和通知。
- 应用切后台、电量策略和扫描频率限制。

## 17. 明确的非目标与限制

- 不保证发现所有附近设备。
- 不把签名匹配当作设备身份认证。
- 不把 GPS 共行判断当作跟踪确认。
- 不提供专业无线电测向能力。
- 不主动连接、攻击、干扰或控制被观察设备。
- 不把手机观测位置等同于目标设备位置。
- 不保证系统暴露所有 BLE 原始广播或 Wi-Fi IE。
- 不默认提供 Fieldwatch 云端账号、服务器或远程数据库。
- Android 的实现细节不能直接视为 HarmonyOS API 行为。

## 18. 鸿蒙版验收总清单

后续每个功能模块完成后，应至少确认：

- 功能是否与本清单中的 Android 基线等价，或是否记录了平台差异。
- 是否放在 NGF 业务层，未把 Fieldwatch 专属逻辑污染到共享框架层。
- 是否使用 ArkTS 类型安全写法，避免 `any`、`unknown` 和未类型化对象。
- 是否复用 NGF 已有的存储、日志、网络、任务、导航和 UI 能力。
- 是否设计了无权限、系统能力不可用、扫描失败、后台受限和无数据等状态。
- 是否保护 MAC、坐标、广播原始数据和导出文件的隐私边界。
- 是否为纯领域逻辑补充 Hypium 单元测试。
- 是否为关键页面、权限流程和扫描生命周期补充设备集成测试。
- 是否在 HarmonyOS 官方文档确认后再使用系统 API。
- 是否在交付记录中说明尚未验证的真机能力和平台差异。

## 19. 参考来源

- `Fieldwatch/README.md`
- `Fieldwatch/CHANGELOG.md`
- `Fieldwatch/dist/Fieldwatch_User_Manual.pdf`
- `Fieldwatch/app/src/main/java/app/fieldwatch/domain/`
- `Fieldwatch/app/src/main/java/app/fieldwatch/data/`
- `Fieldwatch/app/src/main/java/app/fieldwatch/radio/`
- `Fieldwatch/app/src/main/java/app/fieldwatch/ui/`
- `Fieldwatch/app/src/test/java/app/fieldwatch/`

本清单是鸿蒙版本的功能基线；后续若发现源码与文档不一致，应以实际源码行为为准，并在本文件中补充差异说明。