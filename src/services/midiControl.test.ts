import {
  MidiControlAdapter,
  MIDIAccessLike,
  MIDIInputLike,
  MIDIMessageEventLike,
  MIDIConnectionEventLike,
  subscribeKeyEvents,
  captureKeyOnce,
  translateMIDIMessage,
  Midi14BitPairer,
} from './midiControl';
import { ControlEvent } from './controlBindings';

type FakeInput = MIDIInputLike & { listeners: Set<(e: MIDIMessageEventLike) => void> };
type FakeAccess = MIDIAccessLike & { stateListeners: Set<(e: MIDIConnectionEventLike) => void> };

function makeFakeInput(id: string, name = 'Fake Input'): FakeInput {
  const listeners = new Set<(e: MIDIMessageEventLike) => void>();
  return {
    id,
    name,
    manufacturer: 'Test',
    listeners,
    addEventListener: vi.fn((_type: 'midimessage', l: (e: MIDIMessageEventLike) => void) => { listeners.add(l); }),
    removeEventListener: vi.fn((_type: 'midimessage', l: (e: MIDIMessageEventLike) => void) => { listeners.delete(l); }),
    open: vi.fn().mockResolvedValue({} as MIDIInputLike),
    close: vi.fn().mockResolvedValue({} as MIDIInputLike),
  };
}

function makeFakeAccess(inputs: MIDIInputLike[]): FakeAccess {
  const map = new Map<string, MIDIInputLike>();
  inputs.forEach((input) => map.set(input.id, input));
  const stateListeners = new Set<(e: MIDIConnectionEventLike) => void>();
  return {
    inputs: map,
    stateListeners,
    addEventListener: vi.fn((_type: 'statechange', l: (e: MIDIConnectionEventLike) => void) => { stateListeners.add(l); }),
    removeEventListener: vi.fn((_type: 'statechange', l: (e: MIDIConnectionEventLike) => void) => { stateListeners.delete(l); }),
  };
}

function sendMessage(input: MIDIInputLike, data: number[]): void {
  const event: MIDIMessageEventLike = { data };
  (input as FakeInput).listeners.forEach((l) => l(event));
}

describe('translateMIDIMessage', () => {
  test('translates CC message', () => {
    const event = translateMIDIMessage([0xb0, 7, 63]);
    expect(event).toEqual({
      source: 'midi-cc',
      id: 'ch1/cc7',
      value: 63 / 127,
    });
  });

  test('translates note on', () => {
    const event = translateMIDIMessage([0x90, 60, 127]);
    expect(event).toEqual({
      source: 'midi-note',
      id: 'ch1/note60',
      value: 1,
    });
  });

  test('translates note on with zero velocity as release', () => {
    const event = translateMIDIMessage([0x90, 60, 0]);
    expect(event).toEqual({
      source: 'midi-note',
      id: 'ch1/note60',
      value: 0,
    });
  });

  test('translates note off', () => {
    const event = translateMIDIMessage([0x80, 60, 64]);
    expect(event).toEqual({
      source: 'midi-note',
      id: 'ch1/note60',
      value: 0,
    });
  });

  test('ignores unknown short messages', () => {
    expect(translateMIDIMessage([0xf8])).toBeNull();
  });
});

