import { CommonModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { COLOR_CARD } from './Constants';
import { MATERIAL_STYLE_VALUES, normalizeMaterialStyle } from './ImmersiveMaterialLevel';

const MATERIAL_ACCENT: string = '#FF7CA8';

function currentMaterialStyle(): string {
  return normalizeMaterialStyle(String(AppStorage.get('bika_material_style') ?? 'THIN'));
}

/** 仅在确认支持通用材质后访问 SDK 枚举。 */
function immersiveStyle(value: string): uiMaterial.ImmersiveStyle {
  const styles: uiMaterial.ImmersiveStyle[] = [
    uiMaterial.ImmersiveStyle.ULTRA_THIN, uiMaterial.ImmersiveStyle.THIN, uiMaterial.ImmersiveStyle.REGULAR,
    uiMaterial.ImmersiveStyle.THICK, uiMaterial.ImmersiveStyle.ULTRA_THICK
  ];
  return styles[MATERIAL_STYLE_VALUES.indexOf(normalizeMaterialStyle(value))];
}

export function supportsHdsImmersiveMaterial(): boolean {
  if (deviceInfo.sdkApiVersion < 23) {
    return false;
  }
  try {
    return hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE);
  } catch (_error) {
    return false;
  }
}

export function supportsComponentImmersiveMaterial(): boolean {
  if (deviceInfo.sdkApiVersion < 26) {
    return false;
  }
  try {
    const supported = typeof uiMaterial.isImmersiveMaterialSupported === 'function'
      ? uiMaterial.isImmersiveMaterialSupported() : supportsHdsImmersiveMaterial();
    return supported && uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
  } catch (_error) {
    return false;
  }
}

export function noImmersiveMaterial(): uiMaterial.Material | undefined {
  if (deviceInfo.sdkApiVersion < 26) {
    return undefined;
  }
  try {
    return uiMaterial.Material.empty;
  } catch (_error) {
    return undefined;
  }
}

/** 有光感时沿用原生玻璃，普通设备使用主题实底。 */
export class GlassCapsuleMaterial extends CommonModifier {
  private readonly fallbackColor: ResourceColor;
  private readonly reader: boolean;
  private readonly style: string;

  constructor(fallbackColor: ResourceColor, reader: boolean = false, style: string = currentMaterialStyle()) {
    super();
    this.fallbackColor = fallbackColor;
    this.reader = reader;
    this.style = normalizeMaterialStyle(style);
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (supportsComponentImmersiveMaterial()) {
      try {
        const material = new uiMaterial.ImmersiveMaterial({
          style: immersiveStyle(this.style),
          materialColor: this.reader ? '#991C1C1E' : undefined,
          lightEffect: this.reader ? { color: MATERIAL_ACCENT } : undefined,
          applyShadow: true,
          interactive: false
        });
        instance.backgroundColor(this.fallbackColor);
        instance.systemMaterial(material);
        return;
      } catch (error) {
        console.warn('[CompatibleMaterial] capsule material unavailable: ' + String(error));
      }
    }
    const empty = noImmersiveMaterial();
    if (empty !== undefined) {
      instance.systemMaterial(empty);
    }
    instance.backgroundColor(this.fallbackColor);
  }
}

function currentPopupLevel(): string {
  return AppStorage.get<string>('bika_material_level') ?? 'EXQUISITE';
}

/** 普通弹窗以光效和阴影体现档位，材质厚度独立选择。 */
export function compatiblePopupMaterial(materialColor?: ResourceColor,
  style: string = currentMaterialStyle(), level: string = currentPopupLevel()): uiMaterial.Material | undefined {
  if (!supportsComponentImmersiveMaterial()) {
    return undefined;
  }
  try {
    const options: uiMaterial.ImmersiveOptions = { style: immersiveStyle(style), materialColor };
    switch (level) {
      case 'ADAPTIVE':
        break; // 使用系统为当前弹窗选择的默认光效和阴影。
      case 'GENTLE':
        options.lightEffect = { color: '#66FF7CA8' };
        options.applyShadow = false;
        break;
      case 'SMOOTH':
        options.lightEffect = null;
        options.applyShadow = false;
        break;
      default:
        options.lightEffect = { color: MATERIAL_ACCENT };
        options.applyShadow = true;
    }
    return new uiMaterial.ImmersiveMaterial(options);
  } catch (error) {
    console.warn('[CompatibleMaterial] popup material unavailable: ' + String(error));
    return undefined;
  }
}

function sheetMaterialTint(): string {
  const mode = String(AppStorage.get('bika_color_mode') ?? 'system');
  const dark = mode === 'dark' || (mode === 'system' && AppStorage.get('system_color_mode') === 'dark');
  return dark ? '#B31B2029' : '#B3FFFFFF';
}

/** 普通设备与纯色面板都由系统 Sheet 绘制一层不透明主题背景。 */
export function compatibleSheetOptions(options: SheetOptions, useMaterial: boolean = true,
  style: string = currentMaterialStyle(), level: string = currentPopupLevel()): SheetOptions {
  const material = useMaterial ? compatiblePopupMaterial(sheetMaterialTint(), style, level) : undefined;
  options.systemMaterial = material ?? noImmersiveMaterial();
  if (material === undefined) {
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.blurStyle = BlurStyle.NONE;
  }
  return options;
}

export function compatibleMenuOptions(options: MenuOptions, style: string = currentMaterialStyle(),
  level: string = currentPopupLevel(), materialColor?: ResourceColor): MenuOptions {
  const material = compatiblePopupMaterial(materialColor, style, level);
  options.systemMaterial = material ?? noImmersiveMaterial();
  if (material === undefined) {
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.backgroundBlurStyle = BlurStyle.NONE;
  }
  return options;
}
