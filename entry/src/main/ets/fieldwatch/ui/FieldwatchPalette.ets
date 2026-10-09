/**
 * Fieldwatch 调色板。
 *
 * 取自原版 Android `ui/theme/Theme.kt` 的精确取值（辐射4 风格的荧光绿 + 近黑底）。
 * 之所以用字符串常量而不是 `$r('app.color.*')`：Canvas 2D 的 `fillStyle` 只接受
 * 字符串/渐变，不接受 Resource；雷达与列表必须共用同一份颜色，否则两处会漂移。
 * 组件侧同样使用本表，保证深浅色切换只有一个真源。
 */
export class FieldwatchPalette {
  /** 页面底色（原版 Night）。 */
  public readonly night: string;
  /** 卡片/面板底色（原版 Panel）。 */
  public readonly panel: string;
  /** 次级面板（原版 Panel2）。 */
  public readonly panel2: string;
  /** 描边（原版 outline）。 */
  public readonly outline: string;
  /** 分隔线。 */
  public readonly divider: string;
  /** 主强调色（原版 Phosphor）。 */
  public readonly accent: string;
  /** 选中态强调色（原版 PhosphorActive）。 */
  public readonly accentActive: string;
  /** 强调色之上的文字色。 */
  public readonly onAccent: string;
  /** 次级强调色（原版 Amber）。 */
  public readonly amber: string;
  /** 告警/弱信号（原版 SignalRed）。 */
  public readonly signalRed: string;
  /** 第三强调色（原版 Cyan）。 */
  public readonly cyan: string;
  /** 正文（原版 onBackground）。 */
  public readonly text: string;
  /** 次级正文（原版 onSurfaceVariant）。 */
  public readonly textDim: string;
  /** 头部 FIELDWATCH 字色。 */
  public readonly headerText: string;
  /** 类别徽章底色。 */
  public readonly badgeBg: string;
  /** RSSI 条填充。 */
  public readonly rssiBar: string;
  /** 透明哨兵：系统栏必须用它，写不透明色等于给状态栏刷了一块底色。 */
  public readonly transparent: string;
  /** 提示/警告文字。 */
  public readonly warn: string;
  /** 搜寻提示：非常近 / 更近 / 基本没变 / 更远。 */
  public readonly huntVeryClose: string;
  public readonly huntCloser: string;
  public readonly huntSame: string;
  public readonly huntFar: string;
  /** 签名着色环（按 colorIndex 取用）。 */
  public readonly signatureRamp: string[];
  /** 引导遮罩。 */
  public readonly overlayScrim: string;
  /** RSSI 条轨道。 */
  public readonly rssiTrack: string;
  /** 星闪（NearLink）信号源颜色，与 BLE 绿 / Wi-Fi 青区分开。 */
  public readonly nearLink: string;

  constructor(night: string, panel: string, panel2: string, outline: string, divider: string, accent: string,
    accentActive: string, onAccent: string, amber: string, signalRed: string, cyan: string, text: string,
    textDim: string, headerText: string, badgeBg: string, rssiBar: string, rssiTrack: string, overlayScrim: string, transparent: string, warn: string,
    huntVeryClose: string, huntCloser: string, huntSame: string, huntFar: string, signatureRamp: string[],
    nearLink: string = '#7C6BFF') {
    this.night = night;
    this.panel = panel;
    this.panel2 = panel2;
    this.outline = outline;
    this.divider = divider;
    this.accent = accent;
    this.accentActive = accentActive;
    this.onAccent = onAccent;
    this.amber = amber;
    this.signalRed = signalRed;
    this.cyan = cyan;
    this.text = text;
    this.textDim = textDim;
    this.headerText = headerText;
    this.badgeBg = badgeBg;
    this.rssiBar = rssiBar;
    this.rssiTrack = rssiTrack;
    this.overlayScrim = overlayScrim;
    this.transparent = transparent;
    this.warn = warn;
    this.huntVeryClose = huntVeryClose;
    this.huntCloser = huntCloser;
    this.huntSame = huntSame;
    this.huntFar = huntFar;
    this.signatureRamp = signatureRamp;
    this.nearLink = nearLink;
  }

  /** 深色（默认）：辐射4 风格的荧光绿 + 近黑底。 */
  static dark(): FieldwatchPalette {
    return new FieldwatchPalette('#0B0F14', '#141A22', '#1B232D', '#2A3340', '#222A34', '#3DFF9A', '#35D683',
      '#003820', '#FFB020', '#FF3D5A', '#4FC3F7', '#D5DCE3', '#9AA6B2', '#E8EDF2', '#1B232D', '#FF3D5A', '#1B232D', '#B3000000', '#00000000', '#FFB020',
      '#FF8A65', '#68E56D', '#F4C95D', '#6EAED9', ['#4FC3F7', '#3DFF9A', '#FFB020', '#FF8A65', '#B388FF', '#FF80AB', '#4DD0E1', '#AED581', '#FFD54F']);
  }

  /** 浅色：同一套语义的日间版本，绿色加深以保证对比度。 */
  static light(): FieldwatchPalette {
    return new FieldwatchPalette('#F4F6F8', '#FFFFFF', '#E6EBEF', '#C5CDD4', '#D8DFE5', '#0B7A48', '#0A6B3F',
      '#FFFFFF', '#9A6400', '#B00020', '#0277BD', '#12171C', '#3F4A55', '#12171C', '#E6EBEF', '#B00020', '#E6EBEF', '#66000000', '#00000000', '#9A6400',
      '#C2410C', '#0B7A48', '#9A6400', '#3F4A55', ['#0277BD', '#0B7A48', '#9A6400', '#C2410C', '#5B4BC4', '#AD1457', '#00838F', '#558B2F', '#8D6E00']);
  }

  static of(isDark: boolean): FieldwatchPalette {
    return isDark ? FieldwatchPalette.dark() : FieldwatchPalette.light();
  }
}

/**
 * 当前生效的调色板。
 *
 * 自行从 AppStorage 惰性读取 `ngf_is_dark_mode`，因此不需要任何页面做 @Watch 接线；
 * 只在深浅色真正翻转时重建对象，避免每次 build 都产生新实例导致无谓重绘。
 * 未设置时默认深色——Fieldwatch 是夜战风格。
 */
export class FieldwatchPaletteHolder {
  private static current: FieldwatchPalette = FieldwatchPalette.dark();
  private static lastDark: boolean = true;

  static get(): FieldwatchPalette {
    const stored: boolean | undefined = AppStorage.get<boolean>('ngf_is_dark_mode');
    const isDark: boolean = stored === undefined || stored === null ? true : stored;
    if (isDark !== FieldwatchPaletteHolder.lastDark) {
      FieldwatchPaletteHolder.lastDark = isDark;
      FieldwatchPaletteHolder.current = FieldwatchPalette.of(isDark);
    }
    return FieldwatchPaletteHolder.current;
  }
}
