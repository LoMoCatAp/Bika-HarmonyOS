

export interface MaterialOption {
  value: string;
  label: string;
}

export const MATERIAL_OPTIONS: MaterialOption[] = [
  { value: 'EXQUISITE', label: '精美' },
  { value: 'GENTLE', label: '轻柔' },
  { value: 'SMOOTH', label: '流畅' },
  { value: 'ADAPTIVE', label: '自适应' }
];

export const MATERIAL_STYLE_OPTIONS: MaterialOption[] = [
  { value: 'ULTRA_THIN', label: '超薄' },
  { value: 'THIN', label: '薄' },
  { value: 'REGULAR', label: '常规' },
  { value: 'THICK', label: '厚' },
  { value: 'ULTRA_THICK', label: '超厚' }
];

export const COLOR_MODE_OPTIONS: MaterialOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' }
];
