import { HostConfig } from '../../models/HostConfig';
import { FtpEntry, FtpSessionState, IFtpSession } from '../types/FtpTypes';
import { tryLoadNative, HmsshNativeModule } from './NativeBridge';

export class NativeFtpSession implements IFtpSession {
  private native: HmsshNativeModule | null = null;
  private sessionId: number = 0;
  private connected: boolean = false;
  private cwd: string = '/';
  private statusMessage: string = '';
  private listener: ((msg: string) => void) | null = null;
  state: FtpSessionState = FtpSessionState.Idle;

  onStatus(listener: (msg: string) => void): void {
    this.listener = listener;
  }

  isConnected(): boolean {
    return this.connected;
  }

  getCwd(): string {
    return this.cwd;
  }

  getStatusMessage(): string {
    return this.statusMessage;
  }

  async connect(host: HostConfig): Promise<void> {
    this.state = FtpSessionState.Connecting;
    this.native = tryLoadNative();
    if (!this.native) {
      this.state = FtpSessionState.Error;
      throw new Error('原生模块未加载（需 DevEco 编译 libhmssh_native.so）');
    }
    this.emit(`正在连接（Native FTP） ${host.username}@${host.host}:${host.port} ...`);
    const result = this.native.ftpConnect({
      host: host.host,
      port: host.port,
      username: host.username,
      password: host.password
    });
    if (!result.ok) {
      this.state = FtpSessionState.Error;
      throw new Error(result.error || 'ftpConnect 失败');
    }
    this.sessionId = result.id;
    this.connected = true;
    this.state = FtpSessionState.Connected;
    const start = host.remotePath && host.remotePath.length > 0 ? host.remotePath : '/';
    if (start !== '/') {
      const err = this.native.ftpCd(this.sessionId, start);
      if (err) {
        this.emit(`CWD ${start} 失败: ${err}，停留在根目录`);
      }
    }
    this.cwd = this.native.ftpCwd(this.sessionId);
    this.emit(`已连接（Native FTP）。cwd=${this.cwd}`);
  }

  async disconnect(): Promise<void> {
    if (this.native && this.sessionId > 0) {
      try {
        this.native.ftpDisconnect(this.sessionId);
      } catch (_e) {
        // ignore
      }
    }
    this.sessionId = 0;
    this.connected = false;
    this.state = FtpSessionState.Disconnected;
    this.cwd = '/';
    this.emit('FTP 会话已断开');
  }

  async list(): Promise<FtpEntry[]> {
    this.ensure();
    const result = this.native!.ftpList(this.sessionId);
    if (result.error && result.error.length > 0) {
      this.emit(result.error);
      throw new Error(result.error);
    }
    this.cwd = this.native!.ftpCwd(this.sessionId);
    const entries: FtpEntry[] = result.entries.map((e) => ({
      name: e.name,
      path: e.path,
      isDirectory: e.isDirectory,
      size: e.size,
      modifiedAt: e.modifiedAt
    }));
    this.emit(`列出 ${this.cwd}：${entries.length} 项`);
    return entries;
  }

  async cd(path: string): Promise<void> {
    this.ensure();
    const err = this.native!.ftpCd(this.sessionId, path);
    if (err && err.length > 0) {
      this.emit(err);
      throw new Error(err);
    }
    this.cwd = this.native!.ftpCwd(this.sessionId);
    this.emit(`进入 ${this.cwd}`);
  }

  async download(remotePath: string): Promise<string> {
    this.ensure();
    // 写入应用缓存路径占位；内容由 native RETR 落盘后读回较复杂，这里返回状态说明
    const local = `/data/storage/el2/base/haps/entry/cache/ftp_dl_${Date.now()}`;
    const err = this.native!.ftpRetr(this.sessionId, remotePath, local);
    if (err && err.length > 0) {
      throw new Error(err);
    }
    this.emit(`[native download] ${remotePath} → ${local}`);
    return `[saved] ${local}`;
  }

  async upload(remotePath: string, content: string): Promise<void> {
    this.ensure();
    // 简化：将 content 先写本地再 STOR（完整文件 IO 需 @kit.CoreFileKit；此处提示路径约定）
    const local = `/data/storage/el2/base/haps/entry/cache/ftp_ul_${Date.now()}`;
    // 无同步写文件 API 时 STOR 可能失败——保留 stub 语义并抛出可读错误由 UI 展示
    const err = this.native!.ftpStor(this.sessionId, remotePath, local);
    if (err && err.length > 0) {
      // 回退：记录意图
      this.emit(`[native upload stub] ${remotePath} (${content.length} bytes) — ${err}`);
      throw new Error(`STOR 需要先将内容写入沙箱文件后再调用；当前: ${err}`);
    }
    this.emit(`[native upload] ${remotePath}`);
  }

  private ensure(): void {
    if (!this.connected || !this.native || this.sessionId <= 0) {
      throw new Error('FTP 未连接');
    }
  }

  private emit(msg: string): void {
    this.statusMessage = msg;
    if (this.listener) {
      this.listener(msg);
    }
  }
}
