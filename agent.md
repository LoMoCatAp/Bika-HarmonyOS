# HarmonyOS（ArkTS / ArkUI）开发实战手册

> 面向 HarmonyOS NEXT（ArkTS + ArkUI）应用开发的**通用**工程手册。
> 全部条目来自真实项目调试过程，含可直接抄用的代码片段与踩坑记录。

**适用**：HarmonyOS NEXT（API 12+，示例以 API 24 为目标，含 API 26 能力预留）
**技术栈**：ArkTS 严格模式、ArkUI 声明式 UI、HDS 设计套件（@kit.UIDesignKit）、Kit 化系统能力

---

## 0. 环境与命令速查

| 项 | 典型路径 / 值 |
|---|---|
| SDK | `C:\Program Files\Huawei\DevEco Studio\sdk` |
| hvigor | `...\DevEco Studio\tools\hvigor\bin\hvigorw.js` |
| hdc | `...\sdk\default\openharmony\toolchains\hdc.exe` |
| 应用版本 | `AppScope/app.json5` → `versionCode` / `versionName` |
| 模块与权限 | `entry/src/main/module.json5` |
| 页面清单 | `entry/src/main/resources/base/profile/main_pages.json` |
| 产物 | `entry/build/default/outputs/default/entry-default-{signed,unsigned}.hap` |
| 颜色资源 | `resources/base/element/color.json` + `resources/dark/element/color.json`（深浅色各一份） |

### 构建（PowerShell）

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& node "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
```

- 全量构建约 60~90 秒；改动大或出现诡异错误时先删 `entry/build` 再构建。
- 成功标志：输出 `BUILD SUCCESSFUL`；失败标志：`COMPILE RESULT:FAIL {ERROR:n WARN:m}`。

### 真机调试

```powershell
& $hdc list targets                    # 有输出才是真连接
& $hdc install -r path\entry-default-signed.hap
& $hdc shell aa start -a EntryAbility -b <bundleName>
& $hdc shell bm uninstall -n <bundleName>
```

---

## 1. 工程结构与页面分层

```
AppScope/app.json5                    应用级配置（版本号、图标、标签）
entry/src/main/module.json5           模块：abilities / 权限 / 页面入口
entry/src/main/ets/
  entryability/EntryAbility.ets       应用入口（窗口、颜色模式、设置恢复）
  pages/                              @Entry 路由页（每个页面一个文件）
  components/                         可复用组件（列表卡、图片、空态…）
  common/                             常量、工具、缓存、导出、兼容封装
  network/                            请求客户端、签名、DNS、下载
entry/src/main/resources/
  base/element/color.json             浅色主题颜色
  dark/element/color.json             深色主题颜色（键名必须一一对应）
