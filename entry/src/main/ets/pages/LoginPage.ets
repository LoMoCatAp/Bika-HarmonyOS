import { router, promptAction } from '@kit.ArkUI';
import { ApiService } from '../network/ApiService';
import { CacheManager } from '../common/CacheManager';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_DISABLED,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_HINT,
  COLOR_INPUT_BG,
  COLOR_DIVIDER,
  COLOR_CARD,
  COLOR_WHITE
} from '../common/Constants';

/**
 * 登录页面
 * 哔咔账号（邮箱+密码）登录，自动保存凭据
 */
@Entry
@Component
struct LoginPage {
  @State email: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State savePassword: boolean = true;
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  private apiService: ApiService = ApiService.getInstance();
  /** 频控熔断倒计时定时器 */
  private cooldownTimer: number = -1;

  async aboutToAppear(): Promise<void> {
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

  build() {
    Column() {
      // ── 顶部标题栏 ──
      Row() {
        Button({ type: ButtonType.Normal }) {
          Text('←')
            .fontSize(20)
            .fontColor(COLOR_TEXT_TITLE)
        }
        .backgroundColor(Color.Transparent)
        .width(40)
        .height(40)
        .onClick(() => this.onBack())

        Text('账号')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_TITLE)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 占位保持平衡
        Row().width(40).height(40)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topSafeHeight + 8, bottom: 4 })
      .backgroundColor(COLOR_CARD)

      Divider().height(1).color(COLOR_DIVIDER)

      // ── 登录表单 ──
      Column() {
        // Logo / 标题
        Text('Bika')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_PRIMARY)
          .margin({ top: 40, bottom: 8 })

        Text('登录以使用完整功能')
          .fontSize(14)
          .fontColor(COLOR_TEXT_HINT)
          .margin({ bottom: 32 })

        // 用户名或邮箱（账号名与邮箱都提交到服务端 email 字段）
        TextInput({ placeholder: '用户名或邮箱', text: this.email })
          .width('85%')
          .height(48)
          .fontSize(15)
          .backgroundColor(COLOR_INPUT_BG)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string) => this.email = value)

        // 密码输入
        TextInput({ placeholder: '密码', text: this.password })
          .width('85%')
          .height(48)
          .fontSize(15)
          .backgroundColor(COLOR_INPUT_BG)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .type(InputType.Password)
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => this.password = value)
          .margin({ top: 12 })

        // 记住密码
        Row() {
          Toggle({ type: ToggleType.Switch, isOn: this.savePassword })
            .selectedColor(COLOR_PRIMARY)
            .onChange((checked: boolean) => this.savePassword = checked)

          Text('记住密码')
            .fontSize(13)
            .fontColor(COLOR_TEXT_HINT)
            .margin({ left: 8 })
        }
        .width('85%')
        .margin({ top: 12 })
        .justifyContent(FlexAlign.Start)

        // 错误消息
        if (this.errorMsg) {
          Text(this.errorMsg)
            .fontSize(13)
            .fontColor(COLOR_PRIMARY)
            .margin({ top: 12 })
        }

        // 登录按钮
        Button({ type: ButtonType.Normal }) {
          if (this.isLoading) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#FFFFFF')
          } else {
            Text('登  录')
              .fontSize(16)
              .fontColor(COLOR_WHITE)
          }
        }
        .width('85%')
        .height(48)
        .backgroundColor(this.isLoading ? COLOR_PRIMARY_DISABLED : COLOR_PRIMARY)
        .borderRadius(24)
        .margin({ top: 24 })
        .onClick(() => this.onLogin())
        .enabled(!this.isLoading)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_CARD)
  }
}
