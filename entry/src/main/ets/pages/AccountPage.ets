import { promptAction, router } from '@kit.ArkUI';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';
import { AuthServiceFactory, AuthStore } from '../services/AuthService';
import { CloudSyncServiceFactory } from '../services/CloudSyncService';
import { CloudConfig } from '../common/Constants';

/**
 * 帐号：登录 / 注册 + Mock/真实服务器切换 + 云同步。
 */
@Entry
@Component
struct AccountPage {
  @StorageLink('themeRev') themeRev: number = 0;
  @StorageLink('authRev') authRev: number = 0;
  @State mode: string = 'login'; // login | register
  @State email: string = '';
  @State username: string = '';
  @State password: string = '';
  @State baseUrl: string = CloudConfig.DEFAULT_BASE_URL;
  @State useMock: boolean = true;
  @State busy: boolean = false;
  @State statusText: string = '';
  @State loggedIn: boolean = false;
  @State displayName: string = '';

  aboutToAppear(): void {
    const store = AuthStore.getInstance();
    this.baseUrl = store.getBaseUrl();
    this.useMock = store.isUseMock();
    this.refreshSession();
  }

  private refreshSession(): void {
    void this.authRev;
    const store = AuthStore.getInstance();
    this.loggedIn = store.isLoggedIn();
    this.useMock = store.isUseMock();
    const u = store.getUser();
    this.displayName = u ? `${u.username}（${u.email}）` : '';
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

  private toast(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2500 });
    } catch (_e) {
      this.statusText = msg;
    }
  }

  private async toggleMock(next: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const store = AuthStore.getInstance();
      // 切换后端时清会话，避免 Mock token 打到真实服务器
      if (store.isLoggedIn()) {
        await AuthServiceFactory.create().logout();
      }
      await store.setUseMock(next);
      this.useMock = next;
      this.refreshSession();
      this.toast(next ? '已切换为 Mock（离线）' : '已切换为真实服务器');
    } finally {
      this.busy = false;
    }
  }

  private async doLogin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = '';
    try {
      if (!this.useMock) {
        await AuthStore.getInstance().setBaseUrl(this.baseUrl);
      }
      const auth = AuthServiceFactory.create();
      const loginId = this.mode === 'register' ? this.email : (this.email || this.username);
      if (this.mode === 'register') {
        await auth.register(this.email.trim(), this.username.trim(), this.password);
      } else {
        await auth.login(loginId.trim(), this.password);
      }
      this.refreshSession();
      this.toast(this.mode === 'register' ? '注册并登录成功' : '登录成功');
      try {
        const msg = await CloudSyncServiceFactory.create().syncAll();
        this.statusText = msg;
        this.toast(msg);
      } catch (syncErr) {
        const m = syncErr instanceof Error ? syncErr.message : '同步失败';
        this.statusText = `已登录，同步跳过：${m}`;
      }
    } catch (e) {
      const m = e instanceof Error ? e.message : '操作失败';
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
  }

  private async doLogout(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await AuthServiceFactory.create().logout();
      this.refreshSession();
      this.statusText = '';
      this.toast('已退出登录');
    } finally {
      this.busy = false;
    }
  }

  private async doSync(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = '同步中…';
    try {
      const msg = await CloudSyncServiceFactory.create().syncAll();
      this.statusText = msg;
      this.toast(msg);
    } catch (e) {
      const m = e instanceof Error ? e.message : '同步失败';
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
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
        Text($r('app.string.account_title'))
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
          // Mock / 真实服务器切换（始终可见）
          this.sectionTitle($r('app.string.account_backend'))
          Column() {
            Text($r('app.string.account_backend_hint'))
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
            Row() {
              Text($r('app.string.account_backend_mock'))
                .fontSize(16)
                .fontColor(this.useMock ? this.accent() : this.textPrimary())
                .layoutWeight(1)
              if (this.useMock) {
                Text('✓').fontSize(18).fontColor(this.accent())
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              if (!this.useMock) {
                this.toggleMock(true);
              }
            })
            Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
            Row() {
              Text($r('app.string.account_backend_real'))
                .fontSize(16)
                .fontColor(!this.useMock ? this.accent() : this.textPrimary())
                .layoutWeight(1)
              if (!this.useMock) {
                Text('✓').fontSize(18).fontColor(this.accent())
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              if (this.useMock) {
                this.toggleMock(false);
              }
            })
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          if (!this.useMock) {
            this.sectionTitle($r('app.string.account_server'))
            Column() {
              Text($r('app.string.account_server_hint'))
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 8 })
              TextInput({ text: this.baseUrl, placeholder: 'http://192.168.x.x:8080' })
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor(this.textPrimary())
                .backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 16 })
                .onChange((v: string) => {
                  this.baseUrl = v;
                })
                .margin({ bottom: 12 })
            }
            .width('100%')
            .backgroundColor(this.surfaceCard())
            .borderRadius($r('app.float.card_radius'))
            .clip(true)
          }

          if (this.loggedIn) {
            this.sectionTitle($r('app.string.account_signed_in'))
            Column() {
              Text(this.displayName)
                .fontSize(16)
                .fontColor(this.textPrimary())
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 8 })
              Text(this.useMock ? $r('app.string.account_mock_hint') : $r('app.string.account_sync_hint'))
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              Text($r('app.string.account_secrets_note'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 12 })
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Row() {
                Text(this.busy ? $r('app.string.account_busy') : $r('app.string.account_sync_now'))
                  .fontSize(16)
                  .fontColor(this.accent())
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .opacity(this.busy ? 0.5 : 1)
              .onClick(() => {
                this.doSync();
              })
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Row() {
                Text($r('app.string.account_logout'))
                  .fontSize(16)
                  .fontColor('#E84026')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => {
                this.doLogout();
              })
            }
            .width('100%')
            .backgroundColor(this.surfaceCard())
            .borderRadius($r('app.float.card_radius'))
            .clip(true)
          } else {
            this.sectionTitle($r('app.string.account_auth'))
            Column() {
              Row() {
                Text($r('app.string.account_login_tab'))
                  .fontSize(15)
                  .fontColor(this.mode === 'login' ? this.accent() : this.textSecondary())
                  .fontWeight(this.mode === 'login' ? FontWeight.Medium : FontWeight.Normal)
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                  .onClick(() => {
                    this.mode = 'login';
                  })
                Text($r('app.string.account_register_tab'))
                  .fontSize(15)
                  .fontColor(this.mode === 'register' ? this.accent() : this.textSecondary())
                  .fontWeight(this.mode === 'register' ? FontWeight.Medium : FontWeight.Normal)
                  .padding({ left: 8, right: 16, top: 14, bottom: 14 })
                  .onClick(() => {
                    this.mode = 'register';
                  })
              }
              .width('100%')

              Divider().color(this.divider()).strokeWidth(0.5)

              if (this.mode === 'register') {
                this.field($r('app.string.account_email'), this.email, (v: string) => {
                  this.email = v;
                }, false)
                Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
                this.field($r('app.string.account_username'), this.username, (v: string) => {
                  this.username = v;
                }, false)
                Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              } else {
                this.field($r('app.string.account_login_id'), this.email, (v: string) => {
                  this.email = v;
                }, false)
                Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              }

              this.field($r('app.string.account_password'), this.password, (v: string) => {
                this.password = v;
              }, true)

              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })

              Row() {
                Text(this.busy ? $r('app.string.account_busy') :
                  (this.mode === 'register' ? $r('app.string.account_register_btn') :
                    $r('app.string.account_login_btn')))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.accent())
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 16 })
              .opacity(this.busy ? 0.5 : 1)
              .onClick(() => {
                this.doLogin();
              })
            }
            .width('100%')
            .backgroundColor(this.surfaceCard())
            .borderRadius($r('app.float.card_radius'))
            .clip(true)
          }

          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(12)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 4, right: 4 })
          }

          if (this.busy) {
            Text($r('app.string.account_busy'))
              .fontSize(12)
              .fontColor(this.accent())
              .width('100%')
              .padding({ left: 4, right: 4 })
          }

          Text($r('app.string.account_huks_note'))
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
  field(label: Resource, value: string, onChange: (v: string) => void, password: boolean) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(this.textSecondary())
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 2 })
      TextInput({ text: value, placeholder: '' })
        .width('100%')
        .height(40)
        .fontSize(16)
        .fontColor(this.textPrimary())
        .backgroundColor(Color.Transparent)
        .padding({ left: 16, right: 16 })
        .type(password ? InputType.Password : InputType.Normal)
        .onChange(onChange)
        .margin({ bottom: 8 })
    }
    .width('100%')
  }
}
