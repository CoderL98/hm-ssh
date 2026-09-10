export class NavParams {
  static readonly HOST_ID: string = 'hostId';
  static readonly EDIT_MODE: string = 'editMode';
}

export class RouteNames {
  static readonly INDEX: string = 'pages/Index';
  static readonly HOST_EDIT: string = 'pages/HostEditPage';
  static readonly TERMINAL: string = 'pages/TerminalPage';
  static readonly FTP_BROWSER: string = 'pages/FtpBrowserPage';
  static readonly VNC_SESSION: string = 'pages/VncSessionPage';
  static readonly SETTINGS: string = 'pages/SettingsPage';
  static readonly ACCOUNT: string = 'pages/AccountPage';
}

/**
 * 云端服务默认配置。
 *
 * - USE_MOCK 出厂为 **false**（真实 HTTP 对接 Rust 后端）；帐号页可切换 Mock 离线演示。
 * - DEFAULT_BASE_URL：模拟器访问宿主机常用 `http://10.0.2.2:8080`；
 *   本机 / 部分预览可用 `http://127.0.0.1:8080`；真机请改为电脑局域网 IP（如 `http://192.168.1.10:8080`）。
 *   运行时可在「帐号」页修改并持久化到 AuthStore。
 */
export class CloudConfig {
  /** 出厂默认：真实 HTTP；帐号页可改为 Mock */
  static readonly USE_MOCK: boolean = false;
  /**
   * 默认基址（模拟器 → 宿主机）。
   * 真机请改为局域网 IP；本机调试可改为 http://127.0.0.1:8080。
   */
  static readonly DEFAULT_BASE_URL: string = 'http://10.0.2.2:8080';
  /** 与服务端 routes::auth::MIN_PASSWORD_LEN 对齐 */
  static readonly MIN_PASSWORD_LEN: number = 8;
}