```

**页面分两层，先判断再用**：

| 层级 | 载体 | 适用 |
|---|---|---|
| 路由页 | `@Entry` + `router.pushUrl` | 独立全屏页面：登录、阅读器、详情、列表结果页 |
| 子页 | `NavPathStack` + `HdsNavDestination` | 同一 Tab 内的二/三层页面：设置、收藏、历史、关于… |

判断标准：**需要保留底部导航栏层级关系**的功能用子页；**需要全屏沉浸或从多处进入**的用路由页。

---

## 2. 构建、签名与真机调试

### 2.1 签名不一致无法覆盖安装

```
error: failed to install bundle. code:9568332 error: install sign info inconsistent.
```

**原因**：设备上已装应用与当前 HAP 的签名证书不同（换设备 / 换签名配置 / 装过他人签名包）。
**解法**：先卸载再安装（注意会清空该设备应用数据）。

```powershell
& $hdc shell bm uninstall -n <bundleName>
& $hdc install path\entry-default-signed.hap
```

### 2.2 启动失败：设备锁屏

```
error: failed to start ability. Error Code:10106102 The device screen is locked...
```

安装其实已成功；解锁屏幕后手动打开即可（开发者模式无法自动解锁）。

### 2.3 只发布未签名包

Release / 分发只放 `entry-default-unsigned.hap`；签名包仅本地安装，且**不要提交进版本库**。

### 2.4 常见编译报错

| 现象 | 真正原因 | 处理 |
|---|---|---|
| `Cannot find name 'XxxAttribute'` 一堆类型错误 | 别处有**语法错误**，编译器级联报错 | 从**第一条** ERROR 往上找，先修语法 |
| `The '@State' property 'x' must be specified a default value` | 声明被破坏（如 `@State a: T` 被改成 `@State a: T,`） | 检查被脚本误改的声明行 |
| 页面必须恰好一个 `@Entry` | 子组件误加 `@Entry` | 只有路由页加 `@Entry` |
| 卡片/布局属性不生效 | 同名属性写了两次 | 后者生效；删掉多余的旧调用 |

---

## 3. HDS 设计套件（@kit.UIDesignKit）

```ts
import {
  HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, HdsNavDestination,
  HdsTabs, HdsTabsController, HdsAnimationMode, DividerMode, DividerShowType,
  hdsMaterial, hdsEffect
} from '@kit.UIDesignKit';
```

### 3.1 全屏窗口下标题栏必须显式声明安全区

```ts
private immersiveTitleBar(title: string): HdsNavigationTitleBarOptions {
  return {
    content: { title: { mainTitle: title } },
    enableComponentSafeArea: true,   // 组件自身避开安全区
    avoidLayoutSafeArea: true,       // 布局不避开（内容可延伸到状态栏下）
    style: {
      originalStyle: {
        backgroundStyle: { backgroundColor: $r('app.color.card') },
        contentStyle: {
          titleStyle: { mainTitleColor: $r('app.color.text_title') },
          backIconStyle: { iconColor: $r('app.color.text_title') }
        }
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
  };
}
```

漏掉 `enableComponentSafeArea` / `avoidLayoutSafeArea` 会表现为：标题被状态栏压住、内容整体被顶飞。

### 3.2 HdsTabsController 没有运行时换材质 API

底栏材质档位**没有** `setMaterialLevel` 之类的运行时接口；改档位只能让组件重建（改 `.key()`），
而重建有重大副作用（见 3.3）。

### 3.3 `.key()` 重建会销毁整棵子树

**现象**：在子页里改了一个用于刷新底栏的 `.key()`，结果**当前子页被瞬间踢回上级**，
但数据其实已写入（重新进入能看到新值）。用户感受是「点了没反应 / 页面跳了」。

**根因**：`.key()` 变化 → 组件销毁重建 → 其内部 `NavPathStack` 一并重建 → 栈里子页全丢。

**解法**：**子页打开期间冻结 key**，等回到根页再重建：

```ts
.key(this.subpageOpen ? 'tabs_stable' : ('tabs_' + this.materialLevel + '_' + this.rev))
```

> 结论：任何让 `HdsTabs` 重建的方案，先想清楚会销毁什么。

### 3.4 同组件多个 `.bindSheet()` 会互相顶掉

**现象**：多个弹窗（更新日志 / 隐私政策 / 设置面板）点不开，只有最后一个生效。
**解法**：统一成一个 `bindSheet`，用状态区分内容：

```ts
@State sheetKind: number = 0;   // 0=更新 1=日志 2=隐私

.bindSheet($$this.showSheet, this.bottomSheet(), {
  detents: [SheetSize.FIT_CONTENT],
  preferType: SheetType.BOTTOM,
  showClose: true,
  dragBar: false,
  onWillDismiss: (): void => { this.showSheet = false; }
})

@Builder
bottomSheet() {
  if (this.sheetKind === 0) { this.sheetUpdate() }
  else if (this.sheetKind === 1) { this.sheetChangelog() }
  else { this.sheetPrivacy() }
}
```

阅读器（设置 / 导出）、详情页（评论 / 下载）同理。

---

## 4. 状态管理与渲染刷新（最容易踩的一类坑）

### 4.1 `AppStorage.get()` 不是响应式的

**现象**：设置页下拉框选完文字不刷新，退出重进才更新。
**根因**：`AppStorage.get<T>(key)` 只是**当次取值**，不建立依赖。
**解法**：用 `@StorageLink`（双向，可写回）/ `@StorageProp`（单向读）。

### 4.2 NavDestination（子页）内容不随父组件状态重渲染

**现象**：子页里的控件（下拉文字、卡片样式）在父页状态变化后纹丝不动。
**解法**：把**需要即时刷新的那一小块**抽成独立 `@Component`，让它**自己持有** `@StorageLink`：

```ts
@Component
struct LevelSelect {
  @StorageLink('material_level') level: string = 'A';
  @State popScale: number = 1;

  private label(): string { /* 由 this.level 计算 */ return this.level; }

  build() {
    Row({ space: 4 }) {
      Text(this.label()).fontSize(15)
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12)
    }
    .scale({ x: this.popScale, y: this.popScale })
    .bindMenu(OPTIONS.map((opt: Opt): MenuElement => {
      return {
        value: opt.label,
        action: (): void => {
          animateTo({ duration: 130, curve: Curve.EaseOut }, () => { this.popScale = 1.12; });
          animateTo({ duration: 320, curve: curves.springMotion(0.55, 0.85) }, () => {
            this.popScale = 1;
            this.level = opt.value;                                   // 写回 AppStorage
            let r = AppStorage.get<number>('material_rev') ?? 0;
            AppStorage.setOrCreate('material_rev', r + 1);            // 修订号驱动跨页刷新
          });
        }
      };
    }))
  }
}
```

### 4.3 跨页面刷新用「修订号」

```ts
// 写方
AppStorage.setOrCreate('material_rev', (AppStorage.get<number>('material_rev') ?? 0) + 1);
// 读方（需要重渲染的页面声明）
@StorageProp('material_rev') materialRev: number = 0;
```

### 4.4 系统级颜色模式是唯一「免重建即时生效」的开关

```ts
this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
// COLOR_MODE_LIGHT / COLOR_MODE_NOT_SET(跟随系统)
```

系统会重新解析全部 `$r('app.color.*')`，**不需要重建任何组件**。
这也是「显示模式能立即生效、而自定义材质档位不能」的根本原因。

### 4.5 `@Watch` 用于监听 AppStorage 变化

```ts
@StorageLink('subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;
onSubpageChanged(): void { /* ... */ }
```

---

## 5. 页面结构：路由页 vs 子页（NavDestination）

### 5.1 子页标准构建方式（五步）

**第 1 步：声明栈**

```ts
struct ProfilePage {
  private stack: NavPathStack = new NavPathStack();
}
```

**第 2 步：HdsNavigation 承载根内容并注册 navDestination**

```ts
build() {
  HdsNavigation(this.stack) {
    Column() {
      Scroll() { /* 根页内容 */ }
    }
    .width('100%').height('100%').backgroundColor(COLOR_BG)
  }
  .hideTitleBar(true)                 // 根页自绘时隐藏系统标题栏
  .mode(NavigationMode.Stack)
  .navDestination(this.pageMap)       // 名字 → 子页映射
  .width('100%').height('100%')
}
```

**第 3 步：@Builder pageMap(name) 做映射**

```ts
@Builder
pageMap(name: string) {
  if (name === 'settings') { this.settingsDestination() }
  else if (name === 'about') { this.aboutDestination() }
  // ... 每个子页一行
}
```

**第 4 步：子页 = 自绘返回头 + 内容，外层必须是 HdsNavDestination**

```ts
@Builder
settingsDestination() {
  HdsNavDestination() {
    Column() {
      this.subpageHeader('设置')
      Column() { /* 内容 */ }.layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor(COLOR_BG)
  }
}

@Builder
subpageHeader(title: string) {
  Column() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([COLOR_PRIMARY])
      }
      .width(40).height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.closeSubpage())
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      Text(title).fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_TITLE)
    }
    .width('100%').height(48).padding({ left: 16, right: 16 })
  }
  .width('100%')
  .padding({ top: this.topSafeHeight })     // 顶部让开状态栏
}
```

**第 5 步：开 / 关子页（登录拦截 + 底栏联动）**

```ts
private openSubpage(name: string): void {
  if (!this.isLoggedIn && name !== 'settings' && name !== 'about') {
    router.pushUrl({ url: 'pages/LoginPage' });     // 未登录拦截
    return;
  }
  AppStorage.set('subpage_open', true);             // 通知底栏收起
  this.stack.pushPathByName(name, '');
  if (name === 'favourites') { this.loadFavourites(true); }   // 打开即加载
}

private closeSubpage(): void {
  this.stack.pop();
  // 只有完全退出子页栈才恢复底栏（三层子页返回一层时底栏应保持隐藏）
  if (this.stack.size() === 0) {
    AppStorage.set('subpage_open', false);
  }
}
```

### 5.2 规则与易错点

1. 子页里再开子页，**继续 push 到同一个 stack**（不要 `router.pushUrl`，否则底栏动画与返回层级都会错）。
2. 恢复底栏必须判断 `stack.size() === 0`。
3. `pageMap` 的字符串要与 `pushPathByName` **完全一致**——拼错不报错，只会白屏。
4. 子页内容必须包在 `HdsNavDestination()` 里，否则拿不到 HDS 转场与安全区处理。
5. 子页内容会被 NavDestination 冻结渲染（见 4.2），需要即时刷新的控件必须自持 `@StorageLink`。

---

## 6. 底部导航栏与子页切换动画

HdsTabs 自带收起/展开动画，**不要自己写平移动画**：

```ts
// 根壳组件
@StorageLink('subpage_open') @Watch('onSubpageChanged') subpageOpen: boolean = false;

onSubpageChanged(): void {
  if (this.subpageOpen) {
    this.tabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);  // 收起
  } else {
    this.tabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);  // 展开
  }
}
```

数据流：

```
子页 openSubpage()
  → AppStorage.set('subpage_open', true)
  → 根壳 @StorageLink + @Watch 触发 onSubpageChanged()
  → tabsController.applyHideAnimation(SCROLL_ANIMATION)   // 底栏收起
closeSubpage() 且 stack.size() === 0
  → AppStorage.set('subpage_open', false)
  → applyShowAnimation(SCROLL_ANIMATION)                   // 底栏恢复
