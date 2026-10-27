
## fieldwatch/application/FieldwatchApplication.ets  (60)
  268 | ' 扫描强度='
      ctx: + ' 扫描强度=' + this.state.settings.scanIntensity + ' 屏幕常亮=' + this.state.settings.keepScreenOn.toString());
  523 | ' / 公司 0x004C -> '
      ctx: + ' / 公司 0x004C -> ' + this.radioDb.company(0x004C));
 1626 | '# Fieldwatch AI 补充说明 / AI Export addendum'
      ctx: lines.push('# Fieldwatch AI 补充说明 / AI Export addendum');
 1628 | '实验性用途。Fieldwatch 是只接收的被动监听工具，不做关联、不做注入、不连云。'
      ctx: lines.push('实验性用途。Fieldwatch 是只接收的被动监听工具，不做关联、不做注入、不连云。');
 1650 | '**Takeaway (required, last line).** One sentence starting with 要点： that adds one number.'
      ctx: lines.push('**Takeaway (required, last line).** One sentence starting with 要点： that adds one number.');
 1700 | '# Fieldwatch AI 对比补充说明 / Compare addendum'
      ctx: lines.push('# Fieldwatch AI 对比补充说明 / Compare addendum');
 1712 | '**Takeaway (required, last line).** One sentence starting with 要点：.'
      ctx: lines.push('**Takeaway (required, last line).** One sentence starting with 要点：.');
 1721 | '本次观测: '
      ctx: lines.push('本次观测: ' + current.length.toString() + ' 台信号源');
 1722 | '没有可对比的第二段观测。'
      ctx: lines.push(saved === undefined ? '没有可对比的第二段观测。' : ('第二段观测: ' + saved.name + ' · ' + saved.radioCount.toString() + ' 台'));
 1723 | '只比较在场情况 —— 仅在本次、仅在第二段、两者都在。'
      ctx: lines.push('只比较在场情况 —— 仅在本次、仅在第二段、两者都在。');
 1997 | 'Fieldwatch 设备详情'
      ctx: out.push('Fieldwatch 设备详情');
 1999 | '实验性输出。不是法律意义上的身份。这是系统暴露出来的内容，不代表一定存在追踪器或摄像头。'
      ctx: out.push('实验性输出。不是法律意义上的身份。这是系统暴露出来的内容，不代表一定存在追踪器或摄像头。');
 2005 | '## 身份'
      ctx: out.push('## 身份');
 2006 | '信号源: '
      ctx: out.push('信号源: ' + (sighting.kind === RadioKind.WIFI ? 'Wi-Fi 接入点（在广播网络）' : (sighting.kind === RadioKind.NEARLINK ? '星闪广播源' : '蓝牙低功耗广播源')));
 2007 | '厂商: '
      ctx: out.push('厂商: ' + this.vendorOfSighting(sighting));
 2009 | '## 信号'
      ctx: out.push('## 信号');
 2010 | '此处强度 (RSSI): '
      ctx: out.push('此处强度 (RSSI): ' + sighting.rssi.toString() + ' dBm');
 2011 | '本次会话听到的强度范围: '
      ctx: out.push('本次会话听到的强度范围: ' + sighting.rssiMin.toString() + ' ~ ' + sighting.rssiMax.toString() + ' dBm');
 2012 | '声明的发射功率: '
      ctx: if (sighting.facts.txPower > -128) out.push('声明的发射功率: ' + sighting.facts.txPower.toString() + ' dBm');
 2013 | '频率: '
      ctx: if (sighting.facts.frequencyMhz > 0) out.push('频率: ' + sighting.facts.frequencyMhz.toString() + ' MHz');
 2015 | '## 本次会话'
      ctx: out.push('## 本次会话');
 2016 | '首次出现: '
      ctx: out.push('首次出现: ' + new Date(sighting.firstSeen).toLocaleString());
 2017 | '最后出现: '
      ctx: out.push('最后出现: ' + new Date(sighting.lastSeen).toLocaleString());
 2018 | '命中次数: '
      ctx: out.push('命中次数: ' + sighting.count.toString());
 2020 | '最后定位: '
      ctx: out.push('最后定位: ' + sighting.location.latitude.toFixed(5) + ', ' + sighting.location.longitude.toFixed(5));
 2021 | '最后定位是听到它时手机的位置，不是这台信号源的位置。'
      ctx: out.push('最后定位是听到它时手机的位置，不是这台信号源的位置。');
 2023 | '匹配的特征: '
      ctx: if (names.length > 0) out.push('匹配的特征: ' + names.join('; '));
 2024 | '原始广播: '
      ctx: if (sighting.facts.rawAdHex.length > 0) out.push('原始广播: ' + sighting.facts.rawAdHex);
 2038 | '> 实验性功能。不构成法律意义上的身份认定。'
      ctx: out.push('> 实验性功能。不构成法律意义上的身份认定。');
 2040 | '你是一位射频 / 隐私分析专家，熟悉 IEEE OUI、蓝牙 SIG 分配号、GAP Appearance、蓝牙广播格式与 Wi-Fi 信标。'
      ctx: out.push('你是一位射频 / 隐私分析专家，熟悉 IEEE OUI、蓝牙 SIG 分配号、GAP Appearance、蓝牙广播格式与 Wi-Fi 信标。');
 2042 | '用户希望从一条 Fieldwatch 观测中尽可能了解**这一台**无线电。Fieldwatch 是仅接收的被动观测工具。'
      ctx: out.push('用户希望从一条 Fieldwatch 观测中尽可能了解**这一台**无线电。Fieldwatch 是仅接收的被动观测工具。');
 2044 | '必须遵守的约束：'
      ctx: out.push('必须遵守的约束：');
 2045 | '- 这是**一台**广播设备，不是人、车辆或法律身份。'
      ctx: out.push('- 这是**一台**广播设备，不是人、车辆或法律身份。');
 2046 | '- Wi-Fi 行**只有接入点**。关联的客户端不可见。'
      ctx: out.push('- Wi-Fi 行**只有接入点**。关联的客户端不可见。');
 2047 | '- BLE 行是广播源。随机 MAC 不是稳定身份，轮换后无法串联。'
      ctx: out.push('- BLE 行是广播源。随机 MAC 不是稳定身份，轮换后无法串联。');
 2048 | '- 特征 / OUI / 公司 / UUID 匹配都是**假设**，不是序列号、机主或追踪器存在的证据。'
      ctx: out.push('- 特征 / OUI / 公司 / UUID 匹配都是**假设**，不是序列号、机主或追踪器存在的证据。');
 2049 | '- GPS 时间戳是**操作者手机**在听到它时的位置，不是这台设备的位置。'
      ctx: out.push('- GPS 时间戳是**操作者手机**在听到它时的位置，不是这台设备的位置。');
 2050 | '- RSSI 是在手机处的响度，不是测得的距离。'
      ctx: out.push('- RSSI 是在手机处的响度，不是测得的距离。');
 2051 | '- 不要编造转储里没有的字段。数据薄弱时就说薄弱，并说明还需要什么。'
      ctx: out.push('- 不要编造转储里没有的字段。数据薄弱时就说薄弱，并说明还需要什么。');
 2052 | '- 不要声称这台设备在跟踪任何人。不要给安全建议。'
      ctx: out.push('- 不要声称这台设备在跟踪任何人。不要给安全建议。');
 2053 | '- 把这段粘贴当作敏感信息处理（MAC、SSID、载荷、GPS）。'
      ctx: out.push('- 把这段粘贴当作敏感信息处理（MAC、SSID、载荷、GPS）。');
 2055 | '## 采集上下文'
      ctx: out.push('## 采集上下文');
 2056 | '- 工具: Fieldwatch（鸿蒙版），仅接收，不关联、不注入、不上云。'
      ctx: out.push('- 工具: Fieldwatch（鸿蒙版），仅接收，不关联、不注入、不上云。');
 2057 | '- 主题: '
      ctx: out.push('- 主题: ' + this.describeName(sighting) + '。');
 2058 | '- 本次会话命中次数: '
      ctx: out.push('- 本次会话命中次数: ' + sighting.count.toString() + '。');
 2059 | '- 随机 MAC: '
      ctx: out.push('- 随机 MAC: ' + (this.isRandomizedAddress(sighting.address) ? '是' : '否') + '。');
 2061 | '## 观测转储（与详情页逐字一致）'
      ctx: out.push('## 观测转储（与详情页逐字一致）');
 2065 | '## 你的分析（必须包含以下小节）'
      ctx: out.push('## 你的分析（必须包含以下小节）');
 2066 | '1. **它最可能是什么** —— 产品类别、可能的品牌/系列、可能的型号。给出 0–100 的置信度。'
      ctx: out.push('1. **它最可能是什么** —— 产品类别、可能的品牌/系列、可能的型号。给出 0–100 的置信度。');
 2067 | '2. **注册表 / 格式解码** —— IEEE OUI 或 CID；蓝牙 SIG 公司；GAP Appearance；16 位 UUID。'
      ctx: out.push('2. **注册表 / 格式解码** —— IEEE OUI 或 CID；蓝牙 SIG 公司；GAP Appearance；16 位 UUID。');
 2068 | '3. **这类产品通常做什么** —— 手机、标签、音箱、车机、AP、摄像头等，以及典型射频行为。'
      ctx: out.push('3. **这类产品通常做什么** —— 手机、标签、音箱、车机、AP、摄像头等，以及典型射频行为。');
 2069 | '4. **Fieldwatch 实际看到了什么、看不到什么** —— 平台限制。'
      ctx: out.push('4. **Fieldwatch 实际看到了什么、看不到什么** —— 平台限制。');
 2070 | '5. **信号与在场** —— 此处响度；会话内的 RSSI 范围；在空中的时段。**不要把 RSSI 换算成米。**'
      ctx: out.push('5. **信号与在场** —— 此处响度；会话内的 RSSI 范围；在空中的时段。**不要把 RSSI 换算成米。**');
 2071 | '6. **特征匹配** —— 命中的特征当作筛选命中，不是身份。说明载荷是否支持这个匹配。'
      ctx: out.push('6. **特征匹配** —— 命中的特征当作筛选命中，不是身份。说明载荷是否支持这个匹配。');
 2072 | '7. **待解问题** —— 还需要什么额外观测才能提高或降低置信度。'
      ctx: out.push('7. **待解问题** —— 还需要什么额外观测才能提高或降低置信度。');
 2073 | '8. **不能得出的结论** —— 简明列出转储**不**支持的结论（机主、跟踪、法律身份、距离）。'
      ctx: out.push('8. **不能得出的结论** —— 简明列出转储**不**支持的结论（机主、跟踪、法律身份、距离）。');
 2075 | '最后用一行给出**要点**（这台无线电最可能是什么，以及下一步该查什么）。不要给安全建议。'
      ctx: out.push('最后用一行给出**要点**（这台无线电最可能是什么，以及下一步该查什么）。不要给安全建议。');
 2154 | ' | 实时列表 '
      ctx: + ' | 实时列表 ' + this.state.sightings.length.toString() + ' 条');
 2251 | ' 条（上限 '
      ctx: + this.state.sightings.length.toString() + ' 条（上限 ' + target.toString() + '）');
 2543 | '测试设备'
      ctx: this.watchAlert.speak('测试设备', '测试签名', parseVoiceWhat(this.state.settings.watchVoiceWhat));

