// ═══════════════════════════════════════════════════════════════════════════════
//  midiControl.ts
//  Web MIDI adapter + keyboard adapter behind the normalized ControlEvent type.
//  The hardware layer is fully injectable: tests pass a fake MIDIAccessLike.
// ═══════════════════════════════════════════════════════════════════════════════

import { ControlEvent, ControlEventCallback } from './controlBindings';

export interface MIDIDevice {
  id: string;
  name: string;
  manufacturer?: string;
}

export interface MIDIMessageEventLike {
  data: Uint8Array | number[];
}

export interface MIDIConnectionEventLike {
  port: MIDIInputLike;
}

export interface MIDIInputLike {
  id: string;
  name?: string;
  manufacturer?: string;
  onmidimessage: ((event: MIDIMessageEventLike) => void) | null;
  open(): Promise<MIDIInputLike>;
  close(): Promise<MIDIInputLike>;
}

export interface MIDIAccessLike {
  inputs: Map<string, MIDIInputLike>;
  onstatechange: ((event: MIDIConnectionEventLike) => void) | null;
}

function isMIDIInputLike(port: unknown): port is MIDIInputLike {
  if (!port || typeof port !== 'object') return false;
  const p = port as Partial<MIDIInputLike>;
  return typeof p.id === 'string' && typeof p.open === 'function';
}

function normalizeMIDIData(raw: Uint8Array | number[]): number[] {
  if (Array.isArray(raw)) return raw;
  return Array.from(raw);
}

export function translateMIDIMessage(data: number[]): ControlEvent | null {
  if (data.length < 2) return null;

  const status = data[0];
  const channel = (status & 0x0f) + 1;
  const messageType = status & 0xf0;

  // Control Change
  if (messageType === 0xb0 && data.length >= 3) {
    const controller = data[1];
    const value = data[2] / 127;
    return {
      source: 'midi-cc',
      id: `ch${channel}/cc${controller}`,
      value: Math.max(0, Math.min(1, value)),
    };
  }

  // Note On
  if (messageType === 0x90 && data.length >= 3) {
    const note = data[1];
    const velocity = data[2];
    if (velocity === 0) {
      return {
        source: 'midi-note',
        id: `ch${channel}/note${note}`,
        value: 0,
      };
    }
    return {
      source: 'midi-note',
      id: `ch${channel}/note${note}`,
      value: velocity / 127,
    };
  }

  // Note Off
  if (messageType === 0x80 && data.length >= 3) {
    const note = data[1];
    return {
      source: 'midi-note',
      id: `ch${channel}/note${note}`,
      value: 0,
    };
  }

  return null;
}

/**
 * Opt-in 14-bit CC pairing (MIDI 1.0: CC 0–31 MSB, 32–63 LSB).
 * The MSB emits a coarse `chN/ccM` event straight away so MSB-only gear keeps
 * working; a following LSB on M+32 re-emits `chN/ccM` at 14-bit resolution and
 * is swallowed. An LSB with no prior MSB on that channel passes through as a
 * plain 7-bit CC, so controllers using 32–63 as ordinary knobs still map.
 */
export class Midi14BitPairer {
  private msb = new Map<string, number>();

  translate(data: number[]): ControlEvent | null {
    const status = data[0];
    if ((status & 0xf0) !== 0xb0 || data.length < 3) return translateMIDIMessage(data);
    const channel = (status & 0x0f) + 1;
    const controller = data[1];
    const value = data[2] & 0x7f;
    if (controller < 32) {
      this.msb.set(`${channel}/${controller}`, value);
      return translateMIDIMessage(data);
    }
    if (controller < 64) {
      const base = controller - 32;
      const msb = this.msb.get(`${channel}/${base}`);
      if (msb !== undefined) {
        return {
          source: 'midi-cc',
          id: `ch${channel}/cc${base}`,
          value: ((msb << 7) | value) / 16383,
        };
      }
    }
    return translateMIDIMessage(data);
  }
}

export interface MidiControlAdapterOptions {
  /** Pair CC 0–31 with 32–63 into 14-bit values. Off by default. */
  pair14Bit?: boolean;
}

export class MidiControlAdapter {
  private access: MIDIAccessLike | null = null;
  private listeners = new Set<ControlEventCallback>();
  private subscribedInputs = new Set<MIDIInputLike>();
  private pairer: Midi14BitPairer | null = null;

