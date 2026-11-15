/**
 * stageController.ts — control-window side of stage outputs.
 *
 * Opens stage popups (placed on a chosen display through the Window Management
 * API when it is available), receives each stage's transferred canvas and
 * attaches it to the current WebGPU backend as an output, forwards resizes and
 * calibration changes, and re-attaches every open stage after a backend switch
 * (device-loss recovery spawns a new worker; the old canvases died with it).
 *
 * One instance per control window (getStageController()). Never imported by the
 * main bundle eagerly: the stage panel loads it on first open.
 */

import type { AttachOutputResult, OutputCanvas, OutputStatus } from '../renderer/webgpu/outputs';
import { applyCalibrationKey } from './calibrationKeys';
import { CalibrationStore } from './calibrationStore';
import { defaultOutputConfig, sanitizeOutputConfig, type OutputConfig } from './outputConfig';
import {
  isValidOutputId,
  parseStageToControl,
  STAGE_TAG,
  stageUrl,
  type ControlToStage,
  type StageToControl,
} from './stageProtocol';

/** The slice of the WebGPU backend (page or worker proxy) outputs need. */
export interface StageOutputBackend {
  attachOutput(id: string, canvas: OutputCanvas, width: number, height: number, config: unknown): Promise<AttachOutputResult>;
  detachOutput(id: string): void;
  setOutputConfig(id: string, config: unknown): void;
  setOutputSize(id: string, width: number, height: number): void;
  getOutputStatus(): OutputStatus[];
}

export type StageState = 'opening' | 'attaching' | 'live' | 'failed' | 'closed';

export interface StageInfo {
  id: string;
  state: StageState;
  error?: string;
  width: number;
  height: number;
  config: OutputConfig;
  /** Corner the keyboard moves (0 TL, 1 TR, 2 BR, 3 BL). */
  selected: number;
  /** Where the window was placed ('' when the Window Management API was not used). */
  screenLabel: string;
}

/** Minimal Window Management API surface (Chromium; permission-gated). */
export interface ScreenPlacement {
  label: string;
  left: number;
  top: number;
  width: number;
  height: number;
  isPrimary: boolean;
}

interface ScreenDetailedLike {
  label?: string;
  availLeft?: number;
  availTop?: number;
  left?: number;
  top?: number;
  availWidth?: number;
  availHeight?: number;
  width?: number;
  height?: number;
  isPrimary?: boolean;
}

/** Displays the stage can be placed on, or null when the API is missing or permission was refused. */
export async function listScreens(win: Window): Promise<ScreenPlacement[] | null> {
  const getScreenDetails = (win as unknown as { getScreenDetails?: () => Promise<{ screens: ScreenDetailedLike[] }> }).getScreenDetails;
  if (typeof getScreenDetails !== 'function') return null;
  try {
    const details = await getScreenDetails.call(win);
    return details.screens.map((s, i) => ({
      label: s.label || `Display ${i + 1}`,
      left: s.availLeft ?? s.left ?? 0,
      top: s.availTop ?? s.top ?? 0,
      width: s.availWidth ?? s.width ?? 1280,
      height: s.availHeight ?? s.height ?? 720,
      isPrimary: !!s.isPrimary,
    }));
  } catch {
    return null;
  }
}

export function windowFeatures(screen: ScreenPlacement | null): string {
  if (!screen) return 'popup,width=960,height=540';
  const r = (v: number) => Math.round(v);
  return `popup,left=${r(screen.left)},top=${r(screen.top)},width=${r(screen.width)},height=${r(screen.height)}`;
}

interface StageEntry {
  info: StageInfo;
  win: Window | null;
  /** Serial of the canvas that is attached (late canvases from an older request are ignored). */
  attachedSerial: number;
}

export interface StageControllerDeps {
  win: Window;
  getBackend(): StageOutputBackend | null;
  store?: CalibrationStore;
  /** How often to check for stage windows closed without a `bye` (ms). */
  pollMs?: number;
}

type Listener = (stages: StageInfo[]) => void;

export class StageController {
  private readonly stages = new Map<string, StageEntry>();
  private readonly listeners = new Set<Listener>();
  private readonly store: CalibrationStore;
  private readonly poll: ReturnType<typeof setInterval>;
  private nextIndex = 1;

