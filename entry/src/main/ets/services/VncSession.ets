import { HostConfig } from '../models/HostConfig';

export enum VncSessionState {
  Idle = 'idle',
  Connecting = 'connecting',
  Connected = 'connected',
  Disconnected = 'disconnected',
  Error = 'error'
}

/** 假帧缓冲描述，真实 RFB 需 native 解码 */
export interface VncFramebufferInfo {
  width: number;
  height: number;
  /** 占位色，模拟桌面背景 */
  placeholderColor: string;
  label: string;
}

/**
 * VNC 会话抽象。真实 RFB 协议需 NAPI 模块解码像素与输入事件。
 */
export interface IVncSession {
  connect(host: HostConfig): Promise<void>;
  disconnect(): Promise<void>;
  isConnected(): boolean;
  getFramebuffer(): VncFramebufferInfo | null;
  /** 鼠标事件钩子（Mock：记录日志） */
  sendPointer(x: number, y: number, buttons: number): void;
  /** 键盘事件钩子（Mock：记录日志） */
  sendKey(keysym: number, down: boolean): void;
  getStatusMessage(): string;
  onStatus(listener: (msg: string) => void): void;
}

export class MockVncSession implements IVncSession {
  private connected: boolean = false;
  private statusMessage: string = '';
  private listener: ((msg: string) => void) | null = null;
  private framebuffer: VncFramebufferInfo | null = null;
  private currentHost: HostConfig | null = null;
  state: VncSessionState = VncSessionState.Idle;
  /** 简易事件日志，便于 UI 展示 stub 行为 */
  private eventLog: string[] = [];

  onStatus(listener: (msg: string) => void): void {
    this.listener = listener;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getFramebuffer(): VncFramebufferInfo | null {
    return this.framebuffer;
  }

  getStatusMessage(): string {
    return this.statusMessage;
  }

  getEventLog(): string[] {
    return this.eventLog.slice();
  }

  async connect(host: HostConfig): Promise<void> {
    this.state = VncSessionState.Connecting;
    this.currentHost = host;
    this.eventLog = [];
    this.emit(`正在连接 VNC ${host.host}:${host.port} ...`);
    await new Promise<void>((resolve) => setTimeout(resolve, 400));
    this.connected = true;
    this.state = VncSessionState.Connected;
    this.framebuffer = {
      width: 1280,
      height: 720,
      placeholderColor: '#1A2332',
      label: `Mock Desktop · ${host.host}:${host.port}`
    };
    this.emit(`已连接（Mock VNC）。真实 RFB 需 NAPI 模块。`);
  }

  async disconnect(): Promise<void> {
    if (!this.connected && this.state !== VncSessionState.Connecting) {
      return;
    }
    this.emit('VNC 会话已断开');
    this.connected = false;
    this.state = VncSessionState.Disconnected;
    this.framebuffer = null;
    this.currentHost = null;
  }

  sendPointer(x: number, y: number, buttons: number): void {
    if (!this.connected) {
      return;
    }
    const line = `[pointer] x=${Math.floor(x)} y=${Math.floor(y)} buttons=${buttons}`;
    this.eventLog.push(line);
    if (this.eventLog.length > 40) {
      this.eventLog.shift();
    }
    // Mock：仅更新状态摘要，不阻塞 UI
    this.statusMessage = line;
  }

  sendKey(keysym: number, down: boolean): void {
    if (!this.connected) {
      return;
    }
    const line = `[key] keysym=${keysym} ${down ? 'down' : 'up'}`;
    this.eventLog.push(line);
    if (this.eventLog.length > 40) {
      this.eventLog.shift();
    }
    this.statusMessage = line;
  }

  private emit(msg: string): void {
    this.statusMessage = msg;
    if (this.listener) {
      this.listener(msg);
    }
  }
}

export class VncSessionFactory {
  static create(): IVncSession {
    return new MockVncSession();
  }
}
