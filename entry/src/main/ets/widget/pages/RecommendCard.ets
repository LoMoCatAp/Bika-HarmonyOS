/**
 * Bika 为你推荐 4*4 桌面卡片
 *
 * 布局：标题 + 2x2 封面网格，撑满卡片高度。
 * 动态卡片：整格点击 postCardAction(action:'router') → open_comic（作品详情）。
 * 数据：ApiService.getRandomComics()（GET comics/random），
 *       经 common/WidgetExtraData.ets 下发 recTitle / recJson / extraShowCover。
 * 封面：Image('memory://' + coverKey)；无封面时骨架色块。
 */
let recommendCardStorage: LocalStorage = new LocalStorage();

interface RecommendRow {
  id: string;
  title: string;
  coverKey: string;
  rank: number;
}

@Entry(recommendCardStorage)
@Component
struct RecommendCard {
  @LocalStorageProp('recTitle') recTitle: string = '为你推荐';
  @LocalStorageProp('recJson') recJson: string = '[]';
  @LocalStorageProp('extraShowCover') extraShowCover: string = 'true';

  private readonly ABILITY_NAME: string = 'EntryAbility';
  private readonly MAX_ITEMS: number = 4;

  private str(v: string): string {
    return v ? v : '';
  }

  private parseRows(): RecommendRow[] {
    let rows: RecommendRow[] = [];
    try {
      let parsed = JSON.parse(this.recJson) as RecommendRow[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && rows.length < this.MAX_ITEMS; i++) {
          let it = parsed[i];
          let row: RecommendRow = {
            id: this.str(it.id),
            title: this.str(it.title),
            coverKey: this.str(it.coverKey),
            rank: it.rank > 0 ? it.rank : 0
          };
          if (row.title.length === 0) {
            continue;
          }
          rows.push(row);
        }
      }
    } catch (err) {
      rows = [];
    }
    return rows;
  }

  private canShowCover(coverKey: string): boolean {
    return this.extraShowCover !== 'false' && coverKey.length > 0;
  }

  private openComic(id: string, title: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: { action: 'open_comic', comicId: id, comicTitle: title }
    });
  }

  build() {
    Column() {
      Row() {
        Text(this.recTitle.length > 0 ? this.recTitle : '为你推荐')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bika_text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('Bika')
          .fontSize(9)
          .fontColor($r('app.color.bika_primary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_primary_tint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.parseRows().length === 0) {
        Column() {
          Row() {
            Text('')
              .layoutWeight(1)
              .height('100%')
              .borderRadius(8)
              .backgroundColor($r('app.color.bika_placeholder'))
              .margin({ right: 6 })
            Text('')
              .layoutWeight(1)
              .height('100%')
              .borderRadius(8)
              .backgroundColor($r('app.color.bika_placeholder'))
          }
          .width('100%')
          .layoutWeight(1)

          Row() {
            Text('')
              .layoutWeight(1)
              .height('100%')
              .borderRadius(8)
              .backgroundColor($r('app.color.bika_placeholder'))
              .margin({ right: 6 })
            Text('')
              .layoutWeight(1)
              .height('100%')
              .borderRadius(8)
              .backgroundColor($r('app.color.bika_placeholder'))
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
      } else {
        Column() {
          // key 必须带 coverKey：封面是二次刷新才下发的；key 不变时 ArkUI 会复用
          // 「还是骨架色块」的旧节点，封面永远不出现（与排行榜 ForEach 同款修法）
          Row() {
            ForEach(this.parseRows().slice(0, 2), (item: RecommendRow, idx: number) => {
              Column() {
                Stack() {
                  if (this.canShowCover(item.coverKey)) {
                    Image('memory://' + item.coverKey)
                      .width('100%')
                      .height('100%')
                      .objectFit(ImageFit.Cover)
                  } else {
                    Text('')
                      .width('100%')
                      .height('100%')
                      .backgroundColor($r('app.color.bika_placeholder'))
                  }
                }
                .width('100%')
                .layoutWeight(1)
                .borderRadius(8)
                .clip(true)

                Text(item.title)
                  .fontSize(11)
                  .fontColor($r('app.color.bika_text_title'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .height('100%')
              .margin({ left: 3, right: 3 })
              .onClick((): void => this.openComic(item.id, item.title))
            }, (item: RecommendRow, idx: number) => 'r0_' + item.id + '_' + item.coverKey)
          }
          .width('100%')
          .layoutWeight(1)

          if (this.parseRows().length > 2) {
            Row() {
              ForEach(this.parseRows().slice(2, 4), (item: RecommendRow, idx: number) => {
                Column() {
                  Stack() {
                    if (this.canShowCover(item.coverKey)) {
                      Image('memory://' + item.coverKey)
                        .width('100%')
                        .height('100%')
                        .objectFit(ImageFit.Cover)
                    } else {
                      Text('')
                        .width('100%')
                        .height('100%')
                        .backgroundColor($r('app.color.bika_placeholder'))
                    }
                  }
                  .width('100%')
                  .layoutWeight(1)
                  .borderRadius(8)
                  .clip(true)

                  Text(item.title)
                    .fontSize(11)
                    .fontColor($r('app.color.bika_text_title'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .height('100%')
                .margin({ left: 3, right: 3 })
                .onClick((): void => this.openComic(item.id, item.title))
              }, (item: RecommendRow, idx: number) => 'r1_' + item.id + '_' + item.coverKey)
            }
            .width('100%')
            .layoutWeight(1)
            .margin({ top: 6 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.bika_card'))
    .borderRadius(16)
  }
}
