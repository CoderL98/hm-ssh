import { router, promptAction } from '@kit.ArkUI';
import { HostConfig, HostProtocol } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';
import { maybePushAfterLocalChange } from '../services/CloudSyncService';

/**
 * 主机编辑：设置表单风格 —— 顶栏取消/保存文字操作 + 白色分组字段。
 */
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
  @StorageLink('themeRev') themeRev: number = 0;
  private lastProtocol: HostProtocol = 'ssh';

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  private accentSoft(): string {
    void this.themeRev;
    return ThemeTokens.accentSoft(ThemeStore.getInstance().getAccentId());
  }

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
        Text($r('app.string.btn_cancel'))
          .fontSize(16)
          .fontColor(this.accent())
          .padding({ left: 4, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            router.back();
          })
        Text(this.isEdit ? $r('app.string.host_edit') : $r('app.string.host_add'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text($r('app.string.btn_save'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accent())
          .padding({ left: 12, right: 4, top: 8, bottom: 8 })
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          // 协议分组
          Column() {
            this.protocolPicker()
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          // 基本信息分组
          Column() {
            this.formRow('显示名称', this.name, (v: string) => {
              this.name = v;
            }, '例如：家里 NAS')
            this.thinDivider()
            this.formRow('主机地址', this.host, (v: string) => {
              this.host = v;
            }, 'IP 或域名')
            this.thinDivider()
            this.formRow('端口', this.portText, (v: string) => {
              this.portText = v;
            }, `${HostConfig.defaultPort(this.protocol)}`)
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_radius'))
          .clip(true)

          if (this.protocol === 'ssh' || this.protocol === 'ftp') {
            Column() {
              this.formRow('用户名', this.username, (v: string) => {
                this.username = v;
              }, this.protocol === 'ftp' ? 'ftpuser' : 'root')
              this.thinDivider()
              this.passwordRow()
              if (this.protocol === 'ssh') {
                this.thinDivider()
                this.privateKeyRow()
              }
              if (this.protocol === 'ftp') {
                this.thinDivider()
                this.formRow('初始路径（可选）', this.remotePath, (v: string) => {
                  this.remotePath = v;
                }, '/')
              }
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius($r('app.float.card_radius'))
            .clip(true)
          }

          if (this.protocol === 'vnc') {
            Column() {
              this.passwordRow()
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius($r('app.float.card_radius'))
            .clip(true)

            Text($r('app.string.vnc_edit_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ left: 4, right: 4 })
          }
        }
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          top: 8,
          bottom: 24
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  thinDivider() {
    Divider()
      .color($r('app.color.divider'))
      .strokeWidth(0.5)
      .margin({ left: 16 })
  }

  @Builder
  protocolPicker() {
    Column() {
      Text($r('app.string.host_protocol'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 16, top: 12, bottom: 8 })
        .width('100%')
      Row({ space: 8 }) {
        this.protocolChip('SSH', 'ssh')
        this.protocolChip('FTP', 'ftp')
        this.protocolChip('VNC', 'vnc')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  protocolChip(label: string, value: HostProtocol) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.protocol === value ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.protocol === value ? this.accent() : $r('app.color.text_primary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .borderRadius(8)
      .backgroundColor(this.protocol === value ? this.accentSoft() : $r('app.color.control_secondary'))
      .border({
        width: this.protocol === value ? 1 : 0,
        color: this.accent()
      })
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
    if (isNaN(port) || port === prevDefault) {
      this.portText = `${HostConfig.defaultPort(next)}`;
    }
    this.protocol = next;
    this.lastProtocol = next;
  }

  @Builder
  formRow(label: string, value: string, onChange: (v: string) => void, placeholder: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .width(96)
      TextInput({ placeholder: placeholder, text: value })
        .layoutWeight(1)
        .height(48)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  passwordRow() {
    Row() {
      Text(this.protocol === 'vnc' ? $r('app.string.vnc_password') : $r('app.string.host_password'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .width(96)
      TextInput({ placeholder: '可选，演示用明文存储', text: this.password })
        .layoutWeight(1)
        .height(48)
        .type(InputType.Password)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange((v: string) => {
          this.password = v;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  privateKeyRow() {
    Column() {
      Text($r('app.string.host_private_key'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })
      TextArea({
        placeholder: $r('app.string.host_private_key_placeholder'),
        text: this.privateKey
      })
        .width('100%')
        .height(100)
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => {
          this.privateKey = v;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  private async save(): Promise<void> {
    const hostAddr = this.host.trim();
    if (!hostAddr) {
      promptAction.showToast({ message: $r('app.string.toast_invalid_host') });
      return;
    }
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
    // 登录态后台推送（不含密码/私钥）
    void maybePushAfterLocalChange('hosts');
    promptAction.showToast({ message: $r('app.string.toast_saved') });
    router.back();
  }
}
