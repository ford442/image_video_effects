import {
  MidiControlAdapter,
  MIDIAccessLike,
  MIDIInputLike,
  MIDIMessageEventLike,
  subscribeKeyEvents,
  captureKeyOnce,
  translateMIDIMessage,
} from './midiControl';
import { ControlEvent } from './controlBindings';

function makeFakeInput(id: string, name = 'Fake Input'): MIDIInputLike {
  return {
    id,
    name,
    manufacturer: 'Test',
    onmidimessage: null,
    open: jest.fn().mockResolvedValue({} as MIDIInputLike),
    close: jest.fn().mockResolvedValue({} as MIDIInputLike),
  };
}

function makeFakeAccess(inputs: MIDIInputLike[]): MIDIAccessLike {
  const map = new Map<string, MIDIInputLike>();
  inputs.forEach((input) => map.set(input.id, input));
  return {
    inputs: map,
    onstatechange: null,
  };
}

function sendMessage(input: MIDIInputLike, data: number[]): void {
  const event: MIDIMessageEventLike = { data };
  if (input.onmidimessage) {
    input.onmidimessage(event);
  }
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

  test('requestAccess returns false when navigator.requestMIDIAccess is missing', async () => {
    const adapter = new MidiControlAdapter();
    const result = await adapter.requestAccess();
    expect(result).toBe(false);
  });
});

describe('subscribeKeyEvents', () => {
  afterEach(() => {
    // Ensure no lingering listeners between tests.
    jest.restoreAllMocks();
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