  constructor(initialAccess?: MIDIAccessLike, options: MidiControlAdapterOptions = {}) {
    this.setPair14Bit(options.pair14Bit ?? false);
    if (initialAccess) {
      this.attachAccess(initialAccess);
    }
  }

  async requestAccess(): Promise<boolean> {
    if (this.access) return true;
    if (typeof navigator === 'undefined') return false;
    const nav = navigator as typeof navigator & {
      requestMIDIAccess?: (options?: { sysex?: boolean }) => Promise<MIDIAccessLike>;
    };
    if (!nav.requestMIDIAccess) return false;

    try {
      const access = await nav.requestMIDIAccess({ sysex: false });
      this.attachAccess(access as unknown as MIDIAccessLike);
      return true;
    } catch {
      return false;
    }
  }

  disable(): void {
    if (!this.access) return;
    this.access.onstatechange = null;
    for (const input of this.subscribedInputs) {
      input.onmidimessage = null;
    }
    this.subscribedInputs.clear();
    this.access = null;
  }

  getDevices(): MIDIDevice[] {
    if (!this.access) return [];
    const devices: MIDIDevice[] = [];
    this.access.inputs.forEach((input) => {
      devices.push({
        id: input.id,
        name: input.name || `MIDI ${input.id}`,
        manufacturer: input.manufacturer,
      });
    });
    return devices;
  }

  setPair14Bit(enabled: boolean): void {
    this.pairer = enabled ? new Midi14BitPairer() : null;
  }

  subscribe(callback: ControlEventCallback): () => void {
    this.listeners.add(callback);
    return () => {
      this.listeners.delete(callback);
    };
  }

  private attachAccess(access: MIDIAccessLike): void {
    this.access = access;
    this.access.inputs.forEach((input) => {
      this.hookInput(input);
    });
    this.access.onstatechange = (event) => {
      if (isMIDIInputLike(event.port) && event.port.onmidimessage === null) {
        this.hookInput(event.port);
      }
    };
  }

  private hookInput(input: MIDIInputLike): void {
    if (this.subscribedInputs.has(input)) return;
    this.subscribedInputs.add(input);
    input.onmidimessage = (event) => {
      const data = normalizeMIDIData(event.data);
      const controlEvent = this.pairer ? this.pairer.translate(data) : translateMIDIMessage(data);
      if (controlEvent) {
        this.emit(controlEvent);
      }
    };
  }

  private emit(event: ControlEvent): void {
    this.listeners.forEach((cb) => cb(event));
  }
}

function shouldIgnoreKey(e: KeyboardEvent): boolean {
  // Ignore modifier-only keys and repeated holds.
  if (e.repeat) return true;
  const ignored = new Set([
    'Shift',
    'Control',
    'Alt',
    'Meta',
    'CapsLock',
    'Tab',
    'Escape',
  ]);
  return ignored.has(e.key);
}

/**
 * Subscribe to global keydown/keyup events. Returns an unsubscribe function.
 */
export function subscribeKeyEvents(callback: ControlEventCallback): () => void {
  if (typeof window === 'undefined') return () => {};

  const onKeyDown = (e: KeyboardEvent) => {
    if (shouldIgnoreKey(e)) return;
    callback({ source: 'key', id: e.key, value: 1 });
  };

  const onKeyUp = (e: KeyboardEvent) => {
    if (shouldIgnoreKey(e)) return;
    callback({ source: 'key', id: e.key, value: 0 });
  };

  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);

  return () => {
    window.removeEventListener('keydown', onKeyDown);
    window.removeEventListener('keyup', onKeyUp);
  };
}

/**
 * Capture a single keydown event, then auto-unsubscribe. Useful for MIDI-learn UI.
 */
export function captureKeyOnce(callback: ControlEventCallback): () => void {
  if (typeof window === 'undefined') return () => {};

  let unsubscribe = () => {};

  const onKeyDown = (e: KeyboardEvent) => {
    if (shouldIgnoreKey(e)) return;
    unsubscribe();
    callback({ source: 'key', id: e.key, value: 1 });
  };

  window.addEventListener('keydown', onKeyDown);
  unsubscribe = () => {
    window.removeEventListener('keydown', onKeyDown);
  };

  return unsubscribe;
}
