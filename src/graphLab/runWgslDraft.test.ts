import { isWgslRuntimeId, WgslDraftRunner, WgslRunnerHost, wgslRuntimeIds } from './runDraft';

/** A renderer that compiles anything without "BROKEN", binds per slot and records calls. */
function fakeHost(initial: string | null = 'liquid') {
  const slots = new Map<number, string>([[0, initial ?? '']]);
  const compiled = new Map<string, string>();
  const sources = new Map<string, string>();
  const gates: Array<() => void> = [];
  let hold = false;
  const host: WgslRunnerHost & { compiled: typeof compiled; slots: typeof slots; params: number[][]; holdNext(): void; release(): void } = {
    compiled,
    slots,
    params: [],
    holdNext: () => void (hold = true),
    release: () => gates.splice(0).forEach((g) => g()),
    loadShader: vi.fn(async (id: string, url: string) => {
      const wgsl = sources.get(url) ?? '';
      if (hold) {
        hold = false;
        await new Promise<void>((r) => gates.push(r));
      }
      if (wgsl.includes('BROKEN')) return false;
      compiled.set(id, wgsl);
      return true;
    }),
    setSlotShader: vi.fn((slot: number, id: string) => void slots.set(slot, id)),
    getSlotState: vi.fn((slot: number) => ({ shaderId: slots.get(slot) ?? '' }) as ReturnType<WgslRunnerHost['getSlotState']>),
    setSlotParams: vi.fn((_slot: number, ...p: number[]) => void host.params.push(p)),
  };
  let n = 0;
  const makeUrl = (wgsl: string) => {
    const url = `blob:test/${n++}`;
    sources.set(url, wgsl);
    return { url, release: () => sources.delete(url) };
  };
  return { host, makeUrl };
}

describe('WgslDraftRunner', () => {
  it('binds only after a successful compile, alternating the two runtime ids', async () => {
    const { host, makeUrl } = fakeHost();
    const r = new WgslDraftRunner(host, 0, 'liquid', makeUrl);
    const [a, b] = wgslRuntimeIds(0);
    expect(await r.submit('v1')).toEqual({ ok: true, shaderId: a });
    expect(host.slots.get(0)).toBe(a);
    expect(await r.submit('v2')).toEqual({ ok: true, shaderId: b });
    expect(await r.submit('v3')).toEqual({ ok: true, shaderId: a });
    expect(host.compiled.get(a)).toBe('v3');
    expect(isWgslRuntimeId(a) && isWgslRuntimeId(b) && !isWgslRuntimeId('liquid')).toBe(true);
  });

  it('a failed compile keeps the last good pipeline bound (never a black frame)', async () => {
    const { host, makeUrl } = fakeHost();
    const r = new WgslDraftRunner(host, 0, 'liquid', makeUrl);
    const first = await r.submit('good');
    expect(first.ok).toBe(true);
    const bound = host.slots.get(0);
    const res = await r.submit('BROKEN');
    expect(res).toMatchObject({ ok: false, reason: 'compile', message: expect.stringMatching(/last good one keeps running/) });
    expect(host.slots.get(0)).toBe(bound);
    expect(host.compiled.get(bound!)).toBe('good');
    expect(r.isBound()).toBe(true);
  });

  it('a first compile that fails leaves the slot untouched', async () => {
    const { host, makeUrl } = fakeHost('liquid');
    const r = new WgslDraftRunner(host, 0, 'liquid', makeUrl);
    expect((await r.submit('BROKEN')).ok).toBe(false);
    expect(host.setSlotShader).not.toHaveBeenCalled();
    expect(host.slots.get(0)).toBe('liquid');
  });

  it('only the latest of queued texts is compiled', async () => {
    const { host, makeUrl } = fakeHost();
    const r = new WgslDraftRunner(host, 0, null, makeUrl);
    host.holdNext();
    const p1 = r.submit('one');
    await vi.waitFor(() => expect(host.loadShader).toHaveBeenCalledTimes(1));
    // Typed while "one" compiles: "two" is never compiled, "three" is.
    const p2 = r.submit('two');
    const p3 = r.submit('three');
    host.release();
    const results = await Promise.all([p1, p2, p3]);
    expect(results.map((x) => (x.ok ? 'bound' : x.reason))).toEqual(['bound', 'superseded', 'bound']);
    expect(host.loadShader).toHaveBeenCalledTimes(2);
    expect(host.compiled.get(host.slots.get(0)!)).toBe('three');
  });

  it('stop puts the previous shader back unless the slot was taken', async () => {
    const { host, makeUrl } = fakeHost('liquid');
    const r = new WgslDraftRunner(host, 0, 'liquid', makeUrl);
    await r.submit('v1');
    r.setParams([1, 2, 3, 4]);
    expect(host.params).toEqual([[1, 2, 3, 4]]);
    r.stop();
    expect(host.slots.get(0)).toBe('liquid');

    const r2 = new WgslDraftRunner(host, 0, 'liquid', makeUrl);
    await r2.submit('v1');
    host.slots.set(0, 'someone-else');
    expect(r2.isBound()).toBe(false);
    r2.stop();
    expect(host.slots.get(0)).toBe('someone-else');
    expect(await r2.submit('v2')).toMatchObject({ ok: false, reason: 'stopped' });
  });

  it('releases the blob URL after the compile', async () => {
    const { host } = fakeHost();
    const release = vi.fn();
    const r = new WgslDraftRunner(host, 0, null, () => ({ url: 'blob:x', release }));
    await r.submit('v');
    expect(release).toHaveBeenCalledTimes(1);
  });
});
