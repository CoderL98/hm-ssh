/**
 * 远程主机配置：支持 SSH / FTP / VNC 协议。
 */
export type HostProtocol = 'ssh' | 'ftp' | 'vnc';

export interface HostJson {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  password: string;
  privateKey: string;
  /** 协议：ssh | ftp | vnc；缺省视为 ssh（兼容旧数据） */
  protocol?: string;
  /** FTP 初始远程路径，可选 */
  remotePath?: string;
  createdAt: number;
  updatedAt: number;
}

export class HostConfig {
  id: string = '';
  name: string = '';
  host: string = '';
  port: number = 22;
  username: string = '';
  /** 明文仅用于里程碑演示；正式版应使用加密存储 */
  password: string = '';
  /** 私钥路径或 PEM 文本占位，后续接入真实 SSH */
  privateKey: string = '';
  protocol: HostProtocol = 'ssh';
  /** FTP 初始目录，默认 / */
  remotePath: string = '/';
  createdAt: number = 0;
  updatedAt: number = 0;

  displayName(): string {
    if (this.name && this.name.trim().length > 0) {
      return this.name.trim();
    }
    if (this.protocol === 'vnc') {
      return `${this.host}:${this.port}`;
    }
    const user = this.username && this.username.trim().length > 0 ? this.username : 'user';
    return `${user}@${this.host}`;
  }

  subtitle(): string {
    return `${this.protocolLabel()} · ${this.host}:${this.port}`;
  }

  protocolLabel(): string {
    if (this.protocol === 'ftp') {
      return 'FTP';
    }
    if (this.protocol === 'vnc') {
      return 'VNC';
    }
    return 'SSH';
  }

  protocolBadgeColor(): string {
    if (this.protocol === 'ftp') {
      return '#E67E22';
    }
    if (this.protocol === 'vnc') {
      return '#8E44AD';
    }
    return '#0A59F7';
  }

  /** 按协议返回推荐默认端口 */
  static defaultPort(protocol: HostProtocol): number {
    if (protocol === 'ftp') {
      return 21;
    }
    if (protocol === 'vnc') {
      return 5900;
    }
    return 22;
  }

  static normalizeProtocol(raw: string | undefined | null): HostProtocol {
    if (raw === 'ftp' || raw === 'vnc' || raw === 'ssh') {
      return raw;
    }
    return 'ssh';
  }

  clone(): HostConfig {
    return HostConfig.fromJson(this.toJson());
  }

  toJson(): HostJson {
    return {
      id: this.id,
      name: this.name,
      host: this.host,
      port: this.port,
      username: this.username,
      password: this.password,
      privateKey: this.privateKey,
      protocol: this.protocol,
      remotePath: this.remotePath,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt
    };
  }

  static fromJson(json: HostJson): HostConfig {
    const c = new HostConfig();
    c.id = json.id ?? '';
    c.name = json.name ?? '';
    c.host = json.host ?? '';
    c.protocol = HostConfig.normalizeProtocol(json.protocol);
    c.port = json.port ?? HostConfig.defaultPort(c.protocol);
    c.username = json.username ?? '';
    c.password = json.password ?? '';
    c.privateKey = json.privateKey ?? '';
    c.remotePath = json.remotePath && json.remotePath.length > 0 ? json.remotePath : '/';
    c.createdAt = json.createdAt ?? 0;
    c.updatedAt = json.updatedAt ?? 0;
    return c;
  }
}
