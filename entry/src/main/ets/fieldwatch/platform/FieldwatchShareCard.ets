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
export const SHARE_CARD_HEIGHT: number = 1080;

// ── 收藏卡版式常量（文档 §1「卡片语法」）────────────────────────────────
//
// 画布 720×1080，元素自上而下只有 6 样：边框环 / 主体图 / 等级带 / 名称+trait /
// 脚注 / 品牌行。旧版元素（雷达、堆叠条、三色块、日期角标、辉光网格）全部删除。
/** 边框环宽度：12px 渐变环，颜色即稀有度 / verdict 材质。 */
const BORDER: number = 12;
/** 主体图展示区：cover 裁切 696×688，顶部圆角 26、下直角。 */
const HERO_W: number = 696;
const HERO_H: number = 688;
const HERO_RADIUS: number = 26;
/** 等级带：44 高，紧贴主体图下沿。 */
const BAND_H: number = 44;
const BAND_Y: number = BORDER + HERO_H;
/** 名称 54 Bold 的基线；trait 紧随其后。 */
const NAME_BASELINE: number = BAND_Y + BAND_H + 68;
const TRAIT_BASELINE: number = NAME_BASELINE + 36;
/** 强制脚注（琥珀原句）。 */
const FOOTNOTE_BASELINE: number = 928;
/** 品牌行基线。 */
const BRAND_BASELINE: number = SHARE_CARD_HEIGHT - 34;

/** 卡片内边距（等级带与正文的左右留白）。 */
const SIDE_PAD: number = 26;

/** 背景底色：与 App 深色主题同一套色值，避免分享卡和界面像两个产品。 */
const CARD_BG: string = '#0B0F14';

/**
 * 卡片材质：决定边框渐变与等级带颜色。
 *
 * 六个取值分别对应「图鉴稀有度四档 + 安防 verdict 三档」里会上卡的组合，
 * 色值见 {@link paletteOf}（来源：docs/分享卡收藏卡素材说明.md §4）。
 */
export enum ShareCardMaterial {
  /** 极稀有（金）。 */
  GOLD = 'gold',
  /** 常见（深钢）。 */
  STEEL = 'steel',
  /** 少见（蓝）。 */
  BLUE = 'blue',
  /** 稀有（紫）。 */
  PURPLE = 'purple',
  /** 安防：确认（红）。 */
  RED = 'red',
  /** 安防：可疑（橙）。 */
  ORANGE = 'orange'
}

/** 三段纵向渐变（上 → 中 → 下）。等级带取中间色。 */
class CardPalette {
  public top: string = '';
  public mid: string = '';
  public bottom: string = '';
  constructor(top: string, mid: string, bottom: string) {
    this.top = top;
    this.mid = mid;
    this.bottom = bottom;
  }
}

/**
 * 材质 → 三段渐变。
 *
 * **色值唯一事实源是文档 §4**，代码里不留第二套口径：
 * 金 / 橙为文档已验证值，深钢 / 蓝 / 紫 / 红为文档拟定值（落码后已回写文档）。
 */
function paletteOf(material: ShareCardMaterial): CardPalette {
  switch (material) {
    case ShareCardMaterial.GOLD:
      return new CardPalette('rgb(138,109,27)', 'rgb(245,217,122)', 'rgb(138,109,27)');
    case ShareCardMaterial.ORANGE:
      return new CardPalette('rgb(179,74,0)', 'rgb(255,176,102)', 'rgb(179,74,0)');
    case ShareCardMaterial.BLUE:
      return new CardPalette('rgb(29,78,216)', 'rgb(127,178,255)', 'rgb(29,78,216)');
    case ShareCardMaterial.PURPLE:
      return new CardPalette('rgb(109,40,217)', 'rgb(196,165,255)', 'rgb(109,40,217)');
    case ShareCardMaterial.RED:
      return new CardPalette('rgb(185,28,28)', 'rgb(255,138,122)', 'rgb(185,28,28)');
    default:
      return new CardPalette('rgb(58,69,82)', 'rgb(138,153,173)', 'rgb(58,69,82)');
  }
}

/**
 * 卡片上的全部文字（不含任何内置文案）。
 *
 * **文案不进这个类**：卡片上的每一个字都必须由调用方从资源文件取来，
 * 否则「不出现防偷拍/查摄像头」这条红线就多了一个绕不过去的入口。
 */
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

/** cover 裁切的源矩形。 */
class CoverRect {
  public sx: number = 0;
  public sy: number = 0;
  public sw: number = 0;
  public sh: number = 0;
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

