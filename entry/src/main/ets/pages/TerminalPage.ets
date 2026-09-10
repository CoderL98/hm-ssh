import { router } from '@kit.ArkUI';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { ISshSession, SshSessionFactory } from '../services/SshSession';
import { TerminalView } from '../components/TerminalView';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';

@Entry
@Component
struct TerminalPage {
  @State output: string = '';
  @State inputText: string = '';
  @State connected: boolean = false;
  @State title: string = '';

  @StorageLink('themeRev') themeRev: number = 0;

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  private session: ISshSession = SshSessionFactory.create();
  private host: HostConfig | null = null;

  aboutToAppear(): void {
    // 连接前新鲜工厂：避免 field-init 时 AppSettings/.so 未就绪而永久 Mock
    this.session = SshSessionFactory.create();
    const params = router.getParams() as Record<string, string>;
    let hostId = '';
    if (params && params['hostId']) {
      hostId = String(params['hostId']);
    }
    const found = HostStore.getInstance().getById(hostId);
    this.host = found !== undefined ? found : null;
    if (this.host) {
      this.title = this.host.displayName();
      this.session.onOutput((_chunk: string) => {
        this.output = this.session.getOutput();
        this.connected = this.session.isConnected();
      });
      this.session.connect(this.host).then(() => {
        this.output = this.session.getOutput();
        this.connected = this.session.isConnected();
      }).catch((e: Error) => {
        this.output = `连接失败：${e.message}
${SshSessionFactory.lastNativeHint()}
`;
        this.connected = false;
      });
    } else {
      this.output = '未找到主机配置。\n';
    }
  }

  aboutToDisappear(): void {
    if (this.session.isConnected()) {
      this.session.disconnect();
    }
  }

  build() {
    Column() {
      Row() {
        Button('< 返回')
          .type(ButtonType.Normal)
          .backgroundColor(Color.Transparent)
          .fontColor(this.accent())
          .onClick(() => {
            this.session.disconnect().then(() => {
              router.back();
            });
          })
        Blank()
      }
      .width('100%')
      .padding({ left: 4, right: 8, top: 4 })

      TerminalView({
        output: this.output,
        connected: this.connected,
        title: this.title,
        inputText: $inputText,
        onSend: (cmd: string) => {
          this.session.send(cmd).then(() => {
            this.output = this.session.getOutput();
            this.connected = this.session.isConnected();
          });
        },
        onDisconnect: () => {
          this.session.disconnect().then(() => {
            this.output = this.session.getOutput();
            this.connected = false;
          });
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
