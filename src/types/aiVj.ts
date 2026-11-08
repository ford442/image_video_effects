/**
 * AI VJ / AutoDJ shared types — no ML or runtime imports (safe for main bundle).
 */

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

export interface CaptionResult {
  generated_text: string;
}

export interface ImageCaptionPipeline {
  (url: string, options?: { max_new_tokens?: number }): Promise<CaptionResult[]>;
}

export interface LlmChatCompletion {
  choices: Array<{ message: { content: string | null } }>;
}

export interface LlmEngine {
  chat: {
    completions: {
      create(options: {
        messages: Array<{ role: string; content: string }>;
        temperature?: number;
      }): Promise<LlmChatCompletion>;
    };
  };
}

export interface AutoTransitionConfig {
  source: 'timer' | 'beat';
  intervalMs?: number;
  durationMs: number;
  mode?: 'randomize' | 'cyclePresets';
  beatInput?: 'mic' | 'element';
  mediaElement?: HTMLMediaElement;
}

/** Options for firing the next transition by hand (controller, OSC, the Auto Transition button). */
export interface TriggerTransitionOptions {
  /**
   * Dissolve a shader change from the picture on screen instead of cutting (OSC `crossfade`).
   * Absent keeps today's behavior, so existing MIDI / key bindings do not start fading.
   */
  crossfade?: boolean;
}