## fieldwatch/data/FieldwatchSettingsRepository.ets  (1)
  225 | '预设 1'
      ctx: const migrated: FilterPreset[] = [new FilterPreset('预设 1', legacy)];

## fieldwatch/domain/FieldwatchCandidateEngine.ets  (22)
  156 | '已标记'
      ctx: return new SignatureFamilyHint(FamilyVerdict.TAGGED, '已标记',
  157 | '匹配到特征 '
      ctx: '匹配到特征 ' + matchedNames.join('、')
  158 | '。第二条特征仍可能同时标记这台无线电（服务 UUID、产品 OUI）。'
      ctx: + '。第二条特征仍可能同时标记这台无线电（服务 UUID、产品 OUI）。', 0, '');
  162 | '仅此一台'
      ctx: return new SignatureFamilyHint(FamilyVerdict.SINGLE, '仅此一台',
  163 | '没有可聚类的空中唯一 ID。随机地址、家用型名称与通用芯片会被跳过。'
      ctx: '没有可聚类的空中唯一 ID。随机地址、家用型名称与通用芯片会被跳过。', 0, '');
  183 | '仅此一台'
      ctx: return new SignatureFamilyHint(FamilyVerdict.SINGLE, '仅此一台',
  184 | '在场设备里没有别的 MAC 共享这个空中唯一 ID。从这里建的签名基本只标到这一个地址。'
      ctx: '在场设备里没有别的 MAC 共享这个空中唯一 ID。从这里建的签名基本只标到这一个地址。',
  192 | '强特征族'
      ctx: strong ? '强特征族' : '可能的特征族',
  193 | '在场有 '
      ctx: '在场有 ' + bestCount.toString() + ' 台共享同一个' + kindLabel + '。'
  194 | '这是目录级模式，不是单个 MAC。'
      ctx: + (strong ? '这是目录级模式，不是单个 MAC。' : '样本偏薄 —— 可能是目录级模式。'),
  200 | '名称模式'
      ctx: if (kind === CandidateRuleKind.NAME_GLOB) return '名称模式';
  201 | '厂商 IE'
      ctx: if (kind === CandidateRuleKind.VENDOR_IE) return '厂商 IE';
  202 | '服务 UUID'
      ctx: if (kind === CandidateRuleKind.SERVICE_UUID) return '服务 UUID';
  203 | '厂商数据前缀'
      ctx: if (kind === CandidateRuleKind.MANUFACTURER_DATA) return '厂商数据前缀';
  205 | '空中唯一 ID'
      ctx: return '空中唯一 ID';
  339 | '个 AP'
      ctx: const word: string = cluster.radioKind === RadioKind.WIFI ? '个 AP' : '个广播源';
  340 | ' 在日志中命中 '
      ctx: candidate.notes = candidate.distinctRadios.toString() + ' ' + word + ' 在日志中命中 ' + this.ruleLabel(cluster.primary) + '。共享的空中 ID，不是单台 MAC。';
  348 | '同一名称通配在 '
      ctx: if (kind === CandidateRuleKind.NAME_GLOB) return '同一名称通配在 ' + count.toString() + ' 台信号源上 —— 不是家用 SSID。';
  349 | '同一 vendor IE 出现在 '
      ctx: if (kind === CandidateRuleKind.VENDOR_IE) return '同一 vendor IE 出现在 ' + count.toString() + ' 个 BSSID 上。不是 WPS / P2P。';
  350 | '同一服务 UUID 出现在 '
      ctx: if (kind === CandidateRuleKind.SERVICE_UUID) return '同一服务 UUID 出现在 ' + count.toString() + ' 个 BLE 广播源上。';
  351 | '同一制造商数据前缀出现在 '
      ctx: if (kind === CandidateRuleKind.MANUFACTURER_DATA) return '同一制造商数据前缀出现在 ' + count.toString() + ' 个 BLE 广播源上。';
  352 | '同一 IEEE OUI 出现在 '
      ctx: return '同一 IEEE OUI 出现在 ' + count.toString() + ' 个稳定 BSSID 上。不是芯片模组前缀。';

## fieldwatch/domain/FieldwatchChangelog.ets  (4)
   49 | '首个公开发布版本：实时雷达、强度 / 时间线 / 信号轨迹 / 分类四种视图与工具箱（信道分析、信号追踪、反追踪）'
      ctx: '首个公开发布版本：实时雷达、强度 / 时间线 / 信号轨迹 / 分类四种视图与工具箱（信道分析、信号追踪、反追踪）',
   50 | '611 条内置特征签名、候选特征发现与「添加到目录」；支持目录导出 / 导入 / 更新与恢复默认'
      ctx: '611 条内置特征签名、候选特征发现与「添加到目录」；支持目录导出 / 导入 / 更新与恢复默认',
   51 | '观测会话（开始 / 结束 / 对比）、CSV / JSONL / GPX / KML / WiGLE 导出与复盘 PDF'
      ctx: '观测会话（开始 / 结束 / 对比）、CSV / JSONL / GPX / KML / WiGLE 导出与复盘 PDF',
   52 | '隐私模式（地址脱敏）与严格离线：除主动更新特征目录外不产生任何联网'
      ctx: '隐私模式（地址脱敏）与严格离线：除主动更新特征目录外不产生任何联网'

## fieldwatch/domain/FieldwatchDeviceExplain.ets  (99)
   71 | '有限可发现：正在短暂寻找附近的连接。'
      ctx: if ((flags & 0x01) !== 0) parts.push('有限可发现：正在短暂寻找附近的连接。');
   72 | '可发现：其它 BLE 设备能找到它。'
      ctx: if ((flags & 0x02) !== 0) parts.push('可发现：其它 BLE 设备能找到它。');
   73 | '仅 BLE：不支持经典蓝牙（耳机／传文件那条射频）。'
      ctx: if ((flags & 0x04) !== 0) parts.push('仅 BLE：不支持经典蓝牙（耳机／传文件那条射频）。');
   74 | '除 BLE 外，可能也支持经典蓝牙（BR/EDR）。'
      ctx: else parts.push('除 BLE 外，可能也支持经典蓝牙（BR/EDR）。');
   75 | '双模芯片：BLE 与经典蓝牙可同时工作。'
      ctx: if ((flags & 0x08) !== 0 || (flags & 0x10) !== 0) parts.push('双模芯片：BLE 与经典蓝牙可同时工作。');
   81 | ' —— 长距离 BLE（更慢、更远）'
      ctx: if (label.indexOf('Coded') >= 0) return label + ' —— 长距离 BLE（更慢、更远）';
   82 | ' —— 更快的 BLE（蓝牙 5）'
      ctx: if (label.indexOf('2M') >= 0) return label + ' —— 更快的 BLE（蓝牙 5）';
   83 | ' —— 标准 BLE 无线电'
      ctx: if (label.indexOf('1M') >= 0) return label + ' —— 标准 BLE 无线电';
   97 | '本地管理 BSSID。车载、Mesh 与访客 AP 常长期保留这个地址，不是手机那种轮换 MAC。'
      ctx: return '本地管理 BSSID。车载、Mesh 与访客 AP 常长期保留这个地址，不是手机那种轮换 MAC。';
   99 | '公开的出厂地址（稳定，由 IEEE 分配）。'
      ctx: if (type === 'public' && !randomized) return '公开的出厂地址（稳定，由 IEEE 分配）。';
  100 | '随机／隐私地址。MAC 会变化，因此不是持久的身份标识。'
      ctx: if (type === 'random' || randomized) return '随机／隐私地址。MAC 会变化，因此不是持久的身份标识。';
  101 | ' · 通用 IEEE 地址（稳定的 OUI）。'
      ctx: if (type.length > 0) return type + ' · 通用 IEEE 地址（稳定的 OUI）。';
  102 | '通用 IEEE 地址（稳定的 OUI）。'
      ctx: return '通用 IEEE 地址（稳定的 OUI）。';
  107 | '不可用'
      ctx: if (!this.measured(rssi)) return '不可用';
  108 | '很强'
      ctx: if (rssi >= -45) return '很强';
  109 | '强'
      ctx: if (rssi >= -60) return '强';
  110 | '中等'
      ctx: if (rssi >= -75) return '中等';
  111 | '弱'
      ctx: if (rssi >= -88) return '弱';
  112 | '很弱'
      ctx: return '很弱';
  117 | '不可用'
      ctx: if (!this.measured(rssi)) return '不可用';
  123 | '不可用'
      ctx: if (!this.measured(min) && !this.measured(max)) return '不可用';
  149 | 'WPA3 密码（SAE 握手）'
      ctx: if (has('SAE') || has('WPA3')) bits.push('WPA3 密码（SAE 握手）');
  150 | '增强开放（加密但无密码）'
      ctx: if (has('OWE')) bits.push('增强开放（加密但无密码）');
  151 | 'WPA2 密码（PSK）'
      ctx: if (has('PSK') && has('WPA2')) bits.push('WPA2 密码（PSK）');
  152 | 'Wi-Fi 密码（WPA/PSK）'
      ctx: else if (has('PSK') || has('WPA')) bits.push('Wi-Fi 密码（WPA/PSK）');
  153 | '企业登录（802.1X）'
      ctx: if (has('802.1X') || has('EAP')) bits.push('企业登录（802.1X）');
  154 | 'WEP（老旧、脆弱）'
      ctx: if (has('WEP')) bits.push('WEP（老旧、脆弱）');
  155 | '开放网络，或加密方式未解析出来'
      ctx: if (has('ESS') && bits.length === 0) bits.push('开放网络，或加密方式未解析出来');
  156 | 'AES 加密'
      ctx: if (has('CCMP') || has('GCMP')) bits.push('AES 加密');
  157 | 'TKIP（较老、较弱的密码套件）'
      ctx: if (has('TKIP')) bits.push('TKIP（较老、较弱的密码套件）');
  158 | '已启用 WPS 配网'
      ctx: if (has('WPS')) bits.push('已启用 WPS 配网');
  159 | 'Mesh 节点'
      ctx: if (has('MESH')) bits.push('Mesh 节点');
  160 | '自组网（ad-hoc）'
      ctx: if (has('IBSS')) bits.push('自组网（ad-hoc）');
  161 | '基础设施接入点'
      ctx: if (has('ESS')) bits.push('基础设施接入点');
  173 | '连接基础服务'
      ctx: if (short === 0x1800) extra = '连接基础服务';
  174 | '属性协议'
      ctx: else if (short === 0x1801) extra = '属性协议';
  175 | '型号 / 序列号 / 固件'
      ctx: else if (short === 0x180A) extra = '型号 / 序列号 / 固件';
  176 | '电量'
      ctx: else if (short === 0x180F) extra = '电量';
  177 | '键盘、鼠标或手柄'
      ctx: else if (short === 0x1812) extra = '键盘、鼠标或手柄';
  178 | '心率传感器'
      ctx: else if (short === 0x180D) extra = '心率传感器';
  179 | '血压传感器'
      ctx: else if (short === 0x1810) extra = '血压传感器';
  180 | '温湿度一类环境传感器'
      ctx: else if (short === 0x181A) extra = '温湿度一类环境传感器';
  181 | 'LE 骑行功率／速度'
      ctx: else if (short === 0x1844 || short === 0x1845 || short === 0x1846) extra = 'LE 骑行功率／速度';
  183 | 'Google Fast Pair（多为耳机／音箱）'
      ctx: else if (short === 0xFE2C) extra = 'Google Fast Pair（多为耳机／音箱）';
  185 | 'Apple Find My 相关'
      ctx: else if (short === 0xFD44) extra = 'Apple Find My 相关';
  186 | 'Tile 追踪器'
      ctx: else if (short === 0xFEED || short === 0xFEDD) extra = 'Tile 追踪器';
  187 | '涂鸦 IoT'
      ctx: else if (short === 0xFD50) extra = '涂鸦 IoT';
  189 | 'HP 打印机'
      ctx: else if (short === 0xFE78) extra = 'HP 打印机';
  190 | 'Sonos 音箱'
      ctx: else if (short === 0xFE07) extra = 'Sonos 音箱';
  192 | 'ASSA ABLOY 门禁'
      ctx: else if (short === 0xFCBF) extra = 'ASSA ABLOY 门禁';
  193 | 'August Home 门锁'
      ctx: else if (short === 0xFE24) extra = 'August Home 门锁';
  195 | 'Apple（不是 ASSA ABLOY）'
      ctx: else if (short === 0xFCB2) extra = 'Apple（不是 ASSA ABLOY）';
  233 | 'Wi-Fi 接入点'
      ctx: const kindLabel: string = sighting.kind === RadioKind.WIFI ? 'Wi-Fi 接入点' : '蓝牙 LE 广播源';
  235 | '它确实在广播，但没有声明任何产品类别（没有 Appearance、Class of Device，也没有知名的服务）。'
      ctx: '它确实在广播，但没有声明任何产品类别（没有 Appearance、Class of Device，也没有知名的服务）。',
  249 | '未知广播源'
      ctx: return new ExplainGuess('未知广播源', '未知广播源', '线索不足。', ExplainConfidence.LOW, true);
  260 | '很可能是'
      ctx: const hedge: string = confidence === ExplainConfidence.HIGH ? '很可能是'
  261 | '可能是'
      ctx: : (confidence === ExplainConfidence.MEDIUM ? '可能是' : '也许是');
  263 | '这是设备自己广播的内容，不是视觉识别结果。'
      ctx: reasons.join('') + '这是设备自己广播的内容，不是视觉识别结果。', confidence, false);
  275 | '耳机或头戴耳机'
      ctx: bucket = 'audio-personal'; label = '耳机或头戴耳机'; weight = 7;
  277 | '音箱'
      ctx: bucket = 'audio-speaker'; label = '音箱'; weight = 7;
  278 | '鼠标'
      ctx: } else if (has('mouse')) { bucket = 'mouse'; label = '鼠标'; weight = 8;
  279 | '键盘'
      ctx: } else if (has('keyboard')) { bucket = 'keyboard'; label = '键盘'; weight = 8;
  280 | '游戏手柄'
      ctx: } else if (has('gamepad') || has('joystick')) { bucket = 'gamepad'; label = '游戏手柄'; weight = 7;
  281 | '手表或腕戴设备'
      ctx: } else if (has('watch')) { bucket = 'watch'; label = '手表或腕戴设备'; weight = 7;
  282 | '手机'
      ctx: } else if (has('phone')) { bucket = 'phone'; label = '手机'; weight = 6;
  284 | '电脑或平板'
      ctx: bucket = 'computer'; label = '电脑或平板'; weight = 6;
  285 | '查找标签 / 追踪器'
      ctx: } else if (has('tag') || has('keyring')) { bucket = 'tag'; label = '查找标签 / 追踪器'; weight = 6;
  286 | '遥控器'
      ctx: } else if (has('remote')) { bucket = 'remote'; label = '遥控器'; weight = 6;
  287 | '输入设备（键盘、鼠标之类）'
      ctx: } else if (has('hid')) { bucket = 'hid'; label = '输入设备（键盘、鼠标之类）'; weight = 4;
  288 | '心率监测器'
      ctx: } else if (has('heart')) { bucket = 'health'; label = '心率监测器'; weight = 7;
  290 | '健康传感器'
      ctx: bucket = 'health'; label = '健康传感器'; weight = 6;
  291 | '显示器或电视棒'
      ctx: } else if (has('display') || has('monitor')) { bucket = 'display'; label = '显示器或电视棒'; weight = 4;
  292 | '时钟'
      ctx: } else if (has('clock')) { bucket = 'clock'; label = '时钟'; weight = 5;
  293 | '智能眼镜'
      ctx: } else if (has('glasses')) { bucket = 'glasses'; label = '智能眼镜'; weight = 6;
  295 | '它声明的外观（Appearance）是 '
      ctx: return new ExplainHint(bucket, label, '它声明的外观（Appearance）是 ' + name + '。', weight);
  308 | '耳机或头戴耳机'
      ctx: if (minor === 1 || minor === 2 || minor === 6) { bucket = 'audio-personal'; label = '耳机或头戴耳机'; weight = 6; }
  309 | '音箱'
      ctx: else if (minor === 3 || minor === 4 || minor === 5 || minor === 7) { bucket = 'audio-speaker'; label = '音箱'; weight = 6; }
  310 | '音频设备'
      ctx: else { bucket = 'audio-personal'; label = '音频设备'; weight = 3; }
  313 | '鼠标'
      ctx: if (minor === 2) { bucket = 'mouse'; label = '鼠标'; weight = 7; }
  314 | '键盘'
      ctx: else if (minor === 1) { bucket = 'keyboard'; label = '键盘'; weight = 7; }
  315 | '输入设备'
      ctx: else if (minor === 3) { bucket = 'hid'; label = '输入设备'; weight = 5; }
  316 | '游戏手柄'
      ctx: else if (minor === 4 || minor === 5) { bucket = 'gamepad'; label = '游戏手柄'; weight = 6; }
  317 | '输入配件'
      ctx: else { bucket = 'hid'; label = '输入配件'; weight = 3; }
  320 | '手机'
      ctx: if (minor === 3 || minor === 4 || minor === 5) { bucket = 'phone'; label = '手机'; weight = 5; }
  323 | '电脑'
      ctx: if (minor === 3 || minor === 4) { bucket = 'computer'; label = '电脑'; weight = 5; }
  324 | '手表'
      ctx: else if (minor === 7) { bucket = 'watch'; label = '手表'; weight = 6; }
  327 | '健康传感器'
      ctx: if (minor === 2 || minor === 3 || minor === 4 || minor === 5) { bucket = 'health'; label = '健康传感器'; weight = 6; }
  333 | 'Class of Device 显示它是'
      ctx: return new ExplainHint(bucket, label, 'Class of Device 显示它是' + label + '。', weight);
  349 | '键盘、鼠标或手柄'
      ctx: if (id === 0x1812) out.push(new ExplainHint('hid', '键盘、鼠标或手柄', '它提供 HID（人机接口）服务。', 5));
  351 | 'LE Audio 耳机或音箱'
      ctx: out.push(new ExplainHint('audio-personal', 'LE Audio 耳机或音箱', '它提供蓝牙 LE Audio 服务。', 6));
  352 | '心率监测器'
      ctx: } else if (id === 0x180D) out.push(new ExplainHint('health', '心率监测器', '它提供心率服务。', 6));
  353 | '血压计'
      ctx: else if (id === 0x1810) out.push(new ExplainHint('health', '血压计', '它提供血压服务。', 6));
  354 | '环境传感器'
      ctx: else if (id === 0x181A) out.push(new ExplainHint('sensor', '环境传感器', '它提供环境感知服务。', 4));
  355 | '耳机或音箱'
      ctx: else if (id === 0xFE2C) out.push(new ExplainHint('audio-personal', '耳机或音箱', '带 Google Fast Pair（多见于耳机与音箱）。', 5));
  356 | 'SmartTag 服务 UUID。'
      ctx: else if (id === 0xFD5A) out.push(new ExplainHint('tag', 'Samsung SmartTag', 'SmartTag 服务 UUID。', 7));
  357 | 'Apple Find My 配件'
      ctx: else if (id === 0xFD44) out.push(new ExplainHint('tag', 'Apple Find My 配件', 'Find My 相关 UUID。', 6));
  358 | 'Tile 追踪器'
      ctx: else if (id === 0xFEED || id === 0xFEDD) out.push(new ExplainHint('tag', 'Tile 追踪器', 'Tile 服务 UUID。', 7));
  378 | '匹配到特征 '
      ctx: '匹配到特征 ' + name + '。', weight));
  387 | '隐藏 SSID 的接入点'
      ctx: out.push(new ExplainHint('wifi-hidden', '隐藏 SSID 的接入点', '它在广播但刻意不公布网络名。', 4));

