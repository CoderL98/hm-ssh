import { router, promptAction, display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { ISshSession, SshSessionFactory } from '../services/SshSession';
import { FtpEntry, FtpSessionFactory, IFtpSession } from '../services/FtpSession';
import { IVncSession, VncFramebufferInfo, VncSessionFactory } from '../services/VncSession';
import { HostListPanel } from '../components/HostListPanel';
import { TerminalView } from '../components/TerminalView';
import { FtpBrowserView } from '../components/FtpBrowserView';
import { VncSessionView } from '../components/VncSessionView';
import { BreakpointHelper, WindowSizeState } from '../layout/Breakpoint';
import { RouteNames } from '../common/Constants';
import { maybePushAfterLocalChange, syncAllCoalesced, CloudSyncServiceFactory } from '../services/CloudSyncService';
import { AuthStore } from '../services/AuthService';
import { ThemeTokens } from '../theme/ThemeTokens';
import { AppSettings } from '../services/AppSettings';

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
  @StorageLink('themeRev') themeRev: number = 0;
  @StorageLink('hostRev') @Watch('onHostRev') hostRev: number = 0;
  @StorageLink('authRev') @Watch('onAuthRev') authRev: number = 0;
  @StorageLink('appSettingsRev') @Watch('onAppSettingsRev') appSettingsRev: number = 0;
  @StorageLink('syncToastMsg') @Watch('onSyncToastMsg') syncToastMsg: string = '';
  @State authLoggedIn: boolean = false;
  @State authLabel: string = '';
  @State syncStatusLabel: string = '';
  @State syncing: boolean = false;

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

  private sshSession: ISshSession = SshSessionFactory.create();
  private ftpSession: IFtpSession = FtpSessionFactory.create();
  private vncSession: IVncSession = VncSessionFactory.create();
  private lastPreferNative: boolean = false;
  private windowClass: window.Window | undefined = undefined;
  private sizeSnapshot: WindowSizeState = new WindowSizeState();
  private sizeDebounceTimer: number = -1;
  private pendingWidthPx: number = 0;
  private pendingHeightPx: number = 0;

  aboutToAppear(): void {
    this.refreshAuth();
    this.reloadHosts();
    this.consumeSyncToast();
    void this.refreshSyncStatus();
    // AppSettings 就绪后再按工厂重建，避免 field-init 永久冻在 Mock
    this.lastPreferNative = AppSettings.getInstance().preferNative();
    // 会话延后到首次分栏连接时再按工厂创建（窄屏各会话页自建）
    this.initWindowListener();
  }

  aboutToDisappear(): void {
    if (this.sizeDebounceTimer >= 0) {
      clearTimeout(this.sizeDebounceTimer);
      this.sizeDebounceTimer = -1;
    }
    this.detachWindowListener();
    this.disconnectAll();
  }

  onPageShow(): void {
    this.refreshAuth();
    this.reloadHosts();
    this.consumeSyncToast();
    void this.refreshSyncStatus();
  }

  private reloadHosts(): void {
    void this.hostRev;
    this.hosts = HostStore.getInstance().getAll();
  }

  onHostRev(): void {
    this.reloadHosts();
  }

  onAuthRev(): void {
    this.refreshAuth();
    void this.refreshSyncStatus();
  }

  onAppSettingsRev(): void {
    void this.appSettingsRev;
    const prefer = AppSettings.getInstance().preferNative();
    if (prefer === this.lastPreferNative) {
      return;
    }
    this.lastPreferNative = prefer;
    // 原生开关翻转：重建会话；若分栏已选中主机则重连
    const selected = this.selectedId;
    void this.disconnectAll().then(() => {
      this.recreateSessions();
      if (this.useSplit && selected) {
        const host = HostStore.getInstance().getById(selected);
        if (host) {
          void this.openInSplit(host);
        }
      }
    });
  }

  /** 按当前 AppSettings / .so 可用性新鲜构造 Native* 或 Mock */
  private recreateSessions(): void {
    this.sshSession = SshSessionFactory.create();
    this.ftpSession = FtpSessionFactory.create();
    this.vncSession = VncSessionFactory.create();
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
  }

  private refreshAuth(): void {
    void this.authRev;
    const auth = AuthStore.getInstance();
    this.authLoggedIn = auth.isLoggedIn();
    const u = auth.getUser();
    this.authLabel = u ? u.username : '';
  }

  onSyncToastMsg(): void {
    this.consumeSyncToast();
  }

  private consumeSyncToast(): void {
    const msg = this.syncToastMsg;
    if (!msg || msg.length === 0) {
      return;
    }
    try {
      promptAction.showToast({ message: msg, duration: 2800 });
    } catch (_e) {
      // ignore
    }
    try {
      AppStorage.setOrCreate('syncToastMsg', '');
    } catch (_e) {
      // ignore
    }
  }

  private goAccount(): void {
    router.pushUrl({ url: RouteNames.ACCOUNT });
  }

  private initWindowListener(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        this.windowClass = win;
        this.applyWindowSize(win);
        win.on('windowSizeChange', (size: window.Size) => {
          this.scheduleSizeChanged(size.width, size.height);
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
          void maybePushAfterLocalChange('hosts');
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
    if (!AppSettings.getInstance().isReady()) {
      try {
        promptAction.showToast({ message: '设置加载中，请稍后再连接', duration: 2000 });
      } catch (_e) {
        // ignore
      }
      return;
    }
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
    // 每次按工厂重建，以响应「使用原生协议」开关与 .so 可用性
    this.recreateSessions();
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
    try {
      await this.sshSession.connect(host);
      this.terminalOutput = this.sshSession.getOutput();
      this.terminalConnected = this.sshSession.isConnected();
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      this.terminalOutput = `连接失败：${msg}
${SshSessionFactory.lastNativeHint()}
`;
      this.terminalConnected = false;
    }
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
      this.ftpError = `${e}（${FtpSessionFactory.lastNativeHint()}）`;
      this.ftpConnected = false;
    } finally {
      this.ftpLoading = false;
    }
  }

  private async openVncSplit(host: HostConfig): Promise<void> {
    this.vncTitle = host.displayName();
    try {
      await this.vncSession.connect(host);
      this.vncConnected = this.vncSession.isConnected();
      this.vncFramebuffer = this.vncSession.getFramebuffer();
      this.vncStatus = this.vncSession.getStatusMessage();
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      this.vncConnected = false;
      this.vncStatus = `连接失败：${msg}（${VncSessionFactory.lastNativeHint()}）`;
    }
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

  private splitHintColor(): string {
    void this.themeRev;
    return ThemeTokens.surface().textSecondary;
  }

  private splitPaneBg(): string {
    void this.themeRev;
    return ThemeTokens.surface().pageBackground;
  }

  private splitDivider(): string {
    void this.themeRev;
    return ThemeTokens.surface().divider;
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
      authLabel: this.authLabel,
      loggedIn: this.authLoggedIn,
      syncStatusLabel: this.syncStatusLabel,
      syncing: this.syncing,
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
      },
      onAccount: () => {
        this.goAccount();
      },
      onPullSync: () => {
        void this.doPullSync();
      }
    })
  }

  @Builder
  SplitLayout() {
    Row() {
      HostListPanel({
        hosts: this.hosts,
        selectedId: this.selectedId,
        authLabel: this.authLabel,
        loggedIn: this.authLoggedIn,
        syncStatusLabel: this.syncStatusLabel,
        syncing: this.syncing,
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
        },
        onAccount: () => {
          this.goAccount();
        },
        onPullSync: () => {
          void this.doPullSync();
        }
      })
        .width(this.listPaneWidth)
        .height('100%')

      Divider()
        .vertical(true)
        .color(this.splitDivider())
        .strokeWidth(1)

      if (this.hasActiveSession()) {
        this.SessionPane()
      } else {
        Column() {
          Text($r('app.string.terminal_select_host'))
            .fontSize(16)
            .fontColor(this.splitHintColor())
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.splitPaneBg())
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
