/**
 * 主题色板与对比度工具。
 * 强调色 / 终端配色均保证可读对比；禁止 fg≈bg。
 */

export type ThemeMode = 'system' | 'light' | 'dark';
export type AccentId = 'blue' | 'green' | 'orange' | 'purple' | 'pink' | 'gray';
export type TerminalSchemeId =
  | 'classic_dark'
  | 'light'
  | 'solarized_dark'
  | 'solarized_light'
  | 'nord'
  | 'monokai';

export interface AccentPreset {
  id: AccentId;
  label: string;
  color: string;
}

export interface TerminalScheme {
  id: TerminalSchemeId;
  label: string;
  bg: string;
  fg: string;
  cursor: string;
}

/** WCAG 相对亮度；输入 #RRGGBB 或 #AARRGGBB / #RGB */
export function relativeLuminance(hex: string): number {
  const rgb = parseRgb(hex);
  if (!rgb) {
    return 0;
  }
  const lin = (c: number): number => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * lin(rgb.r) + 0.7152 * lin(rgb.g) + 0.0722 * lin(rgb.b);
}

export function contrastRatio(a: string, b: string): number {
  const l1 = relativeLuminance(a);
  const l2 = relativeLuminance(b);
  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/** 强调色上的前景：按亮度自动黑/白，保证按钮文字可读 */
export function onAccentForeground(accentHex: string): string {
  return relativeLuminance(accentHex) > 0.55 ? '#000000' : '#FFFFFF';
}

/**
 * 校验并钳制终端配色：fg 与 bg 对比度至少 4.5；
 * 过低则回退到 Classic Dark，绝不允许同色。
 */
export function ensureTerminalContrast(bg: string, fg: string): TerminalSchemePair {
  if (normalizeHex(bg) === normalizeHex(fg)) {
    return { bg: '#1E1E1E', fg: '#D4D4D4', clamped: true };
  }
  if (contrastRatio(bg, fg) < 4.5) {
    return { bg: '#1E1E1E', fg: '#D4D4D4', clamped: true };
  }
  return { bg: bg, fg: fg, clamped: false };
}

export interface TerminalSchemePair {
  bg: string;
  fg: string;
  clamped: boolean;
}

interface Rgb {
  r: number;
  g: number;
  b: number;
}

function parseRgb(hex: string): Rgb | null {
  let h = hex.trim();
  if (h.startsWith('#')) {
    h = h.substring(1);
  }
  if (h.length === 8) {
    // AARRGGBB → 取 RGB
    h = h.substring(2);
  }
  if (h.length === 3) {
    h = `${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}`;
  }
  if (h.length !== 6) {
    return null;
  }
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  if (isNaN(r) || isNaN(g) || isNaN(b)) {
    return null;
  }
  return { r: r, g: g, b: b };
}

function hex2(n: number): string {
  const s = n.toString(16).toUpperCase();
  return s.length >= 2 ? s : `0${s}`;
}

function normalizeHex(hex: string): string {
  const rgb = parseRgb(hex);
  if (!rgb) {
    return hex.toUpperCase();
  }
  return `#${hex2(rgb.r)}${hex2(rgb.g)}${hex2(rgb.b)}`;
}

/** 给 #RRGGBB 加 Alpha，输出 #AARRGGBB */
export function withAlpha(hex: string, alpha: number): string {
  const rgb = parseRgb(hex);
  if (!rgb) {
    return hex;
  }
  const a = Math.max(0, Math.min(255, Math.round(alpha * 255)));
  return `#${hex2(a)}${hex2(rgb.r)}${hex2(rgb.g)}${hex2(rgb.b)}`;
}

export const ACCENT_PRESETS: AccentPreset[] = [
  { id: 'blue', label: '系统蓝', color: '#0A59F7' },
  { id: 'green', label: '绿', color: '#00A870' },
  { id: 'orange', label: '橙', color: '#E6780F' },
  { id: 'purple', label: '紫', color: '#8A2BE2' },
  { id: 'pink', label: '粉', color: '#E91E8C' },
  { id: 'gray', label: '灰/中性', color: '#6B7280' }
];

export const TERMINAL_SCHEMES: TerminalScheme[] = [
  { id: 'classic_dark', label: '经典深色', bg: '#1E1E1E', fg: '#D4D4D4', cursor: '#AEAFAD' },
  { id: 'light', label: '浅色', bg: '#FAFAFA', fg: '#1E1E1E', cursor: '#333333' },
  { id: 'solarized_dark', label: 'Solarized Dark', bg: '#002B36', fg: '#839496', cursor: '#93A1A1' },
  { id: 'solarized_light', label: 'Solarized Light', bg: '#FDF6E3', fg: '#657B83', cursor: '#586E75' },
  { id: 'nord', label: 'Nord', bg: '#2E3440', fg: '#D8DEE9', cursor: '#88C0D0' },
  { id: 'monokai', label: 'Monokai', bg: '#272822', fg: '#F8F8F2', cursor: '#F92672' }
];

/** 浅色 / 深色表面色板（纯净风） */
export class SurfacePalette {
  pageBackground: string = '#F1F3F5';
  cardBackground: string = '#FFFFFF';
  textPrimary: string = '#182431';
  textSecondary: string = '#99000000';
  divider: string = '#33000000';
  badgeBackground: string = '#F1F3F5';
  badgeText: string = '#99000000';
  chevron: string = '#99000000';
  controlSecondary: string = '#F1F3F5';
  emptyIcon: string = '#CCCCCC';
  windowBackground: string = '#FFFFFF';

  static light(): SurfacePalette {
    return new SurfacePalette();
  }

  static dark(): SurfacePalette {
    const p = new SurfacePalette();
    p.pageBackground = '#000000';
    p.cardBackground = '#1C1C1E';
    p.textPrimary = '#FFFFFF';
    p.textSecondary = '#99FFFFFF';
    p.divider = '#33FFFFFF';
    p.badgeBackground = '#2C2C2E';
    p.badgeText = '#99FFFFFF';
    p.chevron = '#66FFFFFF';
    p.controlSecondary = '#2C2C2E';
    p.emptyIcon = '#666666';
    p.windowBackground = '#000000';
    return p;
  }
}

/**
 * 根据 ThemeStore 状态解析当前 UI 令牌。
 * 页面通过 @StorageLink('themeRev') 订阅变更后调用此类方法。
 */
export class ThemeTokens {
  private static darkOverride: boolean | null = null;

  /** 由 ThemeStore 在解析系统/手动模式后写入 */
  static setEffectiveDark(isDark: boolean): void {
    ThemeTokens.darkOverride = isDark;
  }

  static isDark(): boolean {
    return ThemeTokens.darkOverride === true;
  }

  static surface(): SurfacePalette {
    return ThemeTokens.isDark() ? SurfacePalette.dark() : SurfacePalette.light();
  }

  static accentColor(accentId: AccentId): string {
    const found = ACCENT_PRESETS.find((a: AccentPreset) => a.id === accentId);
    return found ? found.color : '#0A59F7';
  }

  static onAccent(accentId: AccentId): string {
    return onAccentForeground(ThemeTokens.accentColor(accentId));
  }

  /** 选中行浅色 tint（强调色低透明） */
  static rowSelected(accentId: AccentId): string {
    const c = ThemeTokens.accentColor(accentId);
    return ThemeTokens.isDark() ? withAlpha(c, 0.22) : withAlpha(c, 0.10);
  }

  /** 选中 chip / 焦点底 */
  static accentSoft(accentId: AccentId): string {
    const c = ThemeTokens.accentColor(accentId);
    return ThemeTokens.isDark() ? withAlpha(c, 0.28) : withAlpha(c, 0.10);
  }

  static terminalScheme(id: TerminalSchemeId): TerminalScheme {
    const found = TERMINAL_SCHEMES.find((s: TerminalScheme) => s.id === id);
    const base = found ? found : TERMINAL_SCHEMES[0];
    const safe = ensureTerminalContrast(base.bg, base.fg);
    return {
      id: base.id,
      label: base.label,
      bg: safe.bg,
      fg: safe.fg,
      cursor: base.cursor
    };
  }

  static accentLabel(id: AccentId): string {
    const found = ACCENT_PRESETS.find((a: AccentPreset) => a.id === id);
    return found ? found.label : id;
  }

  static schemeLabel(id: TerminalSchemeId): string {
    const found = TERMINAL_SCHEMES.find((s: TerminalScheme) => s.id === id);
    return found ? found.label : id;
  }

  static modeLabel(mode: ThemeMode): string {
    if (mode === 'light') {
      return '浅色';
    }
    if (mode === 'dark') {
      return '深色';
    }
    return '跟随系统';
  }
}
