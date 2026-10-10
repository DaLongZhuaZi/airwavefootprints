/**
 * 电波足迹反馈中心的 API 客户端。
 *
 * **端点与服务端路径都按 AF 自己的空间来**：
 * 基础地址 `https://feedback.manxia.top`，路径一律带 `/api/v1/apps/af` 前缀。
 *
 * **裸的 `/api/v1/issues` 是漫匣的空间，绝不能用** ——
 * 用了就会把漫匣的条目显示给电波足迹的用户（第一版就是这么错的，
 * 列表里出现的全是漫匣的反馈）。用户看不出两个 App 共用一个后端，
 * 只有管理员知道；这一层隔离**只由路径前缀保证**。
 *
 * 另两条硬约束：
 *  ① 只走公开接口，管理员接口不进客户端；
 *  ② 编号一律用 AF 路由下的 `issue_number` 展示与寻址，不与漫匣混。
 *
 * 与漫匣的差异（**照抄漫匣的字段会 422**）：
 *  `context` 只许 `station_name` / `frequency` / `location` 三个键；
 *  `issue_type` 只许 `software` / `ui` / `suggestion` / `other`；
 *  `supports` 只收 `device_id`（**不带** turnstile_token）。
 *
 * 设计约束（本仓库四条不变量之一）：应用是「严格离线」的，
 * 所以每一次请求都**必须由用户显式触发**，没有轮询、预取或自动重试。
 */

import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchFeedback';

/** 反馈中心基础地址。 */
export const FEEDBACK_ORIGIN: string = 'https://feedback.manxia.top';

/** AF 的空间前缀。**所有业务路径都必须经过它**。 */
export const AF_API_PREFIX: string = '/api/v1/apps/af';

/** Turnstile 挑战页；完成后跳 `airwavefootprints://turnstile?token=…`。 */
export const TURNSTILE_SHELL_URL: string = FEEDBACK_ORIGIN + '/turnstile-shell?app=af';

/** 单文件上限 80 MiB；单条反馈附件总量上限 160 MiB。 */
export const MAX_FILE_BYTES: number = 80 * 1024 * 1024;
export const MAX_ISSUE_BYTES: number = 160 * 1024 * 1024;

export type FeedbackIssueType = 'software' | 'ui' | 'suggestion' | 'other';
export type FeedbackUploadCategory = 'text' | 'image' | 'video' | 'archive';

/** 请求结果：区分「成功」与「失败原因」，UI 才能给对提示。 */
export enum FeedbackOutcome {
  OK = 'ok',
  /** 429：按 IP 限流。 */
  RATE_LIMITED = 'rate_limited',
  /** 409：分块偏移不连续。 */
  CHUNK_MISMATCH = 'chunk_mismatch',
  /** 404：AF 空间里没有这个编号，或上传会话已过期。 */
  NOT_FOUND = 'not_found',
  /** 422：字段不合法（类型 / context / 长度）。 */
  INVALID = 'invalid',
  /** 其它失败：网络不通、超时、5xx。 */
  FAILED = 'failed'
}

export class FeedbackDiagnostic {
  public model: string = '';
  public system_version: string = '';
  public app_version: string = '';
  public build_number: number = 0;
  public device_type: string = '';
}

/** **只有这三个键**：多传漫匣的字段会 422。 */
export class FeedbackContext {
  public station_name: string = '';
  public frequency: string = '';
  public location: string = '';
}

export class FeedbackAttachment {
  public id: string = '';
  public original_name: string = '';
  public category: string = '';
  public media_type: string = '';
  public size: number = 0;
  public download_url: string = '';
}

export class FeedbackIssueSummary {
  public id: string = '';
  public issue_number: number = 0;
  public title: string = '';
  public issue_type: string = '';
  public status: string = '';
  public priority: string = '';
  public labels: string[] = [];
  public support_count: number = 0;
  public post_count: number = 0;
  public attachment_count: number = 0;
  public created_at: string = '';
  public updated_at: string = '';
}

export class FeedbackIssuePost {
  public id: string = '';
  public author_kind: string = '';
  public body: string = '';
  public created_at: string = '';
}

