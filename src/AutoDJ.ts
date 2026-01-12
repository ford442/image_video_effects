
import { pipeline, env } from '@xenova/transformers';
import * as webllm from "@mlc-ai/web-llm";

// --- Configuration ---
env.allowLocalModels = false;
const CAPTIONER_ID = 'Xenova/vit-gpt2-image-captioning';
const LLM_ID = 'gemma-2-2b-it-q4f32_1-MLC';

// --- Interfaces ---
export interface ImageRecord {
  url: string;
  tags: string[];
  description?: string;
}

export interface ShaderRecord {
  id: string;
  name: string;
  tags: string[];
  description?: string;
}

export type AIStatus = 'idle' | 'loading-models' | 'ready' | 'generating' | 'error';

// --- The AI VJ Director Class ---
export class Alucinate {
  // Manifests & Suggestions
  private imageManifest: ImageRecord[] = [];
  private shaderManifest: ShaderRecord[] = [];
  private imageThemes: string[] = [];

  // AI Models
  private captioner: any = null;
  private llm: webllm.MLCEngine | null = null;

  // State
  private loopInterval: number | null = null;
  private isRunning = false;
  public status: AIStatus = 'idle';
  public statusMessage: string = "AI Not Initialized";
  public onStatusChange: ((status: AIStatus, message: string) => void) | null = null;
  
  // Callbacks
  private onNextImage: (url: string) => void;
  private onNextShader: (id: string) => void;
  public getCurrentState: () => { currentImage: ImageRecord | null, currentShader: ShaderRecord | null };

  constructor(
    onNextImage: (url: string) => void,
    onNextShader: (id: string) => void,
    getCurrentState: () => { currentImage: ImageRecord | null, currentShader: ShaderRecord | null }
  ) {
    this.onNextImage = onNextImage;
    this.onNextShader = onNextShader;
    this.getCurrentState = getCurrentState;
  }

  private setStatus(status: AIStatus, message: string) {
    this.status = status;
    this.statusMessage = message;
    console.log(`[Alucinate] Status: ${status} - ${message}`);
    if (this.onStatusChange) {
        this.onStatusChange(status, message);
    }
  }

  public async initialize(imageManifest: ImageRecord[], shaderDefs: any[], imageSuggestionsUrl: string) {
    if (this.status === 'ready' || this.status === 'loading-models') return;

    this.setStatus('loading-models', 'Starting AI model initialization...');
    
    try {
        this.imageManifest = imageManifest;

        this.setStatus('loading-models', 'Fetching suggestions...');
        const suggestionsResponse = await fetch(imageSuggestionsUrl);
        const suggestionsMarkdown = await suggestionsResponse.text();
        this.imageThemes = this.parseImageSuggestions(suggestionsMarkdown);

        this.shaderManifest = shaderDefs
            .filter(def => def.tags && def.tags.length > 0)
            .map(def => ({
                id: def.id,
                name: def.name,
                tags: def.tags || [],
                description: def.description || '' 
            }));

        this.setStatus('loading-models', 'Loading image captioning model...');
        this.captioner = await pipeline('image-to-text', CAPTIONER_ID, {
             progress_callback: (progress: any) => {
                this.setStatus('loading-models', `Captioner: ${progress.status} (${(progress.progress || 0).toFixed(2)}%)`);
            }
        });

        this.setStatus('loading-models', 'Loading large language model...');
        this.llm = await webllm.CreateMLCEngine(LLM_ID, {
            initProgressCallback: (progress: webllm.InitProgressReport) => {
                this.setStatus('loading-models', `LLM: ${progress.text.replace('[...]', `(${(progress.progress * 100).toFixed(2)}%)`)}`);
            },
            appConfig: {
                model_list: [
                    {
                        "model": "https://huggingface.co/mlc-ai/gemma-2-2b-it-q4f32_1-MLC",
                        "model_id": "gemma-2-2b-it-q4f32_1-MLC",
                        "model_lib": "https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/v0_2_80/gemma-2-2b-it-q4f32_1-ctx4k_cs1k-webgpu.wasm",
                    }
                ]
            }
        });

        this.setStatus('ready', 'AI models initialized successfully.');
    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        this.setStatus('error', `Initialization failed: ${errorMessage}`);
        console.error("Failed to initialize Alucinate:", error);
    }
  }

  private parseImageSuggestions(markdown: string): string[] {
      const suggestions: string[] = [];
      const promptRegex = /- \*\*Prompt:\*\*\s*"(.*?)"/g;
      let match;
      while ((match = promptRegex.exec(markdown)) !== null) {
          suggestions.push(match[1]);
      }
      return suggestions;
  }

  public start(): boolean {
    if (this.isRunning) return false;
    if (this.status !== 'ready') {
        console.warn('Alucinate is not ready. Please initialize models first.');
        this.setStatus('idle', 'Cannot start: AI not initialized.');
        return false;
    }
    console.log('Starting Alucinate loop...');
    this.isRunning = true;
    this.runCycle(); 
    this.loopInterval = window.setInterval(() => this.runCycle(), 25000);
    return true;
  }

  public stop() {
    if (!this.isRunning || this.loopInterval === null) return;
    console.log('Stopping Alucinate loop.');
    this.isRunning = false;
    clearInterval(this.loopInterval);
    this.loopInterval = null;
    if (this.status === 'generating') {
        this.setStatus('ready', 'AI VJ stopped.');
    }
  }

