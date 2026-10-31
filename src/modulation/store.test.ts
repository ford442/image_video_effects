import { afterEach, describe, expect, it, vi } from 'vitest';
import { getModulationRuntime, modulationStore, resetModulationRuntime, Route } from './index';

const r = (over: Partial<Route> = {}): Route => ({
  id: 'a', source: { kind: 'audio', band: 'bass' }, target: { slot: 0, param: 'p1' }, depth: 1, offset: 0, curve: 'linear', ...over,
});

afterEach(() => { modulationStore.reset(); resetModulationRuntime(); });

describe('modulationStore', () => {
  it('resolves ranges, mirrors into the realm runtime and notifies', () => {
    const seen = vi.fn();
    modulationStore.subscribe(seen);
    modulationStore.setRangeResolver(() => ({ min: -2, max: 5 }));
    modulationStore.setRoutes([r(), r({ id: 'o', target: { slot: 0, param: 'opacity' } }), { bogus: true } as unknown as Route]);
    const routes = modulationStore.getSnapshot().routes;
    expect(routes.map((x) => [x.id, x.min, x.max])).toEqual([['a', -2, 5], ['o', 0, 1]]);
    expect(getModulationRuntime().routeCount).toBe(2);
    expect(seen).toHaveBeenLastCalledWith(expect.objectContaining({ bpm: 120 }));
    expect(modulationStore.getRoutes()[0]).toEqual(r());
  });

  it('upserts and removes routes', () => {
    modulationStore.upsertRoute(r());
    modulationStore.upsertRoute(r({ depth: 0.3 }));
    expect(modulationStore.getRoutes()).toHaveLength(1);
    expect(modulationStore.getRoutes()[0]!.depth).toBe(0.3);
    modulationStore.removeRoute('a');
    expect(modulationStore.getRoutes()).toHaveLength(0);
  });

  it('tracks the panel target', () => {
    const seen = vi.fn();
    modulationStore.subscribePanel(seen);
    modulationStore.openPanel({ slot: 2, param: 'p3' });
    expect(seen).toHaveBeenCalledWith({ slot: 2, param: 'p3' }, true);
    modulationStore.closePanel();
    expect(modulationStore.getPanel().open).toBe(false);
  });
});
