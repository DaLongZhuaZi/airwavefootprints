import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { logger, uiContextManager } from 'ngf_framework';
import { SecuritySummary } from '../domain/FieldwatchSecurityScan';
import { foldedSignatureClass, SignatureClass } from '../domain/FieldwatchModels';

const TAG: string = 'FieldwatchShareCard';
/** 分享卡落盘目录（沙箱内）。 */
const CARD_DIR: string = 'fieldwatch/share';
/**
 * 卡片画布尺寸（px）。2:3 竖版，适配聊天窗口与朋友圈的首图比例。
 *
 * 取 720×1080 而不是 1080×1620：实测 1080 宽度出的 PNG 有 822 KB，
 * ShareKit 走 want 传递时直接 `IPC data is oversized`。
 * 720 宽度在手机上仍然是清晰的一屏，文件体积降到约 1/3。
 */
export const SHARE_CARD_WIDTH: number = 720;
// 高度不在这里硬编码：由下面的版式常量相加得出（见 SHARE_CARD_HEIGHT 定义处）。

// ── 收藏卡版式常量（文档 §1「卡片语法」）────────────────────────────────
//
// 画布 720×1080，元素自上而下只有 6 样：边框环 / 主体图 / 等级带 / 名称+trait /
// 脚注 / 品牌行。旧版元素（雷达、堆叠条、三色块、日期角标、辉光网格）全部删除。
/** 边框环宽度：12px 渐变环，颜色即稀有度 / verdict 材质。 */
const BORDER: number = 12;
/** 外圆角：卡片四角圆角，导出 PNG 后四角透明。 */
const CARD_RADIUS: number = 30;
/** 内底圆角 = 外圆角 - 边框宽，保证环宽均匀。 */
const INNER_RADIUS: number = CARD_RADIUS - BORDER;

/**
 * 主体图展示区：**与源图同比例 1:2**（源图 1024×2048 → 696×1392）。
 *
 * 绘制时按 696/源宽 等比缩放、从 (BORDER,BORDER) 起 1:1 贴合，**既不裁切也不留黑边**。
 * v2 的 cover / fit 与边缘拉伸填充全部作废：cover 会切掉横宽设备两端，fit 会留底色接缝。
 */
const HERO_W: number = 696;
const HERO_H: number = 1392;
const HERO_RADIUS: number = 26;

/** 等级带：52 高，紧贴主体图下沿。 */
const BAND_Y: number = BORDER + HERO_H;
const BAND_H: number = 52;
const BAND_BOTTOM: number = BAND_Y + BAND_H;

/**
 * 下半区节奏：名称 → trait → [脚注] → 品牌。
 *
 * 行距固定为「带底 + 84 → + 46 → + 92」，底边距 32；**总高由这些常量相加得出**，
 * 不硬编码 —— 以后调任何一行都不会把卡片撑破或留出大块空白。
 */
const NAME_BASELINE: number = BAND_BOTTOM + 84;
const TRAIT_BASELINE: number = NAME_BASELINE + 46;
/** 强制脚注（琥珀原句，**仅安防卡使用**；图鉴卡为空则跳过）。 */
const FOOTNOTE_BASELINE: number = TRAIT_BASELINE + 46;
const BRAND_BASELINE: number = TRAIT_BASELINE + 92;
/** 底边距。 */
const BOTTOM_PAD: number = 32;

/**
 * finder 主体图的垂直微调（仅这一张）。
 *
 * finder 源图主体略偏上，直接贴合时视觉重心靠顶。这里只对 finder 下移一点，
 * 顶边空隙用「源图顶部极薄切片纵向拉伸」补齐 —— 源图顶部是深色纹理底，接缝不可见。
 * **不改 hero 区尺寸与比例，也不重出任何源图。**
 */
const FINDER_OFFSET_Y: number = 28;

/** 画布高度：由版式常量推出（约 1710），不硬编码。 */
export const SHARE_CARD_HEIGHT: number = BRAND_BASELINE + BOTTOM_PAD;

/** 卡片内边距（等级带与正文的左右留白）。 */
const SIDE_PAD: number = 26;

