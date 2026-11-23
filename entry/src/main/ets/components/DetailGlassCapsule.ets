import { immersiveCapsuleTint } from '../common/ImmersiveMaterialLevel';
import { CommonModifier } from '@kit.ArkUI';
import { GlassCapsuleMaterial, noImmersiveMaterial } from '../common/CompatibleMaterial';
import { COLOR_CARD } from '../common/Constants';

/** 清空原生 TabBar 宿主表面，避免胶囊外出现整条透明材质。 */
export class DetailBarBackground extends CommonModifier {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.backgroundColor(Color.Transparent);
    instance.backgroundBlurStyle(BlurStyle.NONE);
    const empty = noImmersiveMaterial();
    if (empty !== undefined) {
      instance.systemMaterial(empty);
    }
  }
}

/** 仅在圆角胶囊内绘制材质；Navigation 宿主不绘制整条背板。 */
@Component
export struct DetailGlassCapsule {
  @Prop capsuleWidth: Length = '100%';
  @Prop capsuleHeight: number = 44;
  // 父页面通过箭头闭包传入 Builder，保留父页面 this 和状态依赖。
  @BuilderParam content: () => void;
  @StorageProp('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_style') materialStyle: string = 'THIN';
  @StorageProp('bika_color_mode') colorMode: string = 'system';
  @StorageProp('system_color_mode') systemColorMode: string = 'light';

  private darkMode(): boolean {
    return this.colorMode === 'dark' || (this.colorMode === 'system' && this.systemColorMode === 'dark');
  }

  @Builder
  glassContent() {
    Stack() {
      Row()
        .width('100%').height(this.capsuleHeight)
        .borderRadius(this.capsuleHeight / 2)
        .attributeModifier(new GlassCapsuleMaterial(COLOR_CARD, false, this.materialStyle))
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      Row()
        .width('100%').height(this.capsuleHeight)
        .borderRadius(this.capsuleHeight / 2)
        .backgroundColor(immersiveCapsuleTint(this.materialLevel, this.darkMode()))
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      Row() {
        this.content()
      }
      .width('100%').height(this.capsuleHeight)
    }
    .width('100%').height(this.capsuleHeight)
    .borderRadius(this.capsuleHeight / 2)
  }

  build() {
    Navigation() {
    }
    .width(this.capsuleWidth)
    .height(this.capsuleHeight)
    .backgroundColor(Color.Transparent)
    .borderRadius(this.capsuleHeight / 2)
    .clip(true)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .hideToolBar(true)
    .title({ builder: this.glassContent, height: this.capsuleHeight }, {
      barStyle: BarStyle.STACK,
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      systemMaterial: noImmersiveMaterial()
    })
    .hideTitleBar(false)
    .ignoreLayoutSafeArea([], [])
  }
}
