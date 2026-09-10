import { router } from '@kit.ArkUI';
import { RouteNames } from '../common/Constants';
import { AuthStore } from '../services/AuthService';
import { ThemeStore } from '../services/ThemeStore';
import { maybePushAfterLocalChange } from '../services/CloudSyncService';
import {
  AccentId,
  AccentPreset,
  ACCENT_PRESETS,
  ThemeMode,
  ThemeTokens,
  TerminalScheme,
  TerminalSchemeId,
  TERMINAL_SCHEMES,
  onAccentForeground
} from '../theme/ThemeTokens';

/**
 * 设置页（纯净风）：外观 / 强调色 / 终端配色。
 */
@Entry
@Component
struct SettingsPage {
  @StorageLink('themeRev') themeRev: number = 0;
  @State mode: ThemeMode = 'system';
  @State accentId: AccentId = 'blue';
  @State schemeId: TerminalSchemeId = 'classic_dark';
  @StorageLink('authRev') authRev: number = 0;
  @State accountSubtitle: string = '';

  aboutToAppear(): void {
    this.syncFromStore();
    this.refreshAccount();
  }

  private refreshAccount(): void {
    void this.authRev;
    const auth = AuthStore.getInstance();
    if (auth.isLoggedIn()) {
      const u = auth.getUser();
      this.accountSubtitle = u ? u.username : '已登录';
    } else {
      this.accountSubtitle = '登录以同步主机与设置'; // mirrors account_entry_subtitle
    }
  }

  private syncFromStore(): void {
    const store = ThemeStore.getInstance();
    this.mode = store.getThemeMode();
    this.accentId = store.getAccentId();
    this.schemeId = store.getTerminalSchemeId();
  }

  private surfacePage(): string {
    void this.themeRev;
    return ThemeTokens.surface().pageBackground;
  }

  private surfaceCard(): string {
    void this.themeRev;
    return ThemeTokens.surface().cardBackground;
  }

  private textPrimary(): string {
    void this.themeRev;
    return ThemeTokens.surface().textPrimary;
  }

  private textSecondary(): string {
    void this.themeRev;
    return ThemeTokens.surface().textSecondary;
  }

  private divider(): string {
    void this.themeRev;
    return ThemeTokens.surface().divider;
  }

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.btn_back'))
          .fontSize(16)
          .fontColor(this.accent())
          .padding({ left: 4, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.settings_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary())
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('')
          .width(56)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          this.sectionTitle($r('app.string.account_entry'))
          Column() {
            Row() {
              Column() {
                Text($r('app.string.account_entry'))
                  .fontSize(16)
                  .fontColor(this.textPrimary())
                  .width('100%')
                Text(this.accountSubtitle)
                  .fontSize(13)
                  .fontColor(this.textSecondary())
                  .width('100%')
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text('›')
                .fontSize(20)
                .fontColor(this.textSecondary())
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              router.pushUrl({ url: RouteNames.ACCOUNT });
            })
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          this.sectionTitle($r('app.string.settings_appearance'))
          Column() {
            this.modeRow($r('app.string.theme_mode_light'), 'light')
            this.thinDivider()
            this.modeRow($r('app.string.theme_mode_dark'), 'dark')
            this.thinDivider()
            this.modeRow($r('app.string.theme_mode_system'), 'system')
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          this.sectionTitle($r('app.string.settings_accent'))
          Column() {
            Text($r('app.string.settings_accent_hint'))
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
            Row({ space: 14 }) {
              ForEach(ACCENT_PRESETS, (preset: AccentPreset) => {
                this.accentDot(preset)
              }, (preset: AccentPreset) => preset.id)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
            .justifyContent(FlexAlign.Start)

            // 主按钮预览：强调色底 + 自动黑/白字
            Row() {
              Text($r('app.string.settings_accent_preview'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(onAccentForeground(ThemeTokens.accentColor(this.accentId)))
                .textAlign(TextAlign.Center)
                .width('100%')
                .height(40)
                .borderRadius(8)
                .backgroundColor(ThemeTokens.accentColor(this.accentId))
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 14 })
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          this.sectionTitle($r('app.string.settings_terminal'))
          Column() {
            ForEach(TERMINAL_SCHEMES, (scheme: TerminalScheme, index: number) => {
              Column() {
                this.schemeRow(scheme)
                if (index < TERMINAL_SCHEMES.length - 1) {
                  this.thinDivider()
                }
              }
            }, (scheme: TerminalScheme) => scheme.id)
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          Text($r('app.string.settings_contrast_note'))
            .fontSize(12)
            .fontColor(this.textSecondary())
            .width('100%')
            .padding({ left: 4, right: 4, bottom: 24 })
        }
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          top: 8,
          bottom: 24
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfacePage())
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title)
      .fontSize(13)
      .fontColor(this.textSecondary())
      .width('100%')
      .padding({ left: 4, top: 4 })
  }

  @Builder
  thinDivider() {
    Divider()
      .color(this.divider())
      .strokeWidth(0.5)
      .margin({ left: 16 })
  }

  @Builder
  modeRow(label: Resource, value: ThemeMode) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(this.textPrimary())
        .layoutWeight(1)
      if (this.mode === value) {
        Text('✓')
          .fontSize(18)
          .fontColor(this.accent())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => {
      ThemeStore.getInstance().setThemeMode(value).then(() => {
        this.mode = value;
        void maybePushAfterLocalChange('settings');
      });
    })
  }

  @Builder
  accentDot(preset: AccentPreset) {
    Column() {
      Stack() {
        Column()
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(preset.color)
        if (this.accentId === preset.id) {
          Column()
            .width(36)
            .height(36)
            .borderRadius(18)
            .border({ width: 2, color: this.textPrimary() })
          Text('✓')
            .fontSize(16)
            .fontColor(onAccentForeground(preset.color))
        }
      }
      .width(36)
      .height(36)
      .alignContent(Alignment.Center)

      Text(preset.label)
        .fontSize(11)
        .fontColor(this.accentId === preset.id ? this.accent() : this.textSecondary())
        .margin({ top: 6 })
        .maxLines(1)
    }
    .onClick(() => {
      ThemeStore.getInstance().setAccentId(preset.id).then(() => {
        this.accentId = preset.id;
        void maybePushAfterLocalChange('settings');
      });
    })
  }

  @Builder
  schemeRow(scheme: TerminalScheme) {
    Row({ space: 12 }) {
      // 预览条：bg + 样例字
      Row() {
        Text('Aa 提示符$')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(scheme.fg)
          .padding({ left: 10, right: 10 })
      }
      .width(120)
      .height(36)
      .borderRadius(6)
      .backgroundColor(scheme.bg)
      .justifyContent(FlexAlign.Center)

      Text(scheme.label)
        .fontSize(16)
        .fontColor(this.textPrimary())
        .layoutWeight(1)

      if (this.schemeId === scheme.id) {
        Text('✓')
          .fontSize(18)
          .fontColor(this.accent())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      ThemeStore.getInstance().setTerminalSchemeId(scheme.id).then(() => {
        this.schemeId = scheme.id;
        void maybePushAfterLocalChange('settings');
      });
    })
  }
}