/** 背景底色：与 App 深色主题同一套色值，避免分享卡和界面像两个产品。 */
const CARD_BG: string = '#0B0F14';

/**
 * 卡片材质：决定边框渐变与等级带颜色。
 *
 * 六个取值分别对应「图鉴稀有度四档 + 安防 verdict 三档」里会上卡的组合，
 * 色值与分级装饰见 {@link paletteOf}（来源：docs/分享卡收藏卡素材说明.md §4）。
 */
export enum ShareCardMaterial {
  /** 极稀有（金）：双环。 */
  GOLD = 'gold',
  /** 常见（深钢）：素环。 */
  STEEL = 'steel',
  /** 少见（蓝）：斜向渐变。 */
  BLUE = 'blue',
  /** 稀有（紫）：主环 + 内圈细线。 */
  PURPLE = 'purple',
  /** 安防：确认（红）。 */
  RED = 'red',
  /** 安防：可疑（橙）。 */
  ORANGE = 'orange'
}

/**
 * 三段渐变（边框用） + 等级带底色/文字色 + 分级装饰开关。
 *
 * **等级带不取渐变中间色**：中间色偏浅，白字读不清、深字也发灰。
 * 改成「饱和主色打底 + 与之对比度足够的文字色」，见文档 §4。
 */
class CardPalette {
  public top: string = '';
  public mid: string = '';
  public bottom: string = '';
  /** 等级带底色（饱和主色）。 */
  public band: string = '';
  /** 等级带文字色。 */
  public bandText: string = '';
  /** 渐变方向是否斜向（左上 → 右下）；false 为纵向。 */
  public diagonal: boolean = false;
  /** 是否在外侧压一条细亮线（极稀有的双环）。 */
  public outerRing: boolean = false;
  /** 是否在主环内侧压一条 1px 细线（稀有）。 */
  public innerLine: boolean = false;
  constructor(top: string, mid: string, bottom: string, band: string, bandText: string) {
    this.top = top;
    this.mid = mid;
    this.bottom = bottom;
    this.band = band;
    this.bandText = bandText;
  }
}

/**
 * 材质 → 渐变 / 带色 / 分级装饰。
 *
 * **色值唯一事实源在代码**（本函数），文档 §4 只作说明，改色必须改这里。
 * 分级（文档 §4）：常见素环、少见斜向、稀有内圈细线、极稀有双环。
 */
function paletteOf(material: ShareCardMaterial): CardPalette {
  let palette: CardPalette;
  switch (material) {
    case ShareCardMaterial.GOLD:
      palette = new CardPalette('rgb(138,109,27)', 'rgb(245,217,122)', 'rgb(138,109,27)',
        'rgb(201,162,39)', 'rgb(26,20,0)');
      palette.outerRing = true;
      return palette;
    case ShareCardMaterial.ORANGE:
      return new CardPalette('rgb(179,74,0)', 'rgb(255,176,102)', 'rgb(179,74,0)',
        'rgb(232,106,23)', 'rgb(26,15,0)');
    case ShareCardMaterial.BLUE:
      palette = new CardPalette('rgb(29,78,216)', 'rgb(127,178,255)', 'rgb(29,78,216)',
        'rgb(29,78,216)', 'rgb(242,245,248)');
      palette.diagonal = true;
      return palette;
    case ShareCardMaterial.PURPLE:
      palette = new CardPalette('rgb(109,40,217)', 'rgb(196,165,255)', 'rgb(109,40,217)',
        'rgb(109,40,217)', 'rgb(242,245,248)');
      palette.innerLine = true;
      return palette;
    case ShareCardMaterial.RED:
      return new CardPalette('rgb(185,28,28)', 'rgb(255,138,122)', 'rgb(185,28,28)',
        'rgb(185,28,28)', 'rgb(242,245,248)');
    default:
      // 常见（钢）：素环，上下色值由 (58,69,82) 提亮到 (90,105,125)，带色同步协调。
      return new CardPalette('rgb(90,105,125)', 'rgb(138,153,173)', 'rgb(90,105,125)',
        'rgb(110,127,150)', 'rgb(242,245,248)');
  }
}

