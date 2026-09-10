import { describe, it, expect } from '@ohos/hypium';
import { BreakpointHelper, BreakpointType } from '../../../main/ets/layout/Breakpoint';

export default function listTest() {
  describe('BreakpointHelper', () => {
    it('narrow_phone_portrait', 0, () => {
      expect(BreakpointHelper.useSplitLayout(360)).assertFalse();
      expect(BreakpointHelper.getBreakpoint(360)).assertEqual(BreakpointType.SM);
    });

    it('wide_foldable_landscape', 0, () => {
      expect(BreakpointHelper.useSplitLayout(720)).assertTrue();
      expect(BreakpointHelper.getBreakpoint(720)).assertEqual(BreakpointType.MD);
    });
  });
}
