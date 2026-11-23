import { ACCENT_COLORS_KEY, AccentColors, DEFAULT_ACCENT_COLORS } from '../common/AppearanceAccent';
import { CapsuleSegmentButtonV2, ColorMetrics, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { COLOR_CARD, COLOR_TEXT_TITLE } from '../common/Constants';
import { compatiblePopupMaterial, noImmersiveMaterial, supportsComponentImmersiveMaterial } from '../common/CompatibleMaterial';

@Component
export struct ReaderSettingSegments {
  @StorageProp(ACCENT_COLORS_KEY) appearanceColors: AccentColors = DEFAULT_ACCENT_COLORS;
  items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  @Prop selected: number = 0;
  @Prop groupLabel: string = '';
  @Prop asTab: boolean = false;
  @Prop animationsOn: boolean = true;
  onSelect: (index: number) => void = (_index: number): void => {};

  build() {
    if (this.asTab) {
      TabSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selected,
        $selectedIndex: (index: number): void => this.onSelect(index),
        itemSelectedFontColor: ColorMetrics.resourceColor(this.appearanceColors.primary),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor(this.appearanceColors.tint),
        enableStateAnimation: this.animationsOn,
        backgroundSystemMaterial: noImmersiveMaterial()
      })
        .width('100%')
        .accessibilityText(this.groupLabel)
    } else {
      CapsuleSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selected,
        $selectedIndex: (index: number): void => this.onSelect(index),
        itemSelectedFontColor: ColorMetrics.resourceColor(this.appearanceColors.primary),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor(this.appearanceColors.tint),
        enableStateAnimation: this.animationsOn,
        backgroundSystemMaterial: noImmersiveMaterial()
      })
        .width('100%')
        .accessibilityText(this.groupLabel)
    }
  }
}

@Component
export struct ReaderSettingSelect {
  @StorageProp('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_style') materialStyle: string = 'THIN';
  @Prop label: string = '';
  @Prop options: SelectOption[] = [];
  @Prop selected: number = 0;
  onSelect: (index: number) => void = (_index: number): void => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(15).fontColor(COLOR_TEXT_TITLE).layoutWeight(1)
      Select(this.options)
        .selected(this.selected)
        .value(this.options[this.selected]?.value ?? '')
        .menuSystemMaterial(compatiblePopupMaterial(undefined, this.materialStyle, this.materialLevel) ?? noImmersiveMaterial())
        .menuBackgroundColor(supportsComponentImmersiveMaterial() ? undefined : COLOR_CARD)
        .menuBackgroundBlurStyle(supportsComponentImmersiveMaterial() ? undefined : BlurStyle.NONE)
        .height(44)
        .accessibilityText(this.label)
        .onSelect((index: number): void => this.onSelect(index))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
  }
}

@Component
export struct ReaderSettingToggle {
  @StorageProp(ACCENT_COLORS_KEY) appearanceColors: AccentColors = DEFAULT_ACCENT_COLORS;
  @Prop label: string = '';
  @Prop checked: boolean = false;
  onChange: (checked: boolean) => void = (_checked: boolean): void => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(15).fontColor(COLOR_TEXT_TITLE).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor(this.appearanceColors.primary)
        .accessibilityText(this.label)
        .onChange((checked: boolean): void => this.onChange(checked))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
  }
}
