/**
 * Bika「最近更新」4*4 桌面卡片
 *
 * 布局：标题 + 继续阅读行 + 2x2 封面网格，全部撑满卡片高度（不留大块空白）。
 * 动态卡片：所有可点区域都是 postCardAction(action:'router')。
 * 封面：Image('memory://' + coverKey)；无封面时是骨架色块，不用文字兜底。
 * 颜色：全部 app.color.*，跟随系统深浅色。
 */
let recentCardStorage: LocalStorage = new LocalStorage();

interface RecentRow {
  id: string;
  title: string;
  coverKey: string;
  order: number;
  time: number;
}

@Entry(recentCardStorage)
@Component
struct RecentCard {
  @LocalStorageProp('recentTitle') recentTitle: string = '最近更新';
  @LocalStorageProp('continueTitle') continueTitle: string = '';
  @LocalStorageProp('continueSubtitle') continueSubtitle: string = '';
  @LocalStorageProp('continueComicId') continueComicId: string = '';
  @LocalStorageProp('continueCoverKey') continueCoverKey: string = '';
  @LocalStorageProp('recentJson') recentJson: string = '[]';
  @LocalStorageProp('showCover') showCover: string = 'true';
  @LocalStorageProp('emptyText') emptyText: string = '打开 Bika 开始阅读';

  private readonly ABILITY_NAME: string = 'EntryAbility';
  private readonly MAX_ROWS: number = 4;

  private str(v: string): string {
    return v ? v : '';
  }

  private parseRows(): RecentRow[] {
    let rows: RecentRow[] = [];
    try {
      let parsed = JSON.parse(this.recentJson) as RecentRow[];
      if (parsed && parsed.length > 0) {
        for (let i = 0; i < parsed.length && rows.length < this.MAX_ROWS; i++) {
          let it = parsed[i];
          let row: RecentRow = {
            id: this.str(it.id),
            title: this.str(it.title),
            coverKey: this.str(it.coverKey),
            order: it.order > 0 ? it.order : 0,
            time: it.time > 0 ? it.time : 0
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
      console.info('[BikaWidget:RecentCard] showCover=' + this.showCover + ' rows=' + rows.length +
        ' key0=' + (rows.length > 0 ? rows[0].coverKey : '') + ' continueKey=' + this.continueCoverKey);
    } catch (e) {
    }
    return rows;
  }

  private canShow(coverKey: string): boolean {
    return this.showCover !== 'false' && coverKey.length > 0;
  }

  private keyAt(rows: RecentRow[], i: number): string {
    return i < rows.length ? rows[i].coverKey : '';
  }

  private titleAt(rows: RecentRow[], i: number): string {
    return i < rows.length ? rows[i].title : '';
  }

  private idAt(rows: RecentRow[], i: number): string {
    return i < rows.length ? rows[i].id : '';
  }

  private openContinue(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: {
        action: 'continue_reading',
        comicId: this.continueComicId,
        comicTitle: this.continueTitle
      }
    });
  }

  private openComic(id: string, title: string): void {
    postCardAction(this, {
      action: 'router',
      abilityName: this.ABILITY_NAME,
      params: { action: 'open_comic', comicId: id, comicTitle: title }
    });
  }

  @Builder
  coverCell(rows: RecentRow[], index: number) {
    Column() {
      Stack() {
        if (this.canShow(this.keyAt(rows, index))) {
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
        .fontSize(10)
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

  @Builder
  skeletonGrid() {
    Column() {
      Row() {
        Text('')
          .width('48%')
          .layoutWeight(1)
          .height('100%')
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_placeholder'))
        Text('')
          .width('48%')
          .layoutWeight(1)
          .height('100%')
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_placeholder'))
          .margin({ left: 6 })
      }
      .width('100%')
      .layoutWeight(1)

      Row() {
        Text('')
          .width('48%')
          .layoutWeight(1)
          .height('100%')
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_placeholder'))
        Text('')
          .width('48%')
          .layoutWeight(1)
          .height('100%')
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_placeholder'))
          .margin({ left: 6 })
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ top: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(this.recentTitle.length > 0 ? this.recentTitle : '最近更新')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bika_text_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('Bika')
          .fontSize(10)
          .fontColor($r('app.color.bika_primary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor($r('app.color.bika_primary_tint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.continueTitle.length > 0) {
        Row() {
          Stack() {
            if (this.canShow(this.continueCoverKey)) {
              Image('memory://' + this.continueCoverKey)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            } else {
              Text('')
                .width('100%')
                .height('100%')
                .backgroundColor($r('app.color.bika_primary_tint'))
            }
          }
          .width(30)
          .height('100%')
          .borderRadius(8)
          .clip(true)

          Column() {
            Text(this.continueTitle)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.bika_text_title'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.continueSubtitle.length > 0 ? this.continueSubtitle : '继续上次阅读')
              .fontSize(10)
              .fontColor($r('app.color.bika_text_secondary'))
              .maxLines(1)
              .margin({ top: 2 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .height('100%')
          .margin({ left: 8 })
        }
        .width('100%')
        .height(48)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 6 })
        .onClick((): void => this.openContinue())
      }

      if (this.parseRows().length === 0) {
        this.skeletonGrid()
        Text(this.emptyText)
          .fontSize(10)
          .fontColor($r('app.color.bika_text_hint'))
          .maxLines(1)
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