describe('MidiControlAdapter', () => {
  test('enumerates devices from injected MIDIAccess', () => {
    const input = makeFakeInput('input-1', 'Launch Control');
    const access = makeFakeAccess([input]);
    const adapter = new MidiControlAdapter(access);

    expect(adapter.getDevices()).toEqual([
      { id: 'input-1', name: 'Launch Control', manufacturer: 'Test' },
    ]);
  });

  test('subscribes to CC events from fake input', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const adapter = new MidiControlAdapter(access);

    const events: ControlEvent[] = [];
    adapter.subscribe((e: ControlEvent) => events.push(e));

    sendMessage(input, [0xb2, 14, 64]);

    expect(events).toEqual([
      { source: 'midi-cc', id: 'ch3/cc14', value: 64 / 127 },
    ]);
  });

  test('subscribes to note on/off from fake input', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const adapter = new MidiControlAdapter(access);

    const events: ControlEvent[] = [];
    adapter.subscribe((e: ControlEvent) => events.push(e));

    sendMessage(input, [0x91, 48, 100]);
    sendMessage(input, [0x81, 48, 0]);

    expect(events).toEqual([
      { source: 'midi-note', id: 'ch2/note48', value: 100 / 127 },
      { source: 'midi-note', id: 'ch2/note48', value: 0 },
    ]);
  });

  test('unsubscribe stops events', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const adapter = new MidiControlAdapter(access);

    const events: ControlEvent[] = [];
    const unsubscribe = adapter.subscribe((e: ControlEvent) => events.push(e));
    unsubscribe();

    sendMessage(input, [0xb0, 1, 127]);
    expect(events).toHaveLength(0);
  });

  test('disable removes message handlers', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const adapter = new MidiControlAdapter(access);

    const events: ControlEvent[] = [];
    adapter.subscribe((e: ControlEvent) => events.push(e));
    adapter.disable();

    sendMessage(input, [0xb0, 1, 127]);
    expect(events).toHaveLength(0);
    expect(adapter.getDevices()).toEqual([]);
  });

  test('two adapters on one input both receive a message (#1511 bug 6)', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const a = new MidiControlAdapter(access);
    const b = new MidiControlAdapter(access);
    const aEvents: ControlEvent[] = [];
    const bEvents: ControlEvent[] = [];
    a.subscribe((e) => aEvents.push(e));
    b.subscribe((e) => bEvents.push(e));

    sendMessage(input, [0xb0, 7, 127]);

    expect(aEvents).toHaveLength(1);
    expect(bEvents).toHaveLength(1);
  });

  test('disabling one adapter does not silence the other (#1511 bug 6)', () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    const a = new MidiControlAdapter(access);
    const b = new MidiControlAdapter(access);
    const bEvents: ControlEvent[] = [];
    b.subscribe((e) => bEvents.push(e));

    a.disable();
    sendMessage(input, [0xb0, 7, 127]);

    expect(bEvents).toHaveLength(1);
    expect(input.listeners.size).toBe(1);
    expect(access.stateListeners.size).toBe(1);
  });

  test('hooks a hot-plugged input once and only for live adapters', () => {
    const access = makeFakeAccess([]);
    const adapter = new MidiControlAdapter(access);
    const events: ControlEvent[] = [];
    adapter.subscribe((e) => events.push(e));
    const plugged = makeFakeInput('input-2');

    access.stateListeners.forEach((l) => l({ port: plugged }));
    access.stateListeners.forEach((l) => l({ port: plugged }));
    sendMessage(plugged, [0x90, 60, 127]);
    expect(events).toHaveLength(1);
    expect(plugged.listeners.size).toBe(1);

    adapter.disable();
    expect(plugged.listeners.size).toBe(0);
  });

  test('disable before requestAccess resolves attaches nothing (#1511 bug 6)', async () => {
    const input = makeFakeInput('input-1');
    const access = makeFakeAccess([input]);
    let resolveAccess!: (a: MIDIAccessLike) => void;
    const nav = navigator as unknown as { requestMIDIAccess?: () => Promise<MIDIAccessLike> };
    const original = nav.requestMIDIAccess;
    nav.requestMIDIAccess = vi.fn(() => new Promise<MIDIAccessLike>((r) => { resolveAccess = r; }));
    try {
      const adapter = new MidiControlAdapter();
      const pending = adapter.requestAccess();
      adapter.disable();
      resolveAccess(access);
      await expect(pending).resolves.toBe(false);
      expect(input.listeners.size).toBe(0);
      expect(access.stateListeners.size).toBe(0);
      expect(adapter.getDevices()).toEqual([]);
    } finally {
      nav.requestMIDIAccess = original;
    }
  });

  test('requestAccess returns false when navigator.requestMIDIAccess is missing', async () => {
    const adapter = new MidiControlAdapter();
    const result = await adapter.requestAccess();
    expect(result).toBe(false);
  });
});