```

**为什么用 AppStorage 而不是回调**：子页与底栏属于兄弟组件，没有直接引用关系；
AppStorage + @Watch 是最短的桥。

```ts
HdsTabs({ index: this.currentTab, controller: this.tabsController }) {
  TabContent() { HomePage() }.tabBar(this.tabLabel(0, '首页', $r('sys.symbol.house')))
  TabContent() { ProfilePage() }.tabBar(this.tabLabel(1, '我的', $r('sys.symbol.person')))
}
.key(this.subpageOpen ? 'tabs_stable' : ('tabs_' + this.materialLevel + '_' + this.materialRev))
.barOverlap(true)                       // 内容延伸到栏下（内容底部要留白）
.animationDuration(0)                   // 关闭默认切换缓动，避免与自定义动画打架
.barPosition(BarPosition.End)
.divider({ mode: DividerMode.NONE })
.barFloatingStyle({
  barBottomMargin: Math.max(0, this.bottomSafeHeight - 6),   // 全屏下抬到手势条上方再下移
  adaptToHandedness: true,
  lightColor: '#FF7CA8',
  systemMaterialEffect: {
    materialType: hdsMaterial.MaterialType.IMMERSIVE,
    materialLevel: this.hdsMaterialLevel()
  }
})
.onChange((index: number): void => {
  this.currentTab = index;
  AppStorage.set('active_tab', index);    // 记忆页签
})
```

---

## 7. 动画与交互规范

**原则**：全部使用原生能力（`animateTo` / `curves` / `TransitionEffect` / `clickEffect` / `attributeModifier`），
不手写帧动画、不引第三方动效库。**任何状态变化都要有过渡，不要硬切。**

| 场景 | 写法 |
|---|---|
| 按钮按压 | `clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })` |
| 列表卡按压 | `clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })` |
| 弹簧反馈 | `animateTo({ duration: 320, curve: curves.springMotion(0.55, 0.85) }, () => { /* 改状态 */ })` |
| 开关/档位切换 | 先 130ms 放到 1.12（`Curve.EaseOut`），再 320ms 弹簧回 1 并写入新值 |
| 弹窗内容进场 | `@State entered` + `.translate({ y: entered ? 0 : 24 })` + `TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))` |
| 图片占位 | 呼吸动画（opacity 0.4 ↔ 0.8 循环） |
| 标签/胶囊切换 | scale + 背景色过渡 |
| 列表增删 | `ForEach` + 稳定 key（避免整列表重建） |

### 7.1 全局动画开关

```ts
let animOn = AppStorage.get<boolean>('animations_enabled') ?? true;
if (animOn) {
  animateTo({ duration: 200, curve: Curve.EaseOut }, () => { this.value = next; });
} else {
  this.value = next;          // 关闭时直接赋值，不套 animateTo
}
```

---

## 8. 列表、网格与多设备适配

### 8.1 自适应列数（不要写死）

```ts
import { display } from '@kit.ArkUI';

export function screenWidthVp(): number {
  return px2vp(display.getDefaultDisplaySync().width);   // 注意 px → vp
}

/** 图标网格 */
export function adaptiveIconColumns(): string {
  let w = screenWidthVp();
  if (w >= 900) return '1fr 1fr 1fr 1fr 1fr 1fr';
  if (w >= 700) return '1fr 1fr 1fr 1fr 1fr';
  if (w >= 560) return '1fr 1fr 1fr 1fr';
  return '1fr 1fr 1fr';
}

