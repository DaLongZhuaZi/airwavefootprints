import { describe, it, expect } from '@ohos/hypium';
import { builtinScenePacks, isBuiltinScenePack, ScenePack } from '../main/ets/fieldwatch/domain/FieldwatchScenePacks';
import { SignatureClass } from '../main/ets/fieldwatch/domain/FieldwatchModels';

/**
 * 按 id 找包。
 *
 * **不能用「先声明 let、再在 forEach 里赋值」**：ArkTS 会在闭包赋值后
 * 把变量收窄成 `never`，下一行 `hotel.filter` 直接编译失败（实测）。
 * 返回值的写法让类型收窄发生在调用点，稳妥。
 */
function packOf(id: string): ScenePack | undefined {
  const packs: ScenePack[] = builtinScenePacks();
  for (let index: number = 0; index < packs.length; index += 1) {
    if (packs[index].id === id) return packs[index];
  }
  return undefined;
}

export default function fieldwatchScenePacksTest() {
  describe('FieldwatchScenePacks', () => {
    // 文档第五节拍板点 3 的四个包（按推荐方案执行）：宿舍 / 酒店 / 夜跑 / 办公室。
    // id 必须稳定 —— 落库用的是它，改 id 会让用户已存的包失效。
    it('ships exactly the four agreed scenes with stable ids', 0, () => {
      const packs: ScenePack[] = builtinScenePacks();
      expect(packs.length).assertEqual(4);
      expect(packs[0].id).assertEqual('dorm');
      expect(packs[1].id).assertEqual('hotel');
      expect(packs[2].id).assertEqual('nightrun');
      expect(packs[3].id).assertEqual('office');
      expect(isBuiltinScenePack('hotel')).assertTrue();
      expect(isBuiltinScenePack('custom-user-pack')).assertFalse();
    });

    // 每个包都必须是「包含式类别筛选」：场景包表达「我要找什么」，
    // 排除式会把不在名单里的东西一起放进来，与场景意图相反。
    it('every pack filters inclusively by class', 0, () => {
      builtinScenePacks().forEach((pack: ScenePack): void => {
        expect(pack.filter.useClassFilter).assertTrue();
        expect(pack.filter.excludeClasses).assertFalse();
        expect(pack.filter.classes.length > 0).assertTrue();
      });
    });

    // 酒店的意图单一：房间里不该出现的摄像头/录音类。
    // 若混进手机、耳机，这个包就退化成「什么都能看到」，等于没筛。
    it('keeps the hotel pack focused on cameras and audio', 0, () => {
      const hotel: ScenePack | undefined = packOf('hotel');
      expect(hotel !== undefined).assertTrue();
      if (hotel !== undefined) {
        const classes: SignatureClass[] = hotel.filter.classes;
        expect(classes.indexOf(SignatureClass.CAMERA) >= 0).assertTrue();
        expect(classes.indexOf(SignatureClass.SURVEILLANCE) >= 0).assertTrue();
        expect(classes.indexOf(SignatureClass.PHONE) < 0).assertTrue();
      }
    });

    // 夜跑要把远处路人挡掉，门槛必须比室内那三个更严（-75 > -90）。
    it('raises the signal floor for the night-run pack', 0, () => {
      const night: ScenePack | undefined = packOf('nightrun');
      const dorm: ScenePack | undefined = packOf('dorm');
      expect(night !== undefined && dorm !== undefined).assertTrue();
      if (night !== undefined && dorm !== undefined) {
        const nightFloor: number = night.filter.rssiMin;
        const dormFloor: number = dorm.filter.rssiMin;
        expect(nightFloor).assertEqual(-75);
        expect(dormFloor).assertEqual(-90);
        // 数值越大越严。
        expect(nightFloor > dormFloor).assertTrue();
      }
    });

    // 每次调用都返回新实例：调用方改一份不能污染「内置定义」。
    it('returns fresh definitions so callers cannot mutate the built-ins', 0, () => {
      const first: ScenePack[] = builtinScenePacks();
      first[0].filter.classes.push(SignatureClass.DRONE);
      const second: ScenePack[] = builtinScenePacks();
      expect(second[0].filter.classes.indexOf(SignatureClass.DRONE) < 0).assertTrue();
    });
  });
}
