/**
 * Bika 为你推荐 4*4 桌面卡片
 *
 * 布局：标题 + 2x2 封面网格，撑满卡片高度。
 * 动态卡片：整格点击 postCardAction(action:'router') → open_comic（作品详情）。
 * 数据：ApiService.getCollections()，为空回退 getRandomComics()，
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
    try {
      console.info('[BikaWidget:RecommendCard] showCover=' + this.extraShowCover + ' rows=' + rows.length +
        ' key0=' + (rows.length > 0 ? rows[0].coverKey : ''));
    } catch (e) {
    }
    return rows;
  }

  private canShowCover(coverKey: string): boolean {
    return this.extraShowCover !== 'false' && coverKey.length > 0;
  }

  private keyAt(rows: RecommendRow[], i: number): string {
    return i < rows.length ? rows[i].coverKey : '';
  }

  private titleAt(rows: RecommendRow[], i: number): string {
    return i < rows.length ? rows[i].title : '';
  }

  private idAt(rows: RecommendRow[], i: number): string {
    return i < rows.length ? rows[i].id : '';
  }

  private openComic(id: string, title: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: { action: 'open_comic', comicId: id, comicTitle: title }
    });
  }

  @Builder
  coverCell(rows: RecommendRow[], index: number) {
    Column() {
      Stack() {
        if (this.canShowCover(this.keyAt(rows, index))) {
          Image('memory://' + this.keyAt(rows, index))
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

      Text(this.titleAt(rows, index))
        .fontSize(11)
        .fontColor($r('app.color.bika_text_title'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height('100%')
    .margin({ left: 3, right: 3 })
    .onClick((): void => this.openComic(this.idAt(rows, index), this.titleAt(rows, index)))
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
          Row() {
            this.coverCell(this.parseRows(), 0)
            if (this.parseRows().length > 1) {
              this.coverCell(this.parseRows(), 1)
            }
          }
          .width('100%')
          .layoutWeight(1)

          if (this.parseRows().length > 2) {
            Row() {
              this.coverCell(this.parseRows(), 2)
              if (this.parseRows().length > 3) {
                this.coverCell(this.parseRows(), 3)
              }
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
