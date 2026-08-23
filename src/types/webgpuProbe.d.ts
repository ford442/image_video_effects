import type { WebGpuProbeSerializable } from '../renderer/webgpuBootProbe';

declare global {
  interface Window {
    webgpuProbe?: WebGpuProbeSerializable;
  }
}

export {};
