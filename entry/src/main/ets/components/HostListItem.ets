import { HostConfig } from '../models/HostConfig';

/**
 * 设置列表行：标题 + 副标题、灰色协议标签、右箭头；整行点击连接。
 * 编辑 / 删除通过长按菜单或次要文字，避免胶囊按钮堆叠。
 */
@Component
export struct HostListItem {
  @Prop host: HostConfig = new HostConfig();
  @Prop selected: boolean = false;
  onConnect: (host: HostConfig) => void = () => {};
  onEdit: (host: HostConfig) => void = () => {};
  onDelete: (host: HostConfig) => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.host.displayName())
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.host.subtitle())
          .fontSize($r('app.float.caption_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.host.protocolLabel())
        .fontSize(11)
        .fontColor($r('app.color.badge_text'))
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.badge_background'))
        .borderRadius(4)
        .margin({ right: 8 })

      Text($r('app.string.btn_edit'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 4, right: 8 })
        .onClick(() => this.onEdit(this.host))

      Text('›')
        .fontSize(22)
        .fontColor($r('app.color.chevron'))
        .margin({ left: 2 })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 14, bottom: 14 })
    .backgroundColor(this.selected ? $r('app.color.row_selected') : Color.Transparent)
    .onClick(() => this.onConnect(this.host))
    .bindContextMenu(this.OverflowMenu, ResponseType.LongPress)
  }

  @Builder
  OverflowMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.btn_connect') })
        .onClick(() => this.onConnect(this.host))
      MenuItem({ content: $r('app.string.btn_edit') })
        .onClick(() => this.onEdit(this.host))
      MenuItem({ content: $r('app.string.btn_delete') })
        .onClick(() => this.onDelete(this.host))
    }
  }
}
