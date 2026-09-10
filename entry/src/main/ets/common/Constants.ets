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
 * USE_MOCK 为出厂默认；运行时可在「帐号」页切换 Mock / 真实服务器（写入 AuthStore）。
 */
export class CloudConfig {
  /** 出厂默认：Mock 离线帐号；帐号页可改为对接 Rust server */
  static readonly USE_MOCK: boolean = true;
  /** 真机请改为电脑局域网 IP；模拟器视环境使用 10.0.2.2 或本机 */
  static readonly DEFAULT_BASE_URL: string = 'http://127.0.0.1:8080';
  /** 与服务端 routes::auth::MIN_PASSWORD_LEN 对齐 */
  static readonly MIN_PASSWORD_LEN: number = 8;
}
