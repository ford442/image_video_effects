import { OscBridge, OscBridgeStatus } from './oscBridge';
import { encodeOscMessage } from './oscPacket';
import { oscFlagFromSearch, oscWsUrlFromSearch } from './oscFlags';

class FakeSocket {
  static instances: FakeSocket[] = [];
  binaryType = 'blob';
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  constructor(public url: string) { FakeSocket.instances.push(this); }
  close() { this.onclose?.(); }
}

describe('oscFlags', () => {
  it('parses ?osc', () => {
    expect(oscFlagFromSearch('')).toBeNull();
    expect(oscFlagFromSearch('?osc')).toBe(true);
    expect(oscFlagFromSearch('?osc=1')).toBe(true);
    expect(oscFlagFromSearch('?osc=0')).toBe(false);
    expect(oscFlagFromSearch('?osc=false')).toBe(false);
  });

  it('only honours ws/wss overrides', () => {
    expect(oscWsUrlFromSearch('?osc_ws=ws://10.0.0.2:9001/osc/ws')).toBe('ws://10.0.0.2:9001/osc/ws');
    expect(oscWsUrlFromSearch('?osc_ws=http://evil')).toBeNull();
    expect(oscWsUrlFromSearch('?osc_ws=%%%')).toBeNull();
  });
});

describe('OscBridge', () => {
  beforeEach(() => {
    FakeSocket.instances = [];
    jest.useFakeTimers();
  });
  afterEach(() => jest.useRealTimers());

  const make = () => {
    const handle = { setSlotParam: jest.fn(), triggerTransition: jest.fn(), setSlotShader: jest.fn(), setAudioAmount: jest.fn() };
    const statuses: OscBridgeStatus[] = [];
    const bridge = new OscBridge({
      url: 'ws://relay',
      getHandle: () => handle,
      onStatus: (s) => statuses.push(s),
      WebSocketImpl: FakeSocket as unknown as typeof WebSocket,
      minBackoffMs: 100,
      maxBackoffMs: 400,
    });
    return { bridge, handle, statuses };
  };

  it('dispatches binary frames and ignores malformed ones', () => {
    const { bridge, handle } = make();
    bridge.start();
    const ws = FakeSocket.instances[0];
    expect(ws).toBeDefined();
    expect(ws!.binaryType).toBe('arraybuffer');
    ws!.onopen?.();
    const pkt = encodeOscMessage('/pixelocity/slot/1/param/y', [0.5]);
    ws!.onmessage?.({ data: pkt.buffer.slice(pkt.byteOffset, pkt.byteOffset + pkt.byteLength) });
    expect(handle.setSlotParam).toHaveBeenCalledWith(1, 'zoomParam2', 0.5);
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    ws!.onmessage?.({ data: new ArrayBuffer(3) });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
    bridge.stop();
  });

  it('reconnects with capped exponential backoff until stopped', () => {
    const { bridge, statuses } = make();
    bridge.start();
    FakeSocket.instances[0]!.onclose?.();
    jest.advanceTimersByTime(99);
    expect(FakeSocket.instances).toHaveLength(1);
    jest.advanceTimersByTime(1);
    expect(FakeSocket.instances).toHaveLength(2);
    FakeSocket.instances[1]!.onclose?.();
    jest.advanceTimersByTime(200);
    expect(FakeSocket.instances).toHaveLength(3);
    bridge.stop();
    jest.advanceTimersByTime(10_000);
    expect(FakeSocket.instances).toHaveLength(3);
    expect(statuses[statuses.length - 1]).toBe('closed');
  });
});
