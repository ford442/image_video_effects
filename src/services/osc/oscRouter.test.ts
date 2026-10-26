import { dispatchOscMessage, OscActionsHandle, routeOscMessage, transitionOptionsForCue } from './oscRouter';

const msg = (address: string, ...args: Array<number | string | boolean | null>) => ({ address, args });

describe('routeOscMessage', () => {
  it.each([
    ['x', 'zoomParam1'],
    ['y', 'zoomParam2'],
    ['z', 'zoomParam3'],
    ['w', 'zoomParam4'],
  ])('maps param/%s to %s', (axis, key) => {
    expect(routeOscMessage(msg(`/pixelocity/slot/2/param/${axis}`, 0.42))).toEqual({
      type: 'setSlotParam', slot: 2, param: key, value: 0.42,
    });
  });

  it('clamps values and accepts ints / booleans', () => {
    expect(routeOscMessage(msg('/pixelocity/slot/0/param/x', 3))).toMatchObject({ value: 1 });
    expect(routeOscMessage(msg('/pixelocity/slot/0/param/x', -1))).toMatchObject({ value: 0 });
    expect(routeOscMessage(msg('/pixelocity/slot/0/param/x', true))).toMatchObject({ value: 1 });
  });

  it('bounds slots to the physical cap (0..5)', () => {
    expect(routeOscMessage(msg('/pixelocity/slot/5/param/x', 0.5))).not.toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/6/param/x', 0.5))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/-1/param/x', 0.5))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/1e0/param/x', 0.5))).toBeNull();
  });

  it('routes shader, transition and audio amount', () => {
    expect(routeOscMessage(msg('/pixelocity/slot/1/shader', 'liquid-chrome'))).toEqual({
      type: 'setSlotShader', slot: 1, shaderId: 'liquid-chrome',
    });
    expect(routeOscMessage(msg('/pixelocity/transition'))).toEqual({ type: 'triggerTransition' });
    expect(routeOscMessage(msg('/pixelocity/transition', 'crossfade'))).toEqual({ type: 'triggerTransition', name: 'crossfade' });
    expect(routeOscMessage(msg('/pixelocity/transition', 0))).toBeNull(); // button release
    expect(routeOscMessage(msg('/pixelocity/audio/amount', 0.3))).toEqual({ type: 'setAudioAmount', value: expect.any(Number) });
  });

  it('ignores foreign / malformed addresses', () => {
    expect(routeOscMessage(msg('/other/slot/0/param/x', 1))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/0/param/q', 1))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/0/param/x', 'nope'))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/slot/0/shader', 1))).toBeNull();
    expect(routeOscMessage(msg('/pixelocity/audio/amount'))).toBeNull();
  });
});

describe('dispatchOscMessage', () => {
  it('calls the handle', () => {
    const handle: OscActionsHandle = {
      setSlotParam: vi.fn(),
      triggerTransition: vi.fn(),
      setSlotShader: vi.fn(),
      setAudioAmount: vi.fn(),
    };
    dispatchOscMessage(msg('/pixelocity/slot/3/param/w', 0.5), handle);
    dispatchOscMessage(msg('/pixelocity/slot/0/shader', 'none'), handle);
    dispatchOscMessage(msg('/pixelocity/transition', 1), handle);
    dispatchOscMessage(msg('/pixelocity/audio/amount', 0.25), handle);
    expect(handle.setSlotParam).toHaveBeenCalledWith(3, 'zoomParam4', 0.5);
    expect(handle.setSlotShader).toHaveBeenCalledWith(0, 'none');
    expect(handle.triggerTransition).toHaveBeenCalledTimes(1);
    expect(handle.setAudioAmount).toHaveBeenCalledWith(0.25);
  });
});

describe('transition cues', () => {
  const makeHandle = (): OscActionsHandle => ({
    setSlotParam: vi.fn(),
    triggerTransition: vi.fn(),
    setSlotShader: vi.fn(),
    setAudioAmount: vi.fn(),
  });

  it('passes the crossfade cue through to the transition handle', () => {
    const handle = makeHandle();
    const action = dispatchOscMessage(msg('/pixelocity/transition', 'crossfade'), handle);
    expect(action).toEqual({ type: 'triggerTransition', name: 'crossfade' });
    expect(handle.triggerTransition).toHaveBeenCalledTimes(1);
    expect(handle.triggerTransition).toHaveBeenCalledWith('crossfade');
  });

  it('a nameless trigger calls the handle with no argument, exactly as before', () => {
    const handle = makeHandle();
    dispatchOscMessage(msg('/pixelocity/transition'), handle);
    dispatchOscMessage(msg('/pixelocity/transition', 1), handle);
    expect(handle.triggerTransition).toHaveBeenCalledTimes(2);
    for (const call of (handle.triggerTransition as ReturnType<typeof vi.fn>).mock.calls) {
      expect(call).toEqual([]);
    }
  });

  it('a button release fires nothing', () => {
    const handle = makeHandle();
    expect(dispatchOscMessage(msg('/pixelocity/transition', 0), handle)).toBeNull();
    expect(handle.triggerTransition).not.toHaveBeenCalled();
  });

  it('only the crossfade cue asks for a dissolve', () => {
    expect(transitionOptionsForCue('crossfade')).toEqual({ crossfade: true });
    expect(transitionOptionsForCue(' CrossFade ')).toEqual({ crossfade: true });
    expect(transitionOptionsForCue()).toBeUndefined();
    expect(transitionOptionsForCue('')).toBeUndefined();
    expect(transitionOptionsForCue('wipe')).toBeUndefined();
  });
});
