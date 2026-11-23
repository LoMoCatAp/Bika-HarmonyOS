import { ACCENT_COLORS_KEY, AccentColors, DEFAULT_ACCENT_COLORS } from '../common/AppearanceAccent';

/** 章节列表中的未读更新胶囊。 */
@Component
export struct ChapterUpdateBadge {
  @StorageProp(ACCENT_COLORS_KEY) appearanceColors: AccentColors = DEFAULT_ACCENT_COLORS;
  build() {
    Text('有更新')
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.appearanceColors.primary)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(this.appearanceColors.tint)
      .borderRadius(8)
      .margin({ left: 8, right: 8 })
  }
}
