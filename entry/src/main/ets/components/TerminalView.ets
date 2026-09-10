/**
 * SSH 终端：设置风顶栏 / 底栏 chrome；仅内容区使用 terminal 深色。
 */
@Component
export struct TerminalView {
  @Prop output: string = '';
  @Prop connected: boolean = false;
  @Prop title: string = '';
  @Link inputText: string;
  onSend: (cmd: string) => void = () => {};
  onDisconnect: () => void = () => {};
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      Row() {
        Text(this.title.length > 0 ? this.title : '终端')
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
      .padding({
        left: 16,
        right: 12,
        top: 12,
        bottom: 12
      })
      .backgroundColor($r('app.color.card_background'))

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.5)

      Scroll(this.scroller) {
        Text(this.output.length > 0 ? this.output : ' ')
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor($r('app.color.terminal_fg'))
          .width('100%')
          .padding(12)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.terminal_bg'))
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.5)

      Row({ space: 10 }) {
        TextInput({
          placeholder: $r('app.string.terminal_input_hint'),
          text: this.inputText
        })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontFamily('monospace')
          .backgroundColor($r('app.color.control_secondary'))
          .borderRadius(8)
          .enabled(this.connected)
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.submitInput();
          })

        Text('发送')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.connected ? $r('app.color.primary') : $r('app.color.text_secondary'))
          .padding({ left: 8, right: 4, top: 8, bottom: 8 })
          .enabled(this.connected)
          .onClick(() => this.submitInput())
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private submitInput(): void {
    if (!this.connected) {
      return;
    }
    const cmd = this.inputText;
    this.inputText = '';
    this.onSend(cmd);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }
}
