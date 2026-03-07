// Base renderer interface
export interface Renderer {
  init(canvas: HTMLCanvasElement): Promise<boolean>;
  render(): void;
  destroy(): void;
  
  // Video input
  setVideo(video: HTMLVideoElement): void;
  updateVideoFrame(): void;
  
  // Audio input
  updateAudioData(bass: number, mid: number, treble: number): void;
  
  // Mouse input
  updateMouse(x: number, y: number): void;
  
  // Parameters
  setParam(name: string, value: number): void;
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
