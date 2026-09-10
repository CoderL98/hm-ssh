import { VncFramebufferInfo } from '../services/VncSession';

/**
 * VNC 会话：设置风顶栏 chrome；仅桌面内容区保持深色占位。
 */
@Component
export struct VncSessionView {
  @Prop title: string = '';
  @Prop connected: boolean = false;
  @Prop statusMessage: string = '';
  @Prop framebuffer: VncFramebufferInfo | null = null;
  @Prop noteVisible: boolean = true;
  onDisconnect: () => void = () => {};
  onPointer: (x: number, y: number, buttons: number) => void = () => {};
  onKeyStub: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.title.length > 0 ? this.title : 'VNC')
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

      if (this.statusMessage.length > 0) {
        Text(this.statusMessage)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.card_background'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (!this.connected || !this.framebuffer) {
        Column() {
          Text($r('app.string.vnc_not_connected'))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          Text($r('app.string.vnc_native_note'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
            .padding({ left: 24, right: 24 })
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_background'))
      } else {
        Stack() {
          Column() {
            Text(this.fbLabel())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E8EEF5')
            Text(this.fbSizeText())
              .fontSize(13)
              .fontColor('#99AAB8')
              .margin({ top: 8 })
            Text($r('app.string.vnc_placeholder_hint'))
              .fontSize(12)
              .fontColor('#7A8A99')
              .margin({ top: 16 })
              .padding({ left: 20, right: 20 })
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.fbColor())

          Column() {
            ForEach([0, 1, 2, 3], (row: number) => {
              Row() {
                ForEach([0, 1, 2, 3], (col: number) => {
                  Column()
                    .width('25%')
                    .height('100%')
                    .border({
                      width: { right: col < 3 ? 0.5 : 0, bottom: row < 3 ? 0.5 : 0 },
                      color: '#14FFFFFF'
                    })
                }, (col: number) => `c${row}_${col}`)
              }
              .width('100%')
              .height('25%')
            }, (row: number) => `r${row}`)
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down || event.type === TouchType.Move) {
            if (event.touches && event.touches.length > 0) {
              const t = event.touches[0];
              this.onPointer(t.x, t.y, event.type === TouchType.Down ? 1 : 0);
            }
          } else if (event.type === TouchType.Up) {
            if (event.touches && event.touches.length > 0) {
              const t = event.touches[0];
              this.onPointer(t.x, t.y, 0);
            }
          }
        })

        Row({ space: 12 }) {
          Text($r('app.string.vnc_key_stub'))
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .padding({ left: 4, right: 8, top: 6, bottom: 6 })
            .onClick(() => this.onKeyStub())
          Text($r('app.string.vnc_native_note_short'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(2)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.card_background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private fbLabel(): string {
    if (this.framebuffer) {
      return this.framebuffer.label;
    }
    return 'VNC';
  }

  private fbSizeText(): string {
    if (this.framebuffer) {
      return `${this.framebuffer.width} × ${this.framebuffer.height}`;
    }
    return '';
  }

  private fbColor(): string {
    if (this.framebuffer) {
      return this.framebuffer.placeholderColor;
    }
    return '#1A2332';
  }
}
