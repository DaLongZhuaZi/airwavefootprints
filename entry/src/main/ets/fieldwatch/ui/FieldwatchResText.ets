import { invalidateNGFTextCache, ngfText, ngfTextCacheSize } from 'ngf_framework';

/**
 * Fieldwatch 的资源文本缓存入口。
 *
 * 实现已下沉到框架层 `ngf_framework/i18n/utils/ResourceTextCache`（`ngfText`）：
 * 领域层（`fieldwatch/domain/**`）也要取本地化文本，让领域层去 import 一个 `ui/` 工具
 * 会把依赖方向拧反。这里保留一层别名，UI 侧继续用 `fieldwatchText` 读起来更直观。
 */
export function fieldwatchText(key: string): string {
  return ngfText(key);
}

/** 语言切换后调用，立即丢弃旧语言的缓存。 */
export function invalidateFieldwatchText(): void {
  invalidateNGFTextCache();
}

/** 已缓存的条目数（诊断用）。 */
export function fieldwatchTextCacheSize(): number {
  return ngfTextCacheSize();
}
