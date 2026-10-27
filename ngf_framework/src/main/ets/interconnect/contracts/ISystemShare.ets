export interface ISystemShare {
  /**
   * 调起原生系统级分享面板 (ShareKit)
   * 鸿蒙 4.0 (API 11) 起，推荐使用 systemShare 组件
   * @param text 分享的文本内容
   */
  shareText(text: string): void;

  /**
   * 分享一张**本机文件**（通常是应用沙箱里落盘的图片）。
   *
   * 为什么是「文件」而不是位图：ShareKit 的 `SharedRecord` 只接受
   * `content`（文本）或 `uri`（文件 URI）二选一，没有直接传 PixelMap 的入口。
   * 所以调用方要先把内容落成文件，再把路径交过来。
   *
   * @param fileUri     文件的可分享 URI（`file://` 或应用文件 URI），**不是沙箱裸路径**
   * @param utd         统一数据类型，例如 `general.png` / `general.jpeg`
   * @param title       分享面板里显示的标题；空串则用文件名
   * @param label       面板里的类型标签，图片建议 'IMAGE'
   */
  shareFile(fileUri: string, utd: string, title: string, label: string): void;
}
