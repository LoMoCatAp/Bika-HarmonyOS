/** 胶囊通透度由独立普通底色层控制，不把 SDK 材质厚度冒充 HDS 原生档位。 */
export function immersiveCapsuleTint(level: string, dark: boolean, darkBase: string = '20252E'): ResourceColor {
  const alpha: string = level === 'GENTLE' ? '33' : level === 'SMOOTH' ? '99' : '00';
  return alpha === '00' ? Color.Transparent : '#' + alpha + (dark ? darkBase : 'FFFFFF');
}
