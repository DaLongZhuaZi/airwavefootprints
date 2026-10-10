/**
 * 电波足迹的深度链接（Deep Link）。
 *
 * 与 `module.json5` 里 `EntryAbility.skills` 的 `uris` **必须一致**：
 * 那份声明决定系统把哪些 URI 交给我们，这里决定怎么解释它。
 * 两处不一致的表现是「点了链接应用被拉起来，但什么也没发生」——
 * 系统放行了，我们却认不出来。
 *
 * 纯逻辑 + 一个单例桥，不依赖任何页面：
 * EntryAbility 在 `onCreate` / `onNewWant` 里只做「识别 + 转交」，
 * 导航交给页面（页面才知道自己现在在哪、该往哪压栈）。
 */

import { logger } from 'ngf_framework';

const TAG: string = 'FieldwatchDeepLink';

/** 与 `module.json5` 的 `skills.uris[].scheme` 一致。 */
export const FIELDWATCH_SCHEME: string = 'airwavefootprints';

export enum FieldwatchDeepLinkKind {
  /** 不是本应用的链接。 */
  NONE = 'none',
  /** 只是把应用拉起来。 */
  OPEN = 'open',
  /** 打开反馈中心；可带 issue 号直达某一条。 */
  FEEDBACK = 'feedback',
  /** Cloudflare Turnstile 在系统浏览器里完成后的回传。 */
  TURNSTILE = 'turnstile'
}

export class FieldwatchDeepLink {
  public kind: FieldwatchDeepLinkKind = FieldwatchDeepLinkKind.NONE;
  public raw: string = '';
  /** 仅 TURNSTILE：验证令牌。 */
  public token: string = '';
  /** 仅 FEEDBACK：要直达的 issue 号；0 表示只打开列表。 */
  public issueNumber: number = 0;
  /** 仅 FEEDBACK：`feedback/new` 直达「新建」表单。 */
  public createMode: boolean = false;
}

export function isFieldwatchUri(uri: string): boolean {
  return uri.length > 0 && uri.startsWith(FIELDWATCH_SCHEME + '://');
}

/**
 * 解析 URI。**任何异常都退回 `NONE`**，绝不抛错 ——
 * 深链是外部输入，来源不可控（浏览器、第三方应用、手输），
 * 解析失败只应表现为「什么都没发生」，而不是崩掉。
 */
export function parseFieldwatchUri(uri: string): FieldwatchDeepLink {
  const link: FieldwatchDeepLink = new FieldwatchDeepLink();
  link.raw = uri;
  if (!isFieldwatchUri(uri)) return link;
  try {
    const after: string = uri.substring(FIELDWATCH_SCHEME.length + 3);
    const queryAt: number = after.indexOf('?');
    const pathPart: string = queryAt === -1 ? after : after.substring(0, queryAt);
    const queryPart: string = queryAt === -1 ? '' : after.substring(queryAt + 1);
    const segments: string[] = pathPart.split('/');
    const host: string = segments.length > 0 ? segments[0].toLowerCase() : '';
    if (host === 'open') {
      link.kind = FieldwatchDeepLinkKind.OPEN;
    } else if (host === 'feedback') {
      link.kind = FieldwatchDeepLinkKind.FEEDBACK;
      // `airwavefootprints://feedback/123` 直达第 123 条。
      if (segments.length > 1) {
        // `feedback/new` 直达新建表单；其余按 issue 号解析。
        if (segments[1].toLowerCase() === 'new') {
          link.createMode = true;
        } else {
          const parsed: number = parseInt(segments[1], 10);
          link.issueNumber = isNaN(parsed) ? 0 : parsed;
        }
      }
    } else if (host === 'turnstile') {
      link.kind = FieldwatchDeepLinkKind.TURNSTILE;
      link.token = readQueryValue(queryPart, 'token');
    }
  } catch (error) {
    logger.warn(TAG, '解析深链失败: ' + String(error));
    return new FieldwatchDeepLink();
  }
  return link;
}

