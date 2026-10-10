import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { clearContext, NGFAbilityContextLike, setContext } from '../GlobalContext';
import { uiContextManager } from 'ngf_framework';
import { ngfStarterKernel } from 'ngf_framework';

import { ngfPlatformWindowManagerFacade } from 'ngf_framework';
import { ngfThemeManagerFacade, NGFThemeMode } from 'ngf_framework';
import { ngfI18nManagerFacade } from 'ngf_framework';
import { ngfHoldingAwarenessFacade } from 'ngf_framework';
import { ngfDeviceAdaptationFacade } from 'ngf_framework';
import { ngfVisualEffectsFacade } from 'ngf_framework';
import { ngfScreenKeepAwakeFacade } from 'ngf_framework';
import { logger } from 'ngf_framework';
import { crashAnalytics } from 'ngf_framework';
import { ngfContinuationManagerFacade } from 'ngf_framework';
import { fieldwatchApplication } from '../fieldwatch/application/FieldwatchApplication';
import { fieldwatchDeepLinkBridge } from '../fieldwatch/platform/FieldwatchDeepLink';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const abilityContext = this.context as NGFAbilityContextLike;
    setContext(abilityContext);
    uiContextManager.bindAbilityContext(this.context as common.UIAbilityContext);
    const bootstrapResult = ngfStarterKernel.bootstrap();
    void ngfScreenKeepAwakeFacade.initialize(this.context as common.UIAbilityContext);
    crashAnalytics.initialize();
    logger.startup(TAG, 'NGF 引导启动完成', '成功=' + bootstrapResult);
    // **必须在 bootstrap 之后重读设置。**
    //
    // `fieldwatchApplication` 是本文件 import 进来的单例，它的构造函数在**模块导入时**
    // 就执行了 —— 早于这一行 bootstrap，因此那次 `settingsRepository.load()`
    // 读到的是**尚未初始化的内存缓存**，全部落回默认值。
    // 不在这里重读，用户就会看到「所有设置每次启动都被重置」。
    fieldwatchApplication.reloadSettings();
    // 清理上一次运行残留的通知（进程被杀时不会有正常收尾）。
    // 不 await：这里不阻塞启动；`syncBackgroundTask` 会在第一次发布前再 await 一次。
    void fieldwatchApplication.clearStaleNotifications();

    // 解析流转数据
    if (want.parameters) {
      ngfContinuationManagerFacade.receiveContinuationData(want.parameters as Record<string, Object>);
    }
    // 快捷方式 / 卡片带进来的目标标签页（`targetTab`）。
    this.applyTargetTab(want);
    // 深度链接（`airwavefootprints://…`）。
    // 冷启动时页面还没创建，桥会先存下，由页面就绪后取走。
    this.applyDeepLink(want);

    /**
     * API 23 适配说明：
     * getApplicationContext().setColorMode() 在 API 21 已废弃
     * 颜色模式现在通过 ThemeManagerFacade 统一管理
     * 系统颜色模式变化通过 onConfigurationUpdate 监听
     */
    logger.info(TAG, '颜色模式由 ThemeManagerFacade 统一管理，无需手动设置');

    ngfThemeManagerFacade.initializeDefaults();
    // Fieldwatch 是夜战风格：未显式选择主题时强制深色，默认不跟随系统深浅色。
    if (ngfThemeManagerFacade.getCurrentTheme() === NGFThemeMode.AUTO) {
      ngfThemeManagerFacade.setThemeOverride(NGFThemeMode.DARK);
      // setThemeOverride 只写 AppStorage；$r("app.color.*") 的深/浅解析取决于应用颜色模式，
      // 不调用 setColorMode 会让所有资源引用仍落在 base(浅色) 目录。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      logger.info(TAG, '默认主题已设为深色（不跟随系统）');
    }
    ngfI18nManagerFacade.initializeDefaults();
    void ngfHoldingAwarenessFacade.initialize();
    void ngfVisualEffectsFacade.initialize();

    logger.lifecycle(TAG, '生命周期: onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.lifecycle(TAG, '生命周期: onNewWant');
    if (want.parameters) {
      ngfContinuationManagerFacade.receiveContinuationData(want.parameters as Record<string, Object>);
    }
    // **热启动也要处理**：应用已在前台时点快捷方式走的是这里，不是 onCreate。
    this.applyTargetTab(want);
    this.applyDeepLink(want);
  }

  /**
   * 处理深度链接。
   *
   * 这里**只做识别与转交**，不做任何导航：
   * 冷启动时页面还不存在，热启动时页面又不在本文件的掌控里；
   * 导航交给页面（它才知道自己现在在哪、该往哪压栈）。
   * 与 `applyTargetTab` 是同一个思路。
   */
  private applyDeepLink(want: Want): void {
    const uri: string = want.uri === undefined ? '' : want.uri;
    if (uri.length === 0) return;
    fieldwatchDeepLinkBridge.accept(uri);
  }

  /**
   * 记下 `want.parameters.targetTab`，由页面在 1 秒刷新里消费。
   *
   * 这里**不直接切页**：冷启动时页面还没创建，热启动时页面又不在本文件的掌控里。
   * 统一交给应用层做「先记下、页面消费」的中间态，两条路径共用一套逻辑。
   */
  private applyTargetTab(want: Want): void {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined) return;
    const target: Object | undefined = parameters['targetTab'];
    if (target === undefined) return;
    fieldwatchApplication.requestTab(String(target));
    logger.info(TAG, '快捷方式目标标签页: ' + String(target));
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.lifecycle(TAG, '生命周期: onContinue，开始跨端流转');
    try {
      ngfContinuationManagerFacade.collectAllContinuationData(wantParam);
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (e) {
      logger.error(TAG, '流转失败: ' + e);
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  onDestroy(): void {
    void fieldwatchApplication.onAbilityDestroy();
    ngfHoldingAwarenessFacade.destroy();
    uiContextManager.clearAbilityContext();
    clearContext();
    crashAnalytics.terminate();
    logger.lifecycle(TAG, '生命周期: onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.lifecycle(TAG, '生命周期: onWindowStageCreate');
    ngfPlatformWindowManagerFacade.bindWindowStage(windowStage);
    // 兜一次：`SettingsManager.initialize` 是 `void` 异步调用的，
    // `onCreate` 返回时它可能还没走完。这里再读一次，确保页面首帧拿到的就是磁盘上的值。
    fieldwatchApplication.reloadSettings();
    ngfScreenKeepAwakeFacade.onWindowStageCreate();
    ngfDeviceAdaptationFacade.bindWindowStage(windowStage);

    windowStage.loadContent('pages/fieldwatch/FieldwatchPage', (err: BusinessError): void => {
      if (err.code !== 0) {
        logger.error(TAG, '加载页面内容失败: ' + JSON.stringify(err));
        return;
      }
      logger.info(TAG, '页面内容加载成功');
    });
  }

  onWindowStageDestroy(): void {
    ngfScreenKeepAwakeFacade.onWindowStageDestroy();
    ngfDeviceAdaptationFacade.clearWindowStage();
    ngfPlatformWindowManagerFacade.clearWindowStage();
    logger.lifecycle(TAG, '生命周期: onWindowStageDestroy');
  }

  onForeground(): void {
    logger.lifecycle(TAG, '生命周期: onForeground');
    ngfScreenKeepAwakeFacade.onForeground();
    ngfDeviceAdaptationFacade.refresh('ability_foreground');
    void ngfHoldingAwarenessFacade.resume();
    void fieldwatchApplication.onAbilityForeground();
  }

  onBackground(): void {
    logger.lifecycle(TAG, '生命周期: onBackground');
    ngfScreenKeepAwakeFacade.onBackground();
    void fieldwatchApplication.onAbilityBackground();
  }

  onConfigurationUpdate(config: Configuration): void {
    logger.info(TAG, '配置更新: colorMode=' + config.colorMode + ', language=' + config.language);
    ngfDeviceAdaptationFacade.refresh('configuration_update');

    const colorMode = config.colorMode;
    if (colorMode !== undefined) {
      ngfThemeManagerFacade.handleSystemColorModeChanged(colorMode);
    }

    const language = config.language;
    if (language !== undefined) {
      ngfI18nManagerFacade.handleSystemLocaleChanged(language);
    }
  }
}
