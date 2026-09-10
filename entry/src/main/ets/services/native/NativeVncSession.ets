import { HostConfig } from '../../models/HostConfig';
import { IVncSession, VncFramebufferInfo, VncSessionState } from '../types/VncTypes';
import { tryLoadNative, HmsshNativeModule } from './NativeBridge';

export class NativeVncSession implements IVncSession {
  private native: HmsshNativeModule | null = null;
  private sessionId: number = 0;
  private connected: boolean = false;
  private statusMessage: string = '';
  private listener: ((msg: string) => void) | null = null;
  private framebuffer: VncFramebufferInfo | null = null;
  private rgba: ArrayBuffer | null = null;
  private pollTimer: number = -1;
  state: VncSessionState = VncSessionState.Idle;

  onStatus(listener: (msg: string) => void): void {
    this.listener = listener;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getFramebuffer(): VncFramebufferInfo | null {
    return this.framebuffer;
  }

  /** 供 UI 用 PixelMap / ImageBitmap 绘制 */
  getRgbaBuffer(): ArrayBuffer | null {
    return this.rgba;
  }

  getStatusMessage(): string {
    return this.statusMessage;
  }

  async connect(host: HostConfig): Promise<void> {
    this.state = VncSessionState.Connecting;
    this.native = tryLoadNative();
    if (!this.native) {
      this.state = VncSessionState.Error;
      throw new Error('原生模块未加载（需 DevEco 编译 libhmssh_native.so）');
    }
    this.emit(`正在连接（Native VNC） ${host.host}:${host.port} ...`);
    const result = this.native.vncConnect({
      host: host.host,
      port: host.port,
      username: '',
      password: host.password
    });
    if (!result.ok) {
      this.state = VncSessionState.Error;
      throw new Error(result.error || 'vncConnect 失败');
    }
    this.sessionId = result.id;
    this.connected = true;
    this.state = VncSessionState.Connected;
    this.refreshFb();
    this.emit('已连接（Native VNC / RFB Raw）');
    this.startPoll();
  }

  async disconnect(): Promise<void> {
    this.stopPoll();
    if (this.native && this.sessionId > 0) {
      try {
        this.native.vncDisconnect(this.sessionId);
      } catch (_e) {
        // ignore
      }
    }
    this.sessionId = 0;
    this.connected = false;
    this.state = VncSessionState.Disconnected;
    this.framebuffer = null;
    this.rgba = null;
    this.emit('VNC 会话已断开');
  }

  sendPointer(x: number, y: number, buttons: number): void {
    if (!this.connected || !this.native || this.sessionId <= 0) {
      return;
    }
    this.native.vncPointerEvent(this.sessionId, Math.floor(x), Math.floor(y), buttons);
    this.statusMessage = `[pointer] x=${Math.floor(x)} y=${Math.floor(y)} buttons=${buttons}`;
  }

  sendKey(keysym: number, down: boolean): void {
    if (!this.connected || !this.native || this.sessionId <= 0) {
      return;
    }
    this.native.vncKeyEvent(this.sessionId, keysym, down);
    this.statusMessage = `[key] keysym=${keysym} ${down ? 'down' : 'up'}`;
  }

  private startPoll(): void {
    this.stopPoll();
    this.pollTimer = setInterval(() => {
      this.refreshFb();
    }, 100) as number;
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private refreshFb(): void {
    if (!this.native || this.sessionId <= 0) {
      return;
    }
    const fb = this.native.vncFramebuffer(this.sessionId);
    if (fb.error && fb.error.length > 0 && fb.width <= 0) {
      return;
    }
    this.rgba = fb.rgba;
    this.framebuffer = {
      width: fb.width,
      height: fb.height,
      placeholderColor: '#1A2332',
      label: `Native VNC · ${fb.width}×${fb.height}`,
      hasPixelBuffer: true
    };
  }

  private emit(msg: string): void {
    this.statusMessage = msg;
    if (this.listener) {
      this.listener(msg);
    }
  }
}
