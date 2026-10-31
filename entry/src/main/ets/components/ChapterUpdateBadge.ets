import { COLOR_PRIMARY, COLOR_PRIMARY_TINT } from '../common/Constants';

/** 章节列表中的未读更新胶囊。 */
@Component
export struct ChapterUpdateBadge {
  build() {
    Text('有更新')
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_PRIMARY)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(COLOR_PRIMARY_TINT)
      .borderRadius(8)
      .margin({ left: 8, right: 8 })
  }
}
