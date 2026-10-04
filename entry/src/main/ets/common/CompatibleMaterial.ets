import { CommonModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect } from '@kit.UIDesignKit';

/**
 * 沉浸光感材质
 * - API 26+：uiMaterial.ImmersiveMaterial（THIN 沉浸薄材 + 主色点光）
 * - 旧设备：hdsEffect 点光 + 渐变阴影回退
 */

function activeDarkMode(): boolean {
  const mode: string = String(AppStorage.get('bika_color_mode') ?? 'system');
  if (mode === 'dark') {
    return true;
  }
  if (mode === 'light') {
    return false;
  }
  return String(AppStorage.get('system_color_mode') ?? 'light') === 'dark';
}

/** 材质档位 → 点光强度（强/均衡/弱/自适应），切换档位时所有卡片材质即时变化 */
function materialIntensity(): number {
  const level: string = String(AppStorage.get('bika_material_level') ?? 'EXQUISITE');
  if (level === 'SMOOTH') {
    return 0.35;
  }
  if (level === 'GENTLE') {
    return 0.18;
  }
  if (level === 'ADAPTIVE') {
    return 0.45;
  }
  return 0.6;
}

export function supportsComponentImmersiveMaterial(): boolean {
  return deviceInfo.sdkApiVersion >= 26;
}

export function supportsHdsImmersiveMaterial(): boolean {
  return deviceInfo.sdkApiVersion >= 23;
}

export class CompatibleMaterialModifier extends CommonModifier {
  private readonly accentColor: string;
  private readonly applyShadow: boolean;
  private readonly transparentBackground: boolean;

  constructor(accentColor: string, applyShadow: boolean = false, transparentBackground: boolean = false) {
    super();
    this.accentColor = accentColor;
    this.applyShadow = applyShadow;
    this.transparentBackground = transparentBackground;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const darkMode: boolean = activeDarkMode();
    if (!supportsComponentImmersiveMaterial()) {
      instance.backgroundColor(this.transparentBackground ? Color.Transparent : (darkMode ? '#1B2029' : '#FFFFFF'));
      if (supportsHdsImmersiveMaterial()) {
        const effect: VisualEffect = new hdsEffect.HdsEffectBuilder()
          .pressShadow(hdsEffect.PressShadowType.BLEND_GRADIENT)
          .pointLight({
            sourceType: hdsEffect.PointLightSourceType.SOFT,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
            options: {
              color: this.accentColor,
              intensity: materialIntensity(),
              height: 24,
              bloom: materialIntensity() * 0.2
            }
          })
          .buildEffect();
        instance.visualEffect(effect);
      }
      if (this.applyShadow) {
        instance.border({ width: 1, color: darkMode ? '#343B48' : '#DDE2EC' });
        instance.shadow({ radius: 10, color: darkMode ? '#52000000' : '#14000000', offsetY: 2 });
      }
      return;
    }
    instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: this.applyShadow ? (darkMode ? '#1B2029' : '#FFFFFF') : Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: this.accentColor }
    }));
  }
}

export function compatibleImmersiveMaterial(accentColor: string,
  applyShadow: boolean = false, transparentBackground: boolean = false): CommonModifier {
  return new CompatibleMaterialModifier(accentColor, applyShadow, transparentBackground);
}

/** 弹窗材质点光颜色（品牌主色，与应用页签 lightColor / 沉浸 Toast 保持一致） */
const SHEET_LIGHT_COLOR: string = '#FF7CA8';

/**
 * 沉浸光感档位 → 弹窗材质底色透明度（ARGB 的 AA 段）。
 * 档位越强（EXQUISITE）底色越通透，越能透出后景；档位越弱（GENTLE）底色越实，越稳重。
 * 说明：uiMaterial.ImmersiveMaterial 只有 style（厚度）没有强度字段，档位只能落到底色透明度上；
 * 材质厚度由系统按应用沉浸光配置（module.json5 的 UIMaterial.state）决定。
 */
function sheetTintAlpha(level: string): string {
  if (level === 'SMOOTH') {
    return 'C4'; // 77%
  }
  if (level === 'GENTLE') {
    return 'CC'; // 80%
  }
  if (level === 'ADAPTIVE') {
    return 'BF'; // 75%
  }
  return 'B3'; // EXQUISITE 70%
}

/**
 * bindSheet 的 SheetOptions.systemMaterial 专用材质工厂。
 * - API 26+：返回 uiMaterial.ImmersiveMaterial（THIN 薄材 + 主色点光 + 跟随主题的透明底色）
 * - 旧设备：返回 undefined，bindSheet 保持系统默认背景
 * 注意：materialColor 必须带透明度，完全不透明会彻底挡住材质滤镜。
 */
export function compatibleSheetMaterial(materialLevel: string = 'EXQUISITE',
  accentColor: string = SHEET_LIGHT_COLOR): uiMaterial.Material | undefined {
  if (!supportsComponentImmersiveMaterial()) {
    return undefined;
  }
  try {
    // 底色跟随主题卡片色：浅色白、深色 #1B2029，保证弹窗内文字对比度
    const base: string = activeDarkMode() ? '1B2029' : 'FFFFFF';
    console.info('[CompatibleMaterial] sheet material: level=' + materialLevel + ' api=' + deviceInfo.sdkApiVersion);
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#' + sheetTintAlpha(materialLevel) + base,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: accentColor }
    });
  } catch (err) {
    console.error('[CompatibleMaterial] sheet material build failed: ' + JSON.stringify(err));
    return undefined;
  }
}
