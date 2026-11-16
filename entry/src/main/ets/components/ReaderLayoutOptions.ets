import { ReaderPageLayout } from '../models/ReaderPageSpread';
import { ReaderTurnEffect } from '../models/ReaderCurlGeometry';
import { ReaderSettingSelect, ReaderSettingToggle } from './ReaderSettingSegments';

const PAGE_LAYOUTS: ReaderPageLayout[] = ['auto', 'single', 'double'];
const PAGE_LAYOUT_OPTIONS: SelectOption[] = [{ value: '自动' }, { value: '单页' }, { value: '双页' }];
const TURN_EFFECT_OPTIONS: SelectOption[] = [{ value: '滑动' }, { value: '仿真' }];

@Component
export struct ReaderLayoutOptions {
  @Prop layout: ReaderPageLayout = 'auto';
  @Prop firstSingle: boolean = false;
  @Prop effect: ReaderTurnEffect = 'slide';
  @Prop showTurnEffect: boolean = true;
  onEffectChange: (effect: ReaderTurnEffect) => void = (_effect: ReaderTurnEffect): void => {};
  onLayoutChange: (layout: ReaderPageLayout) => void = (_layout: ReaderPageLayout): void => {};
  onFirstSingleChange: (enabled: boolean) => void = (_enabled: boolean): void => {};

  build() {
    Column({ space: 4 }) {
      ReaderSettingSelect({
        label: '页面布局',
        options: PAGE_LAYOUT_OPTIONS,
        selected: PAGE_LAYOUTS.indexOf(this.layout),
        onSelect: (index: number): void => this.onLayoutChange(PAGE_LAYOUTS[index])
      })
      if (this.showTurnEffect) {
        ReaderSettingSelect({
          label: '翻页动效',
          options: TURN_EFFECT_OPTIONS,
          selected: this.effect === 'curl' ? 1 : 0,
          onSelect: (index: number): void => this.onEffectChange(index === 1 ? 'curl' : 'slide')
        })
      }

      if (this.layout !== 'single') {
        ReaderSettingToggle({
          label: '首图单独显示',
          checked: this.firstSingle,
          onChange: (enabled: boolean): void => this.onFirstSingleChange(enabled)
        })
      }
    }
    .width('100%')
  }
}
