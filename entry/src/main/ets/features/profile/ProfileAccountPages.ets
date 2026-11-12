import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { COLOR_PRIMARY, COLOR_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_HINT, COLOR_TEXT_TITLE, COLOR_CARD, COLOR_INPUT_BG, COLOR_PLACEHOLDER, COLOR_DIVIDER, COLOR_WHITE } from '../../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileEditPage {
  profileEditScroller: Scroller = new Scroller();
  @Link editSlogan: string;
  @Link editSaving: boolean;
  saveProfileEdit: () => Promise<void> = async (): Promise<void> => {};
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
      Scroll(this.profileEditScroller) {
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
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .padding({ bottom: 16 })
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
    .bindToScrollable([this.profileEditScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}

/** 沿用个人中心的状态绑定、滚动位置与事件。 */
@Component
export struct ProfileAccountPage {
  accountScroller: Scroller = new Scroller();
  @Link oldPassword: string;
  @Link newPassword: string;
  @Link confirmNewPassword: string;
  @Link passwordSaving: boolean;
  submitPasswordChange: () => Promise<void> = async (): Promise<void> => {};
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
      Scroll(this.accountScroller) {
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
                .placeholderColor(COLOR_TEXT_SECONDARY)
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
                .placeholderColor(COLOR_TEXT_SECONDARY)
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
                .placeholderColor(COLOR_TEXT_SECONDARY)
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
            .backgroundColor(COLOR_CARD).border({ width: 1, color: COLOR_DIVIDER })
            .padding({ bottom: 16 })

            Text('修改成功后需要重新登录。')
              .fontSize(12)
              .fontColor(COLOR_TEXT_HINT)
              .width('100%')
              .padding({ left: 16, right: 16 })
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
    .bindToScrollable([this.accountScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.closeSubpage();
      return true;
    })
  }
}
