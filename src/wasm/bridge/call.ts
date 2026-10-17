/**
 * The one place the bridge calls into the Emscripten module. Generated wrappers
 * (_generated.ts, from src/contracts/wasm_exports.json) go through here; no
 * other bridge file calls ccall.
 *
 * An `async` export can reach wgpuInstanceWaitAny. Under ASYNCIFY that unwinds
 * the wasm stack and ccall returns a Promise, so a plain sync ccall would hand
 * that Promise back as if it were the result: truthy for init, NaN for
 * loadShader. Async exports are therefore always called with { async: true },
 * awaited, and run one at a time per module (ASYNCIFY cannot start a second
 * suspension while one is in flight).
 *
 * While one is suspended, a sync export follows its contract `whileSuspended`:
 *  - call:  runs now (plain CPU state; safe mid-suspend)
 *  - queue: runs in order once the queued async work ahead of it is done
 *  - skip:  dropped; returns the fallback (per-frame work that the next frame redoes)
 */
import type { EmscriptenModule } from './state.js';

export type CcallType = 'number' | 'string';
export type CcallReturn = 'number' | 'string' | null;
export type WhileSuspended = 'call' | 'queue' | 'skip';

interface Seam {
  /** An async export is executing (started, not yet returned). */
  active: string | null;
  /** Items chained on `tail` that have not started yet. */
  queued: number;
  tail: Promise<unknown>;
  /** Sync calls dropped mid-suspend, by export name (diagnostics). */
  skipped: Record<string, number>;
}

const seams = new WeakMap<object, Seam>();

function seamOf(mod: EmscriptenModule): Seam {
  let s = seams.get(mod);
  if (!s) {
    s = { active: null, queued: 0, tail: Promise.resolve(), skipped: {} };
    seams.set(mod, s);
  }
  return s;
}

function logQueuedFailure(ident: string): (err: unknown) => void {
  return (err) => console.error(`[WASM] queued ${ident} threw:`, err);
}

/** Chain `fn` after everything already queued on this module. */
function enqueue<T>(s: Seam, run: () => T | Promise<T>): Promise<T> {
  s.queued += 1;
  const p = s.tail.then(() => {
    s.queued -= 1;
    return run();
  });
  s.tail = p.then(
    () => undefined,
    () => undefined,
  );
  return p;
}

/** True when the module exports `_<ident>` (older artifacts lack the optional ones). */
export function hasExport(mod: EmscriptenModule, ident: string): boolean {
  return typeof (mod as unknown as Record<string, unknown>)[`_${ident}`] === 'function';
}

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
      if (s.active === ident) s.active = null;
    });
  };
  if (!s.active && s.queued === 0) {
    const p = start();
    s.tail = p.then(
      () => undefined,
      () => undefined,
    );
    return p;
  }
  return enqueue(s, start);
}

export function callSync(
  mod: EmscriptenModule,
  ident: string,
  returnType: CcallReturn,
  argTypes: CcallType[],
  args: unknown[],
  whileSuspended: WhileSuspended,
  fallback: unknown,
): unknown {
  const s = seamOf(mod);
  if (whileSuspended === 'skip' && s.active) {
    s.skipped[ident] = (s.skipped[ident] ?? 0) + 1;
    return fallback;
  }
  if (whileSuspended === 'queue' && (s.active || s.queued > 0)) {
    void enqueue(s, () => mod.ccall(ident, returnType, argTypes, args)).catch(logQueuedFailure(ident));
    return fallback;
  }
  return mod.ccall(ident, returnType, argTypes, args);
}

/** An async export of this module is suspended right now. */
export function isSuspended(mod: EmscriptenModule | null | undefined): boolean {
  return Boolean(mod && seams.get(mod)?.active);
}

/** Async work is running or queued: a new queued call would wait. */
export function isBusy(mod: EmscriptenModule | null | undefined): boolean {
  const s = mod ? seams.get(mod) : undefined;
  return Boolean(s && (s.active || s.queued > 0));
}

/**
 * Run `fn` now when nothing is running or queued, else in order after the queued
 * work. For bridge operations that must not be dropped (an image or depth upload,
 * a capture) but whose exports are `skip` mid-suspend. The caller copies any
 * buffer `fn` reads: it may run after the caller's frame.
 */
export function runWhenIdle<T>(mod: EmscriptenModule, fn: () => T): Promise<T> {
  const s = seamOf(mod);
  if (!s.active && s.queued === 0) {
    try {
      return Promise.resolve(fn());
    } catch (err) {
      return Promise.reject(err);
    }
  }
  return enqueue(s, fn);
}

export function getSeamDiagnostics(mod: EmscriptenModule | null | undefined): {
  active: string | null;
  queued: number;
  skipped: Record<string, number>;
} {
  const s = mod ? seams.get(mod) : undefined;
  return { active: s?.active ?? null, queued: s?.queued ?? 0, skipped: { ...(s?.skipped ?? {}) } };
}
