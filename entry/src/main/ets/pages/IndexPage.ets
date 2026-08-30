import { router, display, promptAction, curves } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ApiService, ComicsPageResult } from '../network/ApiService';
import { ComicViewModel, buildImageUrl, BikaComicSummary, BikaNotification, BikaComment } from '../models/Comic';
import { NetImage } from '../components/NetImage';
import { ComicCard } from '../components/ComicCard';
import { CacheManager, HistoryItem } from '../common/CacheManager';
import { DownloadManager, DownloadTask } from '../common/DownloadManager';
import { compatibleImmersiveMaterial } from '../common/CompatibleMaterial';
import { ImageLoader } from '../common/ImageLoader';
import { WindowHelper } from '../common/WindowHelper';
import { ApiRouteManager } from '../network/ApiRouteManager';
import { DnsService, DnsIpEntry } from '../network/DnsService';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_PRIMARY_TINT_2,
  COLOR_BG,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_HINT,
  COLOR_TEXT_DISABLED,
  COLOR_TEXT_TITLE,
  COLOR_CARD,
  COLOR_INPUT_BG,
  COLOR_PLACEHOLDER,
  COLOR_GLASS_TOP,
  COLOR_DIVIDER,
  COLOR_WHITE,
  DEFAULT_CHANNELS,
  SORT_OPTIONS,
  SortOption,
  BikaChannel,
  adaptiveChannelColumns,
  adaptiveListColumns
} from '../common/Constants';
import { HdsTabs, HdsTabsController, HdsAnimationMode, DividerMode, hdsMaterial, HdsNavigation, HdsNavDestination } from '@kit.UIDesignKit';

/**
 * 主入口 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */

/** 全部分类标识 */
const CATEGORY_ALL: string = '全部';

// ═══════════════════════════════════════════
// 首页 — 频道网格
@Component
struct HomePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  @StorageProp('avatarUrl') avatarUrl: string = '';
  @StorageProp('bika_material_rev') materialRev: number = 0;
  /** 频道自定义：顺序与隐藏 */
  @State channelOrder: string[] = [];
  @State channelHidden: string[] = [];
  @State showChannelEdit: boolean = false;
  /** 频道按压效果 */
  @State pressedChannel: string = '';
  private cache: CacheManager | null = null;

  /** 跳转个人中心（由 IndexPage 切换 tab） */
  onGotoProfile(): void {
    AppStorage.set('bika_goto_profile', Date.now());
  }

  aboutToAppear(): void {
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      this.channelOrder = cache.loadChannelsOrder();
      this.channelHidden = cache.loadChannelsHidden();
    });
  }

  /** 按自定义顺序与隐藏过滤后的频道 */
  private visibleChannels(): BikaChannel[] {
    let base = DEFAULT_CHANNELS.slice(0);
    if (this.channelOrder.length > 0) {
      base.sort((a: BikaChannel, b: BikaChannel) => {
        let ia = this.channelOrder.indexOf(a.label);
        let ib = this.channelOrder.indexOf(b.label);
        if (ia < 0) {
          ia = 999;
        }
        if (ib < 0) {
          ib = 999;
        }
        return ia - ib;
      });
    }
    return base.filter(c => this.channelHidden.indexOf(c.label) < 0);
  }

  /** 当前编辑顺序列表 */
  private channelEditList(): string[] {
    let labels = this.channelOrder.length > 0
      ? this.channelOrder.slice(0)
      : DEFAULT_CHANNELS.map(c => c.label);
    return labels;
  }

  private persistChannels(): void {
    if (this.cache) {
      this.cache.saveChannelsCustom(this.channelOrder, this.channelHidden);
    }
  }

  private moveChannel(index: number, delta: number): void {
    let list = this.channelEditList();
    let to = index + delta;
    if (to < 0 || to >= list.length) {
      return;
    }
    let tmp = list[index];
    list[index] = list[to];
    list[to] = tmp;
    this.channelOrder = list;
    this.persistChannels();
  }

  private toggleChannelHidden(label: string): void {
    let arr = this.channelHidden.slice(0);
    let idx = arr.indexOf(label);
    if (idx >= 0) {
      arr.splice(idx, 1);
    } else {
      arr.push(label);
    }
    this.channelHidden = arr;
    this.persistChannels();
  }

  private resetChannels(): void {
    this.channelOrder = [];
    this.channelHidden = [];
    this.persistChannels();
  }

  /** 频道编辑弹窗 */
  @Builder
  channelEditSheet() {
    Column({ space: 0 }) {
      Text('')
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(COLOR_TEXT_SECONDARY)
        .opacity(0.32)
        .margin({ top: 6, bottom: 4 })
      Row() {
        Text('编辑频道')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        Text('恢复默认')
          .fontSize(13)
          .fontColor(COLOR_PRIMARY)
          .onClick(() => this.resetChannels())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.channelEditList(), (label: string, index: number) => {
            Row({ space: 8 }) {
              Image(DEFAULT_CHANNELS.find(c => c.label === label)?.icon ?? $r('app.media.ic_cat_index'))
                .width(30)
                .height(30)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
                .backgroundColor(COLOR_PLACEHOLDER)
              Text(label)
                .fontSize(14)
                .fontColor(this.channelHidden.indexOf(label) >= 0 ? COLOR_TEXT_HINT : COLOR_TEXT_TITLE)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.arrow_up'))
                .fontSize(16)
                .fontColor([index > 0 ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED])
                .padding(6)
                .onClick(() => this.moveChannel(index, -1))
              SymbolGlyph($r('sys.symbol.arrow_down'))
                .fontSize(16)
                .fontColor([index < this.channelEditList().length - 1 ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED])
                .padding(6)
                .onClick(() => this.moveChannel(index, 1))
              Toggle({ type: ToggleType.Switch, isOn: this.channelHidden.indexOf(label) < 0 })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.toggleChannelHidden(label);
                })
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
          }, (label: string) => label)
        }
        .width('100%')
        .padding({ bottom: this.bottomSafeHeight + 12 })
      }
      .width('100%')
      .height(this.channelSheetHeight())
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** 频道编辑列表高度（屏幕 55%） */
  private channelSheetHeight(): number {
    return px2vp(display.getDefaultDisplaySync().height) * 0.55;
  }

  /** 频道按压缩放（受全局动画开关控制） */
  private setChannelPressed(label: string, down: boolean): void {
    let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
    if (!animOn) {
      return;
    }
    if (down) {
      animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
        this.pressedChannel = label;
      });
    } else {
      animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.pressedChannel = '';
      });
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // 顶部占位（浮层标题栏）
          Row().height(this.topSafeHeight + 56)

          // 频道网格（方形图标 + 名称，按自定义顺序与隐藏过滤）
          Grid() {
            ForEach(this.visibleChannels(), (ch: BikaChannel) => {
              GridItem() {
                Column({ space: 8 }) {
                  Image(ch.icon)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(18)
                    .backgroundColor(COLOR_PLACEHOLDER)
                  Text(ch.label)
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .scale({ x: this.pressedChannel === ch.label ? 0.94 : 1, y: this.pressedChannel === ch.label ? 0.94 : 1 })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.setChannelPressed(ch.label, true);
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.setChannelPressed(ch.label, false);
                  }
                })
                .onClick(() => {
                  if (ch.kind === 'board') {
                    promptAction.showToast({ message: '该功能已下线', duration: 1600 });
                    return;
                  }
                  router.pushUrl({
                    url: 'pages/ChannelListPage',
                    params: { label: ch.label, kind: ch.kind }
                  });
                })
              }
            }, (ch: BikaChannel) => ch.label)
          }
          .columnsTemplate(adaptiveChannelColumns())
          .columnsGap(14)
          .rowsGap(18)
          .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 76 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .backgroundColor(COLOR_BG)

      // 浮层标题栏（纯色融入背景）
      Row() {
        Text('Bika')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([COLOR_TEXT_TITLE])
          .padding(6)
          .onClick(() => {
            this.showChannelEdit = true;
          })
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([COLOR_TEXT_TITLE])
          .padding(6)
          .onClick(() => {
            router.pushUrl({ url: 'pages/SearchPage' });
          })
        if (this.isLoggedIn) {
          if (this.avatarUrl.length > 0) {
            NetImage({
              src: this.avatarUrl,
              fit: ImageFit.Cover,
              radius: 18,
              fillParent: true
            })
              .width(36)
              .height(36)
              .margin({ left: 8 })
              .onClick(() => {
                this.onGotoProfile();
              })
          } else {
            Image($r('app.media.ic_default_avatar'))
              .width(36)
              .height(36)
              .borderRadius(18)
              .objectFit(ImageFit.Cover)
              .margin({ left: 8 })
              .onClick(() => {
                this.onGotoProfile();
              })
          }
        } else {
          Button({ type: ButtonType.Normal }) {
            Text('登录')
              .fontSize(14)
              .fontColor(COLOR_WHITE)
          }
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(18)
          .width(64)
          .height(34)
          .margin({ left: 8 })
          .onClick(() => router.pushUrl({ url: 'pages/LoginPage' }))
        }
      }
      .position({ x: 0, y: 0 })
      .width('100%')
      .padding({ left: 20, right: 20, top: this.topSafeHeight + 8, bottom: 6 })
      .backgroundColor(COLOR_GLASS_TOP)
      .backdropBlur(20)
      .zIndex(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    .bindSheet($$this.showChannelEdit, this.channelEditSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: false,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showChannelEdit = false;
      }
    })
  }
}

// ═══════════════════════════════════════════
// 我的 — 个人中心
// ═══════════════════════════════════════════

/** 下载分组（按作品归纳） */
interface DownloadGroup {
  comicId: string;
  title: string;
  coverUrl: string;
  coverLocal: string;
  description: string;
  author: string;
  downloadedCount: number;
  totalCount: number;
  hasDownloading: boolean;
  hasWaiting: boolean;
  hasFailed: boolean;
  failedFirst: DownloadTask | null;
  downloadingTitle: string;
  downloadingProgress: number;
  downloadingTotal: number;
  sizeBytes: number;
}

/** 下载列表（独立组件：订阅 DownloadManager 实时刷新） */
@Component
struct DownloadListView {
  @State tasks: DownloadTask[] = [];
  @StorageProp('bika_material_rev') materialRev: number = 0;
  private cb: (tasks: DownloadTask[]) => void = (tasks: DownloadTask[]) => {
    this.tasks = tasks;
  };

  aboutToAppear(): void {
    DownloadManager.getInstance().subscribe(this.cb);
  }

  aboutToDisappear(): void {
    DownloadManager.getInstance().unsubscribe(this.cb);
  }

  /** 分组 */
  private groups(): DownloadGroup[] {
    let map = new Map<string, DownloadGroup>();
    for (let t of this.tasks) {
      let g = map.get(t.comicId);
      if (!g) {
        g = {
          comicId: t.comicId,
          title: t.comicTitle,
          coverUrl: t.coverUrl ?? '',
          coverLocal: t.coverLocal ?? '',
          description: t.description ?? '',
          author: t.author ?? '',
          downloadedCount: 0,
          totalCount: 0,
          hasDownloading: false,
          hasWaiting: false,
          hasFailed: false,
          failedFirst: null,
          downloadingTitle: '',
          downloadingProgress: 0,
          downloadingTotal: 0,
          sizeBytes: 0
        };
        map.set(t.comicId, g);
      }
      g.totalCount++;
      if (t.status === 'completed') {
        g.downloadedCount++;
        g.sizeBytes += t.sizeBytes ?? 0;
      }
      if (t.status === 'downloading') {
        g.hasDownloading = true;
        g.downloadingTitle = t.chapterTitle;
        g.downloadingProgress = t.progress;
        g.downloadingTotal = t.total;
      }
      if (t.status === 'waiting') {
        g.hasWaiting = true;
      }
      if (t.status === 'failed') {
        g.hasFailed = true;
        if (!g.failedFirst) {
          g.failedFirst = t;
        }
      }
    }
    return Array.from(map.values());
  }

