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
  category: string;
  tags: string[];
  description?: string;
  params?: Array<{ id: string; name: string; default: number; min: number; max: number; step?: number }>;
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
  // UPDATED: Now accepts an array of strings for the stack
  private onUpdateStack: (ids: string[]) => void;
  public onUpdateParams?: (params: Record<string, number>[]) => void;
  public getCurrentState: () => { currentImage: ImageRecord | null, currentShader: ShaderRecord | null };

  constructor(
    onNextImage: (url: string) => void,
    // UPDATED Constructor signature
    onUpdateStack: (ids: string[]) => void,
    getCurrentState: () => { currentImage: ImageRecord | null, currentShader: ShaderRecord | null }
  ) {
    this.onNextImage = onNextImage;
    this.onUpdateStack = onUpdateStack;
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

  public async initialize(imageManifest: ImageRecord[], imageSuggestionsUrl: string) {
    if (this.status === 'ready' || this.status === 'loading-models') return;

    this.setStatus('loading-models', 'Starting AI model initialization...');
    
    try {
        this.imageManifest = imageManifest;

        this.setStatus('loading-models', 'Fetching suggestions...');
        try {
            const suggestionsResponse = await fetch(imageSuggestionsUrl);
            const suggestionsMarkdown = await suggestionsResponse.text();
            this.imageThemes = this.parseImageSuggestions(suggestionsMarkdown);
        } catch (e) {
            console.warn("Could not load suggestions, using defaults.");
            this.imageThemes = ["abstract digital art", "neon geometric shapes", "fluid dynamics"];
        }

        this.setStatus('loading-models', 'Loading shader manifest...');
        this.shaderManifest = await Alucinate.buildShaderManifest();

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
      return suggestions.length > 0 ? suggestions : ["vibrant colorful patterns"];
  }

  public static async buildShaderManifest(): Promise<ShaderRecord[]> {
      const files = [
          'advanced-hybrid.json', 'artistic.json', 'distortion.json',
          'generative.json', 'geometric.json', 'image.json',
          'interactive-mouse.json', 'interactive.json', 'lighting-effects.json',
          'liquid-effects.json', 'liquid.json', 'post-processing.json',
          'retro-glitch.json', 'simulation.json', 'visual-effects.json'
      ];

      const responses = await Promise.all(
          files.map(f => fetch(`./shader-lists/${f}`).catch(() => null))
      );

      const arrays = await Promise.all(
          responses.map(async (res, idx) => {
              if (!res || !res.ok) {
                  console.warn(`[Alucinate] Failed to load ${files[idx]}`);
                  return [];
              }
              try {
                  return await res.json();
              } catch {
                  console.warn(`[Alucinate] Invalid JSON in ${files[idx]}`);
                  return [];
              }
          })
      );

      const seen = new Set<string>();
      const manifest: ShaderRecord[] = [];

      for (const arr of arrays) {
          if (!Array.isArray(arr)) continue;
          for (const def of arr) {
              if (!def || !def.id || seen.has(def.id)) continue;
              seen.add(def.id);
              manifest.push({
                  id: def.id,
                  name: def.name || def.id,
                  category: def.category || 'image',
                  tags: Array.isArray(def.tags) ? def.tags : [],
                  description: def.description || '',
                  params: Array.isArray(def.params) ? def.params : []
              });
          }
      }

      console.log(`[Alucinate] Loaded unified manifest: ${manifest.length} shaders`);
      return manifest;
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

  public async generateFromVibe(vibeText: string): Promise<boolean> {
    if (!this.llm || this.status === 'loading-models') return false;
    try {
        this.setStatus('generating', `Vibe: "${vibeText}"`);
        const result = await this.selectShadersFromLLM(vibeText, vibeText);
        if (result) {
            const ids = result.map(r => r.id);
            const params = result.map(r => r.params);
            const readableStack = ids.map(id => {
                const s = this.shaderManifest.find(m => m.id === id);
                return s ? s.name : id;
            }).join(' + ');
            this.setStatus('generating', `Mixing stack: ${readableStack}`);
            this.onUpdateStack(ids);
            if (this.onUpdateParams) {
                this.onUpdateParams(params);
            }
            return true;
        }
        return false;
    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        this.setStatus('error', `Vibe generation failed: ${errorMessage}`);
        console.error('[Alucinate] generateFromVibe error:', error);
        return false;
    }
  }

  private async runCycle() {
    if (!this.isRunning || this.status !== 'ready') return;

    const { currentImage } = this.getCurrentState();
    if (!currentImage || !currentImage.url) {
      console.warn('Alucinate: No current image. Kicking things off with a random one.');
      const firstImage = this.imageManifest[Math.floor(Math.random() * this.imageManifest.length)];
      if (firstImage) this.onNextImage(firstImage.url);
      return; 
    }

    try {
        this.setStatus('generating', 'Analyzing current scene...');
        const caption = await this.generateCaption(currentImage.url);
        if (!caption) {
            this.setStatus('error', 'Failed to generate image caption.');
            // Fallback: Random single shader
            const random = this.shaderManifest[Math.floor(Math.random() * this.shaderManifest.length)];
            this.onUpdateStack([random.id, 'none', 'none']);
            return;
        }
        this.setStatus('generating', `Image caption: "${caption}"`);

        // NEW: Get a full stack with params instead of just IDs
        const shaderStack = await this.selectShadersFromLLM(caption, caption);
        
        if (shaderStack && this.isRunning) {
            const ids = shaderStack.map(s => s.id);
            const params = shaderStack.map(s => s.params);
            const readableStack = ids.map(id => {
                const s = this.shaderManifest.find(m => m.id === id);
                return s ? s.name : id;
            }).join(' + ');
            
            this.setStatus('generating', `Mixing stack: ${readableStack}`);
            this.onUpdateStack(ids);
            if (this.onUpdateParams) {
                this.onUpdateParams(params);
            }
        } else if (this.isRunning) {
            // Fallback
            const random = this.shaderManifest[Math.floor(Math.random() * this.shaderManifest.length)];
            this.onUpdateStack([random.id, 'none', 'none']);
        }
        
        await new Promise(resolve => setTimeout(resolve, 2000));
        if (!this.isRunning) return;

        this.setStatus('generating', 'Dreaming up the next scene...');
        // Use the first shader in the stack for context
        const primaryShaderName = this.shaderManifest.find(s => s.id === (shaderStack ? shaderStack[0].id : ''))?.name || 'effect';
        
        const nextTheme = await this.getNextImageThemeFromLLM(caption, primaryShaderName);
        if (!nextTheme) return; // Keep current image if theme fails
        
        this.setStatus('generating', `Next theme: "${nextTheme}"`);

        const nextImage = this.findBestMatchingImage(nextTheme, currentImage.url);
        
        setTimeout(() => {
            if (this.isRunning) {
                this.onNextImage(nextImage.url);
                this.setStatus('ready', 'Visuals updated. Enjoy the vibe.');
            }
        }, 5000);

    } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        this.setStatus('error', `Cycle error: ${errorMessage}`);
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
  
  private buildCandidateShortlist(caption: string, vibe: string): ShaderRecord[] {
    const text = `${caption} ${vibe}`.toLowerCase();
    const words = new Set(text.split(/\W+/).filter(w => w.length > 2));

    const scored = this.shaderManifest.map(s => {
        let score = 0;
        const tags = s.tags.map(t => t.toLowerCase());
        const desc = (s.description || '').toLowerCase();
        for (const word of words) {
            if (tags.some(t => t.includes(word))) score += 2;
            if (desc.includes(word)) score += 1;
        }
        return { shader: s, score };
    });

    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, 40).map(x => x.shader);
  }

  private async selectShadersFromLLM(caption: string, vibe: string): Promise<Array<{id: string, params: Record<string, number>}> | null> {
    if (!this.llm) return null;
    
    const candidates = this.buildCandidateShortlist(caption, vibe);

    const shaderOptions = candidates
        .map(s => {
            const paramInfo = (s.params || [])
                .map(p => `${p.id}:${p.min}-${p.max}(${p.default})`)
                .join(',');
            return `"${s.id}" (${s.tags.slice(0,2).join(',')})${paramInfo ? ' params:[' + paramInfo + ']' : ''}`;
        })
        .join(', ');

    const prompt = `
You are an expert VJ creating a 3-layer visual effect stack for an image described as: "${caption}".
Your goal is to choose 3 shader IDs (or "none") to combine into a coherent visual style, and suggest parameter values for each.

Roles:
1. Base: The primary effect.
2. Modifier: Distorts or changes the base.
3. Overlay: Adds texture, glitch, or lighting.

Candidate shaders (pick from these): ${shaderOptions}

Respond with a JSON array of 3 objects. Use "none" for empty slots and empty params.
Example: [{"id":"neon-pulse","params":{"speed":0.8,"intensity":0.3}},{"id":"liquid-warp","params":{}},{"id":"none","params":{}}]
Your Selection:
`;

    try {
        const reply = await this.llm.chat.completions.create({ 
            messages: [{ role: "user", content: prompt }],
            temperature: 0.7
        });
        
        const content = reply.choices[0].message.content || "";
        console.log("[Alucinate] LLM Raw Reply:", content);

        // Try object array format first
        const jsonMatch = content.match(/\[.*\]/s);
        if (jsonMatch) {
            try {
                const jsonStr = jsonMatch[0].replace(/'/g, '"');
                const parsed = JSON.parse(jsonStr);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    const result: Array<{id: string, params: Record<string, number>}> = [];
                    for (let i = 0; i < 3; i++) {
                        const item = parsed[i];
                        if (item && typeof item === 'object' && item.id) {
                            const id = item.id;
                            if (id === 'none' || this.shaderManifest.some(s => s.id === id)) {
                                const params: Record<string, number> = {};
                                if (item.params && typeof item.params === 'object') {
                                    for (const [k, v] of Object.entries(item.params)) {
                                        if (typeof v === 'number') params[k] = v;
                                    }
                                }
                                result.push({ id, params });
                            } else {
                                result.push({ id: 'none', params: {} });
                            }
                        } else if (typeof item === 'string') {
                            // Fallback: old string array format
                            result.push({ id: item === 'none' || this.shaderManifest.some(s => s.id === item) ? item : 'none', params: {} });
                        } else {
                            result.push({ id: 'none', params: {} });
                        }
                    }
                    if (result.length > 0) return result;
                }
            } catch (e) {
                console.warn("[Alucinate] Failed to parse LLM object array, falling back to string array.");
            }
        }

        // Fallback: Grab the first 3 valid IDs found in the text
        const allIds = this.shaderManifest.map(s => s.id);
        // eslint-disable-next-line no-useless-escape
        const foundIds = content.split(/[\s,"\[\]{}:]+/).filter(word => allIds.includes(word) || word === 'none');
        
        if (foundIds.length > 0) {
            return [
                { id: foundIds[0] || 'none', params: {} },
                { id: foundIds[1] || 'none', params: {} },
                { id: foundIds[2] || 'none', params: {} }
            ];
        }

        return null;
    } catch (error) {
        console.error('LLM shader selection failed:', error);
        return null;
    }
  }

  private async getNextImageThemeFromLLM(currentCaption: string, currentShader: string): Promise<string | null> {
      if (!this.llm) return null;
      const themeExamples = this.imageThemes.slice(0, 3).join(', ');
      const prompt = `
Context: Last scene was "${currentCaption}" with "${currentShader}" effect.
Task: Describe the next scene in one short sentence. Be creative.
Inspiration: ${themeExamples}.
Next Scene:`;

      try {
          const reply = await this.llm.chat.completions.create({ messages: [{ role: "user", content: prompt}]});
          const choice = reply.choices[0].message.content;
          return choice ? choice.trim() : null;
      } catch (error) {
          console.error('LLM theme suggestion failed:', error);
          return "abstract geometric neon"; 
      }
  }

  private findBestMatchingImage(theme: string, currentUrl: string): ImageRecord {
      const themeWords = new Set(theme.toLowerCase().replace(/[^a-z\s]/g, '').split(/\s+/).filter(w => w.length > 2));
      let bestScore = -1;
      let bestImage: ImageRecord | null = null;

      let candidates = this.imageManifest.filter(image => image.url !== currentUrl);
      if (candidates.length === 0 && this.imageManifest.length > 0) candidates = this.imageManifest;
      if (candidates.length === 0) return { url: currentUrl, tags: [] };

      for (const image of candidates) {
          let score = 0;
          const imageTags = new Set(image.tags.map(t => t.toLowerCase()));
          for (const word of themeWords) {
              if (imageTags.has(word)) score += 2;
          }
          // Bonus for description matching
          if (image.description && themeWords.size > 0) {
              const descWords = image.description.toLowerCase().split(/\s+/);
              for(const word of descWords) if(themeWords.has(word)) score += 1;
          }

          if (score > bestScore) {
              bestScore = score;
              bestImage = image;
          }
      }

      return bestImage || candidates[Math.floor(Math.random() * candidates.length)];
  }
}
