/**
 * deviceRegistry.ts — the one owner record for the renderer's GPUDevice (#1395).
 *
 * The TS WebGPU backend that actually renders publishes here: the page
 * `WebGPURenderer` publishes the device it ended up with after setup (after
 * any OOM retry, never the boot-probe handoff it may have destroyed), and the
 * render-worker proxy publishes `{ device: null, thread: 'worker' }` because
 * the device lives in the worker. Both clear on device loss, worker death and
 * teardown. Every publish and clear bumps `generation`, so a consumer that
 * cached something device-bound (a compiler, a model backend choice) can tell
 * it is stale.
 *
 * Consumers (ShaderScanner, ShaderValidator via shaderCompileService, depth
 * estimation, RendererManager.getDevice) read or subscribe — they never
 * requestAdapter/requestDevice (deviceOwnership.test.ts).
 */

export type RendererDeviceThread = 'main' | 'worker';

export interface RendererDeviceEntry {
  /** Bumped by every publish and clear. */
  generation: number;
  /** The live device on this thread; null when none, or when it lives in the render worker. */
  device: GPUDevice | null;
  supportsSubgroups: boolean;
  /** Where the live device is; null when no TS backend holds one. */
  thread: RendererDeviceThread | null;
  /** Why the last clear happened (diagnostics only). */
  clearedBecause: string | null;
}

type Listener = (entry: RendererDeviceEntry) => void;

let entry: RendererDeviceEntry = {
  generation: 0,
  device: null,
  supportsSubgroups: false,
  thread: null,
  clearedBecause: null,
};
/** The backend that published the current entry; only it may clear it. */
let owner: object | null = null;
const listeners = new Set<Listener>();

function set(next: Omit<RendererDeviceEntry, 'generation'>, nextOwner: object | null): void {
  owner = nextOwner;
  entry = { ...next, generation: entry.generation + 1 };
  for (const listener of Array.from(listeners)) {
    try {
      listener(entry);
    } catch (e) {
      console.warn('[deviceRegistry] listener threw', e);
    }
  }
}

/**
 * The backend `owner` now renders on `device` (null when the device is in the render
 * worker). Replaces whatever was published before.
 */
export function publishRendererDevice(
  device: GPUDevice | null,
  options: { supportsSubgroups?: boolean; thread?: RendererDeviceThread; owner?: object } = {},
): void {
  set(
    {
      device,
      supportsSubgroups: options.supportsSubgroups ?? false,
      thread: options.thread ?? 'main',
      clearedBecause: null,
    },
    options.owner ?? null,
  );
}

/**
 * The device is gone (loss, worker death, teardown). With `owner`, only that backend's
 * entry is cleared, so a stale backend cannot clear the one that replaced it. A clear
 * that would not change anything keeps the generation.
 */
export function clearRendererDevice(reason: string, clearingOwner?: object): void {
  if (entry.thread === null) return;
  if (clearingOwner !== undefined && clearingOwner !== owner) return;
  set({ device: null, supportsSubgroups: false, thread: null, clearedBecause: reason }, null);
}

export function getRendererDeviceEntry(): RendererDeviceEntry {
  return entry;
}

/** The live device when it is on this thread. */
export function getRendererDevice(): GPUDevice | null {
  return entry.device;
}

export function getRendererSupportsSubgroups(): boolean {
  return entry.supportsSubgroups;
}

export function getDeviceGeneration(): number {
  return entry.generation;
}

/** True while a TS backend holds a live device, on this thread or in the render worker. */
export function isRendererDeviceLive(): boolean {
  return entry.thread !== null;
}

/** Called on every publish/clear with the new entry. Returns an unsubscribe. */
export function subscribeRendererDevice(listener: Listener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Jest only: forget the owner and listeners between tests (the generation keeps counting). */
export function resetRendererDeviceRegistryForTests(): void {
  listeners.clear();
  owner = null;
  entry = { generation: entry.generation + 1, device: null, supportsSubgroups: false, thread: null, clearedBecause: null };
}
