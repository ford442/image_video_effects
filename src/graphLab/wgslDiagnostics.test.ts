import type { NagaDiagnostic } from '../utils/nagaWasm';
import { withBundledLibraries } from '../wasm/bridge/wgslLibraries';
import { createDiagnosticScheduler, DiagnoseDeps, DiagnoseResult, diagnoseWgsl, nagaMessage } from './wgslDiagnostics';
import { WGSL_TEMPLATE } from './wgslDraft';

/** A stub naga: an error at the first line of the expanded module containing `BAD`. */
function stubDeps(): DiagnoseDeps & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    resolve: withBundledLibraries(async () => null),
    validate: (wgsl: string): NagaDiagnostic => {
      calls.push(wgsl);
      const lines = wgsl.split('\n');
      const i = lines.findIndex((l) => l.includes('BAD'));
      if (i < 0) return { ok: true };
      const col = (lines[i] ?? '').indexOf('BAD') + 1;
      return {
        ok: false,
        kind: 'parse',
        line: i + 1,
        pos: col,
        message: `error: no definition in scope for identifier: \`BAD\`\n  ┌─ wgsl:${i + 1}:${col}\n  │\n${i + 1} │ ${lines[i]}\n  │ ${' '.repeat(col - 1)}^^^ unknown identifier\n\n`,
      };
    },
  };
}

describe('diagnoseWgsl', () => {
  it('lands a naga error on the user line, past the expanded prelude', async () => {
    const src = WGSL_TEMPLATE.replace('let t = u.config.x', 'let t = BAD');
    const userLine = src.split('\n').findIndex((l) => l.includes('BAD')) + 1;
    const r = await diagnoseWgsl(src, stubDeps());
    expect(r.ok).toBe(false);
    expect(r.diagnostics).toEqual([
      expect.objectContaining({ severity: 'error', source: 'naga', line: userLine, column: 11, length: 3 }),
    ]);
    // The expanded module is ~50 lines longer than the user text: the raw naga line was not used.
    expect(r.expanded!.text.split('\n').findIndex((l) => l.includes('BAD')) + 1).toBeGreaterThan(userLine + 40);
  });

  it('blames an error inside a library on the #include line, never on a prelude line', async () => {
    const deps = stubDeps();
    deps.resolve = withBundledLibraries(async (n) => (n === '_lib.wgsl' ? 'fn f() -> f32 { return BAD; }' : null));
    const r = await diagnoseWgsl('// a\n#include "_prelude.wgsl"\n#include "_lib.wgsl"\nfn main() {}', deps);
    expect(r.diagnostics[0]).toMatchObject({ line: 3, column: 1 });
    expect(r.diagnostics[0]?.message).toMatch(/^in _lib\.wgsl:1 \(included here\)/);
  });

  it('reports @param and include problems without calling naga on a failed expansion', async () => {
    const deps = stubDeps();
    const r = await diagnoseWgsl('// @param x 1 0 0\n#include "_nope.wgsl"', deps);
    expect(r.diagnostics.map((d) => [d.source, d.line])).toEqual([['params', 1], ['include', 2]]);
    expect(deps.calls).toEqual([]);
  });

  it('requires @compute fn main when it can reflect', async () => {
    const r = await diagnoseWgsl('fn other() {}', {
      ...stubDeps(),
      reflect: () => ({ ok: true, valid: true, bindings: [], entryPoints: [] }),
    });
    expect(r.diagnostics[0]).toMatchObject({ source: 'entry-point', severity: 'error' });
  });

  it('keeps naga notes and drops the excerpt', () => {
    expect(nagaMessage({ ok: false, message: "error: Function [0] 'f' is invalid\n  ┌─ wgsl:1:1\n  │\n  = The `return` expression does not match\n" })).toBe(
      "Function [0] 'f' is invalid\nThe `return` expression does not match",
    );
  });
});

describe('createDiagnosticScheduler', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('shows the diagnostic of the last keystroke on the right line within 300 ms', async () => {
    const deps = stubDeps();
    const results: DiagnoseResult[] = [];
    const s = createDiagnosticScheduler({ diagnose: (src) => diagnoseWgsl(src, deps), onResult: (r) => results.push(r) });
    const good = WGSL_TEMPLATE;
    const bad = WGSL_TEMPLATE.replace('let uv =', 'let uv = BAD +');
    const badLine = bad.split('\n').findIndex((l) => l.includes('BAD')) + 1;

    // Typing: every keystroke within the debounce re-arms it; nothing runs yet.
    for (let i = 0; i < 5; i++) {
      s.schedule(i % 2 ? bad : good);
      await vi.advanceTimersByTimeAsync(40);
    }
    s.schedule(bad); // last keystroke at t = 0
    expect(deps.calls).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(149);
    expect(results).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(151); // t = 300 ms
    expect(deps.calls).toHaveLength(1);
    expect(results).toHaveLength(1);
    expect(results[0]?.source).toBe(bad);
    expect(results[0]?.diagnostics[0]).toMatchObject({ line: badLine, severity: 'error' });
    s.dispose();
  });

  it('drops a result that finishes after a newer edit', async () => {
    let release: (() => void) | null = null;
    const results: string[] = [];
    const s = createDiagnosticScheduler({
      diagnose: async (src) => {
        if (src === 'slow') await new Promise<void>((r) => (release = r));
        return { source: src, ok: true, diagnostics: [], expanded: null, header: { params: [], problems: [] } };
      },
      onResult: (r) => results.push(r.source),
    });
    s.schedule('slow');
    await vi.advanceTimersByTimeAsync(150);
    s.schedule('fast');
    await vi.advanceTimersByTimeAsync(150);
    (release as (() => void) | null)?.();
    await vi.advanceTimersByTimeAsync(0);
    expect(results).toEqual(['fast']);
  });

  it('reports a naga load failure through onError', async () => {
    const onError = vi.fn();
    const s = createDiagnosticScheduler({ diagnose: () => Promise.reject(new Error('404')), onResult: vi.fn(), onError });
    s.schedule('x');
    await vi.advanceTimersByTimeAsync(150);
    expect(onError).toHaveBeenCalledWith(expect.objectContaining({ message: '404' }));
  });
});
