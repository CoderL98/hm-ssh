import { router, promptAction } from '@kit.ArkUI';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';

@Entry
@Component
struct HostEditPage {
  @State name: string = '';
  @State host: string = '';
  @State portText: string = '22';
  @State username: string = '';
  @State password: string = '';
  @State privateKey: string = '';
  @State editingId: string = '';
  @State isEdit: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params['hostId']) {
      const hostId = String(params['hostId']);
      const existing = HostStore.getInstance().getById(hostId);
      if (existing) {
        this.editingId = existing.id;
        this.name = existing.name;
        this.host = existing.host;
        this.portText = `${existing.port}`;
        this.username = existing.username;
        this.password = existing.password;
        this.privateKey = existing.privateKey;
        this.isEdit = true;
      }
    }
  }

  build() {
    Column() {
      Row() {
        Button($r('app.string.btn_cancel'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })
        Text(this.isEdit ? $r('app.string.host_edit') : $r('app.string.host_add'))
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button($r('app.string.btn_save'))
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding(12)

      Scroll() {
        Column({ space: 12 }) {
          this.formField('显示名称', this.name, (v: string) => {
            this.name = v;
          }, '例如：家里 NAS')
          this.formField('主机地址', this.host, (v: string) => {
            this.host = v;
          }, 'IP 或域名')
          this.formField('端口', this.portText, (v: string) => {
            this.portText = v;
          }, '22')
          this.formField('用户名', this.username, (v: string) => {
            this.username = v;
          }, 'root')
          this.passwordField()
          this.privateKeyField()
        }
        .padding($r('app.float.page_padding'))
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  formField(label: string, value: string, onChange: (v: string) => void, placeholder: string) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6 })
        .width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.card_background'))
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  passwordField() {
    Column() {
      Text($r('app.string.host_password'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6 })
        .width('100%')
      TextInput({ placeholder: '可选，演示用明文存储', text: this.password })
        .width('100%')
        .height(44)
        .type(InputType.Password)
        .backgroundColor($r('app.color.card_background'))
        .onChange((v: string) => {
          this.password = v;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  privateKeyField() {
    Column() {
      Text($r('app.string.host_private_key'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6 })
        .width('100%')
      TextArea({
        placeholder: $r('app.string.host_private_key_placeholder'),
        text: this.privateKey
      })
        .width('100%')
        .height(120)
        .backgroundColor($r('app.color.card_background'))
        .onChange((v: string) => {
          this.privateKey = v;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private async save(): Promise<void> {
    const hostAddr = this.host.trim();
    const user = this.username.trim();
    if (!hostAddr || !user) {
      promptAction.showToast({ message: $r('app.string.toast_invalid') });
      return;
    }
    let port = parseInt(this.portText, 10);
    if (isNaN(port) || port <= 0 || port > 65535) {
      port = 22;
    }
    const config = new HostConfig();
    config.id = this.editingId;
    config.name = this.name.trim();
    config.host = hostAddr;
    config.port = port;
    config.username = user;
    config.password = this.password;
    config.privateKey = this.privateKey;
    await HostStore.getInstance().upsert(config);
    promptAction.showToast({ message: $r('app.string.toast_saved') });
    router.back();
  }
}
