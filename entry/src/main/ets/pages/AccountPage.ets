import { promptAction, router } from '@kit.ArkUI';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';
import { AuthServiceFactory, AuthStore } from '../services/AuthService';
import {
  CloudSyncServiceFactory,
  syncAllCoalesced,
  SyncStatusHub,
  resolveConflictKeepLocal,
  resolveConflictUseCloud
} from '../services/CloudSyncService';
import { CloudConfig } from '../common/Constants';
import { AppSettings } from '../services/AppSettings';
import { HostStore } from '../services/HostStore';

/**
 * 帐号：登录 / 注册 + Mock/真实服务器切换 + 云同步。
 */
@Entry
@Component
struct AccountPage {
  @StorageLink('themeRev') themeRev: number = 0;
  @StorageLink('authRev') @Watch('onAuthRev') authRev: number = 0;
  @StorageLink('appSettingsRev') @Watch('onAppSettingsRev') appSettingsRev: number = 0;
  @State mode: string = 'login'; // login | register
  @State email: string = '';
  @State username: string = '';
  @State password: string = '';
  @State baseUrl: string = CloudConfig.DEFAULT_BASE_URL;
  @State useMock: boolean = false;
  @State busy: boolean = false;
  @State statusText: string = '';
  @State loggedIn: boolean = false;
  @State displayName: string = '';
  @State displayEmail: string = '';
  @State lastSyncLabel: string = '';
  @State cloudVault: boolean = false;
  @State vaultPassphrase: string = '';
  @State rememberVault: boolean = true;
  @State huksStatus: string = '';
  @State currentPassword: string = '';
  @State newPassword: string = '';
  @State deletePassword: string = '';
  @State conflictMessage: string = '';
  @State syncErrorHint: string = '';

  aboutToAppear(): void {
    this.hydrateFromStores();
  }

  onAuthRev(): void {
    this.hydrateFromStores();
  }

  onAppSettingsRev(): void {
    void this.appSettingsRev;
    const settings = AppSettings.getInstance();
    this.cloudVault = settings.isCloudVaultEnabled();
    this.vaultPassphrase = settings.getVaultPassphrase();
    this.rememberVault = settings.isRememberVaultPassphrase();
  }

  /** AuthStore/AppSettings 就绪后（含冷启动竞态）刷新表单与会话展示 */
  private hydrateFromStores(): void {
    const store = AuthStore.getInstance();
    this.baseUrl = store.getBaseUrl();
    this.useMock = store.isUseMock();
    const settings = AppSettings.getInstance();
    this.cloudVault = settings.isCloudVaultEnabled();
    this.vaultPassphrase = settings.getVaultPassphrase();
    this.rememberVault = settings.isRememberVaultPassphrase();
    const he = HostStore.getInstance().getHuksError();
    this.huksStatus = he ? `HUKS：${he}` : 'HUKS：就绪或将在首次加密时初始化';
    this.refreshSession();
  }

  private refreshSession(): void {
    void this.authRev;
    const store = AuthStore.getInstance();
    this.loggedIn = store.isLoggedIn();
    this.useMock = store.isUseMock();
    const u = store.getUser();
    this.displayName = u ? u.username : '';
    this.displayEmail = u ? u.email : '';
    void this.refreshLastSyncLabel();
    this.conflictMessage = SyncStatusHub.getConflictMessage();
    this.syncErrorHint = SyncStatusHub.isOffline() ? '离线' :
      (SyncStatusHub.getLastError().length > 0 ? `同步失败：${SyncStatusHub.getLastError()}` : '');
  }

  private async refreshLastSyncLabel(): Promise<void> {
    try {
      const ts = await CloudSyncServiceFactory.create().getLastSyncAt();
      if (!ts || ts <= 0) {
        this.lastSyncLabel = '尚未同步';
        return;
      }
      const d = new Date(ts);
      const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
      this.lastSyncLabel =
        `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
        `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    } catch (_e) {
      this.lastSyncLabel = '';
    }
  }

