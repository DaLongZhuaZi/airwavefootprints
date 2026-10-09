import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger, uiContextManager } from 'ngf_framework';

const TAG: string = 'FieldwatchCatalogFile';
const SUFFIX_CHOICES: string[] = ['.json', '.txt', '.csv'];
const SUFFIX_FILTERS: string[] = ['电波足迹 导出 (.json, .txt, .csv)|.json,.txt,.csv'];

/**
 * 特征库/报告的用户文件通道：经系统文件选择器导出与导入。
 *
 * 只在用户主动点击时调用；不联网，也不访问未选择的路径。
 * 每一步都写日志，因为 picker 失败时常常既不抛异常也不返回 URI，
 * 没有日志就无法区分「用户取消」和「选择器没起来」。
 */
export class FieldwatchCatalogFileGateway {
  /**
   * 让用户选择保存位置并写出文本。
   *
   * **带回退**：真机实测过「选择器被拉起但 `save()` 不返回 URI」的情况 ——
   * 用户看不到任何反应，以为功能坏了。因此选择器拿不到位置时，
   * 自动改走 DOWNLOAD 通道（那条路不需要在选择器里确认，此前已实测可用），
   * 至少保证文件真的落到下载目录，而不是静默失败。
   *
   * 用户主动取消选择器时也会走到回退 —— 这是刻意的：
   * 无法区分「取消」与「选择器没起来」，宁可多写一个文件，也不要让功能看起来没反应。
   */
  async saveToFile(fileName: string, content: string): Promise<boolean> {
    const uris: string[] = await this.pickSaveUri(fileName);
    logger.info(TAG, 'save() 返回 ' + uris.length.toString() + ' 个 URI');
    if (uris.length === 0) {
      logger.warn(TAG, '未取得保存位置，回退到下载目录通道');
      return await this.saveToDownloads(fileName, content);
    }
    try {
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        const written: number = fileIo.writeSync(file.fd, content);
        logger.info(TAG, '已写出 ' + written.toString() + ' 字节到用户选择的位置');
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (error) {
      logger.warn(TAG, '写入选定文件失败: ' + this.errorMessage(error));
      return false;
    }
  }
  /**
   * 直接写入系统下载目录（pickerMode = DOWNLOAD，不弹选择器）。
   * 选择器需要用户手动确认，自动化与无障碍场景下很脆弱；这条通道一键完成。
   * 代价：DOWNLOAD 模式下 newFileNames 不生效，文件名由系统生成。
   */
  async saveToDownloads(fileName: string, content: string): Promise<boolean> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '保存到下载目录失败：没有 Ability 上下文');
      return false;
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris: string[] = await documentPicker.save(options);
      logger.info(TAG, 'DOWNLOAD 模式 save() 返回 ' + (uris === undefined ? 0 : uris.length).toString() + ' 个 URI');
      if (uris === undefined || uris.length === 0) return false;
      // DOWNLOAD 模式返回的是系统为本应用准备的下级目录，需要在其中创建文件。
      let target: string = uris[0];
      const stat: fileIo.Stat = fileIo.statSync(target);
      if (stat.isDirectory()) target = target + '/' + fileName;
      logger.info(TAG, '目标路径是否为目录: ' + stat.isDirectory().toString());
      const file: fileIo.File = fileIo.openSync(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const written: number = fileIo.writeSync(file.fd, content);
        logger.info(TAG, '已写入下载目录 ' + written.toString() + ' 字节');
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (error) {
      logger.warn(TAG, '保存到下载目录异常: ' + this.errorMessage(error));
      return false;
    }
  }
  private async pickSaveUri(fileName: string): Promise<string[]> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '导出失败：没有 Ability 上下文');
      return [];
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = SUFFIX_CHOICES;
      logger.info(TAG, '即将拉起保存选择器: ' + fileName);
      const result: string[] = await documentPicker.save(options);
      return result === undefined ? [] : result;
    } catch (error) {
      logger.warn(TAG, '保存选择器异常: ' + this.errorMessage(error));
      return [];
    }
  }

  /** 让用户选择文件并读出文本。取消返回空字符串。 */
  async pickAndRead(): Promise<string> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '导入失败：没有 Ability 上下文');
      return '';
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = SUFFIX_FILTERS;
      const uris: string[] = await documentPicker.select(options);
      logger.info(TAG, 'select() 返回 ' + (uris === undefined ? 0 : uris.length).toString() + ' 个 URI');
      if (uris === undefined || uris.length === 0) return '';
      return this.readText(uris[0]);
    } catch (error) {
      logger.warn(TAG, '导入签名包失败: ' + this.errorMessage(error));
      return '';
    }
  }

  private readText(uri: string): string {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const size: number = stat.size;
      if (size <= 0) return '';
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      const read: number = fileIo.readSync(file.fd, buffer);
      if (read <= 0) return '';
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer.slice(0, read)));
    } finally {
      fileIo.closeSync(file);
    }
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}