import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { ngfImmersiveContentTop, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import {
  batteryText, carLastSeenParts, CarLastSeenParts, clockOf, DeviceBoardCard, hasUsableLocation, mapUri
} from '../../fieldwatch/domain/FieldwatchDeviceBoard';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

const BOARD_UNDERLAY_HEIGHT: number = 168;

/**
 * 我的设备看板（P2-12）与找车（P2-13）。
 *
 * 每台自有设备一张卡：在附近 / 上次见到 / 自定义名 / 电量（解不到不显示）。
 * 标了「我的车」的卡片多一行「最后听到它：今天 18:02，B2 层附近」，
 * 坐标点跳系统地图 —— **不自建地图**（文档明确要求）。
 */
@Component
export struct FieldwatchDeviceBoardPage {
  withShell: boolean = true;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  @State private cards: DeviceBoardCard[] = [];
  @State private tick: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    void fieldwatchApplication.ensureOwnDevicesLoaded().then((): void => { this.reload(); });
    this.reload();
    this.timer = setInterval((): void => { this.reload(); }, 3000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
  }

  private reload(): void {
    this.cards = fieldwatchApplication.deviceBoardCards();
    this.tick += 1;
  }

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  private contentTop(): number {
    return this.withShell ? ngfImmersiveContentTop(BOARD_UNDERLAY_HEIGHT, this.topInset) : this.topInset + 16;
  }

  /** 跳系统地图。**不自建地图**，只交坐标给系统。 */
  private openMap(card: DeviceBoardCard): void {
    if (!hasUsableLocation(card.lastLatitude, card.lastLongitude)) return;
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) return;
    const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: mapUri(card.lastLatitude, card.lastLongitude, card.label)
    }).catch((): void => {
      this.getUIContext().getPromptAction().showToast({
        message: this.text('app.string.fieldwatch_board_map_failed'),
        duration: 2200
      });
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.withShell) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              BOARD_UNDERLAY_HEIGHT)
          })
        }
        this.buildBody()
      }.width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build(
      $r('app.string.fieldwatch_board_title'),
      $r('app.string.fieldwatch_board_subtitle'),
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
      Column({ space: 12 }) {
        if (this.cards.length === 0) this.buildEmpty()
        else {
          ForEach(this.cards, (card: DeviceBoardCard): void => {
            this.buildCard(card)
          }, (card: DeviceBoardCard): string => card.profileId + this.tick.toString())
        }
      }
      .width('100%').constraintSize({ maxWidth: 560 })
      .padding({ left: 16, right: 16, top: this.contentTop(), bottom: 28 })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildEmpty() {
    Column({ space: 8 }) {
      Text($r('app.string.fieldwatch_board_empty')).fontSize(15)
        .fontColor(FieldwatchPaletteHolder.get().text).textAlign(TextAlign.Center)
      Text($r('app.string.fieldwatch_board_empty_hint')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim).textAlign(TextAlign.Center)
    }.width('100%').padding({ top: 60, bottom: 40 }).alignItems(HorizontalAlign.Center)
  }

  /** 一台设备一张卡。 */
  @Builder
  private buildCard(card: DeviceBoardCard) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r(card.isCar ? 'sys.symbol.car_side_rear_radiowaves' : 'sys.symbol.dot_radiowaves_left_and_right'))
          .fontSize(22)
          .fontColor([card.nearby ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().textDim])
        Column({ space: 2 }) {
          Text(card.label.length > 0 ? card.label : this.text('app.string.fieldwatch_find_unnamed'))
            .fontSize(16).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(card.nearby ? $r('app.string.fieldwatch_board_nearby') : this.lastSeenLine(card))
            .fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        // 电量**只在解出来时显示**；解不出来这一块整个不渲染。
        if (card.hasBattery()) {
          Text(batteryText(card.batteryPercent)).fontSize(14)
            .fontColor(card.batteryPercent <= 20 ? FieldwatchPaletteHolder.get().signalRed : FieldwatchPaletteHolder.get().accent)
        }
      }.width('100%')

      // 找车（P2-13）：标了车的卡片多一行「最后听到它」。
      if (card.isCar && card.lastSeenAt > 0) this.buildCarLine(card)

      Row({ space: 8 }) {
        FieldwatchButton({
          label: card.isCar ? $r('app.string.fieldwatch_board_unmark_car') : $r('app.string.fieldwatch_board_mark_car'),
          tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
          onTap: (): void => {
            fieldwatchApplication.setOwnDeviceCar(card.profileId, !card.isCar);
            this.reload();
          }
        })
        if (card.hasLocation()) {
          FieldwatchButton({
            label: $r('app.string.fieldwatch_board_open_map'),
            tone: FieldwatchButtonTone.OUTLINE, compact: true, fillWidth: false,
            onTap: (): void => { this.openMap(card); }
          })
        }
      }.width('100%')
    }
    .width('100%').padding(14).borderRadius(16).alignItems(HorizontalAlign.Start)
    .backgroundColor(FieldwatchPaletteHolder.get().panel)
  }

  /** 找车那一行：最后听到它 + 位置 + 原理说明。 */
  @Builder
  private buildCarLine(card: DeviceBoardCard) {
    Column({ space: 4 }) {
      Text(this.carLineText(card)).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().text).width('100%')
      // 原理说明**必须写清**：熄火前最后位置 ≈ 停车位置，不承诺室内精度。
      Text($r('app.string.fieldwatch_board_car_hint')).fontSize(11)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private carLineText(card: DeviceBoardCard): string {
    const parts: CarLastSeenParts = carLastSeenParts(card.lastSeenAt, card.lastLatitude, card.lastLongitude, '');
    const template: string = this.text('app.string.fieldwatch_board_car_line');
    let when: string = parts.when;
    if (when.length === 0) when = clockOf(card.lastSeenAt);
    return template.replace('%1', when).replace('%2', parts.where.length > 0 ? parts.where : '');
  }

  private lastSeenLine(card: DeviceBoardCard): string {
    if (card.lastSeenAt <= 0) return this.text('app.string.fieldwatch_board_never_seen');
    const template: string = this.text('app.string.fieldwatch_board_last_seen');
    return template.replace('%1', clockOf(card.lastSeenAt));
  }
}