/** 作品/内容卡片网格 */
export function adaptiveCardColumns(): string {
  let w = screenWidthVp();
  if (w >= 900) return '1fr 1fr 1fr 1fr 1fr';
  if (w >= 700) return '1fr 1fr 1fr 1fr';
  if (w >= 560) return '1fr 1fr 1fr';
  return '1fr 1fr';
}
```

```ts
Grid() { ForEach(list, (item: Item) => { GridItem() { Card({ item }) } }, (item: Item) => item.id) }
.columnsTemplate(adaptiveCardColumns())
.columnsGap(10).rowsGap(12)
```

### 8.2 悬浮导航栏不遮挡内容

滚动容器底部 padding 要给足「安全区 + 悬浮栏高度」：

```ts
.padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafeHeight + 76 })
```

### 8.3 阅读/图文类页面的平板限宽（两侧留黑）

```ts
// 单页 Swiper 与连续滚动 List 都要限宽
.constraintSize({ maxWidth: 780 })
```

配合深色背景即可自然居中留黑，避免平板上图片撑满全屏。

### 8.4 空态与错误态

列表为空**必须**给空态；加载失败**必须**给文案 + 重试按钮：

```ts
if (this.errorMsg.length > 0) {
  Column({ space: 12 }) {
    Text(this.errorMsg).fontSize(14).fontColor(COLOR_TEXT_HINT)
    Button('重新加载', { type: ButtonType.Normal })
      .onClick(() => this.load(true))
  }.width('100%').padding({ top: 60 }).alignItems(HorizontalAlign.Center)
} else if (this.list.length === 0 && !this.loading) {
  Column({ space: 10 }) {
    SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(36).fontColor([COLOR_TEXT_DISABLED])
    Text('暂无内容').fontSize(14).fontColor(COLOR_TEXT_HINT)
  }.width('100%').padding({ top: 70 }).alignItems(HorizontalAlign.Center)
} else { /* 列表 */ }
```

> 缺空态最坑：接口返回空数组时页面**纯白**，会被当成「页面坏了」。

---

## 9. 登录 / 注册页的正确写法

### 9.1 登录页骨架

```ts
@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State savePassword: boolean = true;
  @State usernameFocused: boolean = false;
  @State passwordFocused: boolean = false;
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  private stack: NavPathStack = new NavPathStack();
  private cooldownTimer: number = -1;

  build() {
    HdsNavigation(this.stack) {
      Column() { /* 表单 */ }
        .width('100%').height('100%').padding({ left: 24, right: 24 })
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
```

### 9.2 输入框要点（手感最好的一套）

```ts
TextInput({ placeholder: '用户名', text: this.username })
  .height(52)
  .fontSize(15)
  .backgroundColor(COLOR_CARD)
  .borderRadius(12)
  .padding({ left: 16, right: 16 })
  .border({ width: 1, color: this.usernameFocused ? COLOR_PRIMARY : COLOR_DIVIDER })  // 聚焦描边
  .enterKeyType(EnterKeyType.Next)          // 用户名 → 下一个
  .onFocus(() => { this.usernameFocused = true; })
  .onBlur(() => { this.usernameFocused = false; })
  .onChange((value: string) => this.username = value)

TextInput({ placeholder: '密码', text: this.password })
  .type(InputType.Password)                 // ★ 必须显式声明，否则明文
  .enterKeyType(EnterKeyType.Done)          // 密码 → 完成
  // ...同样的聚焦描边与 onChange
```

### 9.3 提交逻辑（含限流熔断）

```ts
async onLogin(): Promise<void> {
  if (!this.username.trim()) { this.errorMsg = '用户名不能为空'; return; }
  if (!this.password.trim()) { this.errorMsg = '密码不能为空'; return; }
  this.isLoading = true;
  this.errorMsg = '';
  try {
    await this.api.signIn(this.username.trim(), this.password);
    promptAction.showToast({ message: '登录成功', duration: 2000 });
    router.back();                                   // 成功后返回来源页
  } catch (err) {
    this.errorMsg = (err as Error).message || '登录失败，请稍后重试';
    if (this.cooldownTimer >= 0) { clearInterval(this.cooldownTimer); }
    this.cooldownTimer = setInterval(() => {          // 限流时每秒刷新剩余时间
      let remain = Api.getRateLimitRemainSec();
      if (remain > 0) {
        let unit = remain >= 60 ? Math.ceil(remain / 60) + ' 分钟' : remain + ' 秒';
        this.errorMsg = '请求过于频繁，请等约 ' + unit + ' 后再试（开关飞行模式换 IP 可立即恢复）';
      } else {
        clearInterval(this.cooldownTimer);
        this.cooldownTimer = -1;
        this.errorMsg = '限流已结束，可以重新尝试';
      }
    }, 1000);
  } finally {
    this.isLoading = false;
  }
}

aboutToDisappear(): void {            // ★ 必须清理，否则离开页面后定时器仍在跑
  if (this.cooldownTimer >= 0) {
    clearInterval(this.cooldownTimer);
    this.cooldownTimer = -1;
  }
}
```

### 9.4 登录页要点

1. 用户名/密码用 `@State` + `TextInput` 受控绑定（`text: this.x` + `onChange`），便于回填与清空。
2. `isLoading` 期间禁用提交按钮，**防止重复请求**（每次请求都消耗配额）。
3. 错误显示在表单下方（`errorMsg`），比 toast 更持久可读。
4. 成功后 `router.back()`；来源页在 `onPageShow` 里同步登录态即可自动刷新。
5. 需要「记住密码」时用 `preferences` 持久化（见 11.1），不要明文写文件。

### 9.5 注册页要点

- 独立路由页，从登录页 `router.pushUrl({ url: 'pages/RegisterPage' })` 进入。
- 校验顺序（先易后难、逐条提示）：
  1. 昵称长度（如 2~50 字符）；
  2. 用户名非空且**只允许字母数字**（`/^[a-zA-Z0-9]+$/`）；
  3. 密码长度下限（如 ≥ 8）；
  4. 所有必填项（如密保问题与答案）不能为空。
- 防重复提交：`if (this.registering) return; this.registering = true;` … `finally { this.registering = false; }`
- 错误中文化：把 `invalid` / `validation` 之类的原始错误映射为可读提示。
- 成功后**回填用户名再返回**，避免用户重输：

```ts
AppStorage.set('registered_username', username);
router.back();
// 登录页 aboutToAppear(): 读 'registered_username' 填进输入框并清空该键
```

---

## 10. 网络请求与请求签名

### 10.1 HTTP 客户端

```ts
import { http } from '@kit.NetworkKit';

// ★ 复用单例：每请求 createHttp+destroy 会把握手额度打满
private static shared: http.HttpRequest | null = null;
if (!shared) { shared = http.createHttp(); }

let options: http.HttpRequestOptions = {
  method: http.RequestMethod.POST,
  header: headers,
  extraData: body,
  expectDataType: http.HttpDataType.STRING,
  connectTimeout: 10000,
  readTimeout: 15000,
  usingProxy: true,                 // ★ 是 options 的属性，不是 HttpRequest 的
  protocol: http.HttpProtocol.HTTP2
};
let resp = await shared.request(url, options);
if (resp.responseCode !== 200) { /* 处理 */ }
let data = JSON.parse(resp.result as string);
```

**坑**：
1. `usingProxy` 挂错对象要么编译不过、要么静默不生效。
2. HTTP/2 必须显式设 `protocol`。
3. 超时时间务必设置，否则弱网下请求悬挂（配合加载态与重试按钮）。

### 10.2 rcp（需要按域名直连指定 IP 时）

```ts
import { rcp } from '@kit.RemoteCommunicationKit';
let rules: rcp.StaticDnsRule[] = [ /* domain → ip[] */ ];
let config: rcp.SessionConfiguration = { /* dnsRules: rules, ... */ };
let session = rcp.createSession(config);
let req = new rcp.Request(url, method, headers, body ?? undefined);
```

### 10.3 请求签名（HMAC-SHA256 常见形态）

```ts
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

let mac = cryptoFramework.createMac('SHA256');
let keyGen = cryptoFramework.createSymKeyGenerator('HMAC');
let symKey = await keyGen.convertKey({ data: keyBytes });
await mac.init(symKey);
await mac.update({ data: rawBytes });        // rawBytes = 待签名串
let out = await mac.doFinal();               // 再 hex / base64 编码

let encoder = new util.TextEncoder();
let b64 = new util.Base64Helper();
```

**坑**：
1. `init/update/doFinal` 全部是 **Promise**，漏 `await` 拿到空结果。
2. **签名的 path 必须与实际发出的 URL 完全一致**（含查询串、中文已 `encodeURIComponent`）。
3. 认证头若为裸 token，不要自作主张加 `Bearer `。

### 10.4 响应解包：先照抄已验证的同类接口

**典型事故**：某列表接口全空白，因为把外层 `data` 当成了分页对象：

```ts
// ❌ data = { comics: { docs, pages } }，却直接读 data.docs → 永远 undefined
let paged = data as Paged<T>;
return { list: paged.docs || [], pages: toNum(paged.pages) };

// ✅ 先取内层，再读 docs
let data = await this.request<Record<string, Object>>('comics?page=1&s=dd', 'GET', null, true);
let paged = data['comics'] as Paged<T>;
return { list: paged.docs || [], pages: toNum(paged.pages) };
```

> 经验：新接口一律**对照一个已经跑通的同类接口**的取字段方式，不要凭印象写。

### 10.5 限流与重试

- 服务端限流（如 HTTP 429 / 业务码）时，**不要自动重试**：会让请求量翻倍，越试越封。
- 给用户**明确文案 + 剩余时间倒计时 + 手动重试按钮**。
- 只有幂等的 GET 且明确知道配额充裕时，才考虑「一次性重试」。

---

## 11. 文件读写、系统选择器与导出

### 11.1 设置持久化（preferences）

```ts
import { preferences } from '@kit.ArkData';

this.prefs = await preferences.getPreferences(context, 'app_cache');
this.prefs?.putSync(key, value);
this.prefs?.flushSync();        // ★ 不 flush 不落盘，杀进程即丢
```

**坑**：`getPreferences` 需要 Context；在工具类/Ability 里要**显式传 context**（`getContext()` 只保证 UI 上下文可用）。

### 11.2 文件读写（fileIo）

```ts
import { fileIo as fs } from '@kit.CoreFileKit';

if (!fs.accessSync(dir)) { fs.mkdirSync(dir); }
let file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
fs.writeSync(file.fd, bytes);
fs.closeSync(file.fd);

let stat = fs.statSync(path);              // size / mtime
let names = fs.listFileSync(dir);
fs.unlinkSync(path);
```

**坑**：
1. `fs.rmdirSync()` **不能删非空目录** → 自己写递归删除。
2. 句柄用完必须 `closeSync`，否则文件被占用（重写会失败）。
3. 缓存目录用 `context.cacheDir`，持久数据用 `context.filesDir`。

### 11.3 系统文件保存对话框

```ts
import { picker, fileUri } from '@kit.CoreFileKit';

let options = new picker.DocumentSaveOptions();
options.newFileNames = ['导出文件.pdf'];            // 预设文件名
let documentViewPicker = new picker.DocumentViewPicker(ctx);
let uris = await documentViewPicker.save(options);  // 用户可自选目录
// 之后用 uris[0] 直接写文件

let shareUri = fileUri.getUriFromPath(localPath);   // 本地路径 → file:// uri（拖拽/分享必需）
```

### 11.4 手写 ZIP（无压缩 STORE）

需要：本地文件头 + 数据 + 中央目录 + EOCD，且 **CRC32 必须正确**。
验证方法：用系统解压/`.NET ZipFile` 解压比对字节。

### 11.5 手写 PDF（把图片合成为 PDF）

要点（缺一个都打不开）：

1. 每个对象必须包成 `N 0 obj ... endobj`；
2. 内容流必须带 `/Length N` 且用 `stream` / `endstream` 包裹；
3. **xref 的字节偏移必须精确**；
4. 图片用 `/DCTDecode`（JPEG）直接嵌入最省事。

---

## 12. 图片加载与缓存

### 12.1 三级缓存

```
内存缓存（Map，按 LRU 淘汰）
  ↓ 未命中
磁盘缓存（cacheDir 下按 URL 哈希命名，限制总大小 + LRU 清理）
  ↓ 未命中
网络（可多域名/镜像回退）
```

```ts
import { image } from '@kit.ImageKit';
let source = image.createImageSource(buf);       // ArrayBuffer → ImageSource
let pixelMap = await source.createPixelMap();    // 需要尺寸/预览时
```

### 12.2 组件化的图片加载（占位 + 失败兜底）

```ts
@Component
export struct NetImage {
  src: string = '';
  @State loaded: boolean = false;
  @State failed: boolean = false;

  build() {
    Stack() {
      if (!this.loaded && !this.failed) {
        Column().width('100%').height('100%')
          .backgroundColor(COLOR_PLACEHOLDER)      // 占位呼吸动画
      }
      Image(this.src)
        .objectFit(ImageFit.Cover)
        .onComplete(() => { this.loaded = true; })
        .onError(() => { this.failed = true; })    // 失败再走镜像回退
    }
  }
}
```

**坑**：
1. 大图必须按显示尺寸解码（`createPixelMap({ desiredSize })`），否则内存暴涨。
2. `pixelMap` / `imageSource` 用完 release。
3. 磁盘缓存要有上限与淘汰，否则无限增长。
4. 代理/直连切换要统一在下载层做，UI 层不感知。

---

## 13. 系统能力集成

### 13.1 音量键等物理按键（inputConsumer）

```ts
import { inputConsumer, KeyCode } from '@kit.InputKit';

let upConfig: inputConsumer.KeyPressedConfig = {
  key: KeyCode.KEYCODE_VOLUME_UP,
  action: 1,           // 1 = 按下
  isRepeat: false      // ★ 过滤长按重复
};
inputConsumer.on('keyPressed', upConfig, this.volumeUpCallback);
// 页面销毁务必注销
inputConsumer.off('keyPressed', this.volumeUpCallback);
```

**坑**：默认 `isRepeat: true` 时长按连发，表现为「按两次才生效」或连翻多页；再加 300ms 去抖更稳。
弹窗打开时应忽略按键，避免误触发。

### 13.2 拖拽（UDMF）

```ts
import { unifiedDataChannel } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';

let record = new unifiedDataChannel.Image();
record.uri = fileUri.getUriFromPath(localPath);
let data = new unifiedDataChannel.UnifiedData(record);

// 组件上：
.draggable(true)
.onDragStart(() => data)
.dragPreview(/* 需要 ImageModifier 或返回 { pixelMap } */)
```

**坑**：
1. 预览图不显示通常是预览数据结构不对（返回 `{ pixelMap }`）；
2. `@Builder` 名称不要与内置属性同名（如 `dragPreview`），否则编译报错；
3. uri 必须是 `file://` 形式（用 `fileUri.getUriFromPath`）。

### 13.3 系统分享（ShareKit）

```ts
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';

let record: systemShare.SharedRecord = { /* title / uri / ... */ };
let sharedData = new systemShare.SharedData(record);
let controller = new systemShare.ShareController(sharedData);
controller.show(context as common.UIAbilityContext, {
  previewMode: systemShare.SharePreviewMode.DEFAULT
});
```

> 分享优先用 `systemShare`；`pasteboard`（剪贴板）只适合「复制文本」这类轻场景。

### 13.4 窗口能力

```ts
import { window } from '@kit.ArkUI';

// 全屏沉浸（EntryAbility.onWindowStageCreate 内）
windowStage.getMainWindow((err, win) => {
  if (err.code) { return; }
  win.setWindowLayoutFullScreen(true);
});

// 屏幕方向（阅读器横竖屏锁定）
window.getLastWindow(context).then((win: window.Window) => {
  win.setPreferredOrientation(window.Orientation.LANDSCAPE);   // PORTRAIT / UNSPECIFIED
});
```

### 13.5 防截屏

```ts
windowClass.setWindowPrivacyMode(true);
```

**坑**：必须在 `module.json5` 声明 `ohos.permission.PRIVACY_WINDOW`，否则**静默失效**（开关能点但没效果）。

### 13.6 网络状态（判断 WiFi）

```ts
import { connection } from '@kit.NetworkKit';
let net = connection.getDefaultNetSync();
let caps = connection.getNetCapabilitiesSync(net);
let isWifi = caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI);
```

---

## 14. 官方 API 清单与正确用法（按 Kit）

### 14.1 @kit.ArkUI

| API | 用途 | 要点 / 坑 |
|---|---|---|
| `router.pushUrl/back/getParams` | 路由 | 参数弱类型，取出要断言；子页用 NavPathStack 不用 router |
| `display.getDefaultDisplaySync()` | 屏幕尺寸 | 返回 px，布局要 `px2vp` |
| `promptAction.showToast/showDialog` | 提示 | toast 同时只显示一个 |
| `curves.springMotion(v, d)` | 弹簧曲线 | 必须 `import { curves } from '@kit.ArkUI'` |
| `window.getLastWindow/setPreferredOrientation` | 窗口方向 | 需要 context；离屏还原 `UNSPECIFIED` |
| `window.setWindowLayoutFullScreen` | 全屏 | 需与 HDS 安全区标志配合 |
| `window.setWindowPrivacyMode` | 防截屏 | 需声明权限 |
| `uiMaterial.ImmersiveMaterial` + `CommonModifier` | 官方材质（API 26+） | 继承 `CommonModifier` 实现 `applyNormalAttribute`，用 `.attributeModifier()` 挂载 |
| `animateTo` / `TransitionEffect` / `clickEffect` | 动画（全局内置） | 见第 7 章 |
| `AppStorage` / `@StorageLink` / `@StorageProp` / `@Watch` | 状态 | `AppStorage.get()` 非响应式 |

### 14.2 @kit.AbilityKit

```ts
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, bundleManager, common } from '@kit.AbilityKit';

this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);

onConfigurationUpdate(newConfig: Configuration): void {
  const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  AppStorage.setOrCreate('system_color_mode', isDark ? 'dark' : 'light');
}

let info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
AppStorage.setOrCreate('app_version', info.versionName);
```

- `common.UIAbilityContext` 通过 `getContext(this) as common.UIAbilityContext` 获取；
  **非 UI 场景要显式传 context**。

### 14.3 @kit.UIDesignKit

| API | 用途 | 要点 / 坑 |
|---|---|---|
| `HdsNavigation(stack)` + `.navDestination(builder)` | 子页容器 | `.mode(NavigationMode.Stack)`；根页自绘时 `.hideTitleBar(true)` |
| 标题栏 Options | 沉浸标题 | 必须 `enableComponentSafeArea` + `avoidLayoutSafeArea` |
| `HdsNavDestination()` | 子页外壳 | 少了它没有转场/安全区处理 |
| `HdsTabs` + `HdsTabsController` | 底部页签 | 改 `.key()` 会销毁整棵子树 |
| `applyHideAnimation/applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)` | 子页进出底栏动画 | 无运行时换材质 API |
| `hdsMaterial.MaterialType/MaterialLevel` | 材质 | 档位变更需重建才生效 |
| `hdsEffect` | 旧设备材质回退 | 按 API 版本分支 |
| `DividerMode` / `DividerShowType` | 分割线 | — |

### 14.4 @kit.NetworkKit

`http`（`createHttp` / `HttpRequestOptions`：`method/header/extraData/expectDataType/connectTimeout/readTimeout/usingProxy/protocol`）、
`rcp`（`createSession` / `StaticDnsRule`）、`socket`（`constructTCPSocketInstance` 做握手测速）、
`connection`（`getDefaultNetSync` / `getNetCapabilitiesSync` / `NetBearType.BEARER_WIFI`）。

### 14.5 @kit.CoreFileKit

`fileIo`（`openSync/writeSync/readSync/closeSync/accessSync/mkdirSync/listFileSync/statSync/unlinkSync/rmdirSync`）、
`picker.DocumentViewPicker`（`.save()` / `.select()`）、`fileUri.getUriFromPath`、`BackupExtensionAbility`。

### 14.6 @kit.ArkData

`preferences.getPreferences/putSync/flushSync`、`unifiedDataChannel`（`Image` / `UnifiedData` 拖拽）。

### 14.7 @kit.InputKit

`inputConsumer.on('keyPressed', KeyPressedConfig, cb)` / `.off(...)`；`KeyCode.KEYCODE_*`。

### 14.8 @kit.CryptoArchitectureKit + @kit.ArkTS

`cryptoFramework.createMac/createSymKeyGenerator/convertKey/init/update/doFinal`；
`util.TextEncoder` / `util.Base64Helper`。

### 14.9 @kit.ImageKit / @kit.ShareKit / @kit.BasicServicesKit / @kit.PerformanceAnalysisKit

`image.createImageSource/createPixelMap`；
`systemShare.SharedRecord/SharedData/ShareController.show`；
`deviceInfo.sdkApiVersion`、`BusinessError`；
`hilog.info(DOMAIN, tag, '%{public}s', msg)`——**不写 `%{public}s` 日志里只有 `<private>`**。

---

## 15. 兼容性与版本分级

```ts
import { deviceInfo } from '@kit.BasicServicesKit';

export function supportsImmersiveComponent(): boolean {
  return deviceInfo.sdkApiVersion >= 26;      // 组件级沉浸材质
}
export function supportsHdsMaterial(): boolean {
  return deviceInfo.sdkApiVersion >= 23;      // HDS 回退材质
}
```

**原则**：

1. 用能力探测分支 + 回退实现，**不要假定设备版本**。
2. 新 API 先查最低可用版本；不可用时给视觉上不突兀的降级样式。
3. 官方 API 可能**回收/调整**（例如移除部分组件的材质支持）：
   这时宁可**整页统一样式**，也不要「一半玻璃一半纯色」的割裂。
4. 若某版本必须保留旧观感，可以**并存两个发布版本**（旧版本继续可下载），并在更新日志说明。

---

## 16. 打包发布流程（通用）

1. 改版本号：`AppScope/app.json5` → `versionCode`（自增编码）+ `versionName`
2. 更新应用内更新日志（若 App 内展示）
3. 本地构建 → 真机安装验证
4. 提交、打标签、推送
5. 建 Release / 分发，上传 **unsigned** HAP

```bash
git add -A
git commit -m "vX.Y.Z: 变更摘要"
git push origin main
git tag vX.Y.Z
git push origin refs/tags/vX.Y.Z
```

### 16.1 中文正文乱码（PowerShell 提交 Release 时的经典坑）

用 `ConvertTo-Json` + `Invoke-RestMethod` 发中文正文，会变成 `????`。**改用字节直发**：

```powershell
$json  = [System.IO.File]::ReadAllText('.body.json', [System.Text.Encoding]::UTF8)  # 文件里换行写成 \n 转义
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $bytes `
  -ContentType 'application/json; charset=utf-8'
```

- 上传二进制资产必须显式 `-ContentType 'application/octet-stream'`，否则报 422。
- 覆盖式发布（不升版本）：`git commit --amend` + `push -f` + `git tag -f` + 重新上传资产。

---

## 17. 工具使用与协作经验（尤其给 AI Agent）

1. **改代码优先用「先读后改」的文件编辑**，不要用脚本字符串替换：
   - 行尾 CRLF/LF 不一致会让 `Replace` 静默失败；
   - `LastIndexOf` 之类定位会命中代码里的同名标识符，把声明改坏引发**大量级联报错**；
   - 必须脚本化时用正则 `\r?\n` 兼容行尾，并在改完 `grep` 验证。
2. **文件被改坏就回滚**：`git checkout HEAD -- <file>` 后干净重做，比在废墟上修补快得多。
3. **先验证再下结论**：每步用 grep/read 核对，不要凭「应该改好了」。
4. **长任务放后台**：构建/下载用后台任务，完成后收集输出，不要占着前台超时。
5. **权限与沙箱**：某些执行环境里，外层程序的权限**不会**自动下传给嵌套工具调用，
   需要给实际执行的调用单独声明；只读工具可用不代表写/进程类工具可用。
6. **报错先看第一条**：ArkTS 的级联错误会淹没真正原因。

---

## 18. 常见构建场景详解

### 18.1 返回键的构建（区域 / 颜色 / 系统返回拦截）

**三种返回入口，别混用**：

| 入口 | 用法 | 适用 |
|---|---|---|
| 系统标题栏返回 | `HdsNavigation(...).hideBackButton(false)` | 使用系统标题栏的路由页 |
| 自绘返回键 | 圆形 Button + `SymbolGlyph` + `onClick(closeSubpage)` | 根页隐藏标题栏的子页（统一放 `subpageHeader`） |
| 手势/物理返回 | `.onBackPressed(() => { ...; return true; })` | 需要拦截系统返回的地方 |

```ts
/** 子页统一返回头：圆形返回键 + 大标题 */
@Builder
subpageHeader(title: string) {
  Column() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([COLOR_TEXT_TITLE])       // ★ 数组；跟随主题色资源
      }
      .width(40).height(40)                     // 视觉尺寸
      .backgroundColor(Color.Transparent)
      .onClick(() => this.closeSubpage())       // ★ 走统一关闭函数
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })

      Text(title).fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_TITLE)
    }
    .width('100%').height(48)
    .padding({ left: 16, right: 16 })
  }
  .width('100%')
  .padding({ top: this.topSafeHeight })         // 顶部让开状态栏
}
```

**点击热区（区域）**：视觉 40×40 偏小，保证热区 ≥ 44~48 vp，两种做法：

```ts
// 做法 A：放大尺寸（视觉与热区一起变大）
Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20) }
  .width(48).height(48)

