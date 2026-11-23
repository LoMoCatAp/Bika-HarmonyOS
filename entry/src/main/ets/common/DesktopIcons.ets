import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';

export interface DesktopIcon {
  id: string;
  label: string;
  image: Resource;
}

export interface DesktopIconOption extends DesktopIcon {
  portrait?: DesktopIcon;
}

// 备用图标 ID 随安装升级保留，更新图案时复用原 ID。
export const DESKTOP_ICONS: DesktopIconOption[] = [
  {
    id: '', label: '原版文字', image: $r('app.media.bika'),
    portrait: { id: 'silhouette', label: '粉白剪影', image: $r('app.media.appearance_icon_silhouette') }
  },
  { id: 'halftone', label: '粉色网点', image: $r('app.media.appearance_icon_halftone') },
  {
    id: 'multicolor', label: '四色文字', image: $r('app.media.appearance_icon_multicolor'),
    portrait: { id: 'multicolor_face', label: '四色剪影', image: $r('app.media.appearance_icon_multicolor_face') }
  },
  {
    id: 'lavender_wordmark', label: '淡紫文字', image: $r('app.media.appearance_icon_lavender_wordmark'),
    portrait: { id: 'lavender', label: '淡紫剪影', image: $r('app.media.appearance_icon_lavender') }
  },
  {
    id: 'berry', label: '白底莓红文字', image: $r('app.media.appearance_icon_berry'),
    portrait: { id: 'berry_face', label: '白底莓红剪影', image: $r('app.media.appearance_icon_berry_face') }
  },
  {
    id: 'rose', label: '钴蓝黄文字', image: $r('app.media.appearance_icon_rose'),
    portrait: { id: 'rose_face', label: '钴蓝黄剪影', image: $r('app.media.appearance_icon_rose_face') }
  },
  {
    id: 'graphite', label: '朱红奶白文字', image: $r('app.media.appearance_icon_graphite'),
    portrait: { id: 'graphite_face', label: '朱红奶白剪影', image: $r('app.media.appearance_icon_graphite_face') }
  },
  {
    id: 'mist', label: '湖绿冰白文字', image: $r('app.media.appearance_icon_mist'),
    portrait: { id: 'mist_face', label: '湖绿冰白剪影', image: $r('app.media.appearance_icon_mist_face') }
  },
  {
    id: 'wine', label: '亮柠深绿文字', image: $r('app.media.appearance_icon_wine'),
    portrait: { id: 'wine_face', label: '亮柠深绿剪影', image: $r('app.media.appearance_icon_wine_face') }
  }
];

let iconChange: Promise<void> | undefined;

export function canSwitchDesktopIcon(): boolean {
  return deviceInfo.sdkApiVersion >= 26 &&
    typeof bundleManager.getAlternateIcons === 'function' && typeof bundleManager.setAlternateIcon === 'function';
}

export function desktopIcon(id: string): DesktopIcon {
  for (const option of DESKTOP_ICONS) {
    if (option.id === id) {
      return option;
    }
    const portrait = option.portrait;
    if (portrait && portrait.id === id) {
      return portrait;
    }
  }
  return DESKTOP_ICONS[0];
}

export async function readDesktopIcon(): Promise<string> {
  if (!canSwitchDesktopIcon()) {
    return '';
  }
  if (iconChange !== undefined) {
    await iconChange.catch((): void => {});
  }
  const icons = await bundleManager.getAlternateIcons();
  return icons.find((item: bundleManager.AlternateIconInfo): boolean => item.enabled)?.iconName ?? '';
}

export async function switchDesktopIcon(id: string): Promise<void> {
  const previous = iconChange ?? Promise.resolve();
  const change = previous.catch((): void => {}).then((): Promise<void> => {
    return bundleManager.setAlternateIcon(id);
  }).catch((error: BusinessError): void => {
    // 恢复默认时，系统会把「已是默认」报告为错误。
    if (id !== '' || error.code !== 17700309) {
      throw new Error(error.code + ': ' + error.message);
    }
  });
  iconChange = change;
  try {
    await change;
  } finally {
    if (iconChange === change) {
      iconChange = undefined;
    }
  }
}
