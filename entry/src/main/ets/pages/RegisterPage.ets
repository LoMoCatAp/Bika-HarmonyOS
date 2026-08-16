import { router, promptAction } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, hdsMaterial } from '@kit.UIDesignKit';
import { ApiService } from '../network/ApiService';
import {
  COLOR_PRIMARY,
  COLOR_PRIMARY_TINT,
  COLOR_TEXT_TITLE,
  COLOR_TEXT_SECONDARY,
  COLOR_TEXT_HINT,
  COLOR_INPUT_BG,
  COLOR_PLACEHOLDER,
  COLOR_BG,
  COLOR_CARD,
  COLOR_WHITE,
  COLOR_DIVIDER
} from '../common/Constants';

/**
 * 注册页：邮箱/昵称/密码 + 生日/性别 + 三道密保题
 */
@Entry
@Component
struct RegisterPage {
  @State email: string = '';
  @State name: string = '';
  @State password: string = '';
  @State birthday: string = '2000-01-01';
  @State gender: string = 'm';
  @State question1: string = '';
  @State answer1: string = '';
  @State question2: string = '';
  @State answer2: string = '';
  @State question3: string = '';
  @State answer3: string = '';
  @State registering: boolean = false;
  @State registerError: string = '';
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  private stack: NavPathStack = new NavPathStack();

  private immersiveTitleBar(title: string): HdsNavigationTitleBarOptions {
    return {
      content: { title: { mainTitle: title } },
      enableComponentSafeArea: true,
      avoidLayoutSafeArea: true,
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('app.color.bika_bg')
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

  private apiService: ApiService = ApiService.getInstance();

  private pad(n: number): string {
    return n < 10 ? '0' + n : String(n);
  }

  private formatDate(d: Date): string {
    return d.getFullYear() + '-' + this.pad(d.getMonth() + 1) + '-' + this.pad(d.getDate());
  }

  private parseDate(s: string): Date {
    let parts = s.split('-');
    if (parts.length === 3) {
      return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    }
    return new Date(2000, 0, 1);
  }

  private pickBirthday(): void {
    DatePickerDialog.show({
      start: new Date(1950, 0, 1),
      end: new Date(),
      selected: this.parseDate(this.birthday),
      onDateAccept: (value: Date) => {
        this.birthday = this.formatDate(value);
      }
    });
  }

  private async doRegister(): Promise<void> {
    // bika BasicInfo 校验顺序：昵称 → 用户名 → 密码
    let nickname = this.name.trim();
    if (nickname.length < 2) {
      promptAction.showToast({ message: '昵称至少需要 2 个字符', duration: 1600 });
      return;
    }
    if (nickname.length > 50) {
      promptAction.showToast({ message: '昵称不能超过 50 个字符', duration: 1600 });
      return;
    }
    let username = this.email.trim();
    if (username.length === 0) {
      promptAction.showToast({ message: '请输入用户名', duration: 1600 });
      return;
    }
    if (!/^[a-zA-Z0-9]+$/.test(username)) {
      promptAction.showToast({ message: '用户名只能包含字母和数字', duration: 2000 });
      return;
    }
    if (this.password.length < 8) {
      promptAction.showToast({ message: '密码至少需要 8 个字符', duration: 1600 });
      return;
    }
    let questions = [this.question1.trim(), this.question2.trim(), this.question3.trim()];
    let answers = [this.answer1.trim(), this.answer2.trim(), this.answer3.trim()];
    for (let i = 0; i < 3; i++) {
      if (questions[i].length === 0 || answers[i].length === 0) {
        promptAction.showToast({ message: '请完整填写三道密保题', duration: 1600 });
        return;
      }
    }
    if (this.registering) {
      return;
    }
    this.registering = true;
    this.registerError = '';
    try {
      await this.apiService.register(username, this.password, nickname,
        this.birthday, this.gender, questions, answers);
      promptAction.showToast({ message: '注册成功，请登录', duration: 2000 });
      AppStorage.set('reg_email', username);
      router.back();
    } catch (err) {
      let msg = (err as Error).message || '注册失败';
      let low = msg.toLowerCase();
      if (low.indexOf('invalid') >= 0 || low.indexOf('validation') >= 0) {
        msg = '注册失败：昵称可能已被占用，请换一个昵称；用户名只能包含字母和数字，密码至少 8 个字符';
      }
      this.registerError = msg;
      promptAction.showToast({ message: msg, duration: 2400 });
    } finally {
      this.registering = false;
    }
  }

  @Builder
  genderChip(value: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.gender === value ? COLOR_WHITE : COLOR_TEXT_SECONDARY)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.gender === value ? COLOR_PRIMARY : COLOR_INPUT_BG)
      .onClick(() => {
        this.gender = value;
      })
  }

