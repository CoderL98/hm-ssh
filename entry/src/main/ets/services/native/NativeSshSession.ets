import { HostConfig } from '../../models/HostConfig';
import { ISshSession, SshSessionState } from '../types/SshTypes';
import { tryLoadNative, HmsshNativeModule } from './NativeBridge';

/**
 * 调用 NAPI libhmssh_native 的真实 SSH 会话。
 * 轮询 sshRead 推送到 onOutput；无 .so / libssh2 时 connect 抛错由工厂处理。
 */
export class NativeSshSession implements ISshSession {
  private native: HmsshNativeModule | null = null;
  private sessionId: number = 0;
  private connected: boolean = false;
  private outputBuffer: string = '';
  private listener: ((chunk: string) => void) | null = null;
  private pollTimer: number = -1;
  state: SshSessionState = SshSessionState.Idle;

  onOutput(listener: (chunk: string) => void): void {
    this.listener = listener;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getOutput(): string {
    return this.outputBuffer;
  }

  clearOutput(): void {
    this.outputBuffer = '';
    this.emit('');
  }

  async connect(host: HostConfig): Promise<void> {
    this.state = SshSessionState.Connecting;
    this.native = tryLoadNative();
    if (!this.native) {
      this.state = SshSessionState.Error;
      throw new Error('原生模块未加载（需 DevEco 编译 libhmssh_native.so）');
    }
    this.append(`正在连接（Native SSH） ${host.username}@${host.host}:${host.port} ...\n`);
    const result = this.native.sshConnect({
      host: host.host,
      port: host.port,
      username: host.username,
      password: host.password,
      privateKey: host.privateKey
    });
    if (!result.ok) {
      this.state = SshSessionState.Error;
      throw new Error(result.error || 'sshConnect 失败');
    }
    this.sessionId = result.id;
    this.connected = true;
    this.state = SshSessionState.Connected;
    this.append(`已连接（Native）。\n`);
    this.startPoll();
  }

  async disconnect(): Promise<void> {
    this.stopPoll();
    if (this.native && this.sessionId > 0) {
      try {
        this.native.sshDisconnect(this.sessionId);
      } catch (_e) {
        // ignore
      }
    }
    this.sessionId = 0;
    if (this.connected) {
      this.append('\n[会话已断开]\n');
    }
    this.connected = false;
    this.state = SshSessionState.Disconnected;
  }

  async send(command: string): Promise<void> {
    if (!this.connected || !this.native || this.sessionId <= 0) {
      this.append('\n[未连接]\n');
      return;
    }
    const payload = command.endsWith('\n') ? command : `${command}\n`;
    const err = this.native.sshSend(this.sessionId, payload);
    if (err && err.length > 0) {
      this.append(`\n[send error] ${err}\n`);
    }
  }

  resize(cols: number, rows: number): void {
    if (!this.connected || !this.native || this.sessionId <= 0) {
      return;
    }
    this.native.sshResize(this.sessionId, cols, rows);
  }

  private startPoll(): void {
    this.stopPoll();
    // setInterval 在 ArkTS 可用；约 50ms 轮询
    this.pollTimer = setInterval(() => {
      if (!this.native || this.sessionId <= 0) {
        return;
      }
      const chunk = this.native.sshRead(this.sessionId, 16384);
      if (chunk && chunk.length > 0) {
        this.append(chunk);
      }
    }, 50) as number;
  }

  private stopPoll(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private append(chunk: string): void {
    this.outputBuffer += chunk;
    this.emit(chunk);
  }

  private emit(chunk: string): void {
    if (this.listener) {
      this.listener(chunk);
    }
  }
}
