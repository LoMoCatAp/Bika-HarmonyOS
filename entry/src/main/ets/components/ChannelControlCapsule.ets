import { immersiveCapsuleTint } from '../common/ImmersiveMaterialLevel';
import { CommonModifier, uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { supportsComponentImmersiveMaterial } from '../common/CompatibleMaterial';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../common/Constants';

/** 每枚胶囊独立绘制材质，颜色随应用主题与材质档位更新。 */
class ChannelCapsuleMaterial extends CommonModifier {
  private readonly dark: boolean;

  constructor(dark: boolean) {
    super();
    this.dark = dark;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const alpha = '99';
    const tint = '#' + alpha + (this.dark ? '20252E' : 'FFFFFF');
    if (supportsComponentImmersiveMaterial()) {
      try {
        if (uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE) {
          instance.backgroundColor(Color.Transparent);
          instance.backdropBlur(0);
          instance.systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THIN,
            // 配色交给系统，不叠加自定义底色或粉色点光。
            materialColor: Color.Transparent,
            applyShadow: true,
            interactive: false
          }));
          return;
        }
        instance.systemMaterial(uiMaterial.Material.empty);
      } catch (err) {
        console.warn('[ChannelCapsule] material unavailable: ' + JSON.stringify(err));
      }
    }
    instance.backgroundColor(tint);
    instance.backdropBlur(20);
  }
}

/** 沿用阅读器方案：胶囊位于独立 Navigation.title 作用域，宿主背板透明。 */
@Component
export struct ChannelControlCapsule {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop filterIcon: boolean = false;
  @StorageProp('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_color_mode') colorMode: string = 'system';
  @StorageProp('system_color_mode') systemColorMode: string = 'light';
  @StorageProp('bika_animations') animationsOn: boolean = true;
  @State pressed: boolean = false;
  onActivate: () => void = (): void => {};

  private darkMode(): boolean {
    return this.colorMode === 'dark' || (this.colorMode === 'system' && this.systemColorMode === 'dark');
  }

  private capsuleWidth(): number {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    const fontScale = Math.min(1.3, Math.max(1, context?.config.fontSizeScale ?? 1));
    let textWidth = 0;
    for (let index = 0; index < this.label.length; index++) {
      textWidth += this.label.charCodeAt(index) <= 0xFF ? 6.5 : 13;
    }
    return Math.max(56, Math.ceil(textWidth * fontScale) + 28 + (this.filterIcon ? 20 : 0));
  }

  private setPressed(pressed: boolean): void {
    if (this.pressed === pressed) {
      return;
    }
    if (this.animationsOn) {
      animateTo({ duration: 140, curve: Curve.EaseOut }, () => {
        this.pressed = pressed;
      });
    } else {
      this.pressed = pressed;
    }
  }

  @Builder
  capsuleLabel() {
    Row({ space: 4 }) {
      if (this.filterIcon) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(16)
          .fontColor([this.selected ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
      }
      Text(this.label)
        .fontSize(13)
        .maxFontScale(1.3)
        .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selected ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 12 })
  }

  @Builder
  capsuleContent() {
    Stack() {
      Row()
        .width('100%').height(36)
        .borderRadius(18)
        .attributeModifier(new ChannelCapsuleMaterial(this.darkMode()))
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      Row()
        .width('100%').height(36)
        .borderRadius(18)
        .backgroundColor(immersiveCapsuleTint(this.materialLevel, this.darkMode()))
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      this.capsuleLabel()
    }
    .width('100%').height(36)
    .borderRadius(18)
    .scale({ x: this.animationsOn && this.pressed ? 0.96 : 1, y: this.animationsOn && this.pressed ? 0.96 : 1 })
    .accessibilityGroup(true)
    .accessibilityText(this.label)
    .accessibilitySelected(this.selected)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.setPressed(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.type === TouchType.Move) {
        this.setPressed(false);
      }
    })
    .onClick((): void => this.onActivate())
  }

  build() {
    Navigation() {
    }
    .width(this.capsuleWidth())
    .height(36)
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .clip(true)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .hideToolBar(true)
    .title({ builder: this.capsuleContent, height: 36 }, {
      barStyle: BarStyle.STACK,
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      systemMaterial: supportsComponentImmersiveMaterial() ? uiMaterial.Material.empty : undefined
    })
    .hideTitleBar(false)
    .ignoreLayoutSafeArea([], [])
  }
}