export class FeedbackIssueDetail extends FeedbackIssueSummary {
  public description: string = '';
  public diagnostic: FeedbackDiagnostic = new FeedbackDiagnostic();
  public context: FeedbackContext = new FeedbackContext();
  public posts: FeedbackIssuePost[] = [];
  public attachments: FeedbackAttachment[] = [];
  /** 仅带 `device_id` 查询时有意义：本机是否已点过支持。 */
  public supported_by_device: boolean = false;
}

export class FeedbackIssuePage {
  public items: FeedbackIssueSummary[] = [];
  public page: number = 1;
  public page_size: number = 20;
  public total: number = 0;
}

export class FeedbackCreateIssue {
  public title: string = '';
  public description: string = '';
  public issue_type: FeedbackIssueType = 'other';
  public diagnostic: FeedbackDiagnostic = new FeedbackDiagnostic();
  public context: FeedbackContext = new FeedbackContext();
  public turnstile_token: string = '';
}

export class FeedbackSupportResult {
  public issue_number: number = 0;
  public support_count: number = 0;
  public already_supported: boolean = false;
}

export class FeedbackUploadSession {
  public upload_id: string = '';
  public issue_number: number = 0;
  public chunk_size: number = UPLOAD_CHUNK_SIZE;
  /** 会话声明的总字节数。 */
  public requested_size: number = 0;
  /** 服务端**已收到**的字节数；上传从这里继续（断点续传）。 */
  public received_size: number = 0;
  public expires_at: string = '';
}

export class FeedbackFileHash {
  public size: number = 0;
  public sha256: string = '';
}

/** 分块上传的返回；`received_size` 是服务端已收到的字节数，**以它推进偏移**。 */
export class FeedbackUploadChunkResult {
  public upload_id: string = '';
  public received_size: number = 0;
  public requested_size: number = 0;
  public complete: boolean = false;
}

export class FeedbackUploadProgress {
  public completed: number = 0;
  public total: number = 0;
}

/** 用户主动取消上传；与真实错误区分开，UI 提示完全不同。 */
export class FeedbackUploadCancelledError extends Error {
  public constructor() { super('上传已取消'); }
}

/** 分块大小 4 MiB（服务端 `chunk_size` 也是它）。 */
export const UPLOAD_CHUNK_SIZE: number = 4 * 1024 * 1024;
/** 单块失败重试次数（网络抖动很常见，重试比让用户重传整个文件划算）。 */
export const UPLOAD_CHUNK_RETRY_COUNT: number = 2;

/** 一次请求的结果：状态 + 正文。 */
export class FeedbackResponse {
  public outcome: FeedbackOutcome = FeedbackOutcome.FAILED;
  public status: number = 0;
  public body: string = '';
  public ok(): boolean { return this.outcome === FeedbackOutcome.OK; }
}

export class FieldwatchFeedbackService {
  private static instance: FieldwatchFeedbackService | null = null;
  private deviceId: string = '';

  private constructor() {}

  static getInstance(): FieldwatchFeedbackService {
    if (FieldwatchFeedbackService.instance === null) {
      FieldwatchFeedbackService.instance = new FieldwatchFeedbackService();
    }
    return FieldwatchFeedbackService.instance;
  }

  /** 稳定的匿名设备 ID：服务端用它去重「同一设备对同一条的重复支持」。 */
  setDeviceId(value: string): void { this.deviceId = value; }
  getDeviceId(): string { return this.deviceId; }

  /** 可用性探测。**用户主动点「检查服务」时才调**。 */
  async healthz(): Promise<boolean> {
    const response: FeedbackResponse = await this.request('/healthz', http.RequestMethod.GET, '', 6000);
    return response.ok();
  }

  async listIssues(page: number, pageSize: number, search: string,
    issueType: string, status: string): Promise<FeedbackResponse> {
    const query: string[] = ['page=' + page.toString(), 'page_size=' + pageSize.toString()];
    // 空参数也要带上：服务端按「存在但为空」处理，省略反而可能走另一条分支。
    query.push('search=' + encodeURIComponent(search));
    query.push('issue_type=' + encodeURIComponent(issueType));
    query.push('status=' + encodeURIComponent(status));
    return this.request(AF_API_PREFIX + '/issues?' + query.join('&'), http.RequestMethod.GET, '');
  }

