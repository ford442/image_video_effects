import { Renderer, RendererConfig } from './Renderer';

export class JSRenderer implements Renderer {
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private config: RendererConfig;
  private video: HTMLVideoElement | null = null;
  private image: HTMLImageElement | null = null;
  private animationId: number | null = null;
  private showDebugInfo: boolean = true;

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

    // Canvas size already set by WebGPUCanvas, don't override it
    console.log(`✅ JS Renderer initialized with canvas size: ${canvas.width}x${canvas.height}`);
    this.startRenderLoop();
    return true;
  }

  setVideo(video: HTMLVideoElement): void {
    this.video = video;
    this.image = null; // Clear image when video is set
  }

  updateVideoFrame(): void {
    // Video is sampled directly in render loop
  }

  async loadImage(url: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        this.image = img;
        this.video = null; // Clear video when image is loaded
        console.log(`✅ JSRenderer: Image loaded ${img.width}x${img.height}`);
        resolve(url);
      };
      img.onerror = (err) => {
        console.error('❌ JSRenderer: Failed to load image:', err);
        reject(err);
      };
      img.src = url;
    });
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

  render = (): void => {
    if (!this.ctx || !this.canvas) {
      console.warn('🚨 JSRenderer.render: Missing context or canvas!', {
        ctx: this.ctx ? 'present' : 'NULL',
        canvas: this.canvas ? `${this.canvas.width}x${this.canvas.height}` : 'NULL'
      });
      return;
    }

    // Clear - use solid black to ensure we see rendering
    this.ctx.fillStyle = '#000000';
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // Draw image if available
    if (this.image && this.image.complete) {
      // Maintain aspect ratio
      const canvasAspect = this.canvas.width / this.canvas.height;
      const imageAspect = this.image.width / this.image.height;
      
      let drawWidth = this.canvas.width;
      let drawHeight = this.canvas.height;
      let offsetX = 0;
      let offsetY = 0;
      
      if (imageAspect > canvasAspect) {
        // Image is wider - fit to height
        drawHeight = this.canvas.height;
        drawWidth = this.canvas.height * imageAspect;
        offsetX = (this.canvas.width - drawWidth) / 2;
      } else {
        // Image is taller - fit to width
        drawWidth = this.canvas.width;
        drawHeight = this.canvas.width / imageAspect;
        offsetY = (this.canvas.height - drawHeight) / 2;
      }
      
      this.ctx.drawImage(this.image, offsetX, offsetY, drawWidth, drawHeight);
    }

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
    if (this.showDebugInfo) {
      this.ctx.fillStyle = '#00ff00';
      this.ctx.font = '16px monospace';
      this.ctx.fillText(`✓ Rendering (${this.canvas.width}x${this.canvas.height})`, 10, 30);
      this.ctx.font = '14px monospace';
      this.ctx.fillText(`Audio: ${(audioIntensity * 100).toFixed(1)}%`, 10, 60);
      this.ctx.fillText(`Agents: ${this.config.agentCount}`, 10, 80);
      this.ctx.fillText(`Mouse: ${this.params.mouseX.toFixed(2)}, ${this.params.mouseY.toFixed(2)}`, 10, 100);
      if (this.image) {
        this.ctx.fillText(`Image: ${this.image.width}x${this.image.height}`, 10, 120);
      } else if (this.video) {
        this.ctx.fillText(`Video: ${this.video.videoWidth}x${this.video.videoHeight}`, 10, 120);
      } else {
        this.ctx.fillText('No input source', 10, 120);
      }
    }
  };

  private startRenderLoop(): void {
    let frameCount = 0;
    const loop = () => {
      this.render();
      frameCount++;
      // Log once per 60 frames to avoid spam
      if (frameCount % 60 === 0) {
        console.log(`🎨 JSRenderer: ${frameCount} frames rendered, canvas: ${this.canvas?.width}x${this.canvas?.height}, ctx: ${this.ctx ? 'OK' : 'NULL'}`);
      }
      this.animationId = requestAnimationFrame(loop);
    };
    loop();
  }

  destroy(): void {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
  }
}
