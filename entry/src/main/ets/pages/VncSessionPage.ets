import { router } from '@kit.ArkUI';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { MockVncSession, VncFramebufferInfo, VncSessionFactory } from '../services/VncSession';
import { VncSessionView } from '../components/VncSessionView';

@Entry
@Component
struct VncSessionPage {
  @State title: string = '';
  @State connected: boolean = false;
  @State statusMessage: string = '';
  @State framebuffer: VncFramebufferInfo | null = null;
  private session: MockVncSession = VncSessionFactory.create() as MockVncSession;
  private host: HostConfig | null = null;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    let hostId = '';
    if (params && params['hostId']) {
      hostId = String(params['hostId']);
    }
    const found = HostStore.getInstance().getById(hostId);
    this.host = found !== undefined ? found : null;
    this.session.onStatus((msg: string) => {
      this.statusMessage = msg;
    });
    if (this.host) {
      this.title = this.host.displayName();
      this.session.connect(this.host).then(() => {
        this.connected = this.session.isConnected();
        this.framebuffer = this.session.getFramebuffer();
        this.statusMessage = this.session.getStatusMessage();
      });
    } else {
      this.statusMessage = '未找到主机配置。';
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
          .fontColor($r('app.color.primary'))
          .onClick(() => {
            this.session.disconnect().then(() => {
              router.back();
            });
          })
        Blank()
      }
      .width('100%')
      .padding({ left: 4, right: 8, top: 4 })

      VncSessionView({
        title: this.title,
        connected: this.connected,
        statusMessage: this.statusMessage,
        framebuffer: this.framebuffer,
        onDisconnect: () => {
          this.session.disconnect().then(() => {
            this.connected = false;
            this.framebuffer = null;
            this.statusMessage = this.session.getStatusMessage();
          });
        },
        onPointer: (x: number, y: number, buttons: number) => {
          this.session.sendPointer(x, y, buttons);
          this.statusMessage = this.session.getStatusMessage();
        },
        onKeyStub: () => {
          // 模拟一次按键（例如 Return keysym 0xff0d）
          this.session.sendKey(0xff0d, true);
          this.session.sendKey(0xff0d, false);
          this.statusMessage = this.session.getStatusMessage();
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
