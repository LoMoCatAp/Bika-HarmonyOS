import { showImmersiveToast } from '../../common/ImmersiveToast';
import { ApiService } from '../../network/ApiService';
import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { CacheManager } from '../../common/CacheManager';
import { DnsIpEntry } from '../../network/DnsService';
import { COLOR_PRIMARY, COLOR_PRIMARY_TINT, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_DISABLED, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_INPUT_BG, COLOR_DIVIDER, COLOR_WHITE } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileDnsPage {
  dnsScroller: Scroller = new Scroller();
  @Link dnsFetching: boolean;
  @Link dnsTesting: boolean;
  accentColor: ResourceColor = $r('app.color.bika_primary');
  @StorageLink('bika_use_proxy') useProxy: boolean = false;
  @Link dnsApiIps: string[];
  @Link dnsImageIps: string[];
  fetchAndTestDns: () => Promise<void> = async (): Promise<void> => {};
  @Link dnsLines: Map<string, DnsIpEntry[]>;
  applyLowestLatencyDns: () => void = (): void => {};
  @Link dnsError: string;
  selectDnsIp: (entry: DnsIpEntry) => void = (entry: DnsIpEntry): void => {};
  resetDns: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  subpageContentTop: number = 56 + 8;
  closeSubpage: () => void = (): void => {};
  loadDnsSelection: () => void = (): void => {};

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

  private dnsLatencyLabel(entry: DnsIpEntry): string {
    if (entry.latency === -2) {
      return '测量中…';
    }
    if (entry.latency < 0) {
      return '超时';
    }
    return entry.latency + ' ms';
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    HdsNavDestination() {
      Scroll(this.dnsScroller) {
        Column({ space: 12 }) {
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
                  Text('规则模式 VPN（常见代理客户端）')
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
                    showImmersiveToast({
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
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

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
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })

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
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .onClick(() => this.resetDns())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topSafeHeight + this.subpageContentTop, bottom: 40 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.dnsScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
    .onShown(() => {
      this.loadDnsSelection();
    })
  }
}
