/**
 * Bika 我的收藏 2*4 桌面卡片（2 行 4 列，短而宽）
 *
 * 布局：标题 + 4 列封面网格，封面撑满剩余高度。
 * 动态卡片：标题 → open_favourites；格子 → open_comic（postCardAction）。
 * 数据：ApiService.getFavourites('dd',1)，经 common/WidgetExtraData.ets 下发。
 * 封面：Image('memory://' + coverKey)；无封面时骨架色块。
 */
let favoritesCardStorage: LocalStorage = new LocalStorage();

interface FavoriteRow {
  id: string;
  title: string;
  coverKey: string;
  rank: number;
}

@Entry(favoritesCardStorage)
@Component
struct FavoritesCard {
  @LocalStorageProp('favTitle') favTitle: string = '我的收藏';
  @LocalStorageProp('favJson') favJson: string = '[]';
  @LocalStorageProp('extraShowCover') extraShowCover: string = 'true';

  private readonly ABILITY_NAME: string = 'EntryAbility';
  private readonly MAX_ITEMS: number = 4;

  private str(v: string): string {
    return v ? v : '';
  }

  private parseRows(): FavoriteRow[] {
    let rows: FavoriteRow[] = [];
    try {
      let parsed = JSON.parse(this.favJson) as FavoriteRow[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && rows.length < this.MAX_ITEMS; i++) {
          let it = parsed[i];
          let row: FavoriteRow = {
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
      console.info('[BikaWidget:FavoritesCard] showCover=' + this.extraShowCover + ' rows=' + rows.length +
        ' key0=' + (rows.length > 0 ? rows[0].coverKey : ''));
    } catch (e) {
    }
    return rows;
  }

  private canShowCover(coverKey: string): boolean {
    return this.extraShowCover !== 'false' && coverKey.length > 0;
  }

  private openFavourites(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: { action: 'open_favourites' }
    });
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
        Text(this.favTitle.length > 0 ? this.favTitle : '我的收藏')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bika_text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('全部')
          .fontSize(9)
          .fontColor($r('app.color.bika_primary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_primary_tint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => this.openFavourites())

      if (this.parseRows().length === 0) {
        Row() {
          ForEach([0, 1, 2, 3], (n: number) => {
            Text('')
              .layoutWeight(1)
              .height('100%')
              .borderRadius(8)
              .backgroundColor($r('app.color.bika_placeholder'))
              .margin({ left: 3, right: 3 })
          }, (n: number) => 'sk' + n)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
      } else {
        Row() {
          ForEach(this.parseRows(), (item: FavoriteRow, index: number) => {
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
                .fontSize(10)
                .fontColor($r('app.color.bika_text_title'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .height('100%')
            .margin({ left: 3, right: 3 })
            .onClick((): void => this.openComic(item.id, item.title))
            // key 带上 coverKey，避免复用「尚未拿到封面」时构建的骨架节点
          }, (item: FavoriteRow, index: number) => item.id + '_' + index + '_' + item.coverKey)
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
