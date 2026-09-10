import { HostConfig } from '../models/HostConfig';

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
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 8 }) {
        Button($r('app.string.btn_connect'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(12)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.onConnect(this.host))

        Button($r('app.string.btn_edit'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(12)
          .backgroundColor('#E8E8E8')
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.onEdit(this.host))

        Button($r('app.string.btn_delete'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(12)
          .backgroundColor($r('app.color.danger'))
          .onClick(() => this.onDelete(this.host))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selected ? '#1A0A59F7' : $r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .margin({ bottom: 8 })
  }
}