  /** 详情；带 `device_id` 才会返回 `supported_by_device`。 */
  async getIssue(issueNumber: number): Promise<FeedbackResponse> {
    const query: string = this.deviceId.length > 0
      ? '?device_id=' + encodeURIComponent(this.deviceId) : '';
    return this.request(AF_API_PREFIX + '/issues/' + issueNumber.toString() + query,
      http.RequestMethod.GET, '');
  }

  /** 创建反馈；201 返回详情（含分配到的 **AF 编号**）。 */
  async createIssue(payload: FeedbackCreateIssue): Promise<FeedbackResponse> {
    return this.request(AF_API_PREFIX + '/issues', http.RequestMethod.POST, JSON.stringify(payload));
  }

  /** 「我也遇到了」。**只带 device_id**，不带 turnstile_token。 */
  async supportIssue(issueNumber: number): Promise<FeedbackResponse> {
    const body: string = JSON.stringify({ device_id: this.deviceId });
    return this.request(AF_API_PREFIX + '/issues/' + issueNumber.toString() + '/supports',
      http.RequestMethod.POST, body);
  }

  /** 给已有反馈追加补充。 */
  async createPost(issueNumber: number, body: string, token: string): Promise<FeedbackResponse> {
    const payload: string = JSON.stringify({ body: body, turnstile_token: token });
    return this.request(AF_API_PREFIX + '/issues/' + issueNumber.toString() + '/posts',
      http.RequestMethod.POST, payload);
  }

  /** 开一个上传会话；返回 upload_id 与 chunk_size（4 MiB）。 */
  async createUploadSession(issueNumber: number, originalName: string, size: number,
    sha256: string, mediaType: string, category: FeedbackUploadCategory,
    token: string, postId: string): Promise<FeedbackResponse> {
    const payload: Record<string, string | number> = {
      'original_name': originalName,
      'size': size,
      'sha256': sha256,
      'media_type': mediaType,
      'category': category,
      'turnstile_token': token
    };
    if (postId.length > 0) payload['post_id'] = postId;
    return this.request(AF_API_PREFIX + '/issues/' + issueNumber.toString() + '/upload-sessions',
      http.RequestMethod.POST, JSON.stringify(payload));
  }

  /**
   * 上传一块。**严格顺序、偏移连续**；错位返回 409。
   *
   * 优先 PATCH；鸿蒙 NetStack 发不出 PATCH 时用等价的 POST 入口，
   * 头和 body 完全相同（服务端两个入口行为一致）。
   */
  async uploadChunk(uploadId: string, offset: number, bytes: ArrayBuffer): Promise<FeedbackResponse> {
    const path: string = '/api/v1/uploads/' + uploadId;
    const headers: Record<string, string> = {
      'Content-Type': 'application/octet-stream',
      'X-Chunk-Offset': offset.toString()
    };
    const viaPatch: FeedbackResponse = await this.requestRaw(path, http.RequestMethod.PATCH, bytes, headers);
    // 405 / 网络层不支持 PATCH —— 换等价入口重试一次。
    if (viaPatch.status === 405 || viaPatch.status === 0) {
      return this.requestRaw(path + '/chunks', http.RequestMethod.POST, bytes, headers);
    }
    return viaPatch;
  }

  /** 收尾：服务端校验 SHA-256 后生成附件（默认待管理员审核）。 */
  async completeUpload(uploadId: string): Promise<FeedbackResponse> {
    return this.request('/api/v1/uploads/' + uploadId + '/complete', http.RequestMethod.POST, '{}');
  }

