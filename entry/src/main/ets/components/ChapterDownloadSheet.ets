import { EpViewModel } from '../models/Comic';
import {
  COLOR_PRIMARY, COLOR_TEXT_TITLE, COLOR_TEXT_SECONDARY, COLOR_TEXT_DISABLED,
  COLOR_CARD, COLOR_DIVIDER, COLOR_WHITE
} from '../common/Constants';

/** 详情页与阅读器共用的章节选择弹窗内容，由系统 sheet 统一绘制表面。 */
@Component
export struct ChapterDownloadSheet {
  @Prop chapters: EpViewModel[] = [];
  @Link selectedOrders: number[];
  isDownloaded: (order: number) => boolean = (_order: number): boolean => false;
  onStart: () => void = (): void => {};

  private toggleDownloadSelect(order: number): void {
    const index = this.selectedOrders.indexOf(order);
    if (index >= 0) {
      const next = this.selectedOrders.slice();
      next.splice(index, 1);
      this.selectedOrders = next;
    } else {
      this.selectedOrders = this.selectedOrders.concat(order);
    }
  }

  private selectAllChapters(): void {
    this.selectedOrders = this.chapters.map((ep: EpViewModel) => ep.order);
  }

  private clearChapterSelection(): void {
    this.selectedOrders = [];
  }

  build() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6 })
      Row() {
        Text('选择要下载的章节')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        Text('全选')
          .fontSize(14)
          .fontColor(COLOR_PRIMARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => this.selectAllChapters())
        Text('清除')
          .fontSize(14)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 8 })
          .onClick(() => this.clearChapterSelection())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })

      Scroll() {
        Grid() {
          ForEach(this.chapters, (ep: EpViewModel) => {
            GridItem() {
              Row({ space: 4 }) {
                if (this.isDownloaded(ep.order)) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(14)
                    .fontColor([this.selectedOrders.indexOf(ep.order) >= 0 ? COLOR_WHITE : COLOR_PRIMARY])
                }
                Text(ep.title.length > 0 ? ep.title : ('第' + ep.order + '话'))
                  .fontSize(13)
                  .fontColor(this.selectedOrders.indexOf(ep.order) >= 0 ? COLOR_WHITE : COLOR_TEXT_TITLE)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(this.isDownloaded(ep.order) ? 1 : 0)
              }
              .width('100%')
              .height(38)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 8, right: 8 })
              .backgroundColor(this.selectedOrders.indexOf(ep.order) >= 0 ? COLOR_PRIMARY : COLOR_CARD)
              .border({ width: 1, color: this.selectedOrders.indexOf(ep.order) >= 0 ? COLOR_PRIMARY : COLOR_DIVIDER, radius: 12 })
              .onClick(() => this.toggleDownloadSelect(ep.order))
            }
          }, (ep: EpViewModel) => String(ep.order))
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
      }
      .width('100%')
      .height(220)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Button(this.selectedOrders.length > 0
        ? '开始下载所选章节 (' + this.selectedOrders.length + ')'
        : '开始下载所选章节 (0)', { type: ButtonType.Normal })
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(COLOR_WHITE)
        .backgroundColor(this.selectedOrders.length > 0 ? COLOR_PRIMARY : COLOR_TEXT_DISABLED)
        .borderRadius(23)
        .enabled(this.selectedOrders.length > 0)
        .onClick(() => this.onStart())
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
  }
}
