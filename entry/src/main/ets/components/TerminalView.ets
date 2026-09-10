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
      .padding({
        left: 12,
        right: 12,
        top: 10,
        bottom: 10
      })
      .backgroundColor($r('app.color.card_background'))

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
      .onChange(() => {
        // keep for future
      })

      Row({ space: 8 }) {
        TextInput({
          placeholder: $r('app.string.terminal_input_hint'),
          text: this.inputText
        })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontFamily('monospace')
          .enabled(this.connected)
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.submitInput();
          })

        Button('发送')
          .height(40)
          .enabled(this.connected)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => this.submitInput())
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.card_background'))
    }
    .width('100%')
    .height('100%')
  }

  private submitInput(): void {
    if (!this.connected) {
      return;
    }
    const cmd = this.inputText;
    this.inputText = '';
    this.onSend(cmd);
    // 滚动到底部
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }
}
