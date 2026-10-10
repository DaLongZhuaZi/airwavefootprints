import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from 'ngf_framework';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ngfImmersiveContentTop, ngfSettingsStoreFacade, NGFHdsTitleBarOptionsFactory, NGFImmersiveTopChromePresetFactory, NGFImmersiveTopChromeUnderlay, resolveResourceString } from 'ngf_framework';
import {
  FeedbackContext, FeedbackCreateIssue, FeedbackDiagnostic, FeedbackIssueDetail, FeedbackIssuePage,
  FeedbackAttachment, FeedbackIssuePost, FeedbackIssueSummary, FeedbackIssueType, FeedbackOutcome, FeedbackResponse,
  FeedbackFileHash, FeedbackSupportResult, FeedbackUploadCategory, FeedbackUploadProgress,
  FeedbackUploadSession, fieldwatchFeedbackService, MAX_FILE_BYTES, MAX_ISSUE_BYTES,
  TURNSTILE_SHELL_URL, UPLOAD_CHUNK_SIZE
} from '../../fieldwatch/platform/FieldwatchFeedbackService';
import { fieldwatchDeepLinkBridge } from '../../fieldwatch/platform/FieldwatchDeepLink';
import { fieldwatchApplication } from '../../fieldwatch/application/FieldwatchApplication';
import { LogEntry } from '../../fieldwatch/domain/FieldwatchModels';
import { FieldwatchPaletteHolder } from '../../fieldwatch/ui/FieldwatchPalette';
import { FieldwatchButton, FieldwatchButtonTone } from '../../fieldwatch/ui/FieldwatchButton';

/** 待上传附件在本地的状态。 */
enum LocalAttachmentStatus {
  PENDING = 'pending',
  UPLOADING = 'uploading',
  DONE = 'done',
  FAILED = 'failed'
}

class LocalAttachment {
  public localId: string = '';
  public name: string = '';
  public localPath: string = '';
  public size: number = 0;
  public mediaType: string = 'application/octet-stream';
  public category: FeedbackUploadCategory = 'archive';
  public progress: number = 0;
  public status: LocalAttachmentStatus = LocalAttachmentStatus.PENDING;
  public errorMessage: string = '';
  /** 由「附加日志」生成（重新生成时要先删掉旧的）。 */
  public isGeneratedLog: boolean = false;
}

const TAG: string = 'FieldwatchFeedback';
/** 草稿键：从新建退出后还能接着写（漫匣也是这么做的）。 */
const DRAFT_TITLE_KEY: string = 'fieldwatch.feedback.draft.title';
const DRAFT_BODY_KEY: string = 'fieldwatch.feedback.draft.body';
const DRAFT_TYPE_KEY: string = 'fieldwatch.feedback.draft.type';
const DEVICE_ID_KEY: string = 'fieldwatch.feedbackDeviceId';
const PAGE_SIZE: number = 20;
/** 只许这四种类型（服务端 422 之外的值）。 */
const ISSUE_TYPES: string[] = ['software', 'ui', 'suggestion', 'other'];
/** Turnstile 令牌约 240 秒过期，等待窗口略短一点。 */
const TOKEN_TIMEOUT_MS: number = 230000;

/**
 * 反馈中心。
 *
 * **只用 AF 自己的空间**（`/api/v1/apps/af/...`）——
 * 用户看不出与漫匣共用后端，这一层隔离完全由路径前缀保证。
 * 编号也一律是 AF 路由下的 `issue_number`。
 *
 * 三条实现约束：
 *  ① 每一次请求都由用户显式触发（应用是严格离线的）；
 *  ② 失败提示**按状态码区分**：429 说稍后再试、404 说编号不存在或会话过期、
 *     422 说字段不合法 —— 全说成「失败了」用户无从下手；
 *  ③ 创建/支持/补充/开上传会话都要 Turnstile 令牌，
 *     由内嵌 WebView 打开挑战页、拦截 `airwavefootprints://turnstile?token=…` 取得。
 */
@Component
export struct FieldwatchFeedbackPage {
  withShell: boolean = false;
  topInset: number = 0;
  onClose: () => void = (): void => {};
  openIssueNumber: number = 0;
  /** 深链 `feedback/new`：进入即打开新建表单。 */
  openCreate: boolean = false;
  private readonly contentTop: number = 92;
  private readonly underlayHeight: number = 168;
  // ── 动画（与漫匣同一套参数）──
  /**
   * 页面进入：**x 位移 40 + 透明度**，与其他详情页一致。
   *
   * 曾经照搬漫匣改成 y 位移 16 —— 那在**横屏分栏**下是错的：
   * 右栏应当从右侧滑入（它本来就在右边），从下往上冒很怪。
   * 而且位移必须加在 `HdsNavDestination` **根节点**上：
   * 退出时 pop() 会让模式从 Split 翻到 Stack，右栏要从 33% 拉伸到 100%，
   * 只淡出内容的话根节点的不透明背景还在，
   * 看到的是一整块实心空白面板在拉伸（设备详情页的注释里记着这个坑）。
   */
  @State private enterShift: number = 40;
  @State private enterAlpha: number = 0;
  /** 内容切换：列表 / 详情 / 新建之间切换时重放。 */
  @State private contentOpacity: number = 1;
  @State private contentOffsetY: number = 0;
  /**
   * 内容动画令牌。
   *
   * **必须要有**：连续切换（列表 -> 详情 -> 返回）时，
   * 前一次动画的回调可能在状态已经变了之后才执行，
   * 把内容重新设成半透明 —— 表现为「切过去是灰的」。
   * 令牌让过期回调自己作废。
   */
  private contentAnimToken: number = 0;
  private contentScroller: Scroller = new Scroller();
  private leaving: boolean = false;
  @State private tick: number = 0;
  @State private items: FeedbackIssueSummary[] = [];
  @State private total: number = 0;
  @State private page: number = 1;
  @State private loading: boolean = false;
  /**
   * 「正在提交」独立于 `loading`。
   *
   * `loading` 同时被列表加载用，而进入新建时会顺带刷一次列表 ——
   * 提交按钮绑 `loading` 的话，进页面就是灰的（实测）。
   */
  @State private submitting: boolean = false;
  @State private notice: string = '';
  @State private search: string = '';
  @State private typeFilter: string = '';
  @State private statusFilter: string = '';
  @State private detail: FeedbackIssueDetail | undefined = undefined;
  @State private replyText: string = '';
  @State private creating: boolean = false;
  @State private draftTitle: string = '';
  @State private draftBody: string = '';
  @State private draftType: string = 'software';
  /** 现场上下文草稿（AF 只许 station_name / frequency / location）。 */
  /** 日志范围（分钟）；0 = 全部，-1 = 未选。 */
  @State private logRangeMinutes: number = -1;
  /** Turnstile 挑战页是否打开。 */
  @State private turnstileOpen: boolean = false;
  @State private turnstileHint: string = '';
  /** 待上传附件。 */
  @State private attachments: LocalAttachment[] = [];
  /** 上传中的文案（「正在上传 1/2：文件名」）；空串表示没有在上传。 */
  @State private uploadText: string = '';
  /** 上传是否被用户取消（用普通成员：不参与渲染）。 */
  private uploadCancelled: boolean = false;
  private attachmentSeq: number = 0;
  private webController: webview.WebviewController = new webview.WebviewController();

  private text(key: string): string {
    return resolveResourceString(this.getUIContext().getHostContext(), $r(key));
  }

  aboutToAppear(): void {
    this.ensureDeviceId();
    if (this.withShell) setTimeout((): void => { this.playEnter(); }, 0);
    if (this.openCreate) { this.restoreDraft(); this.goToMode('compose'); void this.loadList(1); }
    else if (this.openIssueNumber > 0) void this.loadDetail(this.openIssueNumber);
    else void this.loadList(1);
  }

  /** 匿名设备 ID：本地随机生成一次并持久化，**不采集任何硬件标识**。 */
  private ensureDeviceId(): void {
    let id: string = ngfSettingsStoreFacade.getString(DEVICE_ID_KEY, '');
    if (id.length === 0) {
      id = util.generateRandomUUID();
      ngfSettingsStoreFacade.setString(DEVICE_ID_KEY, id);
    }
    fieldwatchFeedbackService.setDeviceId(id);
  }