## fieldwatch/domain/FieldwatchRadioDb.ets  (7)
  164 | ' 条, MA-S '
      ctx: + ' 条, MA-S ' + this.masKeys.length.toString() + ' 条, 名称 ' + nameCount.toString() + ' 个');
  174 | '未载入'
      ctx: if (!this.ready) return '未载入';
  178 | ' 首键='
      ctx: + ' 首键=' + firstKey.toString(16) + ' 末键=' + lastKey.toString(16)
  181 | ' 名称数='
      ctx: + ' 名称数=' + (this.nameOff.length - 1).toString()
  182 | ' 名0=['
      ctx: + ' 名0=[' + this.nameAt(0) + ']'
  183 | ' 名1=['
      ctx: + ' 名1=[' + this.nameAt(1) + ']'
  184 | ' 池长='
      ctx: + ' nstr=' + this.nameStart.toString() + ' 池长=' + (this.nameEnd - this.nameStart).toString();

## fieldwatch/domain/FieldwatchWidgetState.ets  (10)
   76 | ' 秒前'
      ctx: if (seconds < 60) return seconds.toString() + ' 秒前';
   77 | ' 分钟前'
      ctx: if (seconds < 3600) return Math.round(seconds / 60).toString() + ' 分钟前';
   78 | ' 小时前'
      ctx: return Math.round(seconds / 3600).toString() + ' 小时前';
  104 | 'app 未运行'
      ctx: data[FieldwatchWidgetKeys.STATUS] = 'app 未运行';
  105 | '开启后台运行并切到后台后，这里会显示扫描情况'
      ctx: data[FieldwatchWidgetKeys.DETAIL] = '开启后台运行并切到后台后，这里会显示扫描情况';
  109 | ' · 星闪 '
      ctx: + ' · 星闪 ' + state.nearLink.toString();
  110 | ' · 已暂停'
      ctx: if (state.paused) status += ' · 已暂停';
  114 | '关注 · '
      ctx: parts.push('关注 · ' + state.watchLabel + ' ' + state.watchRssi.toString() + ' dBm · ' + ageText(state.watchAgeSec));
  117 | '特征族 · '
      ctx: parts.push('特征族 · ' + state.familyLabel + ' · ' + ageText(state.familyAgeSec));
  119 | '尚未命中关注目标或特征族'
      ctx: data[FieldwatchWidgetKeys.DETAIL] = parts.length > 0 ? parts.join('\n') : '尚未命中关注目标或特征族';

