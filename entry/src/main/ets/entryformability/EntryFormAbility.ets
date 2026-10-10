import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { logger } from 'ngf_framework';
import {
  buildWidgetCardData, encodeWidgetForms, FieldwatchWidgetForm, FieldwatchWidgetState,
  parseWidgetForms, parseWidgetState, WIDGET_FORMS_KEY
} from '../fieldwatch/domain/FieldwatchWidgetState';

const TAG: string = 'EntryFormAbility';
/** 与框架 `SettingsManager` 同一个 preferences 文件（应用侧写、这里读写）。 */
const PREFERENCES_NAME: string = 'ngf_settings';
const WIDGET_STATE_KEY: string = 'fieldwatch.widgetState';
/** 卡片自动刷新的最小间隔（分钟）。系统下限就是 5。 */
const NEXT_REFRESH_MINUTES: number = 5;

/**
 * 电波足迹卡片。
 *
 * **方向是「应用写状态、卡片侧拉」，但刷新是双向的**：
 *   - 状态：应用写 `fieldwatch.widgetState`，本扩展读；
 *   - 卡片清单：本扩展把 formId 登记进 `fieldwatch.widgetForms`，**应用读它并主动 updateForm** ——
 *     主应用拿不到自己的 formId（`formProvider` 没有枚举接口），只能由扩展反向登记。
 * 没有这条登记，卡片就只能等系统 30 分钟的周期刷新，表现就是「卡片是死的」。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  /** formId -> 尺寸。`onUpdateForm` / `onFormEvent` 拿不到尺寸，必须自己记。 */
  private readonly dimensions: Map<string, string> = new Map<string, string>();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const dimension: string = this.dimensionOf(want);
    // **formId 只在 want 里给一次**（IDENTITY_KEY），错过就再也拿不到尺寸；
    // 顺手登记给主应用，让它能主动推送 —— 否则卡片只能等系统 30 分钟周期刷新。
    const formId: string = this.formIdOf(want);
    logger.lifecycle(TAG, 'onAddForm formId=' + formId + ' dimension=' + dimension);
    if (formId.length > 0) {
      this.dimensions.set(formId, dimension);
      this.register(formId);
      this.scheduleNext(formId);
    }
    return formBindingData.createFormBindingData(this.buildData(dimension));
  }

  /** 从 want 里取系统分配的 formId。 */
  private formIdOf(want: Want): string {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined) return '';
    const raw: Object | undefined = parameters[formInfo.FormParam.IDENTITY_KEY];
    return raw === undefined ? '' : String(raw);
  }

  onCastToNormalForm(formId: string): void {
    this.register(formId);
  }

  onUpdateForm(formId: string): void {
    this.push(formId);
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片上的刷新按钮：立刻重算一次。
    if (message === 'refresh') this.push(formId);
  }

  onRemoveForm(formId: string): void {
    this.dimensions.delete(formId);
    this.register(formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private push(formId: string): void {
    const dimension: string = this.dimensionOfForm(formId);
    const data: Record<string, string> = this.buildData(dimension);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).then((): void => {
      // 顺手把下一次刷新排到 5 分钟后：系统默认的 30 分钟周期对「正在不在跑」太慢。
      this.scheduleNext(formId);
    }).catch((error: Error): void => {
      logger.error(TAG, 'updateForm 失败: ' + error.message);
    });
  }

  private scheduleNext(formId: string): void {
    formProvider.setFormNextRefreshTime(formId, NEXT_REFRESH_MINUTES).catch((error: Error): void => {
      logger.warn(TAG, 'setFormNextRefreshTime 失败: ' + error.message);
    });
  }

  private dimensionOf(want: Want): string {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined) return '2*2';
    const raw: Object | undefined = parameters[formInfo.FormParam.DIMENSION_KEY];
    if (raw === undefined) return '2*2';
    // FormDimension: 1 = 2*2，2 = 2*4。
    return Number(raw) === 2 ? '2*4' : '2*2';
  }

  /** 尺寸只在 `onAddForm` 给过；之后按 formId 查表，查不到就按小卡片渲染。 */
  private dimensionOfForm(formId: string): string {
    const known: string | undefined = this.dimensions.get(formId);
    return known === undefined ? '2*2' : known;
  }

  private buildData(dimension: string): Record<string, string> {
    const state: FieldwatchWidgetState = parseWidgetState(this.readState());
    return buildWidgetCardData(state, dimension, Date.now());
  }

  private readState(): string {
    try {
      const store: dataPreferences.Preferences = dataPreferences.getPreferencesSync(this.context, { name: PREFERENCES_NAME });
      return store.getSync(WIDGET_STATE_KEY, '') as string;
    } catch (error) {
      logger.warn(TAG, '读取卡片状态失败: ' + error);
      return '';
    }
  }

  /** 把 formId 与尺寸登记进共享存储，供主应用主动推送。 */
  private register(formId: string): void {
    try {
      const store: dataPreferences.Preferences = dataPreferences.getPreferencesSync(this.context, { name: PREFERENCES_NAME });
      const existing: FieldwatchWidgetForm[] = parseWidgetForms(store.getSync(WIDGET_FORMS_KEY, '') as string);
      const kept: FieldwatchWidgetForm[] = existing.filter((item: FieldwatchWidgetForm): boolean => item.id !== formId);
      if (this.dimensions.has(formId)) kept.push(new FieldwatchWidgetForm(formId, this.dimensionOfForm(formId)));
      store.putSync(WIDGET_FORMS_KEY, encodeWidgetForms(kept));
      store.flush();
    } catch (error) {
      logger.warn(TAG, '登记卡片失败: ' + error);
    }
  }
}
