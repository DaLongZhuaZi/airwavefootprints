import { ngfText } from 'ngf_framework';
/**
 * 更新日志（应用内「关于 → 更新日志」sheet 的数据源）。
 *
 * **为什么是一份手写的静态清单，而不是读 git log：**
 * 1. 面向用户的说服力在「这一个版本改变了什么」，不在提交粒度 ——
 *    把 30 条内部提交压成 3 条用户能读懂的话，只能由人来写；
 * 2. git log 在装机上根本不存在（源码不随包分发）；
 * 3. 落盘成代码里的常量后，它和版本号一样**跟着构建走**，不会出现
 *    「目录文件还没下载，日志先显示不出来」的中间态。
 *
 * **维护约定（每次发布必须执行，见 .rules/skill-app-release.md 的版本号小节）：**
 * - 版本号变化（`versionName` 或 `versionCode` 递增）时，在 CHANGELOG_HEAD
 *   之前**新增一条** `ChangelogEntry`，把旧条目整体下移，不合并、不改写历史；
 * - 每条只写「用户视角的变化」：新能力 / 修复 / 行为变化，各配一条；
 * - 手动补充（版本号没变，但当天合入了要告知用户的修复）时同样加在最前，
 *   `versionLabel` 保持当前版本号即可 —— 阅读者要的是顺序，不是严格发布史。
 */

/** 一条更新记录。 */
export class ChangelogEntry {
  /** 版本标签，对应 `AppScope/app.json5` 的 `versionName`（手动补录时可相同）。 */
  public readonly versionLabel: string;
  /** 构建号，对应 `versionCode`；手动补录时填 0。 */
  public readonly buildNumber: number;
  /** 日期（`YYYY-MM-DD`），取发布日或补录日。 */
  public readonly date: string;
  /** 用户视角的变化，一条一句，不需要句号。 */
  public readonly items: string[];

  constructor(versionLabel: string, buildNumber: number, date: string, items: string[]) {
    this.versionLabel = versionLabel;
    this.buildNumber = buildNumber;
    this.date = date;
    this.items = items;
  }
}

/** 当前构建号：与 `AppScope/app.json5` 的 `versionCode` 保持一致（发布时同步改）。 */
export const CHANGELOG_CURRENT_BUILD: number = 1010101;

/**
 * 更新日志，**最新在最前**。
 *
 * 首个条目对应 `versionName 1.0.0 / versionCode 1000002`（首次上架基线）。
 * 后续版本在数组头部插入新条目，旧条目原样下移。
 */
export const CHANGELOG_HEAD: ChangelogEntry[] = [
  new ChangelogEntry('1.1.1', 1010101, '2026-10-28', [
    ngfText('app.string.fw_cl_111_1'),
    ngfText('app.string.fw_cl_111_2'),
    ngfText('app.string.fw_cl_111_3'),
    ngfText('app.string.fw_cl_111_4'),
    ngfText('app.string.fw_cl_111_5'),
    ngfText('app.string.fw_cl_111_6'),
    ngfText('app.string.fw_cl_111_7'),
    ngfText('app.string.fw_cl_111_8'),
    ngfText('app.string.fw_cl_111_9')
  ]),
  // 手动补录（版本号未变）：当天合入、要告知用户的修复。buildNumber 记 0。
  new ChangelogEntry('1.1.0', 0, '2026-10-21', [
    ngfText('app.string.fw_cl_fix_1'),
    ngfText('app.string.fw_cl_fix_2')
  ]),
  new ChangelogEntry('1.1.0', 1010000, '2026-10-18', [
    ngfText('app.string.fw_cl_110_1'),
    ngfText('app.string.fw_cl_110_2'),
    ngfText('app.string.fw_cl_110_3'),
    ngfText('app.string.fw_cl_110_4'),
    ngfText('app.string.fw_cl_110_5')
  ]),
  new ChangelogEntry('1.0.0', 1000003, '2026-10-12', [
    ngfText('app.string.fw_cl_49'),
    ngfText('app.string.fw_cl_50'),
    ngfText('app.string.fw_cl_51'),
    ngfText('app.string.fw_cl_52')
  ])
];