## fieldwatch/platform/FieldwatchFeedbackService.ets  (7)
  173 | '上传已取消'
      ctx: public constructor() { super('上传已取消'); }
  310 | '读取附件失败: expected='
      ctx: throw new Error('读取附件失败: expected=' + readSize.toString() + ' actual=' + readBytes.toString());
  340 | '本地文件大小在上传前发生变化'
      ctx: throw new Error('本地文件大小在上传前发生变化');
  343 | '上传会话偏移无效'
      ctx: if (offset < 0 || offset > session.requested_size) throw new Error('上传会话偏移无效');
  353 | '读取附件失败: expected='
      ctx: throw new Error('读取附件失败: expected=' + readSize.toString() + ' actual=' + readBytes.toString());
  357 | '分块上传失败'
      ctx: if (result === undefined) throw new Error('分块上传失败');
  358 | '服务器未推进上传偏移'
      ctx: if (result.received_size <= offset && !result.complete) throw new Error('服务器未推进上传偏移');

## fieldwatch/radio/FieldwatchBleScanner.ets  (3)
   31 | '蓝牙未开启，请先开启蓝牙后重试'
      ctx: this.fail('蓝牙未开启，请先开启蓝牙后重试');
  121 | ' 条观测'
      ctx: + this.observationsSinceLog.toString() + ' 条观测');
  212 | 'BLE 扫描失败（'
      ctx: return 'BLE 扫描失败（' + businessError.code.toString() + '）：' + businessError.message;

