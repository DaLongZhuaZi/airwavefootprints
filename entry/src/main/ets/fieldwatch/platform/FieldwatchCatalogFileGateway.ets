import { fileIo, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger, resolveResourceString, uiContextManager } from 'ngf_framework';
import { orderedSaveSuffixes, SAVE_SUFFIX_CHOICES } from '../domain/FieldwatchExportNaming';

const TAG: string = 'FieldwatchCatalogFile';

export enum FieldwatchFileSelectionKind {
  SIGNATURE_PACK = 'signature_pack',
  SETTINGS_BACKUP = 'settings_backup'
}

export enum FieldwatchFileSaveResult {
  SAVED = 'saved',
  NOT_SAVED = 'not_saved',
  FAILED = 'failed'
}

export enum FieldwatchFileActionStatus {
  SUCCESS = 'success',
  NOT_SELECTED = 'not_selected',
  FAILED = 'failed'
}

export class FieldwatchFileReadResult {
  public status: FieldwatchFileActionStatus = FieldwatchFileActionStatus.FAILED;
  public content: string = '';

  constructor(status: FieldwatchFileActionStatus, content: string = '') {
    this.status = status;
    this.content = content;
  }
}

/**
 * 特征库/报告的用户文件通道：经系统文件选择器导出与导入。
 *
 * 只在用户主动点击时调用；不联网，也不访问未选择的路径。
 * 选择器无 URI 按“未选择”处理；异常和读取失败单独返回失败状态。
 */
export class FieldwatchCatalogFileGateway {
  /**
   * 让用户选择保存位置并写出文本。空 URI 按未保存处理；只有用户显式
   * 选择“保存到下载目录”时才调用 DOWNLOAD 通道。
   */
  async saveToFile(fileName: string, content: string): Promise<FieldwatchFileSaveResult> {
    return await this.saveToFileWithChoices(fileName, content, orderedSaveSuffixes(fileName, SAVE_SUFFIX_CHOICES));
  }

  /**
   * 设置备份另存为。
   *
   * 保存侧只接受**纯后缀**；`fileSuffixChoices` 不是 `fileSuffixFilters`，
   * 传「描述|后缀」筛选串会被当成后缀名（此前就是这么传的）。
   */
  async saveSettingsBackupToFile(fileName: string, content: string): Promise<FieldwatchFileSaveResult> {
    return await this.saveToFileWithChoices(fileName, content, orderedSaveSuffixes(fileName, ['.fieldwatch']));
  }

  private async saveToFileWithChoices(fileName: string, content: string, suffixChoices: string[]): Promise<FieldwatchFileSaveResult> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '导出失败：没有 Ability 上下文');
      return FieldwatchFileSaveResult.FAILED;
    }
    let uri: string = '';
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = suffixChoices;
      logger.info(TAG, '即将拉起保存选择器: ' + fileName);
      const uris: string[] = await documentPicker.save(options);
      logger.info(TAG, 'save() 返回 ' + (uris === undefined ? 0 : uris.length).toString() + ' 个 URI');
      if (uris === undefined || uris.length === 0 || uris[0].length === 0) {
        logger.info(TAG, '未取得保存位置，文件未写出');
        return FieldwatchFileSaveResult.NOT_SAVED;
      }
      uri = uris[0];
    } catch (error) {
      logger.warn(TAG, '保存选择器异常: ' + this.errorMessage(error));
      return FieldwatchFileSaveResult.FAILED;
    }
    try {
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        const written: number = fileIo.writeSync(file.fd, content);
        logger.info(TAG, '已写出 ' + written.toString() + ' 字节到用户选择的位置');
      } finally {
        fileIo.closeSync(file);
      }
      return FieldwatchFileSaveResult.SAVED;
    } catch (error) {
      logger.warn(TAG, '写入选定文件失败: ' + this.errorMessage(error));
      return FieldwatchFileSaveResult.FAILED;
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
  /** 让用户选择文件并读出文本，区分未选文件和读取失败。 */
  async pickAndRead(selectionKind: FieldwatchFileSelectionKind = FieldwatchFileSelectionKind.SIGNATURE_PACK): Promise<FieldwatchFileReadResult> {
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) {
      logger.warn(TAG, '导入失败：没有 Ability 上下文');
      return new FieldwatchFileReadResult(FieldwatchFileActionStatus.FAILED);
    }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const filter: string = selectionKind === FieldwatchFileSelectionKind.SETTINGS_BACKUP
        ? resolveResourceString(context, $r('app.string.fieldwatch_settings_backup_file_filter'))
        : resolveResourceString(context, $r('app.string.fieldwatch_signatures_import_filter'));
      options.fileSuffixFilters = [filter];
      const uris: string[] = await documentPicker.select(options);
      logger.info(TAG, 'select() 返回 ' + (uris === undefined ? 0 : uris.length).toString() + ' 个 URI');
      if (uris === undefined || uris.length === 0 || uris[0].length === 0) {
        return new FieldwatchFileReadResult(FieldwatchFileActionStatus.NOT_SELECTED);
      }
      return new FieldwatchFileReadResult(FieldwatchFileActionStatus.SUCCESS, this.readText(uris[0]));
    } catch (error) {
      logger.warn(TAG, '选择或读取文件失败: ' + this.errorMessage(error));
      return new FieldwatchFileReadResult(FieldwatchFileActionStatus.FAILED);
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
