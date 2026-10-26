import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ISystemShare } from '../contracts/ISystemShare';
import { uiContextManager } from '../../platformOhos/UIContextManager';
import { logger } from '../../utils/Logger';

const TAG: string = 'SystemShareFacade';

export class SystemShareFacade implements ISystemShare {

  shareText(text: string): void {
    const context = uiContextManager.getFullAbilityContext();
    if (!context) {
      logger.error(TAG, '缺少 UIAbilityContext，无法拉起分享面板');
      return;
    }

    try {
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: text
      });

      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      
      let contextUI = uiContextManager.getUIContext();
      if (!context) {
        logger.error(TAG, '缺少 UIAbilityContext');
        return;
      }
      
      controller.show(context as common.UIAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {
        logger.info(TAG, '成功拉起原生系统 ShareKit 分享面板');
      }).catch((e: Error) => {
        logger.error(TAG, '拉起分享面板异常: ' + e);
      });
    } catch (e) {
      logger.error(TAG, '拉起分享面板失败: ' + e);
    }
  }

  /**
   * 分享一个本机文件（图片/文档）。
   *
   * 与 `shareText` 走同一条 ShareKit 链路，只是记录里用 `uri` 而不是 `content`。
   * ShareKit 的注释明确：`content` 与 `uri` **必须二选一**，同时给会参数错误，
   * 所以这里单独构造一条文件记录，不复用文本那条。
   *
   * `label` 决定分享面板的归类（IMAGE / FILE / VIDEO …）。不传的话部分目标
   * 应用会拿到一个类型不明的附件，只能按文件下载 —— 图片分享看起来就像坏了。
   */
  shareFile(fileUri: string, utd: string, title: string, label: string): void {
    const context = uiContextManager.getFullAbilityContext();
    if (!context) {
      logger.error(TAG, '缺少 UIAbilityContext，无法拉起分享面板');
      return;
    }
    const uri: string = fileUri.trim();
    if (uri.length === 0) {
      logger.error(TAG, '分享文件失败：uri 为空');
      return;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: utd,
        uri: uri,
        title: title,
        label: label
      };
      const shareData: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(context as common.UIAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).then(() => {
        logger.info(TAG, '文件分享面板已拉起: ' + label);
      }).catch((e: Error) => {
        logger.error(TAG, '拉起文件分享面板异常: ' + e.message);
      });
    } catch (e) {
      logger.error(TAG, '拉起文件分享面板失败: ' + e);
    }
  }
}

export const ngfSystemShareFacade: ISystemShare = new SystemShareFacade();
