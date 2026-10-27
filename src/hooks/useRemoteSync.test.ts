import { renderHook, act } from '@testing-library/react';
import { useRemoteSync } from './useRemoteSync';

class MockBroadcastChannel {
  static instances: MockBroadcastChannel[] = [];
  name: string;
  onmessage: ((ev: MessageEvent) => void) | null = null;
  posted: Array<{ type: string; payload?: unknown }> = [];

  constructor(name: string) {
    this.name = name;
    MockBroadcastChannel.instances.push(this);
  }

  postMessage(data: { type: string; payload?: unknown }) {
    this.posted.push(data);
    for (const other of MockBroadcastChannel.instances) {
      if (other === this) continue;
      other.onmessage?.({ data } as MessageEvent);
    }
  }

  close() {
    const idx = MockBroadcastChannel.instances.indexOf(this);
    if (idx >= 0) MockBroadcastChannel.instances.splice(idx, 1);
  }
}

describe('useRemoteSync commands', () => {
  const originalBC = global.BroadcastChannel;

  beforeEach(() => {
    MockBroadcastChannel.instances = [];
    // @ts-expect-error test mock
    global.BroadcastChannel = MockBroadcastChannel;
  });

  afterEach(() => {
    global.BroadcastChannel = originalBC;
  });

  function mountMain(handlers: {
    handleRandomizeSlot?: (slot: number) => void;
    triggerRandomizeAllSlots?: () => void;
    triggerRoulette?: () => void;
    updateSlotParam?: (index: number, updates: Record<string, number>) => void;
    handleNewRandomImage?: () => Promise<void>;
    loadLocalMedia?: (blob: Blob, kind: 'image' | 'video') => Promise<void>;
  }) {
    return renderHook(() =>
      useRemoteSync({
        modes: ['liquid', 'none', 'none'],
        activeSlot: 0,
        slotParams: [] as any,
        shaderCategory: 'image',
        inputSource: 'image',
        autoChangeEnabled: false,
        autoChangeDelay: 10,
        isModelLoaded: false,
        availableModes: [],
        videoList: [],
        selectedVideo: '',
        isMuted: true,
        setMode: vi.fn(),
        setActiveSlot: vi.fn(),
        updateSlotParam: handlers.updateSlotParam ?? vi.fn(),
        setShaderCategory: vi.fn(),
        syncInputSourceToRenderer: vi.fn(),
        setAutoChangeEnabled: vi.fn(),
        setAutoChangeDelay: vi.fn(),
        handleNewRandomImage: vi.fn(async () => {}),
        loadDepthModel: vi.fn(async () => {}),
        setSelectedVideo: vi.fn(),
        setIsMuted: vi.fn(),
        ...handlers,
      }),
    );
  }

  it('dispatches CMD_RANDOMIZE_SLOT to handleRandomizeSlot', () => {
    const handleRandomizeSlot = vi.fn();
    mountMain({ handleRandomizeSlot });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_RANDOMIZE_SLOT', payload: 0 },
      } as MessageEvent);
    });

    expect(handleRandomizeSlot).toHaveBeenCalledWith(0);
  });

  it('dispatches CMD_ROULETTE to triggerRoulette', () => {
    const triggerRoulette = vi.fn();
    mountMain({ triggerRoulette });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_ROULETTE' },
      } as MessageEvent);
    });

    expect(triggerRoulette).toHaveBeenCalled();
  });

  it('dispatches CMD_RANDOMIZE_ALL_SLOTS', () => {
    const triggerRandomizeAllSlots = vi.fn();
    mountMain({ triggerRandomizeAllSlots });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_RANDOMIZE_ALL_SLOTS' },
      } as MessageEvent);
    });

    expect(triggerRandomizeAllSlots).toHaveBeenCalled();
  });

  it('dispatches CMD_UPDATE_SLOT_PARAM to updateSlotParam (target params)', () => {
    const updateSlotParam = vi.fn();
    mountMain({ updateSlotParam });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: {
          type: 'CMD_UPDATE_SLOT_PARAM',
          payload: { index: 0, updates: { zoomParam1: 0.42, zoomParam2: 0.8 } },
        },
      } as MessageEvent);
    });

    expect(updateSlotParam).toHaveBeenCalledWith(0, { zoomParam1: 0.42, zoomParam2: 0.8 });
  });

  it('ignores CMD_UPDATE_SLOT_PARAM without index/updates', () => {
    const updateSlotParam = vi.fn();
    mountMain({ updateSlotParam });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_UPDATE_SLOT_PARAM', payload: {} },
      } as MessageEvent);
    });

    expect(updateSlotParam).not.toHaveBeenCalled();
  });

  it('dispatches CMD_LOAD_RANDOM_IMAGE to handleNewRandomImage', () => {
    const handleNewRandomImage = vi.fn(async () => {});
    mountMain({ handleNewRandomImage });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_LOAD_RANDOM_IMAGE' },
      } as MessageEvent);
    });

    expect(handleNewRandomImage).toHaveBeenCalled();
  });

  it('loads CMD_UPLOAD_FILE bytes into the main app (regression: upload was a no-op)', () => {
    const loadLocalMedia = vi.fn(async () => {});
    mountMain({ loadLocalMedia });

    const main = MockBroadcastChannel.instances[0];
    const bytes = new Uint8Array([1, 2, 3, 4]);
    act(() => {
      main!.onmessage?.({
        data: {
          type: 'CMD_UPLOAD_FILE',
          payload: { name: 'clip.mp4', type: 'video', mimeType: 'video/mp4', data: bytes.buffer },
        },
      } as MessageEvent);
    });

    expect(loadLocalMedia).toHaveBeenCalledTimes(1);
    const [blob, kind] = loadLocalMedia.mock.calls[0] as unknown as [Blob, string];
    expect(kind).toBe('video');
    expect(blob.type).toBe('video/mp4');
    expect(blob.size).toBe(bytes.byteLength);
  });

  it('ignores CMD_UPLOAD_FILE with an invalid payload', () => {
    const loadLocalMedia = vi.fn(async () => {});
    mountMain({ loadLocalMedia });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main!.onmessage?.({
        data: { type: 'CMD_UPLOAD_FILE', payload: { type: 'audio', data: 'nope' } },
      } as MessageEvent);
    });

    expect(loadLocalMedia).not.toHaveBeenCalled();
  });
});
