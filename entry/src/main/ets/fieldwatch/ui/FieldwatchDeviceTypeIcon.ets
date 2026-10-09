import { RadioKind, SignatureClass } from '../domain/FieldwatchModels';
import { FieldwatchPaletteHolder } from './FieldwatchPalette';

/**
 * 类别 → 系统符号。
 *
 * 全部名称已逐条核对 API 26 的 sysResource 符号目录（3778 个）确实存在；
 * 鸿蒙符号是专业绘制的单色矢量，比自绘 SVG 更清晰，且天然支持着色。
 * 未覆盖的类别返回空串，由自绘 SVG 兜底。
 */
export function deviceClassSymbol(category: SignatureClass): string {
  if (category === SignatureClass.BEACON) return 'sys.symbol.dot_radiowaves_left_and_right';
  if (category === SignatureClass.SIGNAGE) return 'sys.symbol.building';
  if (category === SignatureClass.WEARABLE || category === SignatureClass.BODYWORN) return 'sys.symbol.watch';
  if (category === SignatureClass.SURVEILLANCE) return 'sys.symbol.video';
  if (category === SignatureClass.CAMERA) return 'sys.symbol.camera';
  if (category === SignatureClass.AUDIO) return 'sys.symbol.headphones';
  if (category === SignatureClass.VEHICLE) return 'sys.symbol.car';
  if (category === SignatureClass.THERMOSTAT) return 'sys.symbol.thermometer_medium';
  if (category === SignatureClass.LOCK) return 'sys.symbol.lock';
  if (category === SignatureClass.HEALTH) return 'sys.symbol.heart';
  if (category === SignatureClass.HOME) return 'sys.symbol.house';
  if (category === SignatureClass.ISP || category === SignatureClass.ROUTER) return 'sys.symbol.wifi_router';
  if (category === SignatureClass.PHONE) return 'sys.symbol.phone';
  if (category === SignatureClass.GLASSES) return 'sys.symbol.face';
  if (category === SignatureClass.MESH) return 'sys.symbol.shareplay';
  if (category === SignatureClass.LAW_ENFORCEMENT) return 'sys.symbol.shield_badge_circle_dot';
  if (category === SignatureClass.HACKING) return 'sys.symbol.shield_checkered';
  return '';
}

/**
 * 星闪设备类型 → 用户可读名称。
 *
 * 星闪广播自带 `DeviceClass`，所以这个名称是**设备自己声明的**，
 * 不像 BLE 那样靠特征库推断 —— 这是星闪独有的一项可信信息。
 * 未覆盖的值回退到空串，由调用方决定如何显示。
 */
export function nearLinkClassLabel(deviceClass: number): string {
  if (deviceClass === 0x000200 || deviceClass === 0x000201) return '手机';
  if (deviceClass === 0x000300) return '计算机';
  if (deviceClass === 0x000301) return '笔记本';
  if (deviceClass === 0x000302) return '平板';
  if (deviceClass === 0x000303) return '一体机';
  if (deviceClass === 0x000304) return '迷你主机';
  if (deviceClass === 0x000400 || deviceClass === 0x000401) return '手表';
  if (deviceClass === 0x000500) return '人机接口设备';
  if (deviceClass === 0x000501) return '键盘';
  if (deviceClass === 0x000502) return '鼠标';
  if (deviceClass === 0x000503) return '手柄';
  if (deviceClass === 0x000504) return '手写笔';
  if (deviceClass === 0x000505) return '触控板';
  if (deviceClass === 0x000600) return '音频播放设备';
  if (deviceClass === 0x000601) return '智能音箱';
  if (deviceClass === 0x000602) return '回音壁';
  if (deviceClass === 0x000700) return '音频采集设备';
  if (deviceClass === 0x000701) return 'K 歌麦克风';
  if (deviceClass === 0x000702) return '领夹麦克风';
  if (deviceClass === 0x000800) return '可穿戴音频';
  if (deviceClass === 0x000801) return '入耳式耳机';
  if (deviceClass === 0x000802) return '头戴耳机';
  if (deviceClass === 0x000803) return '包耳式耳机';
  if (deviceClass === 0x000804) return '颈挂式耳机';
  if (deviceClass === 0x000900) return '个人护理设备';
  if (deviceClass === 0x000901) return '电动牙刷';
  if (deviceClass === 0x000902) return '智能水杯';
  if (deviceClass === 0x000903) return '电动剃须刀';
  if (deviceClass === 0x000A00) return '暖通设备';
  if (deviceClass === 0x000A01) return '空气净化器';
  if (deviceClass === 0x000A02) return '加湿器';
  if (deviceClass === 0x000A03) return '循环扇';
  if (deviceClass === 0x000B00) return '电动出行设备';
  if (deviceClass === 0x000B01) return '电动滑板车';
  if (deviceClass === 0x000B02) return '电动自行车';
  if (deviceClass === 0x000C00) return '灯具';
  if (deviceClass === 0x000C01) return '智能台灯';
  if (deviceClass === 0x000D00) return '遥控器';
  if (deviceClass === 0x000D01) return '电视遥控器';
  if (deviceClass === 0x000E00) return '影像设备';
  if (deviceClass === 0x000E01) return '智慧屏';
  if (deviceClass === 0x000E02) return '网络摄像头';
  if (deviceClass === 0x000E03) return '投屏器';
  if (deviceClass === 0x000F00) return '网络设备';
  if (deviceClass === 0x000F01) return 'IoT 网关';
  if (deviceClass === 0x001000) return '门禁设备';
  if (deviceClass === 0x001001) return '智能门锁';
  if (deviceClass === 0x001002) return '智能钥匙';
  if (deviceClass === 0x001003) return '车钥匙';
  if (deviceClass === 0x001004) return '车锁';
  if (deviceClass === 0x000100) return '未分类设备';
  return '';
}
/**
 * 星闪设备类型 → 系统符号。
 *
 * 星闪广播直接携带 `DeviceClass`（54 种），因此**不需要特征库命中**就能显示正确图标 ——
 * 这是星闪相对 BLE 的独有能力。全部符号名已逐条核对 API 26 的系统符号目录。
 *
 * 未覆盖的类型统一回退到电波符号，不会出现空图标。
 */
