import { router, promptAction, display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HostConfig } from '../models/HostConfig';
import { HostStore } from '../services/HostStore';
import { MockSshSession, SshSessionFactory } from '../services/SshSession';
import { HostListPanel } from '../components/HostListPanel';
import { TerminalView } from '../components/TerminalView';
import { BreakpointHelper, WindowSizeState } from '../layout/Breakpoint';
import { RouteNames } from '../common/Constants';

/**
 * 主页：根据窗口宽度在窄屏栈式导航与宽屏主从分栏间切换。
 * 阔折叠展开横屏、平板等宽度充足时，左侧主机列表 + 右侧终端。
 */
@Entry
@Component
struct Index {
  @State hosts: HostConfig[] = [];
  @State selectedId: string = '';
  @State useSplit: boolean = false;
  @State widthVp: number = 360;
  @State heightVp: number = 780;
  @State terminalOutput: string = '';
  @State terminalInput: string = '';
  @State terminalConnected: boolean = false;
  @State terminalTitle: string = '';
  private session: MockSshSession = SshSessionFactory.create() as MockSshSession;
  private windowClass: window.Window | undefined = undefined;
  private sizeSnapshot: WindowSizeState = new WindowSizeState();

  aboutToAppear(): void {
    this.reloadHosts();
    this.session.onOutput((_chunk: string) => {
      this.terminalOutput = this.session.getOutput();
      this.terminalConnected = this.session.isConnected();
    });
    this.initWindowListener();
  }

  aboutToDisappear(): void {
    this.detachWindowListener();
    if (this.session.isConnected()) {
      this.session.disconnect();
    }
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

  /**
   * 窗口像素尺寸 → vp，再判定断点。
   * 阔折叠展开 / 横屏后宽度增大，自动切换主从布局。
   */
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
            this.selectedId = '';
            this.session.disconnect();
            this.terminalConnected = false;
            this.terminalOutput = '';
            this.terminalTitle = '';
          }
          this.reloadHosts();
          promptAction.showToast({ message: $r('app.string.toast_deleted') });
        });
      }
    });
  }

  private connectHost(host: HostConfig): void {
    this.selectedId = host.id;
    if (this.useSplit) {
      this.terminalTitle = host.displayName();
      this.session.disconnect().then(() => {
        this.session.clearOutput();
        return this.session.connect(host);
      }).then(() => {
        this.terminalOutput = this.session.getOutput();
        this.terminalConnected = this.session.isConnected();
      });
    } else {
      router.pushUrl({
        url: RouteNames.TERMINAL,
        params: {
          'hostId': host.id
        }
      });
    }
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
        .width('36%')
        .height('100%')

      Divider()
        .vertical(true)
        .color($r('app.color.divider'))
        .strokeWidth(1)

      if (this.selectedId.length > 0 || this.terminalConnected) {
        TerminalView({
          output: this.terminalOutput,
          connected: this.terminalConnected,
          title: this.terminalTitle,
          inputText: $terminalInput,
          onSend: (cmd: string) => {
            this.session.send(cmd).then(() => {
              this.terminalOutput = this.session.getOutput();
              this.terminalConnected = this.session.isConnected();
            });
          },
          onDisconnect: () => {
            this.session.disconnect().then(() => {
              this.terminalOutput = this.session.getOutput();
              this.terminalConnected = false;
            });
          }
        })
          .layoutWeight(1)
          .height('100%')
      } else {
        Column() {
          Text($r('app.string.terminal_select_host'))
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.terminal_bg'))
      }
    }
    .width('100%')
    .height('100%')
  }
}
