import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { OwnDeviceProfile } from '../../fieldwatch/domain/FieldwatchOwnDevice';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/** 顶栏沉浸底板高度，与关注列表 / 特征详情同值。 */
const DAILY_UNDERLAY_HEIGHT: number = 168;

/**
 * 日常模式首屏。
 *
 * **只放三张大卡 + 一条「我的设备」摘要。** 其余能力不是被删掉，而是收进了
 * 各卡片自己的二级页面与设置里的模式开关 —— 落地文档第六节明确禁止
 * 「为日常模式阉割专业模式」，所以这里不做任何功能裁剪，只做首屏减负。
 *
 * 术语红线（文档 P0-1 验收）：本页与它直达的页面里不得出现
 * RSSI / dBm / MAC / 广播 / 签名。文案一律走资源文件，改文案时不要绕过这条。
 *
 * 两种宿主（与 FieldwatchWatchlistPage 同一套写法）：
 *   - 作为根页面首屏：withShell = false，由根页面的 HdsNavigation 提供壳；
 *   - 作为路由 fieldwatch.daily 的目标页：withShell = true，自己带顶栏，
 *     这样横屏右栏与深链直达都能落到同一个组件，不会出现两套日常首屏。
 *
 * 安防扫描（P1）与 Wi-Fi 体检（P1）在 P0 只是**入口占位**：
 * 卡片照常显示（首屏结构现在就定下来，避免 P1 再改布局），
 * 点进去明确告知「下个版本见」，不摆假数据、不假装已经能用。
 */
