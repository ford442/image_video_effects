/**
 * inputRing.ts
 *
 * SharedArrayBuffer input channel for the render worker (#1314 WP-1). Used
 * only when both the page and the worker are cross-origin isolated
 * (COOP same-origin + COEP credentialless); otherwise input travels as one
 * coalesced `frameInput` postMessage per animation frame.
 *
 * One writer (the page) and one reader (the worker's frame loop, once per
 * frame), so no locks: a seqlock guards the state block, and ripples use a
 * single-producer / single-consumer ring.
 *
 * Layout (bytes):
 *   0    Int32 header[16]
 *          0 magic           1 seq (odd while writing)   2 slot dirty mask
 *          3 ripple write #  4 ripple read #              5 clear generation
 *          6 ripple # at clear   7 state generation     8 mouseDown (0/1)
 *   64   Float32 state[160]: mouse x,y · audio b,m,t · 128 bins · 6×vec4 slot params
 *   704  Float32 ripples[64 × 2]
 */

export const INPUT_RING_BYTES = 4096;
export const INPUT_RING_MAGIC = 0x50585231; // "PXR1"
export const RIPPLE_CAPACITY = 64;
export const SLOT_COUNT = 6;
export const BIN_COUNT = 128;

const H_MAGIC = 0;
const H_SEQ = 1;
const H_DIRTY = 2;
const H_RIPPLE_W = 3;
const H_RIPPLE_R = 4;
const H_CLEAR_GEN = 5;
const H_CLEAR_AT = 6;
const H_STATE_GEN = 7;
const H_MOUSE_DOWN = 8;

const STATE_OFFSET = 64;
const S_MOUSE = 0;
const S_AUDIO = 2;
const S_BINS = 5;
const S_SLOTS = S_BINS + BIN_COUNT; // 133
const STATE_FLOATS = S_SLOTS + SLOT_COUNT * 4; // 157
const RIPPLE_OFFSET = 704;

/** True when this realm can share memory with a worker. */
export function canShareMemory(): boolean {
  return (
    typeof SharedArrayBuffer !== 'undefined' &&
    typeof Atomics !== 'undefined' &&
    (globalThis as { crossOriginIsolated?: boolean }).crossOriginIsolated === true
  );
}

export function createInputRingBuffer(): SharedArrayBuffer {
  const sab = new SharedArrayBuffer(INPUT_RING_BYTES);
  Atomics.store(new Int32Array(sab, 0, 16), H_MAGIC, INPUT_RING_MAGIC);
  const state = new Float32Array(sab, STATE_OFFSET, STATE_FLOATS);
  state.set([0.5, 0.5], S_MOUSE);
  for (let i = 0; i < SLOT_COUNT * 4; i++) state[S_SLOTS + i] = 0.5;
  return sab;
}

/** Page side: write-only view. */
export class InputRingWriter {
  private readonly header: Int32Array;
  private readonly state: Float32Array;
  private readonly ripples: Float32Array;

  constructor(sab: SharedArrayBuffer) {
    this.header = new Int32Array(sab, 0, 16);
    this.state = new Float32Array(sab, STATE_OFFSET, STATE_FLOATS);
    this.ripples = new Float32Array(sab, RIPPLE_OFFSET, RIPPLE_CAPACITY * 2);
  }

  /** Mutate the state block under the seqlock. */
  private write(mutate: (state: Float32Array) => void): void {
    Atomics.add(this.header, H_SEQ, 1); // odd: a reader retries
    mutate(this.state);
    Atomics.add(this.header, H_SEQ, 1); // even: consistent again
    Atomics.add(this.header, H_STATE_GEN, 1);
  }

  setMouse(x: number, y: number): void {
    this.write((s) => {
      s[S_MOUSE] = x;
      s[S_MOUSE + 1] = y;
    });
  }

  setMouseDown(down: boolean): void {
    Atomics.store(this.header, H_MOUSE_DOWN, down ? 1 : 0);
    Atomics.add(this.header, H_STATE_GEN, 1);
  }

  setAudio(bass: number, mid: number, treble: number): void {
    this.write((s) => {
      s[S_AUDIO] = bass;
      s[S_AUDIO + 1] = mid;
      s[S_AUDIO + 2] = treble;
    });
  }

  setBins(bins: Float32Array): void {
    this.write((s) => s.set(bins.subarray(0, BIN_COUNT), S_BINS));
  }

  setSlotParams(slot: number, p: ArrayLike<number>): void {
    if (slot < 0 || slot >= SLOT_COUNT) return;
    this.write((s) => {
      for (let i = 0; i < 4; i++) s[S_SLOTS + slot * 4 + i] = p[i] ?? 0.5;
    });
    Atomics.or(this.header, H_DIRTY, 1 << slot);
  }

