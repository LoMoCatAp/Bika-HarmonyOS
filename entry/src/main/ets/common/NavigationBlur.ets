import { TitleBarStyleOptions, HdsNavigationTitleBarOptions, DividerShowType, ScrollEffectType, BlurStrategy } from '@kit.UIDesignKit';

/** 与主页共用原生渐变模糊；前景按钮的光感材质由独立胶囊承载。 */
export function navigationBlurStyle(): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      enableRefreshOffsetChange: true
    },
    blurStrategy: BlurStrategy.ADAPTIVE,
    originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent } },
    scrollEffectStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 26, blurRadius: 36 }
    }
  };
}

/** 空标题占位维持原生模糊范围，实际标题与返回胶囊位于导航容器上层。 */
export function navigationBlurTitleBar(headerSlot: CustomBuilder,
  componentSafeArea: boolean = false): HdsNavigationTitleBarOptions {
  return {
    content: {
      title: { mainTitle: '' },
      stackBuilder: headerSlot,
      divider: { showType: DividerShowType.OFF }
    },
    enableComponentSafeArea: componentSafeArea,
    avoidLayoutSafeArea: true,
    style: navigationBlurStyle()
  };
}