export function nearLinkClassSymbol(deviceClass: number): string {
  // 计算机类：通用计算机 / 笔记本 / 平板 / 一体机 / 迷你主机
  if (deviceClass === 0x000300 || deviceClass === 0x000301 || deviceClass === 0x000302
    || deviceClass === 0x000303 || deviceClass === 0x000304) return 'sys.symbol.computer';
  // 手机类
  if (deviceClass === 0x000200 || deviceClass === 0x000201) return 'sys.symbol.phone';
  // 手表类
  if (deviceClass === 0x000400 || deviceClass === 0x000401) return 'sys.symbol.watch';
  // 人机接口：键盘 / 鼠标 / 触控板 / 手柄 / 手写笔
  if (deviceClass === 0x000501) return 'sys.symbol.keyboard';
  if (deviceClass === 0x000502) return 'sys.symbol.mouse_right_click_move';
  if (deviceClass === 0x000504) return 'sys.symbol.doc_plaintext_and_pencil';
  // 音频播放：音箱 / 智能音箱 / 回音壁
  if (deviceClass === 0x000600 || deviceClass === 0x000601 || deviceClass === 0x000602) return 'sys.symbol.speaker';
  // 音频采集：麦克风 / 麦克风阵列
  if (deviceClass === 0x000700 || deviceClass === 0x000701 || deviceClass === 0x000702) return 'sys.symbol.mic';
  // 可穿戴音频：入耳 / 头戴 / 颈挂
  if (deviceClass === 0x000800 || deviceClass === 0x000801 || deviceClass === 0x000802
    || deviceClass === 0x000803 || deviceClass === 0x000804) return 'sys.symbol.headphones';
  // 个护：牙刷 / 水杯 / 剃须刀
  if (deviceClass === 0x000901 || deviceClass === 0x000902) return 'sys.symbol.cup';
  if (deviceClass === 0x000903) return 'sys.symbol.bolt';
  // 暖通：净化器 / 加湿器 / 循环扇
  if (deviceClass === 0x000A00 || deviceClass === 0x000A01 || deviceClass === 0x000A02
    || deviceClass === 0x000A03) return 'sys.symbol.air_conditioning_purification_open_fill';
  // 电动出行：滑板车 / 电动自行车
  if (deviceClass === 0x000B00 || deviceClass === 0x000B01 || deviceClass === 0x000B02) return 'sys.symbol.bicycle';
  // 灯具
  if (deviceClass === 0x000C00 || deviceClass === 0x000C01) return 'sys.symbol.lightbulb';
  // 影像：智慧屏 / 投屏器
  if (deviceClass === 0x000E00 || deviceClass === 0x000E01 || deviceClass === 0x000E03) return 'sys.symbol.tv_and_rectangle_portrait';
  if (deviceClass === 0x000E02) return 'sys.symbol.camera';
  // 网络：IoT 网关
  if (deviceClass === 0x000F00 || deviceClass === 0x000F01) return 'sys.symbol.wifi_router';
  // 门禁：智能锁 / 车锁
  if (deviceClass === 0x001000 || deviceClass === 0x001001 || deviceClass === 0x001004) return 'sys.symbol.lock';
  // 钥匙：智能钥匙 / 车钥匙
  if (deviceClass === 0x001002 || deviceClass === 0x001003) return 'sys.symbol.key';
  // 未分类 / 遥控器 / 其它：回退到电波符号
  return 'sys.symbol.dot_radiowaves_left_and_right';
}
/**
 * 设备/类别图标。
 *
 * 优先用系统符号（清晰、可着色）；FINDER / DRONE 与「只有无线电种类、没有类别」
 * 的场景走自绘 SVG。SVG 全部是纯填充路径，因此 fillColor 能正确着色。
 */
@Component
export struct FieldwatchDeviceTypeIcon {
  @Prop kind: RadioKind = RadioKind.BLE;
  @Prop category: SignatureClass = SignatureClass.OTHER;
  @Prop tint: ResourceColor = FieldwatchPaletteHolder.get().accent;
  @Prop glyphSize: number = 24;

  private svgResource(): Resource {
    if (this.category === SignatureClass.DRONE) return $r('app.media.fieldwatch_drone');
    if (this.category === SignatureClass.FINDER) return $r('app.media.fieldwatch_tracker');
    if (this.kind === RadioKind.WIFI) {
      return this.category === SignatureClass.ISP || this.category === SignatureClass.ROUTER
        ? $r('app.media.fieldwatch_router')
        : $r('app.media.fieldwatch_wifi_ap');
    }
    if (this.category === SignatureClass.PHONE) return $r('app.media.fieldwatch_phone');
    return $r('app.media.fieldwatch_ble');
  }

  build() {
    if (deviceClassSymbol(this.category).length > 0) {
      SymbolGlyph($r(deviceClassSymbol(this.category))).fontSize(this.glyphSize).fontColor([this.tint])
    } else {
      Image(this.svgResource()).width(this.glyphSize).height(this.glyphSize).fillColor(this.tint).objectFit(ImageFit.Contain)
    }
  }
}