  private playEnter(): void {
    // **不要在这里把 enterShift/enterAlpha 重置回 40/0。**
    //
    // 初值本来就是 40/0（字段初始化器），在同一个同步块里先重置再 animateTo，
    // 起点与终点会被合并进同一帧 —— 动画实际上不播，页面是「瞬间出现」的
    // （实测反馈「出现时的动画不对、消失时是对的」）。
    // 其他详情页（设备详情 / 特征编辑器）都只设终态。
    this.getUIContext().animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.enterShift = 0;
      this.enterAlpha = 1;
    });
  }

  /** 内容进场：切模式后重放一次。 */
  private animateContentIn(trigger: string): void {
    const token: number = this.contentAnimToken + 1;
    this.contentAnimToken = token;
    this.contentOpacity = 0.12;
    this.contentOffsetY = 8;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      if (token === this.contentAnimToken) {
        this.contentOpacity = 1;
        this.contentOffsetY = 0;
      }
    });
    logger.debug(TAG, '反馈中心内容动画: ' + trigger);
  }

  /**
   * 切到某个模式：**列表 / 详情 / 新建**。
   *
   * 三件事必须一起做，否则动画会看起来「卡一下」：
   *  ① 换状态；② 滚动回顶部（带 220ms 动画）；③ 重放内容进场。
   * 只做 ① 的话，从详情滚到底再返回列表会停在半空。
   */
  private goToMode(next: string): void {
    if (next === 'list') {
      this.detail = undefined;
      this.creating = false;
    } else if (next === 'detail') {
      this.creating = false;
    } else {
      this.creating = true;
      this.detail = undefined;
    }
    this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 220 } });
    this.animateContentIn('mode:' + next);
  }

  /**
   * 返回键拦截。**这是反馈中心的二级页面必须做的**：
   * 不拦的话在详情/新建里按返回会直接退出整个反馈中心回到主页，
   * 用户丢掉当前上下文（实测反馈）。
   *
   * 与漫匣同一套语义：
   *  ① 验证页开着 -> 先关它（否则用户被困在挑战页里出不来）；
   *  ② 二级视图（新建 / 详情）-> 回上一级；
   *  ③ 列表 -> 才真正退出页面。
   *
   * 另外：从新建退出时**先存草稿**（漫匣也是这么做的），
   * 下次进来还能接着写。
   */
  private handleBack(): boolean {
    if (this.turnstileOpen) {
      // 用空 token 结算等待者：既关掉挑战页，也让挂起的提交走「验证失败」分支，
      // 而不是永远吊在那里。
      fieldwatchDeepLinkBridge.accept('airwavefootprints://turnstile?token=');
      return true;
    }
    if (this.creating) {
      this.saveDraft();
      this.notice = '';
      this.goToMode('list');
      // 新建只从列表的「提出」进入（详情里的补充是内联的，不是独立的 compose），
      // 所以这里一律回列表 —— 与漫匣的实际流程一致。
      return true;
    }
    if (this.detail !== undefined) {
      this.notice = '';
      this.goToMode('list');
      void this.loadList(1);
      return true;
    }
    this.leaveThenClose();
    return true;
  }

  // ── 草稿（跨退出保留；漫匣还会跨重启，这里先做到会话内 + 设置存储） ──
  private saveDraft(): void {
    ngfSettingsStoreFacade.setString(DRAFT_TITLE_KEY, this.draftTitle);
    ngfSettingsStoreFacade.setString(DRAFT_BODY_KEY, this.draftBody);
    ngfSettingsStoreFacade.setString(DRAFT_TYPE_KEY, this.draftType);
  }

  private restoreDraft(): void {
    this.draftTitle = ngfSettingsStoreFacade.getString(DRAFT_TITLE_KEY, '');
    this.draftBody = ngfSettingsStoreFacade.getString(DRAFT_BODY_KEY, '');
    const savedType: string = ngfSettingsStoreFacade.getString(DRAFT_TYPE_KEY, '');
    if (savedType.length > 0) this.draftType = savedType;
  }

  private clearDraft(): void {
    this.saveDraft();
    ngfSettingsStoreFacade.setString(DRAFT_TITLE_KEY, '');
    ngfSettingsStoreFacade.setString(DRAFT_BODY_KEY, '');
  }

  /**
   * Toast 提示。
   *
   * 与漫匣同一实现（`getPromptAction().showToast`，2200ms）。
   * 提交成功、校验失败这类**一次性结果**必须用 toast ——
   * 只写进页面里的 `notice` 会被滚动带走，用户根本注意不到。
   */
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
  }

  private leaveThenClose(): void {
    if (this.leaving) return;
    this.leaving = true;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn,
      onFinish: (): void => { this.onClose(); } }, (): void => {
      this.enterShift = 40;
      this.enterAlpha = 0;
    });
  }

  /** 把状态码翻成用户能照着做的提示。 */
  private noticeOf(response: FeedbackResponse): string {
    if (response.outcome === FeedbackOutcome.RATE_LIMITED) return this.text('app.string.fieldwatch_feedback_rate_limited');
    if (response.outcome === FeedbackOutcome.NOT_FOUND) return this.text('app.string.fieldwatch_feedback_not_found');
    if (response.outcome === FeedbackOutcome.INVALID) return this.text('app.string.fieldwatch_feedback_invalid');
    if (response.outcome === FeedbackOutcome.CHUNK_MISMATCH) return this.text('app.string.fieldwatch_feedback_chunk_mismatch');
    return this.text('app.string.fieldwatch_feedback_network_failed');
  }

  /**
   * 取一枚 Turnstile 令牌：打开挑战页，等回传。
   *
   * 挑战页由内嵌 WebView 加载，`onLoadIntercept` 拦到 `airwavefootprints://turnstile`
   * 就交给深链桥结算；走系统浏览器时同一条深链也会落到同一个桥。
   * 超时/失败一律返回空串，由调用方走「验证失败」分支。
   */
  private async requestToken(): Promise<string> {
    this.turnstileHint = this.text('app.string.fieldwatch_feedback_turnstile_wait');
    this.turnstileOpen = true;
    const token: string = await fieldwatchDeepLinkBridge.waitForTurnstileToken(TOKEN_TIMEOUT_MS);
    this.turnstileOpen = false;
    this.turnstileHint = '';
    if (token.length === 0) this.notice = this.text('app.string.fieldwatch_feedback_turnstile_failed');
    return token;
  }

  private async loadList(page: number): Promise<void> {
    this.loading = true;
    this.notice = '';
    const response: FeedbackResponse = await fieldwatchFeedbackService.listIssues(
      page, PAGE_SIZE, this.search.trim(), this.typeFilter, this.statusFilter);
    this.loading = false;
    if (!response.ok()) {
      this.showToast(this.noticeOf(response));
      return;
    }
    const parsed: FeedbackIssuePage = this.parsePage(response.body);
    this.items = page === 1 ? parsed.items : this.items.concat(parsed.items);
    this.total = parsed.total;
    this.page = page;
    this.tick += 1;
  }

  private async loadDetail(issueNumber: number): Promise<void> {
    this.loading = true;
    this.notice = '';
    const response: FeedbackResponse = await fieldwatchFeedbackService.getIssue(issueNumber);
    this.loading = false;
    if (!response.ok()) { this.showToast(this.noticeOf(response)); return; }
    this.detail = this.parseDetail(response.body);
    this.goToMode('detail');
    this.tick += 1;
  }

  private async submitDraft(): Promise<void> {
    // **两条独立校验**（与漫匣一致）：
    //
    // 原来合成了一条「标题与描述都要填」—— 用户两个都填了却看到这句话，
    // 完全不知道真正的原因是描述差一个字（实测反馈）。
    // 提示必须指出**到底是哪一项、差多少**。
    const title: string = this.draftTitle.trim();
    const body: string = this.draftBody.trim();
    if (title.length < 2) {
      this.showToast(this.text('app.string.fieldwatch_feedback_need_title'));
      return;
    }
    if (body.length < 10) {
      this.showToast(this.text('app.string.fieldwatch_feedback_need_body')
        .replace('%1', body.length.toString()));
      return;
    }
    const token: string = await this.requestToken();
    if (token.length === 0) return;
    this.submitting = true;
    this.notice = '';
    const payload: FeedbackCreateIssue = new FeedbackCreateIssue();
    payload.title = this.draftTitle.trim();
    payload.description = this.draftBody.trim();
    payload.issue_type = this.draftType as FeedbackIssueType;
    payload.diagnostic = this.diagnostic();
    payload.context = this.context();
    payload.turnstile_token = token;
    const response: FeedbackResponse = await fieldwatchFeedbackService.createIssue(payload);
    this.submitting = false;
    if (!response.ok()) { this.showToast(this.noticeOf(response)); return; }
    this.clearDraft();
    this.draftTitle = '';
    this.draftBody = '';
    const created: FeedbackIssueDetail | undefined = this.parseDetail(response.body);
    this.detail = created;
    this.goToMode('detail');
    // **先报成功**：issue 已经建出来了，这一步的成败与后面的附件无关。
    // 带上编号，用户能立刻去列表里找到它（漫匣也是这么做的）。
    if (created !== undefined) {
      this.showToast(this.text('app.string.fieldwatch_feedback_toast_submitted')
        .replace('%1', created.issue_number.toString()));
    }
    // **附件在反馈创建成功之后才传**：上传会话必须挂在一条已存在的反馈上，
    // 先传再建是拿不到 issue_number 的。
    const total: number = this.attachments.length;
    if (created !== undefined && total > 0) {
      try {
        const uploaded: number = await this.uploadAll(created.issue_number, token);
        this.showToast(this.text('app.string.fieldwatch_feedback_toast_uploaded')
          .replace('%1', uploaded.toString()).replace('%2', total.toString()));
      } catch (error) {
        const failure: BusinessError = error as BusinessError;
        logger.warn(TAG, '附件上传中断 code=' + failure.code + ' msg=' + failure.message);
        this.showToast(this.text('app.string.fieldwatch_feedback_toast_upload_partial'));
      }
      // 传完（或失败）都要重新拉一次详情：服务端才知道附件真正落了多少，
      // 本地那份是「我以为的状态」，不能当结果用。
      void this.loadDetail(created.issue_number);
    }
    // **清空必须无条件执行**：否则上传中途出错时附件会残留在表单里，
    // 用户以为没提交成功，实际 issue 已经建好了（实测反馈）。
    this.attachments = [];
    this.notice = '';
    void this.loadList(1);
  }

  /** 「我也遇到了」：**不带令牌**，只带设备 ID。 */
  private async support(): Promise<void> {
    const detail: FeedbackIssueDetail | undefined = this.detail;
    if (detail === undefined) return;
    this.loading = true;
    const response: FeedbackResponse = await fieldwatchFeedbackService.supportIssue(detail.issue_number);
    this.loading = false;
    if (!response.ok()) { this.showToast(this.noticeOf(response)); return; }
    let already: boolean = false;
    try {
      already = (JSON.parse(response.body) as FeedbackSupportResult).already_supported;
    } catch (error) {
      already = false;
    }
    this.showToast(already
      ? this.text('app.string.fieldwatch_feedback_already_supported')
      : this.text('app.string.fieldwatch_feedback_supported'));
    void this.loadDetail(detail.issue_number);
  }

  private async sendReply(): Promise<void> {
    const detail: FeedbackIssueDetail | undefined = this.detail;
    if (detail === undefined) return;
    if (this.replyText.trim().length < 2) {
      this.showToast(this.text('app.string.fieldwatch_feedback_reply_too_short'));
      return;
    }
    const token: string = await this.requestToken();
    if (token.length === 0) return;
    this.loading = true;
    const response: FeedbackResponse = await fieldwatchFeedbackService.createPost(
      detail.issue_number, this.replyText.trim(), token);
    this.loading = false;
    if (!response.ok()) { this.showToast(this.noticeOf(response)); return; }
    this.replyText = '';
    this.showToast(this.text('app.string.fieldwatch_feedback_toast_replied'));
    void this.loadDetail(detail.issue_number);
  }

  // ── 附件 ──

  private abilityContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 待上传附件的总字节数。 */
  private pendingBytes(): number {
    let total: number = 0;
    this.attachments.forEach((item: LocalAttachment): void => { total += item.size; });
    return total;
  }

  /**
   * 选文件。
   *
   * 两道上限**在选中时就拦**（单文件 80 MiB、单条总量 160 MiB）：
   * 让用户传完 79 MiB 才被服务端拒掉，是纯粹的浪费。
   */
  private async selectAttachments(): Promise<void> {
    const context: common.UIAbilityContext | undefined = this.abilityContext();
    if (context === undefined) { this.notice = this.text('app.string.fieldwatch_feedback_picker_failed'); return; }
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 5;
      options.fileSuffixFilters = ['.txt', '.log', '.json', '.xml', '.md', '.csv',
        '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp',
        '.mp4', '.mov', '.webm', '.zip', '.tar', '.gz', '.7z'];
      const uris: string[] = await documentPicker.select(options);
      for (let i: number = 0; i < uris.length; i += 1) {
        await this.adoptPickedFile(uris[i]);
      }
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '选择附件失败 code=' + failure.code + ' msg=' + failure.message);
    }
  }

  /** 把选中的 URI 复制进沙箱并登记为待上传项。 */
  private async adoptPickedFile(uri: string): Promise<void> {
    const name: string = this.fileNameOf(uri);
    try {
      const source: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = await fileIo.stat(source.fd);
      if (stat.size > MAX_FILE_BYTES) {
        await fileIo.close(source);
        this.notice = this.text('app.string.fieldwatch_feedback_file_too_large');
        return;
      }
      if (this.pendingBytes() + stat.size > MAX_ISSUE_BYTES) {
        await fileIo.close(source);
        this.notice = this.text('app.string.fieldwatch_feedback_total_too_large');
        return;
      }
      // 复制进沙箱：选择器给的 URI 权限是临时的，上传可能要几分钟，
      // 期间用户可能已经切走应用（漫匣同样这么做）。
      const context: common.UIAbilityContext | undefined = this.abilityContext();
      const dir: string = context === undefined ? '' : context.cacheDir;
      const target: string = dir + '/fb_' + Date.now().toString() + '_' + name;
      await fileIo.copyFile(source.fd, target);
      await fileIo.close(source);
      this.attachmentSeq += 1;
      const item: LocalAttachment = new LocalAttachment();
      item.localId = 'local-' + Date.now().toString() + '-' + this.attachmentSeq.toString();
      item.name = name;
      item.localPath = target;
      item.size = stat.size;
      item.mediaType = this.mediaTypeOf(name);
      item.category = this.categoryOf(name);
      this.attachments = this.attachments.concat([item]);
      this.notice = '';
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '登记附件失败 code=' + failure.code + ' msg=' + failure.message);
      this.notice = this.text('app.string.fieldwatch_feedback_picker_failed');
    }
  }

  private removeAttachment(localId: string): void {
    const next: LocalAttachment[] = [];
    this.attachments.forEach((item: LocalAttachment): void => {
      if (item.localId !== localId) next.push(item);
    });
    this.attachments = next;
  }

  /**
   * 生成「应用日志」附件。
   *
   * 取本应用自己的日志缓冲（现场问题几乎都发生在扫描过程中，
   * 日志比截图有用得多）。没有日志就不生成空文件。
   */
  private async attachAppLogs(minutes: number): Promise<void> {
    const context: common.UIAbilityContext | undefined = this.abilityContext();
    if (context === undefined) { this.notice = this.text('app.string.fieldwatch_feedback_log_failed'); return; }
    await this.removeGeneratedLogs();
    const state = fieldwatchApplication.getState();
    const lines: string[] = [];
    const cutoff: number = minutes > 0 ? Date.now() - minutes * 60 * 1000 : 0;
    lines.push('# 电波足迹 · 记录导出');
    lines.push('# 导出时间: ' + new Date().toISOString());
    lines.push('# 应用版本: ' + deviceInfo.displayVersion + ' / ' + deviceInfo.osFullName);
    lines.push('');
    // `state.logs` 是「记录」—— 用户主动保存的观测条目，不是技术日志。
    // 现场问题几乎都能在最近的记录里复现，所以导出它比导出 hilog 有用。
    state.logs.forEach((entry: LogEntry): void => {
      const observation = entry.observation;
      if (observation.seenAt < cutoff) return;
      lines.push('[' + new Date(observation.seenAt).toISOString() + '] '
        + observation.kind + ' ' + observation.name + ' (' + observation.address + ')'
        + ' ' + observation.rssi.toString() + ' dBm');
    });
    if (lines.length <= 4) { this.notice = this.text('app.string.fieldwatch_feedback_no_logs'); return; }
    const path: string = context.cacheDir + '/af_logs_' + Date.now().toString() + '.txt';
    const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    try {
      await fileIo.write(file.fd, lines.join('\n'));
    } finally {
      await fileIo.close(file);
    }
    const stat: fileIo.Stat = await fileIo.stat(path);
    this.attachmentSeq += 1;
    const item: LocalAttachment = new LocalAttachment();
    item.localId = 'log-' + Date.now().toString() + '-' + this.attachmentSeq.toString();
    item.name = 'airwavefootprints-log.txt';
    item.localPath = path;
    item.size = stat.size;
    item.mediaType = 'text/plain';
    item.category = 'text';
    item.isGeneratedLog = true;
    this.attachments = this.attachments.concat([item]);
    this.logRangeMinutes = minutes;
    this.notice = this.text('app.string.fieldwatch_feedback_log_attached')
      .replace('%1', (lines.length - 4).toString());
  }

  private async removeGeneratedLogs(): Promise<void> {
    this.logRangeMinutes = -1;
    const next: LocalAttachment[] = [];
    for (let i: number = 0; i < this.attachments.length; i += 1) {
      const item: LocalAttachment = this.attachments[i];
      if (item.isGeneratedLog) {
        try { await fileIo.unlink(item.localPath); } catch (error) { /* 文件可能已被清掉 */ }
      } else {
        next.push(item);
      }
    }
    this.attachments = next;
  }

  /** 文件名（去掉 URI 的查询串）。 */
  private fileNameOf(uri: string): string {
    const cut: number = uri.indexOf('?');
    const clean: string = cut === -1 ? uri : uri.substring(0, cut);
    const slash: number = clean.lastIndexOf('/');
    const raw: string = slash === -1 ? clean : clean.substring(slash + 1);
    return raw.length > 0 ? raw : 'attachment';
  }

  private suffixOf(name: string): string {
    const dot: number = name.lastIndexOf('.');
    return dot === -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /** 后缀 -> category（服务端只收 text/image/video/archive）。 */
  private categoryOf(name: string): FeedbackUploadCategory {
    const suffix: string = this.suffixOf(name);
    if (['txt', 'log', 'json', 'xml', 'md', 'csv', 'yml', 'yaml'].indexOf(suffix) >= 0) return 'text';
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'].indexOf(suffix) >= 0) return 'image';
    if (['mp4', 'mov', 'mkv', 'webm', 'avi'].indexOf(suffix) >= 0) return 'video';
    return 'archive';
  }

  private mediaTypeOf(name: string): string {
    const suffix: string = this.suffixOf(name);
    if (suffix === 'txt' || suffix === 'log') return 'text/plain';
    if (suffix === 'json') return 'application/json';
    if (suffix === 'png') return 'image/png';
    if (suffix === 'jpg' || suffix === 'jpeg') return 'image/jpeg';
    if (suffix === 'webp') return 'image/webp';
    if (suffix === 'gif') return 'image/gif';
    if (suffix === 'mp4') return 'video/mp4';
    if (suffix === 'zip') return 'application/zip';
    return 'application/octet-stream';
  }

  /**
   * 把附件逐个传上去。
   *
   * 每份走三步：算 SHA-256 -> 开会话 -> 分块上传 + complete。
   * 一份失败不阻断其余（用户至少能拿到部分附件），但会在卡片上标红。
   */
  private async uploadAll(issueNumber: number, token: string): Promise<number> {
    let uploaded: number = 0;
    this.uploadCancelled = false;
    const total: number = this.attachments.length;
    for (let i: number = 0; i < this.attachments.length; i += 1) {
      const item: LocalAttachment = this.attachments[i];
      if (this.uploadCancelled) break;
      // 上传可能要几分钟（80 MiB 上限），**必须一直有可见进度**，
      // 否则用户不知道还在传还是已经卡死（漫匣同款文案）。
      this.uploadText = this.text('app.string.fieldwatch_feedback_uploading_named')
        .replace('%1', (i + 1).toString())
        .replace('%2', total.toString())
        .replace('%3', item.name);
      this.patchAttachment(item.localId, 0, LocalAttachmentStatus.UPLOADING, '');
      try {
        const hash: FeedbackFileHash = await fieldwatchFeedbackService.calculateFileSha256(item.localPath);
        const sessionResponse: FeedbackResponse = await fieldwatchFeedbackService.createUploadSession(
          issueNumber, item.name, hash.size, hash.sha256, item.mediaType, item.category, token, '');
        if (!sessionResponse.ok()) {
          this.patchAttachment(item.localId, 0, LocalAttachmentStatus.FAILED, this.noticeOf(sessionResponse));
          continue;
        }
        const session: FeedbackUploadSession = JSON.parse(sessionResponse.body) as FeedbackUploadSession;
        // 服务端没回 requested_size 时用本地大小兜底，否则循环条件永远不成立。
        if (session.requested_size <= 0) session.requested_size = hash.size;
        if (session.chunk_size <= 0) session.chunk_size = UPLOAD_CHUNK_SIZE;
        const localId: string = item.localId;
        const response: FeedbackResponse = await fieldwatchFeedbackService.uploadFile(
          item.localPath, session,
          (progress: FeedbackUploadProgress): void => {
            this.patchAttachment(localId, progress.completed, LocalAttachmentStatus.UPLOADING, '');
          },
          (): boolean => this.uploadCancelled);
        if (response.ok()) {
          uploaded += 1;
          this.patchAttachment(item.localId, item.size, LocalAttachmentStatus.DONE, '');
        } else {
          this.patchAttachment(item.localId, 0, LocalAttachmentStatus.FAILED, this.noticeOf(response));
        }
      } catch (error) {
        const failure: BusinessError = error as BusinessError;
        logger.warn(TAG, '上传附件失败 code=' + failure.code + ' msg=' + failure.message);
        this.patchAttachment(item.localId, 0, LocalAttachmentStatus.FAILED,
          this.text('app.string.fieldwatch_feedback_upload_failed'));
      }
    }
    this.uploadText = '';
    return uploaded;
  }

  private patchAttachment(localId: string, progress: number, status: LocalAttachmentStatus, error: string): void {
    const next: LocalAttachment[] = [];
    this.attachments.forEach((item: LocalAttachment): void => {
      if (item.localId === localId) {
        const updated: LocalAttachment = new LocalAttachment();
        updated.localId = item.localId;
        updated.name = item.name;
        updated.localPath = item.localPath;
        updated.size = item.size;
        updated.mediaType = item.mediaType;
        updated.category = item.category;
        updated.isGeneratedLog = item.isGeneratedLog;
        updated.progress = progress;
        updated.status = status;
        updated.errorMessage = error;
        next.push(updated);
      } else {
        next.push(item);
      }
    });
    this.attachments = next;
    this.tick += 1;
  }

  private diagnostic(): FeedbackDiagnostic {
    const info: FeedbackDiagnostic = new FeedbackDiagnostic();
    // `deviceInfo.model` 在当前 API 上不存在，正确字段是 `productModel`。
    info.model = deviceInfo.productModel;
    info.system_version = deviceInfo.osFullName;
    info.app_version = deviceInfo.displayVersion;
    info.build_number = 0;
    info.device_type = deviceInfo.deviceType;
    return info;
  }

  /**
   * 现场上下文：**只填这三个键**。
   *
   * 多传漫匣的字段（`manga_title` 之类）会被服务端 422 拒掉。
   * 这里取当前关注的目标名与位置标注，让反馈自带现场信息。
   */
  private context(): FeedbackContext {
    const ctx: FeedbackContext = new FeedbackContext();
    // 用户明确要求去掉现场上下文（电台/频率/位置）。
    // 仍然按文档形状发出这三个键（**空值**）—— 服务端做的是「只许这三个键」的
    // 白名单校验，键在、值为空不会 422；整个省略反而可能撞上必填校验。
    return ctx;
  }

  private parsePage(text: string): FeedbackIssuePage {
    const page: FeedbackIssuePage = new FeedbackIssuePage();
    if (text.length === 0) return page;
    try {
      const raw = JSON.parse(text) as FeedbackIssuePage;
      page.items = raw.items === undefined ? [] : raw.items;
      page.total = raw.total === undefined ? 0 : raw.total;
    } catch (error) {
      page.items = [];
    }
    return page;
  }

  /**
   * 解析详情。**必须显式归一化**。
   *
   * `JSON.parse` 得到的是**普通对象，不会带上类的字段默认值**：
   * 服务端没返回的字段（`posts` / `attachments` / `context`…）会是 `undefined`，
   * 而 `ForEach(undefined)` 会让整个页面渲染失败 ——
   * 实测表现是「标题栏在、内容全白」，非常难查。
   */
  private parseDetail(text: string): FeedbackIssueDetail | undefined {
    try {
      const raw = JSON.parse(text) as FeedbackIssueDetail;
      const detail: FeedbackIssueDetail = new FeedbackIssueDetail();
      detail.id = raw.id;
      detail.issue_number = raw.issue_number;
      detail.title = raw.title;
      detail.issue_type = raw.issue_type;
      detail.status = raw.status;
      detail.priority = raw.priority;
      detail.labels = raw.labels === undefined ? [] : raw.labels;
      detail.support_count = raw.support_count;
      detail.post_count = raw.post_count;
      detail.attachment_count = raw.attachment_count;
      detail.created_at = raw.created_at;
      detail.updated_at = raw.updated_at;
      detail.description = raw.description === undefined ? '' : raw.description;
      detail.supported_by_device = raw.supported_by_device === true;
      detail.posts = raw.posts === undefined ? [] : raw.posts;
      detail.attachments = raw.attachments === undefined ? [] : raw.attachments;
      detail.diagnostic = raw.diagnostic === undefined ? new FeedbackDiagnostic() : raw.diagnostic;
      detail.context = raw.context === undefined ? new FeedbackContext() : raw.context;
      // 上下文字段也可能是 undefined（服务端省略空值）。
      if (detail.context.station_name === undefined) detail.context.station_name = '';
      if (detail.context.frequency === undefined) detail.context.frequency = '';
      if (detail.context.location === undefined) detail.context.location = '';
      if (detail.diagnostic.model === undefined) detail.diagnostic.model = '';
      if (detail.diagnostic.system_version === undefined) detail.diagnostic.system_version = '';
      if (detail.diagnostic.app_version === undefined) detail.diagnostic.app_version = '';
      return detail;
    } catch (error) {
      return undefined;
    }
  }

  build() {
    if (this.withShell) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.TopStart }) {
          NGFImmersiveTopChromeUnderlay({
            spec: NGFImmersiveTopChromePresetFactory.build(FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().panel, FieldwatchPaletteHolder.get().night,
              FieldwatchPaletteHolder.get().accent, FieldwatchPaletteHolder.get().accent,
              this.underlayHeight)
          })
          this.buildBody()
          if (this.turnstileOpen) this.buildTurnstile()
        }.width('100%').height('100%')
      }
      .titleBar(NGFHdsTitleBarOptionsFactory.build(
        $r('app.string.fieldwatch_feedback_title'),
        $r('app.string.fieldwatch_feedback_subtitle'),
        FieldwatchPaletteHolder.get().night,
        hdsMaterial.MaterialLevel.GENTLE,
        true,
        false
      ))
      .onBackPressed((): boolean => { return this.handleBack(); })
      .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .translate({ x: this.enterShift })
      .opacity(this.enterAlpha)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    } else {
      this.buildBody()
    }
  }

  /** Turnstile 挑战页。**拦截自定义 scheme**，不依赖外部浏览器。 */
  @Builder
  private buildTurnstile() {
    Stack({ alignContent: Alignment.Bottom }) {
      Web({ src: TURNSTILE_SHELL_URL, controller: this.webController })
        .width('100%').height('100%')
        .backgroundColor(FieldwatchPaletteHolder.get().night)
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          const url: string = event.data.getRequestUrl();
          // 挑战完成 → 页面跳 `airwavefootprints://turnstile?token=…`，
          // 这里截住它，交给深链桥结算等待者，**不要让 WebView 真去导航**。
          if (url.startsWith('airwavefootprints://')) {
            fieldwatchDeepLinkBridge.accept(url);
            return true;
          }
          return false;
        })
      // ── 悬浮提示 ──
      //
      // 验证可能要很久（Cloudflare 挑战 + 用户操作），期间**必须一直有一块
      // 明确的状态提示**，否则用户不知道应用是在等他还是卡死了。
      //
      // 做成**贴底悬浮卡**而不是全屏遮罩：挑战页本身要能操作，
      // 盖住它等于让人没法完成验证。
      Row({ space: 12 }) {
        LoadingProgress().width(26).height(26)
          .color(FieldwatchPaletteHolder.get().accent)
        Column({ space: 3 }) {
          Text($r('app.string.fieldwatch_feedback_turnstile_title')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().text)
          Text(this.turnstileHint.length > 0
            ? this.turnstileHint : $r('app.string.fieldwatch_feedback_turnstile_wait'))
            .fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text($r('app.string.fieldwatch_feedback_turnstile_cancel')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().accent)
          .onClick((): void => { fieldwatchDeepLinkBridge.accept('airwavefootprints://turnstile?token='); })
      }.width('100%').padding(14)
      .backgroundColor(FieldwatchPaletteHolder.get().panel)
      .borderRadius(16)
      .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().outline)
      .shadow({ radius: 24, color: FieldwatchPaletteHolder.get().night, offsetX: 0, offsetY: 8 })
      .margin({ left: 16, right: 16, bottom: 28 })
    }.width('100%').height('100%')
    .backgroundColor(FieldwatchPaletteHolder.get().night)
  }

  @Builder
  private buildBody() {
    Scroll(this.contentScroller) {
      Column({ space: 12 }) {
        if (this.detail !== undefined) this.buildDetail(this.detail)
        else if (this.creating) this.buildCreateForm()
        else this.buildList()
      }.width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: this.withShell ? ngfImmersiveContentTop(this.underlayHeight, this.topInset) : 20, bottom: 48 })
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
    // 内容切换动画：透明度 + 纵向位移，与漫匣同一套参数。
    .opacity(this.contentOpacity)
    .translate({ y: this.contentOffsetY })
  }

  @Builder
  private buildList() {
    Column({ space: 12 }) {
      this.buildBannerCard()
      this.buildSearchCard()
      if (this.loading) Text($r('app.string.fieldwatch_feedback_loading')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
      if (this.notice.length > 0) Text(this.notice).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().warn)
      if (this.items.length === 0 && !this.loading && this.notice.length === 0) {
        Text($r('app.string.fieldwatch_feedback_no_items')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }
      ForEach(this.items, (item: FeedbackIssueSummary): void => {
        this.buildIssueCard(item)
      }, (item: FeedbackIssueSummary): string => item.id)
      if (this.items.length > 0 && this.items.length < this.total) {
        Button($r('app.string.fieldwatch_feedback_load_more')).height(40).width('100%')
          .backgroundColor(FieldwatchPaletteHolder.get().accent)
          .fontColor(FieldwatchPaletteHolder.get().night)
          .onClick((): void => { void this.loadList(this.page + 1); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 顶部横幅：说明这是什么 + 「提出」入口。 */
  @Builder
  private buildBannerCard() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Stack() {
          Circle().width(40).height(40).fill(FieldwatchPaletteHolder.get().accent)
          SymbolGlyph($r('sys.symbol.info_circle')).fontSize(22)
            .fontColor([FieldwatchPaletteHolder.get().night])
        }
        Column({ space: 3 }) {
          Text($r('app.string.fieldwatch_feedback_banner_title')).fontSize(18)
            .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
          Text($r('app.string.fieldwatch_feedback_banner_sub')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(15)
            .fontColor([FieldwatchPaletteHolder.get().night])
          Text($r('app.string.fieldwatch_feedback_new_short')).fontSize(14)
            .fontColor(FieldwatchPaletteHolder.get().night)
        }.padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(18).backgroundColor(FieldwatchPaletteHolder.get().accent)
        .onClick((): void => { this.notice = ''; this.goToMode('compose'); })
      }.width('100%')
      Text($r('app.string.fieldwatch_feedback_banner_note')).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().textDim).width('100%').textAlign(TextAlign.Center)
      Row({ space: 8 }) {
        Text($r('app.string.fieldwatch_feedback_badge_anon')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().accent)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(9)
          .backgroundColor(FieldwatchPaletteHolder.get().accent + '1F')
        Text($r('app.string.fieldwatch_feedback_badge_admin')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%').justifyContent(FlexAlign.Center)
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  /** 搜索 + 类型/状态筛选（同一张卡片，与漫匣一致）。 */
  @Builder
  private buildSearchCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          TextInput({ text: this.search, placeholder: $r('app.string.fieldwatch_feedback_search') })
            .layoutWeight(1).height(36).fontSize(14).backgroundColor(Color.Transparent)
            .onChange((value: string): void => { this.search = value; })
            .onSubmit((): void => { void this.loadList(1); })
        }.layoutWeight(1).height(40).padding({ left: 12, right: 12 })
        .borderRadius(20).backgroundColor(FieldwatchPaletteHolder.get().night)
        Stack() {
          Circle().width(38).height(38).fill(FieldwatchPaletteHolder.get().accent)
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20)
            .fontColor([FieldwatchPaletteHolder.get().night])
        }.onClick((): void => { void this.loadList(1); })
      }.width('100%')
      Row({ space: 6 }) {
        Text($r('app.string.fieldwatch_feedback_label_type')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width(30)
        this.buildTypeChip($r('app.string.fieldwatch_feedback_all'), '')
        ForEach(ISSUE_TYPES, (item: string): void => {
          this.buildTypeChip($r('app.string.fieldwatch_feedback_type_' + item), item)
        }, (item: string): string => item)
      }.width('100%')
      Row({ space: 6 }) {
        Text($r('app.string.fieldwatch_feedback_label_status')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim).width(30)
        this.buildStatusChip($r('app.string.fieldwatch_feedback_all'), '')
        this.buildStatusChip($r('app.string.fieldwatch_feedback_status_open'), 'open')
        this.buildStatusChip($r('app.string.fieldwatch_feedback_status_in_progress'), 'in_progress')
        this.buildStatusChip($r('app.string.fieldwatch_feedback_status_resolved'), 'resolved')
        this.buildStatusChip($r('app.string.fieldwatch_feedback_status_closed'), 'closed')
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  /** Issue 卡片：编号 + 类型徽标 + 状态徽标 + 居中标题 + 支持/补充 + 箭头。 */
  @Builder
  private buildIssueCard(item: FeedbackIssueSummary) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(16)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text('#' + item.issue_number.toString()).fontSize(14)
          .fontColor(FieldwatchPaletteHolder.get().accent)
        Text(this.typeLabel(item.issue_type)).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().text)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(9)
          .backgroundColor(FieldwatchPaletteHolder.get().night)
        Blank()
        Text(this.statusLabel(item.status)).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().accent)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(11)
          .borderWidth(1).borderColor(FieldwatchPaletteHolder.get().accent)
      }.width('100%')
      Text(item.title).fontSize(17).fontColor(FieldwatchPaletteHolder.get().text)
        .width('100%').textAlign(TextAlign.Center).maxLines(3)
      Row({ space: 16 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.star')).fontSize(14)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text(this.text('app.string.fieldwatch_feedback_support_count').replace('%1', item.support_count.toString()))
            .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
        }
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(14)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text(this.text('app.string.fieldwatch_feedback_post_count').replace('%1', item.post_count.toString()))
            .fontSize(13).fontColor(FieldwatchPaletteHolder.get().textDim)
        }
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .onClick((): void => { void this.loadDetail(item.issue_number); })
  }

  @Builder
  private buildStatusChip(label: ResourceStr, value: string) {
    Text(label).fontSize(13).height(30).layoutWeight(1).textAlign(TextAlign.Center)
      .borderRadius(15)
      .backgroundColor(this.statusFilter === value
        ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().night)
      .fontColor(this.statusFilter === value
        ? FieldwatchPaletteHolder.get().night : FieldwatchPaletteHolder.get().text)
      .onClick((): void => { this.statusFilter = value; void this.loadList(1); })
  }

  @Builder
  private buildTypeChip(label: ResourceStr, value: string) {
    Text(label).fontSize(13).height(30).layoutWeight(1).textAlign(TextAlign.Center)
      .borderRadius(15)
      .backgroundColor(this.typeFilter === value
        ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().night)
      .fontColor(this.typeFilter === value
        ? FieldwatchPaletteHolder.get().night : FieldwatchPaletteHolder.get().text)
      .onClick((): void => { this.typeFilter = value; void this.loadList(1); })
  }

  private listSummary(): string {
    const template: string = this.text('app.string.fieldwatch_feedback_list_summary');
    return template.replace('%1', this.items.length.toString()).replace('%2', this.total.toString());
  }

  private issueMeta(item: FeedbackIssueSummary): string {
    const template: string = this.text('app.string.fieldwatch_feedback_issue_meta');
    return template.replace('%1', this.typeLabel(item.issue_type))
      .replace('%2', this.statusLabel(item.status))
      .replace('%3', item.support_count.toString())
      .replace('%4', item.post_count.toString());
  }

  private typeLabel(value: string): string {
    return ISSUE_TYPES.indexOf(value) >= 0 ? this.text('app.string.fieldwatch_feedback_type_' + value) : value;
  }

  private statusLabel(value: string): string {
    const known: string[] = ['open', 'in_progress', 'resolved', 'closed', 'merged'];
    return known.indexOf(value) >= 0 ? this.text('app.string.fieldwatch_feedback_status_' + value) : value;
  }

  @Builder
  private buildDetail(detail: FeedbackIssueDetail) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Blank()
        Text($r('app.string.fieldwatch_feedback_back')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().accent)
          .onClick((): void => { this.notice = ''; this.goToMode('list'); void this.loadList(1); })
      }.width('100%')
      Text(detail.title).fontSize(20).fontWeight(FontWeight.Medium)
        .fontColor(FieldwatchPaletteHolder.get().text).width('100%').textAlign(TextAlign.Center)
      // 支持 / 补充 计数 + 「我也遇到」。
      Row({ space: 16 }) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.star')).fontSize(15)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text(this.text('app.string.fieldwatch_feedback_support_count').replace('%1', detail.support_count.toString()))
            .fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim)
        }
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(15)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text(this.text('app.string.fieldwatch_feedback_post_count').replace('%1', detail.post_count.toString()))
            .fontSize(14).fontColor(FieldwatchPaletteHolder.get().textDim)
        }
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(15)
            .fontColor([FieldwatchPaletteHolder.get().night])
          Text(detail.supported_by_device
            ? $r('app.string.fieldwatch_feedback_supported_already') : $r('app.string.fieldwatch_feedback_support'))
            .fontSize(14).fontColor(FieldwatchPaletteHolder.get().night)
        }.padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(18)
        .backgroundColor(detail.supported_by_device
          ? FieldwatchPaletteHolder.get().textDim : FieldwatchPaletteHolder.get().accent)
        .onClick((): void => { void this.support(); })
      }.width('100%')
      if (this.notice.length > 0) Text(this.notice).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().warn)
      // 正文作为时间线的第一条（漫匣把描述也放在时间线里）。
      this.buildTimelineCard($r('app.string.fieldwatch_feedback_author_anon'), detail.description,
        detail.created_at, false)
      ForEach(detail.posts, (post: FeedbackIssuePost): void => {
        this.buildTimelineCard(post.author_kind, post.body, post.created_at,
          post.author_kind.indexOf('admin') >= 0 || post.author_kind.indexOf('管理') >= 0)
      }, (post: FeedbackIssuePost): string => post.id)
      this.buildDiagnosticCard(detail)
      this.buildPublicAttachments(detail)
      // 「匿名补充」：与漫匣一致，补充内容和附件放在同一段里。
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(18)
            .fontColor([FieldwatchPaletteHolder.get().accent])
          Text($r('app.string.fieldwatch_feedback_reply_title')).fontSize(15)
            .fontColor(FieldwatchPaletteHolder.get().text)
        }.width('100%').justifyContent(FlexAlign.Center)
        Text($r('app.string.fieldwatch_feedback_reply_sub')).fontSize(12)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
          .width('100%').textAlign(TextAlign.Center)
        TextArea({ text: this.replyText, placeholder: $r('app.string.fieldwatch_feedback_reply_hint') })
          .height(120).width('100%').fontSize(15)
          .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(14)
          .onChange((value: string): void => { this.replyText = value; })
      }.width('100%').padding(14)
      .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
      .alignItems(HorizontalAlign.Start)
      this.buildAttachmentCard()
      Button($r('app.string.fieldwatch_feedback_submit_reply')).height(46).width('100%')
        .backgroundColor(FieldwatchPaletteHolder.get().accent)
        .fontColor(FieldwatchPaletteHolder.get().night)
        .onClick((): void => { void this.sendReply(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  /** 时间线条目：头像 + 作者 + 时间 + 正文。 */
  @Builder
  private buildTimelineCard(author: ResourceStr, body: string, createdAt: string, isAdmin: boolean) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Stack() {
          Circle().width(36).height(36)
            .fill(isAdmin ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().night)
          SymbolGlyph($r(isAdmin ? 'sys.symbol.star_fill' : 'sys.symbol.person_fill')).fontSize(19)
            .fontColor([isAdmin ? FieldwatchPaletteHolder.get().night : FieldwatchPaletteHolder.get().textDim])
        }
        Column({ space: 2 }) {
          Text(author).fontSize(14).fontColor(FieldwatchPaletteHolder.get().text)
          Text($r('app.string.fieldwatch_feedback_badge_anon')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.formatStamp(createdAt)).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      Text(body).fontSize(15).fontColor(FieldwatchPaletteHolder.get().text)
        .width('100%').textAlign(TextAlign.Center)
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  /** 诊断信息卡：机型 / 系统 / APP 三列。 */
  @Builder
  private buildDiagnosticCard(detail: FeedbackIssueDetail) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right')).fontSize(18)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Text($r('app.string.fieldwatch_feedback_diagnostic')).fontSize(15)
          .fontColor(FieldwatchPaletteHolder.get().text)
        Blank()
        Text($r('app.string.fieldwatch_feedback_diagnostic_note_short')).fontSize(11)
          .fontColor(FieldwatchPaletteHolder.get().textDim)
      }.width('100%')
      Row({ space: 10 }) {
        this.buildMetaColumn($r('app.string.fieldwatch_feedback_meta_model'),
          detail.diagnostic === undefined || detail.diagnostic.model.length === 0
            ? this.text('app.string.fieldwatch_feedback_not_provided') : detail.diagnostic.model)
        this.buildMetaColumn($r('app.string.fieldwatch_feedback_meta_system'),
          detail.diagnostic === undefined || detail.diagnostic.system_version.length === 0
            ? this.text('app.string.fieldwatch_feedback_not_provided') : detail.diagnostic.system_version)
        this.buildMetaColumn($r('app.string.fieldwatch_feedback_meta_app'),
          detail.diagnostic === undefined || detail.diagnostic.app_version.length === 0
            ? this.text('app.string.fieldwatch_feedback_not_provided')
            : detail.diagnostic.app_version)
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildMetaColumn(label: ResourceStr, value: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      Text(value).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text).maxLines(1)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  /** 附件卡：选择文件 + 日志范围 + 限额说明（漫匣同款）。 */
  @Builder
  private buildAttachmentCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(20)
          .fontColor([FieldwatchPaletteHolder.get().accent])
        Column({ space: 2 }) {
          Text($r('app.string.fieldwatch_feedback_attachments')).fontSize(15)
            .fontColor(FieldwatchPaletteHolder.get().text)
          Text($r('app.string.fieldwatch_feedback_attachment_kinds')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(15)
            .fontColor([FieldwatchPaletteHolder.get().text])
          Text($r('app.string.fieldwatch_feedback_pick_file')).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().text)
        }.padding({ left: 12, right: 12, top: 7, bottom: 7 }).borderRadius(16)
        .backgroundColor(FieldwatchPaletteHolder.get().night)
        .onClick((): void => { void this.selectAttachments(); })
      }.width('100%')
      // 日志范围选择（漫匣的 15 分钟 / 1 小时 / 3 小时 / 全部 / 清除）。
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14)
            .fontColor([FieldwatchPaletteHolder.get().textDim])
          Text($r('app.string.fieldwatch_feedback_log_from_app')).fontSize(13)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%').justifyContent(FlexAlign.Center)
        Row({ space: 6 }) {
          this.buildLogRangeChip($r('app.string.fieldwatch_feedback_log_15m'), 15)
          this.buildLogRangeChip($r('app.string.fieldwatch_feedback_log_1h'), 60)
          this.buildLogRangeChip($r('app.string.fieldwatch_feedback_log_3h'), 180)
          this.buildLogRangeChip($r('app.string.fieldwatch_feedback_log_all'), 0)
          Text($r('app.string.fieldwatch_feedback_log_clear')).fontSize(13).height(32)
            .layoutWeight(1).textAlign(TextAlign.Center).borderRadius(16)
            .backgroundColor(FieldwatchPaletteHolder.get().accent)
            .fontColor(FieldwatchPaletteHolder.get().night)
            .onClick((): void => { void this.removeGeneratedLogs(); })
        }.width('100%')
      }.width('100%').padding(10).borderRadius(12)
      .backgroundColor(FieldwatchPaletteHolder.get().night)
      ForEach(this.attachments, (item: LocalAttachment): void => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(item.name).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text)
              .layoutWeight(1).maxLines(1)
            Text(this.formatBytes(item.size)).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
            Text($r('app.string.fieldwatch_feedback_remove')).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().warn)
              .onClick((): void => { this.removeAttachment(item.localId); })
          }.width('100%')
          Row() {
            Row().height(4).borderRadius(2)
              .width(Math.round(item.size === 0 ? 0 : item.progress / item.size * 100).toString() + '%')
              .backgroundColor(item.status === LocalAttachmentStatus.FAILED
                ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().accent)
          }.width('100%').height(4).borderRadius(2)
          .backgroundColor(FieldwatchPaletteHolder.get().outline)
          Text(this.attachmentStatus(item)).fontSize(11)
            .fontColor(item.status === LocalAttachmentStatus.FAILED
              ? FieldwatchPaletteHolder.get().warn : FieldwatchPaletteHolder.get().textDim)
        }.width('100%').padding(10)
        .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(10)
        .alignItems(HorizontalAlign.Start)
      }, (item: LocalAttachment): string => item.localId)
      // 上传中：转圈 + 文案 + 取消（漫匣同款）。
      if (this.uploadText.length > 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
            .color(FieldwatchPaletteHolder.get().accent)
          Text(this.uploadText).fontSize(12).layoutWeight(1).maxLines(1)
            .fontColor(FieldwatchPaletteHolder.get().accent)
          Text($r('app.string.fieldwatch_feedback_upload_cancel')).fontSize(12)
            .fontColor(FieldwatchPaletteHolder.get().warn)
            .onClick((): void => { this.uploadCancelled = true; })
        }.width('100%').padding(10).borderRadius(10)
        .backgroundColor(FieldwatchPaletteHolder.get().night)
      }
      // 限额用 AF 自己的数字（漫匣是 10/20/80，与 AF 不同，不能照抄）。
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.info_circle')).fontSize(13)
          .fontColor([FieldwatchPaletteHolder.get().textDim])
        Text(this.attachmentHint()).fontSize(11).fontColor(FieldwatchPaletteHolder.get().textDim)
          .layoutWeight(1)
      }.width('100%')
    }.width('100%').padding(14)
    .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildLogRangeChip(label: ResourceStr, minutes: number) {
    Text(label).fontSize(13).height(32).layoutWeight(1).textAlign(TextAlign.Center)
      .borderRadius(16)
      .backgroundColor(this.logRangeMinutes === minutes
        ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().panel)
      .fontColor(this.logRangeMinutes === minutes
        ? FieldwatchPaletteHolder.get().night : FieldwatchPaletteHolder.get().text)
      .onClick((): void => { void this.attachAppLogs(minutes); })
  }
  @Builder
  private buildCreateForm() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Blank()
        Text($r('app.string.fieldwatch_feedback_cancel')).fontSize(13)
          .fontColor(FieldwatchPaletteHolder.get().accent)
          .onClick((): void => { this.notice = ''; this.goToMode('list'); })
      }.width('100%')
      Text($r('app.string.fieldwatch_feedback_create_title')).fontSize(20)
        .fontWeight(FontWeight.Medium).fontColor(FieldwatchPaletteHolder.get().text)
        .width('100%').textAlign(TextAlign.Center)
      Text($r('app.string.fieldwatch_feedback_create_sub')).fontSize(13)
        .fontColor(FieldwatchPaletteHolder.get().textDim)
        .width('100%').textAlign(TextAlign.Center)
      // 类型只给 AF 实际的四类（software / ui / suggestion / other）。
      Row({ space: 6 }) {
        ForEach(ISSUE_TYPES, (item: string): void => {
          this.buildDraftTypeChip($r('app.string.fieldwatch_feedback_type_' + item), item)
        }, (item: string): string => item)
      }.width('100%')
      TextInput({ text: this.draftTitle, placeholder: $r('app.string.fieldwatch_feedback_draft_title') })
        .height(48).width('100%').fontSize(15)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
        .onChange((value: string): void => { this.draftTitle = value; })
      TextArea({ text: this.draftBody, placeholder: $r('app.string.fieldwatch_feedback_draft_body') })
        .height(150).width('100%').fontSize(15)
        .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(14)
        .onChange((value: string): void => { this.draftBody = value; })
      // 现场上下文（电台/频率/位置）已按用户要求去掉：不收集、不显示。
      Text(this.diagnosticText()).fontSize(12).fontColor(FieldwatchPaletteHolder.get().textDim)
      this.buildAttachmentCard()
      if (this.notice.length > 0) Text(this.notice).fontSize(12)
        .fontColor(FieldwatchPaletteHolder.get().warn)
      Button($r('app.string.fieldwatch_feedback_submit_issue')).height(46).width('100%')
        .backgroundColor(FieldwatchPaletteHolder.get().accent)
        .fontColor(FieldwatchPaletteHolder.get().night)
        .enabled(!this.submitting)
        .onClick((): void => { void this.submitDraft(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildDraftTypeChip(label: ResourceStr, value: string) {
    Text(label).fontSize(13).height(34).layoutWeight(1).textAlign(TextAlign.Center)
      .borderRadius(17)
      .backgroundColor(this.draftType === value
        ? FieldwatchPaletteHolder.get().accent : FieldwatchPaletteHolder.get().panel)
      .fontColor(this.draftType === value
        ? FieldwatchPaletteHolder.get().night : FieldwatchPaletteHolder.get().text)
      .onClick((): void => { this.draftType = value; })
  }

  /**
   * 服务端给的是 ISO 串（`2026-10-10T10:48:06.171189Z`）——
   * 直接显示对用户毫无意义，转成本地时间。
   */
  private formatStamp(value: string): string {
    if (value.length === 0) return '';
    const at: number = Date.parse(value);
    if (isNaN(at)) return value;
    const date: Date = new Date(at);
    const hh: string = date.getHours().toString().padStart(2, '0');
    const mm: string = date.getMinutes().toString().padStart(2, '0');
    return (date.getMonth() + 1).toString() + '/' + date.getDate().toString() + ' ' + hh + ':' + mm;
  }

  private formatBytes(value: number): string {
    if (value < 1024) return value.toString() + ' B';
    if (value < 1024 * 1024) return (Math.round(value / 1024)).toString() + ' KB';
    return (Math.round(value / (1024 * 1024) * 10) / 10).toString() + ' MB';
  }

  /** 打开公开附件：交给系统（浏览器 / 对应应用）。 */
  private async openAttachment(item: FeedbackAttachment): Promise<void> {
    if (item.download_url.length === 0) return;
    const context: common.UIAbilityContext | undefined = this.abilityContext();
    if (context === undefined) return;
    try {
      await context.openLink(item.download_url, { appLinkingOnly: false });
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '打开附件失败 code=' + failure.code + ' msg=' + failure.message);
    }
  }

  /** 公开附件列表（已审核通过的）。 */
  @Builder
  private buildPublicAttachments(detail: FeedbackIssueDetail) {
    if (detail.attachments.length > 0) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.paperclip')).fontSize(16)
            .fontColor([FieldwatchPaletteHolder.get().accent])
          Text($r('app.string.fieldwatch_feedback_attachments')).fontSize(15)
            .fontColor(FieldwatchPaletteHolder.get().text)
          Blank()
          Text($r('app.string.fieldwatch_feedback_attachment_note')).fontSize(11)
            .fontColor(FieldwatchPaletteHolder.get().textDim)
        }.width('100%')
        ForEach(detail.attachments, (item: FeedbackAttachment): void => {
          Row({ space: 8 }) {
            Text(item.original_name).fontSize(13).fontColor(FieldwatchPaletteHolder.get().text)
              .layoutWeight(1).maxLines(1)
            Text(this.formatBytes(item.size)).fontSize(11)
              .fontColor(FieldwatchPaletteHolder.get().textDim)
            Text($r('app.string.fieldwatch_feedback_open')).fontSize(12)
              .fontColor(FieldwatchPaletteHolder.get().accent)
              .onClick((): void => { void this.openAttachment(item); })
          }.width('100%').padding(10)
          .backgroundColor(FieldwatchPaletteHolder.get().night).borderRadius(10)
        }, (item: FeedbackAttachment): string => item.id)
      }.width('100%').padding(14)
      .backgroundColor(FieldwatchPaletteHolder.get().panel).borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  private attachmentHint(): string {
    const template: string = this.text('app.string.fieldwatch_feedback_attachment_hint');
    return template.replace('%1', this.formatBytes(MAX_FILE_BYTES))
      .replace('%2', this.formatBytes(MAX_ISSUE_BYTES))
      .replace('%3', this.formatBytes(this.pendingBytes()));
  }

  private attachmentStatus(item: LocalAttachment): string {
    if (item.status === LocalAttachmentStatus.UPLOADING) {
      return this.text('app.string.fieldwatch_feedback_uploading') + ' '
        + this.formatBytes(item.progress) + ' / ' + this.formatBytes(item.size);
    }
    if (item.status === LocalAttachmentStatus.DONE) return this.text('app.string.fieldwatch_feedback_uploaded');
    if (item.status === LocalAttachmentStatus.FAILED) {
      return item.errorMessage.length > 0 ? item.errorMessage : this.text('app.string.fieldwatch_feedback_upload_failed');
    }
    return this.text('app.string.fieldwatch_feedback_pending_upload');
  }

  private diagnosticText(): string {
    const template: string = this.text('app.string.fieldwatch_feedback_diagnostic_note');
    return template.replace('%1', deviceInfo.productModel).replace('%2', deviceInfo.osFullName);
  }
}