## fieldwatch/radio/FieldwatchNearLinkScanner.ets  (8)
   48 | '星闪能力探测失败：'
      ctx: this.fail('星闪能力探测失败：' + this.errorMessage(error));
   52 | '本机不支持星闪'
      ctx: this.fail('本机不支持星闪');
   60 | '星闪未开启，请先开启星闪后重试'
      ctx: this.fail('星闪未开启，请先开启星闪后重试');
   64 | '读取星闪状态失败：'
      ctx: this.fail('读取星闪状态失败：' + this.errorMessage(error));
  154 | '星闪扫描权限未授予'
      ctx: if (code === 201) return '星闪扫描权限未授予';
  155 | '本机不支持星闪'
      ctx: if (code === 801) return '本机不支持星闪';
  156 | '星闪未开启，请先开启星闪后重试'
      ctx: if (code === 36100003) return '星闪未开启，请先开启星闪后重试';
  157 | '星闪扫描失败（'
      ctx: return '星闪扫描失败（' + code.toString() + '）：' + error.message;

## fieldwatch/radio/FieldwatchWifiScanner.ets  (6)
  146 | '注册 Wi-Fi 扫描状态监听失败'
      ctx: this.handleFailureCode(this.codeOf(error), '注册 Wi-Fi 扫描状态监听失败');
  161 | 'Wi-Fi 信息权限未授予，请重新授权'
      ctx: this.handleFailureCode(PERMISSION_DENIED, 'Wi-Fi 信息权限未授予，请重新授权');
  165 | 'Wi-Fi 未开启，请先打开 Wi-Fi'
      ctx: this.handleFailureCode(WIFI_DISABLED, 'Wi-Fi 未开启，请先打开 Wi-Fi');
  170 | '系统位置信息未开启，Wi-Fi 扫描需要位置服务'
      ctx: this.lastErrorMessage = '系统位置信息未开启，Wi-Fi 扫描需要位置服务';
  200 | '系统暂时拒绝或节流 Wi-Fi 扫描'
      ctx: this.handleFailureCode(SYSTEM_REJECTED, '系统暂时拒绝或节流 Wi-Fi 扫描');
  357 | 'Wi-Fi 扫描失败'
      ctx: private errorMessage(error: Object): string { const businessError: BusinessError = error as BusinessError; return businessError.message === undefined 

## fieldwatch/ui/FieldwatchDeviceTypeIcon.ets  (51)
   40 | '手机'
      ctx: if (deviceClass === 0x000200 || deviceClass === 0x000201) return '手机';
   41 | '计算机'
      ctx: if (deviceClass === 0x000300) return '计算机';
   42 | '笔记本'
      ctx: if (deviceClass === 0x000301) return '笔记本';
   43 | '平板'
      ctx: if (deviceClass === 0x000302) return '平板';
   44 | '一体机'
      ctx: if (deviceClass === 0x000303) return '一体机';
   45 | '迷你主机'
      ctx: if (deviceClass === 0x000304) return '迷你主机';
   46 | '手表'
      ctx: if (deviceClass === 0x000400 || deviceClass === 0x000401) return '手表';
   47 | '人机接口设备'
      ctx: if (deviceClass === 0x000500) return '人机接口设备';
   48 | '键盘'
      ctx: if (deviceClass === 0x000501) return '键盘';
   49 | '鼠标'
      ctx: if (deviceClass === 0x000502) return '鼠标';
   50 | '手柄'
      ctx: if (deviceClass === 0x000503) return '手柄';
   51 | '手写笔'
      ctx: if (deviceClass === 0x000504) return '手写笔';
   52 | '触控板'
      ctx: if (deviceClass === 0x000505) return '触控板';
   53 | '音频播放设备'
      ctx: if (deviceClass === 0x000600) return '音频播放设备';
   54 | '智能音箱'
      ctx: if (deviceClass === 0x000601) return '智能音箱';
   55 | '回音壁'
      ctx: if (deviceClass === 0x000602) return '回音壁';
   56 | '音频采集设备'
      ctx: if (deviceClass === 0x000700) return '音频采集设备';
   57 | 'K 歌麦克风'
      ctx: if (deviceClass === 0x000701) return 'K 歌麦克风';
   58 | '领夹麦克风'
      ctx: if (deviceClass === 0x000702) return '领夹麦克风';
   59 | '可穿戴音频'
      ctx: if (deviceClass === 0x000800) return '可穿戴音频';
   60 | '入耳式耳机'
      ctx: if (deviceClass === 0x000801) return '入耳式耳机';
   61 | '头戴耳机'
      ctx: if (deviceClass === 0x000802) return '头戴耳机';
   62 | '包耳式耳机'
      ctx: if (deviceClass === 0x000803) return '包耳式耳机';
   63 | '颈挂式耳机'
      ctx: if (deviceClass === 0x000804) return '颈挂式耳机';
   64 | '个人护理设备'
      ctx: if (deviceClass === 0x000900) return '个人护理设备';
   65 | '电动牙刷'
      ctx: if (deviceClass === 0x000901) return '电动牙刷';
   66 | '智能水杯'
      ctx: if (deviceClass === 0x000902) return '智能水杯';
   67 | '电动剃须刀'
      ctx: if (deviceClass === 0x000903) return '电动剃须刀';
   68 | '暖通设备'
      ctx: if (deviceClass === 0x000A00) return '暖通设备';
   69 | '空气净化器'
      ctx: if (deviceClass === 0x000A01) return '空气净化器';
   70 | '加湿器'
      ctx: if (deviceClass === 0x000A02) return '加湿器';
   71 | '循环扇'
      ctx: if (deviceClass === 0x000A03) return '循环扇';
   72 | '电动出行设备'
      ctx: if (deviceClass === 0x000B00) return '电动出行设备';
   73 | '电动滑板车'
      ctx: if (deviceClass === 0x000B01) return '电动滑板车';
   74 | '电动自行车'
      ctx: if (deviceClass === 0x000B02) return '电动自行车';
   75 | '灯具'
      ctx: if (deviceClass === 0x000C00) return '灯具';
   76 | '智能台灯'
      ctx: if (deviceClass === 0x000C01) return '智能台灯';
   77 | '遥控器'
      ctx: if (deviceClass === 0x000D00) return '遥控器';
   78 | '电视遥控器'
      ctx: if (deviceClass === 0x000D01) return '电视遥控器';
   79 | '影像设备'
      ctx: if (deviceClass === 0x000E00) return '影像设备';
   80 | '智慧屏'
      ctx: if (deviceClass === 0x000E01) return '智慧屏';
   81 | '网络摄像头'
      ctx: if (deviceClass === 0x000E02) return '网络摄像头';
   82 | '投屏器'
      ctx: if (deviceClass === 0x000E03) return '投屏器';
   83 | '网络设备'
      ctx: if (deviceClass === 0x000F00) return '网络设备';
   84 | 'IoT 网关'
      ctx: if (deviceClass === 0x000F01) return 'IoT 网关';
   85 | '门禁设备'
      ctx: if (deviceClass === 0x001000) return '门禁设备';
   86 | '智能门锁'
      ctx: if (deviceClass === 0x001001) return '智能门锁';
   87 | '智能钥匙'
      ctx: if (deviceClass === 0x001002) return '智能钥匙';
   88 | '车钥匙'
      ctx: if (deviceClass === 0x001003) return '车钥匙';
   89 | '车锁'
      ctx: if (deviceClass === 0x001004) return '车锁';
   90 | '未分类设备'
      ctx: if (deviceClass === 0x000100) return '未分类设备';

## fieldwatch/ui/FieldwatchFindWizard.ets  (1)
  257 | ' 地址直配='
      ctx: + ' 地址直配=' + (addressHit ? '命中' : '未命中') + ' 同名候选=' + nameCount.toString());

