import { HostConfig } from '../models/HostConfig';
import { HostListItem } from './HostListItem';

/**
 * 左侧 / 窄屏主机列表：鸿蒙设置纯净风大标题 + 白色分组卡片列表。
 */
@Component
export struct HostListPanel {
  @Prop hosts: HostConfig[] = [];
  @Prop selectedId: string = '';
  onAdd: () => void = () => {};
  onConnect: (host: HostConfig) => void = () => {};
  onEdit: (host: HostConfig) => void = () => {};
  onDelete: (host: HostConfig) => void = () => {};

  build() {
    Column() {
      Row() {
        Text($r('app.string.host_list_title'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('+')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .padding({ left: 12, right: 4, top: 4, bottom: 4 })
          .onClick(() => this.onAdd())
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        top: 16,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)

      if (this.hosts.length === 0) {
        Column() {
          Text($r('app.string.host_list_empty'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Text($r('app.string.host_add'))
            .fontSize(16)
            .fontColor($r('app.color.primary'))
            .margin({ top: 20 })
            .onClick(() => this.onAdd())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding($r('app.float.page_padding'))
      } else {
        // 白色分组卡片包裹列表行
        Column() {
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
                      .color($r('app.color.divider'))
                      .strokeWidth(0.5)
                      .margin({ left: 16 })
                  }
                }
              }
            }, (host: HostConfig) => host.id)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .divider({ strokeWidth: 0 })
        }
        .width('100%')
        .layoutWeight(1)
        .margin({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: 12
        })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.card_radius'))
        .clip(true)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
