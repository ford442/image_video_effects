import { afterEach, describe, expect, it, vi } from 'vitest';
import { ControlBindingRegistry } from '../services/controlBindings';
import { connectControlEventsToModulation, externalKey } from './external';
import { modulationStore } from './store';

afterEach(() => modulationStore.reset());

describe('external modulation source', () => {
  it('forwards every dispatched control event, bound or not, until disconnected', () => {
    const seen = vi.fn();
    modulationStore.subscribeExternal(seen);
    const off = connectControlEventsToModulation();
    const registry = new ControlBindingRegistry();
    const handle = { setSlotParam: vi.fn(), randomizeSlot: vi.fn(), randomizeAll: vi.fn(), triggerTransition: vi.fn(), toggleAutoTransition: vi.fn() };
    registry.dispatch({ source: 'midi-cc', id: 'ch1/cc7', value: 0.25 }, handle);
    expect(seen).toHaveBeenCalledWith({ 'midi-cc:ch1/cc7': 0.25 });
    off();
    registry.dispatch({ source: 'key', id: 'KeyA', value: 1 }, handle);
    expect(seen).toHaveBeenCalledTimes(1);
    expect(externalKey({ source: 'key', id: 'KeyA' })).toBe('key:KeyA');
  });
});