  /**
   * 流式计算文件 SHA-256。
   *
   * **必须流式**：附件上限 80 MiB，一次性读进内存会直接把应用拖垮。
   * 分块大小与上传一致，读一遍就能同时喂给哈希。
   */
  async calculateFileSha256(localPath: string): Promise<FeedbackFileHash> {
    const hash: FeedbackFileHash = new FeedbackFileHash();
    const source: fileIo.File = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = await fileIo.stat(source.fd);
      const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      let offset: number = 0;
      while (offset < stat.size) {
        const remaining: number = stat.size - offset;
        const readSize: number = remaining > UPLOAD_CHUNK_SIZE ? UPLOAD_CHUNK_SIZE : remaining;
        const buffer: ArrayBuffer = new ArrayBuffer(readSize);
        const readBytes: number = await fileIo.read(source.fd, buffer, { length: readSize });
        if (readBytes !== readSize) {
          throw new Error('读取附件失败: expected=' + readSize.toString() + ' actual=' + readBytes.toString());
        }
        await md.update({ data: new Uint8Array(buffer) });
        offset += readBytes;
      }
      const digest: cryptoFramework.DataBlob = await md.digest();
      hash.size = stat.size;
      hash.sha256 = this.bytesToHex(digest.data);
      return hash;
    } finally {
      await fileIo.close(source);
    }
  }

  /**
   * 分块上传一个文件。
   *
   * 三个要点（都是漫匣踩过的）：
   *  ① **从 `received_size` 开始**：会话可能已经收过一部分，重传整份是浪费；
   *  ② **以服务端返回的 `received_size` 推进偏移**，不自己加——
   *     服务端才知道它真正落了盘多少；返回没推进就报错，否则会死循环；
   *  ③ 每块失败重试 2 次、退避 350ms×n。
   */
  async uploadFile(localPath: string, session: FeedbackUploadSession,
    onProgress: (progress: FeedbackUploadProgress) => void,
    shouldCancel: () => boolean): Promise<FeedbackResponse> {
    const source: fileIo.File = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = await fileIo.stat(source.fd);
      if (stat.size !== session.requested_size) {
        throw new Error('本地文件大小在上传前发生变化');
      }
      let offset: number = session.received_size;
      if (offset < 0 || offset > session.requested_size) throw new Error('上传会话偏移无效');
      if (shouldCancel()) throw new FeedbackUploadCancelledError();
      fileIo.lseek(source.fd, offset, fileIo.WhenceType.SEEK_SET);
      while (offset < session.requested_size) {
        if (shouldCancel()) throw new FeedbackUploadCancelledError();
        const remaining: number = session.requested_size - offset;
        const readSize: number = remaining > UPLOAD_CHUNK_SIZE ? UPLOAD_CHUNK_SIZE : remaining;
        const buffer: ArrayBuffer = new ArrayBuffer(readSize);
        const readBytes: number = await fileIo.read(source.fd, buffer, { length: readSize });
        if (readBytes !== readSize) {
          throw new Error('读取附件失败: expected=' + readSize.toString() + ' actual=' + readBytes.toString());
        }
        const result: FeedbackUploadChunkResult | undefined = await this.uploadChunkWithRetry(
          session.upload_id, offset, buffer, shouldCancel);
        if (result === undefined) throw new Error('分块上传失败');
        if (result.received_size <= offset && !result.complete) throw new Error('服务器未推进上传偏移');
        offset = result.received_size;
        const progress: FeedbackUploadProgress = new FeedbackUploadProgress();
        progress.completed = offset;
        progress.total = session.requested_size;
        onProgress(progress);
      }
      if (shouldCancel()) throw new FeedbackUploadCancelledError();
      return await this.completeUpload(session.upload_id);
    } finally {
      await fileIo.close(source);
    }
  }

  private async uploadChunkWithRetry(uploadId: string, offset: number, buffer: ArrayBuffer,
    shouldCancel: () => boolean): Promise<FeedbackUploadChunkResult | undefined> {
    let attempt: number = 0;
    while (true) {
      if (shouldCancel()) throw new FeedbackUploadCancelledError();
      const response: FeedbackResponse = await this.uploadChunk(uploadId, offset, buffer);
      if (response.ok()) {
        try {
          return JSON.parse(response.body) as FeedbackUploadChunkResult;
        } catch (error) {
          return undefined;
        }
      }
      // 409 = 偏移错位：重试没有意义，必须让用户重开会话。
      if (response.outcome === FeedbackOutcome.CHUNK_MISMATCH) return undefined;
      if (attempt >= UPLOAD_CHUNK_RETRY_COUNT) return undefined;
      attempt += 1;
      await this.delay(350 * attempt);
    }
  }

  private async delay(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, milliseconds);
    });
  }

  private bytesToHex(bytes: Uint8Array): string {
    let hex: string = '';
    for (let i: number = 0; i < bytes.length; i += 1) {
      const part: string = bytes[i].toString(16);
      hex += part.length === 1 ? '0' + part : part;
    }
    return hex;
  }

  private jsonHeaders(): Record<string, string> {
    return { 'Content-Type': 'application/json', 'Accept': 'application/json' };
  }

  /**
   * 发一次请求。
   *
   * **GET 失败会自动重试一次**：实测冷启动后的第一次请求偶发失败
   * （两次装机后首屏都撞上），而只读接口重试一次没有任何副作用。
   * 写接口**绝不自动重试** —— 创建/支持/补充重复提交的代价远大于让用户手动重试。
   */
  private async request(path: string, method: http.RequestMethod, body: string,
    timeoutMs: number = 20000): Promise<FeedbackResponse> {
    const first: FeedbackResponse = await this.requestOnce(path, method, body, timeoutMs);
    if (first.ok() || method !== http.RequestMethod.GET) return first;
    await this.delay(600);
    return this.requestOnce(path, method, body, timeoutMs);
  }

  private async requestOnce(path: string, method: http.RequestMethod, body: string,
    timeoutMs: number): Promise<FeedbackResponse> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(FEEDBACK_ORIGIN + path, {
        method: method,
        header: this.jsonHeaders(),
        extraData: body.length > 0 ? body : undefined,
        connectTimeout: 10000,
        readTimeout: timeoutMs
      });
      return this.toResponse(response);
    } catch (error) {
      // 打印 code/message：`String(error)` 只会得到 `[object Object]`，
      // 拿到它等于没有信息（第一版就是这样，只能靠猜）。
      const failure: BusinessError = error as BusinessError;
      logger.warn(TAG, '请求异常 ' + path + ' code=' + failure.code + ' msg=' + failure.message);
      return new FeedbackResponse();
    } finally {
      request.destroy();
    }
  }

  private async requestRaw(path: string, method: http.RequestMethod, bytes: ArrayBuffer,
    headers: Record<string, string>): Promise<FeedbackResponse> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(FEEDBACK_ORIGIN + path, {
        method: method,
        header: headers,
        extraData: bytes,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      return this.toResponse(response);
    } catch (error) {
      logger.warn(TAG, '分块上传异常 ' + path + ': ' + String(error));
      return new FeedbackResponse();
    } finally {
      request.destroy();
    }
  }

  /**
   * 把 HTTP 状态收敛成 `FeedbackOutcome`。
   *
   * 这层映射是**必须的**：限流要提示「稍后再试」、偏移错位要重开会话、
   * 422 要指出字段问题 —— 全都当成「失败了」用户就无从下手。
   */
  private toResponse(response: http.HttpResponse): FeedbackResponse {
    const result: FeedbackResponse = new FeedbackResponse();
    result.status = response.responseCode;
    result.body = typeof response.result === 'string' ? response.result : '';
    if (result.status >= 200 && result.status < 300) result.outcome = FeedbackOutcome.OK;
    else if (result.status === 429) result.outcome = FeedbackOutcome.RATE_LIMITED;
    else if (result.status === 409) result.outcome = FeedbackOutcome.CHUNK_MISMATCH;
    else if (result.status === 404) result.outcome = FeedbackOutcome.NOT_FOUND;
    else if (result.status === 422) result.outcome = FeedbackOutcome.INVALID;
    else result.outcome = FeedbackOutcome.FAILED;
    if (result.outcome !== FeedbackOutcome.OK) {
      logger.warn(TAG, '请求失败 status=' + result.status.toString() + ' outcome=' + result.outcome);
    }
    return result;
  }
}

export const fieldwatchFeedbackService: FieldwatchFeedbackService = FieldwatchFeedbackService.getInstance();
