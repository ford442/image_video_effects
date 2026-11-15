/**
 * calibrationStore.ts — persisted output layout and named calibrations.
 *
 *  - layout: the last config of every output id, restored when a stage with that
 *    id is opened again (so a corner pin survives a reload).
 *  - calibrations: named snapshots ("Club wall", "Left projector") to load into
 *    any output.
 *
 * localStorage only, every access guarded: private windows and blocked storage
 * just mean nothing is remembered.
 */

import { sanitizeOutputConfig, type OutputConfig } from './outputConfig';

export const LAYOUT_KEY = 'pixelocity.stageOutputs.v1';
export const CALIBRATIONS_KEY = 'pixelocity.outputCalibrations.v1';
const MAX_NAMED = 64;
const MAX_NAME = 64;

type StorageLike = Pick<Storage, 'getItem' | 'setItem'>;

function defaultStorage(): StorageLike | null {
  try {
    return typeof localStorage !== 'undefined' ? localStorage : null;
  } catch {
    return null;
  }
}

function readMap(storage: StorageLike | null, key: string): Record<string, OutputConfig> {
  if (!storage) return {};
  try {
    const raw = storage.getItem(key);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return {};
    const out: Record<string, OutputConfig> = {};
    for (const [name, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (name.length > 0 && name.length <= MAX_NAME) out[name] = sanitizeOutputConfig(value);
    }
    return out;
  } catch {
    return {};
  }
}

function writeMap(storage: StorageLike | null, key: string, map: Record<string, OutputConfig>): boolean {
  if (!storage) return false;
  try {
    storage.setItem(key, JSON.stringify(map));
    return true;
  } catch {
    return false;
  }
}

export class CalibrationStore {
  constructor(private readonly storage: StorageLike | null = defaultStorage()) {}

  /** The config an output had when it was last changed, or null. */
  loadLayout(outputId: string): OutputConfig | null {
    return readMap(this.storage, LAYOUT_KEY)[outputId] ?? null;
  }

  saveLayout(outputId: string, config: OutputConfig): void {
    const map = readMap(this.storage, LAYOUT_KEY);
    map[outputId] = sanitizeOutputConfig(config);
    writeMap(this.storage, LAYOUT_KEY, map);
  }

  listNamed(): string[] {
    return Object.keys(readMap(this.storage, CALIBRATIONS_KEY)).sort((a, b) => a.localeCompare(b));
  }

  loadNamed(name: string): OutputConfig | null {
    return readMap(this.storage, CALIBRATIONS_KEY)[name] ?? null;
  }

  /** False when the name is unusable, the store is full, or storage refused the write. */
  saveNamed(name: string, config: OutputConfig): boolean {
    const key = name.trim();
    if (key.length === 0 || key.length > MAX_NAME) return false;
    const map = readMap(this.storage, CALIBRATIONS_KEY);
    if (!(key in map) && Object.keys(map).length >= MAX_NAMED) return false;
    map[key] = sanitizeOutputConfig(config);
    return writeMap(this.storage, CALIBRATIONS_KEY, map);
  }

  deleteNamed(name: string): void {
    const map = readMap(this.storage, CALIBRATIONS_KEY);
    if (!(name in map)) return;
    delete map[name];
    writeMap(this.storage, CALIBRATIONS_KEY, map);
  }
}
