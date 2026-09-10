import { HostConfig } from '../models/HostConfig';
import { AppSettings } from './AppSettings';
import { isNativeModulePresent, getNativeLoadError } from './native/NativeBridge';
import { NativeSshSession } from './native/NativeSshSession';
import { ISshSession, SshSessionState } from './types/SshTypes';

export { ISshSession, SshSessionState } from './types/SshTypes';

export class MockSshSession implements ISshSession {
  private connected: boolean = false;
  private outputBuffer: string = '';
  private listener: ((chunk: string) => void) | null = null;
  private currentHost: HostConfig | null = null;
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

  async connect(host: HostConfig): Promise<void> {
    this.state = SshSessionState.Connecting;
    this.currentHost = host;
    this.append(`正在连接 ${host.username}@${host.host}:${host.port} ...\n`);
    // 模拟网络延迟
    await new Promise<void>((resolve) => setTimeout(resolve, 400));
    this.connected = true;
    this.state = SshSessionState.Connected;
    const banner =
      `HarmonyOS SSH Mock Session\n` +
      `Host: ${host.host}\n` +
      `Auth: ${host.privateKey ? 'private-key(placeholder)' : 'password'}\n` +
      `----------------------------------------\n` +
      `欢迎使用鸿蒙SSH（模拟会话）。输入命令将回显；\n` +
      `真实 SSH 请接入 NAPI + libssh2（见 README）。\n` +
      `${host.username}@${host.host}:~$ `;
    this.append(banner);
  }

  async disconnect(): Promise<void> {
    if (!this.connected && this.state !== SshSessionState.Connecting) {
      return;
    }
    this.append('\n[会话已断开]\n');
    this.connected = false;
    this.state = SshSessionState.Disconnected;
    this.currentHost = null;
  }

  async send(command: string): Promise<void> {
    const cmd = command.replace(/\r?\n$/, '');
    if (!this.connected || !this.currentHost) {
      this.append('\n[未连接] 请先连接主机。\n');
      return;
    }
    // 用户输入已在 UI 侧显示；此处输出模拟结果
    this.append(`${cmd}\n`);
    if (cmd === 'exit' || cmd === 'logout') {
      this.append('logout\n');
      await this.disconnect();
      return;
    }
    if (cmd === 'clear') {
      this.outputBuffer = '';
      this.emit('');
      this.append(`${this.currentHost.username}@${this.currentHost.host}:~$ `);
      return;
    }
    if (cmd.trim().length === 0) {
      this.append(`${this.currentHost.username}@${this.currentHost.host}:~$ `);
      return;
    }
    // echo 风格模拟输出
    this.append(`[mock] ${cmd}\n`);
    this.append(`${this.currentHost.username}@${this.currentHost.host}:~$ `);
  }

  clearOutput(): void {
    this.outputBuffer = '';
    this.emit('');
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

/** 工厂：preferNative 且 .so 可用 → Native，否则 Mock */
export class SshSessionFactory {
  static create(): ISshSession {
    try {
      if (AppSettings.getInstance().preferNative() && isNativeModulePresent()) {
        return new NativeSshSession();
      }
    } catch (_e) {
      // require/.so 缺失或构造失败 → Mock，避免整页崩溃
    }
    return new MockSshSession();
  }

  static lastNativeHint(): string {
    if (!AppSettings.getInstance().preferNative()) {
      return '已使用 Mock（设置中未开启原生协议）';
    }
    if (!isNativeModulePresent()) {
      const err = getNativeLoadError();
      return err ? `原生模块不可用：${err}` : '原生模块不可用，已回退 Mock';
    }
    return '将尝试 Native SSH';
  }
}
