/**
 * gpuErrorRateLimit.ts — route device `uncapturederror` events into reportError (#1311 WP-A item 5).
 * Validation errors can fire every frame, so each distinct message is reported on its first
 * occurrence and then every Nth. One shared limiter serves the boot-probe and renderer listeners
 * (they may sit on the same handed-off device), so an event seen by both is reported once.
 */
import { reportError, type RendererError } from './ErrorHandling';

export const UNCAPTURED_ERROR_REPORT_EVERY = 100;
const MAX_TRACKED_MESSAGES = 256;

export function createRateLimitedReporter(
  every: number,
  sink: (error: RendererError) => void = (e) => reportError(e),
): (error: RendererError) => void {
  const counts = new Map<string, number>();
  return (error) => {
    if (!counts.has(error.message) && counts.size >= MAX_TRACKED_MESSAGES) counts.clear();
    const n = (counts.get(error.message) ?? 0) + 1;
    counts.set(error.message, n);
    if (n === 1) sink(error);
    else if (n % every === 0) sink({ ...error, message: `${error.message} (×${n})` });
  };
}

const sharedReporter = createRateLimitedReporter(UNCAPTURED_ERROR_REPORT_EVERY);

export function reportUncapturedGpuError(error: GPUError, source: string): void {
  const name = (error as { name?: string }).name ?? 'GPUError';
  sharedReporter({
    type: name === 'GPUValidationError' ? 'shader-compile' : 'device-lost',
    message: `[${source}] ${name}: ${error.message}`,
    recoverable: true,
  });
}