    // ① 边框：整块铺三段纵向渐变，随后用深色底盖住内部，露出的 12px 就是环。
    const ring: CanvasGradient = ctx.createLinearGradient(0, 0, 0, SHARE_CARD_HEIGHT);
    ring.addColorStop(0, palette.top);
    ring.addColorStop(0.5, palette.mid);
    ring.addColorStop(1, palette.bottom);
    ctx.fillStyle = ring;
    ctx.fillRect(0, 0, SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT);
    ctx.fillStyle = CARD_BG;
    ctx.fillRect(BORDER, BORDER, SHARE_CARD_WIDTH - BORDER * 2, SHARE_CARD_HEIGHT - BORDER * 2);

    // ② 主体图：顶部圆角 26、下直角，cover 裁切填满 696×688。
    if (hero !== undefined) {
      this.clipHeroTop(ctx);
      const cover: CoverRect = this.coverOf(hero.width, hero.height, HERO_W, HERO_H);
      // **不用 9 参数的 drawImage**：在 PixelMap 上它没有按 (sx,sy,sw,sh,dx,dy,dw,dh)
      // 缩放，真机出图时主体图被画成左上角一小块、下面整片黑（实测）。
      // 改成「整图按比例放大 + 负偏移」再用裁剪框取景：只用 5 参数重载，行为确定。
      const scale: number = HERO_W / cover.sw;
      ctx.drawImage(hero.pixelMap,
        BORDER - cover.sx * scale,
        BORDER - cover.sy * scale,
        hero.width * scale,
        hero.height * scale);
      ctx.restore();
    }

    // ③ 等级带：中间色打底，左编号、右 tier / verdict 词。
    ctx.fillStyle = palette.mid;
    ctx.fillRect(BORDER, BAND_Y, HERO_W, BAND_H);
    ctx.fillStyle = CARD_BG;
    ctx.font = 'bold 24px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(content.bandLeft, BORDER + SIDE_PAD, BAND_Y + BAND_H / 2);
    ctx.textAlign = 'right';
    ctx.fillText(content.bandRight, BORDER + HERO_W - SIDE_PAD, BAND_Y + BAND_H / 2);

    // ④ 名称 54 Bold 居中 + 一行 trait。
    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = '#E8EDF2';
    ctx.font = 'bold 54px sans-serif';
    ctx.fillText(content.name, SHARE_CARD_WIDTH / 2, NAME_BASELINE);
    ctx.fillStyle = '#9AA6B2';
    ctx.font = '24px sans-serif';
    ctx.fillText(content.trait, SHARE_CARD_WIDTH / 2, TRAIT_BASELINE);

    // ⑤ 强制脚注：琥珀原句，折行居中。
    ctx.fillStyle = '#FFB020';
    ctx.font = '22px sans-serif';
    this.fillWrapped(ctx, content.footnote, SHARE_CARD_WIDTH / 2, FOOTNOTE_BASELINE,
      SHARE_CARD_WIDTH - BORDER * 2 - SIDE_PAD * 2, 30);

    // ⑥ 品牌行。
    ctx.fillStyle = '#6B7885';
    ctx.font = '20px sans-serif';
    ctx.fillText(content.brand, SHARE_CARD_WIDTH / 2, BRAND_BASELINE);
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

  /**
   * cover 裁切：把源图按目标宽高比裁一块，**不留黑边**。
   *
   * 焦点取画面上半部（文档 §3：裁切焦点约在画面上半部 1/3–1/2 处）——
   * 主体图是竖构图产品照，设备居中偏上，取中间会把设备头顶切掉。
   */
  private coverOf(srcW: number, srcH: number, dstW: number, dstH: number): CoverRect {
    const rect: CoverRect = new CoverRect();
    if (srcW <= 0 || srcH <= 0) {
      rect.sw = srcW;
      rect.sh = srcH;
      return rect;
    }
    const targetAspect: number = dstW / dstH;
    const srcAspect: number = srcW / srcH;
    if (srcAspect > targetAspect) {
      // 源更宽：左右各裁一刀。
      rect.sh = srcH;
      rect.sw = srcH * targetAspect;
      rect.sx = (srcW - rect.sw) / 2;
      rect.sy = 0;
    } else {
      // 源更高：上下裁，焦点偏上。
      rect.sw = srcW;
      rect.sh = srcW / targetAspect;
      rect.sx = 0;
      rect.sy = (srcH - rect.sh) * 0.35;
    }
    return rect;
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
