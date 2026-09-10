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
  /** 本地 HUKS 密文 pack（v1:iv:cipher）；内存 plaintext 在 password 字段 */
  passwordLocalEnc?: string;
  privateKeyLocalEnc?: string;
  /** 云端保险柜密文（cv1:...）；仅当「同步加密密钥到云端」开启时上传 */
  passwordEnc?: string;
  privateKeyEnc?: string;
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
  /** 内存中的明文；落盘时经 HUKS 写入 passwordLocalEnc */
  password: string = '';
  /** 内存中的私钥 PEM；落盘时经 HUKS 写入 privateKeyLocalEnc */
  privateKey: string = '';
  passwordLocalEnc: string = '';
  privateKeyLocalEnc: string = '';
  /** 云端保险柜密文（可跨设备）；默认不上云 */
  passwordEnc: string = '';
  privateKeyEnc: string = '';
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

  /** 列表副标题：地址:端口（协议由静默标签展示） */
  subtitle(): string {
    return `${this.host}:${this.port}`;
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

  /**
   * 协议标签色：纯净风静默中性色，不再使用高饱和橙/紫/蓝块。
   * UI 侧优先用 badge_background + badge_text 资源；此方法供兼容旧调用。
   */
  protocolBadgeColor(): string {
    // 与 badge_text / 次要文案同级的中性色
    if (this.protocol === 'ftp') {
      return '#66000000';
    }
    if (this.protocol === 'vnc') {
      return '#66000000';
    }
    return '#66000000';
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
      // 持久化不写明文；明文仅内存
      password: '',
      privateKey: '',
      passwordLocalEnc: this.passwordLocalEnc,
      privateKeyLocalEnc: this.privateKeyLocalEnc,
      passwordEnc: this.passwordEnc,
      privateKeyEnc: this.privateKeyEnc,
      protocol: this.protocol,
      remotePath: this.remotePath,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt
    };
  }

  /**
   * 云同步载荷：始终排除明文 password / privateKey。
   * 若开启云端保险柜，附带 passwordEnc / privateKeyEnc；否则清空这些字段。
   */
  toCloudJson(includeVaultEnc: boolean = false): HostJson {
    const j = this.toJson();
    j.password = '';
    j.privateKey = '';
    j.passwordLocalEnc = '';
    j.privateKeyLocalEnc = '';
    if (!includeVaultEnc) {
      j.passwordEnc = '';
      j.privateKeyEnc = '';
    }
    return j;
  }

  /** 若本条机密为空而 other 有值，则拷贝本地机密到 this */
  absorbLocalSecrets(other: HostConfig | undefined): void {
    if (!other) {
      return;
    }
    if ((!this.password || this.password.length === 0) && other.password) {
      this.password = other.password;
    }
    if ((!this.privateKey || this.privateKey.length === 0) && other.privateKey) {
      this.privateKey = other.privateKey;
    }
    if ((!this.passwordLocalEnc || this.passwordLocalEnc.length === 0) && other.passwordLocalEnc) {
      this.passwordLocalEnc = other.passwordLocalEnc;
    }
    if ((!this.privateKeyLocalEnc || this.privateKeyLocalEnc.length === 0) && other.privateKeyLocalEnc) {
      this.privateKeyLocalEnc = other.privateKeyLocalEnc;
    }
    if ((!this.passwordEnc || this.passwordEnc.length === 0) && other.passwordEnc) {
      this.passwordEnc = other.passwordEnc;
    }
    if ((!this.privateKeyEnc || this.privateKeyEnc.length === 0) && other.privateKeyEnc) {
      this.privateKeyEnc = other.privateKeyEnc;
    }
  }

  static fromJson(json: HostJson): HostConfig {
    const c = new HostConfig();
    c.id = json.id ?? '';
    c.name = json.name ?? '';
    c.host = json.host ?? '';
    c.protocol = HostConfig.normalizeProtocol(json.protocol);
    c.port = json.port ?? HostConfig.defaultPort(c.protocol);
    c.username = json.username ?? '';
    // 兼容旧明文；新数据明文为空，密文在 *Enc / *LocalEnc
    c.password = json.password ?? '';
    c.privateKey = json.privateKey ?? '';
    c.passwordLocalEnc = json.passwordLocalEnc ?? '';
    c.privateKeyLocalEnc = json.privateKeyLocalEnc ?? '';
    c.passwordEnc = json.passwordEnc ?? '';
    c.privateKeyEnc = json.privateKeyEnc ?? '';
    c.remotePath = json.remotePath && json.remotePath.length > 0 ? json.remotePath : '/';
    c.createdAt = json.createdAt ?? 0;
    c.updatedAt = json.updatedAt ?? 0;
    return c;
  }
}
