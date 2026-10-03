/**
 * Bika 排行榜 2*4 桌面卡片（2 行 4 列，短而宽）
 *
 * 动态卡片：整卡点击进入榜单频道页，每个名次格子点击打开作品详情（postCardAction）。
 * 数据：ApiService.getLeaderboard('D7')，由 FormExtensionAbility 下发
 *   rankTitle / rankJson:[{id,title,coverKey,rank}] / extraShowCover
 * 封面：Image('memory://' + coverKey)；无封面时用骨架色块，不用文字兜底。
 * 颜色：全部 app.color.*，跟随系统深浅色。
 */
let rankCardStorage: LocalStorage = new LocalStorage();

interface RankRow {
  id: string;
  title: string;
  coverKey: string;
  rank: number;
}

@Entry(rankCardStorage)
@Component
struct RankCard {
  @LocalStorageProp('rankTitle') rankTitle: string = '排行榜';
  @LocalStorageProp('rankJson') rankJson: string = '[]';
  @LocalStorageProp('extraShowCover') extraShowCover: string = 'true';

  private readonly ABILITY_NAME: string = 'EntryAbility';
  private readonly MAX_ITEMS: number = 4;

  private str(v: string): string {
    return v ? v : '';
  }

  private parseRows(): RankRow[] {
    let rows: RankRow[] = [];
    try {
      let parsed = JSON.parse(this.rankJson) as RankRow[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && rows.length < this.MAX_ITEMS; i++) {
          let it = parsed[i];
          let row: RankRow = {
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
      console.info('[BikaWidget:RankCard] showCover=' + this.extraShowCover + ' rows=' + rows.length +
        ' key0=' + (rows.length > 0 ? rows[0].coverKey : ''));
    } catch (e) {
    }
    return rows;
  }

  private canShowCover(coverKey: string): boolean {
    return this.extraShowCover !== 'false' && coverKey.length > 0;
  }

  private rankLabel(row: RankRow, index: number): string {
    return row.rank > 0 ? String(row.rank) : String(index + 1);
  }

  private openLeaderboard(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: { action: 'open_leaderboard' }
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
        Text(this.rankTitle.length > 0 ? this.rankTitle : '排行榜')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bika_text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('Top')
          .fontSize(9)
          .fontColor($r('app.color.bika_primary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_primary_tint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick((): void => this.openLeaderboard())

      if (this.parseRows().length === 0) {
        Column() {
          Text('')
            .width('100%')
            .layoutWeight(1)
            .borderRadius(8)
            .backgroundColor($r('app.color.bika_placeholder'))
          Text('')
            .width('68%')
            .height(8)
            .borderRadius(4)
            .backgroundColor($r('app.color.bika_placeholder'))
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })
      } else {
        Row() {
          ForEach(this.parseRows(), (item: RankRow, index: number) => {
            Column() {
              Stack({ alignContent: Alignment.TopStart }) {
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
                Text(this.rankLabel(item, index))
                  .fontSize(9)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.bika_white'))
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.bika_primary'))
                  .margin({ left: 4, top: 4 })
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
            // key 里必须带上 coverKey：ArkUI 对 key 相同的子组件会复用旧节点，
            // 封面是二次刷新才下发的，key 不变就会一直停留在「骨架占位」。
          }, (item: RankRow, index: number) => item.id + '_' + index + '_' + item.coverKey)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.bika_card'))
    .borderRadius(16)
  }
}
