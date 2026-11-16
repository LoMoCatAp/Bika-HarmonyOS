import { CommonModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { COLOR_CARD } from './Constants';

const MATERIAL_ACCENT: string = '#FF7CA8';

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
  // 当前构建 SDK 的 ArkUI 声明不含硬件查询，使用 HDS 的设备材质能力查询。
  if (deviceInfo.sdkApiVersion < 26 || !supportsHdsImmersiveMaterial()) {
    return false;
  }
  try {
    return uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
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

  constructor(fallbackColor: ResourceColor, reader: boolean = false) {
    super();
    this.fallbackColor = fallbackColor;
    this.reader = reader;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (supportsComponentImmersiveMaterial()) {
      try {
        const material = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
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

/** 系统弹窗保留原生材质配色，低算力设备可使用系统自带的底色。 */
export function compatiblePopupMaterial(materialColor?: ResourceColor): uiMaterial.Material | undefined {
  if (!supportsComponentImmersiveMaterial()) {
    return undefined;
  }
  try {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: MATERIAL_ACCENT }
    });
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
export function compatibleSheetOptions(options: SheetOptions, useMaterial: boolean = true): SheetOptions {
  const material = useMaterial ? compatiblePopupMaterial(sheetMaterialTint()) : undefined;
  options.systemMaterial = material ?? noImmersiveMaterial();
  if (material === undefined) {
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.blurStyle = BlurStyle.NONE;
  }
  return options;
}

export function compatibleMenuOptions(options: MenuOptions): MenuOptions {
  if (!supportsComponentImmersiveMaterial()) {
    options.systemMaterial = noImmersiveMaterial();
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.backgroundBlurStyle = BlurStyle.NONE;
  }
  return options;
}