export class ShareCardContent {
  /** 主体图类名（不含 `hero-` 前缀与扩展名），如 `wearable`；未知一律回落 `other`。 */
  public heroClass: string = 'other';
  /** 等级带左侧：图鉴为 `x / 611`，安防为扫描日期。 */
  public bandLeft: string = '';
  /** 等级带右侧：tier / verdict 词。 */
  public bandRight: string = '';
  /** 名称（54 Bold 居中）。 */
  public name: string = '';
  /** 一行 trait：类别 · 关键信息。 */
  public trait: string = '';
  /** 强制脚注：不广播的设备发现不了（必须存在，见落地文档文案红线）。 */
  public footnote: string = '';
  /** 品牌行。 */
  public brand: string = '';
  /** 边框与等级带材质。 */
  public material: ShareCardMaterial = ShareCardMaterial.STEEL;
}

/** 已解码的主体图与其原始像素尺寸（cover 裁切要按原始比例算）。 */
class HeroBitmap {
  public pixelMap: image.PixelMap;
  public width: number;
  public height: number;
  constructor(pixelMap: image.PixelMap, width: number, height: number) {
    this.pixelMap = pixelMap;
    this.width = width;
    this.height = height;
  }
}

/**
 * 绘制分享卡并落盘。
 *
 * 为什么用离屏 Canvas 而不是截图：截图会把状态栏、底栏一起拍进去，
 * 那种图发到群里既不像成品、也泄露了用户的系统状态（时间/信号/电量）。
 */
