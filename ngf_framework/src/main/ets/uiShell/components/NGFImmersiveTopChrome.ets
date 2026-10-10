import { hdsEffect } from '@kit.UIDesignKit';

/**
 * 沉浸式顶栏页面的**内容层顶部避让**。
 *
 * **必须把底板自身的高度算进去。**
 *
 * `NGFImmersiveTopChromeUnderlay` 会 `expandSafeArea([SYSTEM], [TOP])` 向状态栏方向扩展，
 * 所以它实际覆盖的高度是 `underlayHeight + 顶部安全区`（本机实测 168 + 28 = **196vp**，
 * 像素剖面在 y≈392px 处从渐变突降到页面底色，与该值吻合）。
 *
 * 而且它**合成在内容之上**：落在这一带里的内容会被压暗。
 * 实测把强调色 `rgb(21,255,142)`（带外）冲成 `rgb(86,246,158)`（带内）。
 *
 * 之前三个页面都写死 92（= 框架 preset 的 `contentTopInset` 默认值），
 * 于是首个内容元素整块落在覆盖带里 —— 表现为「顶部未正确避让、按钮被挡住」。
 *
 * @param underlayHeight 传给 `NGFImmersiveTopChromePresetFactory.build` 的底板高度
 * @param topInset       顶部系统安全区高度（vp），由根页面测量后传入
 */
export function ngfImmersiveContentTop(underlayHeight: number, topInset: number): number {
  return underlayHeight + topInset;
}

export class NGFImmersiveTopChromeMetrics {
  underlayHeight: number;
  contentTopInset: number;

  constructor(underlayHeight: number, contentTopInset: number) {
    this.underlayHeight = underlayHeight;
    this.contentTopInset = contentTopInset;
  }
}

export class NGFImmersiveTopChromeSpec {
  metrics: NGFImmersiveTopChromeMetrics;
  gradientStart: string;
  gradientMid: string;
  gradientEnd: string;
  primaryGlowColor: string;
  secondaryGlowColor: string;
  lineColor: string | Resource;
  maskColor: string | Resource;
  effectRadius: number;
  effectSaturation: number;
  effectBrightness: number;

  constructor(
    metrics: NGFImmersiveTopChromeMetrics,
    gradientStart: string,
    gradientMid: string,
    gradientEnd: string,
    primaryGlowColor: string,
    secondaryGlowColor: string,
    lineColor: string | Resource,
    maskColor: string | Resource,
    effectRadius: number,
    effectSaturation: number,
    effectBrightness: number
  ) {
    this.metrics = metrics;
    this.gradientStart = gradientStart;
    this.gradientMid = gradientMid;
    this.gradientEnd = gradientEnd;
    this.primaryGlowColor = primaryGlowColor;
    this.secondaryGlowColor = secondaryGlowColor;
    this.lineColor = lineColor;
    this.maskColor = maskColor;
    this.effectRadius = effectRadius;
    this.effectSaturation = effectSaturation;
    this.effectBrightness = effectBrightness;
  }
}

class NGFImmersiveTopChromePointLightOptions implements hdsEffect.PointLightOptions {
  color?: ResourceColor;
  intensity?: number;
  height?: Dimension;
  bloom?: number;

  constructor(color: ResourceColor, intensity: number, height: Dimension, bloom: number) {
    this.color = color;
    this.intensity = intensity;
    this.height = height;
    this.bloom = bloom;
  }
}

class NGFImmersiveTopChromePointLightEffect implements hdsEffect.PointLightEffect {
  sourceType?: hdsEffect.PointLightSourceType;
  illuminatedType?: hdsEffect.PointLightIlluminatedType;
  options?: hdsEffect.PointLightOptions;

  constructor(
    sourceType: hdsEffect.PointLightSourceType,
    illuminatedType: hdsEffect.PointLightIlluminatedType,
    options: hdsEffect.PointLightOptions
  ) {
    this.sourceType = sourceType;
    this.illuminatedType = illuminatedType;
    this.options = options;
  }
}