@Component
export struct FieldwatchDailyPage {
  /** 是否自带 HDS 顶栏（作路由目标页时为 true）。 */
  withShell: boolean = false;
  /** 顶部系统安全区高度（vp），由根页面测量后传入。 */
  topInset: number = 0;
  /** 打开「找东西」。 */
  onOpenFind: () => void = (): void => {};
  /** 切到专业模式。 */
  onSwitchPro: () => void = (): void => {};
  /** 关闭当前路由（作目标页时用）。 */
  onClose: () => void = (): void => {};
  /** 手动重渲染计数器：应用状态不经过 @State，需要它驱动刷新。 */
  @State private tick: number = 0;
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.refreshTimer = setInterval((): void => { this.tick += 1; }, 2000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(DAILY_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  /** 附近设备数：日常文案只说「台」，不区分无线电种类，也不给强度数字。 */
  private nearbyCount(): number {
    const bump: number = this.tick;
    return bump >= 0 ? fieldwatchApplication.getState().sightings.length : 0;
  }

  private ownSummary(): string {
    const bump: number = this.tick;
    // 显式类型：ArkTS 不接受三元表达式在两侧类型不同时的隐式推断。
    const list: OwnDeviceProfile[] = fieldwatchApplication.ownDevices();
    if (bump < 0 || list.length === 0) return this.text('app.string.fieldwatch_daily_own_empty');
    const names: string[] = [];
    for (let index: number = 0; index < list.length && names.length < 2; index += 1) {
      const label: string = list[index].label();
      if (label.length > 0) names.push(label);
    }
    if (names.length === 0) return this.text('app.string.fieldwatch_daily_own_count').replace('%1', list.length.toString());
    return names.join(' · ');
  }

  build() {
    if (this.withShell) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.TopStart }) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              DAILY_UNDERLAY_HEIGHT)
          })
          this.buildBody()
        }.width('100%').height('100%')
      }
      .titleBar(NGFHdsTitleBarOptionsFactory.build(
        $r('app.string.fieldwatch_daily_greeting'),
        $r('app.string.fieldwatch_daily_subtitle'),
        FieldwatchPaletteHolder.get().night,
        hdsMaterial.MaterialLevel.GENTLE,
        true,
        false
      ))
      .onBackPressed((): boolean => { this.onClose(); return true; })
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    } else {
      this.buildBody()
    }
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildHeader()
        this.buildBigCard('sys.symbol.dot_radiowaves_left_and_right',
          $r('app.string.fieldwatch_daily_card_find_title'),
          $r('app.string.fieldwatch_daily_card_find_desc'), true,
          (): void => { this.onOpenFind(); })
        this.buildBigCard('sys.symbol.checkmark_shield',
          $r('app.string.fieldwatch_daily_card_security_title'),
          $r('app.string.fieldwatch_daily_card_security_desc'), false,
          (): void => { this.showSoon('app.string.fieldwatch_daily_card_security_title'); })
        this.buildBigCard('sys.symbol.wifi',
          $r('app.string.fieldwatch_daily_card_wifi_title'),
          $r('app.string.fieldwatch_daily_card_wifi_desc'), false,
          (): void => { this.showSoon('app.string.fieldwatch_daily_card_wifi_title'); })
        this.buildOwnBar()
        this.buildFooter()
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  /** P0/P1 未上线的卡片：一句「下个版本见」，不摆假数据。 */
  private showSoon(titleKey: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: this.text(titleKey) + ' · ' + this.text('app.string.fieldwatch_daily_coming_soon'),
      duration: 2000
    });
  }

  @Builder
  private buildHeader() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.dot_radiowaves')).fontSize(20)
        .fontColor([FieldwatchPaletteHolder.get().accent])
      Text(this.text('app.string.fieldwatch_daily_nearby').replace('%1', this.nearbyCount().toString()))
        .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 2 })
  }

  /**
   * 一张大卡。
   *
   * 三张卡结构完全一致：图标 + 标题 + 一句人话 + 右侧箭头。
   * 「已上线」与「即将上线」只用一行小字区分，不把整卡灰掉 ——
   * 灰卡在深色主题下几乎看不见，用户会以为界面坏了。
   */
  @Builder
  private buildBigCard(symbol: string, title: ResourceStr, desc: ResourceStr, ready: boolean, onTap: () => void) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r(symbol)).fontSize(24)
            .fontColor([ready ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
        }
        .width(52).height(52).borderRadius(16)
        .backgroundColor(FieldwatchPaletteHolder.get().badgeBg)

        Column({ space: 4 }) {
          Text(title).fontSize(19).fontWeight(FontWeight.Medium)
            .fontColor(FieldwatchPaletteHolder.get().headerText)
          Text(desc).fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
      }.width('100%')

      if (!ready) {
        Text(this.text('app.string.fieldwatch_daily_coming_soon'))
          .fontSize(11).fontColor(FieldwatchPaletteHolder.get().warn)
      }
    }
    .width('100%').padding(16)
    .borderRadius(18)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
    .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline)
    .onClick((): void => { onTap(); })
  }

  /**
   * 「我的设备」摘要条。
   *
   * 刻意不做成第四张大卡：它是**状态**不是**动作**。
   * 没有认领过设备时给出「认领后一眼就能找到」，把下一步说清楚；
   * 已认领时直接列名字，点进去就是找东西（P2 的看板再接在这里）。
   */
  @Builder
  private buildOwnBar() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.list_checkmark')).fontSize(18)
        .fontColor([FieldwatchPaletteHolder.get().accent])
      Column({ space: 2 }) {
        Text($r('app.string.fieldwatch_daily_own_title')).fontSize(15)
          .fontColor(FieldwatchPaletteHolder.get().text)
        Text(this.ownSummary()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text($r('app.string.fieldwatch_daily_own_more')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().accent)
    }
    .width('100%').padding(14)
    .borderRadius(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel2)
    .onClick((): void => { this.onOpenFind(); })
  }

  /**
   * 页脚：模式开关。
   *
   * **必须放在首屏可见处**：日常模式把专业入口收进了二级页面，
   * 如果切换入口藏在设置深处，老用户会以为功能被删了。
   */
  @Builder
  private buildFooter() {
    Column({ space: 8 }) {
      FieldwatchButton({
        label: $r('app.string.fieldwatch_daily_switch_pro'),
        tone: FieldwatchButtonTone.OUTLINE,
        onTap: (): void => { this.onSwitchPro(); }
      })
      Text($r('app.string.fieldwatch_daily_switch_hint'))
        .fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
    }
    .width('100%').alignItems(HorizontalAlign.Center)
    .padding({ top: 6 })
  }
}
