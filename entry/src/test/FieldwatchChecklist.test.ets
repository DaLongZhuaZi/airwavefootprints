import { describe, it, expect } from '@ohos/hypium';
import {
  allCheckIds, checkProgress, decodeChecks, encodeChecks, manualCheckGroups, ManualCheckGroup,
  ManualCheckItem, toggleCheck
} from '../main/ets/fieldwatch/domain/FieldwatchSecurityChecklist';

export default function fieldwatchChecklistTest() {
  describe('FieldwatchSecurityChecklist', () => {
    // 清单必须覆盖文档 3.3 点名的四类手法：镜头反光 / 异常安装点 / 断电发热 / 夜视红外。
    it('covers the four physical inspection angles', 0, () => {
      const groups: ManualCheckGroup[] = manualCheckGroups();
      expect(groups.length >= 3).assertTrue();
      const ids: string[] = allCheckIds();
      // 镜头反光。
      expect(ids.indexOf('lens_reflect') >= 0).assertTrue();
      expect(ids.indexOf('lens_dark') >= 0).assertTrue();
      // 异常安装点。
      expect(ids.indexOf('lens_smoke') >= 0).assertTrue();
      expect(ids.indexOf('lens_socket') >= 0).assertTrue();
      expect(ids.indexOf('lens_mirror') >= 0).assertTrue();
      // 断电发热 / 夜视红外。
      expect(ids.indexOf('power_heat') >= 0).assertTrue();
      expect(ids.indexOf('power_ir') >= 0).assertTrue();
    });

    // 每一组都要有标题键，每一条都要有文案键（否则 UI 会渲染空行）。
    it('gives every group and item a resource key', 0, () => {
      manualCheckGroups().forEach((group: ManualCheckGroup): void => {
        expect(group.id.length > 0).assertTrue();
        expect(group.titleKey.length > 0).assertTrue();
        expect(group.items.length > 0).assertTrue();
        group.items.forEach((item: ManualCheckItem): void => {
          expect(item.id.length > 0).assertTrue();
          expect(item.labelKey.indexOf('app.string.') === 0).assertTrue();
        });
      });
    });

    // 条目 id 不能重复（否则打勾会串）。
    it('has unique item ids', 0, () => {
      const ids: string[] = allCheckIds();
      const unique: string[] = [];
      ids.forEach((id: string): void => { if (unique.indexOf(id) < 0) unique.push(id); });
      expect(unique.length).assertEqual(ids.length);
    });

    it('toggles items on and off', 0, () => {
      expect(toggleCheck([], 'lens_dark').length).assertEqual(1);
      expect(toggleCheck(['lens_dark'], 'lens_dark').length).assertEqual(0);
      const two: string[] = toggleCheck(['lens_dark'], 'power_heat');
      expect(two.length).assertEqual(2);
      expect(two.indexOf('power_heat') >= 0).assertTrue();
    });

    // 切换不能改入参（UI 靠返回的新数组判断是否需要落盘）。
    it('does not mutate the input array', 0, () => {
      const original: string[] = ['lens_dark'];
      const next: string[] = toggleCheck(original, 'power_heat');
      expect(original.length).assertEqual(1);
      expect(next.length).assertEqual(2);
    });

    it('reports progress as done over total', 0, () => {
      const total: number = allCheckIds().length;
      const empty: number[] = checkProgress([]);
      expect(empty[0]).assertEqual(0);
      expect(empty[1]).assertEqual(total);
      const one: number[] = checkProgress([allCheckIds()[0]]);
      expect(one[0]).assertEqual(1);
      // 不认识的 id 不计入。
      expect(checkProgress(['ghost'])[0]).assertEqual(0);
    });

    // 编解码要能往返；坏数据退化成空，而不是抛异常。
    it('round-trips the checked set through text', 0, () => {
      const done: string[] = ['lens_dark', 'power_heat'];
      const text: string = encodeChecks(done);
      const back: string[] = decodeChecks(text);
      expect(back.length).assertEqual(2);
      expect(back[0]).assertEqual('lens_dark');
      expect(back[1]).assertEqual('power_heat');
      expect(decodeChecks('').length).assertEqual(0);
      expect(decodeChecks('\n\n').length).assertEqual(0);
    });
  });
}