// 做法 B：保持视觉，仅扩大响应区域
.responseRegion({ x: -6, y: -6, width: 'calc(100% + 12vp)', height: 'calc(100% + 12vp)' })
```

**拦截系统返回**（自绘返回键必须配套，否则手势返回会直接退出应用或退到上一路由页）：

```ts
.hideTitleBar(true)
.hideBackButton(true)
.onBackPressed((): boolean => {
  this.closeSubpage();
  return true;        // ★ true = 已消费，不再向上传递
})
```

路由页要拦截返回则实现页面级回调：

```ts
onBackPress(): boolean {
  if (this.hasUnsavedChanges) { this.confirmDiscard(); return true; }
  return false;       // false = 交回系统处理
}
```

**颜色**：一律用 `$r('app.color.*')` 或主题色常量，**不要硬编码** `#000000`，否则深色模式看不见。

**常见坑**：

1. 只写了 `SymbolGlyph` 没设 `fontColor` → 深色模式下图标不可见。
2. 自绘返回键没接 `.onBackPressed` → 系统返回直接跳错层级。
3. 子页里用 `router.back()` → 会退到上一个**路由页**而不是关闭当前子页；子页应用 `stack.pop()`。
4. `hideBackButton(true)` 后忘记画返回键 → 用户没有返回入口。
5. 返回键放在顶部安全区之外 → 被状态栏压住点不到。

