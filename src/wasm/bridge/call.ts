/**
 * The one place the bridge calls into the Emscripten module. The generated
 * wrappers (_generated.ts, from src/contracts/wasm_exports.json `exports`) go
 * through here; no other bridge file calls ccall (verify:wasm-invariants).
 *
 * An async export's call graph reaches wgpuInstanceWaitAny (the set equals
 * wasm_compile_flags.json jspi.jspiExports). Both builds suspend inside it, so
 * both return a Promise:
 *  - JSPI:     the export itself is wrapped in WebAssembly.promising.
 *  - ASYNCIFY: ccall returns Asyncify.whenDone() once the stack unwinds. A plain
 *              sync ccall would hand back that Promise as if it were the result
 *              (truthy for init, NaN for loadShader) — always pass { async: true }.
 * Async exports run one at a time per module: ASYNCIFY cannot start a second
 * suspension while one is in flight, and under JSPI a second RecreateTextures
 * would interleave with the first. The rest of the bridge never needs to know
 * which artifact is loaded.
 *
 * While one is suspended, a sync export follows its contract `whileSuspended`:
 *  - call:  runs now (plain CPU state; safe mid-suspend)
 *  - queue: runs in call order once the async work queued ahead of it is done
 *           (synchronously as that work settles, before its caller resumes)
 *  - skip:  dropped; returns the fallback (per-frame work the next frame redoes)
 *
 * State is per module, so an init abandoned while still suspended (init.ts
 * reaper) never blocks the module that replaces it.
 */
import type { EmscriptenModule } from './state.js';

export type CcallType = 'number' | 'string';
export type CcallReturn = 'number' | 'string' | null;
export type WhileSuspended = 'call' | 'queue' | 'skip';

interface Task {
  run: () => unknown;
  resolve: (value: unknown) => void;
  reject: (err: unknown) => void;
}

interface Seam {
  /** The async export executing right now (started, not yet settled). */
  active: string | null;
  /** Work waiting for `active` to settle, in call order (queued async exports included). */
  queue: Task[];
  /** A queued task is running: calls it makes run now instead of queueing behind later tasks. */
  draining: boolean;
  /** Sync calls dropped mid-suspend, by export name (diagnostics). */
  skipped: Record<string, number>;
}

const seams = new WeakMap<object, Seam>();

function seamOf(mod: EmscriptenModule): Seam {
  let s = seams.get(mod);
  if (!s) {
    s = { active: null, queue: [], draining: false, skipped: {} };
    seams.set(mod, s);
  }
  return s;
}

/** New work must wait: an async export is in flight, or earlier work is still queued. */
function blocked(s: Seam): boolean {
  return s.active !== null || (s.queue.length > 0 && !s.draining);
}

function enqueue<T>(s: Seam, run: () => T | Promise<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    s.queue.push({ run, resolve: resolve as (value: unknown) => void, reject });
  });
}

/**
 * Run queued work synchronously, in order, until it starts the next async export.
 * Called when an async export settles, before its caller's await resumes, so
 * whatever was queued behind it has landed by the time that caller continues.
 */
function drain(s: Seam): void {
  while (s.active === null) {
    const task = s.queue.shift();
    if (!task) return;
    s.draining = true;
    try {
      task.resolve(task.run());
    } catch (err) {
      task.reject(err);
    } finally {
      s.draining = false;
    }
  }
}

/** True when the module exports `_<ident>` (older artifacts lack the optional ones). */
export function hasExport(mod: EmscriptenModule, ident: string): boolean {
  return typeof (mod as unknown as Record<string, unknown>)[`_${ident}`] === 'function';
}

/** ccall an async export with { async: true }, after any work already queued on the module. */
export function callAsync(
  mod: EmscriptenModule,
  ident: string,
  returnType: CcallReturn,
  argTypes: CcallType[],
  args: unknown[],
): Promise<unknown> {
  const s = seamOf(mod);
  const start = (): Promise<unknown> => {
    s.active = ident;
    let p: Promise<unknown>;
    try {
      p = Promise.resolve(mod.ccall(ident, returnType, argTypes, args, { async: true }));
    } catch (err) {
      p = Promise.reject(err);
    }
    return p.finally(() => {
      s.active = null;
      drain(s);
    });
  };
  return blocked(s) ? enqueue(s, start) : start();
}

