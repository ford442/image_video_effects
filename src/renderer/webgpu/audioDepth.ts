/**
 * audioDepth.ts
 *
 * Audio FFT bins, depth map upload, and extraBuffer (binding 10) management.
 * Plasma buffer (binding 12) is created in resources.ts; no per-frame CPU writes yet.
 * Mirrors wasm_renderer/audio_depth.cpp.
 */

import { AUDIO_FFT_BINS, EXTRA_BIN_OFFSET, EXTRA_FLOATS } from './webgpuConstants';

export interface AudioDepthState {
  bass: number;
  mid: number;
  treble: number;
  freqBins: Float32Array;
  historyHead: number;
}

export function createAudioDepthState(): AudioDepthState {
  return {
    bass: 0,
    mid: 0,
    treble: 0,
    freqBins: new Float32Array(AUDIO_FFT_BINS),
    historyHead: 0,
  };
}

export function updateAudioData(state: AudioDepthState, bass: number, mid: number, treble: number): void {
  state.bass = bass;
  state.mid = mid;
  state.treble = treble;
}

export function updateAudioFrequencyBins(state: AudioDepthState, bins: Float32Array): void {
  const len = Math.min(bins.length, AUDIO_FFT_BINS);
  state.freqBins.set(bins.subarray(0, len), 0);
  if (len < AUDIO_FFT_BINS) {
    state.freqBins.fill(0, len);
  }
}

const extraScratch = new Float32Array(EXTRA_FLOATS);

/**
 * Flush audio + historyHead into extraBuffer (binding 10).
 * Layout: [0]=bass, [1]=mid, [2]=treble, [3]=reserved, [4]=historyHead, [5..132]=FFT bins.
 */
export function writeExtraBuffer(device: GPUDevice, extraBuf: GPUBuffer, state: AudioDepthState): void {
  extraScratch[0] = state.bass;
  extraScratch[1] = state.mid;
  extraScratch[2] = state.treble;
  extraScratch[3] = 0;
  extraScratch[4] = state.historyHead;
  extraScratch.set(state.freqBins, EXTRA_BIN_OFFSET);
  device.queue.writeBuffer(extraBuf, 0, extraScratch);
}

/**
 * Upload a depth map (one float per pixel) to depthRead texture.
 * Mirrors WASM UpdateDepthMap / audio_depth.cpp.
 */
export function updateDepthMap(
  device: GPUDevice,
  depthRead: GPUTexture,
  data: Float32Array,
  width: number,
  height: number,
  canvasW: number,
  canvasH: number,
): void {
  const dstW = canvasW;
  const dstH = canvasH;
  const copyW = Math.min(width, dstW);
  const copyH = Math.min(height, dstH);

  const buf = new Float32Array(dstW * dstH);
  for (let y = 0; y < copyH; y++) {
    for (let x = 0; x < copyW; x++) {
      buf[y * dstW + x] = data[y * width + x];
    }
  }

  device.queue.writeTexture(
    { texture: depthRead },
    buf,
    { bytesPerRow: dstW * 4, rowsPerImage: dstH },
    [dstW, dstH],
  );
}

export function getAudioData(state: AudioDepthState): {
  bass: number;
  mid: number;
  treble: number;
  freqBins: Float32Array;
} {
  return {
    bass: state.bass,
    mid: state.mid,
    treble: state.treble,
    freqBins: state.freqBins,
  };
}
