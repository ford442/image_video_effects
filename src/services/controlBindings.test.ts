import {
  ControlBindingRegistry,
  ControlEvent,
  LiveActionsHandle,
  loadBindings,
  saveBindings,
  sanitizeBindings,
} from './controlBindings';

describe('ControlBindingRegistry', () => {
  const makeHandle = (): LiveActionsHandle & {
    calls: Array<{ method: string; args: unknown[] }>;
  } => {
    const calls: Array<{ method: string; args: unknown[] }> = [];
    return {
      calls,
      setSlotParam: (slot: number, param: string, value: number) =>
        calls.push({ method: 'setSlotParam', args: [slot, param, value] }),
      randomizeSlot: (slot: number) =>
        calls.push({ method: 'randomizeSlot', args: [slot] }),
      randomizeAll: () => calls.push({ method: 'randomizeAll', args: [] }),
      triggerTransition: () =>
        calls.push({ method: 'triggerTransition', args: [] }),
      toggleAutoTransition: () =>
        calls.push({ method: 'toggleAutoTransition', args: [] }),
    };
  };

  test('synthetic MIDI CC drives setSlotParam', () => {
    const registry = new ControlBindingRegistry();
    const handle = makeHandle();

    registry.addBinding(
      { source: 'midi-cc', id: 'ch1/cc7' },
      { type: 'setSlotParam', slot: 0, param: 'zoomParam1' }
    );

    const event: ControlEvent = { source: 'midi-cc', id: 'ch1/cc7', value: 0.75 };
    const handled = registry.dispatch(event, handle);

    expect(handled).toBe(true);
    expect(handle.calls).toEqual([
      { method: 'setSlotParam', args: [0, 'zoomParam1', 0.75] },
    ]);
  });

  test('synthetic key event drives triggerTransition on press only', () => {
    const registry = new ControlBindingRegistry();
    const handle = makeHandle();

    registry.addBinding(
      { source: 'key', id: ' ' },
      { type: 'triggerTransition' }
    );

    const press: ControlEvent = { source: 'key', id: ' ', value: 1 };
    const release: ControlEvent = { source: 'key', id: ' ', value: 0 };

    expect(registry.dispatch(press, handle)).toBe(true);
    expect(registry.dispatch(release, handle)).toBe(true);
    expect(handle.calls).toEqual([{ method: 'triggerTransition', args: [] }]);
  });

  test('synthetic MIDI note drives randomizeAll on press only', () => {
    const registry = new ControlBindingRegistry();
    const handle = makeHandle();

    registry.addBinding(
      { source: 'midi-note', id: 'ch1/note60' },
      { type: 'randomizeAll' }
    );

    const event: ControlEvent = {
      source: 'midi-note',
      id: 'ch1/note60',
      value: 1,
    };
    expect(registry.dispatch(event, handle)).toBe(true);
    expect(handle.calls).toEqual([{ method: 'randomizeAll', args: [] }]);
  });

  test('unmapped event returns false without calling handle', () => {
    const registry = new ControlBindingRegistry();
    const handle = makeHandle();

    const event: ControlEvent = { source: 'midi-cc', id: 'ch9/cc1', value: 0.5 };
    expect(registry.dispatch(event, handle)).toBe(false);
    expect(handle.calls).toHaveLength(0);
  });

  test('removeBinding deletes a binding', () => {
    const registry = new ControlBindingRegistry();
    const trigger = { source: 'key' as const, id: 'r' };

    registry.addBinding(trigger, { type: 'randomizeSlot', slot: 0 });
    expect(registry.getBindings()).toHaveLength(1);

    expect(registry.removeBinding(trigger)).toBe(true);
    expect(registry.getBindings()).toHaveLength(0);
    expect(registry.removeBinding(trigger)).toBe(false);
  });

  test('serialize/deserialize round-trip preserves bindings', () => {
    const registry = new ControlBindingRegistry();
    registry.addBinding(
      { source: 'midi-cc', id: 'ch1/cc1' },
      { type: 'setSlotParam', slot: 1, param: 'zoomParam2' }
    );
    registry.addBinding(
      { source: 'key', id: 't' },
      { type: 'toggleAutoTransition' }
    );

    const json = registry.serialize();
    const parsed = ControlBindingRegistry.deserialize(json);
    const restored = new ControlBindingRegistry(parsed);

    expect(restored.getBindings()).toEqual(registry.getBindings());
  });

  test('deserialization filters malformed entries', () => {
    const raw = JSON.stringify([
      { trigger: { source: 'key', id: 'x' }, action: { type: 'randomizeAll' } },
      { trigger: { source: 'bad-source', id: 'x' }, action: { type: 'randomizeAll' } },
      { trigger: { source: 'key', id: 'y' }, action: { type: 'setSlotParam' } },
      'not-an-object',
    ]);

    const parsed = ControlBindingRegistry.deserialize(raw);
    expect(parsed).toHaveLength(1);
    expect(parsed[0].trigger).toEqual({ source: 'key', id: 'x' });
    expect(parsed[0].action).toEqual({ type: 'randomizeAll' });
  });
});