  constructor(private readonly deps: StageControllerDeps) {
    this.store = deps.store ?? new CalibrationStore();
    deps.win.addEventListener('message', this.onMessage);
    this.poll = setInterval(() => this.reapClosed(), deps.pollMs ?? 1000);
  }

  get calibrations(): CalibrationStore {
    return this.store;
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.list());
    return () => this.listeners.delete(listener);
  }

  list(): StageInfo[] {
    return [...this.stages.values()].map((e) => ({ ...e.info }));
  }

  get(id: string): StageInfo | null {
    const e = this.stages.get(id);
    return e ? { ...e.info } : null;
  }

  /** Renderer-side status of an output (frames presented, errors), if attached. */
  status(id: string): OutputStatus | null {
    return this.deps.getBackend()?.getOutputStatus().find((s) => s.id === id) ?? null;
  }

  /**
   * Open a stage window. Must run in a user gesture (popup blockers). Returns the
   * output id, or null when the popup was blocked.
   */
  open(options: { id?: string; screen?: ScreenPlacement | null } = {}): string | null {
    const id = options.id && isValidOutputId(options.id) ? options.id : this.freeId();
    const existing = this.stages.get(id);
    if (existing?.win && !existing.win.closed) {
      existing.win.focus();
      return id;
    }
    const screen = options.screen ?? null;
    const url = stageUrl(id, this.deps.win.location.href);
    const win = this.deps.win.open(url, `pixelocity-stage-${id}`, windowFeatures(screen));
    const config = this.store.loadLayout(id) ?? defaultOutputConfig();
    const entry: StageEntry = {
      win,
      attachedSerial: 0,
      info: {
        id,
        state: win ? 'opening' : 'failed',
        width: screen?.width ?? 960,
        height: screen?.height ?? 540,
        config,
        selected: 0,
        screenLabel: screen?.label ?? '',
        ...(win ? {} : { error: 'The browser blocked the stage popup — allow popups for this site.' }),
      },
    };
    this.stages.set(id, entry);
    this.emit();
    return win ? id : null;
  }

  close(id: string): void {
    const entry = this.stages.get(id);
    if (!entry) return;
    this.send(entry, { px: STAGE_TAG, type: 'close', outputId: id });
    try {
      entry.win?.close();
    } catch {
      /* ignore */
    }
    this.markClosed(entry);
  }

  /** Forget a closed stage (its layout stays saved). */
  remove(id: string): void {
    const entry = this.stages.get(id);
    if (!entry) return;
    if (entry.info.state !== 'closed') this.close(id);
    this.stages.delete(id);
    this.emit();
  }

  identify(id: string): void {
    const entry = this.stages.get(id);
    if (entry) this.send(entry, { px: STAGE_TAG, type: 'identify', outputId: id, label: id });
  }

  setConfig(id: string, config: OutputConfig): void {
    const entry = this.stages.get(id);
    if (!entry) return;
    entry.info.config = sanitizeOutputConfig(config);
    this.store.saveLayout(id, entry.info.config);
    if (entry.info.state === 'live') this.deps.getBackend()?.setOutputConfig(id, entry.info.config);
    this.emit();
  }

  updateConfig(id: string, fn: (config: OutputConfig) => OutputConfig): void {
    const entry = this.stages.get(id);
    if (entry) this.setConfig(id, fn(entry.info.config));
  }

  selectCorner(id: string, corner: number): void {
    const entry = this.stages.get(id);
    if (!entry) return;
    entry.info.selected = ((Math.round(corner) % 4) + 4) % 4;
    this.emit();
  }

  /** Keyboard calibration (panel or stage window). True when the key was used. */
  handleKey(id: string, key: string, mods: { shift?: boolean; alt?: boolean }): boolean {
    const entry = this.stages.get(id);
    if (!entry) return false;
    const next = applyCalibrationKey(
      { config: entry.info.config, selected: entry.info.selected },
      key,
      mods,
      { width: entry.info.width, height: entry.info.height },
    );
    if (!next) return false;
    entry.info.selected = next.selected;
    if (next.config !== entry.info.config) this.setConfig(id, next.config);
    else this.emit();
    return true;
  }

  /**
   * The backend changed (switch, device-loss recovery): every open stage makes a fresh
   * canvas for the new owner. RendererManager.onBackendReady calls this.
   */
  reattachAll(): void {
    for (const entry of this.stages.values()) {
      if (entry.info.state === 'closed' || !entry.win || entry.win.closed) continue;
      entry.info.state = 'attaching';
      delete entry.info.error;
      this.send(entry, { px: STAGE_TAG, type: 'request-canvas', outputId: entry.info.id });
    }
    this.emit();
  }

  dispose(): void {
    clearInterval(this.poll);
    this.deps.win.removeEventListener('message', this.onMessage);
    for (const id of [...this.stages.keys()]) this.close(id);
    this.listeners.clear();
  }

  // ── internals ────────────────────────────────────────────────────────────

  private readonly onMessage = (event: MessageEvent): void => {
    if (event.origin !== this.deps.win.location.origin) return;
    const msg = parseStageToControl(event.data);
    if (!msg) return;
    const entry = this.stages.get(msg.outputId);
    // A canvas we did not ask for still has to be dropped, not leaked into a stale id.
    if (!entry || (event.source && entry.win && event.source !== entry.win)) return;
    void this.handleStageMessage(entry, msg);
  };

  private async handleStageMessage(entry: StageEntry, msg: StageToControl): Promise<void> {
    const id = entry.info.id;
    switch (msg.type) {
      case 'hello':
        entry.info.state = 'attaching';
        this.emit();
        this.send(entry, { px: STAGE_TAG, type: 'request-canvas', outputId: id });
        return;
      case 'canvas': {
        entry.info.width = msg.width;
        entry.info.height = msg.height;
        const backend = this.deps.getBackend();
        if (!backend) {
          this.fail(entry, 'No WebGPU renderer is running (stage outputs need the WebGPU backend).');
          return;
        }
        let result: AttachOutputResult;
        try {
          result = await backend.attachOutput(id, msg.canvas, msg.width, msg.height, entry.info.config);
        } catch (e) {
          result = { ok: false, error: e instanceof Error ? e.message : String(e) };
        }
        if (entry.info.state === 'closed') {
          if (result.ok) backend.detachOutput(id);
          return;
        }
        if (!result.ok) {
          this.fail(entry, result.error ?? 'attach failed');
          return;
        }
        entry.attachedSerial = msg.serial;
        entry.info.state = 'live';
        delete entry.info.error;
        this.emit();
        return;
      }
      case 'resize':
        entry.info.width = msg.width;
        entry.info.height = msg.height;
        if (entry.info.state === 'live') this.deps.getBackend()?.setOutputSize(id, msg.width, msg.height);
        this.emit();
        return;
      case 'key':
        this.handleKey(id, msg.key, { shift: msg.shift, alt: msg.alt });
        return;
      case 'bye':
        this.markClosed(entry);
        return;
    }
  }

  private fail(entry: StageEntry, error: string): void {
    entry.info.state = 'failed';
    entry.info.error = error;
    this.emit();
  }

  private markClosed(entry: StageEntry): void {
    if (entry.info.state === 'closed') return;
    const wasAttached = entry.info.state === 'live' || entry.info.state === 'attaching';
    entry.info.state = 'closed';
    entry.win = null;
    if (wasAttached) this.deps.getBackend()?.detachOutput(entry.info.id);
    this.emit();
  }

  private reapClosed(): void {
    for (const entry of this.stages.values()) {
      if (entry.info.state !== 'closed' && entry.win?.closed) this.markClosed(entry);
    }
  }

  private send(entry: StageEntry, msg: ControlToStage): void {
    const win = entry.win;
    if (!win || win.closed) return;
    try {
      win.postMessage(msg, this.deps.win.location.origin);
    } catch {
      /* the window is navigating away */
    }
  }

  private freeId(): string {
    for (;;) {
      const id = `stage-${this.nextIndex++}`;
      const e = this.stages.get(id);
      if (!e || e.info.state === 'closed') return id;
    }
  }

  private emit(): void {
    const snapshot = this.list();
    for (const l of this.listeners) l(snapshot);
  }
}

let singleton: StageController | null = null;

/** The control window's controller (created on first use). */
export function getStageController(deps: () => StageControllerDeps): StageController {
  if (!singleton) singleton = new StageController(deps());
  return singleton;
}

/** Tests only. */
export function resetStageControllerForTests(): void {
  singleton?.dispose();
  singleton = null;
}
