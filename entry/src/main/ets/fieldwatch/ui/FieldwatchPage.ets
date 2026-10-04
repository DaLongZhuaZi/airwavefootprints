import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, NGFPageWindowSupport, ngfPermissionManagerFacade } from 'ngf_framework';
import { fieldwatchApplication } from '../application/FieldwatchApplication';
import { radioKindLabel } from '../domain/FieldwatchDomainService';
import { ScanState, Sighting } from '../domain/FieldwatchModels';

const PAGE_UNDERLAY_HEIGHT: number = 164;

@Component
export struct FieldwatchPage {
  @State private refreshToken: number = 0;
  @State private topInsetVp: number = 108;
  @State private permissionMessage: string = '正在申请蓝牙扫描权限…';
  private readonly scroller: Scroller = new Scroller();
  private refreshTimer: number = 0;

  aboutToAppear(): void {
    void this.startBleScan();
    this.refreshTimer = setInterval((): void => { this.refreshToken = Date.now(); }, 1000);
    NGFPageWindowSupport.loadDynamicTopInset(this.getUIContext(), 108, 108, (inset: number): void => { this.topInsetVp = inset; });
  }
  aboutToDisappear(): void {
    fieldwatchApplication.stopBleScan();
    if (this.refreshTimer !== 0) clearInterval(this.refreshTimer);
  }

  private async startBleScan(): Promise<void> {
    const granted: boolean = await ngfPermissionManagerFacade.requestPermissions(['ohos.permission.ACCESS_BLUETOOTH']);
    if (!granted) {
      this.permissionMessage = '蓝牙扫描权限未授予';
      return;
    }
    this.permissionMessage = 'BLE 扫描已启动';
    fieldwatchApplication.startBleScan();
  }

  build() {
    const state = fieldwatchApplication.getState();
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        NGFImmersiveTopChromeUnderlay({ spec: NGFImmersiveTopChromePresetFactory.build('#07101E', '#0C2341', '#0A1626', '#2854F0E8', '#32A4F2D8', PAGE_UNDERLAY_HEIGHT) })
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            this.buildHeader(state.scanState, state.errorMessage, state.sightings.length, state.logs.length)
            ForEach(fieldwatchApplication.filteredSightings(), (item: Sighting): void => { this.buildSightingCard(item); }, (item: Sighting): string => item.key)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topInsetVp, bottom: 32 })
        }
        .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      }
      .width('100%').height('100%')
    }
    .titleBar(NGFHdsTitleBarOptionsFactory.build('电波足迹', '被动无线电观测', $r('app.color.background_primary'), hdsMaterial.MaterialLevel.EXQUISITE, true, false))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .width('100%').height('100%').backgroundColor($r('app.color.background_primary'))
  }

  @Builder
  private buildHeader(scanState: ScanState, errorMessage: string, deviceCount: number, logCount: number) {
    Column({ space: 8 }) {
      Row() {
        Text('Live').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Text(scanState === ScanState.SCANNING ? 'BLE 扫描中' : scanState === ScanState.ERROR ? '扫描异常' : '已停止')
          .fontSize(14)
          .fontColor(scanState === ScanState.SCANNING ? $r('app.color.tag_green') : $r('app.color.text_secondary'))
      }
      Text((errorMessage.length > 0 ? errorMessage : this.permissionMessage) + ' · 只接收 BLE 广播，不主动连接设备').fontSize(14).fontColor($r('app.color.text_secondary'))
      Row({ space: 10 }) {
        this.buildMetric('设备', deviceCount.toString())
        this.buildMetric('日志', logCount.toString())
        Button('重启 BLE 扫描').onClick((): void => { fieldwatchApplication.startBleScan(); this.refreshToken = Date.now(); }).fontSize(13)
      }
    }
    .width('100%').padding(16).backgroundColor($r('app.color.background_secondary')).borderRadius(20)
  }

  @Builder
  private buildMetric(label: string, value: string) {
    Column() { Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')); Text(label).fontSize(12).fontColor($r('app.color.text_secondary')); }.layoutWeight(1)
  }

  @Builder
  private buildSightingCard(sighting: Sighting) {
    Column({ space: 8 }) {
      Row() {
        Text(sighting.name.length > 0 ? sighting.name : '未命名设备').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(radioKindLabel(sighting.kind)).fontSize(12).fontColor($r('app.color.tag_blue'))
      }
      Text(fieldwatchApplication.describe(sighting)).fontSize(13).fontColor($r('app.color.text_secondary'))
      Row() {
        Text('RSSI ' + sighting.rssi.toString() + ' dBm').fontSize(13).fontColor($r('app.color.text_primary'))
        Blank()
        Text('出现 ' + sighting.count.toString() + ' 次').fontSize(13).fontColor($r('app.color.text_secondary'))
      }
      Button('关注/取消关注').onClick((): void => { fieldwatchApplication.toggleWatch(sighting); this.refreshToken = Date.now(); }).fontSize(12).height(36)
    }
    .width('100%').padding(16).backgroundColor($r('app.color.background_secondary')).borderRadius(18)
  }
}
