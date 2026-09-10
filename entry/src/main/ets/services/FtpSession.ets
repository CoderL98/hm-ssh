import { HostConfig } from '../models/HostConfig';
import { AppSettings } from './AppSettings';
import { isNativeModulePresent, getNativeLoadError } from './native/NativeBridge';
import { NativeFtpSession } from './native/NativeFtpSession';
import { FtpEntry, FtpSessionState, IFtpSession } from './types/FtpTypes';

export { FtpEntry, FtpSessionState, IFtpSession } from './types/FtpTypes';

interface MockNode {
  name: string;
  isDirectory: boolean;
  content: string;
  children: Map<string, MockNode>;
  size: number;
  modifiedAt: number;
}

/**
 * Mock FTP：内存文件系统，支持列表、切换目录、上传/下载占位。
 */
export class MockFtpSession implements IFtpSession {
  private connected: boolean = false;
  private cwd: string = '/';
  private root: MockNode = MockFtpSession.createRoot();
  private statusMessage: string = '';
  private listener: ((msg: string) => void) | null = null;
  private currentHost: HostConfig | null = null;
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
    this.currentHost = host;
    this.root = MockFtpSession.createRoot();
    this.emit(`正在连接 FTP ${host.username}@${host.host}:${host.port} ...`);
    await new Promise<void>((resolve) => setTimeout(resolve, 350));
    this.connected = true;
    this.state = FtpSessionState.Connected;
    const start = host.remotePath && host.remotePath.length > 0 ? host.remotePath : '/';
    this.cwd = MockFtpSession.normalizePath(start);
    // 确保起始路径存在
    this.ensureDir(this.cwd);
    this.emit(`已连接（Mock FTP）。cwd=${this.cwd}`);
  }

  async disconnect(): Promise<void> {
    if (!this.connected && this.state !== FtpSessionState.Connecting) {
      return;
    }
    this.emit('FTP 会话已断开');
    this.connected = false;
    this.state = FtpSessionState.Disconnected;
    this.currentHost = null;
    this.cwd = '/';
  }

  async list(): Promise<FtpEntry[]> {
    this.ensureConnected();
    const node = this.resolve(this.cwd);
    if (!node || !node.isDirectory) {
      this.emit(`无法列出目录: ${this.cwd}`);
      return [];
    }
    const entries: FtpEntry[] = [];
    node.children.forEach((child: MockNode, _key: string) => {
      const childPath = MockFtpSession.joinPath(this.cwd, child.name);
      entries.push({
        name: child.name,
        path: childPath,
        isDirectory: child.isDirectory,
        size: child.size,
        modifiedAt: child.modifiedAt
      });
    });
    entries.sort((a: FtpEntry, b: FtpEntry) => {
      if (a.isDirectory !== b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });
    this.emit(`列出 ${this.cwd}：${entries.length} 项`);
    return entries;
  }

  async cd(path: string): Promise<void> {
    this.ensureConnected();
    let target = path;
    if (path === '..') {
      target = MockFtpSession.parentPath(this.cwd);
    } else if (!path.startsWith('/')) {
      target = MockFtpSession.joinPath(this.cwd, path);
    }
    target = MockFtpSession.normalizePath(target);
    const node = this.resolve(target);
    if (!node || !node.isDirectory) {
      this.emit(`目录不存在: ${target}`);
      throw new Error(`目录不存在: ${target}`);
    }
    this.cwd = target;
    this.emit(`进入 ${this.cwd}`);
  }

  async download(remotePath: string): Promise<string> {
    this.ensureConnected();
    const path = remotePath.startsWith('/')
      ? MockFtpSession.normalizePath(remotePath)
      : MockFtpSession.joinPath(this.cwd, remotePath);
    const node = this.resolve(path);
    if (!node || node.isDirectory) {
      this.emit(`下载失败，不是文件: ${path}`);
      throw new Error(`不是文件: ${path}`);
    }
    this.emit(`[mock download] ${path} (${node.size} bytes)`);
    return node.content;
  }

  async upload(remotePath: string, content: string): Promise<void> {
    this.ensureConnected();
    const path = remotePath.startsWith('/')
      ? MockFtpSession.normalizePath(remotePath)
      : MockFtpSession.joinPath(this.cwd, remotePath);
    const parent = MockFtpSession.parentPath(path);
    const name = MockFtpSession.baseName(path);
    this.ensureDir(parent);
    const parentNode = this.resolve(parent);
    if (!parentNode || !parentNode.isDirectory) {
      throw new Error(`父目录不存在: ${parent}`);
    }
    const file: MockNode = {
      name: name,
      isDirectory: false,
      content: content,
      children: new Map(),
      size: content.length,
      modifiedAt: Date.now()
    };
    parentNode.children.set(name, file);
    this.emit(`[mock upload] ${path} (${content.length} bytes)`);
  }

  private ensureConnected(): void {
    if (!this.connected) {
      throw new Error('FTP 未连接');
    }
  }

  private emit(msg: string): void {
    this.statusMessage = msg;
    if (this.listener) {
      this.listener(msg);
    }
  }

  private ensureDir(path: string): void {
    const normalized = MockFtpSession.normalizePath(path);
    if (normalized === '/') {
      return;
    }
    const parts = normalized.split('/').filter((p: string) => p.length > 0);
    let cur = this.root;
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      let next = cur.children.get(part);
      if (!next) {
        next = {
          name: part,
          isDirectory: true,
          content: '',
          children: new Map(),
          size: 0,
          modifiedAt: Date.now()
        };
        cur.children.set(part, next);
      }
      cur = next;
    }
  }

  private resolve(path: string): MockNode | null {
    const normalized = MockFtpSession.normalizePath(path);
    if (normalized === '/') {
      return this.root;
    }
    const parts = normalized.split('/').filter((p: string) => p.length > 0);
    let cur: MockNode = this.root;
    for (let i = 0; i < parts.length; i++) {
      const next = cur.children.get(parts[i]);
      if (!next) {
        return null;
      }
      cur = next;
    }
    return cur;
  }

  private static createRoot(): MockNode {
    const root: MockNode = {
      name: '',
      isDirectory: true,
      content: '',
      children: new Map(),
      size: 0,
      modifiedAt: Date.now()
    };
    const home: MockNode = {
      name: 'home',
      isDirectory: true,
      content: '',
      children: new Map(),
      size: 0,
      modifiedAt: Date.now()
    };
    const user: MockNode = {
      name: 'user',
      isDirectory: true,
      content: '',
      children: new Map(),
      size: 0,
      modifiedAt: Date.now()
    };
    const readme: MockNode = {
      name: 'README.txt',
      isDirectory: false,
      content: 'HarmonyOS FTP Mock FS\n真实 FTP 请接入 NAPI。\n',
      children: new Map(),
      size: 48,
      modifiedAt: Date.now()
    };
    const docs: MockNode = {
      name: 'docs',
      isDirectory: true,
      content: '',
      children: new Map(),
      size: 0,
      modifiedAt: Date.now()
    };
    const note: MockNode = {
      name: 'notes.md',
      isDirectory: false,
      content: '# Notes\nMock file for download/upload demo.\n',
      children: new Map(),
      size: 42,
      modifiedAt: Date.now()
    };
    docs.children.set(note.name, note);
    user.children.set(readme.name, readme);
    user.children.set(docs.name, docs);
    home.children.set(user.name, user);
    root.children.set(home.name, home);
    const tmp: MockNode = {
      name: 'tmp',
      isDirectory: true,
      content: '',
      children: new Map(),
      size: 0,
      modifiedAt: Date.now()
    };
    root.children.set(tmp.name, tmp);
    return root;
  }

  static normalizePath(path: string): string {
    if (!path || path.length === 0) {
      return '/';
    }
    const parts = path.split('/').filter((p: string) => p.length > 0 && p !== '.');
    const stack: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
      } else {
        stack.push(parts[i]);
      }
    }
    return stack.length === 0 ? '/' : `/${stack.join('/')}`;
  }

  static joinPath(base: string, name: string): string {
    if (base === '/') {
      return `/${name}`;
    }
    return `${base}/${name}`;
  }

  static parentPath(path: string): string {
    const normalized = MockFtpSession.normalizePath(path);
    if (normalized === '/') {
      return '/';
    }
    const idx = normalized.lastIndexOf('/');
    if (idx <= 0) {
      return '/';
    }
    return normalized.substring(0, idx);
  }

  static baseName(path: string): string {
    const normalized = MockFtpSession.normalizePath(path);
    if (normalized === '/') {
      return '';
    }
    const idx = normalized.lastIndexOf('/');
    return normalized.substring(idx + 1);
  }
}

export class FtpSessionFactory {
  static create(): IFtpSession {
    try {
      if (AppSettings.getInstance().preferNative() && isNativeModulePresent()) {
        return new NativeFtpSession();
      }
    } catch (_e) {
      // require/.so 缺失或构造失败 → Mock，避免整页崩溃
    }
    return new MockFtpSession();
  }

  static lastNativeHint(): string {
    if (!AppSettings.getInstance().preferNative()) {
      return '已使用 Mock FTP';
    }
    if (!isNativeModulePresent()) {
      return `原生模块不可用：${getNativeLoadError() || '未编译 .so'}`;
    }
    return '将尝试 Native FTP';
  }
}
