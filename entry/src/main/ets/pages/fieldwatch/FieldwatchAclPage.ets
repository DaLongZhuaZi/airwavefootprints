/**
 * 主动扫描授权专页（《主动扫描授权与隐私体系设计》v2 第 7.4 节）。
 *
 * 三块内容：
 *   ① ACL 表：A1–A7 每项能力说明 + 开关（关闭后需手动重开）
 *   ② 审计日志：可查、可删（只存本地）
 *   ③ 一键关闭全部主动能力
 *
 * 关闭后安防页的主动入口会因引擎拒绝而不可用，被动扫描完全不受影响。
 */

import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import {
  ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory,
  NGFImmersiveTopChromeUnderlay, resolveResourceString
} from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { AclCapability, AclEntry, AclRisk, ACL_TABLE_VERSION } from '../../fieldwatch/domain/FieldwatchAcl';
import { AclAuditRecord } from '../../fieldwatch/domain/FieldwatchAclEngine';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const ACL_UNDERLAY_HEIGHT: number = 168;

@Component
export struct FieldwatchAclPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  /** 能力表（进页读一次）。 */
  @State private caps: AclEntry[] = [];
  /** 每项能力是否开启（与 caps 同序）。**不能叫 enabled**：与 ArkUI 组件内置属性冲突。 */
  @State private capEnabled: boolean[] = [];
  /** 审计记录（新→旧）。 */
  @State private audit: AclAuditRecord[] = [];
  @State private tick: number = 0;

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.caps = fieldwatchApplication.aclCapabilities();
    const flags: boolean[] = [];
    this.caps.forEach((entry: AclEntry): void => {
      flags.push(!fieldwatchApplication.isActiveCapabilityDisabled(entry.capability));
    });
    this.capEnabled = flags;
    void this.loadAudit();
  }

  private async loadAudit(): Promise<void> {
    this.audit = await fieldwatchApplication.aclAuditRecords(50);
    this.tick += 1;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(ACL_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.withShell) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              ACL_UNDERLAY_HEIGHT)
          })
        }
        this.buildBody()
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_acl_settings_title'),
      $r('app.string.fieldwatch_acl_intro'),
      FieldwatchPaletteHolder.get().night,
      hdsMaterial.MaterialLevel.GENTLE,
      true,
      false
    ))
    .hideTitleBar(!this.withShell)
    .onBackPressed((): boolean => { this.onClose(); return true; })
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildCapabilityTable()
        this.buildDangerZone()
        this.buildAudit()
      }
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  /** ACL 表：每项能力一行，带说明、风险提示与开关。 */
  @Builder
  private buildCapabilityTable() {
    Column({ space: 10 }) {
      Text(this.text('app.string.fieldwatch_acl_caps_title')).fontSize(15)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).width('100%')
      Text(this.text('app.string.fieldwatch_acl_caps_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      ForEach(this.caps, (entry: AclEntry, index: number): void => {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(this.text(entry.titleKey)).fontSize(13)
              .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isEnabled(entry.capability) })
              .onChange((value: boolean): void => {
                fieldwatchApplication.setActiveCapability(entry.capability, value);
                this.reload();
              })
          }.width('100%')
          // 高风险能力的额外提示（设计文档 2.2 要求）。
          if (entry.risk === AclRisk.HIGH && entry.riskNoteKey.length > 0) {
            Text(this.text(entry.riskNoteKey)).fontSize(10)
              .fontColor(FieldwatchPaletteHolder.get().warn).width('100%')
          }
        }.width('100%').padding({ top: 6, bottom: 6 })
      }, (entry: AclEntry, index: number): string => String(entry.capability))
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /**
   * 读开关状态**必须走 @State 数组**，不能直接查应用层。
   *
   * 真机踩到过：直接 `return !fieldwatchApplication.isActiveCapabilityDisabled(...)` 时，
   * 点「一键关闭」后引擎里状态确实变了，但 ArkUI 没有任何响应式依赖可追踪 ——
   * 开关在界面上纹丝不动，用户会以为按钮坏了。
   */
  private isEnabled(capability: AclCapability): boolean {
    const index: number = this.capIndex(capability);
    if (index < 0 || index >= this.capEnabled.length) return true;
    return this.capEnabled[index];
  }

  private capIndex(capability: AclCapability): number {
    for (let i: number = 0; i < this.caps.length; i += 1) {
      if (this.caps[i].capability === capability) return i;
    }
    return -1;
  }

  /** 一键关闭 / 恢复全部。 */
  @Builder
  private buildDangerZone() {
    Column({ space: 8 }) {
      FieldwatchButton({ label: $r('app.string.fieldwatch_acl_disable_all'),
        tone: FieldwatchButtonTone.WARN,
        onTap: (): void => { fieldwatchApplication.disableAllActive(); this.reload(); } })
      FieldwatchButton({ label: $r('app.string.fieldwatch_acl_enable_all'),
        tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { fieldwatchApplication.enableAllActive(); this.reload(); } })
      Text(this.text('app.string.fieldwatch_acl_version_line')
        .replace('%1', ACL_TABLE_VERSION.toString()))
        .fontSize(10).fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 审计日志：可查、可删。 */
  @Builder
  private buildAudit() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.text('app.string.fieldwatch_acl_audit_title')).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().headerText).layoutWeight(1)
        Text(this.audit.length.toString()).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().accent)
      }.width('100%')
      if (this.audit.length === 0) {
        Text(this.text('app.string.fieldwatch_acl_audit_empty')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
      } else {
        ForEach(this.audit, (record: AclAuditRecord): void => {
          Row({ space: 6 }) {
            Text(this.auditTime(record)).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().textDim).width(96)
            Text(record.capability + ' · ' + record.scope).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().text).layoutWeight(1).maxLines(1)
            Text(record.success ? '✓' : '✗').fontSize(11)
              .fontColor(record.success ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().warn)
          }.width('100%').padding({ top: 3, bottom: 3 })
        }, (record: AclAuditRecord): string => record.id)
        FieldwatchButton({ label: $r('app.string.fieldwatch_acl_audit_clear'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true,
          onTap: (): void => { void this.clearAudit(); } })
      }
    }.width('100%').padding(14).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  private auditTime(record: AclAuditRecord): string {
    const date: Date = new Date(record.at);
    const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
    const day: string = date.getDate().toString().padStart(2, '0');
    const hour: string = date.getHours().toString().padStart(2, '0');
    const minute: string = date.getMinutes().toString().padStart(2, '0');
    return month + '-' + day + ' ' + hour + ':' + minute;
  }

  private async clearAudit(): Promise<void> {
    await fieldwatchApplication.clearAclAudit();
    await this.loadAudit();
  }
}
