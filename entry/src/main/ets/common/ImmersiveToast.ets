import { promptAction } from '@kit.ArkUI';
import { compatiblePopupMaterial, noImmersiveMaterial } from './CompatibleMaterial';
import { COLOR_CARD, COLOR_TEXT_TITLE } from './Constants';

export function showImmersiveToast(options: promptAction.ShowToastOptions): void {
  const material = compatiblePopupMaterial();
  options.systemMaterial = material ?? noImmersiveMaterial();
  if (material === undefined) {
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.backgroundBlurStyle = BlurStyle.NONE;
    options.textColor = options.textColor ?? COLOR_TEXT_TITLE;
  }
  promptAction.showToast(options);
}

export function showImmersiveDialog(
  options: promptAction.ShowDialogOptions
): Promise<promptAction.ShowDialogSuccessResponse> {
  const material = compatiblePopupMaterial();
  options.systemMaterial = material ?? noImmersiveMaterial();
  if (material === undefined) {
    options.backgroundColor = options.backgroundColor ?? COLOR_CARD;
    options.backgroundBlurStyle = BlurStyle.NONE;
  }
  return promptAction.showDialog(options);
}
