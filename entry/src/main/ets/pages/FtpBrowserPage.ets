import { router, promptAction } from '@kit.ArkUI';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { FtpEntry, FtpSessionFactory, MockFtpSession } from '../services/FtpSession';
import { FtpBrowserView } from '../components/FtpBrowserView';
import { ThemeStore } from '../services/ThemeStore';
import { ThemeTokens } from '../theme/ThemeTokens';

@Entry
@Component
struct FtpBrowserPage {
  @State title: string = '';
  @State cwd: string = '/';
  @State entries: FtpEntry[] = [];
  @State connected: boolean = false;
  @State statusMessage: string = '';
  @State loading: boolean = false;
  @State errorMessage: string = '';

  @StorageLink('themeRev') themeRev: number = 0;

  private accent(): string {
    void this.themeRev;
    return ThemeTokens.accentColor(ThemeStore.getInstance().getAccentId());
  }

  private session: MockFtpSession = FtpSessionFactory.create() as MockFtpSession;
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
      this.doConnect();
    } else {
      this.errorMessage = '未找到主机配置。';
    }
  }

  aboutToDisappear(): void {
    if (this.session.isConnected()) {
      this.session.disconnect();
    }
  }

  private async doConnect(): Promise<void> {
    if (!this.host) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      await this.session.connect(this.host);
      this.connected = true;
      this.cwd = this.session.getCwd();
      await this.refreshList();
    } catch (e) {
      this.errorMessage = `${e}`;
      this.connected = false;
    } finally {
      this.loading = false;
    }
  }

  private async refreshList(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.entries = await this.session.list();
      this.cwd = this.session.getCwd();
    } catch (e) {
      this.errorMessage = `${e}`;
      this.entries = [];
    } finally {
      this.loading = false;
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

      FtpBrowserView({
        title: this.title,
        cwd: this.cwd,
        entries: this.entries,
        connected: this.connected,
        statusMessage: this.statusMessage,
        loading: this.loading,
        errorMessage: this.errorMessage,
        onNavigate: (entry: FtpEntry) => {
          this.session.cd(entry.path).then(() => this.refreshList());
        },
        onGoUp: () => {
          this.session.cd('..').then(() => this.refreshList());
        },
        onRefresh: () => {
          this.refreshList();
        },
        onDownload: (entry: FtpEntry) => {
          this.session.download(entry.path).then((content: string) => {
            promptAction.showToast({
              message: `已下载(mock) ${entry.name}，${content.length} 字节`
            });
          }).catch((e: Error) => {
            promptAction.showToast({ message: `下载失败: ${e}` });
          });
        },
        onUploadStub: () => {
          const name = `upload_${Date.now()}.txt`;
          const content = `Mock upload at ${new Date().toISOString()}\n`;
          this.session.upload(name, content).then(() => {
            promptAction.showToast({ message: `已上传(mock) ${name}` });
            return this.refreshList();
          }).catch((e: Error) => {
            promptAction.showToast({ message: `上传失败: ${e}` });
          });
        },
        onDisconnect: () => {
          this.session.disconnect().then(() => {
            this.connected = false;
            this.entries = [];
            this.statusMessage = this.session.getStatusMessage();
          });
        },
        onBreadcrumb: (path: string) => {
          this.session.cd(path).then(() => this.refreshList());
        }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
