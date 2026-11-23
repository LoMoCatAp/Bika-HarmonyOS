import { curves, promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';
import { HdsColorPicker, HdsNavDestination } from '@kit.UIDesignKit';
import { ACCENT_COLORS_KEY, ACCENT_ID_KEY, ACCENT_PRESETS, ACCENT_SETTINGS_KEY, AccentColors, AccentPreset,
  DEFAULT_ACCENT_COLORS, accentColors, accentPreset, applyNativeAccent, customAccentHex, customAccentId,
  normalizeAccentHex, syncAccentColors } from '../../common/AppearanceAccent';
import { CacheManager } from '../../common/CacheManager';
import { compatibleSheetOptions } from '../../common/CompatibleMaterial';
import { COLOR_BG, COLOR_CARD, COLOR_DIVIDER, COLOR_INPUT_BG, COLOR_TEXT_SECONDARY, COLOR_TEXT_TITLE } from '../../common/Constants';
import { DESKTOP_ICONS, DesktopIcon, DesktopIconOption, canSwitchDesktopIcon, desktopIcon, readDesktopIcon,
  switchDesktopIcon } from '../../common/DesktopIcons';
import { navigationBlurTitleBar } from '../../common/NavigationBlur';
import { DetailGlassCapsule } from '../../components/DetailGlassCapsule';
import { MaterialLevelSelect } from './MaterialLevelSelect';
import { COLOR_MODE_OPTIONS, MaterialOption } from './ProfileOptions';

const ICON_PREVIEW_SPRING = curves.springMotion(0.26, 0.88);

const MODE_OPTIONS: SelectOption[] = COLOR_MODE_OPTIONS.map((option: MaterialOption): SelectOption => {
  return { value: option.label };
});

@Component
export struct ProfileAppearancePage {
  scroller: Scroller = new Scroller();
  subpageContentTop: number = 64;
  selectColorModeOption: (index: number) => void = (_index: number): void => {};
  closeSubpage: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafeHeight: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafeHeight: number = 0;
  @StorageProp('bika_color_mode') colorMode: string = 'system';
  @StorageProp('system_color_mode') systemColorMode: string = 'light';
  @StorageProp('bika_material_level') materialLevel: string = 'EXQUISITE';
  @StorageProp('bika_material_style') materialStyle: string = 'THIN';
  @StorageProp(ACCENT_ID_KEY) accentId: string = 'bika';
  @StorageProp(ACCENT_COLORS_KEY) colors: AccentColors = DEFAULT_ACCENT_COLORS;
  @StorageLink('bika_animations') animationsEnabled: boolean = true;
  @State accentSheetOpen: boolean = false;
  @State draftAccent: string = 'bika';
  @State customHexInput: string = '';
  @State accentSaving: boolean = false;
  private accentToastPending: boolean = false;
  @State iconSheetOpen: boolean = false;
  @State appliedIcon: string = '';
  @State iconPortraitPreviews: string[] = [];
  @State iconKnown: boolean = false;
  private iconReading: boolean = false;
  private iconChanging: boolean = false;
  private readonly desktopIconSupported: boolean = canSwitchDesktopIcon();
  private readonly nativeColorPicker: boolean = deviceInfo.sdkApiVersion >= 26 &&
    canIUse('SystemCapability.UIDesign.HDSPattern.Standard');

  private appearanceSheetOptions(title: string, onDisappear?: () => void): SheetOptions {
    return compatibleSheetOptions({
      title: { title },
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      dragBar: false,
      onDisappear
    }, true, this.materialStyle, this.materialLevel);
  }

  private modeIndex(): number {
    return Math.max(0, COLOR_MODE_OPTIONS.findIndex((option: MaterialOption): boolean =>
      option.value === this.colorMode));
  }

  private previewColors(id: string = this.draftAccent): AccentColors {
    const mode = this.colorMode === 'system' ? this.systemColorMode : this.colorMode;
    return accentColors(id, mode);
  }

  private async readIcon(): Promise<void> {
    if (this.iconReading || this.iconChanging) {
      return;
    }
    this.iconReading = true;
    try {
      const iconId = await readDesktopIcon();
      if (this.iconSheetOpen && iconId !== this.appliedIcon) {
        this.iconPortraitPreviews = [iconId];
      }
      this.appliedIcon = iconId;
      this.iconKnown = true;
    } catch (error) {
      console.warn('[ProfileAppearance] reading desktop icon failed: ' + String(error));
    } finally {
      this.iconReading = false;
    }
  }

  private previewIcon(option: DesktopIconOption): DesktopIcon {
    const portrait = option.portrait;
    if (portrait && this.iconPortraitPreviews.includes(portrait.id)) {
      return portrait;
    }
    return option;
  }

  private toggleIconPreview(option: DesktopIconOption): void {
    if (this.desktopIconSupported && (this.iconReading || this.iconChanging)) {
      return;
    }
    const portrait = option.portrait;
    if (!portrait) {
      promptAction.showToast({ message: '没有啦!', duration: 1600 });
      return;
    }
    this.iconPortraitPreviews = this.iconPortraitPreviews.includes(portrait.id)
      ? this.iconPortraitPreviews.filter((id: string): boolean => id !== portrait.id)
      : [...this.iconPortraitPreviews, portrait.id];
    this.playIconSwitchHaptic();
  }

  private async playIconSwitchHaptic(): Promise<void> {
    if (!canIUse('SystemCapability.Sensors.MiscDevice')) {
      return;
    }
    try {
      await vibrator.startVibration({ type: 'time', duration: 24 }, { usage: 'touch' });
    } catch (_) {
      // 部分设备没有可用的振动器，继续切换图标预览。
    }
  }

  private iconPreviewMotion(option: DesktopIconOption, icon: DesktopIcon): AnimateParam {
    if (!this.animationsEnabled) {
      return { duration: 0 };
    }
    return {
      curve: ICON_PREVIEW_SPRING,
      delay: this.previewIcon(option).id === icon.id ? 72 : 0
    };
  }

  private async changeIcon(icon: DesktopIcon): Promise<void> {
    if (!this.desktopIconSupported || this.iconChanging || this.iconReading ||
      (this.iconKnown && this.appliedIcon === icon.id)) {
      return;
    }
    this.iconChanging = true;
    try {
      await switchDesktopIcon(icon.id);
      this.appliedIcon = icon.id;
      this.iconKnown = true;
      promptAction.showToast({ message: '已更换应用图标', duration: 1600 });
    } catch (error) {
      console.warn('[ProfileAppearance] changing desktop icon failed: ' + String(error));
      promptAction.showToast({ message: '更换图标失败，请重试', duration: 2000 });
    } finally {
      this.iconChanging = false;
    }
  }

  private startAccentPreview(): void {
    this.draftAccent = this.accentId;
    this.customHexInput = customAccentHex(this.accentId);
    this.accentSheetOpen = true;
  }

  private chooseCustomAccent(): void {
    this.setPickedColor(normalizeAccentHex(this.customHexInput) || accentPreset(this.draftAccent).light);
  }

  private setPickedColor(value: string): void {
    const hex = normalizeAccentHex(value);
    if (hex.length > 0) {
      this.customHexInput = hex;
      this.draftAccent = customAccentId(hex);
    }
  }

  private changeCustomHex(value: string): void {
    this.customHexInput = value;
    const id = customAccentId(value);
    if (id.length > 0) {
      this.draftAccent = id;
    }
  }

  private validAccentDraft(): boolean {
    return customAccentHex(this.draftAccent).length === 0 || normalizeAccentHex(this.customHexInput).length > 0;
  }

  private async applyAccent(): Promise<void> {
    if (this.accentSaving || !this.validAccentDraft()) {
      return;
    }
    const preset = this.draftAccent;
    this.accentSaving = true;
    try {
      if (preset !== this.accentId) {
        const cache = await CacheManager.getInstance();
        if (!cache.isReady()) {
          throw new Error('Settings unavailable');
        }
        cache.saveSetting(ACCENT_SETTINGS_KEY, preset);
        syncAccentColors(preset);
        this.getUIContext().runScopedTask((): void => applyNativeAccent(preset));
      }
    } catch (error) {
      console.warn('[ProfileAppearance] saving accent failed: ' + String(error));
      promptAction.showToast({ message: '主题色保存失败，请重试', duration: 2000 });
      return;
    } finally {
      this.accentSaving = false;
    }

    this.accentToastPending = true;
    if (this.accentSheetOpen) {
      this.accentSheetOpen = false;
    } else {
      this.onAccentSheetDisappear();
    }
  }

  private onAccentSheetDisappear(): void {
    if (this.accentToastPending) {
      this.accentToastPending = false;
      promptAction.showToast({ message: '已应用主题色', duration: 1600 });
    }
  }

  @Builder
  navigationHeaderSlot() {
    Row().width('100%').height(56)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  chevron() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(15)
      .fontColor([COLOR_TEXT_SECONDARY])
      .accessibilityLevel('no')
  }

  @Builder
  sectionHeading(label: string) {
    Text(label).fontSize(14).fontColor(COLOR_TEXT_SECONDARY).width('100%')
  }

  @Builder
  settingLabel(label: string, icon: Resource, subtitle: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.colors.primary])
        .accessibilityLevel('no')
      Column({ space: 3 }) {
        Text(label).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_TITLE)
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .layoutWeight(1)
  }

  @Builder
  displayCard() {
    Column() {
      Row({ space: 12 }) {
        this.settingLabel('显示模式', $r('sys.symbol.circle_grid_2x2'), '')
        Select(MODE_OPTIONS)
          .selected(this.modeIndex())
          .value(COLOR_MODE_OPTIONS[this.modeIndex()].label)
          .fontColor(COLOR_TEXT_SECONDARY)
          .optionFontColor(COLOR_TEXT_TITLE)
          .selectedOptionFontColor(COLOR_TEXT_TITLE)
          .accessibilityDescription('显示模式')
          .onSelect((index: number): void => this.selectColorModeOption(index))
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      Divider().color(COLOR_DIVIDER).margin({ left: 16, right: 16 })

      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          this.settingLabel('主题色', $r('sys.symbol.paintbrush'), '')
          Circle({ width: 16, height: 16 }).fill(this.colors.primary).accessibilityLevel('no')
          Text(accentPreset(this.accentId).name).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          this.chevron()
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent)
      .onClick((): void => this.startAccentPreview())
      .bindSheet($$this.accentSheetOpen, this.accentSheet(),
        this.appearanceSheetOptions('主题色', (): void => this.onAccentSheetDisappear()))
      Divider().color(COLOR_DIVIDER).margin({ left: 16, right: 16 })

      Row({ space: 12 }) {
        this.settingLabel('动画效果', $r('sys.symbol.wand_and_stars'), '按钮动效、卡片按压、阅读器过渡等')
        Toggle({ type: ToggleType.Switch, isOn: this.animationsEnabled })
          .selectedColor(this.colors.primary)
          .accessibilityText('动画效果')
          .onChange((checked: boolean): void => {
            this.animationsEnabled = checked;
            CacheManager.getInstance().then((cache: CacheManager): void => {
              cache.saveSetting('animations', checked ? 'true' : 'false');
            });
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 58 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_DIVIDER })
    .clip(true)
  }

  @Builder
  accentOption(option: AccentPreset) {
    Button({ type: ButtonType.Circle }) {
      Stack() {
        Circle({ width: 34, height: 34 }).fill(this.previewColors(option.id).primary)
        if (this.draftAccent === option.id) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(15)
            .fontColor([this.previewColors(option.id).onPrimary])
        }
      }
    }
    .width(48).height(48)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(option.name)
    .accessibilitySelected(this.draftAccent === option.id)
    .onClick((): void => { this.draftAccent = option.id; })
  }

  @Builder
  customAccentRow() {
    if (customAccentHex(this.draftAccent).length > 0) {
      Row({ space: 10 }) {
        Text('自定义').fontSize(15).fontColor(COLOR_TEXT_TITLE)
        TextInput({ text: this.customHexInput, placeholder: '#RRGGBB' })
          .maxLength(7)
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(COLOR_TEXT_TITLE)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(COLOR_INPUT_BG)
          .accessibilityText('自定义主题色色值')
          .onChange((value: string): void => this.changeCustomHex(value))
        if (this.nativeColorPicker) {
          Row() {
            HdsColorPicker({
              initialColor: '#FF' + customAccentHex(this.draftAccent).slice(1),
              onColorSelected: (color: string): void => this.setPickedColor(color),
              options: { circleRadius: 15 }
            })
          }
          .width(44).height(44)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
    } else {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text('自定义颜色').fontSize(15).fontColor(COLOR_TEXT_TITLE).layoutWeight(1)
          this.chevron()
        }
        .width('100%')
      }
      .width('100%')
      .height(46)
      .padding({ left: 12, right: 12 })
      .borderRadius(14)
      .backgroundColor(COLOR_CARD)
      .onClick((): void => this.chooseCustomAccent())
    }
  }

  @Builder
  accentSheet() {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(ACCENT_PRESETS, (option: AccentPreset): void => {
          this.accentOption(option)
        }, (option: AccentPreset): string => option.id)
      }
      .width('100%')
      this.customAccentRow()
      Row({ space: 12 }) {
        Text('推荐')
          .fontSize(14).fontColor(this.previewColors().primary)
          .backgroundColor(this.previewColors().tint)
          .borderRadius(12).padding({ left: 10, right: 10, top: 7, bottom: 7 })
        Text('继续阅读')
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.previewColors().onPrimary)
          .backgroundColor(this.previewColors().primary)
          .borderRadius(18).padding({ left: 12, right: 12, top: 8, bottom: 8 })
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: true }).selectedColor(this.previewColors().primary)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(COLOR_CARD)
      .borderRadius(16)
      .accessibilityText('主题色预览')
      Button('应用')
        .width('100%')
        .fontColor(this.previewColors().onPrimary)
        .backgroundColor(this.previewColors().primary)
        .enabled(!this.accentSaving && this.validAccentDraft())
        .onClick((): void => { this.applyAccent(); })
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 20 })
  }

  @Builder
  materialPreviewLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(COLOR_TEXT_TITLE)
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  @Builder
  materialCard() {
    Column() {
      Row() {
        this.settingLabel('光感等级', $r('sys.symbol.sun_max'), '')
        MaterialLevelSelect()
      }
      .width('100%')
      .constraintSize({ minHeight: 58 })
      .padding({ left: 16, right: 16 })
      Divider().color(COLOR_DIVIDER).margin({ left: 16, right: 16 })
      Row() {
        this.settingLabel('面板厚度', $r('sys.symbol.square_stack_3d'), '')
        MaterialLevelSelect({ thickness: true })
      }
      .width('100%')
      .constraintSize({ minHeight: 58 })
      .padding({ left: 16, right: 16 })

      Column() {
        Stack({ alignContent: Alignment.BottomStart }) {
          Image($r('app.media.appearance_icon_silhouette'))
            .width('100%').height('100%').objectFit(ImageFit.Cover)
          Row({ space: 8 }) {
            DetailGlassCapsule({ capsuleWidth: 108, capsuleHeight: 34,
              content: (): void => { this.materialPreviewLabel('继续阅读'); } })
            DetailGlassCapsule({ capsuleWidth: 68, capsuleHeight: 34,
              content: (): void => { this.materialPreviewLabel('章节'); } })
          }
          .padding(12)
        }
        .width('100%')
        .height(110)
        .borderRadius(14)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_DIVIDER })
  }

  @Builder
  iconEntry() {
    Button({ type: ButtonType.ROUNDED_RECTANGLE }) {
      Row({ space: 10 }) {
        this.settingLabel('应用图标', $r('sys.symbol.rectangle_portrait_on_rectangle_portrait'), '')
        if (this.iconKnown) {
          Image(desktopIcon(this.appliedIcon).image)
            .width(26).height(26).borderRadius(6).clip(true).accessibilityLevel('no')
        }
        this.chevron()
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 58 })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(COLOR_CARD)
    .borderRadius(18)
    .border({ width: 1, color: COLOR_DIVIDER })
    .onClick((): void => {
      this.iconPortraitPreviews = [this.appliedIcon];
      this.iconSheetOpen = true;
      this.readIcon();
    })
    .bindSheet($$this.iconSheetOpen, this.iconSheet(), this.appearanceSheetOptions('应用图标'))
  }

  @Builder
  iconPreviewLayer(option: DesktopIconOption, icon: DesktopIcon) {
    Image(icon.image)
      .width('100%').height('100%')
      .borderRadius(13)
      .objectFit(ImageFit.Contain)
      .clip(true)
      .draggable(false)
      .accessibilityLevel('no')
      .scale({
        x: this.previewIcon(option).id === icon.id ? 1 : 0.65,
        y: this.previewIcon(option).id === icon.id ? 1 : 0.65
      })
      .opacity(this.previewIcon(option).id === icon.id ? 1 : 0)
      .animation(this.iconPreviewMotion(option, icon))
  }

  @Builder
  iconOption(option: DesktopIconOption) {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.iconPreviewLayer(option, option)
        if (option.portrait) {
          this.iconPreviewLayer(option, option.portrait)
        }
        if (this.iconKnown && this.appliedIcon === this.previewIcon(option).id) {
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([this.colors.onPrimary])
          }
          .justifyContent(FlexAlign.Center)
          .width(21).height(21)
          .backgroundColor(this.colors.primary)
          .borderRadius(11)
          .border({ width: 2, color: COLOR_CARD })
          .offset({ x: 4, y: 3 })
          .accessibilityLevel('no')
        }
      }
      .width('100%').aspectRatio(1)
      .constraintSize({ maxWidth: 56, maxHeight: 56 })
    }
    .width('100%')
    .height(72)
    .padding({ left: 4, right: 4 })
    .borderRadius(14)
    .backgroundColor(Color.Transparent)
    .stateEffect(false)
    .accessibilityText(this.previewIcon(option).label)
    .accessibilitySelected(this.iconKnown && this.appliedIcon === this.previewIcon(option).id)
    .onClick((): void => { this.changeIcon(this.previewIcon(option)); })
    .priorityGesture(
      LongPressGesture({ repeat: false }).onAction((): void => { this.toggleIconPreview(option); }),
      GestureMask.Normal
    )
  }

  @Builder
  iconSheet() {
    Column({ space: 8 }) {
      GridRow({ columns: 3, gutter: 6 }) {
        ForEach(DESKTOP_ICONS, (option: DesktopIconOption): void => {
          GridCol() { this.iconOption(option) }
        }, (option: DesktopIconOption): string => option.id)
      }
      .width('100%')
      .constraintSize({ maxWidth: 324 })
      Text(this.desktopIconSupported ? '轻点应用，长按切换文字和头像' : '长按切换文字和头像')
        .width('100%').constraintSize({ maxWidth: 324 })
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
      if (!this.desktopIconSupported) {
        Text('当前系统可预览图标').width('100%').fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 8, bottom: 6 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 16 })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 14 }) {
          this.sectionHeading('显示与配色')
          this.displayCard()
          this.sectionHeading('沉浸光感')
          this.materialCard()
          this.iconEntry()
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.topSafeHeight + this.subpageContentTop,
          bottom: Math.max(28, this.bottomSafeHeight + 12)
        })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .backgroundColor(COLOR_BG)
    .hideTitleBar(false)
    .hideBackButton(true)
    .titleBar(navigationBlurTitleBar((): void => { this.navigationHeaderSlot(); }))
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onShown((): void => { this.readIcon(); })
    .onBackPressed((): boolean => {
      if (this.accentSheetOpen || this.iconSheetOpen) {
        this.accentSheetOpen = false;
        this.iconSheetOpen = false;
      } else {
        this.closeSubpage();
      }
      return true;
    })
  }
}
