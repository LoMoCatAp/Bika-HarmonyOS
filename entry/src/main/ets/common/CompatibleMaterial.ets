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
