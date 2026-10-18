/**
 * One error-scope helper for every GPU call whose failure we want to *see*
 * instead of leaking to `uncapturederror` (#1395).
 *
 * WebGPU reports most validation and out-of-memory failures asynchronously:
 * the call returns an (invalid) object and the error goes to the innermost
 * error scope, or to `uncapturederror` when there is none. A try/catch around
 * the call catches only the rarer synchronous throws.
 */

export interface ErrorScopeResult<T> {
  /** fn's return value; undefined when it threw. */
  value?: T;
  /** Error captured by the scope (validation / out-of-memory / internal), or null. */
  error: GPUError | null;
  /** fn threw / rejected, or the scope could not be popped (device lost). */
  threw: boolean;
  thrown?: unknown;
}

function supportsErrorScopes(device: GPUDevice): boolean {
  return typeof device.pushErrorScope === 'function' && typeof device.popErrorScope === 'function';
}

/**
 * Run `fn` inside `pushErrorScope(filter)` and pop exactly once, even when `fn` throws.
 *
 * The scope covers only `fn`'s **synchronous** part: it is popped right after `fn`
 * returns, before any returned promise is awaited. Holding a scope open across an
 * await would also capture errors from unrelated GPU work (the frame loop) and hide
 * them from `uncapturederror`. Async APIs report through their own promise instead
 * (`createComputePipelineAsync` rejects with a GPUPipelineError), so return that
 * promise and its rejection lands in `threw` / `thrown`.
 *
 * Devices without error scopes (test mocks) report only throws.
 */
export async function withErrorScope<T>(
  device: GPUDevice,
  filter: GPUErrorFilter,
  fn: () => T | Promise<T>,
): Promise<ErrorScopeResult<T>> {
  const scoped = supportsErrorScopes(device);
  const result: ErrorScopeResult<T> = { error: null, threw: false };
  if (scoped) device.pushErrorScope(filter);
  let pending: T | Promise<T> | undefined;
  try {
    pending = fn();
  } catch (e) {
    result.threw = true;
    result.thrown = e;
  }
  // Settle handlers attached now, so a rejected pop is never briefly "unhandled".
  const popped = scoped
    ? device.popErrorScope().then(
        (error) => ({ error, failure: undefined as unknown }),
        (failure: unknown) => ({ error: null, failure: failure ?? new Error('popErrorScope failed') }),
      )
    : null;
  if (!result.threw) {
    try {
      result.value = await pending;
    } catch (e) {
      result.threw = true;
      result.thrown = e;
    }
  }
  if (popped) {
    const { error, failure } = await popped;
    result.error = error;
    if (failure !== undefined && !result.threw) {
      result.threw = true;
      result.thrown = failure;
    }
  }
  return result;
}

export function withValidationScope<T>(
  device: GPUDevice,
  fn: () => T | Promise<T>,
): Promise<ErrorScopeResult<T>> {
  return withErrorScope(device, 'validation', fn);
}

export function withOutOfMemoryScope<T>(
  device: GPUDevice,
  fn: () => T | Promise<T>,
): Promise<ErrorScopeResult<T>> {
  return withErrorScope(device, 'out-of-memory', fn);
}

/** True when the scoped call failed in any way (scope error or throw). */
export function scopeFailed(result: ErrorScopeResult<unknown>): boolean {
  return result.threw || result.error !== null;
}

/** Human-readable failure for logs and diagnostics. */
export function describeScopeFailure(result: ErrorScopeResult<unknown>): string | null {
  if (result.error) return result.error.message;
  if (result.threw) {
    const e = result.thrown;
    return e instanceof Error ? e.message : String(e);
  }
  return null;
}