  private isValidEmail(email: string): boolean {
    const e = email.trim();
    const at = e.indexOf('@');
    if (at <= 0 || at >= e.length - 1) {
      return false;
    }
    const domain = e.substring(at + 1);
    return domain.indexOf('.') > 0 && e.indexOf(' ') < 0;
  }

  /** 登录 / 注册表单校验；返回错误文案或 null */
  private validateAuthInput(): string | null {
    if (this.mode === 'register') {
      if (!this.isValidEmail(this.email)) {
        return '请输入有效邮箱';
      }
      if (this.username.trim().length === 0) {
        return '请填写用户名';
      }
      if (this.password.length < CloudConfig.MIN_PASSWORD_LEN) {
        return `密码至少 ${CloudConfig.MIN_PASSWORD_LEN} 位`;
      }
      return null;
    }
    const loginId = (this.email || this.username).trim();
    if (loginId.length === 0 || this.password.length < 1) {
      return '请填写邮箱或用户名与密码';
    }
    return null;
  }

  private formatAuthError(e: Object | string | Error): string {
    const m = e instanceof Error ? e.message : `${e}`;
    if (!m || m.length === 0) {
      return '操作失败';
    }
    if (m.indexOf('无法连接服务器') >= 0) {
      return m;
    }
    return m;
  }

  private bumpHostsUi(): void {
    HostStore.getInstance().notifyChanged();
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
    const pwErr = this.validateAuthInput();
    if (pwErr) {
      this.toast(pwErr);
      this.statusText = pwErr;
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
        const msg = await syncAllCoalesced();
        this.bumpHostsUi();
        this.statusText = msg;
        if (msg.indexOf('已从云端合并') >= 0) {
          this.toast('已从云端合并');
        } else {
          this.toast(msg);
        }
        await this.refreshLastSyncLabel();
      } catch (syncErr) {
        const m = this.formatAuthError(syncErr as Error);
        this.statusText = `已登录，同步跳过：${m}`;
      }
    } catch (e) {
      const m = this.formatAuthError(e as Error);
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
  }


  private async doChangePassword(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.currentPassword.length < 1) {
      this.toast('请填写当前密码');
      return;
    }
    if (this.newPassword.length < CloudConfig.MIN_PASSWORD_LEN) {
      this.toast(`新密码至少 ${CloudConfig.MIN_PASSWORD_LEN} 位`);
      return;
    }
    if (this.currentPassword === this.newPassword) {
      this.toast('新密码须与当前密码不同');
      return;
    }
    this.busy = true;
    this.statusText = '';
    try {
      const auth = AuthServiceFactory.create();
      if (!auth.changePassword) {
        this.toast('当前后端不支持改密');
        return;
      }
      await auth.changePassword(this.currentPassword, this.newPassword);
      this.currentPassword = '';
      this.newPassword = '';
      this.toast('密码已修改');
      this.statusText = '密码已修改，会话已更新';
    } catch (e) {
      const m = this.formatAuthError(e as Error);
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
  }

  private async doDeleteAccount(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.deletePassword.length < 1) {
      this.toast('请填写密码以确认删除帐号');
      return;
    }
    this.busy = true;
    this.statusText = '';
    try {
      const auth = AuthServiceFactory.create();
      if (!auth.deleteAccount) {
        this.toast('当前后端不支持删除帐号');
        return;
      }
      await auth.deleteAccount(this.deletePassword);
      this.deletePassword = '';
      await AppSettings.getInstance().clearVaultPassphrase(true);
      this.vaultPassphrase = '';
      this.refreshSession();
      this.toast('帐号已删除');
      this.statusText = '帐号已删除，本地会话已清除';
    } catch (e) {
      const m = this.formatAuthError(e as Error);
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
  }

