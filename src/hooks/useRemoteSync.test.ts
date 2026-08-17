import { renderHook, act } from '@testing-library/react';
import { useRemoteSync } from './useRemoteSync';
import { SYNC_CHANNEL_NAME } from '../syncTypes';

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
        setMode: jest.fn(),
        setActiveSlot: jest.fn(),
        updateSlotParam: handlers.updateSlotParam ?? jest.fn(),
        setShaderCategory: jest.fn(),
        syncInputSourceToRenderer: jest.fn(),
        setAutoChangeEnabled: jest.fn(),
        setAutoChangeDelay: jest.fn(),
        handleNewRandomImage: jest.fn(),
        loadDepthModel: jest.fn(),
        setSelectedVideo: jest.fn(),
        setIsMuted: jest.fn(),
        ...handlers,
      }),
    );
  }

  it('dispatches CMD_RANDOMIZE_SLOT to handleRandomizeSlot', () => {
    const handleRandomizeSlot = jest.fn();
    mountMain({ handleRandomizeSlot });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main.onmessage?.({
        data: { type: 'CMD_RANDOMIZE_SLOT', payload: 0 },
      } as MessageEvent);
    });

    expect(handleRandomizeSlot).toHaveBeenCalledWith(0);
  });

  it('dispatches CMD_ROULETTE to triggerRoulette', () => {
    const triggerRoulette = jest.fn();
    mountMain({ triggerRoulette });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main.onmessage?.({
        data: { type: 'CMD_ROULETTE' },
      } as MessageEvent);
    });

    expect(triggerRoulette).toHaveBeenCalled();
  });

  it('dispatches CMD_RANDOMIZE_ALL_SLOTS', () => {
    const triggerRandomizeAllSlots = jest.fn();
    mountMain({ triggerRandomizeAllSlots });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main.onmessage?.({
        data: { type: 'CMD_RANDOMIZE_ALL_SLOTS' },
      } as MessageEvent);
    });

    expect(triggerRandomizeAllSlots).toHaveBeenCalled();
  });

  it('dispatches CMD_UPDATE_SLOT_PARAM to updateSlotParam (target params)', () => {
    const updateSlotParam = jest.fn();
    mountMain({ updateSlotParam });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main.onmessage?.({
        data: {
          type: 'CMD_UPDATE_SLOT_PARAM',
          payload: { index: 0, updates: { zoomParam1: 0.42, zoomParam2: 0.8 } },
        },
      } as MessageEvent);
    });

    expect(updateSlotParam).toHaveBeenCalledWith(0, { zoomParam1: 0.42, zoomParam2: 0.8 });
  });

  it('ignores CMD_UPDATE_SLOT_PARAM without index/updates', () => {
    const updateSlotParam = jest.fn();
    mountMain({ updateSlotParam });

    const main = MockBroadcastChannel.instances[0];
    act(() => {
      main.onmessage?.({
        data: { type: 'CMD_UPDATE_SLOT_PARAM', payload: {} },
      } as MessageEvent);
    });

    expect(updateSlotParam).not.toHaveBeenCalled();
  });
});
