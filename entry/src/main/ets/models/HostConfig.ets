/**
 * SSH 主机配置模型
 */
export interface HostJson {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  password: string;
  privateKey: string;
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
  createdAt: number = 0;
  updatedAt: number = 0;

  displayName(): string {
    if (this.name && this.name.trim().length > 0) {
      return this.name.trim();
    }
    return `${this.username}@${this.host}`;
  }

  subtitle(): string {
    return `${this.host}:${this.port}`;
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
      createdAt: this.createdAt,
      updatedAt: this.updatedAt
    };
  }

  static fromJson(json: HostJson): HostConfig {
    const c = new HostConfig();
    c.id = json.id ?? '';
    c.name = json.name ?? '';
    c.host = json.host ?? '';
    c.port = json.port ?? 22;
    c.username = json.username ?? '';
    c.password = json.password ?? '';
    c.privateKey = json.privateKey ?? '';
    c.createdAt = json.createdAt ?? 0;
    c.updatedAt = json.updatedAt ?? 0;
    return c;
  }
}
