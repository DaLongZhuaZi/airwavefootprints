import { pdfService } from '@kit.PDFKit';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchDebriefPdf';

/**
 * 复盘 PDF 生成器。
 *
 * 原版是 Android Canvas 手绘（DebriefPdf.kt，1143 行）；鸿蒙侧没有等价的绘制+分页 API，
 * 但 HMS 的 PDFKit 提供了 createDocument / insertBlankPage / addTextObject / saveDocument，
 * 因此这里走「文本流 + 自动分页」的等价实现，并沿用原版的纸张与版心尺寸。
 */
export class FieldwatchDebriefPdf {
  /** Letter 尺寸（点），与原版 DebriefPdf 的 PAGE_W / PAGE_H 一致。 */
  private static readonly PAGE_W: number = 612;
  private static readonly PAGE_H: number = 792;
  /** 版心边距（点）。 */
  private static readonly MARGIN: number = 48;
  /** 行高（点）。 */
  private static readonly LINE_H: number = 13;
  /** 正文字号（点）。 */
  private static readonly FONT_SIZE: number = 9.5;
  /** 每行最大「半角宽度」；CJK 按 2 计。 */
  private static readonly MAX_WIDTH: number = 104;
  /** 正文色 #12171C；PDFKit 的 textColor 是 BGR，所以要倒序。 */
  private static readonly INK: number = 0x1C1712;
  /** 系统字体：HarmonyOS_Sans_SC 同时覆盖中英文；TextStyle.fontInfo 是必填项。 */
  private static readonly FONT_PATH: string = '/system/fonts/HarmonyOS_Sans_SC.ttf';

  /** 把复盘文本折行到固定宽度。 */
  private wrap(text: string): string[] {
    const out: string[] = [];
    text.split(String.fromCharCode(10)).forEach((raw: string): void => {
      let line: string = raw;
      if (line.length === 0) { out.push(''); return; }
      while (line.length > 0) {
        let width: number = 0;
        let cut: number = 0;
        while (cut < line.length) {
          const code: number = line.charCodeAt(cut);
          const wide: boolean = code > 0x2E80;
          const next: number = width + (wide ? 2 : 1);
          if (next > FieldwatchDebriefPdf.MAX_WIDTH) break;
          width = next;
          cut += 1;
        }
        if (cut === 0) cut = 1;
        out.push(line.substring(0, cut));
        line = line.substring(cut);
      }
    });
    return out;
  }

  /**
   * 生成 PDF 到 outPath。成功返回该路径，失败返回空串。
   * 失败时不抛异常：调用方据此显示「导出失败」而不是崩溃。
   */
  build(text: string, outPath: string): string {
    try {
      const document: pdfService.PdfDocument = new pdfService.PdfDocument();
      if (!document.createDocument(FieldwatchDebriefPdf.PAGE_W, FieldwatchDebriefPdf.PAGE_H)) {
        logger.warn(TAG, 'createDocument 返回 false');
        return '';
      }
      const lines: string[] = this.wrap(text);
      const usable: number = FieldwatchDebriefPdf.PAGE_H - FieldwatchDebriefPdf.MARGIN * 2;
      const perPage: number = Math.floor(usable / FieldwatchDebriefPdf.LINE_H);
      let cursor: number = 0;
      let pageIndex: number = 0;
      do {
        const page: pdfService.PdfPage = document.insertBlankPage(pageIndex, FieldwatchDebriefPdf.PAGE_W, FieldwatchDebriefPdf.PAGE_H);
        let y: number = FieldwatchDebriefPdf.PAGE_H - FieldwatchDebriefPdf.MARGIN;
        for (let index: number = 0; index < perPage && cursor < lines.length; index += 1) {
          const style: pdfService.TextStyle = new pdfService.TextStyle();
          const font: pdfService.FontInfo = new pdfService.FontInfo();
          font.fontPath = FieldwatchDebriefPdf.FONT_PATH;
          style.fontInfo = font;
          style.textSize = FieldwatchDebriefPdf.FONT_SIZE;
          style.textColor = FieldwatchDebriefPdf.INK;
          page.addTextObject(lines[cursor], FieldwatchDebriefPdf.MARGIN, y, style);
          y -= FieldwatchDebriefPdf.LINE_H;
          cursor += 1;
        }
        pageIndex += 1;
      } while (cursor < lines.length);
      if (!document.saveDocument(outPath)) {
        logger.warn(TAG, 'saveDocument 返回 false: ' + outPath);
        return '';
      }
      logger.info(TAG, '复盘 PDF 已生成: ' + pageIndex.toString() + ' 页 -> ' + outPath);
      return outPath;
    } catch (error) {
      logger.warn(TAG, '生成复盘 PDF 异常: ' + (error instanceof Error ? error.message : String(error)));
      return '';
    }
  }
}