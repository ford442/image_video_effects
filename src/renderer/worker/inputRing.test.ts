import {
  canShareMemory,
  createInputRingBuffer,
  InputRingReader,
  InputRingWriter,
  RIPPLE_CAPACITY,
} from './inputRing';

function pair() {
  const sab = createInputRingBuffer();
  return { sab, writer: new InputRingWriter(sab), reader: new InputRingReader(sab) };
}

describe('SAB input ring (#1314 C3)', () => {
  it('is only used when the realm is cross-origin isolated', () => {
    expect(canShareMemory()).toBe(false); // jsdom: crossOriginIsolated is undefined
  });

  it('round-trips mouse, mouse-down, audio and bins; unchanged state is not re-applied', () => {
    const { writer, reader } = pair();
    const first = reader.drain();
    expect(first.state?.mouse).toEqual([0.5, 0.5]); // defaults on the first drain

    writer.setMouse(0.25, 0.75);
    writer.setMouseDown(true);
    writer.setAudio(0.1, 0.2, 0.3);
    const bins = new Float32Array(128).map((_, i) => i / 128);
    writer.setBins(bins);
    const next = reader.drain();
    expect(next.state?.mouse).toEqual([0.25, 0.75]);
    expect(next.state?.mouseDown).toBe(true);
    expect(next.state?.audio.map((v) => Number(v.toFixed(3)))).toEqual([0.1, 0.2, 0.3]);
    expect(Array.from(next.state?.bins ?? []).slice(0, 3)).toEqual([0, 1 / 128, 2 / 128]);

    expect(reader.drain().state).toBeUndefined();
  });

  it('reports only the slots whose params changed', () => {
    const { writer, reader } = pair();
    reader.drain();
    writer.setSlotParams(2, [0.1, 0.2, 0.3, 0.4]);
    writer.setSlotParams(5, [1, 1, 1, 1]);
    const out = reader.drain();
    expect(out.slotParams.map(([slot, ...p]) => [slot, ...p.map((v) => Number(v.toFixed(2)))])).toEqual([
      [2, 0.1, 0.2, 0.3, 0.4],
      [5, 1, 1, 1, 1],
    ]);
    expect(reader.drain().slotParams).toEqual([]);
  });

  it('delivers ripples in order, drops those queued before a clear, and drops when full', () => {
    const { writer, reader } = pair();
    writer.pushRipple(0.1, 0.1);
    writer.clearRipples();
    writer.pushRipple(0.2, 0.2);
    writer.pushRipple(0.3, 0.3);
    const out = reader.drain();
    expect(out.clearRipples).toBe(true);
    expect(out.ripples.map(([x]) => Number(x.toFixed(1)))).toEqual([0.2, 0.3]);
    expect(reader.drain()).toMatchObject({ clearRipples: false, ripples: [] });

    for (let i = 0; i < RIPPLE_CAPACITY; i++) expect(writer.pushRipple(i, i)).toBe(true);
    expect(writer.pushRipple(999, 999)).toBe(false);
    expect(reader.drain().ripples).toHaveLength(RIPPLE_CAPACITY);
    expect(writer.pushRipple(1, 1)).toBe(true); // space again after the drain
  });

  it('skips a torn state block and retries the dirty slots next frame', () => {
    const { sab, writer, reader } = pair();
    reader.drain();
    writer.setSlotParams(1, [0.9, 0.9, 0.9, 0.9]);
    const header = new Int32Array(sab, 0, 16);
    Atomics.add(header, 1, 1); // simulate a writer stuck mid-write (seq odd)
    const torn = reader.drain();
    expect(torn.torn).toBe(true);
    expect(torn.state).toBeUndefined();
    Atomics.add(header, 1, 1); // writer finishes
    const healed = reader.drain();
    expect(healed.torn).toBe(false);
    expect(healed.slotParams.map(([slot]) => slot)).toEqual([1]);
  });

  it('rejects a buffer that is not an input ring', () => {
    expect(() => new InputRingReader(new SharedArrayBuffer(4096))).toThrow('bad magic');
  });
});
