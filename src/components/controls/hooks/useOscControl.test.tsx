import { renderHook, waitFor } from '@testing-library/react';
import type { OscActionsHandle } from '../../../services/osc/oscRouter';
import { dispatchOscMessage } from '../../../services/osc/oscRouter';
import { useOscControl } from './useOscControl';

/** The bridge the hook starts: it only keeps the handle getter, so the test can fire messages. */
const bridge = vi.hoisted(() => ({ getHandle: null as null | (() => unknown) }));

vi.mock('../../../services/osc/oscFlags', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../services/osc/oscFlags')>()),
  oscFlagFromSearch: () => true,
  loadOscBridge: async () => ({
    OscBridge: class {
      constructor(options: { getHandle: () => unknown }) {
        bridge.getHandle = options.getHandle;
      }
      start() {}
      stop() {}
    },
  }),
}));

function mountHook(onTriggerNextTransition: (options?: { crossfade?: boolean }) => void) {
  renderHook(() =>
    useOscControl({
      modes: ['none', 'none', 'none'],
      availableModes: [],
      setMode: vi.fn(),
      onTriggerNextTransition,
    }),
  );
  return waitFor(() => expect(bridge.getHandle).not.toBeNull()).then(() => bridge.getHandle!() as OscActionsHandle);
}

const osc = (address: string, ...args: Array<string | number>) => ({ address, args });

describe('useOscControl transition cue', () => {
  beforeEach(() => {
    bridge.getHandle = null;
  });

  it('/pixelocity/transition crossfade asks the transition to dissolve', async () => {
    const trigger = vi.fn();
    const handle = await mountHook(trigger);
    dispatchOscMessage(osc('/pixelocity/transition', 'crossfade'), handle);
    expect(trigger).toHaveBeenCalledTimes(1);
    expect(trigger).toHaveBeenCalledWith({ crossfade: true });
  });

  it('a bare /pixelocity/transition keeps the old call: no options, so bindings do not fade', async () => {
    const trigger = vi.fn();
    const handle = await mountHook(trigger);
    dispatchOscMessage(osc('/pixelocity/transition'), handle);
    dispatchOscMessage(osc('/pixelocity/transition', 1), handle);
    expect(trigger).toHaveBeenCalledTimes(2);
    for (const call of trigger.mock.calls) expect(call).toEqual([]);
  });

  it('an unknown cue name is a bare trigger too', async () => {
    const trigger = vi.fn();
    const handle = await mountHook(trigger);
    dispatchOscMessage(osc('/pixelocity/transition', 'wipe'), handle);
    expect(trigger).toHaveBeenCalledWith();
  });
});
