import { curves } from '@kit.ArkUI';
import { CacheManager } from '../../common/CacheManager';
import { COLOR_PRIMARY } from '../../common/Constants';
import { MaterialOption, MATERIAL_OPTIONS } from './ProfileOptions';

@Component
export struct MaterialLevelSelect {
  @StorageLink('bika_material_level') level: string = 'EXQUISITE';
  @State popScale: number = 1;

  private label(): string {
    for (let i = 0; i < MATERIAL_OPTIONS.length; i++) {
      if (MATERIAL_OPTIONS[i].value === this.level) {
        return MATERIAL_OPTIONS[i].label;
      }
    }
    return '强';
  }

  build() {
    Row({ space: 4 }) {
      Text(this.label())
        .fontSize(15)
        .fontColor(COLOR_PRIMARY)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([COLOR_PRIMARY])
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .scale({ x: this.popScale, y: this.popScale })
    .bindMenu(MATERIAL_OPTIONS.map((opt: MaterialOption): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          // 与显示模式一致的动画过渡：先弹簧弹跳，再渐变应用新档位
          let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
          if (animOn) {
            animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
              this.popScale = 1.12;
            });
            animateTo({ duration: 320, curve: curves.springMotion(0.55, 0.85) }, () => {
              this.popScale = 1;
              this.level = opt.value;
              let r = AppStorage.get<number>('bika_material_rev') ?? 0;
              AppStorage.setOrCreate('bika_material_rev', r + 1);
            });
          } else {
            this.level = opt.value;
            let r = AppStorage.get<number>('bika_material_rev') ?? 0;
            AppStorage.setOrCreate('bika_material_rev', r + 1);
          }
          CacheManager.getInstance().then(c => c.saveSetting('material_level', opt.value));
        }
      };
    }))
  }
}
