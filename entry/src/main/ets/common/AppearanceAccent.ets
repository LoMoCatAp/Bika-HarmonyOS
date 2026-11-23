import { CustomTheme, ThemeControl } from '@kit.ArkUI';
import { COLOR_PRIMARY, COLOR_PRIMARY_BORDER, COLOR_PRIMARY_DISABLED, COLOR_PRIMARY_TINT,
  COLOR_PRIMARY_TINT_2 } from './Constants';

export const ACCENT_SETTINGS_KEY: string = 'accent_palette';
export const ACCENT_ID_KEY: string = 'bika_accent_id';
export const ACCENT_COLORS_KEY: string = 'bika_accent_colors';
const CUSTOM_ACCENT_PREFIX: string = 'custom:';

export interface AccentPreset {
  id: string;
  name: string;
  light: string;
  dark: string;
}

export const ACCENT_PRESETS: AccentPreset[] = [
  { id: 'bika', name: '哔咔粉', light: '#FF7CA8', dark: '#FF8FB3' },
  { id: 'berry', name: '莓红', light: '#D9054C', dark: '#FF78A4' },
  { id: 'blue', name: '钴蓝', light: '#2239BD', dark: '#A0ACFF' },
  { id: 'cinnamon', name: '朱红', light: '#BA193A', dark: '#FF9FAF' },
  { id: 'wine', name: '玫紫', light: '#8C1868', dark: '#EFA1DC' },
  { id: 'green', name: '湖绿', light: '#00665A', dark: '#66E1CB' }
];

export interface AccentColors {
  primary: string | Resource;
  tint: ResourceColor;
  softTint: ResourceColor;
  border: ResourceColor;
  disabled: ResourceColor;
  onPrimary: ResourceColor;
}

export const DEFAULT_ACCENT_COLORS: AccentColors = {
  primary: COLOR_PRIMARY,
  tint: COLOR_PRIMARY_TINT,
  softTint: COLOR_PRIMARY_TINT_2,
  border: COLOR_PRIMARY_BORDER,
  disabled: COLOR_PRIMARY_DISABLED,
  onPrimary: Color.Black
};

/** 统一使用不透明 RGB，HDS 颜色选择器回传的 ARGB 则取后六位。 */
export function normalizeAccentHex(value: string): string {
  const hex = value.trim().replace(/^#/, '');
  if (!/^([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(hex)) {
    return '';
  }
  return '#' + hex.slice(-6).toUpperCase();
}

export function customAccentId(value: string): string {
  const hex = normalizeAccentHex(value);
  return hex.length > 0 ? CUSTOM_ACCENT_PREFIX + hex : '';
}

export function customAccentHex(id: string): string {
  return id.startsWith(CUSTOM_ACCENT_PREFIX) ? normalizeAccentHex(id.slice(CUSTOM_ACCENT_PREFIX.length)) : '';
}

export function accentPreset(id: string): AccentPreset {
  const custom = customAccentHex(id);
  if (custom.length > 0) {
    return {
      id: CUSTOM_ACCENT_PREFIX + custom,
      name: '自定义',
      light: readableAccent(custom, '#F7F8FC', '#000000'),
      dark: readableAccent(custom, '#1B2029', '#FFFFFF')
    };
  }
  return ACCENT_PRESETS.find((preset: AccentPreset): boolean => preset.id === id) ?? ACCENT_PRESETS[0];
}

function darkAppearance(mode: string): boolean {
  return mode === 'dark' || (mode === 'system' && AppStorage.get<string>('system_color_mode') === 'dark');
}

function mixAccent(surface: string, accent: string, ratio: number): string {
  const background = parseInt(surface.slice(1), 16);
  const foreground = parseInt(accent.slice(1), 16);
  let result = '#';
  for (let shift = 16; shift >= 0; shift -= 8) {
    const base = (background >> shift) & 0xFF;
    const color = (foreground >> shift) & 0xFF;
    result += Math.round(base + (color - base) * ratio).toString(16).padStart(2, '0');
  }
  return result;
}

function linearChannel(value: number): number {
  const channel = value / 255;
  return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
}

function relativeLuminance(hex: string): number {
  const rgb = parseInt(hex.slice(1), 16);
  return 0.2126 * linearChannel((rgb >> 16) & 0xFF) +
    0.7152 * linearChannel((rgb >> 8) & 0xFF) + 0.0722 * linearChannel(rgb & 0xFF);
}

function readableAccent(color: string, background: string, endpoint: string): string {
  const backgroundLum = relativeLuminance(background);
  let candidate = color;
  for (let step = 0; step < 16; step++) {
    const lum = relativeLuminance(candidate);
    const contrast = (Math.max(lum, backgroundLum) + 0.05) / (Math.min(lum, backgroundLum) + 0.05);
    if (contrast >= 4.5) {
      return candidate;
    }
    candidate = mixAccent(color, endpoint, (step + 1) / 16);
  }
  return candidate;
}

export function accentColors(id: string,
  mode: string = AppStorage.get<string>('bika_color_mode') ?? 'system'): AccentColors {
  const preset = accentPreset(id);
  if (preset.id === ACCENT_PRESETS[0].id) {
    return DEFAULT_ACCENT_COLORS;
  }
  const dark = darkAppearance(mode);
  const color = dark ? preset.dark : preset.light;
  const surface = dark ? '#1B2029' : '#FFFFFF';
  return {
    primary: color,
    tint: mixAccent(surface, color, dark ? 0.18 : 0.12),
    softTint: mixAccent(surface, color, dark ? 0.12 : 0.07),
    border: mixAccent(surface, color, dark ? 0.34 : 0.32),
    disabled: mixAccent(surface, color, 0.55),
    onPrimary: relativeLuminance(color) >= 0.179 ? Color.Black : Color.White
  };
}

export function syncAccentColors(id: string = AppStorage.get<string>(ACCENT_ID_KEY) ?? ACCENT_PRESETS[0].id,
  mode: string = AppStorage.get<string>('bika_color_mode') ?? 'system'): void {
  const preset = accentPreset(id);
  AppStorage.setOrCreate(ACCENT_ID_KEY, preset.id);
  AppStorage.setOrCreate(ACCENT_COLORS_KEY, accentColors(preset.id, mode));
}

export function applyNativeAccent(id: string = AppStorage.get<string>(ACCENT_ID_KEY) ?? ACCENT_PRESETS[0].id): void {
  const preset = accentPreset(id);
  const theme: CustomTheme = {
    colors: { brand: preset.light },
    darkColors: { brand: preset.dark }
  };
  try {
    ThemeControl.setDefaultTheme(theme);
  } catch (error) {
    console.warn('[AppearanceAccent] applying the native theme failed: ' + String(error));
  }
}
