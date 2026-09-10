import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  AccentId,
  ThemeMode,
  TerminalSchemeId,
  ThemeTokens
} from '../theme/ThemeTokens';

const STORE_NAME = 'hm_ssh_theme';
const KEY_MODE = 'theme_mode';
const KEY_ACCENT = 'accent_id';
const KEY_TERMINAL = 'terminal_scheme_id';
const THEME_REV_KEY = 'themeRev';

export interface CloudSettingsJson {
  theme_mode?: string;
  accent_id?: string;
  terminal_scheme_id?: string;
}

/**
 * 主题偏好：外观模式、强调色、终端配色。
 * 变更后写入 AppStorage.themeRev，驱动页面刷新令牌。
 */
export class ThemeStore {
  private static instance: ThemeStore | undefined = undefined;
  private pref: preferences.Preferences | null = null;
  private ready: boolean = false;
  private themeMode: ThemeMode = 'system';
  private accentId: AccentId = 'blue';
  private terminalSchemeId: TerminalSchemeId = 'classic_dark';
  private systemDark: boolean = false;
  private revision: number = 0;
  private appContext: common.ApplicationContext | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  static getInstance(): ThemeStore {
    if (!ThemeStore.instance) {
      ThemeStore.instance = new ThemeStore();
    }
    return ThemeStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.uiContext = context;
    this.appContext = context.getApplicationContext();
    this.refreshSystemDark(context);
    if (!this.ready) {
      this.pref = await preferences.getPreferences(context, STORE_NAME);
      this.themeMode = ThemeStore.parseMode(await this.pref.get(KEY_MODE, 'system') as string);
      this.accentId = ThemeStore.parseAccent(await this.pref.get(KEY_ACCENT, 'blue') as string);
      this.terminalSchemeId =
        ThemeStore.parseTerminal(await this.pref.get(KEY_TERMINAL, 'classic_dark') as string);
      this.ready = true;
    }
    this.applyColorMode();
    this.publishTokens();
  }

  /** 系统配置变更（深浅色）时由 EntryAbility 回调 */
  onConfigurationChanged(context: common.UIAbilityContext): void {
    this.uiContext = context;
    this.refreshSystemDark(context);
    if (this.themeMode === 'system') {
      this.applyColorMode();
    }
    this.publishTokens();
  }

  getThemeMode(): ThemeMode {
    return this.themeMode;
  }

  getAccentId(): AccentId {
    return this.accentId;
  }

  getTerminalSchemeId(): TerminalSchemeId {
    return this.terminalSchemeId;
  }

  getRevision(): number {
    return this.revision;
  }

  isEffectiveDark(): boolean {
    if (this.themeMode === 'dark') {
      return true;
    }
    if (this.themeMode === 'light') {
      return false;
    }
    return this.systemDark;
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    this.themeMode = mode;
    await this.persist(KEY_MODE, mode);
    this.applyColorMode();
    this.publishTokens();
  }

  async setAccentId(id: AccentId): Promise<void> {
    this.accentId = id;
    await this.persist(KEY_ACCENT, id);
    this.publishTokens();
  }

  async setTerminalSchemeId(id: TerminalSchemeId): Promise<void> {
    this.terminalSchemeId = id;
    await this.persist(KEY_TERMINAL, id);
    this.publishTokens();
  }


  /** 导出可云同步的设置 JSON */
  exportCloudSettings(): CloudSettingsJson {
    return {
      theme_mode: this.themeMode,
      accent_id: this.accentId,
      terminal_scheme_id: this.terminalSchemeId
    };
  }

  /** 应用云端设置（整包 last-write-wins） */
  async applyCloudSettings(data: CloudSettingsJson): Promise<void> {
    if (data.theme_mode) {
      this.themeMode = ThemeStore.parseMode(data.theme_mode);
      await this.persist(KEY_MODE, this.themeMode);
    }
    if (data.accent_id) {
      this.accentId = ThemeStore.parseAccent(data.accent_id);
      await this.persist(KEY_ACCENT, this.accentId);
    }
    if (data.terminal_scheme_id) {
      this.terminalSchemeId = ThemeStore.parseTerminal(data.terminal_scheme_id);
      await this.persist(KEY_TERMINAL, this.terminalSchemeId);
    }
    this.applyColorMode();
    this.publishTokens();
  }

  private async persist(key: string, value: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  private refreshSystemDark(context: common.Context): void {
    try {
      const conf = context.resourceManager.getConfiguration();
      // colorMode: 0 = light, 1 = dark（HarmonyOS Configuration）
      const mode = conf.colorMode as number;
      this.systemDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK || mode === 1;
    } catch (_e) {
      this.systemDark = false;
    }
  }

  /**
   * 强制浅/深或跟随系统。
   * API 12：ApplicationContext.setColorMode；
   * 同时尽量设置窗口背景色。
   */
  private applyColorMode(): void {
    if (!this.appContext) {
      return;
    }
    try {
      if (this.themeMode === 'light') {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (this.themeMode === 'dark') {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (_e) {
      // 旧运行时忽略
    }
    this.applyWindowBackground();
  }

  private applyWindowBackground(): void {
    if (!this.uiContext) {
      return;
    }
    const dark = this.isEffectiveDark();
    const bg = dark ? '#000000' : '#FFFFFF';
    try {
      window.getLastWindow(this.uiContext).then((win: window.Window) => {
        try {
          win.setWindowBackgroundColor(bg);
        } catch (_e) {
          // ignore
        }
      }).catch(() => {
        // ignore
      });
    } catch (_e) {
      // ignore
    }
  }

  private publishTokens(): void {
    ThemeTokens.setEffectiveDark(this.isEffectiveDark());
    this.revision += 1;
    try {
      AppStorage.setOrCreate(THEME_REV_KEY, this.revision);
    } catch (_e) {
      // AppStorage 可能尚未就绪
    }
  }

  private static parseMode(raw: string): ThemeMode {
    if (raw === 'light' || raw === 'dark' || raw === 'system') {
      return raw;
    }
    return 'system';
  }

  private static parseAccent(raw: string): AccentId {
    const allowed: AccentId[] = ['blue', 'green', 'orange', 'purple', 'pink', 'gray'];
    if (allowed.indexOf(raw as AccentId) >= 0) {
      return raw as AccentId;
    }
    return 'blue';
  }

  private static parseTerminal(raw: string): TerminalSchemeId {
    const allowed: TerminalSchemeId[] = [
      'classic_dark', 'light', 'solarized_dark', 'solarized_light', 'nord', 'monokai'
    ];
    if (allowed.indexOf(raw as TerminalSchemeId) >= 0) {
      return raw as TerminalSchemeId;
    }
    return 'classic_dark';
  }
}