describe('subscribeKeyEvents', () => {
  afterEach(() => {
    // Ensure no lingering listeners between tests.
    vi.restoreAllMocks();
  });

  test('translates keydown/keyup to ControlEvents', () => {
    const events: ControlEvent[] = [];
    const unsubscribe = subscribeKeyEvents((e: ControlEvent) => events.push(e));

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    window.dispatchEvent(new KeyboardEvent('keyup', { key: 'a' }));

    unsubscribe();

    expect(events).toEqual([
      { source: 'key', id: 'a', value: 1 },
      { source: 'key', id: 'a', value: 0 },
    ]);
  });

  test('ignores modifier-only keys and repeats', () => {
    const events: ControlEvent[] = [];
    const unsubscribe = subscribeKeyEvents((e: ControlEvent) => events.push(e));

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Shift' }));
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'b', repeat: true }));

    unsubscribe();

    expect(events).toHaveLength(0);
  });
});

describe('captureKeyOnce', () => {
  test('captures first key and auto-unsubscribes', () => {
    const events: ControlEvent[] = [];
    const unsubscribe = captureKeyOnce((e: ControlEvent) => events.push(e));

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'x' }));
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'y' }));

    unsubscribe();

    expect(events).toEqual([{ source: 'key', id: 'x', value: 1 }]);
  });

  test('ignores modifier keys', () => {
    const events: ControlEvent[] = [];
    const unsubscribe = captureKeyOnce((e: ControlEvent) => events.push(e));

    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Control' }));
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z' }));

    unsubscribe();

    expect(events).toEqual([{ source: 'key', id: 'z', value: 1 }]);
  });
});

describe('channels', () => {
  it('keeps the same CC on different channels distinct', () => {
    expect(translateMIDIMessage([0xb0, 7, 10])?.id).toBe('ch1/cc7');
    expect(translateMIDIMessage([0xb1, 7, 10])?.id).toBe('ch2/cc7');
    expect(translateMIDIMessage([0xbf, 7, 10])?.id).toBe('ch16/cc7');
  });
});

describe('Midi14BitPairer', () => {
  it('emits coarse MSB then a 14-bit refinement on the LSB', () => {
    const p = new Midi14BitPairer();
    const coarse = p.translate([0xb0, 1, 64]);
    expect(coarse).toEqual({ source: 'midi-cc', id: 'ch1/cc1', value: 64 / 127 });
    const fine = p.translate([0xb0, 33, 127]);
    expect(fine?.id).toBe('ch1/cc1');
    expect(fine?.value).toBeCloseTo(((64 << 7) | 127) / 16383);
  });

  it('reaches full scale exactly', () => {
    const p = new Midi14BitPairer();
    p.translate([0xb0, 0, 127]);
    expect(p.translate([0xb0, 32, 127])?.value).toBe(1);
  });

  it('passes an unpaired LSB through as a plain CC', () => {
    const p = new Midi14BitPairer();
    expect(p.translate([0xb0, 40, 127])).toEqual({ source: 'midi-cc', id: 'ch1/cc40', value: 1 });
    // MSB on another channel does not pair.
    p.translate([0xb1, 8, 10]);
    expect(p.translate([0xb0, 40, 0])?.id).toBe('ch1/cc40');
  });

  it('leaves notes and CC >= 64 untouched', () => {
    const p = new Midi14BitPairer();
    expect(p.translate([0x90, 60, 127])?.id).toBe('ch1/note60');
    expect(p.translate([0xb0, 74, 127])?.id).toBe('ch1/cc74');
  });
});
