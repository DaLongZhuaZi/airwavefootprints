let storage = new LocalStorage();

/**
 * 电波足迹卡片。
 *
 * 沿用 NGF 框架卡片的基础样式（顶部图标 + 标题 + 刷新、中部状态、底部动作），
 * 只把内容换成业务状态。
 *
 * **卡片本身不做任何业务判断** —— 该显示什么全部由 `EntryFormAbility` 算好后传进来
 * （`statusText` / `detailText`），这样「什么时候算在运行」只有一处口径。
 *
 * 两个尺寸：
 *   - 2*2 小卡片：扫描计数，或「app 未运行」；
 *   - 2*4 大卡片：最近一次命中的关注目标与特征族。
 *
 * 点击卡片 -> 打开应用并直达**关注列表**（`targetTab=watchlist`，由 EntryAbility 转交页面消费）。
 * 之所以不是设置页：卡片大卡显示的就是关注目标的最近情况，点进去看完整列表才顺。
 */
@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('running') running: string = 'false';
  @LocalStorageProp('statusText') statusText: string = 'app 未运行';
  @LocalStorageProp('detailText') detailText: string = '';
  @LocalStorageProp('updatedText') updatedText: string = '--:--';

  private isLarge(): boolean { return this.dimension === '2*4'; }
  private isRunning(): boolean { return this.running === 'true'; }

  build() {
    Column() {
      this.buildHeader()
      this.buildBody()
      this.buildFooter()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0F14')
    .borderRadius(16)
    // 整张卡片可点：打开应用并进设置页。
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetTab: 'watchlist' }
      });
    })
  }

  @Builder
  buildHeader() {
    Row() {
      Image($r('app.media.startIcon')).width(18).height(18).margin({ right: 6 })
      Text($r('app.string.widget_title'))
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#E8EDF2')
      Blank()
      Text('↻').fontSize(16).fontColor('#9AA6B2')
        .onClick(() => {
          postCardAction(this, { action: 'message', params: { message: 'refresh' } });
        })
    }.width('100%').height(28).padding({ left: 12, right: 12, top: 8 })
  }

  @Builder
  buildBody() {
    Column({ space: 4 }) {
      // 运行状态用一个圆点先给结论，再给数字 —— 一眼能看出「在不在跑」。
      Row({ space: 6 }) {
        Circle().width(8).height(8)
          .fill(this.isRunning() ? '#3DFF9A' : '#FF3D5A')
        Text(this.isRunning() ? $r('app.string.widget_running') : $r('app.string.widget_not_running'))
          .fontSize(12).fontColor(this.isRunning() ? '#3DFF9A' : '#FF3D5A')
      }.width('100%').justifyContent(FlexAlign.Start)
      Text(this.statusText)
        .fontSize(this.isLarge() ? 15 : 17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E8EDF2')
        .maxLines(2)
        .width('100%')
        .textAlign(TextAlign.Start)
      // 大卡片才展示关注目标 / 特征族；小卡片放不下，硬塞只会挤成一团。
      if (this.isLarge() && this.detailText.length > 0) {
        Text(this.detailText)
          .fontSize(12).fontColor('#9AA6B2')
          .maxLines(3).width('100%').textAlign(TextAlign.Start)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 12, right: 12, top: 6 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildFooter() {
    Row() {
      Text($r('app.string.widget_tap_to_settings')).fontSize(10).fontColor('#5C6874')
      Blank()
      Text(this.updatedText).fontSize(10).fontColor('#5C6874')
    }.width('100%').padding({ left: 12, right: 12, bottom: 10 })
  }
}