  private async doResolveKeepLocal(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const msg = await resolveConflictKeepLocal();
      this.conflictMessage = '';
      this.statusText = msg;
      this.toast(msg);
      this.bumpHostsUi();
      await this.refreshLastSyncLabel();
      this.refreshSession();
    } catch (e) {
      const m = this.formatAuthError(e as Error);
      this.toast(m);
      this.statusText = m;
    } finally {
      this.busy = false;
    }
  }

  private async doResolveUseCloud(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const msg = await resolveConflictUseCloud();
      this.conflictMessage = '';
      this.statusText = msg;
      this.toast(msg);
      this.bumpHostsUi();
      await this.refreshLastSyncLabel();
      this.refreshSession();
    } catch (e) {
      const m = this.formatAuthError(e as Error);
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
      // 退出登录清除保险柜口令（含 HUKS 落盘密文）
      await AppSettings.getInstance().clearVaultPassphrase(true);
      this.vaultPassphrase = '';
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
      if (!this.useMock) {
        await AuthStore.getInstance().setBaseUrl(this.baseUrl);
      }
      const msg = await syncAllCoalesced();
      this.bumpHostsUi();
      this.statusText = msg;
      if (msg.indexOf('冲突') >= 0 || msg.indexOf('已从云端合并') >= 0) {
        this.toast(msg.indexOf('冲突') >= 0 ? '同步完成（存在冲突，见下方）' : '已从云端合并');
      } else {
        this.toast(msg);
      }
      await this.refreshLastSyncLabel();
      this.conflictMessage = SyncStatusHub.getConflictMessage();
      this.syncErrorHint = '';
    } catch (e) {
      const m = this.formatAuthError(e as Error);
      SyncStatusHub.markSyncError(m);
      this.toast(m);
      this.statusText = m;
      this.syncErrorHint = SyncStatusHub.isOffline() ? '离线' : `同步失败：${m}`;
      this.conflictMessage = SyncStatusHub.getConflictMessage();
    } finally {
      this.busy = false;
    }
  }

  private async toggleVault(next: boolean): Promise<void> {
    if (next && this.vaultPassphrase.length < CloudConfig.MIN_PASSWORD_LEN) {
      this.toast(`开启保险柜前请先填写至少 ${CloudConfig.MIN_PASSWORD_LEN} 位口令`);
      // keep UI toggle visual in sync by resetting state
      this.cloudVault = false;
      return;
    }
    await AppSettings.getInstance().setVaultPassphrase(this.vaultPassphrase);
    await AppSettings.getInstance().setCloudVaultEnabled(next);
    this.cloudVault = next;
    if (next) {
      // 触发对本机主机重新封存，填充 passwordEnc
      const store = HostStore.getInstance();
      const all = store.getAll();
      for (let i = 0; i < all.length; i++) {
        await store.upsert(all[i]);
      }
    }
    this.toast(next ? '已开启云端密钥保险柜（同步 passwordEnc）' : '已关闭：机密仅本机');
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
              TextInput({ text: this.baseUrl, placeholder: $r('app.string.account_server_placeholder') })
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
                .fontWeight(FontWeight.Medium)
                .fontColor(this.textPrimary())
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 2 })
              if (this.displayEmail.length > 0) {
                Text(this.displayEmail)
                  .fontSize(13)
                  .fontColor(this.textSecondary())
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 8 })
              }
              Text(this.useMock ? $r('app.string.account_mock_hint') : $r('app.string.account_sync_hint'))
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              Text($r('app.string.account_secrets_note'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              Text(this.lastSyncLabel.length > 0 ?
                `上次同步：${this.lastSyncLabel}` : $r('app.string.account_never_synced'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              if (this.syncErrorHint.length > 0) {
                Text(this.syncErrorHint)
                  .fontSize(12)
                  .fontColor('#E84026')
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 8 })
              }
              if (this.conflictMessage.length > 0) {
                Text(this.conflictMessage)
                  .fontSize(12)
                  .fontColor(this.textSecondary())
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 8 })
                Row() {
                  Text($r('app.string.account_conflict_keep_local'))
                    .fontSize(15)
                    .fontColor(this.accent())
                    .padding({ right: 16 })
                    .onClick(() => {
                      this.doResolveKeepLocal();
                    })
                  Text($r('app.string.account_conflict_use_cloud'))
                    .fontSize(15)
                    .fontColor(this.accent())
                    .onClick(() => {
                      this.doResolveUseCloud();
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 12 })
              }
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
              Text($r('app.string.account_change_password'))
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 4 })
              Text($r('app.string.account_change_password_hint'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              this.field($r('app.string.account_current_password'), this.currentPassword, (v: string) => {
                this.currentPassword = v;
              }, true)
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              this.field($r('app.string.account_new_password'), this.newPassword, (v: string) => {
                this.newPassword = v;
              }, true)
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Row() {
                Text(this.busy ? $r('app.string.account_busy') : $r('app.string.account_change_password_btn'))
                  .fontSize(16)
                  .fontColor(this.accent())
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .opacity(this.busy ? 0.5 : 1)
              .onClick(() => {
                this.doChangePassword();
              })
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Text($r('app.string.account_delete'))
                .fontSize(13)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 4 })
              Text($r('app.string.account_delete_hint'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              this.field($r('app.string.account_delete_password'), this.deletePassword, (v: string) => {
                this.deletePassword = v;
              }, true)
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Row() {
                Text(this.busy ? $r('app.string.account_busy') : $r('app.string.account_delete_btn'))
                  .fontSize(16)
                  .fontColor('#E84026')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .opacity(this.busy ? 0.5 : 1)
              .onClick(() => {
                this.doDeleteAccount();
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
              if (this.mode === 'register') {
                Text($r('app.string.account_password_hint'))
                  .fontSize(12)
                  .fontColor(this.textSecondary())
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 8 })
              }

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


          this.sectionTitle($r('app.string.account_cloud_vault'))
          Column() {
            Text($r('app.string.account_cloud_vault_hint'))
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
            Text($r('app.string.account_vault_passphrase'))
              .fontSize(13)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 2 })
            TextInput({ text: this.vaultPassphrase, placeholder: '' })
              .width('100%')
              .height(40)
              .fontSize(16)
              .fontColor(this.textPrimary())
              .backgroundColor(Color.Transparent)
              .padding({ left: 16, right: 16 })
              .type(InputType.Password)
              .onChange((v: string) => {
                this.vaultPassphrase = v;
                void AppSettings.getInstance().setVaultPassphrase(v);
              })
              .margin({ bottom: 4 })
            Text($r('app.string.account_vault_passphrase_hint'))
              .fontSize(12)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
            Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
            Row() {
              Text($r('app.string.account_cloud_vault_toggle'))
                .fontSize(16)
                .fontColor(this.textPrimary())
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.cloudVault })
                .selectedColor(this.accent())
                .onChange((isOn: boolean) => {
                  this.toggleVault(isOn);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            if (this.cloudVault) {
              Divider().color(this.divider()).strokeWidth(0.5).margin({ left: 16 })
              Row() {
                Text($r('app.string.account_remember_vault_passphrase'))
                  .fontSize(16)
                  .fontColor(this.textPrimary())
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.rememberVault })
                  .selectedColor(this.accent())
                  .onChange((isOn: boolean) => {
                    this.rememberVault = isOn;
                    void AppSettings.getInstance().setRememberVaultPassphrase(isOn);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 4 })
              Text($r('app.string.account_remember_vault_hint'))
                .fontSize(12)
                .fontColor(this.textSecondary())
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 10 })
            }
            Text(this.huksStatus)
              .fontSize(12)
              .fontColor(this.textSecondary())
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 12 })
          }
          .width('100%')
          .backgroundColor(this.surfaceCard())
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

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
