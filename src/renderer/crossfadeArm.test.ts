import { CROSSFADE_ARM_WINDOW_MS, CrossfadeArm, slotIdentityChanged } from './crossfadeArm';

describe('slotIdentityChanged', () => {
  const on = { shaderId: 'a', enabled: true, mode: 'chained' as const };

  it('a new shader id, a slot switched on or off, and a mode flip are changes', () => {
    expect(slotIdentityChanged(on, { shaderId: 'b', enabled: true })).toBe(true);
    expect(slotIdentityChanged(null, { shaderId: 'a', enabled: true })).toBe(true);
    expect(slotIdentityChanged(on, { shaderId: null, enabled: false })).toBe(true);
    expect(slotIdentityChanged(on, { shaderId: 'a', enabled: true, mode: 'parallel' })).toBe(true);
    expect(slotIdentityChanged({ ...on, enabled: false }, { shaderId: 'a', enabled: true })).toBe(true);
  });

  it('re-binding the same shader, or clearing an empty slot, is not', () => {
    expect(slotIdentityChanged(on, { shaderId: 'a', enabled: true })).toBe(false);
    expect(slotIdentityChanged(on, { shaderId: 'a', enabled: true, mode: 'chained' })).toBe(false);
    expect(slotIdentityChanged(null, { shaderId: null, enabled: false })).toBe(false);
    expect(slotIdentityChanged({ shaderId: 'a', enabled: false, mode: 'chained' }, { shaderId: null, enabled: false })).toBe(false);
  });
});

describe('CrossfadeArm', () => {
  it('fires once with the armed duration', () => {
    const arm = new CrossfadeArm();
    expect(arm.arm(2000, 0)).toBe(true);
    expect(arm.isArmed).toBe(true);
    expect(arm.take(10)).toBe(2000);
    expect(arm.take(11)).toBeNull();
    expect(arm.isArmed).toBe(false);
  });

  it('a duration of 0 (or junk) is a hard cut: it never arms and disarms what was armed', () => {
    const arm = new CrossfadeArm();
    arm.arm(2000, 0);
    expect(arm.arm(0, 1)).toBe(false);
    expect(arm.isArmed).toBe(false);
    expect(arm.arm(Number.NaN, 1)).toBe(false);
    expect(arm.arm(-5, 1)).toBe(false);
    expect(arm.take(2)).toBeNull();
  });

  it('expires when the stack never lands', () => {
    const arm = new CrossfadeArm();
    arm.arm(2000, 100);
    expect(arm.take(100 + CROSSFADE_ARM_WINDOW_MS + 1)).toBeNull();
    expect(arm.isArmed).toBe(false);
  });

  it('arming again replaces the cue instead of queueing', () => {
    const arm = new CrossfadeArm();
    arm.arm(1000, 0);
    arm.arm(3000, 5);
    expect(arm.take(6)).toBe(3000);
    expect(arm.take(7)).toBeNull();
  });
});
