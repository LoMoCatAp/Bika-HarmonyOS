import { ComicViewModel } from '../models/Comic';
import { NetImage } from './NetImage';
import {
  COLOR_CARD,
  COLOR_DIVIDER,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_DISABLED
} from '../common/Constants';

/**
 * 漫画卡片（首页频道列表通用，BIKA ComicCard 同构）
 */
@Component
export struct ComicCard {
  @Prop comic: ComicViewModel;
  @Prop showTitle: boolean = true;
  @State pressed: boolean = false;

  /** 按压缩放（受全局动画开关控制） */
  private setPressed(down: boolean): void {
    let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
    if (!animOn) {
      return;
    }
    if (down) {
      animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
        this.pressed = true;
      });
    } else {
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.pressed = false;
      });
    }
  }

  build() {
    Column() {
      NetImage({
        src: this.comic.coverUrl,
        fit: ImageFit.Cover,
        topRadius: 18,
        radius: 0,
        fillParent: true
      })
        .width('100%')
        .aspectRatio(0.72)

      Column() {
        if (this.showTitle) {
          Text(this.comic.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_TITLE)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(18)
            .constraintSize({ minHeight: 36 })
            .align(Alignment.Top)

          Row() {
            Text(this.comic.author)
              .fontSize(11)
              .fontColor(COLOR_TEXT_HINT)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.comic.totalViews > 0) {
              Text(this.comic.totalViews + ' 次')
                .fontSize(10)
                .fontColor(COLOR_TEXT_DISABLED)
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_DIVIDER })
    .shadow({
      radius: 12,
      color: '#120F1A33',
      offsetX: 0,
      offsetY: 4
    })
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setPressed(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.setPressed(false);
      }
    })
  }
}
