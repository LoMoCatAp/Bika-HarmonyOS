import { promptAction, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 沉浸光感弹窗（Toast / Dialog）
 * - API 26+：为系统弹窗套用沉浸材质（systemMaterial），保留系统默认背景模糊
 * - 旧设备：保持系统默认样式（不构造材质对象，避免低版本模块缺失）
 */

/** 品牌主色，用于材质点光 */
const ACCENT_HEX: string = '#FF7CA8';

function isDarkMode(): boolean {
  const mode: string = String(AppStorage.get('bika_color_mode') ?? 'system');
  if (mode === 'dark') {
    return true;
  }
  if (mode === 'light') {
    return false;
  }
  return String(AppStorage.get('system_color_mode') ?? 'light') === 'dark';
}

/** 设备是否支持系统沉浸材质弹窗（API 26+） */
export function supportsImmersiveToast(): boolean {
  return deviceInfo.sdkApiVersion >= 26;
}

/** 构造弹窗用的沉浸材质；不支持时返回 undefined */
function popupMaterial(): uiMaterial.Material | undefined {
  if (!supportsImmersiveToast()) {
    return undefined;
  }
  try {
    // 注意：materialColor 必须带透明度，完全不通明会彻底挡住材质效果
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: ACCENT_HEX }
    });
  } catch (err) {
    console.error('[ImmersiveToast] material build failed: ' + JSON.stringify(err));
    return undefined;
  }
}

/**
 * 统一的 Toast 入口：支持沉浸材质的设备自动套用材质，其余设备与系统默认一致。
 * 用法与原 promptAction.showToast 完全一致。
 */
export function showImmersiveToast(options: promptAction.ShowToastOptions): void {
  const material = popupMaterial();
  if (material !== undefined) {
    options.systemMaterial = material;
    console.info('[ImmersiveToast] toast material applied, api=' + deviceInfo.sdkApiVersion);
  } else {
    console.info('[ImmersiveToast] fallback default toast, api=' + deviceInfo.sdkApiVersion);
  }
  promptAction.showToast(options);
}

/**
 * 统一的对话框入口：支持沉浸材质的设备自动套用材质。
 * 用法与原 promptAction.showDialog 完全一致（返回 Promise）。
 */
export function showImmersiveDialog(
  options: promptAction.ShowDialogOptions
): Promise<promptAction.ShowDialogSuccessResponse> {
  const material = popupMaterial();
  if (material !== undefined) {
    options.systemMaterial = material;
    console.info('[ImmersiveToast] dialog material applied, api=' + deviceInfo.sdkApiVersion);
  }
  return promptAction.showDialog(options);
}
