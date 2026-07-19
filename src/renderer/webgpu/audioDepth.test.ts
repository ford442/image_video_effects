import {
  createAudioDepthState,
  updateAudioData,
  updateAudioFrequencyBins,
  writeExtraBuffer,
} from './audioDepth';
import { AUDIO_FFT_BINS, EXTRA_FLOATS, EXTRA_BIN_OFFSET } from './webgpuConstants';

describe('audioDepth', () => {
  it('writes bass/mid/treble and historyHead at correct extraBuffer offsets', () => {
    const state = createAudioDepthState();
    updateAudioData(state, 0.1, 0.5, 0.9);
    state.historyHead = 3;

    const bins = new Float32Array(AUDIO_FFT_BINS);
    bins[0] = 0.25;
    bins[127] = 0.75;
    updateAudioFrequencyBins(state, bins);

    const device = {
      queue: { writeBuffer: jest.fn() },
    } as unknown as GPUDevice;
    const extraBuf = {} as GPUBuffer;

    writeExtraBuffer(device, extraBuf, state);

    expect(device.queue.writeBuffer).toHaveBeenCalledTimes(1);
    const written = (device.queue.writeBuffer as jest.Mock).mock.calls[0][2] as Float32Array;
    expect(written.length).toBe(EXTRA_FLOATS);
    expect(written[0]).toBeCloseTo(0.1);
    expect(written[1]).toBeCloseTo(0.5);
    expect(written[2]).toBeCloseTo(0.9);
    expect(written[4]).toBe(3);
    expect(written[EXTRA_BIN_OFFSET]).toBeCloseTo(0.25);
    expect(written[EXTRA_BIN_OFFSET + 127]).toBeCloseTo(0.75);
  });
});
