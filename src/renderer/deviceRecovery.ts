/**
 * deviceRecovery.ts
 *
 * Recovery lifecycle for a runtime GPUDevice loss in the TS WebGPU backend
 * (page or render worker). The controller only sequences states; the actual
 * re-init is RendererManager's webgpu → webgpu switch, which releases the dead
 * backend and reruns the boot probe (the only place a device is requested).
 *
 *   idle ──loss──▶ lost ──auto (once)──▶ recovering ──ok──▶ idle
 *                   │                        │
 *                   └─(loss soon after a     └─fail──▶ failed ──retry()──▶ recovering
 *                      recovery: no auto)──────────────▲
 *
 * There is no fallback backend: a failed recovery stays `failed` with the
 * boot-probe diagnostics until the user retries.
 */

import type { DeviceLossInfo } from './Renderer';

export type DeviceRecoveryState = 'idle' | 'lost' | 'recovering' | 'failed';

export interface DeviceRecoveryStatus {
  state: DeviceRecoveryState;
  /** Recovery attempts since the page loaded (auto + manual). */
  attempts: number;
  lastLoss: DeviceLossInfo | null;
  /** Why the last attempt failed (boot-probe lastError when available). */
  lastError: string | null;
  /** Date.now() of the last successful recovery. */
  lastRecoveredAt: number | null;
}

/** A second loss this soon after a recovery waits for the user instead of looping. */
export const AUTO_RECOVERY_COOLDOWN_MS = 30_000;

export interface DeviceRecoveryDeps {
  /** Rebuild the backend on a new device; resolves true when it renders again. */
  recover: () => Promise<boolean>;
  /** Failure detail for the overlay (e.g. window.webgpuProbe.lastError). */
  describeFailure?: () => string | null;
  onStatus?: (status: DeviceRecoveryStatus) => void;
  /** The renderer is blocked: surface the diagnostic overlay. */
  onFailed?: (message: string) => void;
  now?: () => number;
}

export class DeviceRecoveryController {
  private status: DeviceRecoveryStatus = {
    state: 'idle',
    attempts: 0,
    lastLoss: null,
    lastError: null,
    lastRecoveredAt: null,
  };
  private inFlight: Promise<boolean> | null = null;
  private disposed = false;

  constructor(private readonly deps: DeviceRecoveryDeps) {}

  getStatus(): DeviceRecoveryStatus {
    return { ...this.status };
  }

  /** A backend reported a runtime device loss. */
  handleLoss(info: DeviceLossInfo): void {
    if (this.disposed || this.inFlight) return;
    const now = this.deps.now?.() ?? Date.now();
    const recentRecovery =
      this.status.lastRecoveredAt !== null && now - this.status.lastRecoveredAt < AUTO_RECOVERY_COOLDOWN_MS;
    this.update({ state: 'lost', lastLoss: info, lastError: null });
    if (recentRecovery) {
      this.fail(`GPU device lost again (${info.reason}) within ${AUTO_RECOVERY_COOLDOWN_MS / 1000}s of a recovery`);
      return;
    }
    void this.retry();
  }

  /** Single-flight: concurrent callers share one attempt. */
  retry(): Promise<boolean> {
    if (this.disposed) return Promise.resolve(false);
    if (this.inFlight) return this.inFlight;
    this.update({ state: 'recovering', attempts: this.status.attempts + 1, lastError: null });
    const attempt = (async () => {
      let ok = false;
      let error: string | null = null;
      try {
        ok = await this.deps.recover();
      } catch (e) {
        error = e instanceof Error ? e.message : String(e);
      }
      this.inFlight = null;
      if (this.disposed) return false;
      if (ok) {
        this.update({ state: 'idle', lastRecoveredAt: this.deps.now?.() ?? Date.now() });
        return true;
      }
      this.fail(error ?? this.deps.describeFailure?.() ?? 'WebGPU reinitialization failed');
      return false;
    })();
    this.inFlight = attempt;
    return attempt;
  }

  /** Stop reacting to losses. An attempt already running still finishes (see whenSettled). */
  dispose(): void {
    this.disposed = true;
  }

  /** Resolves once no attempt is in flight, so teardown can release what it built. */
  whenSettled(): Promise<void> {
    return this.inFlight ? this.inFlight.then(() => undefined, () => undefined) : Promise.resolve();
  }

  private fail(message: string): void {
    this.update({ state: 'failed', lastError: message });
    this.deps.onFailed?.(message);
  }

  private update(patch: Partial<DeviceRecoveryStatus>): void {
    this.status = { ...this.status, ...patch };
    this.deps.onStatus?.(this.getStatus());
  }
}
