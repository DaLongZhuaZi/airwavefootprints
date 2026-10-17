import { ngfI18nManagerFacade } from '../facades/I18nManagerFacade';
import { resolveResourceString } from './ResourceStringResolver';
import { uiContextManager } from '../../platformOhos/UIContextManager';

/**
 * 资源文本缓存（框架级）。
 *
 * ## 为什么需要它
 *
 * `$r('app.string.x')` 返回的是 `Resource` 对象，ArkUI 在**每次 build** 时都要把它
 * 解析成实际文本。实测（HiProfiler 能量录制，翻页场景）`__getResourceId__` 占到已归因
 * JS CPU 的 40% —— 列表行、雷达点、类别行这些每小时重建上百次的 builder 反复解析同一批键。
 *
 * 把 key 解析成 `string` 缓存起来后，build 里传的是纯字符串，ArkUI 不再走资源解析。
 *
 * ## 失效策略
 *
 * 文本随语言变化，所以缓存带 locale 检查：`text()` 内部按 1 秒节流比对当前 locale，
 * 变了就整体清空。节流是为了避免每次查找都去取系统 locale。
 * 语言切换后也可以调 `invalidate()` 立即生效。
 */
class ResourceTextCache {
  private readonly texts: Map<string, string> = new Map<string, string>();
  private localeTag: string = '';
  private lastLocaleCheckAt: number = 0;

  /**
   * 取 `app.string.xxx` 的本地化文本。
   *
   * 命中缓存零解析；未命中才走一次 `resourceManager.getStringSync`。
   * 解析失败（上下文未就绪 / 键不存在）返回空串且**不写缓存**，避免把空串固化下来。
   */
  text(key: string): string {
    const now: number = Date.now();
    if (now - this.lastLocaleCheckAt > 1000) {
      this.lastLocaleCheckAt = now;
      const current: string = this.safeLocale();
      if (current !== this.localeTag) {
        this.texts.clear();
        this.localeTag = current;
      }
    }
    const cached: string | undefined = this.texts.get(key);
    if (cached !== undefined) return cached;
    const context = uiContextManager.getFullAbilityContext();
    if (context === null) return '';
    const value: string = resolveResourceString(context, $r(key));
    if (value.length > 0) this.texts.set(key, value);
    return value;
  }

  /** 强制清空（语言切换后立刻生效，不必等 1 秒节流）。 */
  invalidate(): void {
    this.texts.clear();
    this.localeTag = '';
    this.lastLocaleCheckAt = 0;
  }

  /** 当前缓存条目数，仅用于诊断日志。 */
  size(): number { return this.texts.size; }

  private safeLocale(): string {
    try {
      return ngfI18nManagerFacade.getCurrentLocale();
    } catch (error) {
      return '';
    }
  }
}

const RESOURCE_TEXT_CACHE: ResourceTextCache = new ResourceTextCache();

/** 取本地化文本（带缓存）。key 形如 `app.string.xxx`。 */
export function ngfText(key: string): string {
  return RESOURCE_TEXT_CACHE.text(key);
}

/** 语言切换后调用，立即丢弃旧语言的缓存。 */
export function invalidateNGFTextCache(): void {
  RESOURCE_TEXT_CACHE.invalidate();
}

/** 已缓存的条目数（诊断用）。 */
export function ngfTextCacheSize(): number {
  return RESOURCE_TEXT_CACHE.size();
}