### 18.2 深色模式的构建

**第 1 步：颜色资源双份，键名必须完全一致**

```
resources/base/element/color.json      → 浅色
resources/dark/element/color.json      → 深色（同一套 key）
```

```json
{
  "color": [
    { "name": "app_bg",         "value": "#FFF7F8FA" },
    { "name": "app_card",       "value": "#FFFFFFFF" },
    { "name": "app_text_title", "value": "#FF1A1A1A" },
    { "name": "app_divider",    "value": "#14000000" },
    { "name": "app_primary",    "value": "#FF7CA8" }
  ]
}
```

```ts
// 组件里统一用 $r，系统按当前模式自动取对应值
.backgroundColor($r('app.color.app_card'))
.fontColor($r('app.color.app_text_title'))
```

**第 2 步：切换模式（应用级，立即生效、无需重建组件）**

```ts
import { ConfigurationConstant } from '@kit.AbilityKit';

// 浅色 / 深色 / 跟随系统
this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
```

**第 3 步：跟随系统时监听系统变化**

```ts
onConfigurationUpdate(newConfig: Configuration): void {
  const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  AppStorage.setOrCreate('system_color_mode', isDark ? 'dark' : 'light');
}
```

**第 4 步：启动时恢复用户选择（避免启动瞬间闪浅色）**

