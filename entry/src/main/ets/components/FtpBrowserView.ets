import { FtpEntry } from '../services/FtpSession';

@Component
export struct FtpBrowserView {
  @Prop title: string = '';
  @Prop cwd: string = '/';
  @Prop entries: FtpEntry[] = [];
  @Prop connected: boolean = false;
  @Prop statusMessage: string = '';
  @Prop loading: boolean = false;
  @Prop errorMessage: string = '';
  onNavigate: (entry: FtpEntry) => void = () => {};
  onGoUp: () => void = () => {};
  onRefresh: () => void = () => {};
  onDownload: (entry: FtpEntry) => void = () => {};
  onUploadStub: () => void = () => {};
  onDisconnect: () => void = () => {};
  onBreadcrumb: (path: string) => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.title.length > 0 ? this.title : 'FTP')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.connected) {
          Button($r('app.string.btn_disconnect'))
            .type(ButtonType.Capsule)
            .height(32)
            .fontSize(12)
            .backgroundColor($r('app.color.danger'))
            .onClick(() => this.onDisconnect())
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.card_background'))

      // 面包屑 + 操作
      Column() {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.breadcrumbParts(), (part: BreadcrumbPart) => {
              Text(part.label)
                .fontSize(13)
                .fontColor(part.path === this.cwd ? $r('app.color.primary') : $r('app.color.text_secondary'))
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

        Row({ space: 8 }) {
          Button($r('app.string.ftp_go_up'))
            .type(ButtonType.Capsule)
            .height(30)
            .fontSize(12)
            .enabled(this.connected && this.cwd !== '/')
            .backgroundColor('#E8E8E8')
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.onGoUp())
          Button($r('app.string.ftp_refresh'))
            .type(ButtonType.Capsule)
            .height(30)
            .fontSize(12)
            .enabled(this.connected)
            .backgroundColor('#E8E8E8')
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.onRefresh())
          Button($r('app.string.ftp_upload'))
            .type(ButtonType.Capsule)
            .height(30)
            .fontSize(12)
            .enabled(this.connected)
            .backgroundColor($r('app.color.ftp_badge'))
            .onClick(() => this.onUploadStub())
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .alignItems(HorizontalAlign.Start)

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
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
          Button($r('app.string.ftp_refresh'))
            .margin({ top: 16 })
            .backgroundColor($r('app.color.primary'))
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
          Text('📂')
            .fontSize(40)
            .margin({ bottom: 8 })
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
                  Button($r('app.string.ftp_download'))
                    .type(ButtonType.Capsule)
                    .height(28)
                    .fontSize(11)
                    .backgroundColor($r('app.color.primary'))
                    .onClick(() => this.onDownload(entry))
                }
              }
              .width('100%')
              .padding(12)
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
        .divider({
          strokeWidth: 0.5,
          color: $r('app.color.divider'),
          startMargin: 40,
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
