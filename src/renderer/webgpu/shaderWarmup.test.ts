import { ShaderWarmupHost, ShaderWarmupQueue, WarmupEntry } from './shaderWarmup';

function host(overrides: Partial<ShaderWarmupHost> = {}) {
  const cached = new Set<string>();
  const bound = new Set<string>();
  const evicted: string[] = [];
  const pending = new Map<string, () => void>();
  const loads: string[] = [];
  const h: ShaderWarmupHost = {
    load: (e) => {
      loads.push(e.id);
      return new Promise<boolean>((resolve) => {
        pending.set(e.id, () => {
          cached.add(e.id);
          resolve(true);
        });
      });
    },
    isCached: (id) => cached.has(id),
    boundIds: () => bound,
    evict: (id) => {
      cached.delete(id);
      evicted.push(id);
    },
    ...overrides,
  };
  const finish = async (id: string) => {
    pending.get(id)?.();
    pending.delete(id);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  };
  return { h, cached, bound, evicted, loads, pending, finish };
}

const entries = (...ids: string[]): WarmupEntry[] => ids.map((id) => ({ id, url: `shaders/${id}.wgsl` }));
const sync = (job: () => void) => job();

describe('ShaderWarmupQueue', () => {
  it('compiles at most `concurrency` pipelines at once, in request order', async () => {
    const t = host();
    const q = new ShaderWarmupQueue(t.h, { concurrency: 2, schedule: sync });
    q.request(entries('a', 'b', 'c', 'd'));
    expect(t.loads).toEqual(['a', 'b']);
    await t.finish('a');
    expect(t.loads).toEqual(['a', 'b', 'c']);
    await t.finish('b');
    await t.finish('c');
    await t.finish('d');
    expect(t.loads).toEqual(['a', 'b', 'c', 'd']);
    expect(q.pending).toBe(0);
  });

  it('skips cached, duplicate and refused ids', () => {
    const t = host({ canWarm: (id) => id !== 'graph-root' });
    t.cached.add('a');
    const q = new ShaderWarmupQueue(t.h, { concurrency: 4, schedule: sync });
    q.request(entries('a', 'b', 'b', 'graph-root', 'c'));
    expect(t.loads).toEqual(['b', 'c']);
  });

  it('a new request replaces the queue; scheduled jobs from the old one are dropped', async () => {
    const jobs: Array<() => void> = [];
    const t = host();
    const q = new ShaderWarmupQueue(t.h, { concurrency: 1, schedule: (job) => jobs.push(job) });
    q.request(entries('a', 'b'));
    q.request(entries('x', 'y'));
    jobs.shift()?.(); // stale 'a' job: generation moved on
    expect(t.loads).toEqual([]);
    jobs.shift()?.(); // 'x'
    expect(t.loads).toEqual(['x']);
  });

  it('evicts the least recently warmed unbound pipeline beyond the LRU size', async () => {
    const t = host();
    const q = new ShaderWarmupQueue(t.h, { concurrency: 1, lruSize: 2, schedule: sync });
    t.bound.add('a');
    q.request(entries('a', 'b', 'c'));
    await t.finish('a');
    await t.finish('b');
    await t.finish('c');
    // 'a' is bound to a slot, so the oldest *unbound* warmed id goes.
    expect(t.evicted).toEqual(['b']);
    expect(q.warmedIds()).toEqual(['a', 'c']);
  });

  it('stop() drops queued work and ignores late completions', async () => {
    const t = host();
    const q = new ShaderWarmupQueue(t.h, { concurrency: 1, schedule: sync });
    q.request(entries('a', 'b'));
    q.stop();
    await t.finish('a');
    expect(t.loads).toEqual(['a']);
    expect(q.warmedIds()).toEqual([]);
    q.request(entries('c'));
    expect(t.loads).toEqual(['a']);
  });
});
