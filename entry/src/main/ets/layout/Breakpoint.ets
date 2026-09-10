/**
 * 断点与折叠屏自适应布局辅助。
 * 参考 HarmonyOS 常见窗口宽度断点模式：
 * - sm: 窄屏（手机竖屏）→ Navigation 栈（列表 → 会话页）
 * - md / lg: 宽屏（平板、阔折叠展开横屏等）→ 主从分栏
 * - xl: 超宽（PC / 大平板）→ 列表略加宽
 */
export enum BreakpointType {
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl'
}

/** 宽度阈值（vp），与官方示例常用区间一致 */
export class BreakpointConstants {
  static readonly SM_MAX: number = 520;
  static readonly MD_MAX: number = 840;
  static readonly LG_MAX: number = 1000;
  /** 达到该宽度启用主从并排（主机列表 + 会话面板） */
  static readonly SPLIT_MIN: number = 600;
  /** 超宽时略加宽左侧列表 */
  static readonly WIDE_LIST_MIN: number = 840;
}

export class BreakpointHelper {
  static getBreakpoint(widthVp: number): BreakpointType {
    if (widthVp < BreakpointConstants.SM_MAX) {
      return BreakpointType.SM;
    }
    if (widthVp < BreakpointConstants.MD_MAX) {
      return BreakpointType.MD;
    }
    if (widthVp < BreakpointConstants.LG_MAX) {
      return BreakpointType.LG;
    }
    return BreakpointType.XL;
  }

  /** 是否使用宽屏主从布局（阔折叠横屏 / 平板） */
  static useSplitLayout(widthVp: number): boolean {
    return widthVp >= BreakpointConstants.SPLIT_MIN;
  }

  static isNarrow(widthVp: number): boolean {
    return !BreakpointHelper.useSplitLayout(widthVp);
  }

  /**
   * 左侧主机列表宽度比例（百分比字符串，便于 Row 子项 .width）。
   * md: ~34%，lg(~840+): ~36%，xl(>1000): ~38%
   */
  static listPanePercent(widthVp: number): string {
    if (widthVp >= 1000) {
      return '38%';
    }
    if (widthVp >= BreakpointConstants.WIDE_LIST_MIN) {
      return '36%';
    }
    return '34%';
  }
}

/** 窗口尺寸快照 */
export class WindowSizeState {
  widthVp: number = 360;
  heightVp: number = 780;

  update(widthVp: number, heightVp: number): void {
    this.widthVp = widthVp;
    this.heightVp = heightVp;
  }

  breakpoint(): BreakpointType {
    return BreakpointHelper.getBreakpoint(this.widthVp);
  }

  isSplit(): boolean {
    return BreakpointHelper.useSplitLayout(this.widthVp);
  }

  isLandscape(): boolean {
    return this.widthVp > this.heightVp;
  }

  listPanePercent(): string {
    return BreakpointHelper.listPanePercent(this.widthVp);
  }
}
