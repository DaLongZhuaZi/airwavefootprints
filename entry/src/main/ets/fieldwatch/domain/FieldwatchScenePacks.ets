/**
 * 场景预设包（P1-9）。
 *
 * 复用现有 `FilterPreset` 持久化机制：每个包就是一份带名字的 `FilterDefinition`，
 * 选中后走 `applyFilterPresetByName` 与用户自己存的预设**完全同一条路径**。
 * 因此这里不新建存储、不改筛选页的保存/删除逻辑。
 *
 * 四个包的组合（文档第五节拍板点 3，按推荐方案执行：宿舍 / 酒店 / 夜跑 / 办公室）：
 *   · 宿舍：找的是「室友的设备 + 可疑追踪器」——含关注别人类别、含追踪器类；
 *   · 酒店：找的是「房间里不该有的摄像头/录音」——只留监控、相机、音频；
 *   · 夜跑：找的是「跟在你后面的东西」——强度门槛提高，只留移动中仍在的设备；
 *   · 办公室：找的是「同事的电脑手机 + 打印机」——留计算机/手机/网络类。
 *
 * **每个包都必须「能筛出目标类别且不误杀」**（文档验收原文），
 * 因此四份定义都由同一个构造函数产出，差异只在类别集合与强度门槛。
 */

import { FilterDefinition, SignatureClass } from './FieldwatchModels';

/** 一个内置场景包。 */
export class ScenePack {
  /** 稳定标识（落库用；不要用显示名，改文案会让已存的包失效）。 */
  public id: string;
  /** 显示名资源键。 */
  public titleKey: string;
  /** 一句话说明资源键。 */
  public hintKey: string;
  public filter: FilterDefinition;
  constructor(id: string = '', titleKey: string = '', hintKey: string = '',
    filter: FilterDefinition = new FilterDefinition()) {
    this.id = id;
    this.titleKey = titleKey;
    this.hintKey = hintKey;
    this.filter = filter;
  }
}

/**
 * 构造一份「只看这些类别」的筛选。
 *
 * 公共部分集中在这里：逻辑与、启用类别筛选、包含式（而不是排除式）。
 * 用**包含式**是有意的：场景包给的是「我要找什么」，
 * 排除式会把「不在名单里的东西」一起放进来，与场景意图相反。
 */
function sceneFilter(classes: SignatureClass[], minimumRssi: number): FilterDefinition {
  const filter: FilterDefinition = new FilterDefinition();
  filter.useClassFilter = true;
  filter.excludeClasses = false;
  filter.classes = classes;
  filter.minimumRssi = minimumRssi;
  filter.rssiMin = minimumRssi;
  return filter;
}

/**
 * 四个内置场景包。返回新数组，调用方随意修改不会污染「内置定义」。
 *
 * 强度门槛的取值理由：
 *   · 宿舍/办公室 -90：室内近场，太严会漏掉隔壁室友的手机；
 *   · 酒店 -85：房间尺度，走廊尽头的 AP 应该被挡掉；
 *   · 夜跑 -75：户外开阔，-75 以下基本是远处路人，跟跑步无关。
 */
export function builtinScenePacks(): ScenePack[] {
  const packs: ScenePack[] = [];
  packs.push(new ScenePack('dorm', 'app.string.fieldwatch_scene_dorm', 'app.string.fieldwatch_scene_dorm_hint',
    sceneFilter([SignatureClass.FINDER, SignatureClass.BEACON, SignatureClass.WEARABLE,
      SignatureClass.AUDIO, SignatureClass.PHONE], -90)));
  packs.push(new ScenePack('hotel', 'app.string.fieldwatch_scene_hotel', 'app.string.fieldwatch_scene_hotel_hint',
    sceneFilter([SignatureClass.CAMERA, SignatureClass.SURVEILLANCE, SignatureClass.AUDIO], -85)));
  packs.push(new ScenePack('nightrun', 'app.string.fieldwatch_scene_nightrun', 'app.string.fieldwatch_scene_nightrun_hint',
    sceneFilter([SignatureClass.FINDER, SignatureClass.BEACON, SignatureClass.PHONE, SignatureClass.VEHICLE], -75)));
  packs.push(new ScenePack('office', 'app.string.fieldwatch_scene_office', 'app.string.fieldwatch_scene_office_hint',
    sceneFilter([SignatureClass.PHONE, SignatureClass.ISP, SignatureClass.MESH, SignatureClass.AUDIO], -90)));
  return packs;
}

/** 内置包的 id 集合（用于「这是内置包吗」的判断，避免被用户误删逻辑误伤）。 */
export function isBuiltinScenePack(id: string): boolean {
  let found: boolean = false;
  builtinScenePacks().forEach((pack: ScenePack): void => {
    if (pack.id === id) found = true;
  });
  return found;
}
