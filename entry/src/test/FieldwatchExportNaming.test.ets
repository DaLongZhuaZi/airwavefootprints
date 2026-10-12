import { describe, expect, it } from '@ohos/hypium';
import { extensionOf, orderedSaveSuffixes, SAVE_SUFFIX_CHOICES } from '../main/ets/fieldwatch/domain/FieldwatchExportNaming';

/** 与 FieldwatchApplication.exportFileName 一致的样例文件名（含五种导出格式）。 */
const STAMP: string = '2026-10-11-17-51-57';

export default function fieldwatchExportNamingTest() {
  describe('fieldwatchExportNamingTest', () => {
    // 真机缺陷回归：保存选择器默认选中 fileSuffixChoices 首项，
    // 原实现共享固定列表导致导出 CSV 默认存成 .json（GPX/KML/JSONL 甚至不在候选里）。
    it('puts the file own extension first for every export format', 0, () => {
      const cases: string[] = [
        'fieldwatch-log-' + STAMP + '.csv',
        'fieldwatch-log-' + STAMP + '.jsonl',
        'fieldwatch-log-' + STAMP + '.gpx',
        'fieldwatch-log-' + STAMP + '.kml',
        'fieldwatch-wigle-' + STAMP + '.csv',
        'fieldwatch-signatures.json',
        'fieldwatch-settings-' + STAMP + '.fieldwatch'
      ];
      cases.forEach((fileName: string): void => {
        const ordered: string[] = orderedSaveSuffixes(fileName, SAVE_SUFFIX_CHOICES);
        expect(ordered[0]).assertEqual(extensionOf(fileName));
      });
    });

    it('keeps every candidate exactly once and never drops formats', 0, () => {
      const ordered: string[] = orderedSaveSuffixes('fieldwatch-log-' + STAMP + '.gpx', SAVE_SUFFIX_CHOICES);
      expect(ordered.length).assertEqual(SAVE_SUFFIX_CHOICES.length);
      const seen: Set<string> = new Set<string>();
      ordered.forEach((item: string): void => { seen.add(item); });
      expect(seen.size).assertEqual(SAVE_SUFFIX_CHOICES.length);
      // GPX/KML/JSONL 必须在候选内，否则选择器会强制改成别的后缀。
      expect(ordered.indexOf('.gpx') >= 0).assertTrue();
      expect(ordered.indexOf('.kml') >= 0).assertTrue();
      expect(ordered.indexOf('.jsonl') >= 0).assertTrue();
    });

    it('matches extensions case-insensitively without duplicating them', 0, () => {
      const ordered: string[] = orderedSaveSuffixes('EXPORT.CSV', SAVE_SUFFIX_CHOICES);
      expect(ordered[0]).assertEqual('.csv');
      expect(ordered.filter((item: string): boolean => item === '.csv').length).assertEqual(1);
    });

    it('leaves the candidate list untouched when the name has no extension', 0, () => {
      const ordered: string[] = orderedSaveSuffixes('fieldwatch-log-noext', SAVE_SUFFIX_CHOICES);
      expect(ordered.length).assertEqual(SAVE_SUFFIX_CHOICES.length);
      expect(ordered[0]).assertEqual(SAVE_SUFFIX_CHOICES[0]);
      // 返回副本，调用方改动不得污染共享常量。
      ordered.push('.tmp');
      expect(SAVE_SUFFIX_CHOICES.indexOf('.tmp')).assertEqual(-1);
    });

    it('treats dot-files and trailing dots as having no extension', 0, () => {
      expect(extensionOf('.hidden')).assertEqual('');
      expect(extensionOf('trailing.')).assertEqual('');
      expect(extensionOf('plain')).assertEqual('');
      expect(extensionOf('a.b.CSV')).assertEqual('.csv');
      // 设置备份只允许一个候选：重排后仍是它本身。
      const backup: string[] = orderedSaveSuffixes('backup.fieldwatch', ['.fieldwatch']);
      expect(backup.length).assertEqual(1);
      expect(backup[0]).assertEqual('.fieldwatch');
    });
  });
}
