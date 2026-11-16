import { CapsuleSegmentButtonV2, ColorMetrics, SegmentButtonV2Items, TabSegmentButtonV2, uiMaterial } from '@kit.ArkUI';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_TEXT_TITLE } from '../common/Constants';
import { supportsComponentImmersiveMaterial } from '../common/CompatibleMaterial';

@Component
export struct ReaderSettingSegments {
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
        itemSelectedFontColor: ColorMetrics.resourceColor(COLOR_PRIMARY),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor(COLOR_PRIMARY_TINT),
        enableStateAnimation: this.animationsOn,
        backgroundSystemMaterial: supportsComponentImmersiveMaterial() ? uiMaterial.Material.empty : undefined
      })
        .width('100%')
        .accessibilityText(this.groupLabel)
    } else {
      CapsuleSegmentButtonV2({
        items: this.items,
        selectedIndex: this.selected,
        $selectedIndex: (index: number): void => this.onSelect(index),
        itemSelectedFontColor: ColorMetrics.resourceColor(COLOR_PRIMARY),
        itemSelectedBackgroundColor: ColorMetrics.resourceColor(COLOR_PRIMARY_TINT),
        enableStateAnimation: this.animationsOn,
        backgroundSystemMaterial: supportsComponentImmersiveMaterial() ? uiMaterial.Material.empty : undefined
      })
        .width('100%')
        .accessibilityText(this.groupLabel)
    }
  }
}

@Component
export struct ReaderSettingSelect {
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
  @Prop label: string = '';
  @Prop checked: boolean = false;
  onChange: (checked: boolean) => void = (_checked: boolean): void => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(15).fontColor(COLOR_TEXT_TITLE).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor(COLOR_PRIMARY)
        .accessibilityText(this.label)
        .onChange((checked: boolean): void => this.onChange(checked))
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
  }
}
