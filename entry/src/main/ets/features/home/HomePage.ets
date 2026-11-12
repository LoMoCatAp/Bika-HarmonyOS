import { router, display, ComponentContent } from '@kit.ArkUI';
import { showImmersiveToast } from '../../common/ImmersiveToast';
import { ApiService } from '../../network/ApiService';
import { buildImageUrl } from '../../models/Comic';
import { NetImage } from '../../components/NetImage';
import { DetailGlassCapsule } from '../../components/DetailGlassCapsule';
import { navigationBlurStyle } from '../../common/NavigationBlur';
import { CacheManager } from '../../common/CacheManager';
import { compatibleSheetMaterial } from '../../common/CompatibleMaterial';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_DISABLED, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_PLACEHOLDER, COLOR_WHITE, DEFAULT_CHANNELS, BikaChannel, adaptiveChannelColumns } from '../../common/Constants';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';

@Builder
function homeRefreshPlaceholder() {
  Row().width('100%').height(0)
}

@Component
export struct HomePage {
  /** 由根页协调底栏收起与频道路由，避免频道与子页显隐各走一套。 */
  onOpenChannel: (label: string, kind: string) => void = (): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('bika_animations') animationsOn: boolean = true;
  @StorageProp('isLoggedIn') @Watch('onHomeAuthChanged') isLoggedIn: boolean = false;
  @StorageProp('avatarUrl') avatarUrl: string = '';
  @StorageProp('bika_material_rev') materialRev: number = 0;
  /** 频道自定义：顺序与隐藏 */
  @State channelOrder: string[] = [];
  @State channelHidden: string[] = [];
  @State showChannelEdit: boolean = false;
  @State refreshing: boolean = false;
  @State refreshPullOffset: number = 0;
  /** 频道按压效果 */
  @State pressedChannel: string = '';
  private cache: CacheManager | null = null;
  private homeStack: NavPathStack = new NavPathStack();
  private homeScroller: Scroller = new Scroller();
  private avatarRequest: number = 0;
  private refreshInFlight: boolean = false;
  private refreshContent: ComponentContent<Object> | undefined = undefined;

  /** 跳转个人中心（由 IndexPage 切换 tab） */
  onGotoProfile(): void {
    AppStorage.set('bika_goto_profile', Date.now());
  }

  aboutToAppear(): void {
    this.refreshContent = new ComponentContent(this.getUIContext(), wrapBuilder(homeRefreshPlaceholder));
    this.reloadHomeData().catch(() => {
      // 网络不可用时保留本地频道和默认头像。
    });
  }

  aboutToDisappear(): void {
    this.avatarRequest++;
    this.refreshContent?.dispose();
    this.refreshContent = undefined;
  }

  private onHomeAuthChanged(): void {
    this.avatarRequest++;
    if (this.isLoggedIn) {
      this.loadHomeAvatar().catch(() => {});
    }
  }

  private async loadHomeAvatar(): Promise<void> {
    if (!this.isLoggedIn) {
      return;
    }
    const request = ++this.avatarRequest;
    const user = await ApiService.getInstance().getUserProfile();
    if (request === this.avatarRequest && this.isLoggedIn) {
      AppStorage.setOrCreate('avatarUrl', user.avatar?.path ? buildImageUrl(user.avatar) : '');
    }
  }

  private async reloadHomeData(): Promise<void> {
    const cache = await CacheManager.getInstance();
    this.cache = cache;
    this.channelOrder = cache.loadChannelsOrder();
    this.channelHidden = cache.loadChannelsHidden();
    await this.loadHomeAvatar();
  }