  /** Queue a ripple; false when the ring is full (the ripple is dropped). */
  pushRipple(x: number, y: number): boolean {
    const w = Atomics.load(this.header, H_RIPPLE_W);
    const r = Atomics.load(this.header, H_RIPPLE_R);
    if (w - r >= RIPPLE_CAPACITY) return false;
    const i = (w % RIPPLE_CAPACITY) * 2;
    this.ripples[i] = x;
    this.ripples[i + 1] = y;
    Atomics.store(this.header, H_RIPPLE_W, w + 1); // publish after the payload
    return true;
  }

  clearRipples(): void {
    Atomics.store(this.header, H_CLEAR_AT, Atomics.load(this.header, H_RIPPLE_W));
    Atomics.add(this.header, H_CLEAR_GEN, 1);
  }
}

export interface InputRingSnapshot {
  /** Present only when the state block changed since the last drain. */
  state?: {
    mouse: [number, number];
    mouseDown: boolean;
    audio: [number, number, number];
    bins: Float32Array;
  };
  /** Slots whose params changed, with their full vec4. */
  slotParams: Array<[number, number, number, number, number]>;
  clearRipples: boolean;
  ripples: Array<[number, number]>;
  /** The seqlock never settled within the retry budget; state skipped this frame. */
  torn: boolean;
}

/** Worker side: drained once per frame. */
export class InputRingReader {
  private readonly header: Int32Array;
  private readonly state: Float32Array;
  private readonly ripples: Float32Array;
  private readonly copy = new Float32Array(STATE_FLOATS);
  private lastStateGen = -1;
  private lastClearGen = 0;
  drains = 0;

  constructor(sab: SharedArrayBuffer, private readonly retries = 3) {
    this.header = new Int32Array(sab, 0, 16);
    if (Atomics.load(this.header, H_MAGIC) !== INPUT_RING_MAGIC) throw new Error('input ring: bad magic');
    this.state = new Float32Array(sab, STATE_OFFSET, STATE_FLOATS);
    this.ripples = new Float32Array(sab, RIPPLE_OFFSET, RIPPLE_CAPACITY * 2);
  }

  /** Copy the state block consistently; false when a writer kept it busy. */
  private readState(): boolean {
    for (let attempt = 0; attempt < this.retries; attempt++) {
      const before = Atomics.load(this.header, H_SEQ);
      if (before & 1) continue;
      this.copy.set(this.state);
      if (Atomics.load(this.header, H_SEQ) === before) return true;
    }
    return false;
  }

  drain(): InputRingSnapshot {
    this.drains++;
    const out: InputRingSnapshot = { slotParams: [], clearRipples: false, ripples: [], torn: false };
    const gen = Atomics.load(this.header, H_STATE_GEN);
    const dirty = Atomics.exchange(this.header, H_DIRTY, 0);
    if (gen !== this.lastStateGen || dirty) {
      if (this.readState()) {
        this.lastStateGen = gen;
        const c = this.copy;
        out.state = {
          mouse: [c[S_MOUSE], c[S_MOUSE + 1]],
          mouseDown: Atomics.load(this.header, H_MOUSE_DOWN) === 1,
          audio: [c[S_AUDIO], c[S_AUDIO + 1], c[S_AUDIO + 2]],
          bins: c.slice(S_BINS, S_BINS + BIN_COUNT),
        };
        for (let slot = 0; slot < SLOT_COUNT; slot++) {
          if (!(dirty & (1 << slot))) continue;
          const o = S_SLOTS + slot * 4;
          out.slotParams.push([slot, c[o], c[o + 1], c[o + 2], c[o + 3]]);
        }
      } else {
        out.torn = true;
        if (dirty) Atomics.or(this.header, H_DIRTY, dirty); // retry those slots next frame
      }
    }

    let r = Atomics.load(this.header, H_RIPPLE_R);
    const w = Atomics.load(this.header, H_RIPPLE_W);
    const clearGen = Atomics.load(this.header, H_CLEAR_GEN);
    if (clearGen !== this.lastClearGen) {
      this.lastClearGen = clearGen;
      out.clearRipples = true;
      // Ripples queued before the clear are gone with it.
      r = Math.max(r, Atomics.load(this.header, H_CLEAR_AT));
    }
    for (; r < w; r++) {
      const i = (r % RIPPLE_CAPACITY) * 2;
      out.ripples.push([this.ripples[i], this.ripples[i + 1]]);
    }
    Atomics.store(this.header, H_RIPPLE_R, w);
    return out;
  }
}