## pages/fieldwatch/FieldwatchDeviceDetailPage.ets  (1)
  527 | ' dBm —— 它自称的发射强度，不代表距离'
      ctx: item.facts.txPower.toString() + ' dBm —— 它自称的发射强度，不代表距离', FieldwatchPaletteHolder.get().text)

## pages/fieldwatch/FieldwatchFeedbackPage.ets  (4)
  557 | '# 电波足迹 · 记录导出'
      ctx: lines.push('# 电波足迹 · 记录导出');
  558 | '# 导出时间: '
      ctx: lines.push('# 导出时间: ' + new Date().toISOString());
  559 | '# 应用版本: '
      ctx: lines.push('# 应用版本: ' + deviceInfo.displayVersion + ' / ' + deviceInfo.osFullName);
 1140 | '管理'
      ctx: post.author_kind.indexOf('admin') >= 0 || post.author_kind.indexOf('管理') >= 0)

## pages/fieldwatch/FieldwatchPage.ets  (18)
  516 | '」 栈深 '
      ctx: + '」 栈深 ' + before.toString() + ' -> ' + this.pathStack.size().toString());
 1422 | ' 台 · '
      ctx: Text('+' + node.count.toString() + ' 台 · ' + node.clusterLabel)
 1443 | '…共 '
      ctx: Text('…共 ' + node.memberKeys.length.toString() + ' 台')
 2222 | 'Wi-Fi 4 及更早'
      ctx: if (mhz < 2500) return width >= 40 ? 'Wi-Fi 4 (802.11n)' : 'Wi-Fi 4 及更早';
 2261 | '开放（无密码）'
      ctx: if (value === 1) return '开放（无密码）';
 2262 | 'WEP（已过时）'
      ctx: if (value === 2) return 'WEP（已过时）';
 2711 | '首 '
      ctx: return '首 ' + this.durationText(now - firstMillis) + ' · ' + (lastMillis >= now - 2000 ? '末 now' : '末 ' + this.durationText(now - lastMillis));
 3981 | ' 台信号源 · 未匹配 '
      ctx: this.candidateStats = report.uniqueRadios.toString() + ' 台信号源 · 未匹配 ' + report.unmatchedRadios.toString()
 3982 | ' · 跳过随机 '
      ctx: + ' · 跳过随机 ' + report.skippedRandomized.toString() + ' · 跳过家用 ' + report.skippedHouseLike.toString();
 4268 | ' 台'
      ctx: Text(item.distinctRadios.toString() + ' 台')
 4582 | ' 个'
      ctx: return prefix + this.nearLinkPhase + ' · ' + this.nearLinkCount.toString() + ' 个';
 4836 | ' 个结果'
      ctx: + (this.wifiResultCount > 0 ? ' · ' + this.wifiResultCount.toString() + ' 个结果' : '')
 4945 | '中文'
      ctx: Button('中文').backgroundColor(Color.Transparent).borderWidth(1)
 5497 | '漫匣'
      ctx: list.push(new DeveloperApp('漫匣', '一款基于 HarmonyOS 的现代化漫画阅读应用',
 5500 | '花漾字影'
      ctx: list.push(new DeveloperApp('花漾字影', '帮您轻松创作更亮眼的手持弹幕内容',
 5503 | '书脉'
      ctx: list.push(new DeveloperApp('书脉', '支持多种格式的元数据编辑与封面管理',
 5506 | '移动端 AI 编程协作工具'
      ctx: list.push(new DeveloperApp('NGF Coder', '移动端 AI 编程协作工具',
 5509 | '神秘 APP'
      ctx: list.push(new DeveloperApp('神秘 APP', '敬请期待', '', undefined));

## pages/fieldwatch/FieldwatchSignatureEditorPage.ets  (2)
  735 | '星闪'
      ctx: : (value.indexOf('星闪') >= 0 ? RadioKind.NEARLINK : RadioKind.BLE);
  744 | '星闪'
      ctx: if (kind === RadioKind.NEARLINK) return '星闪';

## pages/fieldwatch/FieldwatchToolboxPage.ets  (3)
 1041 | ' 分钟'
      ctx: Text(formatMinutes(suspect.evidence.spanMs) + ' 分钟').fontSize(11)
 1043 | ' 分'
      ctx: Text(suspect.evidence.score.toString() + ' 分').fontSize(13)
 1067 | ' 分'
      ctx: Text(event.score.toString() + ' 分').fontSize(12)

## pages/ngf/HdsNavigationOfficialShowcasePage.ets  (2)
 1342 | '自定义点光颜色'
      ctx: Text('自定义点光颜色')
 1358 | 'API26 HdsColorPicker: 选中颜色后,上方 PointLight 卡片的 hdsEffect 点光会实时变色。'
      ctx: Text('API26 HdsColorPicker: 选中颜色后,上方 PointLight 卡片的 hdsEffect 点光会实时变色。')

## pages/ngf/MainMenuPage.ets  (22)
  607 | 'Symbol 预览'
      ctx: 'targetTitle': 'Symbol 预览'
  610 | '启动多实例任务: Symbol 预览器'
      ctx: this.appendLog('启动多实例任务: Symbol 预览器');
  612 | '启动多实例任务失败: '
      ctx: this.appendLog('启动多实例任务失败: ' + err);
  624 | '数据沙箱'
      ctx: 'targetTitle': '数据沙箱'
  627 | '启动多实例任务: 数据沙箱'
      ctx: this.appendLog('启动多实例任务: 数据沙箱');
  629 | '启动多实例任务失败: '
      ctx: this.appendLog('启动多实例任务失败: ' + err);
  639 | '打开应用内子窗口: 设置面板'
      ctx: this.appendLog('打开应用内子窗口: 设置面板');
  643 | '打开应用内子窗口失败: '
      ctx: this.appendLog('打开应用内子窗口失败: ' + err);
  653 | '打开应用内子窗口: 任务管理'
      ctx: this.appendLog('打开应用内子窗口: 任务管理');
  657 | '打开应用内子窗口失败: '
      ctx: this.appendLog('打开应用内子窗口失败: ' + err);
  662 | '当前页面状态已保存到 ContinuationFacade，请在另一台鸿蒙设备通过多设备控制中心触发流转。'
      ctx: this.appendLog('当前页面状态已保存到 ContinuationFacade，请在另一台鸿蒙设备通过多设备控制中心触发流转。');
  664 | '流转数据准备就绪'
      ctx: ngfOverlayManagerFacade.showToast('流转数据准备就绪');
  666 | '显示Toast失败: '
      ctx: this.appendLog('显示Toast失败: ' + err);
  672 | '发现宝藏鸿蒙框架 NGF！当前核心服务就绪: '
      ctx: const text = '发现宝藏鸿蒙框架 NGF！当前核心服务就绪: ' + this.isCoreReady + '，最后事件: ' + this.lastEventType;
  675 | '已拉起原生系统 ShareKit 分享面板'
      ctx: this.appendLog('已拉起原生系统 ShareKit 分享面板');
  678 | '分享拉起失败: '
      ctx: this.appendLog('分享拉起失败: ' + err);
 1849 | '架构'
      ctx: this.buildPerfInfoRow('架构', this.runtimeStatus?.is64Bit ? '64-bit' : '32-bit')
 1851 | '运行时间 (uptime)'
      ctx: this.buildPerfInfoRow('运行时间 (uptime)', this.formatUptime(this.runtimeStatus?.uptime))
 1874 | 'App 内存限制'
      ctx: this.buildPerfInfoRow('App 内存限制', String(this.runtimeStatus?.appMemoryLimit || 0) + ' MB')
 1921 | '系统 CPU\\n'
      ctx: Text('系统 CPU\\n' + String(((this.runtimeStatus?.systemCpuUsage || 0) * 100).toFixed(1)) + '%')
 1979 | '温度'
      ctx: this.buildPerfInfoRow('温度', String(((this.runtimeStatus?.batteryTemperature || 0) / 10).toFixed(1)) + ' °C')
 1981 | '充电状态'
      ctx: this.buildPerfInfoRow('充电状态', this.runtimeStatus?.isCharging ? '充电中 / 已满' : '未充电')

## pages/ngf/NGFCapabilitiesDatabasePage.ets  (1)
   54 | 'ngfRdbManager.init 返回了 false'
      ctx: throw new Error('ngfRdbManager.init 返回了 false');

## pages/ngf/NGFDemoDataStoragePage.ets  (3)
  169 | '成功选取图片: '
      ctx: ngfOverlayManagerFacade.showToast('成功选取图片: ' + uris[0]);
  170 | '安全选择图片: '
      ctx: this.appendLog('安全选择图片: ' + uris[0]);
  185 | '安全选择文档: '
      ctx: this.appendLog('安全选择文档: ' + uris[0]);

## pages/ngf/NGFDemoErrorRecoveryPage.ets  (1)
   90 | '模拟错误 ['
      ctx: const message = '模拟错误 [' + severity + '] — ' + String(this.now());

## pages/ngf/NGFDemoWorkflowPage.ets  (1)
  390 | '数据获取'
      ctx: steps.push(new NGFWorkflowStepDefinition('数据获取', 'fetch', '{"url":"https://api.example.com/data"}'));

## pages/ngf/NGFDeviceAwarenessPage.ets  (3)
  439 | '实时握持：'
      ctx: return '实时握持：' + sideStr + ' / ' + confidenceStr;
  449 | '实时设备：'
      ctx: return '实时设备：' + orientationStr + ' · ' + widthStr + ' x ' + heightStr + ' · ' + reasonStr;
  582 | '未知('
      ctx: return '未知(' + level + ')';

## pages/ngf/NGFHdsTabRoutes.ets  (5)
   22 | '框架'
      ctx: new NGFHdsTabConfig(0, '框架', NGFHdsTabRouteName.FRAMEWORK),
   23 | '功能'
      ctx: new NGFHdsTabConfig(1, '功能', NGFHdsTabRouteName.FEATURES),
   24 | '展示'
      ctx: new NGFHdsTabConfig(2, '展示', NGFHdsTabRouteName.SHOWCASE),
   25 | '设备'
      ctx: new NGFHdsTabConfig(3, '设备', NGFHdsTabRouteName.DEVICE),
   26 | '设置'
      ctx: new NGFHdsTabConfig(4, '设置', NGFHdsTabRouteName.SETTINGS)

## pages/ngf/NGFSettingsPage.ets  (1)
  630 | '未知('
      ctx: return '未知(' + level + ')';

## pages/ngf/SystemResourcePreviewPage.ets  (8)
  226 | '已接收拖放 Symbol: '
      ctx: Text(this.droppedSymbol ? '已接收拖放 Symbol: ' + this.droppedSymbol : '长按拖拽下方 Symbol 到此处，测试 UDMF')
  249 | '拖放成功: '
      ctx: this.statusText = '拖放成功: ' + text;
  250 | '拖放成功: '
      ctx: ngfOverlayManagerFacade.showToast('拖放成功: ' + text);
  612 | ' 个 Symbol'
      ctx: return group.name + ' · ' + group.items.length + ' 个 Symbol';
  891 | '搜索 '
      ctx: this.statusText = '搜索 ' + keyword + '：' + String(results.length) + ' 个结果';
  910 | '已复制 '
      ctx: this.statusText = '已复制 ' + fullName;
  911 | '已复制 '
      ctx: ngfOverlayManagerFacade.showToast('已复制 ' + fullName);
  915 | '复制失败：'
      ctx: this.statusText = '复制失败：' + message;

## widget/pages/WidgetCard.ets  (1)
   24 | 'app 未运行'
      ctx: @LocalStorageProp('statusText') statusText: string = 'app 未运行';

TOTAL 355