import { FtpEntry } from '../services/FtpSession';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';

/**
 * FTP 浏览器：设置纯净风顶栏与工具条；列表为白底设置行。
 */
@Component
export struct FtpBrowserView {
  @Prop title: string = '';
  @Prop cwd: string = '/';
  @Prop entries: FtpEntry[] = [];
  @Prop connected: boolean = false;
  @Prop statusMessage: string = '';
  @Prop loading: boolean = false;
  @Prop errorMessage: string = '';
  @StorageLink('themeRev') themeRev: number = 0;
  onNavigate: (entry: FtpEntry) => void = () => {};
  onGoUp: () => void = () => {};
  onRefresh: () => void = () => {};
  onDownload: (entry: FtpEntry) => void = () => {};
  onUploadStub: () => void = () => {};
  onDisconnect: () => void = () => {};
  onBreadcrumb: (path: string) => void = () => {};

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  private linkColor(enabled: boolean): ResourceColor {
    return enabled ? this.accent() : $r('app.color.text_secondary');
  }

  build() {
    Column() {
      Row() {
        Text(this.title.length > 0 ? this.title : 'FTP')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.connected) {
          Text($r('app.string.btn_disconnect'))
            .fontSize(15)
            .fontColor($r('app.color.danger'))
            .padding({ left: 8, right: 4, top: 6, bottom: 6 })
            .onClick(() => this.onDisconnect())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.card_background'))

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.5)

      Column() {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.breadcrumbParts(), (part: BreadcrumbPart) => {
              Text(part.label)
                .fontSize(13)
                .fontColor(part.path === this.cwd ? this.accent() : $r('app.color.text_secondary'))
                .onClick(() => this.onBreadcrumb(part.path))
              if (!part.isLast) {
                Text('/')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
            }, (part: BreadcrumbPart) => part.path + part.label)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        Row({ space: 16 }) {
          Text($r('app.string.ftp_go_up'))
            .fontSize(14)
            .fontColor(this.linkColor(this.connected && this.cwd !== '/'))
            .enabled(this.connected && this.cwd !== '/')
            .onClick(() => this.onGoUp())
          Text($r('app.string.ftp_refresh'))
            .fontSize(14)
            .fontColor(this.linkColor(this.connected))
            .enabled(this.connected)
            .onClick(() => this.onRefresh())
          Text($r('app.string.ftp_upload'))
            .fontSize(14)
            .fontColor(this.linkColor(this.connected))
            .enabled(this.connected)
            .onClick(() => this.onUploadStub())
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.card_background'))

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.accent())
          Text($r('app.string.ftp_loading'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMessage.length > 0) {
        Column() {
          Text($r('app.string.ftp_error'))
            .fontSize(16)
            .fontColor($r('app.color.danger'))
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
            .padding(12)
            .textAlign(TextAlign.Center)
          Text($r('app.string.ftp_refresh'))
            .fontSize(15)
            .fontColor(this.accent())
            .margin({ top: 16 })
            .onClick(() => this.onRefresh())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(16)
      } else if (!this.connected) {
        Column() {
          Text($r('app.string.ftp_not_connected'))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.entries.length === 0) {
        Column() {
          Text($r('app.string.ftp_empty_dir'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.entries, (entry: FtpEntry) => {
            ListItem() {
              Row() {
                Text(entry.isDirectory ? '📁' : '📄')
                  .fontSize(18)
                  .margin({ right: 10 })
                Column() {
                  Text(entry.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(entry.isDirectory ? $r('app.string.ftp_folder') : this.formatSize(entry.size))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (!entry.isDirectory) {
                  Text($r('app.string.ftp_download'))
                    .fontSize(13)
                    .fontColor(this.accent())
                    .padding({ left: 8, right: 4 })
                    .onClick(() => this.onDownload(entry))
                } else {
                  Text('›')
                    .fontSize(20)
                    .fontColor($r('app.color.chevron'))
                }
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 12, bottom: 12 })
              .onClick(() => {
                if (entry.isDirectory) {
                  this.onNavigate(entry);
                }
              })
            }
          }, (entry: FtpEntry) => entry.path)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({
          left: 16,
          right: 16,
          top: 8,
          bottom: 12
        })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.card_radius'))
        .clip(true)
        .divider({
          strokeWidth: 0.5,
          color: $r('app.color.divider'),
          startMargin: 44,
          endMargin: 12
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private breadcrumbParts(): BreadcrumbPart[] {
    const parts: BreadcrumbPart[] = [];
    parts.push({ label: '根目录', path: '/', isLast: this.cwd === '/' });
    if (this.cwd === '/') {
      return parts;
    }
    const segs = this.cwd.split('/').filter((s: string) => s.length > 0);
    let acc = '';
    for (let i = 0; i < segs.length; i++) {
      acc = `${acc}/${segs[i]}`;
      parts.push({
        label: segs[i],
        path: acc,
        isLast: i === segs.length - 1
      });
    }
    return parts;
  }

  private formatSize(size: number): string {
    if (size < 1024) {
      return `${size} B`;
    }
    if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)} KB`;
    }
    return `${(size / (1024 * 1024)).toFixed(1)} MB`;
  }
}

class BreadcrumbPart {
  label: string = '';
  path: string = '';
  isLast: boolean = false;
}
