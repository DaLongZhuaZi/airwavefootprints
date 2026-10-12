/**
 * 导出文件名的后缀契约（纯领域逻辑，无系统依赖）。
 *
 * **为什么单独成文件**：系统保存选择器默认选中 `fileSuffixChoices` 的**第一项**，
 * 不会按 `newFileNames` 推断类型。API26 真机实测：共享一份固定后缀列表时，
 * 导出 CSV 会被默认存成 `.json`，而 GPX/KML/JSONL 原本根本不在候选里。
 * 把「按文件名重排后缀」做成纯函数，既能用 LocalUnit 锁定全部导出格式，
 * 也避免把这条契约埋在带系统依赖的平台文件里。
 */

/** 保存选择器可用的后缀候选（纯后缀，不是「描述|后缀」筛选串）。 */
export const SAVE_SUFFIX_CHOICES: string[] = ['.csv', '.json', '.jsonl', '.gpx', '.kml', '.txt', '.fieldwatch'];

/** 取文件名的小写扩展名（含点）；无扩展名时返回空串。 */
export function extensionOf(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot <= 0 || dot === fileName.length - 1) return '';
  return fileName.substring(dot).toLowerCase();
}

/**
 * 后缀候选重排：把文件自身扩展名放到首位，其余按给定顺序补齐。
 * 首位即选择器默认值，因此重排后默认后缀一定与文件内容类型一致。
 */
export function orderedSaveSuffixes(fileName: string, suffixChoices: string[] = SAVE_SUFFIX_CHOICES): string[] {
  const own: string = extensionOf(fileName);
  if (own.length === 0) return suffixChoices.slice();
  const ordered: string[] = [own];
  suffixChoices.forEach((item: string): void => {
    if (item.toLowerCase() !== own) ordered.push(item);
  });
  return ordered;
}
