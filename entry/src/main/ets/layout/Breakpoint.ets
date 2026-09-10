/**
 * 断点与折叠屏自适应布局辅助。
 * 参考 HarmonyOS 常见窗口宽度断点模式：
 * - sm: 窄屏（手机竖屏）→ Navigation 栈（列表 → 终端）
 * - md / lg: 宽屏（平板、阔折叠展开横屏等）→ 主从分栏
 */
export enum BreakpointType {
  SM = 'sm',
  MD = 'md',
  LG = 'lg'
}

/** 宽度阈值（vp），与官方示例常用区间一致 */
export class BreakpointConstants {
  static readonly SM_MAX: number = 520;
  static readonly MD_MAX: number = 840;
  /** 达到该宽度启用主从并排（主机列表 + 终端） */
  static readonly SPLIT_MIN: number = 600;
}

export class BreakpointHelper {
  static getBreakpoint(widthVp: number): BreakpointType {
    if (widthVp < BreakpointConstants.SM_MAX) {
      return BreakpointType.SM;
    }
    if (widthVp < BreakpointConstants.MD_MAX) {
      return BreakpointType.MD;
    }
    return BreakpointType.LG;
  }

  /** 是否使用宽屏主从布局（阔折叠横屏 / 平板） */
  static useSplitLayout(widthVp: number): boolean {
    return widthVp >= BreakpointConstants.SPLIT_MIN;
  }

  static isNarrow(widthVp: number): boolean {
    return !BreakpointHelper.useSplitLayout(widthVp);
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
}
