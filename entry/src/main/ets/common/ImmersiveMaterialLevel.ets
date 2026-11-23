export const MATERIAL_STYLE_VALUES: string[] = ['ULTRA_THIN', 'THIN', 'REGULAR', 'THICK', 'ULTRA_THICK'];

export function normalizeMaterialStyle(value: string): string {
  return MATERIAL_STYLE_VALUES.includes(value) ? value : 'THIN';
}

/** 五档只调节页签栏背景模糊半径。 */
export function hdsPanelThicknessEffect(value: string): BackgroundEffectOptions {
  const index = MATERIAL_STYLE_VALUES.indexOf(normalizeMaterialStyle(value));
  return { radius: index === 0 ? 0 : (index + 1) * 8 };
}

/** HDS 档位对应的胶囊底色，与材质厚度独立保存。 */
export function immersiveCapsuleTint(level: string, dark: boolean, darkBase: string = '20252E'): ResourceColor {
  const alpha: string = level === 'GENTLE' ? '33' : level === 'SMOOTH' ? '99' : '00';
  return alpha === '00' ? Color.Transparent : '#' + alpha + (dark ? darkBase : 'FFFFFF');
}