  private async refreshHome(): Promise<void> {
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    this.refreshing = true;
    const startedAt = Date.now();
    try {
      await this.reloadHomeData();
    } catch (err) {
      showImmersiveToast({ message: '刷新失败，请稍后重试', duration: 1600 });
    } finally {
      // 本地数据可能立即返回，保留短暂展示时间，避免刚展开就收起。
      const remaining = 400 - (Date.now() - startedAt);
      if (remaining > 0) {
        await new Promise<void>((resolve) => { setTimeout(resolve, remaining); });
      }
      this.refreshInFlight = false;
      this.refreshing = false;
    }
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

  @Builder
  homeEditAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(20).fontColor([COLOR_TEXT_TITLE])
    }
    .width(40).height(40)
    .backgroundColor(Color.Transparent)
    .accessibilityText('编辑频道')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
    .onClick((): void => { this.showChannelEdit = true; })
  }

  @Builder
  homeSearchAction() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([COLOR_TEXT_TITLE])
    }
    .width(40).height(40)
    .backgroundColor(Color.Transparent)
    .accessibilityText('搜索')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: this.animationsOn ? 0.94 : 1 })
    .onClick((): void => { router.pushUrl({ url: 'pages/SearchPage' }); })
  }

  /** 仅为 HDS 保留原有标题栏尺寸，实际按钮在外层独立绘制。 */
  @Builder
  homeHeaderSlot() {
    Row().width('100%').height(56)
  }

  @Builder
  homeHeader() {
    Row({ space: 8 }) {
      Text('Bika')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_TITLE)
        .layoutWeight(1)
      DetailGlassCapsule({
        capsuleWidth: 40, capsuleHeight: 40,
        content: (): void => { this.homeEditAction(); }
      })
      DetailGlassCapsule({
        capsuleWidth: 40, capsuleHeight: 40,
        content: (): void => { this.homeSearchAction(); }
      })
      if (this.isLoggedIn) {
        if (this.avatarUrl.length > 0) {
          NetImage({ src: this.avatarUrl, fit: ImageFit.Cover, radius: 18, fillParent: true })
            .width(36)
            .height(36)
            .accessibilityText('个人中心')
            .onClick(() => { this.onGotoProfile(); })
        } else {
          Image($r('app.media.ic_default_avatar'))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .accessibilityText('个人中心')
            .onClick(() => { this.onGotoProfile(); })
        }
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
    .position({ x: 0, y: this.topSafeHeight })
    .zIndex(2)
  }

  @Builder
  guestChannel() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(172).height(172).fill(COLOR_PRIMARY_TINT)
        Circle().width(18).height(18).fill(COLOR_PRIMARY).opacity(0.35)
          .translate({ x: 78, y: -60 })
        Circle().width(10).height(10).fill(COLOR_PRIMARY).opacity(0.5)
          .translate({ x: -82, y: 42 })
        Column() {}
          .width(118).height(144).backgroundColor(COLOR_PRIMARY).opacity(0.25)
          .borderRadius(18).rotate({ angle: -14 }).translate({ x: -8, y: 2 })
        Column({ space: 12 }) {
          Text('Bika').fontSize(25).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY)
          Row().width(54).height(4).backgroundColor(COLOR_PRIMARY_TINT).borderRadius(2)
          Row().width(38).height(4).backgroundColor(COLOR_PRIMARY_TINT).borderRadius(2)
        }
        .width(118).height(144).justifyContent(FlexAlign.Center)
        .backgroundColor(COLOR_CARD).borderRadius(18)
        .border({ width: 2, color: COLOR_PRIMARY_TINT }).rotate({ angle: 8 })
      }
      .width(208).height(200)
      .accessibilityLevel('no')
      Text('请登录')
        .fontSize(26).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_TITLE)
      Text('登录后可同步收藏与阅读进度')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
      Row({ space: 8 }) {
        Text('立即登录').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_WHITE)
        SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(16).fontColor([COLOR_WHITE])
      }
      .height(44).padding({ left: 24, right: 24 }).borderRadius(22)
      .backgroundColor(COLOR_PRIMARY).margin({ top: 10 })
    }
    .width('100%')
    .padding({ top: 30, bottom: 32, left: 20, right: 20 })
    .linearGradient({ angle: 160, colors: [[COLOR_PRIMARY_TINT, 0], [COLOR_CARD, 0.7]] })
    .borderRadius(28)
    .scale({ x: this.pressedChannel === '__guest_login__' ? 0.97 : 1,
      y: this.pressedChannel === '__guest_login__' ? 0.97 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.setChannelPressed('__guest_login__', true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.type === TouchType.Move) {
        this.setChannelPressed('__guest_login__', false);
      }
    })
    .accessibilityGroup(true)
    .accessibilityText('请登录，点击登录')
    .onClick(() => router.pushUrl({ url: 'pages/LoginPage', params: { from: 'inapp' } }))
  }

  @Builder
  refreshHeader() {
    Row({ space: 8 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY)
      Text(this.refreshing ? '正在刷新' : (this.refreshPullOffset >= 64 ? '松开刷新' : '下拉刷新'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .position({ x: 0, y: this.topSafeHeight + 56 + Math.max(0, (this.refreshPullOffset - 48) / 2) })
    .opacity(Math.min(1, Math.max(0, (this.refreshPullOffset - 24) / 24)))
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  homeNavigation() {
    HdsNavigation(this.homeStack) {
      Scroll(this.homeScroller) {
        Column() {
          // 内容从标题下方开始，滚动时进入原生标题栏的模糊采样区域。
          Row().height(this.topSafeHeight + 56)

          if (!this.isLoggedIn) {
            Column() {
              this.guestChannel()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 76 })
          }

          // 频道网格（方形图标 + 名称，按自定义顺序与隐藏过滤）
          if (this.isLoggedIn) {
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
                    showImmersiveToast({ message: '该功能已下线', duration: 1600 });
                    return;
                  }
                  this.onOpenChannel(ch.label, ch.kind);
                })
              }
            }, (ch: BikaChannel) => ch.label)
          }
          .columnsTemplate(adaptiveChannelColumns())
          .columnsGap(14)
          .rowsGap(18)
          // 滚动统一交给外层 Scroll；越过标题边界的节点继续绘制，供 HDS 模糊采样。
          .enableScrollInteraction(false)
          .clip(false)
          .cachedCount(3, true)
          .padding({ left: 16, right: 16, top: 8, bottom: this.bottomSafeHeight + 76 })
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .clip(false)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      // 顶部交给 Refresh 下拉，底部使用原生弹簧回弹。
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true, effectEdge: EffectEdge.END })
      .translate({ y: this.refreshPullOffset })
      .backgroundColor(COLOR_BG)

    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar({
      content: { title: { mainTitle: '' }, stackBuilder: () => this.homeHeaderSlot() },
      enableComponentSafeArea: false,
      avoidLayoutSafeArea: true,
      style: navigationBlurStyle()
    })
    .bindToScrollable([this.homeScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    // 自定义刷新节点存在时，固定导航容器，只有内容区跟随下拉。
    .position({ x: 0, y: 0 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({ refreshing: $$this.refreshing, refreshingContent: this.refreshContent }) {
        this.homeNavigation()
      }
      .width('100%')
      .height('100%')
      .refreshOffset(64)
      .maxPullDownDistance(128)
      .onOffsetChange((offset: number) => { this.refreshPullOffset = Math.max(0, offset); })
      .onRefreshing(() => { this.refreshHome(); })
      this.refreshHeader()
      // 光感按钮是 HDS 背景模糊的上层兄弟节点，避免共同参与标题栏滤镜。
      this.homeHeader()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showChannelEdit, this.channelEditSheet(), {
      systemMaterial: compatibleSheetMaterial(),
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
