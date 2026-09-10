import { router, promptAction, display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { MockSshSession, SshSessionFactory } from '../services/SshSession';
import { FtpEntry, FtpSessionFactory, MockFtpSession } from '../services/FtpSession';
import { MockVncSession, VncFramebufferInfo, VncSessionFactory } from '../services/VncSession';
import { HostListPanel } from '../components/HostListPanel';
import { TerminalView } from '../components/TerminalView';
import { FtpBrowserView } from '../components/FtpBrowserView';
import { VncSessionView } from '../components/VncSessionView';
import { BreakpointHelper, WindowSizeState } from '../layout/Breakpoint';
import { RouteNames } from '../common/Constants';

/**
 * 主页：窄屏栈式导航；宽屏主从分栏。
 * 右侧面板按主机协议切换 SSH 终端 / FTP 浏览器 / VNC 桌面。
 */
@Entry
@Component
struct Index {
  @State hosts: HostConfig[] = [];
  @State selectedId: string = '';
  @State selectedProtocol: string = '';
  @State useSplit: boolean = false;
  @State widthVp: number = 360;
  @State heightVp: number = 780;
  @State listPaneWidth: string = '34%';

  // SSH
  @State terminalOutput: string = '';
  @State terminalInput: string = '';
  @State terminalConnected: boolean = false;
  @State terminalTitle: string = '';

  // FTP
  @State ftpTitle: string = '';
  @State ftpCwd: string = '/';
  @State ftpEntries: FtpEntry[] = [];
  @State ftpConnected: boolean = false;
  @State ftpStatus: string = '';
  @State ftpLoading: boolean = false;
  @State ftpError: string = '';

  // VNC
  @State vncTitle: string = '';
  @State vncConnected: boolean = false;
  @State vncStatus: string = '';
  @State vncFramebuffer: VncFramebufferInfo | null = null;

  private sshSession: MockSshSession = SshSessionFactory.create() as MockSshSession;
  private ftpSession: MockFtpSession = FtpSessionFactory.create() as MockFtpSession;
  private vncSession: MockVncSession = VncSessionFactory.create() as MockVncSession;
  private windowClass: window.Window | undefined = undefined;
  private sizeSnapshot: WindowSizeState = new WindowSizeState();

  aboutToAppear(): void {
    this.reloadHosts();
    this.sshSession.onOutput((_chunk: string) => {
      this.terminalOutput = this.sshSession.getOutput();
      this.terminalConnected = this.sshSession.isConnected();
    });
    this.ftpSession.onStatus((msg: string) => {
      this.ftpStatus = msg;
    });
    this.vncSession.onStatus((msg: string) => {
      this.vncStatus = msg;
    });
    this.initWindowListener();
  }

  aboutToDisappear(): void {
    this.detachWindowListener();
    this.disconnectAll();
  }

  onPageShow(): void {
    this.reloadHosts();
  }

  private reloadHosts(): void {
    this.hosts = HostStore.getInstance().getAll();
  }

  private initWindowListener(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        this.windowClass = win;
        this.applyWindowSize(win);
        win.on('windowSizeChange', (size: window.Size) => {
          this.onSizeChanged(size.width, size.height);
        });
      }).catch(() => {
        try {
          const d = display.getDefaultDisplaySync();
          this.onSizeChanged(d.width, d.height);
        } catch (_e) {
          this.useSplit = false;
        }
      });
    } catch (_e) {
      this.useSplit = false;
    }
  }

  private detachWindowListener(): void {
    if (this.windowClass) {
      try {
        this.windowClass.off('windowSizeChange');
      } catch (_e) {
        // ignore
      }
    }
  }

  private applyWindowSize(win: window.Window): void {
    try {
      const props = win.getWindowProperties();
      const rect = props.windowRect;
      this.onSizeChanged(rect.width, rect.height);
    } catch (_e) {
      // ignore
    }
  }

  private onSizeChanged(widthPx: number, heightPx: number): void {
    let density = 1;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
      if (density <= 0) {
        density = 1;
      }
    } catch (_e) {
      density = 1;
    }
    const widthVp = widthPx / density;
    const heightVp = heightPx / density;
    this.widthVp = widthVp;
    this.heightVp = heightVp;
    this.sizeSnapshot.update(widthVp, heightVp);
    this.useSplit = BreakpointHelper.useSplitLayout(widthVp);
    this.listPaneWidth = BreakpointHelper.listPanePercent(widthVp);
  }

  private goAdd(): void {
    router.pushUrl({ url: RouteNames.HOST_EDIT });
  }

  private goEdit(host: HostConfig): void {
    router.pushUrl({
      url: RouteNames.HOST_EDIT,
      params: {
        'hostId': host.id
      }
    });
  }

  private confirmDelete(host: HostConfig): void {
    promptAction.showDialog({
      title: $r('app.string.btn_delete'),
      message: $r('app.string.confirm_delete'),
      buttons: [
        { text: $r('app.string.btn_cancel'), color: '#666666' },
        { text: $r('app.string.btn_delete'), color: '#E84026' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        HostStore.getInstance().remove(host.id).then(() => {
          if (this.selectedId === host.id) {
            this.clearSelection();
          }
          this.reloadHosts();
          promptAction.showToast({ message: $r('app.string.toast_deleted') });
        });
      }
    });
  }

  private clearSelection(): void {
    this.selectedId = '';
    this.selectedProtocol = '';
    this.disconnectAll();
    this.terminalConnected = false;
    this.terminalOutput = '';
    this.terminalTitle = '';
    this.ftpConnected = false;
    this.ftpEntries = [];
    this.ftpTitle = '';
    this.ftpCwd = '/';
    this.ftpStatus = '';
    this.ftpError = '';
    this.vncConnected = false;
    this.vncFramebuffer = null;
    this.vncTitle = '';
    this.vncStatus = '';
  }

  private async disconnectAll(): Promise<void> {
    if (this.sshSession.isConnected()) {
      await this.sshSession.disconnect();
    }
    if (this.ftpSession.isConnected()) {
      await this.ftpSession.disconnect();
    }
    if (this.vncSession.isConnected()) {
      await this.vncSession.disconnect();
    }
  }

  private connectHost(host: HostConfig): void {
    this.selectedId = host.id;
    this.selectedProtocol = host.protocol;
    if (this.useSplit) {
      this.openInSplit(host);
    } else {
      this.pushSessionPage(host);
    }
  }

  private pushSessionPage(host: HostConfig): void {
    let url = RouteNames.TERMINAL;
    if (host.protocol === 'ftp') {
      url = RouteNames.FTP_BROWSER;
    } else if (host.protocol === 'vnc') {
      url = RouteNames.VNC_SESSION;
    }
    router.pushUrl({
      url: url,
      params: {
        'hostId': host.id
      }
    });
  }

  private async openInSplit(host: HostConfig): Promise<void> {
    await this.disconnectAll();
    this.terminalConnected = false;
    this.ftpConnected = false;
    this.vncConnected = false;
    this.terminalOutput = '';
    this.ftpEntries = [];
    this.vncFramebuffer = null;

    if (host.protocol === 'ftp') {
      await this.openFtpSplit(host);
    } else if (host.protocol === 'vnc') {
      await this.openVncSplit(host);
    } else {
      await this.openSshSplit(host);
    }
  }

  private async openSshSplit(host: HostConfig): Promise<void> {
    this.terminalTitle = host.displayName();
    this.sshSession.clearOutput();
    await this.sshSession.connect(host);
    this.terminalOutput = this.sshSession.getOutput();
    this.terminalConnected = this.sshSession.isConnected();
  }

  private async openFtpSplit(host: HostConfig): Promise<void> {
    this.ftpTitle = host.displayName();
    this.ftpLoading = true;
    this.ftpError = '';
    try {
      await this.ftpSession.connect(host);
      this.ftpConnected = true;
      this.ftpCwd = this.ftpSession.getCwd();
      this.ftpEntries = await this.ftpSession.list();
    } catch (e) {
      this.ftpError = `${e}`;
      this.ftpConnected = false;
    } finally {
      this.ftpLoading = false;
    }
  }

  private async openVncSplit(host: HostConfig): Promise<void> {
    this.vncTitle = host.displayName();
    await this.vncSession.connect(host);
    this.vncConnected = this.vncSession.isConnected();
    this.vncFramebuffer = this.vncSession.getFramebuffer();
    this.vncStatus = this.vncSession.getStatusMessage();
  }

  private async refreshFtpList(): Promise<void> {
    this.ftpLoading = true;
    this.ftpError = '';
    try {
      this.ftpEntries = await this.ftpSession.list();
      this.ftpCwd = this.ftpSession.getCwd();
    } catch (e) {
      this.ftpError = `${e}`;
      this.ftpEntries = [];
    } finally {
      this.ftpLoading = false;
    }
  }

  private hasActiveSession(): boolean {
    return this.selectedId.length > 0 ||
      this.terminalConnected ||
      this.ftpConnected ||
      this.vncConnected;
  }

  build() {
    Column() {
      if (this.useSplit) {
        this.SplitLayout()
      } else {
        this.NarrowLayout()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NarrowLayout() {
    HostListPanel({
      hosts: this.hosts,
      selectedId: this.selectedId,
      onAdd: () => {
        this.goAdd();
      },
      onConnect: (h: HostConfig) => {
        this.connectHost(h);
      },
      onEdit: (h: HostConfig) => {
        this.goEdit(h);
      },
      onDelete: (h: HostConfig) => {
        this.confirmDelete(h);
      }
    })
  }

  @Builder
  SplitLayout() {
    Row() {
      HostListPanel({
        hosts: this.hosts,
        selectedId: this.selectedId,
        onAdd: () => {
          this.goAdd();
        },
        onConnect: (h: HostConfig) => {
          this.connectHost(h);
        },
        onEdit: (h: HostConfig) => {
          this.goEdit(h);
        },
        onDelete: (h: HostConfig) => {
          this.confirmDelete(h);
        }
      })
        .width(this.listPaneWidth)
        .height('100%')

      Divider()
        .vertical(true)
        .color($r('app.color.divider'))
        .strokeWidth(1)

      if (this.hasActiveSession()) {
        this.SessionPane()
      } else {
        Column() {
          Text($r('app.string.terminal_select_host'))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.page_background'))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SessionPane() {
    if (this.selectedProtocol === 'ftp') {
      FtpBrowserView({
        title: this.ftpTitle,
        cwd: this.ftpCwd,
        entries: this.ftpEntries,
        connected: this.ftpConnected,
        statusMessage: this.ftpStatus,
        loading: this.ftpLoading,
        errorMessage: this.ftpError,
        onNavigate: (entry: FtpEntry) => {
          this.ftpSession.cd(entry.path).then(() => this.refreshFtpList());
        },
        onGoUp: () => {
          this.ftpSession.cd('..').then(() => this.refreshFtpList());
        },
        onRefresh: () => {
          this.refreshFtpList();
        },
        onDownload: (entry: FtpEntry) => {
          this.ftpSession.download(entry.path).then((content: string) => {
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
          this.ftpSession.upload(name, content).then(() => {
            promptAction.showToast({ message: `已上传(mock) ${name}` });
            return this.refreshFtpList();
          }).catch((e: Error) => {
            promptAction.showToast({ message: `上传失败: ${e}` });
          });
        },
        onDisconnect: () => {
          this.ftpSession.disconnect().then(() => {
            this.ftpConnected = false;
            this.ftpEntries = [];
            this.ftpStatus = this.ftpSession.getStatusMessage();
            this.selectedId = '';
            this.selectedProtocol = '';
          });
        },
        onBreadcrumb: (path: string) => {
          this.ftpSession.cd(path).then(() => this.refreshFtpList());
        }
      })
        .layoutWeight(1)
        .height('100%')
    } else if (this.selectedProtocol === 'vnc') {
      VncSessionView({
        title: this.vncTitle,
        connected: this.vncConnected,
        statusMessage: this.vncStatus,
        framebuffer: this.vncFramebuffer,
        onDisconnect: () => {
          this.vncSession.disconnect().then(() => {
            this.vncConnected = false;
            this.vncFramebuffer = null;
            this.vncStatus = this.vncSession.getStatusMessage();
            this.selectedId = '';
            this.selectedProtocol = '';
          });
        },
        onPointer: (x: number, y: number, buttons: number) => {
          this.vncSession.sendPointer(x, y, buttons);
          this.vncStatus = this.vncSession.getStatusMessage();
        },
        onKeyStub: () => {
          this.vncSession.sendKey(0xff0d, true);
          this.vncSession.sendKey(0xff0d, false);
          this.vncStatus = this.vncSession.getStatusMessage();
        }
      })
        .layoutWeight(1)
        .height('100%')
    } else {
      TerminalView({
        output: this.terminalOutput,
        connected: this.terminalConnected,
        title: this.terminalTitle,
        inputText: $terminalInput,
        onSend: (cmd: string) => {
          this.sshSession.send(cmd).then(() => {
            this.terminalOutput = this.sshSession.getOutput();
            this.terminalConnected = this.sshSession.isConnected();
          });
        },
        onDisconnect: () => {
          this.sshSession.disconnect().then(() => {
            this.terminalOutput = this.sshSession.getOutput();
            this.terminalConnected = false;
            this.selectedId = '';
            this.selectedProtocol = '';
          });
        }
      })
        .layoutWeight(1)
        .height('100%')
    }
  }
}
