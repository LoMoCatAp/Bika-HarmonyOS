import { SelectModifier } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { compatibleMenuOptions } from '../../common/CompatibleMaterial';
import { showImmersiveToast } from '../../common/ImmersiveToast';
import { CacheManager } from '../../common/CacheManager';
import { COLOR_TEXT_SECONDARY, COLOR_TEXT_TITLE } from '../../common/Constants';
import { MaterialOption, MATERIAL_OPTIONS, MATERIAL_STYLE_OPTIONS } from './ProfileOptions';

class MaterialSelectMenuStyle extends SelectModifier {
  private readonly options: MenuOptions;

  constructor(options: MenuOptions) {
    super();
    this.options = options;
  }

  applyNormalAttribute(instance: SelectAttribute): void {
    if (deviceInfo.sdkApiVersion >= 26) {
      instance.menuSystemMaterial(this.options.systemMaterial);
    }
    instance.menuBackgroundColor(this.options.backgroundColor);
    instance.menuBackgroundBlurStyle(this.options.backgroundBlurStyle);
  }
}

@Component
export struct MaterialLevelSelect {
  @Prop thickness: boolean = false;
  @StorageLink('bika_material_level') level: string = 'EXQUISITE';
  @StorageLink('bika_material_style') materialStyle: string = 'THIN';
  @StorageProp('bika_color_mode') colorMode: string = 'system';
  @StorageProp('system_color_mode') systemColorMode: string = 'light';
  @State pendingValue: string = '';
  private request: number = 0;

  aboutToDisappear(): void {
    this.request++;
    this.pendingValue = '';
  }

  private options(): MaterialOption[] {
    return this.thickness ? MATERIAL_STYLE_OPTIONS : MATERIAL_OPTIONS;
  }

  private menuOptions(): MenuOptions {
    // 只对选档菜单提供常显的材质差异，HDS 仍由原生光感绘制。
    const dark = this.colorMode === 'dark' || (this.colorMode === 'system' && this.systemColorMode === 'dark');
    let tint: ResourceColor | undefined = undefined;
    if (this.level === 'GENTLE' || this.level === 'SMOOTH') {
      const alpha = this.level === 'GENTLE' ? '66' : 'D9';
      tint = '#' + alpha + (dark ? '20252E' : 'FFFFFF');
    }
    return compatibleMenuOptions({}, this.materialStyle, this.level, tint);
  }

  private selectedIndex(): number {
    const value = this.pendingValue || (this.thickness ? this.materialStyle : this.level);
    const index = this.options().findIndex((option: MaterialOption): boolean => option.value === value);
    return index >= 0 ? index : (this.thickness ? 1 : 0);
  }

  private label(): string {
    return this.options()[this.selectedIndex()].label;
  }

  private async select(value: string): Promise<void> {
    if (!this.options().some((option: MaterialOption): boolean => option.value === value)) {
      return;
    }
    const request = ++this.request;
    this.pendingValue = value;
    try {
      const cache = await CacheManager.getInstance();
      if (request !== this.request) {
        return;
      }
      if (!cache.isReady()) {
        throw new Error('Settings unavailable');
      }
      cache.saveSetting(this.thickness ? 'material_style' : 'material_level', value);
      if (this.thickness) {
        this.materialStyle = value;
      } else {
        this.level = value;
        const revision = AppStorage.get<number>('bika_material_rev') ?? 0;
        AppStorage.setOrCreate('bika_material_rev', revision + 1);
      }
    } catch (_error) {
      if (request === this.request) {
        showImmersiveToast({ message: '显示设置保存失败，请重试', duration: 1600 });
      }
    } finally {
      if (request === this.request) {
        this.pendingValue = '';
      }
    }
  }

  build() {
    Select(this.options().map((option: MaterialOption): SelectOption => {
      return { value: option.label };
    }))
      .selected(this.selectedIndex())
      .value(this.label())
      .fontColor(COLOR_TEXT_SECONDARY)
      .optionFontColor(COLOR_TEXT_TITLE)
      .selectedOptionFontColor(COLOR_TEXT_TITLE)
      .attributeModifier(new MaterialSelectMenuStyle(this.menuOptions()))
      .accessibilityDescription(this.thickness ? '面板厚度' : '光感等级')
      .onSelect((index: number): void => {
        const option = this.options()[index];
        if (option !== undefined) {
          this.select(option.value);
        }
      })
  }
}
