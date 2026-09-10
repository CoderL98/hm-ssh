import { router } from '@kit.ArkUI';
import { HostConfig } from '../models/HostConfig';
import { HostListItem } from './HostListItem';
import { RouteNames } from '../common/Constants';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';

/**
 * 左侧 / 窄屏主机列表：鸿蒙设置纯净风大标题 + 白色分组卡片列表。
 * 标题/链接/强调色走 ThemeTokens（与 Settings 一致，不破坏纯净风）。
 * 右上角：「登录」/ 用户名 → 帐号页；设置；添加。
 * 已登录时可下拉刷新触发云同步。
 */
@Component
export struct HostListPanel {
  @Prop hosts: HostConfig[] = [];
  @Prop selectedId: string = '';
  /** 未登录显示「登录」；已登录显示用户名 */
  @Prop authLabel: string = '';
  @Prop loggedIn: boolean = false;
  /** 同步状态行（如「上次同步：…」/「同步中…」） */
  @Prop syncStatusLabel: string = '';
  @Prop syncing: boolean = false;
  @StorageLink('themeRev') themeRev: number = 0;
  @State refreshing: boolean = false;
  onAdd: () => void = () => {};
  onConnect: (host: HostConfig) => void = () => {};
  onEdit: (host: HostConfig) => void = () => {};
  onDelete: (host: HostConfig) => void = () => {};
  onAccount: () => void = () => {};
  onPullSync: () => void = () => {};

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  private textPrimary(): string {
    void this.themeRev;
    return ThemeTokens.surface().textPrimary;
  }

  private textSecondary(): string {
    void this.themeRev;
    return ThemeTokens.surface().textSecondary;
  }

  private surfacePage(): string {
    void this.themeRev;
    return ThemeTokens.surface().pageBackground;
  }

  private surfaceCard(): string {
    void this.themeRev;
    return ThemeTokens.surface().cardBackground;
  }

  private divider(): string {
    void this.themeRev;
    return ThemeTokens.surface().divider;
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.host_list_title'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary())
          .layoutWeight(1)

        Text(this.loggedIn ?
          (this.authLabel.length > 0 ? this.authLabel : $r('app.string.account_signed_in')) :
          $r('app.string.account_login_tab'))
          .fontSize(15)
          .fontColor(this.accent())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 96 })
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .onClick(() => this.onAccount())
        Text($r('app.string.settings_entry'))
          .fontSize(15)
          .fontColor(this.accent())
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            router.pushUrl({ url: RouteNames.SETTINGS });
          })
        Text('+')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accent())
          .padding({ left: 8, right: 4, top: 4, bottom: 4 })
          .onClick(() => this.onAdd())
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        top: 16,
        bottom: 4
      })
      .alignItems(VerticalAlign.Center)

      if (this.loggedIn) {
        Text(this.syncing ? $r('app.string.host_list_syncing') :
          (this.syncStatusLabel.length > 0 ? this.syncStatusLabel : $r('app.string.account_never_synced')))
          .fontSize(12)
          .fontColor(this.textSecondary())
          .width('100%')
          .padding({
            left: $r('app.float.page_padding'),
            right: $r('app.float.page_padding'),
            bottom: 8
          })
          .onClick(() => {
            if (!this.syncing) {
              this.onPullSync();
            }
          })
      } else {
        Text($r('app.string.host_list_offline_hint'))
          .fontSize(12)
          .fontColor(this.textSecondary())
          .width('100%')
          .padding({
            left: $r('app.float.page_padding'),
            right: $r('app.float.page_padding'),
            bottom: 8
          })
      }

      if (this.hosts.length === 0) {
        Column() {
          Text($r('app.string.host_list_empty'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor(this.textSecondary())
            .textAlign(TextAlign.Center)
          Text($r('app.string.host_add'))
            .fontSize(16)
            .fontColor(this.accent())
            .margin({ top: 20 })
            .onClick(() => this.onAdd())
          if (!this.loggedIn) {
            Text($r('app.string.host_list_login_cta'))
              .fontSize(15)
              .fontColor(this.accent())
              .margin({ top: 12 })
              .onClick(() => this.onAccount())
          } else if (!this.syncing) {
            Text($r('app.string.account_sync_now'))
              .fontSize(15)
              .fontColor(this.accent())
              .margin({ top: 12 })
              .onClick(() => this.onPullSync())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding($r('app.float.page_padding'))
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List() {
            ForEach(this.hosts, (host: HostConfig, index: number) => {
              ListItem() {
                Column() {
                  HostListItem({
                    host: host,
                    selected: host.id === this.selectedId,
                    onConnect: (h: HostConfig) => this.onConnect(h),
                    onEdit: (h: HostConfig) => this.onEdit(h),
                    onDelete: (h: HostConfig) => this.onDelete(h)
                  })
                  if (index < this.hosts.length - 1) {
                    Divider()
                      .color(this.divider())
                      .strokeWidth(0.5)
                      .margin({ left: 16 })
                  }
                }
              }
            }, (host: HostConfig) => `${host.id}_${host.updatedAt}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .divider({ strokeWidth: 0 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: 12
        })
        .backgroundColor(this.surfaceCard())
        .borderRadius($r('app.float.card_radius'))
        .clip(true)
        .onRefreshing(() => {
          if (!this.loggedIn) {
            this.refreshing = false;
            return;
          }
          this.refreshing = true;
          this.onPullSync();
          // Index 会在同步结束后通过 syncing→false 驱动；此处兜底结束刷新动画
          setTimeout(() => {
            this.refreshing = false;
          }, 1200);
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfacePage())
  }
}