class NGFImmersiveTopChromeBackgroundEffectOptions implements BackgroundEffectOptions {
  radius: number;
  saturation?: number;
  brightness?: number;
  color?: ResourceColor;
  adaptiveColor?: AdaptiveColor;

  constructor(radius: number, saturation: number, brightness: number, color: ResourceColor) {
    this.radius = radius;
    this.saturation = saturation;
    this.brightness = brightness;
    this.color = color;
    this.adaptiveColor = AdaptiveColor.DEFAULT;
  }
}

class NGFImmersiveTopChromeEffectFactory {
  static build(spec: NGFImmersiveTopChromeSpec): VisualEffect {
    const pointLightOptions = new NGFImmersiveTopChromePointLightOptions($r('app.color.point_light_color'), 0.32, 30, 0.22);
    const pointLightEffect = new NGFImmersiveTopChromePointLightEffect(
      hdsEffect.PointLightSourceType.SOFT,
      hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      pointLightOptions
    );
    return new hdsEffect.HdsEffectBuilder()
      .pointLight(pointLightEffect)
      .buildEffect();
  }
}

export class NGFImmersiveTopChromePresetFactory {
  static build(
    gradientStart: string,
    gradientMid: string,
    gradientEnd: string,
    primaryGlowColor: string,
    secondaryGlowColor: string,
    underlayHeight: number = 168,
    contentTopInset: number = 92
  ): NGFImmersiveTopChromeSpec {
    return new NGFImmersiveTopChromeSpec(
      new NGFImmersiveTopChromeMetrics(underlayHeight, contentTopInset),
      gradientStart,
      gradientMid,
      gradientEnd,
      primaryGlowColor,
      secondaryGlowColor,
      $r('app.color.glass_divider'),
      $r('app.color.glass_bg_effect_light'),
      38,
      1.22,
      1.04
    );
  }
}

@Component
export struct NGFImmersiveTopChromeUnderlay {
  spec: NGFImmersiveTopChromeSpec = NGFImmersiveTopChromePresetFactory.build(
    '#07101E',
    '#0C2341',
    '#0A1626',
    '#2854F0E8',
    '#32A4F2D8'
  );

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height(this.spec.metrics.underlayHeight)
        .linearGradient({
          angle: 150,
          colors: [
            [this.spec.gradientStart, 0],
            [this.spec.gradientMid, 0.4],
            [this.spec.gradientEnd, 1]
          ]
        })

      Column() {}
        .width(176)
        .height(176)
        .borderRadius(176)
        .backgroundColor(this.spec.primaryGlowColor)
        .opacity(0.22)
        .margin({ left: 192, top: 12 })
        .shadow({ radius: 82, color: $r('app.color.glow_circle_blue_shadow'), offsetX: 10, offsetY: 6 })

      Column() {}
        .width(148)
        .height(148)
        .borderRadius(148)
        .backgroundColor(this.spec.secondaryGlowColor)
        .opacity(0.18)
        .margin({ left: 18, top: 28 })
        .shadow({ radius: 74, color: $r('app.color.glow_circle_cyan_shadow'), offsetX: -8, offsetY: 8 })

      Column() {}
        .width('86%')
        .height(1)
        .backgroundColor(this.spec.lineColor)
        .opacity(0.52)
        .margin({ left: 16, top: 94 })

      Column() {}
        .width('100%')
        .height(this.spec.metrics.underlayHeight)
        .backgroundEffect(
          new NGFImmersiveTopChromeBackgroundEffectOptions(
            this.spec.effectRadius,
            this.spec.effectSaturation,
            this.spec.effectBrightness,
            this.spec.maskColor
          )
        )
        .visualEffect(NGFImmersiveTopChromeEffectFactory.build(this.spec))
    }
    .width('100%')
    .height(this.spec.metrics.underlayHeight)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
