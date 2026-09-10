import { HostConfig } from '../models/HostConfig';
import { HostListItem } from './HostListItem';

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
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button('+')
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .fontSize(20)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.onAdd())
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        top: 12,
        bottom: 12
      })

      if (this.hosts.length === 0) {
        Column() {
          Text('🖥️')
            .fontSize(48)
            .margin({ bottom: 12 })
          Text($r('app.string.host_list_empty'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Button($r('app.string.host_add'))
            .margin({ top: 20 })
            .backgroundColor($r('app.color.primary'))
            .onClick(() => this.onAdd())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding($r('app.float.page_padding'))
      } else {
        List() {
          ForEach(this.hosts, (host: HostConfig) => {
            ListItem() {
              HostListItem({
                host: host,
                selected: host.id === this.selectedId,
                onConnect: (h: HostConfig) => this.onConnect(h),
                onEdit: (h: HostConfig) => this.onEdit(h),
                onDelete: (h: HostConfig) => this.onDelete(h)
              })
            }
          }, (host: HostConfig) => host.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          bottom: 12
        })
        .divider({
          strokeWidth: 0
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
