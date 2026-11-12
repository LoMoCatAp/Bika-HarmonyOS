import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_INPUT_BG, COLOR_DIVIDER, COLOR_WHITE } from '../../common/Constants';
import { ChangelogEntry, CHANGELOG_ENTRIES } from '../../common/Changelog';

interface UpdateBlock {
  kind: string;
  text: string;
}

interface MdRun {
  text: string;
  bold: boolean;
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileUpdateSheet {
  @Link updateVersion: string;
  @Link showAboutSheet: boolean;
  @Link aboutSheetKind: number;
  @Link updateUrl: string;
  openExternalLink: (url: string) => void = (url: string): void => {};
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @Link updateBody: string;

  private markdownLines(): UpdateBlock[] {
    let blocks: UpdateBlock[] = [];
    let raw = this.updateBody.length > 0 ? this.updateBody : '点击「去下载」前往下载页面';
    let lines = raw.split('\n');
    for (let line of lines) {
      let t = line.trim();
      if (t.length === 0 || t === '---') {
        continue;
      }
      if (t.startsWith('###')) {
        blocks.push({ kind: 'h3', text: t.substring(3).trim() });
      } else if (t.startsWith('##')) {
        blocks.push({ kind: 'h2', text: t.substring(2).trim() });
      } else if (t.startsWith('# ')) {
        blocks.push({ kind: 'h1', text: t.substring(2).trim() });
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        blocks.push({ kind: 'bullet', text: t.substring(2).trim() });
      } else {
        blocks.push({ kind: 'text', text: t });
      }
    }
    return blocks;
  }

  private boldRuns(text: string): MdRun[] {
    let runs: MdRun[] = [];
    let rest = text;
    let bold = false;
    while (rest.length > 0) {
      let idx = rest.indexOf('**');
      if (idx < 0) {
        runs.push({ text: rest, bold: bold });
        break;
      }
      if (idx > 0) {
        runs.push({ text: rest.substring(0, idx), bold: bold });
      }
      rest = rest.substring(idx + 2);
      bold = !bold;
    }
    return runs;
  }

  build() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Text('发现新版本 v' + this.updateVersion)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 10 })
      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.markdownLines(), (block: UpdateBlock) => {
            if (block.kind === 'h2') {
              Text() {
                ForEach(this.boldRuns(block.text), (run: MdRun) => {
                  Span(run.text)
                    .fontSize(15)
                    .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Bold)
                    .fontColor(COLOR_TEXT_TITLE)
                }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
              }
              .width('100%')
              .margin({ top: 10, bottom: 2 })
            } else if (block.kind === 'h3') {
              Text(block.text)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
                .width('100%')
                .margin({ top: 8, bottom: 2 })
            } else if (block.kind === 'bullet') {
              Row({ space: 6 }) {
                Text('•')
                  .fontSize(14)
                  .fontColor(COLOR_PRIMARY)
                Text() {
                  ForEach(this.boldRuns(block.text), (run: MdRun) => {
                    Span(run.text)
                      .fontSize(14)
                      .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(COLOR_TEXT_TITLE)
                  }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
                }
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ top: 2, bottom: 2 })
            } else {
              Text() {
                ForEach(this.boldRuns(block.text), (run: MdRun) => {
                  Span(run.text)
                    .fontSize(14)
                    .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }, (run: MdRun) => run.text + '_' + (run.bold ? '1' : '0'))
              }
              .width('100%')
              .lineHeight(21)
            }
          }, (block: UpdateBlock, index: number) => index + '_' + block.kind + '_' + block.text)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row({ space: 12 }) {
        Button('取消', { type: ButtonType.Normal })
          .fontSize(15)
          .fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(COLOR_INPUT_BG)
          .borderRadius(22)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showAboutSheet = false;
            this.aboutSheetKind = 0;
          })
        Button('去下载', { type: ButtonType.Normal })
          .fontSize(15)
          .fontColor(COLOR_WHITE)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(22)
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.showAboutSheet = false;
            this.aboutSheetKind = 0;
            if (this.updateUrl.length > 0) {
              this.openExternalLink(this.updateUrl);
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 12 })
    }
    .width('100%')
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileChangelogSheet {
  @Link expandedAboutVersion: string;
  @Link aboutEntered: boolean;



  build() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
      Row({ space: 12 }) {
        Image($r('app.media.bika'))
          .width(52)
          .height(52)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
          .backgroundColor(COLOR_PRIMARY_TINT)
        Column({ space: 4 }) {
          Text('Bika')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
          Text('当前版本 v' + CHANGELOG_ENTRIES[0].version)
            .fontSize(13)
            .fontColor(COLOR_TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 48 })
      .padding(14)
      .backgroundColor(Color.Transparent)
      .borderRadius(20)
      .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

      Column({ space: 12 }) {
        Text('更新日志')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_TITLE)
          .width('100%')
        Scroll() {
          Column({ space: 10 }) {
            ForEach(CHANGELOG_ENTRIES, (entry: ChangelogEntry): void => {
              Column({ space: 0 }) {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text('v' + entry.version)
                      .fontSize(17)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT_TITLE)
                    Text(entry.date)
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_SECONDARY)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(20)
                    .fontColor([COLOR_TEXT_SECONDARY])
                    .rotate({ angle: this.expandedAboutVersion === entry.version ? 180 : 0 })
                    .animation({ duration: 180, curve: Curve.EaseOut })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick((): void => {
                  this.expandedAboutVersion = this.expandedAboutVersion === entry.version ? '' : entry.version;
                })
                .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.97 })

                if (this.expandedAboutVersion === entry.version) {
                  Column({ space: 8 }) {
                    Divider().margin({ bottom: 12 })
                    ForEach(entry.items, (item: string): void => {
                      Text('• ' + item)
                        .fontSize(14)
                        .lineHeight(21)
                        .fontColor(COLOR_TEXT_SECONDARY)
                        .width('100%')
                    }, (item: string): string => item)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 16 })
                  .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
                  .animation({ duration: 180, curve: Curve.EaseOut })
                }
              }
              .width('100%')
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            }, (entry: ChangelogEntry): string => entry.version)
          }
          .width('100%')
        }
        .width('100%')
        .height(350)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .opacity(this.aboutEntered ? 1 : 0)
      .translate({ y: this.aboutEntered ? 0 : 24 })
      .scale({ x: this.aboutEntered ? 1 : 0.97, y: this.aboutEntered ? 1 : 0.97 })
      .animation({ duration: 420, curve: Curve.Friction })
    }
    .width('100%')
    // 弹窗根容器补与页面一致的底色：内部卡片均为 COLOR_CARD，根用 COLOR_BG 才不撞色，深浅两模式都与页面同色
    // 顶部圆角取值≥系统 sheet 圆角（实测约 24vp），避免底色把弹窗顶角填成直角
    .backgroundColor(COLOR_BG)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfilePrivacySheet {




  build() {
    Column({ space: 14 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 6 }) {
            Text('隐私政策')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('生效日期：2026 年 8 月 16 日')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('账号与资料')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('登录密码与 Token 使用系统 Asset Store Kit 在本机加密保存，用于自动登录和访问哔咔 API。头像、昵称、等级等资料由哔咔服务器提供，本应用不作额外收集与上传。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('本地文件')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('下载的漫画与图片缓存储存在应用沙箱内，不包含任何跟踪标识。卸载应用后随沙箱一并清除。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Column({ space: 6 }) {
            Text('网络请求')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('网络请求仅发往哔咔官方接口（含国内镜像线路），用于登录、拉取漫画与图片。请求签名与官方客户端一致，不包含任何第三方统计。')
              .fontSize(14)
              .lineHeight(21)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .height(420)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    // 隐私政策弹窗与更新日志同底色，保证两类弹窗观感一致
    .backgroundColor(COLOR_BG)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }
}