/** 从 `a=1&b=2` 里取一个值；取不到返回空串。 */
function readQueryValue(query: string, key: string): string {
  if (query.length === 0) return '';
  const parts: string[] = query.split('&');
  for (let i: number = 0; i < parts.length; i += 1) {
    const at: number = parts[i].indexOf('=');
    if (at <= 0) continue;
    if (parts[i].substring(0, at) !== key) continue;
    const raw: string = parts[i].substring(at + 1);
    try {
      return decodeURIComponent(raw);
    } catch (error) {
      // 编码坏了也把原文交出去：总比丢掉整条回传好。
      return raw;
    }
  }
  return '';
}

/** Turnstile 令牌的最短长度；太短的一律当无效，避免把垃圾塞给服务端。 */
const MIN_TOKEN_LENGTH: number = 20;

/**
 * 深链桥：把 EntryAbility 收到的链接转交给页面。
 *
 * **为什么需要「待处理」这一层**：
 * 冷启动时 `onCreate` 先跑、页面还没创建，此刻无法导航；
 * 热启动时页面已存在，可以直接导航。
 * 两种情况用一个「先存下、页面就绪后取走」的中间态统一处理，
 * 与 `requestTab` / `consumePendingTab` 是同一个模式。
 */
export class FieldwatchDeepLinkBridge {
  private static instance: FieldwatchDeepLinkBridge | null = null;
  private pending: FieldwatchDeepLink | undefined = undefined;
  private tokenResolver: ((token: string) => void) | null = null;
  private tokenTimer: number = -1;

  private constructor() {}

  static getInstance(): FieldwatchDeepLinkBridge {
    if (FieldwatchDeepLinkBridge.instance === null) {
      FieldwatchDeepLinkBridge.instance = new FieldwatchDeepLinkBridge();
    }
    return FieldwatchDeepLinkBridge.instance;
  }

  /** EntryAbility 收到深链后调用。TURNSTILE 直接结算等待者，其余存为待处理。 */
  accept(uri: string): void {
    const link: FieldwatchDeepLink = parseFieldwatchUri(uri);
    if (link.kind === FieldwatchDeepLinkKind.NONE) return;
    logger.info(TAG, '收到深链: kind=' + link.kind + ' raw=' + uri);
    if (link.kind === FieldwatchDeepLinkKind.TURNSTILE) {
      this.settleToken(link.token);
      return;
    }
    this.pending = link;
  }

  /** 页面就绪后取走待处理深链；取走后清空（只生效一次）。 */
  consumePending(): FieldwatchDeepLink | undefined {
    const link: FieldwatchDeepLink | undefined = this.pending;
    this.pending = undefined;
    return link;
  }

  /**
   * 等待系统浏览器回传的 Turnstile 令牌。
   *
   * 超时或失败一律以**空串**结束等待，调用方据此走「验证失败」分支；
   * 抛错会让反馈页卡在一个永远不 resolve 的 Promise 上。
   */
  waitForTurnstileToken(timeoutMilliseconds: number): Promise<string> {
    this.settleToken('');
    return new Promise<string>((resolve: (value: string) => void) => {
      this.tokenResolver = resolve;
      this.tokenTimer = setTimeout((): void => {
        if (this.tokenResolver === resolve) {
          this.tokenResolver = null;
          this.tokenTimer = -1;
          resolve('');
          logger.warn(TAG, 'Turnstile 等待超时');
        }
      }, timeoutMilliseconds);
    });
  }

  private settleToken(token: string): void {
    const resolver: ((token: string) => void) | null = this.tokenResolver;
    if (resolver === null) return;
    if (this.tokenTimer >= 0) { clearTimeout(this.tokenTimer); this.tokenTimer = -1; }
    this.tokenResolver = null;
    // 长度不足的令牌一律按空处理，别把明显无效的东西送去服务端。
    resolver(token.length >= MIN_TOKEN_LENGTH ? token : '');
  }
}

export const fieldwatchDeepLinkBridge: FieldwatchDeepLinkBridge = FieldwatchDeepLinkBridge.getInstance();