```ts
// EntryAbility.onCreate
const saved = readSetting('color_mode');                 // 'system' | 'light' | 'dark'
this.context.getApplicationContext().setColorMode(toMode(saved));
```

**第 5 步：需要「色值字符串」的原生 API 怎么办**

部分原生 API（自定义材质、Canvas、签名配色等）要的是 `string`，`$r()` 不能直接用：

```ts
// 方案 A：并排维护一份 hex 常量（最简单，注意与资源同步）
private accentHex: string = '#FF7CA8';

// 方案 B：从资源解析（拿 number 再转 hex）
// const colorNum: number = getContext(this).resourceManager.getColorSync($r('app.color.app_primary'));
```

**深色下的图片**：放 `resources/dark/media/` 同名覆盖；单色图标改用可染色方式（见 18.6）。

**常见坑**：

| 现象 | 原因 |
|---|---|
| 深色下部分控件仍是浅色 | 只在 `base` 定义了该色，`dark` 缺失 |
| 深色下白底白字 | 组件里硬编码了 `#FFFFFF` |
| 静态页文字发灰不可读 | 用了 `Color.Gray` 之类的固定色而非主题资源 |
| 切换后部分区域不变 | 用了 `AppStorage.get()` 取值（非响应式）或原生 API 缓存了旧色 |
| 启动瞬间闪白 | 未在 Ability 启动阶段应用保存的模式 |

### 18.3 列表的构建方式

**选型**：

| 场景 | 组件 | 说明 |
|---|---|---|
| 线性长列表 | `List` + `ListItem`（+`ListItemGroup`） | 自带虚拟化 |
| 网格 | `Grid` + `GridItem` | 列数按屏宽自适应（第 8 章） |
| 瀑布流 | `WaterFlow` + `FlowItem` | 高度不一的内容 |
| 少量内容 | `Scroll` + `Column` | 内容少时才用；长列表会全量渲染卡顿 |

**设置类「分组卡片列表」标准写法**（最常用的形态）：

```ts
Column() {
  ForEach(this.menuItems, (item: MenuItemData, index: number) => {
    Row() {
      Image($r('app.media.' + item.icon)).width(20).height(20)
      Text(item.label).fontSize(15).fontColor($r('app.color.app_text_title'))
        .layoutWeight(1).margin({ left: 12 })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
        .fontColor([$r('app.color.app_text_hint')])
    }
    .width('100%').height(52).padding({ left: 16, right: 16 })
    .onClick(() => this.openSubpage(item.page))

    if (index < this.menuItems.length - 1) {
      Divider().height(1).color($r('app.color.app_divider')).margin({ left: 48 })   // 缩进分割线
    }
  }, (item: MenuItemData) => item.label)        // ★ key 必须稳定唯一
}
.width('100%')
.backgroundColor($r('app.color.app_card'))
.borderRadius(18)
.border({ width: 1, color: $r('app.color.app_divider') })
.padding({ top: 4, bottom: 4 })
```

**长列表用 LazyForEach（性能关键）**

```ts
class DataSource implements IDataSource {
  private items: Item[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): Item { return this.items[index]; }
  registerDataChangeListener(l: DataChangeListener): void { this.listeners.push(l); }
  unregisterDataChangeListener(l: DataChangeListener): void {
    const i = this.listeners.indexOf(l);
    if (i >= 0) { this.listeners.splice(i, 1); }
  }
}

List() {
  LazyForEach(this.ds, (item: Item) => {
    ListItem() { Card({ item: item }) }
  }, (item: Item) => item.id)
}
.cachedCount(10)                              // 预加载数量
.scrollBar(BarState.Off)
.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
.onReachEnd(() => this.loadMore())            // 触底分页
```

**常见坑**：

1. `ForEach` 的 key 用 `index` → 增删后错位、状态串台；必须用稳定唯一 id。
2. 把 `List` 嵌进 `Scroll` → 虚拟化失效，长列表全部渲染导致卡顿。
3. 嵌套滚动冲突（内层滑完外层不滑）→ 用 `.nestedScroll({ scrollForward, scrollBackward })`。
4. 底部被悬浮导航栏遮挡 → 底部 padding 给 `bottomSafeHeight + 栏高`（见 8.2）。
5. 列表为空或加载失败没做空态 → 页面看起来像坏了（见 8.4）。
6. 每次 build 里现算大数组 → 预先转成轻量 VM 再渲染。

### 18.4 检查更新（完整流程）

```ts
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';

@State checkingUpdate: boolean = false;

private async checkUpdate(): Promise<void> {
  if (this.checkingUpdate) { return; }              // ★ 防重复点击
  this.checkingUpdate = true;
  let request = http.createHttp();
  try {
    let response = await request.request(LATEST_RELEASE_API, {
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
    let current = AppStorage.get<string>('app_version') ?? '';
    if (version.length > 0 && version !== current) {
      this.updateVersion = version;
      this.updateBody = String(data['body'] ?? '');      // Release 说明（Markdown）
      this.updateUrl = String(data['html_url'] ?? '');
      this.sheetKind = 0;
      this.showSheet = true;                             // 弹出更新弹窗
    } else {
      promptAction.showToast({ message: '当前已是最新版本 v' + current, duration: 2000 });
    }
  } catch (err) {
    promptAction.showToast({ message: '检查更新失败：' + (err as Error).message, duration: 2000 });
  } finally {
    this.checkingUpdate = false;
    request.destroy();                                   // ★ 释放
  }
}
```

**要点与坑**：