  private sizeLabel(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return (bytes / 1024).toFixed(0) + ' KB';
    }
    return bytes + ' B';
  }

  /** 删除整部作品的下载（原生确认框） */
  private confirmDeleteGroup(g: DownloadGroup): void {
    promptAction.showDialog({
      title: '删除下载',
      message: '删除《' + g.title + '》的全部已下载章节？本地文件将一并删除，且不可恢复。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '删除', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        let manager = DownloadManager.getInstance();
        for (let t of manager.getTasks()) {
          if (t.comicId === g.comicId) {
            manager.deleteTask(t.comicId, t.chapterOrder);
          }
        }
        promptAction.showToast({ message: '已删除', duration: 1600 });
      }
    }).catch((err: Error) => {
      console.warn('[DownloadListView] delete dialog failed: ' + JSON.stringify(err));
    });
  }

  build() {
    if (this.groups().length === 0) {
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(36)
          .fontColor([COLOR_TEXT_DISABLED])
        Text('暂无下载任务')
          .fontSize(14)
          .fontColor(COLOR_TEXT_HINT)
        Text('在漫画详情页点击下载即可离线阅读')
          .fontSize(12)
          .fontColor(COLOR_TEXT_HINT)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(COLOR_BG)
    } else {
      List({ space: 12 }) {
        ForEach(this.groups(), (g: DownloadGroup) => {
          ListItem() {
            Row() {
              if (g.coverLocal.length > 0) {
                NetImage({
                  src: 'file://' + g.coverLocal,
                  fit: ImageFit.Cover,
                  radius: 10,
                  fillParent: true
                })
                  .width(76)
                  .height(100)
              } else {
                NetImage({
                  src: g.coverUrl,
                  fit: ImageFit.Cover,
                  radius: 10,
                  fillParent: true
                })
                  .width(76)
                  .height(100)
              }
              Column({ space: 6 }) {
                Text(g.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (g.author.length > 0) {
                  Text(g.author)
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_HINT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (g.description.length > 0) {
                  Text(g.description)
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Row() {
                  Text('已下载 ' + g.downloadedCount + '/' + g.totalCount + ' 话')
                    .fontSize(12)
                    .fontColor(g.downloadedCount === g.totalCount ? COLOR_PRIMARY : COLOR_TEXT_HINT)
                  if (g.sizeBytes > 0) {
                    Text(' · ' + this.sizeLabel(g.sizeBytes))
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_HINT)
                      .margin({ left: 4 })
                  }
                  Blank()
                  if (g.hasDownloading) {
                    Text('下载中')
                      .fontSize(11)
                      .fontColor(COLOR_PRIMARY)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor(COLOR_PRIMARY_TINT)
                      .borderRadius(8)
                  } else if (g.hasWaiting) {
                    Text('等待中')
                      .fontSize(11)
                      .fontColor(COLOR_TEXT_SECONDARY)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .backgroundColor(COLOR_INPUT_BG)
                      .borderRadius(8)
                  }
                }
                .width('100%')
                if (g.hasDownloading) {
                  Text('正在下载：' + (g.downloadingTitle.length > 0 ? g.downloadingTitle : ('第' + (g.downloadedCount + 1) + '话')))
                    .fontSize(11)
                    .fontColor(COLOR_TEXT_HINT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row() {
                    Progress({
                      value: g.downloadingTotal > 0 ? g.downloadingProgress * 100 / g.downloadingTotal : 0,
                      type: ProgressType.Linear
                    })
                      .height(4)
                      .layoutWeight(1)
                      .color(COLOR_PRIMARY)
                      .backgroundColor(COLOR_PRIMARY_TINT)
                    Text(g.downloadingTotal > 0 ? Math.round(g.downloadingProgress * 100 / g.downloadingTotal) + '%' : '等待中')
                      .fontSize(11)
                      .fontColor(COLOR_PRIMARY)
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                } else if (g.hasWaiting) {
                  if (DownloadManager.getInstance().getWifiOnly() && !DownloadManager.getInstance().isWifiNow()) {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.wifi'))
                        .fontSize(13)
                        .fontColor([COLOR_TEXT_HINT])
                      Text('等待 WiFi，连接后自动下载')
                        .fontSize(11)
                        .fontColor(COLOR_TEXT_HINT)
                    }
                    .width('100%')
                  } else {
                    Text('排队中，即将开始…')
                      .fontSize(11)
                      .fontColor(COLOR_TEXT_HINT)
                      .width('100%')
                  }
                }
                if (g.hasFailed && g.failedFirst) {
                  Row() {
                    Text('下载失败：' + (g.failedFirst.chapterTitle.length > 0 ? g.failedFirst.chapterTitle : ('第' + g.failedFirst.chapterOrder + '话')))
                      .fontSize(11)
                      .fontColor('#C62828')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text('重试')
                      .fontSize(11)
                      .fontColor(COLOR_PRIMARY)
                      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                      .backgroundColor(COLOR_PRIMARY_TINT)
                      .borderRadius(10)
                      .margin({ left: 8 })
                      .onClick(() => {
                        DownloadManager.getInstance().retryTask(g.failedFirst!.comicId, g.failedFirst!.chapterOrder);
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })

              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([COLOR_TEXT_HINT])
                .padding(6)
                .alignSelf(ItemAlign.Start)
                .onClick(() => {
                  this.confirmDeleteGroup(g);
                })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(COLOR_CARD)
            .borderRadius(16)
            .border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ComicDetailPage',
                params: { comicId: g.comicId, comicTitle: g.title }
              });
            })
          }
        }, (g: DownloadGroup) => g.comicId)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
  }
}

/** 沉浸光感档位下拉（原样式；组件级 @StorageLink 保证在设置页内即时刷新） */
@Component
struct MaterialLevelSelect {
  @StorageLink('bika_material_level') level: string = 'EXQUISITE';
  @State popScale: number = 1;

  private label(): string {
    for (let i = 0; i < MATERIAL_OPTIONS.length; i++) {
      if (MATERIAL_OPTIONS[i].value === this.level) {
        return MATERIAL_OPTIONS[i].label;
      }
    }
    return '强';
  }

  build() {
    Row({ space: 4 }) {
      Text(this.label())
        .fontSize(15)
        .fontColor(COLOR_PRIMARY)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([COLOR_PRIMARY])
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .scale({ x: this.popScale, y: this.popScale })
    .bindMenu(MATERIAL_OPTIONS.map((opt: MaterialOption): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          // 与显示模式一致的动画过渡：先弹簧弹跳，再渐变应用新档位
          let animOn = AppStorage.get<boolean>('bika_animations') ?? true;
          if (animOn) {
            animateTo({ duration: 130, curve: Curve.EaseOut }, () => {
              this.popScale = 1.12;
            });
            animateTo({ duration: 320, curve: curves.springMotion(0.55, 0.85) }, () => {
              this.popScale = 1;
              this.level = opt.value;
              let r = AppStorage.get<number>('bika_material_rev') ?? 0;
              AppStorage.setOrCreate('bika_material_rev', r + 1);
            });
          } else {
            this.level = opt.value;
            let r = AppStorage.get<number>('bika_material_rev') ?? 0;
            AppStorage.setOrCreate('bika_material_rev', r + 1);
          }
          CacheManager.getInstance().then(c => c.saveSetting('material_level', opt.value));
        }
      };
    }))
  }
}

/** 更新日志条目 */
interface ChangelogEntry {
  version: string;
  date: string;
  items: string[];
}

/** 更新弹窗正文块 */
interface UpdateBlock {
  kind: string;
  text: string;
}

/** 行内富文本段 */
interface MdRun {
  text: string;
  bold: boolean;
}

/** 更新日志（可折叠列表） */
const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  {
    version: '1.3.5',
    date: '2026-08-31',
    items: [
      '修复：首页「推荐」分区改为全部漫画最新分页流',
      '修复：分类列表接口响应解析错误导致全部分类空白',
      '修复：分类页排序/筛选请求（移除冗余重试导致的频控）'
    ]
  },
  {
    version: '1.3.4',
    date: '2026-08-30',
    items: [
      '修复：分类页（频道列表）内容加载失败时自动重试一次，补充空态与重试按钮',
      '修复：主页/收藏页底部留白不足，频道被底部导航栏遮挡',
      '详情页相关推荐接口未返回时回退「全部最新」列表'
    ]
  },
  {
    version: '1.3.3',
    date: '2026-08-20',
    items: [
      '平板适配：首页频道网格与作品列表按屏幕宽度自适应列数（平板最多 6 列）',
      '阅读器平板适配：内容限宽居中，两侧留黑不再撑满整屏'
    ]
  },
  {
    version: '1.3.2',
    date: '2026-08-19',
    items: [
      '修复：更新日志、隐私政策弹窗无法打开（多个底部弹窗互相冲突）',
      '修复：沉浸光感档位切换不即时生效（档位恢复统一下拉样式，材质强度即时应用）',
      '检查更新弹窗：更新说明适配 Markdown 排版（标题/列表/加粗）'
    ]
  },
  {
    version: '1.3.1',
    date: '2026-08-18',
    items: [
      '动画：全局动画开关（设置→常规），按钮弹簧/卡片按压/图片占位呼吸/阅读器工具栏过渡/页码胶囊/频道按压',
      '沉浸光感档位切换即时生效（底部导航栏）',
      '系统代理：规则模式 VPN 分流（设置→DNS 优化），无需全局模式',
      '下载管理：单作品删除按钮 + 修复本地文件无法删除的问题',
      '关于页新增 GitHub 项目主页链接',
      '修复：音量键偶发需按两次、弹窗打开时音量键仍翻页'
    ]
  },
  {
    version: '1.3.0',
    date: '2026-08-17',
    items: [
      '评论区：排序（最新/最早/最多赞）+ 分页加载',
      '漫画分享：ShareKit 系统分享面板',
      '阅读器：音量键翻页（音量上=下一页，音量下=上一页，设置可关）',
      '图片缓存：新增 200MB 磁盘缓存（三级缓存）',
      '图片拖拽：长按拖到中转站/其他应用（UDMF 系统拖拽）',
      '导出作品：当前章节导出 PDF / 图片压缩包（系统保存对话框，自定义位置与文件名）',
      '修复：下载弹窗与评论弹窗互相冲突失效'
    ]
  },
  {
    version: '1.2.0',
    date: '2026-08-15',
    items: [
      '登录页重写：用户名 + 密码登录（不支持邮箱登录）',
      '注册：用户名 + 昵称 + 密码 + 三道密保题',
      '屏蔽标签：设置中按关键词屏蔽，频道与搜索结果生效',
      '搜索历史：最近搜索记录与一键清空',
      '频道自定义：首页频道排序 / 隐藏 / 恢复默认',
      '资料编辑：个人签名修改',
      '改密码：账号与安全子页，成功后重新登录',
      '检查更新：对接 GitHub Release，可跳转下载',
      '保存图片到相册：SaveButton 安全控件（1.3.0 起由系统拖拽替代）'
    ]
  },
  {
    version: '1.1.0',
    date: '2026-08-13',
    items: [
      '浏览历史增强：封面缩略图、阅读时间显示',
      '浏览历史支持单条删除与一键清空（原生确认框）',
      '浏览历史异步加载修复',
      '全部设置持久化：显示模式/档位/自动签到/防截屏/下载/DNS 重启保留',
      '设置下拉框改为原生菜单，选项即时同步',
      '进入章节自动恢复上次阅读页（页级进度）',
      '阅读器多项修复：翻页手势、页码显示、底部工具栏'
    ]
  },
  {
    version: '1.0.10',
    date: '2026-08-12',
    items: [
      '阅读模式切换保留当前阅读位置',
      '修复上一话/下一话按钮点击无效',
      '本地离线阅读同样保存进度与历史记录',
      '阅读器底部工具栏恢复悬浮毛玻璃（position+offset 定位）',
      '修复进入章节页码错乱与单页模式手势翻页',
      '离线场景翻话按钮按已下载任务计算话数'
    ]
  },
  {
    version: '1.0.9',
    date: '2026-08-11',
    items: [
      '防截屏修复：补声明 ohos.permission.PRIVACY_WINDOW 权限（安装即授予）',
      '防截屏开关提示文案修正',
      '评论弹窗改用系统原生标题（关闭按钮不重叠）',
      '评论失败提示中文化（等级不足说明）',
      '阅读器设置面板改为系统 bindSheet 弹窗样式'
    ]
  },
  {
    version: '1.0.8',
    date: '2026-08-10',
    items: [
      '首页顶部遮罩恢复整层覆盖（状态栏区域也带玻璃遮罩）',
      '退出登录改为紧贴菜单卡下方，与上部卡片平齐'
    ]
  },
  {
    version: '1.0.7',
    date: '2026-08-09',
    items: [
      'DNS 优化全面升级：分流线路拉取 + IP 握手测速 + 应用最低延迟 + 线路点选',
      'DNS 选择实时生效（API 与图片各自直连所选 IP），支持重置默认',
      '防截屏改为启动即应用 + 开关即时生效（主窗口单例）',
      '退出登录位置上移'
    ]
  },
  {
    version: '1.0.6',
    date: '2026-08-08',
    items: [
      '设置页统一规格重建：分区标题、图标、行高与字号全部一致',
      '显示模式改为统一下拉框，沉浸光感/常规/下载卡片规范化',
      '底部导航下移、顶部遮罩收窄、退出登录位置上移',
      '修复设置内嵌套子页返回后导航栏提前出现的问题'
    ]
  },
  {
    version: '1.0.5',
    date: '2026-08-07',
    items: [
      '设置新增常规项：自动签到 / 防截屏 / 清理图片缓存',
      '新增存储与空间管理（下载占用、缓存占用、一键清理）',
      '新增 DNS 优化（直连 IP 池查看、强制刷新、恢复默认）',
      '退出登录移至页面底部，底部导航位置微调'
    ]
  },
  {
    version: '1.0.4',
    date: '2026-08-06',
    items: [
      '修复所有滚动页面内容垂直居中问题',
      '首页/我的/收藏/搜索/频道/详情等页面内容统一从顶部排布'
    ]
  },
  {
    version: '1.0.3',
    date: '2026-08-06',
    items: [
      '设置子页全部改为从顶部排布',
      '底部导航与卡片全面接入沉浸光感材质（档位可调）',
      '关于页：更新日志折叠卡片 + 隐私政策',
      '评论点赞 / 回复 / 发表，子回复展开',
      '阅读器：横竖屏锁定 + 亮度调节',
      '下载：仅 WiFi 下载、并发数设置、失败重试、本地离线阅读'
    ]
  },
  {
    version: '1.0.2',
    date: '2026-08-05',
    items: [
      '频道筛选：主题/排除主题/状态/话数/页数五组筛选',
      '签到状态记忆，防止重复签到',
      '关于弹窗与更新日志（可折叠 + 进场动画）',
      '深浅色模式切换',
      '首页/详情/阅读器沉浸式体验优化'
    ]
  },
  {
    version: '1.0.1',
    date: '2026-08-04',
    items: [
      '首页频道：推荐/排行榜/最近更新/随机本子等 45 个频道',
      '漫画详情：详情/章节/评论三 Tab + 相关推荐 + 收藏点赞',
      '阅读器：五种阅读模式 + 沉浸工具栏 + 设置面板',
      '我的：收藏/历史/通知/我的评论/设置',
      '搜索：关键词推荐 + 高级搜索 + 排序'
    ]
  },
  {
    version: '1.0.0',
    date: '2026-08-04',
    items: [
      '初始版本',
      '账号登录与资料同步（头像/昵称/等级/签名）',
      '图片加载：自有网络栈 + 缓存 + 镜像回退'
    ]
  }
];

/** 菜单项 */
interface MenuItemData {
  icon: Resource;
  label: string;
  page: string;
}

/** 沉浸光感档位选项 */
interface MaterialOption {
  value: string;
  label: string;
}

const MATERIAL_OPTIONS: MaterialOption[] = [
  { value: 'EXQUISITE', label: '强' },
  { value: 'GENTLE', label: '均衡' },
  { value: 'SMOOTH', label: '弱' },
  { value: 'ADAPTIVE', label: '自适应' }
];

/** 显示模式选项 */
const COLOR_MODE_OPTIONS: MaterialOption[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' }
];

@Component
struct ProfilePage {
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  // 主题强调色：哔咔粉（保留哔咔主题色）
  private accentColor: ResourceColor = $r('app.color.bika_primary');
  /** 强调色 hex（沉浸光感点光用） */
  private accentHex: string = '#FF7CA8';
  @State profileError: string = '';
  @State userName: string = '';
  @State avatarUrl: string = '';
  @State userTitle: string = '';
  @State userLevel: number = 0;
  @State userExp: number = 0;
  @State slogan: string = '';
  @State profileLoaded: boolean = false;
  private apiService: ApiService = ApiService.getInstance();
  private cache: CacheManager | null = null;
  private stack: NavPathStack = new NavPathStack();

  // ── 子页面数据状态 ──
  @State favComics: ComicViewModel[] = [];
  @State favSort: string = 'dd';
  @State favPage: number = 1;
  @State favHasMore: boolean = false;
  @State favLoading: boolean = false;
  @State notifications: BikaNotification[] = [];
  @State notifLoading: boolean = false;
  @State myComments: BikaComment[] = [];
  @State commentsLoading: boolean = false;
  @State historyItems: HistoryItem[] = [];
  @StorageLink('bika_color_mode') colorMode: string = 'system';
  /** 下载设置 */
  @State downloadWifiOnly: boolean = false;
  @State downloadConcurrent: number = 1;
  /** 常规设置 */
  @State autoPunch: boolean = false;
  @State secureScreen: boolean = false;
  /** 存储占用（字节） */
  @State downloadSizeBytes: number = 0;
  @State cacheSizeBytes: number = 0;
  @State storageRefreshing: boolean = false;
  /** 屏蔽标签 */
  @State blockedTags: string[] = [];
  @State keywordTags: string[] = [];
  @State blockedLoading: boolean = false;
  /** 资料编辑 */
  @State editSlogan: string = '';
  @State editBirthday: string = '2000-01-01';
  @State editGender: string = 'm';
  @State editSaving: boolean = false;
  /** 改密码 */
  @State oldPassword: string = '';
  @State newPassword: string = '';
  @State confirmNewPassword: string = '';
  @State passwordSaving: boolean = false;
  /** 检查更新 */
  @State checkingUpdate: boolean = false;
  @State updateVersion: string = '';
  @State updateBody: string = '';
  @State updateUrl: string = '';
  /** DNS 分流线路状态 */
  @State dnsLines: Map<string, DnsIpEntry[]> = new Map();
  @State dnsFetching: boolean = false;
  @State dnsTesting: boolean = false;
  @State dnsError: string = '';
  @State dnsApiIps: string[] = [];
  @State dnsImageIps: string[] = [];
  @State punching: boolean = false;
  @StorageLink('download_revision') @Watch('onDownloadChanged') downloadRevision: number = 0;
  @State downloadList: DownloadTask[] = [];
  @State punched: boolean = false;
  /** 关于弹窗（bindSheet） */
  @State showAboutSheet: boolean = false;
  @State expandedAboutVersion: string = '1.0.0';
  @State aboutEntered: boolean = false;
  /** 弹窗类型：0 关闭 1 更新日志 2 隐私政策 */
  @State aboutSheetKind: number = 0;
  /** 沉浸光感档位（与 IndexPage 页签联动） */
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';
  /** 动画效果开关 */
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  /** 使用系统代理（规则模式 VPN） */
  @StorageLink('bika_use_proxy') useProxy: boolean = false;

  /** 菜单（点击进入子页面） */
  private menuItems: MenuItemData[] = [
    { icon: $r('sys.symbol.heart'), label: '我的收藏', page: 'favourites' },
    { icon: $r('sys.symbol.clock'), label: '浏览历史', page: 'history' },
    { icon: $r('sys.symbol.square_and_arrow_down'), label: '我的下载', page: 'downloads' },
    { icon: $r('sys.symbol.bell'), label: '通知', page: 'notifications' },
    { icon: $r('sys.symbol.message'), label: '我的评论', page: 'comments' },
    { icon: $r('sys.symbol.gearshape'), label: '设置', page: 'settings' }
  ];

  aboutToAppear(): void {
    AppStorage.set('isLoggedIn', this.apiService.isLoggedIn());
    this.downloadWifiOnly = DownloadManager.getInstance().getWifiOnly();
    this.downloadConcurrent = DownloadManager.getInstance().getMaxConcurrent();
    this.autoPunch = AppStorage.get<boolean>('bika_auto_punch') === true;
    this.secureScreen = AppStorage.get<boolean>('bika_secure_screen') === true;
    this.applySecureScreen();
    if (this.apiService.isLoggedIn()) {
      this.loadProfile();
    }
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
    });
  }

  /** 登录态变化：登录成功自动拉取资料 */
  onLoginStateChanged(): void {
    if (this.isLoggedIn) {
      this.loadProfile();
    }
  }

  /** 拉取并展示用户资料 */
  async loadProfile(): Promise<void> {
    this.profileError = '';
    try {
      let user = await this.apiService.getUserProfile();
      this.userName = user.name || '';
      this.userTitle = user.title || '';
      this.userLevel = user.level ?? 0;
      this.userExp = user.exp ?? 0;
      this.slogan = user.slogan || '';
      this.editSlogan = user.slogan || '';
      this.editBirthday = user.birthday || '2000-01-01';
      this.editGender = user.gender || 'm';
      this.punched = !!user.isPunched;
      if (user.avatar && user.avatar.path) {
        this.avatarUrl = buildImageUrl(user.avatar);
        AppStorage.set('avatarUrl', this.avatarUrl);
      }
      this.profileLoaded = true;
      console.info('[ProfilePage] profile loaded: ' + this.userName + ' LV.' + this.userLevel);
      this.maybeAutoPunch();
    } catch (err) {
      this.profileError = (err as Error).message || '加载失败';
      console.warn('[ProfilePage] loadProfile failed: ' + this.profileError);
    }
  }

  /** 自动签到（开启后每天首次打开自动打卡，当天只签一次） */
  private async maybeAutoPunch(): Promise<void> {
    if (!this.autoPunch || this.punched || this.punching) {
      return;
    }
    let today = new Date();
    let day = today.getFullYear() + '-' + (today.getMonth() + 1) + '-' + today.getDate();
    if (AppStorage.get<string>('bika_last_punch_day') === day) {
      return;
    }
    this.punching = true;
    try {
      await this.apiService.punchIn();
      this.punched = true;
      AppStorage.set('bika_last_punch_day', day);
      promptAction.showToast({ message: '自动签到成功', duration: 1600 });
    } catch (err) {
      console.warn('[ProfilePage] auto punch failed: ' + JSON.stringify(err));
    } finally {
      this.punching = false;
    }
  }

  /** 应用防截屏开关（ArkUI 原生窗口 API，主窗口单例） */
  private applySecureScreen(): void {
    WindowHelper.applyPrivacyMode(this.secureScreen).catch((err: Error) => {
      console.warn('[ProfilePage] privacy mode failed: ' + JSON.stringify(err));
    });
  }

  /** 清理图片缓存（原生确认对话框） */
  private confirmClearImageCache(): void {
    promptAction.showDialog({
      title: '清理图片缓存',
      message: '将清除章节图片列表、列表页与分类缓存，不影响已下载的漫画。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清理', color: '#FF7CA8' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        ImageLoader.clearCache();
        CacheManager.getInstance().then((cache: CacheManager) => {
          let count = cache.clearImageCache();
          promptAction.showToast({ message: '已清除 ' + count + ' 项缓存', duration: 1600 });
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear cache dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 刷新存储占用统计 */
  private refreshStorage(): void {
    this.storageRefreshing = true;
    this.downloadSizeBytes = DownloadManager.getInstance().getTotalSizeBytes();
    this.cacheSizeBytes = 0;
    try {
      let dir = getContext(this).preferencesDir;
      let files = fs.listFileSync(dir);
      for (let name of files) {
        try {
          this.cacheSizeBytes += fs.statSync(dir + '/' + name).size;
        } catch (err) {
        }
      }
    } catch (err) {
      console.warn('[ProfilePage] cache size calc failed: ' + JSON.stringify(err));
    }
    this.storageRefreshing = false;
  }

  /** 清空全部下载（原生确认对话框） */
  private confirmClearAllDownloads(): void {
    promptAction.showDialog({
      title: '清空全部下载',
      message: '将删除所有已下载漫画的本地文件，且不可恢复。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清空', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        DownloadManager.getInstance().clearAll();
        this.refreshStorage();
        promptAction.showToast({ message: '已清空全部下载', duration: 1600 });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear downloads dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 线路显示名 */
  private dnsLineName(key: string): string {
    if (key === 'unicom') {
      return '联通分流线路';
    }
    if (key === 'telecom') {
      return '电信分流线路';
    }
    if (key === 'mobile') {
      return '移动分流线路';
    }
    if (key === 'overseas') {
      return '海外分流线路';
    }
    return key + ' 分流线路';
  }

  /** 按固定顺序返回线路 key */
  private dnsLineKeys(): string[] {
    let keys = Array.from(this.dnsLines.keys());
    let order = ['unicom', 'telecom', 'mobile', 'overseas'];
    keys.sort((a: string, b: string) => {
      let ia = order.indexOf(a);
      let ib = order.indexOf(b);
      if (ia >= 0 && ib >= 0) {
        return ia - ib;
      }
      if (ia >= 0) {
        return -1;
      }
      if (ib >= 0) {
        return 1;
      }
      return a.localeCompare(b);
    });
    return keys;
  }

  /** 读取已保存的 DNS 选择 */
  private loadDnsSelection(): void {
    try {
      let apiRaw = AppStorage.get<string>('bika_dns_api_ips') ?? '';
      let imageRaw = AppStorage.get<string>('bika_dns_image_ips') ?? '';
      this.dnsApiIps = apiRaw.length > 0 ? JSON.parse(apiRaw) as string[] : [];
      this.dnsImageIps = imageRaw.length > 0 ? JSON.parse(imageRaw) as string[] : [];
    } catch (err) {
      this.dnsApiIps = [];
      this.dnsImageIps = [];
    }
  }

  /** 应用并持久化 DNS 选择 */
  private applyDnsSelection(apiIps: string[], imageIps: string[]): void {
    this.dnsApiIps = apiIps.slice(0);
    this.dnsImageIps = imageIps.slice(0);
    AppStorage.setOrCreate('bika_dns_api_ips', JSON.stringify(apiIps));
    AppStorage.setOrCreate('bika_dns_image_ips', JSON.stringify(imageIps));
    CacheManager.getInstance().then(c => {
      c.saveSetting('dns_api_ips', JSON.stringify(apiIps));
      c.saveSetting('dns_image_ips', JSON.stringify(imageIps));
    });
    ApiRouteManager.getInstance().applyCustomDns(apiIps, imageIps);
    // 刷新列表选中态
    let newMap = new Map<string, DnsIpEntry[]>();
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      let newList: DnsIpEntry[] = [];
      if (list) {
        for (let e of list) {
          newList.push({
            ip: e.ip,
            line: e.line,
            domain: e.domain,
            latency: e.latency,
            selected: e.domain === 'picacomic.com' ? imageIps.indexOf(e.ip) >= 0 : apiIps.indexOf(e.ip) >= 0
          });
        }
      }
      newMap.set(k, newList);
    }
    this.dnsLines = newMap;
    promptAction.showToast({ message: 'DNS 选择已生效', duration: 1600 });
  }

  /** 获取线路并测速（双源拉取 + TCP 握手测速） */
  private async fetchAndTestDns(): Promise<void> {
    if (this.dnsFetching || this.dnsTesting) {
      return;
    }
    this.dnsFetching = true;
    this.dnsError = '';
    try {
      let lines = await DnsService.fetchLines(this.dnsApiIps, this.dnsImageIps);
      if (lines.size === 0) {
        this.dnsError = '未能获取到任何 IP，请检查网络连接。';
        this.dnsFetching = false;
        return;
      }
      this.dnsLines = lines;
      this.dnsFetching = false;
      await this.testAllDnsLatencies();
    } catch (err) {
      this.dnsError = (err as Error).message || '拉取 IP 列表失败';
      this.dnsFetching = false;
    }
  }

  /** 并发 6 路测速全部 IP */
  private async testAllDnsLatencies(): Promise<void> {
    this.dnsTesting = true;
    let all: DnsIpEntry[] = [];
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      if (list) {
        all = all.concat(list);
      }
    }
    let idx = 0;
    let worker = async (): Promise<void> => {
      while (idx < all.length) {
        let entry = all[idx];
        idx++;
        let latency = await DnsService.testLatency(entry.ip);
        let updated: DnsIpEntry = {
          ip: entry.ip,
          line: entry.line,
          domain: entry.domain,
          latency: latency,
          selected: entry.selected
        };
        let newMap = new Map<string, DnsIpEntry[]>();
        let mapKeys = Array.from(this.dnsLines.keys());
        for (let k of mapKeys) {
          let list = this.dnsLines.get(k);
          let newList: DnsIpEntry[] = [];
          if (list) {
            for (let e of list) {
              newList.push(e.ip === entry.ip ? updated : e);
            }
          }
          newMap.set(k, newList);
        }
        this.dnsLines = newMap;
      }
    };
    let workers: Promise<void>[] = [];
    for (let i = 0; i < 6; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    this.dnsTesting = false;
  }

  /** 应用最低延迟 IP（API 与图片各自取最优） */
  private applyLowestLatencyDns(): void {
    let all: DnsIpEntry[] = [];
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      if (list) {
        all = all.concat(list);
      }
    }
    let bestApi = '';
    let bestApiLat = 999999;
    let bestImage = '';
    let bestImageLat = 999999;
    for (let e of all) {
      if (e.latency < 0) {
        continue;
      }
      if (e.domain === 'picaapi.picacomic.com' && e.latency < bestApiLat) {
        bestApi = e.ip;
        bestApiLat = e.latency;
      } else if (e.domain === 'picacomic.com' && e.latency < bestImageLat) {
        bestImage = e.ip;
        bestImageLat = e.latency;
      }
    }
    let apiIps = bestApi.length > 0 ? [bestApi] : this.dnsApiIps;
    let imageIps = bestImage.length > 0 ? [bestImage] : this.dnsImageIps;
    this.applyDnsSelection(apiIps, imageIps);
  }

  /** 选择某条线路 IP（同线路另一域名自动取最优） */
  private selectDnsIp(entry: DnsIpEntry): void {
    let newApi = this.dnsApiIps.slice(0);
    let newImage = this.dnsImageIps.slice(0);
    let lineList = this.dnsLines.get(entry.line);
    if (entry.domain === 'picacomic.com') {
      newImage = [entry.ip];
      if (lineList) {
        let apiList = lineList.filter(e => e.domain === 'picaapi.picacomic.com');
        let best = '';
        let bestLat = 999999;
        for (let e of apiList) {
          if (e.latency >= 0 && e.latency < bestLat) {
            best = e.ip;
            bestLat = e.latency;
          }
        }
        if (best.length === 0 && apiList.length > 0) {
          best = apiList[0].ip;
        }
        if (best.length > 0) {
          newApi = [best];
        }
      }
    } else {
      newApi = [entry.ip];
      if (lineList) {
        let imgList = lineList.filter(e => e.domain === 'picacomic.com');
        let best = '';
        let bestLat = 999999;
        for (let e of imgList) {
          if (e.latency >= 0 && e.latency < bestLat) {
            best = e.ip;
            bestLat = e.latency;
          }
        }
        if (best.length === 0 && imgList.length > 0) {
          best = imgList[0].ip;
        }
        if (best.length > 0) {
          newImage = [best];
        }
      }
    }
    this.applyDnsSelection(newApi, newImage);
  }

  /** 重置默认 DNS */
  private resetDns(): void {
    ApiRouteManager.getInstance().resetToDefault();
    ImageLoader.setCustomImageIps([]);
    this.dnsApiIps = [];
    this.dnsImageIps = [];
    AppStorage.setOrCreate('bika_dns_api_ips', '[]');
    AppStorage.setOrCreate('bika_dns_image_ips', '[]');
    CacheManager.getInstance().then(c => {
      c.saveSetting('dns_api_ips', '[]');
      c.saveSetting('dns_image_ips', '[]');
    });
    // 刷新选中态
    let newMap = new Map<string, DnsIpEntry[]>();
    let keys = Array.from(this.dnsLines.keys());
    for (let k of keys) {
      let list = this.dnsLines.get(k);
      let newList: DnsIpEntry[] = [];
      if (list) {
        for (let e of list) {
          newList.push({ ip: e.ip, line: e.line, domain: e.domain, latency: e.latency, selected: false });
        }
      }
      newMap.set(k, newList);
    }
    this.dnsLines = newMap;
    promptAction.showToast({ message: '已恢复默认 DNS', duration: 1600 });
  }

  /** 延迟显示 */
  private dnsLatencyLabel(entry: DnsIpEntry): string {
    if (entry.latency === -2) {
      return '测量中…';
    }
    if (entry.latency < 0) {
      return '超时';
    }
    return entry.latency + ' ms';
  }

  private sizeLabelForStorage(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes >= 1024 * 1024) {
      return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }
    if (bytes >= 1024) {
      return (bytes / 1024).toFixed(0) + ' KB';
    }
    return bytes + ' B';
  }

  onLogin(): void {
    if (!this.isLoggedIn) {
      router.pushUrl({ url: 'pages/LoginPage' });
    }
  }

  onLogout(): void {
    this.apiService.logout();
    this.isLoggedIn = false;
    try {
      promptAction.showToast({ message: '已退出登录', duration: 2000 });
    } catch (e) {
      console.error('[ProfilePage] toast error:', JSON.stringify(e));
    }
  }

  /** 签到 */
  async onPunchIn(): Promise<void> {
    if (this.punching) {
      return;
    }
    this.punching = true;
    try {
      await this.apiService.punchIn();
      this.punched = true;
      promptAction.showToast({ message: '签到成功', duration: 2000 });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '签到失败', duration: 2000 });
    } finally {
      this.punching = false;
    }
  }

  /** 打开子页面：底部导航动画收缩隐藏 */
  private openSubpage(name: string): void {
    if (!this.isLoggedIn && name !== 'settings' && name !== 'downloads' && name !== 'about' && name !== 'storage' && name !== 'dns' && name !== 'blocked' && name !== 'profile_edit' && name !== 'account') {
      router.pushUrl({ url: 'pages/LoginPage' });
      return;
    }
    AppStorage.set('bika_subpage_open', true);
    this.stack.pushPathByName(name, '');
    if (name === 'favourites') {
      this.loadFavourites(true);
    } else if (name === 'notifications') {
      this.loadNotifications();
    } else if (name === 'comments') {
      this.loadMyComments();
    } else if (name === 'history') {
      this.loadHistory();
    } else if (name === 'downloads') {
      // 强制同步任务列表（单例异步加载完成后刷新）
      this.downloadList = DownloadManager.getInstance().getTasks();
      setTimeout(() => {
        DownloadManager.getInstance().notify();
      }, 60);
    } else if (name === 'blocked') {
      this.loadBlockedTags();
      this.loadKeywordTags();
    } else if (name === 'profile_edit') {
      this.editSlogan = this.slogan;
    }
  }

  /** 读取屏蔽标签与候选关键词 */
  private loadBlockedTags(): void {
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      this.blockedTags = cache.loadBlockedTags();
    });
  }

  private async loadKeywordTags(): Promise<void> {
    if (this.blockedLoading) {
      return;
    }
    this.blockedLoading = true;
    try {
      this.keywordTags = await this.apiService.getKeywords();
    } catch (err) {
      console.warn('[ProfilePage] keywords failed: ' + JSON.stringify(err));
    } finally {
      this.blockedLoading = false;
    }
  }

  /** 切换屏蔽标签 */
  private toggleBlockedTag(tag: string): void {
    let arr = this.blockedTags.slice(0);
    let idx = arr.indexOf(tag);
    if (idx >= 0) {
      arr.splice(idx, 1);
    } else {
      arr.push(tag);
    }
    this.blockedTags = arr;
    AppStorage.set('bika_blocked_tags', JSON.stringify(arr));
    CacheManager.getInstance().then(c => {
      c.saveBlockedTags(arr);
    });
  }

  private closeSubpage(): void {
    this.stack.pop();
    // 只有完全退出子页面栈才恢复底部导航（设置→存储→返回时仍停留在设置页，导航保持隐藏）
    if (this.stack.size() === 0) {
      AppStorage.set('bika_subpage_open', false);
    }
  }

  // ── 子页面数据加载 ──
  private async loadFavourites(reset: boolean): Promise<void> {
    if (this.favLoading) {
      return;
    }
    this.favLoading = true;
    if (reset) {
      this.favPage = 1;
    }
    try {
      let result = await this.apiService.getFavourites(this.favSort, this.favPage);
      let vms = result.comics.map((c: BikaComicSummary) => ComicViewModel.fromSummary(c));
      this.favComics = reset ? vms : this.favComics.concat(vms);
      this.favHasMore = this.favPage < result.pages;
    } catch (err) {
      console.warn('[ProfilePage] favourites failed: ' + JSON.stringify(err));
    } finally {
      this.favLoading = false;
    }
  }

  private async loadNotifications(): Promise<void> {
    if (this.notifLoading) {
      return;
    }
    this.notifLoading = true;
    try {
      this.notifications = await this.apiService.getNotifications(1);
    } catch (err) {
      console.warn('[ProfilePage] notifications failed: ' + JSON.stringify(err));
    } finally {
      this.notifLoading = false;
    }
  }

  private async loadMyComments(): Promise<void> {
    if (this.commentsLoading) {
      return;
    }
    this.commentsLoading = true;
    try {
      this.myComments = await this.apiService.getMyComments(1);
    } catch (err) {
      console.warn('[ProfilePage] my comments failed: ' + JSON.stringify(err));
    } finally {
      this.commentsLoading = false;
    }
  }

  private loadHistory(): void {
    // 缓存单例可能尚未就绪，异步读取后再刷新列表
    CacheManager.getInstance().then(cache => {
      this.cache = cache;
      this.historyItems = cache.loadHistory();
    });
  }

  /** 历史时间显示 */
  private historyTimeLabel(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    let d = new Date(timestamp);
    let now = new Date();
    let pad = (n: number): string => n < 10 ? '0' + n : String(n);
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
      return '今天 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    return pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  /** 删除单条历史（原生确认框） */
  private confirmDeleteHistory(item: HistoryItem): void {
    promptAction.showDialog({
      title: '删除历史记录',
      message: '删除《' + item.title + '》的浏览记录？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        CacheManager.getInstance().then(cache => {
          cache.deleteHistoryItem(item.comicId);
          this.historyItems = cache.loadHistory();
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] delete history dialog failed: ' + JSON.stringify(err));
    });
  }

  /** 清空全部历史（原生确认框） */
  private confirmClearHistory(): void {
    promptAction.showDialog({
      title: '清空全部历史',
      message: '将删除所有浏览记录，且不可恢复。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '清空', color: '#C62828' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        CacheManager.getInstance().then(cache => {
          cache.clearHistory();
          this.historyItems = [];
        });
      }
    }).catch((err: Error) => {
      console.warn('[ProfilePage] clear history dialog failed: ' + JSON.stringify(err));
    });
  }

  private onDownloadChanged(): void {
    this.downloadList = DownloadManager.getInstance().getTasks();
  }

  private setColorMode(mode: string): void {
    // StorageLink 赋值即同步 AppStorage，Menu 下拉显示实时刷新
    this.colorMode = mode;
    CacheManager.getInstance().then(c => c.saveSetting('color_mode', mode));
    let ctx = getContext(this).getApplicationContext();
    if (mode === 'dark') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      ctx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  /** 沉浸光感档位（Select 辅助） */
  private labels(options: MaterialOption[]): string[] {
    return options.map((option: MaterialOption): string => option.label);
  }

  private selectOptions(options: MaterialOption[]): SelectOption[] {
    return this.labels(options).map((label: string): SelectOption => ({ value: label }));
  }

  private optionIndex(options: MaterialOption[], value: string): number {
    const index: number = options.findIndex((option: MaterialOption): boolean => option.value === value);
    return index < 0 ? 0 : index;
  }

  /** 应用材质档位（与 setColorMode 同款机制：赋值即同步 AppStorage + 持久化 + 全局修订号驱动重渲染） */
  private applyMaterialLevel(value: string): void {
    this.materialLevel = value;
    CacheManager.getInstance().then(c => c.saveSetting('material_level', value));
    // 修订号 +1：所有监听组件（含 IndexPage 的 HdsTabs key）立即重建应用新档位
    let rev = AppStorage.get<number>('bika_material_rev') ?? 0;
    AppStorage.setOrCreate('bika_material_rev', rev + 1);
  }

  private selectMaterial(index: number): void {
    const option: MaterialOption | undefined = MATERIAL_OPTIONS[index];
    if (option === undefined) {
      return;
    }
    this.applyMaterialLevel(option.value);
  }

  private selectColorModeOption(index: number): void {
    const option: MaterialOption | undefined = COLOR_MODE_OPTIONS[index];
    if (option === undefined) {
      return;
    }
    this.setColorMode(option.value);
  }

  /** 设置页统一下拉（原生 Menu；显示文字直接读 AppStorage，状态变化即时刷新） */
  @Builder
  settingSelect(options: MaterialOption[], storageKey: string, defaultValue: string,
    onSelect: (index: number) => void) {
    Row({ space: 4 }) {
      Text(this.labels(options)[this.optionIndex(options, AppStorage.get<string>(storageKey) ?? defaultValue)])
        .fontSize(15)
        .fontColor(COLOR_PRIMARY)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([COLOR_PRIMARY])
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .bindMenu(options.map((opt: MaterialOption, index: number): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          onSelect(index);
        }
      };
    }))
  }

  // ── 用户卡 ──
  @Builder
  userCard() {
    Column({ space: 10 }) {
      Row() {
        if (this.avatarUrl.length > 0) {
          NetImage({ src: this.avatarUrl, fit: ImageFit.Cover, radius: 32, fillParent: true })
            .width(64)
            .height(64)
        } else {
          Image($r('app.media.ic_default_avatar'))
            .width(64)
            .height(64)
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
            .backgroundColor(COLOR_PLACEHOLDER)
        }

        Column({ space: 4 }) {
          Text(this.profileError.length > 0
            ? '用户信息加载失败'
            : (this.userName.length > 0 ? this.userName : 'Bika 用户'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_TITLE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 8 }) {
            Text('LV.' + this.userLevel)
              .fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY)
            if (this.userTitle.length > 0) {
              Text(this.userTitle)
                .fontSize(10)
                .fontColor(COLOR_PRIMARY)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(COLOR_PRIMARY_TINT)
                .border({ width: 1, color: COLOR_PRIMARY })
                .borderRadius(4)
            }
          }
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 16 })
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([COLOR_PRIMARY])
          .padding(6)
          .onClick(() => {
            this.openSubpage('profile_edit');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('经验 ' + this.userExp)
          .fontSize(11)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(COLOR_PRIMARY_TINT_2)
          .borderRadius(4)
        Text(this.slogan.length > 0 ? this.slogan : '这个人很懒，什么都没写')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })

        Button(this.punched ? '已签到' : '签到', { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(this.punched ? COLOR_TEXT_SECONDARY : COLOR_WHITE)
          .backgroundColor(this.punched ? COLOR_PRIMARY_TINT : COLOR_PRIMARY)
          .borderRadius(14)
          .height(30)
          .padding({ left: 14, right: 14 })
          .enabled(!this.punching && !this.punched)
          .onClick(() => this.onPunchIn())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 账号与安全（我的页顶部账号区域）
      Divider()
        .margin({ top: 10, bottom: 2 })
      Row() {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(18)
          .fontColor([COLOR_TEXT_SECONDARY])
        Text('账号与安全')
          .fontSize(14)
          .fontColor(COLOR_TEXT_TITLE)
          .margin({ left: 10 })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([COLOR_TEXT_DISABLED])
      }
      .width('100%')
      .height(44)
      .onClick(() => {
        this.openSubpage('account');
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 6 })
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
  }

  /** 菜单列表（点击进入子页面） */
  @Builder
  menuList() {
    Column() {
      ForEach(this.menuItems, (item: MenuItemData, index: number) => {
        Row() {
          SymbolGlyph(item.icon)
            .fontSize(20)
            .fontColor([COLOR_TEXT_SECONDARY])
          Text(item.label)
            .fontSize(15)
            .fontColor(COLOR_TEXT_TITLE)
            .margin({ left: 12 })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([COLOR_TEXT_DISABLED])
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .onClick(() => this.openSubpage(item.page))
        if (index < this.menuItems.length - 1) {
          Divider().height(1).color(COLOR_DIVIDER).margin({ left: 48 })
        }
      }, (item: MenuItemData) => item.label)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    HdsNavigation(this.stack) {
      Column() {
        Scroll() {
          Column({ space: 12 }) {
            if (this.isLoggedIn) {
              this.userCard()
            } else {
              Row() {
                Image($r('app.media.ic_default_avatar'))
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .objectFit(ImageFit.Cover)
                Column({ space: 2 }) {
                  Text('未登录')
                    .fontSize(17)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('登录后同步收藏与评论')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 14 })
                .layoutWeight(1)

                Button('登录', { type: ButtonType.Normal })
                  .fontSize(14)
                  .fontColor(COLOR_WHITE)
                  .backgroundColor(COLOR_PRIMARY)
                  .borderRadius(18)
                  .height(36)
                  .padding({ left: 20, right: 20 })
                  .onClick(() => this.onLogin())
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            }

            this.menuList()

            // 退出登录：紧跟菜单卡下方，与上部平齐
            if (this.isLoggedIn) {
              Row() {
                SymbolGlyph($r('sys.symbol.rectangle_portrait_on_rectangle_portrait'))
                  .fontSize(20)
                  .fontColor([COLOR_TEXT_SECONDARY])
                Text('退出登录')
                  .fontSize(15)
                  .fontColor('#C62828')
                  .margin({ left: 12 })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
              .onClick(() => this.onLogout())
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + 16, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .backgroundColor(COLOR_BG)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAboutSheet, this.profileBottomSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      preferType: SheetType.BOTTOM,
      showClose: true,
      dragBar: false,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onWillDismiss: (): void => {
        this.showAboutSheet = false;
        this.aboutEntered = false;
        this.aboutSheetKind = 0;
      }
    })
  }

  /** 底部弹窗统一分发（单 bindSheet 避免多实例互顶）：aboutSheetKind 0=更新 1=更新日志 2=隐私政策 */
  @Builder
  profileBottomSheet() {
    if (this.aboutSheetKind === 0) {
      this.updateSheet()
    } else {
      this.aboutSheet()
    }
  }

  /** 子页返回头：自绘返回键 + 大标题，内容从上往下排布 */
  @Builder
  subpageHeader(title: string) {
    Column() {
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.accentColor])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(compatibleImmersiveMaterial(this.accentHex, false, true))
        .onClick(() => this.closeSubpage())
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
        Text(title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .padding({ top: this.topSafeHeight })
  }

  /** 子页面注册 */
  @Builder
  pageMap(name: string) {
    if (name === 'favourites') {
      this.favouritesDestination()
    } else if (name === 'history') {
      this.historyDestination()
    } else if (name === 'downloads') {
      this.downloadsDestination()
    } else if (name === 'notifications') {
      this.notificationsDestination()
    } else if (name === 'comments') {
      this.commentsDestination()
    } else if (name === 'settings') {
      this.settingsDestination()
    } else if (name === 'about') {
      this.aboutDestination()
    } else if (name === 'storage') {
      this.storageDestination()
    } else if (name === 'dns') {
      this.dnsDestination()
    } else if (name === 'blocked') {
      this.blockedTagsDestination()
    } else if (name === 'profile_edit') {
      this.profileEditDestination()
    } else if (name === 'account') {
      this.accountDestination()
    }
  }

  /** 我的收藏 */
  @Builder
  favouritesDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的收藏')
        Column() {
        Row() {
          ForEach(SORT_OPTIONS, (item: SortOption) => {
            Text(item.label)
              .fontSize(13)
              .fontColor(this.favSort === item.key ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.favSort === item.key ? COLOR_PRIMARY : COLOR_CARD)
              .borderRadius(15)
              .margin({ right: 8 })
              .onClick(() => {
                if (this.favSort !== item.key) {
                  this.favSort = item.key;
                  this.loadFavourites(true);
                }
              })
          }, (item: SortOption) => item.key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        Scroll() {
          Grid() {
            ForEach(this.favComics, (comic: ComicViewModel) => {
              GridItem() {
                ComicCard({ comic: comic })
              }
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/ComicDetailPage',
                  params: { comicId: comic.id, comicTitle: comic.title }
                });
              })
            }, (comic: ComicViewModel) => comic.id + '_' + this.favSort)
          }
          .columnsTemplate(adaptiveListColumns())
          .columnsGap(10)
          .rowsGap(12)
          .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafeHeight + 76 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onReachEnd(() => {
          if (this.favHasMore && !this.favLoading) {
            this.favPage++;
            this.loadFavourites(false);
          }
        })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 浏览历史 */
  @Builder
  historyDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('浏览历史')
        if (this.historyItems.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无浏览记录')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.historyItems, (item: HistoryItem, index: number) => {
              ListItem() {
                Row() {
                  if (item.coverUrl.length > 0) {
                    NetImage({
                      src: item.coverUrl,
                      fit: ImageFit.Cover,
                      radius: 8,
                      fillParent: true
                    })
                      .width(48)
                      .height(64)
                  } else {
                    Image($r('app.media.ic_default_avatar'))
                      .width(48)
                      .height(64)
                      .borderRadius(8)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(COLOR_PLACEHOLDER)
                  }
                  Column({ space: 4 }) {
                    Text(item.title)
                      .fontSize(15)
                      .fontColor(COLOR_TEXT_TITLE)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('看到第 ' + item.order + ' 话 · ' + this.historyTimeLabel(item.timestamp))
                      .fontSize(12)
                      .fontColor(COLOR_TEXT_HINT)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 12 })
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(18)
                    .fontColor([COLOR_TEXT_HINT])
                    .padding(6)
                    .onClick(() => {
                      this.confirmDeleteHistory(item);
                    })
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([COLOR_TEXT_DISABLED])
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/ComicDetailPage',
                    params: { comicId: item.comicId, comicTitle: item.title }
                  });
                })
              }
              if (index < this.historyItems.length - 1) {
                ListItem() {
                  Divider().height(1).color(COLOR_DIVIDER).margin({ left: 76 })
                }
              }
            }, (item: HistoryItem) => item.comicId)

            ListItem() {
              Row() {
                Text('清空全部历史')
                  .fontSize(14)
                  .fontColor('#C62828')
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.confirmClearHistory();
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的下载（独立组件订阅实时刷新） */
  @Builder
  downloadsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的下载')
        DownloadListView()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 通知 */
  @Builder
  notificationsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('通知')
        if (this.notifications.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.bell'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无通知')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
        } else {
        List({ space: 0 }) {
          ForEach(this.notifications, (n: BikaNotification, index: number) => {
            ListItem() {
              Row() {
                if (n._comic && n._comic.thumb && n._comic.thumb.path) {
                  NetImage({
                    src: buildImageUrl(n._comic.thumb),
                    fit: ImageFit.Cover,
                    radius: 10,
                    fillParent: true
                  })
                    .width(48)
                    .height(64)
                }
                Column({ space: 4 }) {
                  Text(n.content)
                    .fontSize(14)
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(n.created_at ? n.created_at.substring(0, 10) : '')
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            if (index < this.notifications.length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 76 })
              }
            }
          }, (n: BikaNotification) => n._id)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 我的评论 */
  @Builder
  commentsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('我的评论')
        if (this.myComments.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(36)
              .fontColor([COLOR_TEXT_DISABLED])
            Text('暂无评论')
              .fontSize(14)
              .fontColor(COLOR_TEXT_HINT)
          }
          .width('100%')
          .padding({ top: 60 })
          .alignItems(HorizontalAlign.Center)
        } else {
        List({ space: 0 }) {
          ForEach(this.myComments, (comment: BikaComment, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(comment.content)
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_TITLE)
                Row() {
                  Text(comment.created_at ? comment.created_at.substring(0, 10) : '')
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                  Blank()
                  Text('赞 ' + (comment.likesCount ?? 0))
                    .fontSize(10)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            if (index < this.myComments.length - 1) {
              ListItem() {
                Divider().height(1).color(COLOR_DIVIDER).margin({ left: 16 })
              }
            }
          }, (comment: BikaComment) => comment._id)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(COLOR_CARD)
          .borderRadius(18)
          .border({ width: 1, color: COLOR_DIVIDER })
          .margin({ top: 4, bottom: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 设置 */
  @Builder
  settingsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('设置')
        Scroll() {
        Column({ space: 14 }) {
          Text('外观')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('显示模式')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('跟随系统 / 浅色 / 深色')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              this.settingSelect(COLOR_MODE_OPTIONS, 'bika_color_mode', 'system', (index: number): void => {
                this.selectColorModeOption(index);
              })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Text('沉浸光感')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.paintbrush'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('档位')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('导航栏与卡片的材质强度')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              MaterialLevelSelect()
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Text('常规')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.wand_and_stars'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('动画效果')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('按钮动效、卡片按压、阅读器过渡等')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.animationsEnabled })
                .selectedColor(COLOR_PRIMARY)
                .onChange((checked: boolean) => {
                  this.animationsEnabled = checked;
                  AppStorage.setOrCreate('bika_animations', checked);
                  CacheManager.getInstance().then(c => c.saveSetting('animations', checked ? 'true' : 'false'));
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('自动签到')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('每天首次打开自动打卡')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoPunch })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.autoPunch = isOn;
                  AppStorage.setOrCreate('bika_auto_punch', isOn);
                  CacheManager.getInstance().then(c => c.saveSetting('auto_punch', isOn ? 'true' : 'false'));
                  if (isOn) {
                    this.maybeAutoPunch();
                  }
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.eye_slash'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('防截屏')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('截屏与录屏时隐藏内容')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.secureScreen })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.secureScreen = isOn;
                  AppStorage.setOrCreate('bika_secure_screen', isOn);
                  CacheManager.getInstance().then(c => c.saveSetting('secure_screen', isOn ? 'true' : 'false'));
                  this.applySecureScreen();
                  promptAction.showToast({
                    message: isOn ? '已开启防截屏，将禁止截屏/录屏功能' : '已关闭防截屏，恢复截屏/录屏功能',
                    duration: 1600
                  });
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('清理图片缓存')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('章节图片列表与列表页缓存')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.confirmClearImageCache())

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.externaldrive'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('存储与空间')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('下载、缓存占用与清理')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('storage'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('DNS 优化')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('直连与分流线路优化')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('dns'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.nosign'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('屏蔽标签')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('隐藏含指定标签的漫画')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('blocked'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.lock'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('账号与安全')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('修改登录密码')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.openSubpage('account'))
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Text('下载')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('仅 WiFi 下载')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('非 WiFi 时任务自动排队')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.downloadWifiOnly })
                .selectedColor(COLOR_PRIMARY)
                .onChange((isOn: boolean) => {
                  this.downloadWifiOnly = isOn;
                  DownloadManager.getInstance().setWifiOnly(isOn);
                  if (isOn && !DownloadManager.getInstance().isWifiNow()) {
                    promptAction.showToast({ message: '当前非 WiFi 网络，任务将等待 WiFi', duration: 2000 });
                  }
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('最大并发数')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('同时下载的章节数')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              ForEach([1, 2, 3, 5], (n: number) => {
                Text('' + n)
                  .fontSize(13)
                  .fontColor(this.downloadConcurrent === n ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
                  .textAlign(TextAlign.Center)
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor(this.downloadConcurrent === n ? COLOR_PRIMARY : COLOR_PRIMARY_TINT)
                  .margin({ left: 6 })
                  .onClick(() => {
                    this.downloadConcurrent = n;
                    DownloadManager.getInstance().setMaxConcurrent(n);
                  })
              }, (n: number) => '' + n)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Text('应用')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('检查更新')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text(this.checkingUpdate ? '正在检查…' : '检测 GitHub Release 新版本')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => this.checkUpdate())

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(20)
                .fontColor([this.accentColor])
              Column({ space: 3 }) {
                Text('关于')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('应用信息、更新日志与隐私政策')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Text('›')
                .fontSize(26)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.openSubpage('about');
            })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 关于子页 */
  @Builder
  aboutDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('关于')
        Scroll() {
        Column({ space: 14 }) {
          Text('应用信息')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 6 }) {
            Text('Bika')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_TITLE)
              .width('100%')
            Text('HarmonyOS 原生客户端')
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
            Text('版本 ' + CHANGELOG_ENTRIES[0].version)
              .fontSize(14)
              .fontColor(COLOR_TEXT_SECONDARY)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

          Text('文档')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('更新日志')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('查看版本功能变化')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .onClick(() => {
            this.openChangelog();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.doc_text'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('隐私政策')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('账户、资料、文件与网络说明')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .onClick(() => {
            this.openPrivacyPolicy();
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })

          Text('开源')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(20)
              .fontColor([this.accentColor])
            Column({ space: 3 }) {
              Text('GitHub 项目主页')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_TITLE)
              Text('github.com/LoMoCatAp/Bika-HarmonyOS')
                .fontSize(13)
                .fontColor(COLOR_TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('›')
              .fontSize(26)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
          .onClick(() => {
            this.openExternalLink('https://github.com/LoMoCatAp/Bika-HarmonyOS');
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 存储与空间子页 */
  @Builder
  storageDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('存储与空间')
        Scroll() {
          Column({ space: 12 }) {
            Column() {
              Text('下载')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              Row() {
                Column({ space: 3 }) {
                  Text('已下载漫画占用')
                    .fontSize(15)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text(this.storageRefreshing ? '计算中…' : this.sizeLabelForStorage(this.downloadSizeBytes))
                    .fontSize(13)
                    .fontColor(COLOR_PRIMARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('清空')
                  .fontSize(14)
                  .fontColor('#C62828')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(COLOR_PRIMARY_TINT)
                  .borderRadius(14)
                  .onClick(() => this.confirmClearAllDownloads())
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            Column() {
              Text('缓存')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              Row() {
                Column({ space: 3 }) {
                  Text('图片与页面缓存')
                    .fontSize(15)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('内存 ' + ImageLoader.cachedCount() + ' 张 · 磁盘 ' +
                    this.sizeLabelForStorage(this.cacheSizeBytes))
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('清理')
                  .fontSize(14)
                  .fontColor(COLOR_PRIMARY)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(COLOR_PRIMARY_TINT)
                  .borderRadius(14)
                  .onClick(() => {
                    this.confirmClearImageCache();
                    setTimeout(() => this.refreshStorage(), 600);
                  })
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            Row() {
              Text('刷新统计')
                .fontSize(15)
                .fontColor(COLOR_PRIMARY)
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .onClick(() => this.refreshStorage())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
    .onShown(() => {
      this.refreshStorage();
    })
  }

  /** DNS 直连与分流优化子页 */
  @Builder
  dnsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('DNS 直连与分流优化')
        if (this.dnsFetching) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(COLOR_PRIMARY)
            Text('正在获取分流线路…')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PRIMARY_TINT)
        } else if (this.dnsTesting) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(COLOR_PRIMARY)
            Text('正在测量 IP 握手延迟…')
              .fontSize(13)
              .fontColor(COLOR_TEXT_SECONDARY)
          }
          .width('100%')
          .height(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PRIMARY_TINT)
        }
        Scroll() {
          Column({ space: 12 }) {
            // 系统代理开关
            Column({ space: 0 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.dot_radiowaves'))
                  .fontSize(20)
                  .fontColor([this.accentColor])
                Column({ space: 3 }) {
                  Text('使用系统代理')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('规则模式 VPN（Clash / v2rayN 等）')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.useProxy })
                  .selectedColor(COLOR_PRIMARY)
                  .onChange((checked: boolean) => {
                    this.useProxy = checked;
                    ApiService.setUseSystemProxy(checked);
                    CacheManager.getInstance().then(c => c.saveSetting('use_system_proxy', checked ? 'true' : 'false'));
                    promptAction.showToast({
                      message: checked ? '已切换系统代理：请求由代理按域名分流' : '已切回应用内 DNS 直连',
                      duration: 2000
                    });
                  })
              }
              .width('100%')
              .height(58)
              .padding({ left: 16, right: 16 })
              Text('在代理工具的"设置"中打开"允许来自局域网的连接/系统代理"，本开关开启后所有请求改为域名直发，由代理按规则分流，无需全局模式。')
                .fontSize(12)
                .fontColor(COLOR_TEXT_HINT)
                .lineHeight(18)
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 10 })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            // 当前生效 IP
            Column({ space: 8 }) {
              Text('当前生效的直连 IP')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLOR_TEXT_TITLE)
                .width('100%')
              Row() {
                Column({ space: 2 }) {
                  Text('API 线路')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                  Text(this.dnsApiIps.length > 0 ? this.dnsApiIps.join(', ') : '默认系统解析')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Column({ space: 2 }) {
                  Text('图片存储')
                    .fontSize(12)
                    .fontColor(COLOR_TEXT_SECONDARY)
                  Text(this.dnsImageIps.length > 0 ? this.dnsImageIps.join(', ') : '默认系统解析')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily('monospace')
                    .fontColor(COLOR_TEXT_TITLE)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 16 })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(16)
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            // 操作按钮
            Row({ space: 12 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(16)
                    .fontColor([COLOR_WHITE])
                  Text('获取并测速')
                    .fontSize(14)
                    .fontColor(COLOR_WHITE)
                }
              }
              .layoutWeight(1)
              .height(42)
              .backgroundColor(COLOR_PRIMARY)
              .borderRadius(21)
              .enabled(!this.dnsFetching && !this.dnsTesting)
              .onClick(() => {
                this.fetchAndTestDns();
              })

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.bolt'))
                    .fontSize(16)
                    .fontColor([COLOR_PRIMARY])
                  Text('应用最低延迟')
                    .fontSize(14)
                    .fontColor(COLOR_PRIMARY)
                }
              }
              .layoutWeight(1)
              .height(42)
              .backgroundColor(COLOR_PRIMARY_TINT)
              .borderRadius(21)
              .enabled(!this.dnsFetching && !this.dnsTesting && this.dnsLines.size > 0)
              .onClick(() => {
                this.applyLowestLatencyDns();
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // 错误提示
            if (this.dnsError.length > 0) {
              Text(this.dnsError)
                .fontSize(13)
                .fontColor('#C62828')
                .width('100%')
                .padding(12)
                .backgroundColor('#FDECEC')
                .borderRadius(12)
            }

            // 分流线路列表
            ForEach(this.dnsLineKeys(), (lineKey: string) => {
              Column({ space: 8 }) {
                Text(this.dnsLineName(lineKey))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLOR_TEXT_TITLE)
                  .width('100%')
                ForEach(this.dnsLines.get(lineKey) as DnsIpEntry[], (entry: DnsIpEntry) => {
                  Row({ space: 8 }) {
                    Text(entry.ip)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontFamily('monospace')
                      .fontColor(COLOR_TEXT_TITLE)
                    Text(entry.domain === 'picacomic.com' ? '图片' : 'API')
                      .fontSize(10)
                      .fontColor(entry.domain === 'picacomic.com' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(entry.domain === 'picacomic.com' ? COLOR_PRIMARY_TINT : COLOR_INPUT_BG)
                      .borderRadius(4)
                    Blank()
                    Text(this.dnsLatencyLabel(entry))
                      .fontSize(12)
                      .fontColor(entry.latency < 0 ? '#C62828' : COLOR_TEXT_SECONDARY)
                    if (entry.selected) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle'))
                        .fontSize(18)
                        .fontColor([COLOR_PRIMARY])
                    }
                  }
                  .width('100%')
                  .padding(14)
                  .backgroundColor(entry.selected ? COLOR_PRIMARY_TINT : Color.Transparent)
                  .borderRadius(12)
                  .border({ width: entry.selected ? 2 : 1, color: entry.selected ? COLOR_PRIMARY : COLOR_DIVIDER })
                  .onClick(() => this.selectDnsIp(entry))
                }, (entry: DnsIpEntry) => entry.domain + '_' + entry.ip)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .margin({ top: 4 })
            }, (lineKey: string) => lineKey)

            if (this.dnsLines.size === 0 && !this.dnsFetching) {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(36)
                  .fontColor([COLOR_TEXT_DISABLED])
                Text('尚未获取分流线路')
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_HINT)
                Text('点击「获取并测速」拉取可用的直连 IP')
                  .fontSize(12)
                  .fontColor(COLOR_TEXT_HINT)
              }
              .width('100%')
              .padding({ top: 40, bottom: 20 })
              .alignItems(HorizontalAlign.Center)
            }

            // 重置默认
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(20)
                .fontColor([COLOR_TEXT_SECONDARY])
              Text('重置默认')
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .margin({ left: 12 })
                .layoutWeight(1)
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .onClick(() => this.resetDns())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
    .onShown(() => {
      this.loadDnsSelection();
    })
  }

  /** 屏蔽标签子页 */
  @Builder
  blockedTagsDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('屏蔽标签')
        Scroll() {
          Column({ space: 12 }) {
            Column() {
              Text('已屏蔽')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              if (this.blockedTags.length === 0) {
                Text('暂无屏蔽标签')
                  .fontSize(14)
                  .fontColor(COLOR_TEXT_HINT)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
              } else {
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.blockedTags, (tag: string) => {
                    Text(tag)
                      .fontSize(13)
                      .fontColor(COLOR_PRIMARY)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(COLOR_PRIMARY_TINT)
                      .border({ width: 1, color: COLOR_PRIMARY, radius: 15 })
                      .margin({ left: 16, bottom: 8 })
                      .onClick(() => this.toggleBlockedTag(tag))
                  }, (tag: string) => tag)
                }
                .width('100%')
                .padding({ bottom: 8 })
              }
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            Column() {
              Text('可选标签')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              if (this.blockedLoading && this.keywordTags.length === 0) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(COLOR_PRIMARY)
                  Text('加载标签中…')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_HINT)
                }
                .width('100%')
                .padding({ left: 16, bottom: 12 })
              } else {
                Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
                  ForEach(this.keywordTags, (tag: string) => {
                    Text(tag)
                      .fontSize(13)
                      .fontColor(this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY : COLOR_TEXT_TITLE)
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY_TINT : COLOR_CARD)
                      .border({
                        width: 1,
                        color: this.blockedTags.indexOf(tag) >= 0 ? COLOR_PRIMARY : COLOR_DIVIDER,
                        radius: 15
                      })
                      .margin({ left: 16, bottom: 8 })
                      .onClick(() => this.toggleBlockedTag(tag))
                  }, (tag: string) => tag)
                }
                .width('100%')
                .padding({ bottom: 8 })
              }
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

            Text('屏蔽后，频道列表与搜索结果将不再显示含该标签的漫画。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16, top: 4 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 资料编辑子页 */
  @Builder
  profileEditDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('编辑资料')
        Scroll() {
          Column({ space: 12 }) {
            Column() {
              Text('签名')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '写点什么介绍自己…', text: this.editSlogan })
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_PLACEHOLDER)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.editSlogan = v;
                })

              Button(this.editSaving ? '保存中…' : '保存', { type: ButtonType.Normal })
                .fontSize(15)
                .fontColor(COLOR_WHITE)
                .backgroundColor(this.editSaving ? COLOR_TEXT_HINT : COLOR_PRIMARY)
                .borderRadius(22)
                .height(44)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 20 })
                .enabled(!this.editSaving)
                .onClick(() => {
                  this.saveProfileEdit();
                })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .padding({ bottom: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 账号与安全子页（改密码） */
  @Builder
  accountDestination() {
    HdsNavDestination() {
      Column() {
        this.subpageHeader('账号与安全')
        Scroll() {
          Column({ space: 12 }) {
            Column() {
              Text('当前密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '请输入当前密码', text: this.oldPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_PLACEHOLDER)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.oldPassword = v;
                })
              Text('新密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '5-20 位，需包含数字、字母与符号', text: this.newPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_PLACEHOLDER)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.newPassword = v;
                })
              Text('确认新密码')
                .fontSize(13)
                .fontColor(COLOR_TEXT_HINT)
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 6 })
              TextInput({ placeholder: '再次输入新密码', text: this.confirmNewPassword })
                .type(InputType.Password)
                .fontSize(15)
                .fontColor(COLOR_TEXT_TITLE)
                .placeholderColor(COLOR_PLACEHOLDER)
                .backgroundColor(COLOR_INPUT_BG)
                .borderRadius(14)
                .height(46)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.confirmNewPassword = v;
                })
              Button(this.passwordSaving ? '提交中…' : '修改密码', { type: ButtonType.Normal })
                .fontSize(15)
                .fontColor(COLOR_WHITE)
                .backgroundColor(this.passwordSaving ? COLOR_TEXT_HINT : COLOR_PRIMARY)
                .borderRadius(22)
                .height(44)
                .width('calc(100% - 32vp)')
                .margin({ left: 16, right: 16, top: 20 })
                .enabled(!this.passwordSaving)
                .onClick(() => {
                  this.submitPasswordChange();
                })
            }
            .width('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(18)
            .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            .padding({ bottom: 16 })

            Text('修改成功后需要重新登录。')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 40 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }

  /** 保存资料编辑 */
  private async saveProfileEdit(): Promise<void> {
    if (this.editSaving) {
      return;
    }
    this.editSaving = true;
    try {
      await this.apiService.updateProfile(this.editSlogan);
      this.slogan = this.editSlogan;
      promptAction.showToast({ message: '资料已更新', duration: 1600 });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '保存失败', duration: 2000 });
    } finally {
      this.editSaving = false;
    }
  }

  /** 提交修改密码 */
  private async submitPasswordChange(): Promise<void> {
    if (this.oldPassword.length === 0) {
      promptAction.showToast({ message: '请输入当前密码', duration: 1600 });
      return;
    }
    if (this.newPassword.length < 5 || this.newPassword.length > 20) {
      promptAction.showToast({ message: '新密码需 5-20 位', duration: 1600 });
      return;
    }
    if (!/[0-9]/.test(this.newPassword) || !/[a-zA-Z]/.test(this.newPassword) || !/[^0-9a-zA-Z]/.test(this.newPassword)) {
      promptAction.showToast({ message: '新密码需包含数字、字母与符号', duration: 2000 });
      return;
    }
    if (this.newPassword !== this.confirmNewPassword) {
      promptAction.showToast({ message: '两次输入的新密码不一致', duration: 1600 });
      return;
    }
    if (this.passwordSaving) {
      return;
    }
    this.passwordSaving = true;
    try {
      await this.apiService.changePassword(this.oldPassword, this.newPassword);
      promptAction.showToast({ message: '密码已修改，请重新登录', duration: 2000 });
      this.apiService.logout();
      this.isLoggedIn = false;
      router.pushUrl({ url: 'pages/LoginPage' });
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || '修改失败', duration: 2000 });
    } finally {
      this.passwordSaving = false;
    }
  }

  /** 检查更新（GitHub Release） */
  private async checkUpdate(): Promise<void> {
    if (this.checkingUpdate) {
      return;
    }
    this.checkingUpdate = true;
    let request = http.createHttp();
    try {
      let response = await request.request(
        'https://api.github.com/repos/LoMoCatAp/Bika-HarmonyOS/releases/latest', {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      });
      if (response.responseCode !== 200) {
        promptAction.showToast({ message: '检查更新失败 (HTTP ' + response.responseCode + ')', duration: 2000 });
        return;
      }
      let data = JSON.parse(response.result as string) as Record<string, Object>;
      let tag = String(data['tag_name'] ?? '');
      let version = tag.startsWith('v') ? tag.substring(1) : tag;
      let current = AppStorage.get<string>('bika_current_version') ?? '1.1.0';
      if (version.length > 0 && version !== current) {
        this.updateVersion = version;
        this.updateBody = String(data['body'] ?? '');
        this.updateUrl = String(data['html_url'] ?? '');
        this.aboutSheetKind = 0;
        this.showAboutSheet = true;
        } else {
        promptAction.showToast({ message: '当前已是最新版本 v' + current, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '检查更新失败：' + (err as Error).message, duration: 2000 });
    } finally {
      this.checkingUpdate = false;
    }
  }

  /** Markdown 正文 → 纯文本块（原生无 Markdown 组件，做轻量转换） */
  private markdownLines(): UpdateBlock[] {
    let blocks: UpdateBlock[] = [];
    let raw = this.updateBody.length > 0 ? this.updateBody : '点击「去下载」前往 Release 页面';
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

  /** 行内 **加粗** 拆段 */
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

  /** 更新弹窗（Markdown 适配渲染） */
  @Builder
  updateSheet() {
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
    .backgroundColor(COLOR_CARD)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  /** 打开外部链接 */
  private openExternalLink(url: string): void {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      context.openLink(url);
    } catch (err) {
      promptAction.showToast({ message: '无法打开链接', duration: 1600 });
    }
  }

  /** 打开更新日志弹窗 */
  private openChangelog(): void {
    this.expandedAboutVersion = CHANGELOG_ENTRIES[0].version;
    this.aboutEntered = false;
    this.aboutSheetKind = 1;
    this.showAboutSheet = true;
    setTimeout((): void => {
      this.aboutEntered = true;
    }, 80);
  }

  /** 打开隐私政策弹窗 */
  private openPrivacyPolicy(): void {
    this.aboutEntered = false;
    this.aboutSheetKind = 2;
    this.showAboutSheet = true;
    setTimeout((): void => {
      this.aboutEntered = true;
    }, 80);
  }

  /** 关于弹窗（按类型分发） */
  @Builder
  aboutSheet() {
    if (this.aboutSheetKind === 1) {
      this.changelogSheet()
    } else {
      this.privacySheet()
    }
  }

  /** 更新日志弹窗 */
  @Builder
  changelogSheet() {
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
      .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))

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
              .attributeModifier(compatibleImmersiveMaterial(this.accentHex, true))
            }, (entry: ChangelogEntry): string => entry.version)
          }
          .width('100%')
        }
        .width('100%')
        .height(350)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .opacity(this.aboutEntered ? 1 : 0)
      .translate({ y: this.aboutEntered ? 0 : 24 })
      .scale({ x: this.aboutEntered ? 1 : 0.97, y: this.aboutEntered ? 1 : 0.97 })
      .animation({ duration: 420, curve: Curve.Friction })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }

  /** 隐私政策弹窗 */
  @Builder
  privacySheet() {
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
            Text('登录凭据仅保存在本机应用私有目录，用于访问哔咔 API。头像、昵称、等级等资料由哔咔服务器提供，本应用不作额外收集与上传。')
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
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
  }
}

/**
 * 根容器 — HdsTabs 悬浮页签（首页 / 我的）
 * 沉浸光感页签 + 子页面打开时页签收起动画
 */
@Entry
@Component
struct IndexPage {
  @StorageLink('bika_subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;
  @StorageLink('bika_goto_profile') @Watch('onGotoProfile') gotoProfile: number = 0;
  @StorageLink('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_rev') materialRev: number = 0;
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @State currentTab: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    AppStorage.setOrCreate('bika_material_level', this.materialLevel);
    let saved: number | undefined = AppStorage.get<number>('bika_active_tab') as number | undefined;
    if (saved === 0 || saved === 1) {
      this.currentTab = saved;
    }
    if (this.currentTab !== 0) {
      let controller: HdsTabsController = this.tabsController;
      setTimeout((): void => {
        controller.changeIndex(this.currentTab);
      }, 0);
    }
  }

  /** 子页面开合 → 页签收起/恢复动画 */
  onSubpageChanged(): void {
    if (this.subpageOpen) {
      this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    } else {
      this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  /** 首页头像 → 切到「我的」 */
  onGotoProfile(): void {
    if (this.gotoProfile > 0) {
      this.tabsController.changeIndex(1);
      this.currentTab = 1;
    }
  }

  onPageShow(): void {
    AppStorage.set('isLoggedIn', ApiService.getInstance().isLoggedIn());
  }

  /** 沉浸光感档位映射 */
  private hdsMaterialLevel(): hdsMaterial.MaterialLevel {
    if (this.materialLevel === 'EXQUISITE') {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (this.materialLevel === 'SMOOTH') {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    if (this.materialLevel === 'ADAPTIVE') {
      return hdsMaterial.MaterialLevel.ADAPTIVE;
    }
    return hdsMaterial.MaterialLevel.GENTLE;
  }

  @Builder
  tabLabel(index: number, label: string, symbol: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([this.currentTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
      Text(label)
        .fontSize(12)
        .fontColor(this.currentTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height(52)
    .backgroundColor('#00000000')
  }

  build() {
    HdsTabs({ index: this.currentTab, controller: this.tabsController }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.tabLabel(0, '首页', $r('sys.symbol.house')))

      TabContent() {
        ProfilePage()
      }
      .tabBar(this.tabLabel(1, '我的', $r('sys.symbol.person')))
    }
    // 子页打开期间冻结 key：避免重建销毁当前页（设置页会被踢回），关闭子页后再应用新档位
    .key(this.subpageOpen ? 'hds_tabs_stable' : ('hds_tabs_' + this.materialLevel + '_' + this.materialRev))
    .barOverlap(true)
    .animationDuration(0)
    .vertical(false)
    .barPosition(BarPosition.End)
    .divider({ mode: DividerMode.NONE })
    .barFloatingStyle({
      // 全屏窗口下抬起至手势条上方，再向下 10vp
      barBottomMargin: Math.max(0, this.bottomSafeHeight - 6),
      adaptToHandedness: true,
      lightColor: '#FF7CA8',
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: this.hdsMaterialLevel()
      }
    })
    .onChange((index: number): void => {
      this.currentTab = index;
      AppStorage.set('bika_active_tab', index);
    })
    .backgroundColor(COLOR_BG)
    .width('100%')
    .height('100%')
  }
}