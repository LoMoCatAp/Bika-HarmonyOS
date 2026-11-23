import { ACCENT_COLORS_KEY, AccentColors, DEFAULT_ACCENT_COLORS } from '../../common/AppearanceAccent';
import { showImmersiveToast } from '../../common/ImmersiveToast';
import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { CacheManager } from '../../common/CacheManager';
import { DownloadManager } from '../../common/DownloadManager';
import { COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_DIVIDER } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileSettingsPage {
  @StorageProp(ACCENT_COLORS_KEY) appearanceColors: AccentColors = DEFAULT_ACCENT_COLORS;
  settingsScroller: Scroller = new Scroller();
  @Link autoPunch: boolean;
  maybeAutoPunch: () => Promise<void> = async (): Promise<void> => {};
  @Link followUpdates: boolean;
  @Link followUpdatesBusy: boolean;
  changeFollowUpdates: (enabled: boolean) => Promise<void> = async (enabled: boolean): Promise<void> => {};
  @Link secureScreen: boolean;
  applySecureScreen: () => void = (): void => {};
  confirmClearImageCache: () => void = (): void => {};
  openSubpage: (name: string) => void = (name: string): void => {};
  @Link downloadWifiOnly: boolean;
  @Link downloadConcurrent: number;
  @Link widgetShowRealData: boolean;
  notifyWidgetRefresh: () => void = (): void => {};
  @Link widgetShowCover: boolean;
  @Link checkingUpdate: boolean;
  checkUpdate: () => Promise<void> = async (): Promise<void> => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  closeSubpage: () => void = (): void => {};

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      Scroll(this.settingsScroller) {
        Column({ space: 14 }) {
          Text('常规')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
          Column({ space: 0 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.circle_grid_2x2'))
                  .fontSize(20)
                  .fontColor([this.appearanceColors.primary])
                Column({ space: 3 }) {
                  Text('外观')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(COLOR_TEXT_TITLE)
                  Text('显示模式、沉浸光感与应用图标')
                    .fontSize(13)
                    .fontColor(COLOR_TEXT_SECONDARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([COLOR_TEXT_SECONDARY])
              }
              .width('100%')
            }
            .width('100%')
            .constraintSize({ minHeight: 58 })
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(Color.Transparent)
            .borderRadius({ topLeft: 18, topRight: 18 })
            .onClick((): void => this.openSubpage('appearance'))

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('自动签到')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('每天首次打开自动签到')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoPunch })
                .selectedColor(this.appearanceColors.primary)
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
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('追更通知')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('回到应用时检查收藏的新章节')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.followUpdates })
                .selectedColor(this.appearanceColors.primary)
                .enabled(!this.followUpdatesBusy)
                .onChange((isOn: boolean): void => { this.changeFollowUpdates(isOn); })
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.eye_slash'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
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
                .selectedColor(this.appearanceColors.primary)
                .onChange((isOn: boolean) => {
                  this.secureScreen = isOn;
                  AppStorage.setOrCreate('bika_secure_screen', isOn);
                  CacheManager.getInstance().then(c => c.saveSetting('secure_screen', isOn ? 'true' : 'false'));
                  this.applySecureScreen();
                  showImmersiveToast({
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
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('清理图片缓存')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('清理章节图片、列表与分类缓存')
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
                .fontColor([this.appearanceColors.primary])
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
                .fontColor([this.appearanceColors.primary])
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
                .fontColor([this.appearanceColors.primary])
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
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('账号与安全')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('修改后需要重新登录')
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
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('下载')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
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
                .selectedColor(this.appearanceColors.primary)
                .onChange((isOn: boolean) => {
                  this.downloadWifiOnly = isOn;
                  DownloadManager.getInstance().setWifiOnly(isOn);
                  if (isOn && !DownloadManager.getInstance().isWifiNow()) {
                    showImmersiveToast({ message: '当前非 WiFi 网络，任务将等待 WiFi', duration: 2000 });
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
                .fontColor([this.appearanceColors.primary])
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
                  .fontColor(this.downloadConcurrent === n ? this.appearanceColors.onPrimary : COLOR_TEXT_SECONDARY)
                  .textAlign(TextAlign.Center)
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor(this.downloadConcurrent === n ? this.appearanceColors.primary : this.appearanceColors.tint)
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
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('桌面卡片')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.rectangle_portrait_on_rectangle_portrait'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('显示真实内容')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('卡片展示作品名与阅读进度')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.widgetShowRealData })
                .selectedColor(this.appearanceColors.primary)
                .onChange((isOn: boolean) => {
                  this.widgetShowRealData = isOn;
                  CacheManager.getInstance().then(c => c.saveSetting('widget_show_real_data', isOn ? 'true' : 'false'));
                  this.notifyWidgetRefresh();
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

            Divider().margin({ left: 16, right: 16 })

            Row() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('显示封面')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text('卡片展示作品封面')
                  .fontSize(13)
                  .fontColor(COLOR_TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.widgetShowCover })
                .selectedColor(this.appearanceColors.primary)
                .onChange((isOn: boolean) => {
                  this.widgetShowCover = isOn;
                  CacheManager.getInstance().then(c => c.saveSetting('widget_show_cover', isOn ? 'true' : 'false'));
                  this.notifyWidgetRefresh();
                })
            }
            .width('100%')
            .height(58)
            .padding({ left: 16, right: 16 })

          }
          .width('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

          Text('应用')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 })
          Column({ space: 0 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([this.appearanceColors.primary])
              Column({ space: 3 }) {
                Text('检查更新')
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_TEXT_TITLE)
                Text(this.checkingUpdate ? '正在检查…' : '检查是否有新版本')
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
                .fontColor([this.appearanceColors.primary])
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
          .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .backgroundColor(COLOR_BG)
      .align(Alignment.Top)
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .backgroundColor(COLOR_BG)
    .bindToScrollable([this.settingsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}