describe('localStorage persistence', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  test('saveBindings and loadBindings round-trip', () => {
    const bindings = [
      {
        trigger: { source: 'midi-cc' as const, id: 'ch1/cc7' },
        action: { type: 'setSlotParam' as const, slot: 0, param: 'zoomParam1' },
      },
      {
        trigger: { source: 'key' as const, id: 'n' },
        action: { type: 'randomizeSlot' as const, slot: 2 },
      },
    ];

    saveBindings(bindings);
    const loaded = loadBindings();

    expect(loaded).toEqual(bindings);
  });

  test('loadBindings returns empty array for missing key', () => {
    expect(loadBindings()).toEqual([]);
  });

  test('saveBindings caps entries at MAX_ENTRIES', () => {
    const bindings = Array.from({ length: 150 }, (_, i) => ({
      trigger: { source: 'key' as const, id: `key${i}` },
      action: { type: 'randomizeAll' as const },
    }));

    saveBindings(bindings);
    const loaded = loadBindings();
    expect(loaded).toHaveLength(100);
  });

  test('saveBindings survives QuotaExceededError without throwing', () => {
    const bindings = [
      {
        trigger: { source: 'key' as const, id: 'a' },
        action: { type: 'randomizeAll' as const },
      },
    ];
    const originalSetItem = Storage.prototype.setItem;
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});

    Storage.prototype.setItem = function setItem(key: string, value: string) {
      if (key === 'vj_control_bindings') {
        throw new DOMException('Quota exceeded', 'QuotaExceededError');
      }
      return originalSetItem.call(this, key, value);
    };

    expect(() => saveBindings(bindings)).not.toThrow();
    expect(warnSpy).toHaveBeenCalled();

    Storage.prototype.setItem = originalSetItem;
    warnSpy.mockRestore();
  });

  test('saveBindings retries with fewer entries after quota errors', () => {
    const bindings = Array.from({ length: 4 }, (_, i) => ({
      trigger: { source: 'key' as const, id: `key${i}` },
      action: { type: 'randomizeAll' as const },
    }));
    const originalSetItem = Storage.prototype.setItem;
    let attempts = 0;

    Storage.prototype.setItem = function setItem(key: string, value: string) {
      if (key === 'vj_control_bindings') {
        attempts += 1;
        const parsed = JSON.parse(value);
        if (parsed.length > 2) {
          throw new DOMException('Quota exceeded', 'QuotaExceededError');
        }
      }
      return originalSetItem.call(this, key, value);
    };

    saveBindings(bindings);
    expect(attempts).toBeGreaterThan(1);
    expect(loadBindings()).toHaveLength(2);

    Storage.prototype.setItem = originalSetItem;
  });
});

describe('sanitizeBindings', () => {
  test('filters invalid entries and truncates oversized strings', () => {
    const longId = 'x'.repeat(200);
    const longParam = 'p'.repeat(300);
    const sanitized = sanitizeBindings([
      {
        trigger: { source: 'midi-cc', id: longId },
        action: { type: 'setSlotParam', slot: 99, param: longParam },
      },
      {
        trigger: { source: 'bad-source', id: 'x' },
        action: { type: 'randomizeAll' },
      },
    ]);

    expect(sanitized).toHaveLength(1);
    expect(sanitized[0].trigger.id).toHaveLength(64);
    expect((sanitized[0].action as { param: string }).param).toHaveLength(128);
    expect((sanitized[0].action as { slot: number }).slot).toBe(2);
  });

  test('dedupes bindings by trigger', () => {
    const sanitized = sanitizeBindings([
      {
        trigger: { source: 'key', id: 'a' },
        action: { type: 'randomizeAll' },
      },
      {
        trigger: { source: 'key', id: 'a' },
        action: { type: 'triggerTransition' },
      },
    ]);

    expect(sanitized).toHaveLength(1);
    expect(sanitized[0].action).toEqual({ type: 'triggerTransition' });
  });
});