/** Apply `whileSuspended` to a sync call: run it now, queue it, or drop it. */
function withPolicy(
  s: Seam,
  ident: string,
  whileSuspended: WhileSuspended,
  fallback: unknown,
  run: () => unknown,
): unknown {
  if (whileSuspended === 'skip' && s.active) {
    s.skipped[ident] = (s.skipped[ident] ?? 0) + 1;
    return fallback;
  }
  if (whileSuspended === 'queue' && blocked(s)) {
    enqueue(s, run).catch((err: unknown) => console.error(`[WASM] queued ${ident} threw:`, err));
    return fallback;
  }
  return run();
}

/** ccall a sync export, applying its whileSuspended policy when async work is in flight. */
export function callSync(
  mod: EmscriptenModule,
  ident: string,
  returnType: CcallReturn,
  argTypes: CcallType[],
  args: unknown[],
  whileSuspended: WhileSuspended,
  fallback: unknown,
): unknown {
  return withPolicy(seamOf(mod), ident, whileSuspended, fallback, () =>
    mod.ccall(ident, returnType, argTypes, args),
  );
}

/**
 * Call `_<ident>` directly instead of through ccall: the optional exports, which
 * the wrapper has already feature-tested with hasExport (ccall asserts on a
 * missing export). Numeric arguments only; a 'string' return is a C string
 * pointer decoded with UTF8ToString. Same whileSuspended policy as callSync.
 */
export function callDirect(
  mod: EmscriptenModule,
  ident: string,
  returnType: CcallReturn,
  args: number[],
  whileSuspended: WhileSuspended,
  fallback: unknown,
): unknown {
  const fn = (mod as unknown as Record<string, unknown>)[`_${ident}`] as (...a: number[]) => unknown;
  return withPolicy(seamOf(mod), ident, whileSuspended, fallback, () => {
    const r = fn(...args);
    if (returnType !== 'string') return r;
    if (typeof mod.UTF8ToString !== 'function') throw new Error(`[WASM] ${ident}: module lacks UTF8ToString`);
    return mod.UTF8ToString(Number(r));
  });
}

/**
 * An async export of this module is suspended right now. Size-dependent
 * textures may be released mid-call (RecreateTextures → TryCreateHistoryTexture),
 * so per-frame work (Render, video/depth upload) must skip until it resolves.
 */
export function isSuspended(mod: EmscriptenModule | null | undefined): boolean {
  return Boolean(mod && seams.get(mod)?.active);
}

/** Async work is running or queued: a queued call made now would wait. */
export function isBusy(mod: EmscriptenModule | null | undefined): boolean {
  const s = mod ? seams.get(mod) : undefined;
  return Boolean(s && blocked(s));
}

/**
 * Run `fn` now when nothing is running or queued (or from inside a queued task),
 * else in order after the queued work. For bridge operations that must not be dropped (an image or depth upload,
 * a capture) but whose exports are `skip` mid-suspend. The caller copies any
 * buffer `fn` reads: it may run after the caller's frame.
 */
export function runWhenIdle<T>(mod: EmscriptenModule, fn: () => T): Promise<T> {
  const s = seamOf(mod);
  if (!blocked(s)) {
    try {
      return Promise.resolve(fn());
    } catch (err) {
      return Promise.reject(err);
    }
  }
  return enqueue(s, fn);
}

/**
 * Forget this module's in-flight async export and reject what is queued behind
 * it. Only for an abandoned init (init.ts reaper): C++'s own getters show
 * Initialize() has left WaitAny, but the ccall promise never settled, so work
 * queued on the seam (shutdownWasmRenderer) would otherwise wait forever.
 */
export function abandonSeam(mod: EmscriptenModule): void {
  const s = seams.get(mod);
  if (!s) return;
  const dropped = s.queue.splice(0);
  s.active = null;
  for (const task of dropped) task.reject(new Error('[WASM] module abandoned before this call ran'));
}

export interface SeamDiagnostics {
  active: string | null;
  queued: number;
  skipped: Record<string, number>;
}

export function getSeamDiagnostics(mod: EmscriptenModule | null | undefined): SeamDiagnostics {
  const s = mod ? seams.get(mod) : undefined;
  return { active: s?.active ?? null, queued: s?.queue.length ?? 0, skipped: { ...(s?.skipped ?? {}) } };
}
