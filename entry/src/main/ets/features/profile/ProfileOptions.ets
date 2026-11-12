

export interface MaterialOption {
  value: string;
  label: string;
}

export const MATERIAL_OPTIONS: MaterialOption[] = [
  { value: 'EXQUISITE', label: '强' },
  { value: 'GENTLE', label: '均衡' },
  { value: 'SMOOTH', label: '弱' },
  { value: 'ADAPTIVE', label: '自适应' }
];

export const COLOR_MODE_OPTIONS: MaterialOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' }
];