export class FieldwatchShareCard {
  /**
   * 画一张卡并返回**沙箱内的绝对路径**；失败返回空串。
   *
   * 注意返回的是路径不是 URI：URI 由 `fileUriOf` 另外转换，
   * 因为「存相册」和「分享」两条路要的形态不同。
   */
  async render(content: ShareCardContent): Promise<string> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.error(TAG, '缺少 Ability 上下文，无法绘制分享卡');
      return '';
    }
    try {
      const settings: RenderingContextSettings = new RenderingContextSettings(true);
      // 构造参数是 (width, height, settings)，**不接受 OffscreenCanvas 实例**。
      // 上下文自己持有一块离屏画布，画完用 toDataURL 导出即可。
      const ctx: OffscreenCanvasRenderingContext2D =
        new OffscreenCanvasRenderingContext2D(SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT, settings);
      // 主体图必须先解成 PixelMap 再画：draw 是同步的，图片解码是异步的。
      const hero: HeroBitmap | undefined = await this.loadHero(context, content.heroClass);
      this.draw(ctx, content, hero);
      // **走 toDataURL 而不是 PixelMap**：`OffscreenCanvas` 没有直接产出 PixelMap 的接口
      // （`getPixelMap` 只挂在可见 Canvas 的渲染上下文上），而 `ImageBitmap` 也没有
      // `createPixelMapSafe`。`toDataURL` 是这套 API 里唯一确定可用的导出路径，
      // 代价是一次内存拷贝 —— 分享卡只画一次，可以接受。
      const dataUrl: string = ctx.toDataURL('image/png', 1);
      const path: string = this.writeDataUrl(context, dataUrl);
      return path;
    } catch (error) {
      logger.error(TAG, '绘制分享卡失败: ' + this.errorMessage(error));
      return '';
    }
  }

  /**
   * 读 rawfile 主体图并解成 PixelMap。
   *
   * 找不到对应类（含未来新增类别）时回落 `hero-other.webp`；
   * 连兜底图都解不出来时返回 undefined，由绘制层跳过图片区域（不画破图）。
   */
  private async loadHero(context: common.UIAbilityContext,
    heroClass: string): Promise<HeroBitmap | undefined> {
    const wanted: HeroBitmap | undefined = await this.decodeHero(context, heroClass);
    if (wanted !== undefined) return wanted;
    if (heroClass !== 'other') {
      logger.warn(TAG, '主体图缺失，回落 other: ' + heroClass);
      return await this.decodeHero(context, 'other');
    }
    return undefined;
  }

  private async decodeHero(context: common.UIAbilityContext,
    heroClass: string): Promise<HeroBitmap | undefined> {
    const file: string = 'sharecard/hero-' + heroClass + '.webp';
    try {
      const raw: Uint8Array = await context.resourceManager.getRawFileContent(file);
      const source: image.ImageSource = image.createImageSource(raw.buffer as ArrayBuffer);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const info: image.ImageInfo = await source.getImageInfo();
      return new HeroBitmap(pixelMap, info.size.width, info.size.height);
    } catch (error) {
      logger.warn(TAG, '主体图解码失败 ' + file + ': ' + this.errorMessage(error));
      return undefined;
    }
  }

  /**
   * 画布内容。纯绘制，不做任何 IO，便于将来替换成截图或其它输出。
   *
   * 版式严格按文档 §1：边框环 → 主体图 → 等级带 → 名称/trait → 脚注 → 品牌行，
   * 不再有雷达、堆叠条、三色块、日期角标、辉光网格。
   */
  private draw(ctx: OffscreenCanvasRenderingContext2D, content: ShareCardContent,
    hero: HeroBitmap | undefined): void {
    const palette: CardPalette = paletteOf(content.material);

    // 先清成透明：外圆角之外的四个角必须透明，不能留一块底色方块。
    ctx.clearRect(0, 0, SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT);

    // ① 边框环：外圆角矩形填渐变，再叠一个内圆角矩形填底色，露出的 12px 就是环。
    const ring: CanvasGradient = palette.diagonal
      ? ctx.createLinearGradient(0, 0, SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT)
      : ctx.createLinearGradient(0, 0, 0, SHARE_CARD_HEIGHT);
    ring.addColorStop(0, palette.top);
    ring.addColorStop(0.5, palette.mid);
    ring.addColorStop(1, palette.bottom);
    this.fillRoundedGradient(ctx, 0, 0, SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT, CARD_RADIUS, ring);
    this.fillRoundedColor(ctx, BORDER, BORDER, SHARE_CARD_WIDTH - BORDER * 2,
      SHARE_CARD_HEIGHT - BORDER * 2, INNER_RADIUS, CARD_BG);

    // 分级装饰（文档 §4）：常见素环 / 少见斜向 / 稀有内圈细线 / 极稀有双环。
    if (palette.outerRing) {
      this.strokeRounded(ctx, 5, 5, SHARE_CARD_WIDTH - 10, SHARE_CARD_HEIGHT - 10,
        CARD_RADIUS - 5, palette.mid, 2);
    }
    if (palette.innerLine) {
      const inset: number = BORDER + 3;
      this.strokeRounded(ctx, inset, inset, SHARE_CARD_WIDTH - inset * 2,
        SHARE_CARD_HEIGHT - inset * 2, INNER_RADIUS - 3, 'rgba(196,165,255,0.45)', 1);
    }

    // ② 主体图：先铺底色再 fit 画图，留边就是卡片底色。
    ctx.fillStyle = CARD_BG;
    ctx.fillRect(BORDER, BORDER, HERO_W, HERO_H);
    if (hero !== undefined) {
      this.clipHeroTop(ctx);
      // 源图与开槽同比例（1:2），按 696/源宽 等比缩放后从 (BORDER,BORDER) 起 1:1 贴合，
      // 既不裁切也不留边。**不用 9 参数的 drawImage**（在 PixelMap 上不生效）。
      const scale: number = HERO_W / hero.width;
      const drawH: number = hero.height * scale;
      // finder 主体略偏上：仅这一张下移，顶边空隙用边缘拉伸补齐。
      const shift: number = content.heroClass === 'finder' ? FINDER_OFFSET_Y : 0;
      if (shift > 0) {
        // 把源图顶部极薄的一条切片纵向拉伸填满空隙（顶部是深色纹理底，接缝不可见）。
        // 只在裁剪框内生效，不影响下方正常贴图。
        ctx.save();
        ctx.beginPath();
        ctx.rect(BORDER, BORDER, HERO_W, shift);
        ctx.clip();
        ctx.drawImage(hero.pixelMap, BORDER, BORDER, HERO_W, drawH * 12);
        ctx.restore();
      }
      ctx.drawImage(hero.pixelMap, BORDER, BORDER + shift, HERO_W, drawH);
      ctx.restore();
    }

    // ③ 等级带：饱和主色打底 + 对应文字色，左编号、右 tier / verdict 词。
    ctx.fillStyle = palette.band;
    ctx.fillRect(BORDER, BAND_Y, HERO_W, BAND_H);
    ctx.fillStyle = palette.bandText;
    ctx.font = 'bold 26px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(content.bandLeft, BORDER + SIDE_PAD, BAND_Y + BAND_H / 2);
    ctx.textAlign = 'right';
    ctx.fillText(content.bandRight, BORDER + HERO_W - SIDE_PAD, BAND_Y + BAND_H / 2);

    // ④ 名称 58 Bold 居中 + 一行 trait。
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = '#E8EDF2';
    // 安防档（可疑 / 确认）的名称用等宽字体：设备地址/编号读起来更整齐；
    // 图鉴卡保持原字体。等宽不可用时回落 sans-serif，名称不会因此画不出来。
    ctx.font = this.usesMonospaceName(content.material)
      ? 'bold 64px monospace, sans-serif'
      : 'bold 64px sans-serif';
    ctx.fillText(content.name, SHARE_CARD_WIDTH / 2, NAME_BASELINE);
    ctx.fillStyle = '#C3CAD2';
    ctx.font = '28px sans-serif';
    ctx.fillText(content.trait, SHARE_CARD_WIDTH / 2, TRAIT_BASELINE);

    // ⑤ 强制脚注（仅安防卡有内容；图鉴卡为空则跳过）。
    if (content.footnote.length > 0) {
      ctx.fillStyle = '#FFB020';
      ctx.font = '22px sans-serif';
      this.fillWrapped(ctx, content.footnote, SHARE_CARD_WIDTH / 2, FOOTNOTE_BASELINE,
        SHARE_CARD_WIDTH - BORDER * 2 - SIDE_PAD * 2, 30);
    }

    // ⑥ 品牌行。
    ctx.fillStyle = '#7D8A99';
    ctx.font = '22px sans-serif';
    ctx.fillText(content.brand, SHARE_CARD_WIDTH / 2, BRAND_BASELINE);
  }

  /** 安防档（可疑 / 确认）的名称用等宽字体，图鉴卡保持默认。 */
  private usesMonospaceName(material: ShareCardMaterial): boolean {
    return material === ShareCardMaterial.ORANGE || material === ShareCardMaterial.RED;
  }

  /** 圆角矩形路径（顺时针，四角同半径）。 */
  private roundRectPath(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number): void {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w, y + h - r);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r, y + h);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
  }

  private fillRoundedColor(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number, color: string): void {
    ctx.save();
    this.roundRectPath(ctx, x, y, w, h, r);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.restore();
  }

  private fillRoundedGradient(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number, gradient: CanvasGradient): void {
    ctx.save();
    this.roundRectPath(ctx, x, y, w, h, r);
    ctx.fillStyle = gradient;
    ctx.fill();
    ctx.restore();
  }

  private strokeRounded(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number, color: string, lineWidth: number): void {
    ctx.save();
    this.roundRectPath(ctx, x, y, w, h, r);
    ctx.strokeStyle = color;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
    ctx.restore();
  }

  /** 主体图顶部圆角裁剪路径（下沿保持直角）。 */
  private clipHeroTop(ctx: OffscreenCanvasRenderingContext2D): void {
    const x: number = BORDER;
    const y: number = BORDER;
    const right: number = x + HERO_W;
    const bottom: number = y + HERO_H;
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x, bottom);
    ctx.lineTo(x, y + HERO_RADIUS);
    ctx.arcTo(x, y, x + HERO_RADIUS, y, HERO_RADIUS);
    ctx.lineTo(right - HERO_RADIUS, y);
    ctx.arcTo(right, y, right, y + HERO_RADIUS, HERO_RADIUS);
    ctx.lineTo(right, bottom);
    ctx.closePath();
    ctx.clip();
  }

  /** 按宽度折行绘制；返回实际用掉的行数（调用方据此布局后续元素）。 */
  private fillWrapped(ctx: OffscreenCanvasRenderingContext2D, text: string, centerX: number,
    startY: number, maxWidth: number, lineHeight: number): number {
    const chars: string[] = [];
    for (let index: number = 0; index < text.length; index += 1) chars.push(text.charAt(index));
    let line: string = '';
    let lines: number = 1;
    let y: number = startY;
    for (let index: number = 0; index < chars.length; index += 1) {
      const next: string = line + chars[index];
      if (ctx.measureText(next).width > maxWidth && line.length > 0) {
        ctx.fillText(line, centerX, y);
        y += lineHeight;
        lines += 1;
        line = chars[index];
      } else {
        line = next;
      }
    }
    if (line.length > 0) ctx.fillText(line, centerX, y);
    return lines;
  }

  /**
   * data URL（`data:image/png;base64,…`）→ 沙箱 PNG 文件，返回绝对路径。
   *
   * 失败返回空串：调用方据此走「出卡失败」提示，而不是拿一个半截文件去分享。
   */
  private writeDataUrl(context: common.UIAbilityContext, dataUrl: string): string {
    const marker: string = 'base64,';
    const at: number = dataUrl.indexOf(marker);
    if (at < 0) {
      logger.error(TAG, '分享卡导出失败：toDataURL 未返回 base64');
      return '';
    }
    const base64: string = dataUrl.substring(at + marker.length);
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(base64);
    const dir: string = context.filesDir + '/' + CARD_DIR;
    this.ensureDir(dir);
    const path: string = dir + '/share-card-' + Date.now().toString() + '.png';
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      fileIo.closeSync(file);
    }
    return path;
  }

  private ensureDir(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir, true);
    } catch (error) {
      // 已存在时 mkdir 会抛，属正常路径。
      logger.debug(TAG, '创建卡片目录跳过: ' + this.errorMessage(error));
    }
  }

  /**
   * 沙箱路径 → 可分享的应用文件 URI。
   *
   * **必须用 `fileUri.getUriFromPath`，不能自己拼 `file://` + 裸路径。**
   * 手工拼出来的是普通文件 URI，ShareKit 会把它当外部资源去解析，
   * 实测直接抛 `1003702002 IPC data is oversized`（真机复现）。
   * `getUriFromPath` 产出的是**应用文件 URI**（`file://<bundleName>/...` 形态），
   * 只有它能被系统按「本应用授权共享」正确解析，且体积很小。
   */
  fileUriOf(path: string): string {
    const trimmed: string = path.trim();
    if (trimmed.length === 0) return '';
    try {
      return fileUri.getUriFromPath(trimmed);
    } catch (error) {
      logger.error(TAG, '生成应用文件 URI 失败: ' + this.errorMessage(error));
      return '';
    }
  }

  /** 图片的 UTD 字符串（`general.png`），分享与相册两处都用它。 */
  pngUtd(): string { return uniformTypeDescriptor.UniformDataType.PNG; }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

export const fieldwatchShareCard: FieldwatchShareCard = new FieldwatchShareCard();


/**
 * 主体图类名：把 `SignatureClass` 折叠历史别名后转成文件名里的类名。
 *
 * 文档 §2：`BODYWORN` → `wearable`、`ROUTER` → `isp`（与 `foldedSignatureClass` 一致），
 * 且 `LAW_ENFORCEMENT` 的文件名是 `hero-law-enforcement.webp`（下划线转连字符）。
 */
export function heroClassOf(value: SignatureClass): string {
  const folded: SignatureClass = foldedSignatureClass(value);
  return folded.toString().split('_').join('-');
}

/** 有设备才值得出卡：空扫描不发分享卡。 */
export function shareCardWorthPosting(summary: SecuritySummary): boolean {
  return summary.hasDevices();
}