1. **版本比较别用字符串直接比大小**：1.10 与 1.9 的字符串比较会得到错误结果。应按段拆数字比较（`split('.')` 逐段 `Number()`），或直接依赖仓库/服务的 latest 语义。
2. 当前版本从 `bundleManager.getBundleInfoForSelfSync(...)` 取，**在 Ability 启动时写入 AppStorage**，页面才读得到。
3. 网络失败、非 200、JSON 缺字段都要有兜底（`?? ''`），不要抛到界面。
4. 更新说明是 Markdown，而 ArkUI **没有内置 Markdown 组件** → 轻量解析（见 18.5）。
5. 是否在「已是最新」时也弹内容弹窗属于产品决策，需与产品明确。
6. 请求对象用完 `destroy()`，否则多次检查会堆积。

### 18.5 关于页 / 应用信息 / 更新日志 / 隐私政策

**应用信息（版本、包名）**

```ts
import { bundleManager } from '@kit.AbilityKit';
let info = bundleManager.getBundleInfoForSelfSync(
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
AppStorage.setOrCreate('app_version', info.versionName);     // 全局可用
```

**关于页结构**：分组卡片列表（「关于」/「文档」），每行右侧箭头，点击打开对应弹窗或链接。

```
关于
  ├─ 应用名称 / 版本号（只读展示）
  ├─ 检查更新        → 网络校验 + 更新弹窗
  ├─ 项目主页        → 打开外部链接
文档
  ├─ 更新日志        → sheet
  ├─ 隐私政策        → sheet
  └─ 用户协议        → sheet
```

**更新日志**：本地常量数组 + 可折叠卡片（展开时给 `animateTo` + `transition`）

```ts
interface ChangelogEntry { version: string; date: string; items: string[]; }

const CHANGELOG_ENTRIES: ChangelogEntry[] = [
  { version: '1.3.0', date: '2026-08-17', items: ['新增…', '修复…'] },
  { version: '1.2.0', date: '2026-08-15', items: ['…'] }
];
```

**隐私政策**：长文本放进 sheet 内的 `Scroll`，按「小标题 + 正文」分段渲染。

**统一弹窗分发**（避免多 `bindSheet` 互顶，见 3.4）

```ts
@State sheetKind: number = 0;    // 0=更新 1=更新日志 2=隐私政策
@State showSheet: boolean = false;

.bindSheet($$this.showSheet, this.bottomSheet(), { /* ... */ })

@Builder
bottomSheet() {
  if (this.sheetKind === 0) { this.sheetUpdate() }
  else if (this.sheetKind === 1) { this.sheetChangelog() }
  else { this.sheetPrivacy() }
}
```

**Markdown 轻量解析（无第三方库，仅支持标题/列表/分隔线/加粗）**

```ts
interface UpdateBlock { kind: string; text: string; }   // h1|h2|h3|bullet|text
interface MdRun { text: string; bold: boolean; }

private markdownLines(): UpdateBlock[] {
  let blocks: UpdateBlock[] = [];
  for (let line of this.updateBody.split('\n')) {
    let t = line.trim();
    if (t.length === 0 || t === '---') { continue; }
    if (t.startsWith('###')) { blocks.push({ kind: 'h3', text: t.substring(3).trim() }); }
    else if (t.startsWith('##')) { blocks.push({ kind: 'h2', text: t.substring(2).trim() }); }
    else if (t.startsWith('# ')) { blocks.push({ kind: 'h1', text: t.substring(2).trim() }); }
    else if (t.startsWith('- ') || t.startsWith('* ')) { blocks.push({ kind: 'bullet', text: t.substring(2).trim() }); }
    else { blocks.push({ kind: 'text', text: t }); }
  }
  return blocks;
}

/** 行内加粗拆段：以 ** 为界交替切换 bold */
private boldRuns(text: string): MdRun[] {
  let runs: MdRun[] = [];
  let rest = text;
  let bold = false;
  while (rest.length > 0) {
    let idx = rest.indexOf('**');
    if (idx < 0) { runs.push({ text: rest, bold: bold }); break; }
    if (idx > 0) { runs.push({ text: rest.substring(0, idx), bold: bold }); }
    rest = rest.substring(idx + 2);
    bold = !bold;
  }
  return runs;
}
```

**打开外部链接**：用 `UIAbilityContext.openLink(url)`（或 `Want` + `startAbility`），不要在 Web 组件里硬塞。

**常见坑**：

1. 版本号没在 Ability 启动阶段写入 AppStorage → 关于页读不到。
2. sheet 内容超过屏幕没包 `Scroll` → 溢出且无法滚动。
3. 多个 `bindSheet` 挂在同一个组件上 → 只有最后一个生效（见 3.4）。
4. 大体量文案直接写在 `@Component` 里 → 编译慢、难维护；应抽到常量文件。
5. 更新日志折叠卡片的展开/收起没加动画 → 生硬（用 `animateTo` + `transition`）。

### 18.6 SVG 与图标体系

**三种图标来源**：

| 来源 | 写法 | 特点 |
|---|---|---|
| 系统符号 | `SymbolGlyph($r('sys.symbol.chevron_left'))` | 自动适配字重/动效，可 `fontSize` / `fontColor` |
| 工程 SVG | `Image($r('app.media.ic_arrow'))` | 矢量清晰，可染色 |
| 位图 PNG | `Image($r('app.media.ic_logo'))` | 复杂插画，注意多倍图 |

**SVG 染色（关键）**

```ts
Image($r('app.media.ic_arrow'))
  .width(24).height(24)
  .renderingMode(ImageRenderMode.Template)   // ★ 忽略 SVG 自带颜色，交给 fillColor
  .fillColor($r('app.color.app_text_title')) // 跟随深浅色
```

```ts
// 系统符号的颜色参数是数组
SymbolGlyph($r('sys.symbol.chevron_right'))
  .fontSize(16)
  .fontColor([$r('app.color.app_text_hint')])
```

**坑与规则**：

1. SVG 内部写死了 `fill` 颜色时，**不设 Template 则 `fillColor` 无效**，颜色不会跟随主题。
2. **多色/渐变 SVG 不要用 `Template`**——会被整体染成单色。
3. `SymbolGlyph.fontColor()` 传的是**数组**；传单值可能编译不过或不生效。
4. 矢量图标无需多倍图；位图要提供足够分辨率并配 `.objectFit(ImageFit.Contain)`。
5. 深色适配：单色图标走 `fillColor` + 主题色；彩色插画放 `resources/dark/media/` 同名覆盖。
6. 头像/占位统一 `.objectFit(ImageFit.Cover)` + `.borderRadius(半径)`，避免拉伸变形。
7. 应用图标与启动图：`AppScope/resources/base/media/app_icon.png`、模块的 `startWindowIcon`。

**推荐体系**：优先用系统符号（`sys.symbol.*`）保证风格统一；品牌元素用自绘 SVG；复杂插画用 PNG；所有图标颜色一律走主题色资源，禁止硬编码。

---

## 19. 上线前检查清单

- [ ] `AppScope/app.json5` 版本号已更新
- [ ] 应用内更新日志/变更说明文案正确，中文无乱码
- [ ] 全量构建 `BUILD SUCCESSFUL`
- [ ] 真机安装 + **冷启动**验证（改过 HdsTabs / bindSheet / NavDestination 的重点回归）
- [ ] 列表页：有数据 / 空数据 / 加载失败 三种状态都有界面
- [ ] 设置项持久化（重启后仍生效）
- [ ] 深浅色模式、平板横屏、大屏列数均正常
- [ ] 需要权限的功能在 `module.json5` 已声明并实测生效
- [ ] 分享 / 导出 / 拖拽等系统能力真机实测
- [ ] 版本库干净（无多余产物、无签名包、无临时文件）
- [ ] Release 正文编码正确、资产为 unsigned HAP
