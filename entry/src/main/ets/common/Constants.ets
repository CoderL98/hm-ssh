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
 * 云端服务配置。
 * USE_MOCK=true 时走本地 Mock（无需 server）；联调真实服务时改为 false 并设置 DEFAULT_BASE_URL。
 */
export class CloudConfig {
  /** 开发默认：Mock 离线帐号；改为 false 对接 Rust server */
  static readonly USE_MOCK: boolean = true;
  /** 真机请改为电脑局域网 IP；模拟器视环境使用 10.0.2.2 或本机 */
  static readonly DEFAULT_BASE_URL: string = 'http://127.0.0.1:8080';
}

