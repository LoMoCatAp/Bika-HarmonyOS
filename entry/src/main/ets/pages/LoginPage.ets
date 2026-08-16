import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import { CacheManager } from '../common/CacheManager';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_DISABLED,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_TEXT_SECONDARY,
  COLOR_INPUT_BG,
  COLOR_DIVIDER,
  COLOR_CARD,
  COLOR_WHITE
} from '../common/Constants';

/**
 * 登录页面
 * 用户名 + 密码登录（不含邮箱），自动保存凭据
 */
@Entry
@Component
struct LoginPage {
  @State email: string = '';
  @State password: string = '';
  @State showRegister: boolean = false;
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State savePassword: boolean = true;
  @State usernameFocused: boolean = false;
  @State passwordFocused: boolean = false;
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  private apiService: ApiService = ApiService.getInstance();
  private stack: NavPathStack = new NavPathStack();

  private immersiveTitleBar(title: string): HdsNavigationTitleBarOptions {
    return {
      content: { title: { mainTitle: title } },
      enableComponentSafeArea: true,
      avoidLayoutSafeArea: true,
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('app.color.bika_card')
          },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.bika_text_title') },
            backIconStyle: { iconColor: $r('app.color.bika_text_title') }
          }
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    };
  }
  /** 频控熔断倒计时定时器 */
  private cooldownTimer: number = -1;

  async aboutToAppear(): Promise<void> {
    // 注册成功回填邮箱
    let regEmail = AppStorage.get<string>('reg_email');
    if (regEmail && regEmail.length > 0) {
      this.email = regEmail;
      AppStorage.set('reg_email', '');
    }
    await this.loadSavedCredentials();
  }

  async loadSavedCredentials(): Promise<void> {
    try {
      let cache = await CacheManager.getInstance();
      let savedEmail = cache.getEmail();
      let savedPass = cache.getPassword();
      if (savedEmail) {
        this.email = savedEmail;
      }
      if (savedPass) {
        this.password = savedPass;
      }
    } catch (err) {
      console.error('[LoginPage] loadSavedCredentials error:', JSON.stringify(err));
    }
  }

  async onLogin(): Promise<void> {
    if (!this.email.trim()) {
      this.errorMsg = '用户名不能为空';
      return;
    }
    if (!this.password.trim()) {
      this.errorMsg = '密码不能为空';
      return;
    }

    this.isLoading = true;
    this.errorMsg = '';

    try {
      await this.apiService.signIn(this.email.trim(), this.password);
      console.info('[LoginPage] 登录成功');
      promptAction.showToast({ message: '登录成功', duration: 2000 });
      router.back();
    } catch (err) {
      let msg = (err as Error).message;
      this.errorMsg = msg || '登录失败，请稍后重试';
      // 频控熔断倒计时：每秒刷新剩余等待时间
      if (this.cooldownTimer >= 0) {
        clearInterval(this.cooldownTimer);
      }
      this.cooldownTimer = setInterval(() => {
        let remain = ApiService.getRateLimitRemainSec();
        if (remain > 0) {
          let unit = remain >= 60 ? Math.ceil(remain / 60) + ' 分钟' : remain + ' 秒';
          this.errorMsg = '服务器请求过于频繁，请等约 ' + unit + ' 后再试（开关飞行模式更换 IP 可立即恢复）';
        } else {
          if (this.cooldownTimer >= 0) {
            clearInterval(this.cooldownTimer);
            this.cooldownTimer = -1;
          }
          this.errorMsg = '限流已结束，可以重新登录';
        }
      }, 1000);
    } finally {
      this.isLoading = false;
    }
  }

  aboutToDisappear(): void {
    if (this.cooldownTimer >= 0) {
      clearInterval(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }

  onBack(): void {
    router.back();
  }

  /** 忘记密码：哔咔通过官网处理密码找回（bika 原版亦为占位提示） */
  private showForgotPasswordDialog(): void {
    promptAction.showDialog({
      title: '找回密码',
      message: '密码找回需前往哔咔官网处理。是否打开官网？',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '打开官网', color: '#FF7CA8' }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        try {
          let context = getContext(this) as common.UIAbilityContext;
          context.openLink('https://www.picacomic.com');
        } catch (err) {
          promptAction.showToast({ message: '无法打开链接', duration: 1600 });
        }
      }
    }).catch((err: Error) => {
      console.warn('[LoginPage] forgot password dialog failed: ' + JSON.stringify(err));
    });
  }

  build() {
    HdsNavigation(this.stack) {
      // ── 登录表单 ──
      Column() {
        Column() {
          Text('BIKA')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_PRIMARY)
          Text('请登录您的账号')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 用户名（bika 的 email 字段即账号名，不支持邮箱登录）
        TextInput({ placeholder: '用户名', text: this.email })
          .width('100%')
          .height(52)
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
          .placeholderColor(COLOR_TEXT_HINT)
          .backgroundColor(COLOR_CARD)
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .border({ width: 1, color: this.usernameFocused ? COLOR_PRIMARY : COLOR_DIVIDER })
          .enterKeyType(EnterKeyType.Next)
          .onFocus(() => {
            this.usernameFocused = true;
          })
          .onBlur(() => {
            this.usernameFocused = false;
          })
          .onChange((value: string) => this.email = value)
          .margin({ top: 48 })

        // 密码输入
        TextInput({ placeholder: '密码', text: this.password })
          .width('100%')
          .height(52)
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
          .placeholderColor(COLOR_TEXT_HINT)
          .backgroundColor(COLOR_CARD)
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .border({ width: 1, color: this.passwordFocused ? COLOR_PRIMARY : COLOR_DIVIDER })
          .type(InputType.Password)
          .enterKeyType(EnterKeyType.Done)
          .onFocus(() => {
            this.passwordFocused = true;
          })
          .onBlur(() => {
            this.passwordFocused = false;
          })
          .onChange((value: string) => this.password = value)
          .onSubmit(() => this.onLogin())
          .margin({ top: 16 })

        // 记住密码 + 忘记密码
        Row() {
          Toggle({ type: ToggleType.Switch, isOn: this.savePassword })
            .selectedColor(COLOR_PRIMARY)
            .onChange((checked: boolean) => this.savePassword = checked)
          Text('记住密码')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .margin({ left: 8 })
          Blank()
          Text('忘记密码？')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .onClick(() => {
              this.showForgotPasswordDialog();
            })
        }
        .width('100%')
        .margin({ top: 12 })

        // 错误消息
        if (this.errorMsg) {
          Text(this.errorMsg)
            .fontSize(13)
            .fontColor(COLOR_PRIMARY)
            .margin({ top: 12 })
        }

        // 登录按钮（56 高，未填齐禁用）
        Button({ type: ButtonType.Normal }) {
          if (this.isLoading) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color('#FFFFFF')
          } else {
            Text('登录')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_WHITE)
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.isLoading ? COLOR_PRIMARY_DISABLED : COLOR_PRIMARY)
        .borderRadius(28)
        .margin({ top: 32 })
        .onClick(() => this.onLogin())
        .enabled(!this.isLoading && this.email.trim().length > 0 && this.password.trim().length > 0)

        // 注册提示
        Row({ space: 8 }) {
          Text('还没有账号？')
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
          Text('立即注册')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .onClick(() => {
              router.pushUrl({ url: 'pages/RegisterPage' });
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 24 })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar('账号'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_CARD)
  }
}
