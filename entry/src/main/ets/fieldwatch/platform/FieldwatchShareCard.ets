import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { logger, uiContextManager } from 'ngf_framework';
import { SecurityClassCount, SecuritySummary } from '../domain/FieldwatchSecurityScan';

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

/**
 * 分享卡绘制所需的全部输入（不含任何文案）。
 *
 * **文案不进这个类**：卡片上的每一个字都必须是调用方从资源文件取来的，
 * 否则「不出现防偷拍/查摄像头」这条红线就多了一个绕不过去的入口。
 */
export class ShareCardContent {
  /** 大标题，如「扫描完成」。 */
  public title: string = '';
  /** 一句话结论（由 `summaryHeadlineKey` 选出的资源文案）。 */
  public headline: string = '';
  /** 设备总数那行的大数字。 */
  public totalText: string = '';
  /** 总数下方的标签，如「台设备正在广播」。 */
  public totalLabel: string = '';
  /** 分类 Top（已翻译好的「类别 数量」两段）。 */
  public classLabels: string[] = [];
  public classCounts: string[] = [];
  /** 「新面孔 N 台」这类附加行，已翻译。 */
  public extraLines: string[] = [];
  /** 脚注：不广播的设备发现不了（必须存在，见落地文档文案红线）。 */
  public footnote: string = '';
  /** 品牌行（应用名），画在页脚。 */
  public brand: string = '';
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
   * 注意返回的是路径不是 URI：URI 由 `shareUriOf` 另外转换，
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
      this.draw(ctx, content);
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
   * 画布内容。纯绘制，不做任何 IO，便于将来替换成截图或其它输出。
   *
   * **所有尺寸都按画布宽度等比换算**（`s(px)` = px * WIDTH / 1080）：
   * 布局是按 1080 宽设计的，直接改画布尺寸会让文字挤在一起或留白失控。
   * 想再调总尺寸时只改 `SHARE_CARD_WIDTH` 即可，这里不需要动。
   */
  private draw(ctx: OffscreenCanvasRenderingContext2D, content: ShareCardContent): void {
    const scale: number = SHARE_CARD_WIDTH / 1080;
    const s = (value: number): number => value * scale;
    // 底色：与 App 深色主题同一套色值，避免分享卡和界面像两个产品。
    ctx.fillStyle = '#0B0F14';
    ctx.fillRect(0, 0, SHARE_CARD_WIDTH, SHARE_CARD_HEIGHT);
    // 顶部柔光：一块低透明度径向渐变，让纯色底不至于死板。
    const glow: CanvasGradient = ctx.createRadialGradient(SHARE_CARD_WIDTH * 0.5, s(180), s(20),
      SHARE_CARD_WIDTH * 0.5, s(180), SHARE_CARD_WIDTH * 0.9);
    glow.addColorStop(0, 'rgba(61,255,154,0.18)');
    glow.addColorStop(1, 'rgba(11,15,20,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, SHARE_CARD_WIDTH, s(760));

    ctx.textAlign = 'center';
    // 标题
    ctx.fillStyle = '#3DFF9A';
    ctx.font = '600 ' + Math.round(s(44)).toString() + 'px sans-serif';
    ctx.fillText(content.title, SHARE_CARD_WIDTH / 2, s(150));

    // 一句话结论
    ctx.fillStyle = '#E8EDF2';
    ctx.font = '700 ' + Math.round(s(68)).toString() + 'px sans-serif';
    this.fillWrapped(ctx, content.headline, SHARE_CARD_WIDTH / 2, s(260), SHARE_CARD_WIDTH - s(160), s(86));

    // 大数字
    ctx.fillStyle = '#3DFF9A';
    ctx.font = '700 ' + Math.round(s(190)).toString() + 'px sans-serif';
    ctx.fillText(content.totalText, SHARE_CARD_WIDTH / 2, s(600));
    ctx.fillStyle = '#9AA6B2';
    ctx.font = '400 ' + Math.round(s(40)).toString() + 'px sans-serif';
    ctx.fillText(content.totalLabel, SHARE_CARD_WIDTH / 2, s(668));

    // 分类 Top：三行，左标签右数量
    let y: number = s(800);
    ctx.font = '400 ' + Math.round(s(44)).toString() + 'px sans-serif';
    for (let index: number = 0; index < content.classLabels.length; index += 1) {
      ctx.textAlign = 'left';
      ctx.fillStyle = '#D5DCE3';
      ctx.fillText(content.classLabels[index], s(140), y);
      ctx.textAlign = 'right';
      ctx.fillStyle = '#3DFF9A';
      const countText: string = index < content.classCounts.length ? content.classCounts[index] : '';
      ctx.fillText(countText, SHARE_CARD_WIDTH - s(140), y);
      y += s(78);
    }

    // 附加行（新面孔 / 跟随评分）
    ctx.textAlign = 'left';
    ctx.font = '400 ' + Math.round(s(40)).toString() + 'px sans-serif';
    for (let index: number = 0; index < content.extraLines.length; index += 1) {
      ctx.fillStyle = '#9AA6B2';
      ctx.fillText(content.extraLines[index], s(140), y + s(40));
      y += s(68);
    }

    // 分隔线
    ctx.strokeStyle = '#2A3340';
    ctx.lineWidth = Math.max(1, Math.round(s(2)));
    ctx.beginPath();
    ctx.moveTo(s(140), SHARE_CARD_HEIGHT - s(200));
    ctx.lineTo(SHARE_CARD_WIDTH - s(140), SHARE_CARD_HEIGHT - s(200));
    ctx.stroke();

    // 脚注：**必须存在**（不广播的设备发现不了）。用暖色提醒它是限制而不是装饰。
    ctx.fillStyle = '#FFB020';
    ctx.font = '400 ' + Math.round(s(34)).toString() + 'px sans-serif';
    ctx.textAlign = 'center';
    this.fillWrapped(ctx, content.footnote, SHARE_CARD_WIDTH / 2, SHARE_CARD_HEIGHT - s(140),
      SHARE_CARD_WIDTH - s(240), s(46));

    // 品牌行
    ctx.fillStyle = '#5C6875';
    ctx.font = '400 ' + Math.round(s(30)).toString() + 'px sans-serif';
    ctx.fillText(content.brand, SHARE_CARD_WIDTH / 2, SHARE_CARD_HEIGHT - s(50));
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
    const path: string = dir + '/security-card-' + Date.now().toString() + '.png';
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
 * 分享卡的主路径说明（写在代码里，避免后来者又去查）。
 *
 * 落地文档 P1-5 原本给的是「若 NGF 门面不支持图片分享，就用存相册兜底」。
 * 实测核实结果：**门面确实不支持**，但 ShareKit 本身支持 ——
 * `SharedRecord.uri` 接受应用文件 URI，配合 `utd: general.png` 与 `label: 'IMAGE'` 即可。
 * 因此本模块选择**把门面补齐**（`ngfSystemShareFacade.shareFile`），
 * 而不是降级到「存相册 + 提示用户自己分享」：
 *   · 存相册要多一次系统授权弹窗，且用户在相册里还要再操作一遍；
 *   · 补齐门面是一处通用能力，将来别人的图片分享也能直接复用。
 * 文档里那条兜底路径**因此不再需要**，不记为待补项。
 */

/** 分类 Top 的一行，供 UI 组装 `ShareCardContent`。 */
export class ShareClassRow {
  public label: string;
  public count: string;
  constructor(label: string = '', count: string = '') { this.label = label; this.count = count; }
}

/** 把汇总里的分类计数拆成两段（标签由 UI 翻译，数量直接转字符串）。 */
export function shareClassRows(counts: SecurityClassCount[]): ShareClassRow[] {
  const rows: ShareClassRow[] = [];
  counts.forEach((item: SecurityClassCount): void => {
    rows.push(new ShareClassRow(String(item.category), item.count.toString()));
  });
  return rows;
}

/** 供单测用：汇总里是否满足「值得说一句」的条件。 */
export function shareCardWorthPosting(summary: SecuritySummary): boolean {
  return summary.hasDevices();
}
