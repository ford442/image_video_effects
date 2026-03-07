import { Renderer, RendererConfig } from './Renderer';

export class JSRenderer implements Renderer {
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private animationId: number | null = null;
  
  // Sim params
  private params = {
    sensorAngle: Math.PI / 4,
    sensorDist: 9,
    turnSpeed: 0.1,
    decayRate: 0.95,
    depositAmount: 0.5,
    videoFoodStrength: 0.3,
    audioPulseStrength: 0.5,
    mouseAttraction: 0.5,
    mouseX: 0.5,
    mouseY: 0.5,
    audioBass: 0,
    audioMid: 0,
    audioTreble: 0,
  };

  constructor(config: RendererConfig) {
    this.config = config;
  }

  async init(canvas: HTMLCanvasElement): Promise<boolean> {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    
    if (!this.ctx) {
      console.error('❌ Could not get 2D context');
      return false;
    }

    // Set canvas size
    canvas.width = this.config.width;
    canvas.height = this.config.height;

    console.log('✅ JS Renderer initialized');
    this.startRenderLoop();
    return true;
  }

  setVideo(video: HTMLVideoElement): void {
    this.video = video;
  }

  updateVideoFrame(): void {
    // Video is sampled directly in render loop
  }

  updateAudioData(bass: number, mid: number, treble: number): void {
    this.params.audioBass = bass;
    this.params.audioMid = mid;
    this.params.audioTreble = treble;
  }

  updateMouse(x: number, y: number): void {
    this.params.mouseX = x;
    this.params.mouseY = y;
  }

  setParam(name: string, value: number): void {
    if (name in this.params) {
      (this.params as any)[name] = value;
    }
  }

  private render = (): void => {
    if (!this.ctx || !this.canvas) return;

    // Clear
    this.ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // Draw video if available
    if (this.video && this.video.readyState >= 2) {
      this.ctx.drawImage(this.video, 0, 0, this.canvas.width, this.canvas.height);
    }

    // Visual feedback for audio
    const audioIntensity = (this.params.audioBass + this.params.audioMid + this.params.audioTreble) / 3;
    const radius = 50 + audioIntensity * 200;
    
    // Mouse position indicator
    const mx = this.params.mouseX * this.canvas.width;
    const my = this.params.mouseY * this.canvas.height;
    
    this.ctx.beginPath();
    this.ctx.arc(mx, my, radius, 0, Math.PI * 2);
    this.ctx.strokeStyle = `rgba(100, 255, 100, ${0.3 + audioIntensity * 0.7})`;
    this.ctx.lineWidth = 2;
    this.ctx.stroke();

    // Status text
    this.ctx.fillStyle = '#00ff00';
    this.ctx.font = '14px monospace';
    this.ctx.fillText(`Audio: ${(audioIntensity * 100).toFixed(1)}%`, 10, 20);
    this.ctx.fillText(`Agents: ${this.config.agentCount}`, 10, 40);
    this.ctx.fillText(`Mouse: ${this.params.mouseX.toFixed(2)}, ${this.params.mouseY.toFixed(2)}`, 10, 60);
  };

  private startRenderLoop(): void {
    const loop = () => {
      this.render();
      this.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  render(): void {
    // Handled by render loop
  }

  destroy(): void {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
  }
}