  private async runCycle() {
    if (!this.isRunning || this.status !== 'ready') return;

    const { currentImage, currentShader } = this.getCurrentState();
    if (!currentImage || !currentImage.url) {
      console.warn('Alucinate: No current image. Kicking things off with a random one.');
      const firstImage = this.imageManifest[Math.floor(Math.random() * this.imageManifest.length)];
      this.onNextImage(firstImage.url);
      return; 
    }

    try {
        this.setStatus('generating', 'Analyzing current scene...');
        const caption = await this.generateCaption(currentImage.url);
        if (!caption) {
            this.setStatus('error', 'Failed to generate image caption.');
            this.onNextShader(this.shaderManifest[Math.floor(Math.random() * this.shaderManifest.length)].id);
            return;
        }
        this.setStatus('generating', `Image caption: "${caption}"`);

        const nextShaderId = await this.getShaderFromLLM(caption);
        const nextShader = this.shaderManifest.find(s => s.id === nextShaderId);
        if (nextShaderId && this.isRunning) {
            this.setStatus('generating', `LLM selected shader: ${nextShader?.name || nextShaderId}`);
            this.onNextShader(nextShaderId);
        } else if (this.isRunning) {
            const randomShader = this.shaderManifest[Math.floor(Math.random() * this.shaderManifest.length)];
            console.warn(`[Alucinate] LLM failed to select a shader. Picking random: ${randomShader.name}`);
            this.onNextShader(randomShader.id);
        }
        
        await new Promise(resolve => setTimeout(resolve, 2000));
        if (!this.isRunning) return;

        this.setStatus('generating', 'Dreaming up the next scene...');
        const nextTheme = await this.getNextImageThemeFromLLM(caption, nextShader?.name || 'a visual effect');
        if (!nextTheme) {
            this.setStatus('error', 'LLM failed to suggest a new theme.');
            return;
        }
        this.setStatus('generating', `Next theme: "${nextTheme}"`);

        const nextImage = this.findBestMatchingImage(nextTheme, currentImage.url);
        console.log(`[Alucinate] Best match for next image: ${nextImage.url}`);
        
        setTimeout(() => {
            if (this.isRunning) {
                this.onNextImage(nextImage.url);
                this.setStatus('ready', 'Visuals updated. Enjoy the vibe.');
            }
        }, 5000);

    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        this.setStatus('error', `An error occurred during the cycle: ${errorMessage}`);
        console.error('[Alucinate] runCycle error:', error);
        this.stop();
    }
  }

  private async generateCaption(imageUrl: string): Promise<string | null> {
    if (!this.captioner) return null;
    try {
        const result = await this.captioner(imageUrl, { max_new_tokens: 30 });
        return result[0]?.generated_text || null;
    } catch (error) {
        console.error('Caption generation failed:', error);
        return null;
    }
  }
  
  private async getShaderFromLLM(caption: string): Promise<string | null> {
    if (!this.llm) return null;
    const shaderOptions = this.shaderManifest.map(s => `ID: "${s.id}", Name: "${s.name}", Tags: [${s.tags.join(', ')}]`).join('\n');
    const prompt = `You are an expert AI VJ selecting a visual effect ("shader") to match an image. The image is described as: "${caption}". Based on that description, pick the best shader from the following list. Respond with ONLY the shader ID of your choice, and nothing else.
---
 Shader Options ---
${shaderOptions}
---
Your selection (ID only):`;

    try {
        const reply = await this.llm.chat.completions.create({ messages: [{ role: "user", content: prompt }]});
        const choice = reply.choices[0].message.content;
        if (!choice) {
            return null;
        }
        const match = choice.match(/"([^"]+)"/);
        let selectedId = match ? match[1] : choice.trim().split(/\s+/)[0];
        return this.shaderManifest.some(s => s.id === selectedId) ? selectedId : null;
    } catch (error) {
        console.error('LLM shader selection failed:', error);
        return null;
    }
  }

  private async getNextImageThemeFromLLM(currentCaption: string, currentShader: string): Promise<string | null> {
      if (!this.llm) return null;
      const themeExamples = this.imageThemes.slice(0, 5).join('\n - ');
      const prompt = `You are an AI VJ creating a visual journey. The last scene was "${currentCaption}" with a "${currentShader}" effect.
What should the next scene be? Be creative and describe a compelling, new visual. Here are some examples for inspiration:
 - ${themeExamples}

Describe the next scene in a single, descriptive sentence.`;

      try {
          const reply = await this.llm.chat.completions.create({ messages: [{ role: "user", content: prompt}]});
          const choice = reply.choices[0].message.content;
          return choice ? choice.trim() : null;
      } catch (error) {
          console.error('LLM theme suggestion failed:', error);
          return "a futuristic city at night"; // Fallback
      }
  }

  private findBestMatchingImage(theme: string, currentUrl: string): ImageRecord {
      const themeWords = new Set(theme.toLowerCase().replace(/[^a-z\s]/g, '').split(/\s+/).filter(w => w.length > 2));
      let bestScore = -1;
      let bestImage: ImageRecord | null = null;

      // Filter out current image to ensure rotation, UNLESS it's the only one.
      let candidates = this.imageManifest.filter(image => image.url !== currentUrl);

      if (candidates.length === 0) {
          // If only one image exists, we must reuse it (or fail gracefully)
          if (this.imageManifest.length > 0) {
               candidates = this.imageManifest;
          } else {
              // Should not happen due to App.tsx fallback, but safety first
              return { url: currentUrl, tags: [], description: 'Fallback' };
          }
      }

      for (const image of candidates) {
          let score = 0;
          const imageTags = new Set(image.tags.map(t => t.toLowerCase()));
          for (const word of themeWords) {
              if (imageTags.has(word)) {
                  score++;
              }
          }
          if (score > 0) {
             score += image.tags.length / 10;
          }

          if (score > bestScore) {
              bestScore = score;
              bestImage = image;
          }
      }

      if (bestImage) {
          return bestImage;
      }
      // Return random if no match found
      return candidates[Math.floor(Math.random() * candidates.length)];
  }
}
