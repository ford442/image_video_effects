import type { EmscriptenModule } from './state.js';

/**
 * C exports whose call graph reaches wgpuInstanceWaitAny. Must equal
 * src/contracts/wasm_compile_flags.json `jspi.jspiExports` (verify:wasm-invariants).
 *
 * Both builds suspend inside these calls, so both return a Promise:
 *  - JSPI:     the export itself is wrapped in WebAssembly.promising.
 *  - ASYNCIFY: ccall returns Asyncify.whenDone() once the stack unwinds. A plain
 *              sync ccall would hand back that Promise as if it were the result
 *              (truthy for init, NaN for loadShader) — always pass { async: true }.
 * The rest of the bridge never needs to know which artifact is loaded.
 */
export const SUSPENDING_EXPORTS = [
  'initWasmRenderer',
  'loadShader',
  'reloadShader',
  'resizeCanvas',
  'setColorFormat',
] as const;

export type SuspendingExport = (typeof SUSPENDING_EXPORTS)[number];

let tail: Promise<unknown> = Promise.resolve();
let pending = 0;
let idleWaiters: Array<() => void> = [];

/**
 * ccall a suspending export with { async: true }. Calls are serialized: ASYNCIFY
 * cannot start a second async operation while one is in flight, and under JSPI
 * a second RecreateTextures would interleave with the first.
 */
export function callSuspending(
  module: EmscriptenModule,
  ident: SuspendingExport,
  returnType: string | null,
  argTypes: string[],
  args: unknown[],
): Promise<unknown> {
  pending += 1;
  const result = tail.then(() => module.ccall(ident, returnType, argTypes, args, { async: true }));
  tail = result.catch(() => undefined);
  return result.finally(() => {
    pending -= 1;
    if (pending === 0) {
      const waiters = idleWaiters;
      idleWaiters = [];
      waiters.forEach((w) => w());
    }
  });
}

/**
 * True while a suspending export is running. Size-dependent textures may be
 * released mid-call (RecreateTextures → TryCreateHistoryTexture), so per-frame
 * work (Render, video/depth upload) must skip until it resolves.
 */
export function isSuspended(): boolean {
  return pending > 0;
}

/** Run `fn` now if nothing is suspended, else once the queue drains. */
export function whenIdle(fn: () => void): void {
  if (pending === 0) fn();
  else idleWaiters.push(fn);
}

/** Test-only: reset queue state between cases. */
export function resetSuspendingQueueForTests(): void {
  tail = Promise.resolve();
  pending = 0;
  idleWaiters = [];
}
