import { router, promptAction } from '@kit.ArkUI';
import { HostConfig, HostProtocol } from '../models/HostConfig';
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
  @State remotePath: string = '/';
  @State protocol: HostProtocol = 'ssh';
  @State editingId: string = '';
  @State isEdit: boolean = false;
  private lastProtocol: HostProtocol = 'ssh';

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
        this.remotePath = existing.remotePath || '/';
        this.protocol = existing.protocol;
        this.lastProtocol = existing.protocol;
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
          this.protocolPicker()
          this.formField('显示名称', this.name, (v: string) => {
            this.name = v;
          }, '例如：家里 NAS')
          this.formField('主机地址', this.host, (v: string) => {
            this.host = v;
          }, 'IP 或域名')
          this.formField('端口', this.portText, (v: string) => {
            this.portText = v;
          }, `${HostConfig.defaultPort(this.protocol)}`)

          if (this.protocol === 'ssh' || this.protocol === 'ftp') {
            this.formField('用户名', this.username, (v: string) => {
              this.username = v;
            }, this.protocol === 'ftp' ? 'ftpuser' : 'root')
          }

          this.passwordField()

          if (this.protocol === 'ssh') {
            this.privateKeyField()
          }

          if (this.protocol === 'ftp') {
            this.formField('初始路径（可选）', this.remotePath, (v: string) => {
              this.remotePath = v;
            }, '/')
          }

          if (this.protocol === 'vnc') {
            Text($r('app.string.vnc_edit_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 4 })
          }
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
  protocolPicker() {
    Column() {
      Text($r('app.string.host_protocol'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6 })
        .width('100%')
      Row({ space: 8 }) {
        this.protocolChip('SSH', 'ssh')
        this.protocolChip('FTP', 'ftp')
        this.protocolChip('VNC', 'vnc')
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  protocolChip(label: string, value: HostProtocol) {
    Button(label)
      .type(ButtonType.Capsule)
      .height(36)
      .fontSize(14)
      .layoutWeight(1)
      .backgroundColor(this.protocol === value ? $r('app.color.primary') : '#E8E8E8')
      .fontColor(this.protocol === value ? Color.White : $r('app.color.text_primary'))
      .onClick(() => {
        this.onProtocolChange(value);
      })
  }

  private onProtocolChange(next: HostProtocol): void {
    if (this.protocol === next) {
      return;
    }
    const prevDefault = HostConfig.defaultPort(this.lastProtocol);
    let port = parseInt(this.portText, 10);
    // 若端口仍是上一协议默认值，则切换到新协议默认端口
    if (isNaN(port) || port === prevDefault) {
      this.portText = `${HostConfig.defaultPort(next)}`;
    }
    this.protocol = next;
    this.lastProtocol = next;
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
      Text(this.protocol === 'vnc' ? $r('app.string.vnc_password') : $r('app.string.host_password'))
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
    if (!hostAddr) {
      promptAction.showToast({ message: $r('app.string.toast_invalid_host') });
      return;
    }
    // SSH / FTP 需要用户名；VNC 仅需主机与密码
    if (this.protocol !== 'vnc') {
      const user = this.username.trim();
      if (!user) {
        promptAction.showToast({ message: $r('app.string.toast_invalid') });
        return;
      }
    }
    let port = parseInt(this.portText, 10);
    if (isNaN(port) || port <= 0 || port > 65535) {
      port = HostConfig.defaultPort(this.protocol);
    }
    const config = new HostConfig();
    config.id = this.editingId;
    config.name = this.name.trim();
    config.host = hostAddr;
    config.port = port;
    config.username = this.username.trim();
    config.password = this.password;
    config.privateKey = this.protocol === 'ssh' ? this.privateKey : '';
    config.protocol = this.protocol;
    config.remotePath = this.protocol === 'ftp'
      ? (this.remotePath.trim().length > 0 ? this.remotePath.trim() : '/')
      : '/';
    await HostStore.getInstance().upsert(config);
    promptAction.showToast({ message: $r('app.string.toast_saved') });
    router.back();
  }
}
