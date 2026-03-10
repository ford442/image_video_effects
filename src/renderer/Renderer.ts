// Base renderer interface
export interface Renderer {
  init(canvas: HTMLCanvasElement): Promise<boolean>;
  render(): void;
  destroy(): void;

  // Video input
  setVideo(video: HTMLVideoElement | undefined): void;
  updateVideoFrame(): void;

  // Audio input
  updateAudioData(bass: number, mid: number, treble: number): void;

  // Mouse input
  updateMouse(x: number, y: number): void;

  // Parameters
  setParam(name: string, value: number): void;

  // Added optionally implemented methods used by app
  setImageList?: (urls: string[]) => void;
  updateDepthMap?: (data: Float32Array, width: number, height: number) => void;
  getAvailableModes?: () => any[];
  loadImage?: (url: string) => Promise<string>;
  getFrameImage?: () => string;
  applyMask?: (maskType: string) => void;
  setMaskEnabled?: (enabled: boolean) => void;
  setRecording?: (isRecording: boolean) => void;
  setRecordingMode?: (mode: 'loop' | 'continuous') => void;
}

export interface RendererConfig {
  width: number;
  height: number;
  agentCount: number;
}

export const DEFAULT_CONFIG: RendererConfig = {
  width: 1920,
  height: 1080,
  agentCount: 50000,
};