  @Builder
  fieldTitle(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(COLOR_TEXT_HINT)
      .width('100%')
      .padding({ left: 4, top: 14, bottom: 6 })
  }

  @Builder
  fieldHint(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(COLOR_TEXT_HINT)
      .width('100%')
      .padding({ left: 6, top: 4 })
  }

  @Builder
  inputField(placeholder: string, value: string, isPassword: boolean, onChange: (v: string) => void,
    topMargin: number = 0) {
    TextInput({ placeholder: placeholder, text: value })
      .type(isPassword ? InputType.Password : InputType.Normal)
      .fontSize(15)
      .fontColor(COLOR_TEXT_TITLE)
      .placeholderColor(COLOR_PLACEHOLDER)
      .backgroundColor(COLOR_INPUT_BG)
      .borderRadius(14)
      .height(46)
      .width('100%')
      .margin({ top: topMargin })
      .onChange((v: string) => {
        onChange(v);
      })
  }

  build() {
    HdsNavigation(this.stack) {
      Scroll() {
        Column() {
          Row().height(24)
          this.fieldTitle('昵称')
          this.inputField('显示在评论与个人主页', this.name, false, (v: string) => {
            this.name = v;
          })
          this.fieldHint('2-50 个字符')
          this.fieldTitle('用户名')
          this.inputField('用于登录', this.email, false, (v: string) => {
            this.email = v;
          })
          this.fieldHint('只能包含字母和数字')
          this.fieldTitle('密码')
          this.inputField('至少需要 8 个字符', this.password, true, (v: string) => {
            this.password = v;
          })
          this.fieldHint('登录时使用，请牢记')

          this.fieldTitle('生日')
          this.fieldHint('需年满 18 周岁')
          Row() {
            Text(this.birthday)
              .fontSize(15)
              .fontColor(COLOR_TEXT_TITLE)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(20)
              .fontColor([COLOR_PRIMARY])
          }
          .width('100%')
          .height(46)
          .padding({ left: 14, right: 14 })
          .backgroundColor(COLOR_INPUT_BG)
          .borderRadius(14)
          .onClick(() => this.pickBirthday())

          this.fieldTitle('性别')
          Row({ space: 10 }) {
            this.genderChip('m', '男')
            this.genderChip('f', '女')
            this.genderChip('bot', '机器人')
          }
          .width('100%')

          this.fieldTitle('密保问题一（用于找回账号）')
          this.inputField('例如：我的出生地是？', this.question1, false, (v: string) => {
            this.question1 = v;
          })
          this.inputField('答案', this.answer1, false, (v: string) => {
            this.answer1 = v;
          }, 10)
          this.fieldTitle('密保问题二')
          this.inputField('例如：我的小学是？', this.question2, false, (v: string) => {
            this.question2 = v;
          })
          this.inputField('答案', this.answer2, false, (v: string) => {
            this.answer2 = v;
          }, 10)
          this.fieldTitle('密保问题三')
          this.inputField('例如：我最喜欢的食物是？', this.question3, false, (v: string) => {
            this.question3 = v;
          })
          this.inputField('答案', this.answer3, false, (v: string) => {
            this.answer3 = v;
          }, 10)

          Button(this.registering ? '注册中…' : '注册', { type: ButtonType.Normal })
            .fontSize(16)
            .fontColor(COLOR_WHITE)
            .backgroundColor(this.registering ? COLOR_TEXT_HINT : COLOR_PRIMARY)
            .borderRadius(24)
            .height(48)
            .width('100%')
            .margin({ top: 24 })
            .enabled(!this.registering)
            .onClick(() => {
              this.doRegister();
            })
          if (this.registerError.length > 0) {
            Text(this.registerError)
              .fontSize(13)
              .fontColor('#C62828')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 12, bottom: 40 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .titleBar(this.immersiveTitleBar('注册'))
    .hideTitleBar(false)
    .hideBackButton(false)
    .width('100%')
    .height('100%')
    .backgroundColor(COLOR_BG)
  }
}
