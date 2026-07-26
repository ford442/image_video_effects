/**
 * Shader API Service
 * Handles shader CRUD operations and Shadertoy imports
 */

import { STORAGE_API_URL, API_BASE_URL, SHADER_FILES_BASE_URL } from '../config/appConfig';
import { inferRequiresRgba32Float } from '../config/formatPolicy';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';
import { fetchShaderWgsl } from '../utils/fetchShaderWgsl';
import { postShaderRating } from './postShaderRating';

const API_BASE = process.env.REACT_APP_API_BASE_URL || API_BASE_URL;

// --- Types ---

export interface ShaderMetadata {
  id: string;
  name: string;
  author: string;
  date: string;
  type: 'shader';
  description: string;
  filename: string;
  tags: string[];
  /** Deprecated: backend now uses `stars` (aggregate average). Kept for backward compat. */
  rating: number | null;
  /** Aggregate star rating average (0–5) from the backend. */
  stars?: number;
  /** Number of ratings submitted. */
  rating_count?: number;
  /** Total play count. */
  play_count?: number;
  thumbnail_url?: string;
  source: 'shadertoy' | 'upload' | 'created';
  original_id?: string;
  format?: 'glsl' | 'wgsl';
  converted?: boolean;
  glsl_code?: string;
  /** Shader parameter definitions (local manifest / shader-lists). */
  params?: ShaderParam[];
  /** Feature flags from shader definition JSON (e.g. audio-reactive). */
  features?: string[];
}

export interface ShaderImportResult {
  success: boolean;
  id: string;
  name: string;
  meta: ShaderMetadata;
}

export interface ShaderContent {
  id: string;
  content: string;
  type: 'wgsl' | 'glsl';
}

export interface RendererStatus {
  backends: string[];
  default: string;
  wasm_available: boolean;
  wasm_module_url: string;
  wasm_memory_required: number;
}

// --- TintWASM Converter ---

/**
 * Convert GLSL shader code to WGSL using official TintWASM
 */
export async function glslToWgsl(glsl: string, stage: 'fragment' | 'vertex' = 'fragment'): Promise<string> {
  // @ts-ignore CDN module has no type declarations
  const { init } = await import('https://cdn.jsdelivr.net/npm/@webgpu/tint-wasm@latest/dist/tint.js');
  const tint = await init();
  const result = await tint.convertGLSLToWGSL(glsl, stage);
  if (result.error) throw new Error(result.error);
  return result.wgsl;
}

// Alias for backward compatibility
export const convertGlslToWgsl = glslToWgsl;

/**
 * Check if TintWASM is available
 */
export function isTintAvailable(): boolean {
  // Tint availability is determined by whether WebAssembly is supported
  return typeof WebAssembly !== 'undefined';
}

// --- Shadertoy Helpers ---

/**
 * Extract shader ID from various Shadertoy URL formats
 */
export function extractShaderId(urlOrId: string): string | null {
  // Direct ID (e.g., "4dXGRn")
  if (/^[a-zA-Z0-9]+$/.test(urlOrId) && urlOrId.length <= 10) {
    return urlOrId;
  }
  
  // Full URL patterns
  const patterns = [
    /shadertoy\.com\/view\/([a-zA-Z0-9]+)/,
    /shadertoy\.com\/embed\/([a-zA-Z0-9]+)/,
    /shadertoy\.com\/media\/shaders\/([a-zA-Z0-9]+)/,
  ];
  
  for (const pattern of patterns) {
    const match = urlOrId.match(pattern);
    if (match) return match[1];
  }
  
  return null;
}

/** @deprecated Use convertShadertoyGlsl from shadertoyToPixelocity.ts */
export { wrapShadertoyGlsl } from './shadertoyToPixelocity';

// --- API Functions ---

/**
 * Import a shader from Shadertoy
 */
export async function importFromShadertoy(shaderId: string, apiKey: string): Promise<ShaderImportResult> {
  const form = new FormData();
  form.append('shader_id', shaderId);
  form.append('api_key', apiKey);
  
  const res = await fetch(`${API_BASE}/api/shaders/import/shadertoy`, {
    method: 'POST',
    body: form,
  });
  
  if (!res.ok) {
    const err = await res.json();
    throw new Error(err.detail || 'Import failed');
  }
  
  return res.json();
}

/**
 * List all shaders
 */
export async function listShaders(): Promise<ShaderMetadata[]> {
  const res = await fetch(`${API_BASE}/api/shaders`);
  if (!res.ok) throw new Error('Failed to list shaders');
  return res.json();
}

/**
 * Get a shader's WGSL code by ID.
 * Calls the `/code` endpoint which returns `{id, code, name}` and maps it
 * to the legacy `ShaderContent` shape `{id, content, type}`.
 */
export async function getShader(shaderId: string): Promise<ShaderContent> {
  const res = await fetch(`${API_BASE}/api/shaders/${shaderId}/code`);
  if (!res.ok) throw new Error('Shader not found');
  const { id, code } = await res.json() as { id: string; code: string; name?: string };
  return { id, content: code, type: 'wgsl' };
}

/**
 * Upload a shader file.
 * Backend endpoint: POST /api/shaders/upload (multipart/form-data)
 */
export async function uploadShader(
  file: File,
  name: string,
  author: string,
  description: string = '',
  tags: string = '',
  thumbnail?: File
): Promise<ShaderImportResult> {
  const form = new FormData();
  form.append('file', file);
  form.append('name', name);
  form.append('author', author);
  form.append('description', description);
  form.append('tags', tags);
  if (thumbnail) form.append('thumbnail', thumbnail);
  
  const res = await fetch(`${API_BASE}/api/shaders/upload`, {
    method: 'POST',
    body: form,
  });
  
  if (!res.ok) throw new Error('Upload failed');
  return res.json();
}

/**
 * Update shader metadata.
 * Backend accepts a JSON body (MetaPatch model) via PUT /api/shaders/{id}.
 */
export async function updateShaderMetadata(
  shaderId: string,
  updates: Partial<Pick<ShaderMetadata, 'name' | 'description' | 'tags'>>
): Promise<{ success: boolean; id: string }> {
  const body: Record<string, any> = {};
  if (updates.name !== undefined) body.name = updates.name;
  if (updates.tags !== undefined) body.tags = updates.tags;
  
  const res = await fetch(`${API_BASE}/api/shaders/${shaderId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  
  if (!res.ok) throw new Error('Update failed');
  return res.json();
}

/**
 * Rate a shader (1–5 stars).
 * Live API: JSON `{ rating }` via POST /api/shaders/{id}/rate.
 */
export async function rateShader(
  shaderId: string,
  stars: number
): Promise<{ id: string; stars: number; rating_count: number; your_rating: number }> {
  if (stars < 1 || stars > 5) throw new RangeError('Stars must be between 1 and 5');
  return postShaderRating(API_BASE, shaderId, stars);
}

/**
 * Get renderer status
 */
export async function getRendererStatus(): Promise<RendererStatus> {
  const res = await fetch(`${API_BASE}/api/renderer/status`);
  if (!res.ok) throw new Error('Failed to get renderer status');
  return res.json();
}

/**
 * Queue shader for conversion
 */
export async function convertShader(shaderId: string, targetFormat: string = 'wgsl'): Promise<{
  success: boolean;
  id: string;
  conversion: string;
  message: string;
}> {
  const form = new FormData();
  form.append('target_format', targetFormat);
  
  const res = await fetch(`${API_BASE}/api/shaders/${shaderId}/convert`, {
    method: 'POST',
    body: form,
  });
  
  if (!res.ok) throw new Error('Conversion request failed');
  return res.json();
}

// ═══════════════════════════════════════════════════════════════════════════════
//  NEW: VPS Storage API Integration (Added for Contabo backend)
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  VPS Storage API Types
// ═══════════════════════════════════════════════════════════════════════════════

export interface ShaderParam {
  id: string;
  name: string;
  default: number;
  min: number;
  max: number;
  step?: number;
  labels?: string[];
  mapping?: string;
  audio?: 'bass' | 'mid' | 'treble' | 'overall' | { fft: number };
}

export interface ApiShaderEntry {
  id: string;
  name: string;
  filename: string;
  type: string;
  format: string;
  description?: string;
  author?: string;
  date?: string;
  coordinate?: number;
  rating?: number | null;
  has_errors?: boolean;
  category?: string;         // Shader category (e.g., 'image', 'generative', 'distortion')
  tags: string[];
  url?: string;
  /** Shader parameter definitions for UI sliders */
  params?: ShaderParam[];
  /** When true, shader requires @workgroup_size(16,16,4) = 1024-invocation support. */
  requiresDeepWorkgroup?: boolean;
  /** When true, shader samples binding 13 (historyTexture 2d-array ring buffer). */
  requiresHistoryRing?: boolean;
  /** When true, shader requires rgba32float storage (physics / RD sims). */
  requiresRgba32Float?: boolean;
}

export interface ShaderCoordinateData {
  coordinate: number;
  reason: string;
  name: string;
  category: string;
  features: string[];
  tags: string[];
}

// ═══════════════════════════════════════════════════════════════════════════════
//  VPS Storage API Service Class
// ═══════════════════════════════════════════════════════════════════════════════

/** API-only junk entries that should not appear in the shader browser or scanner. */
const JUNK_SHADER_IDS = new Set(['test', 'test-shader-123', 'test-real-shader-456']);

function isJunkShaderEntry(entry: ApiShaderEntry): boolean {
  if (JUNK_SHADER_IDS.has(entry.id)) return true;
  // Uploaded test stubs with no real WGSL backing.
  if (entry.id.startsWith('test-') && (!entry.filename || entry.filename === `${entry.id}.json`)) {
    const name = (entry.name || '').trim().toLowerCase();
    if (name === 'test' || name === entry.id) return true;
  }
  return false;
}

function filterShaderList(entries: ApiShaderEntry[]): ApiShaderEntry[] {
  const filtered = entries.filter((entry) => !isJunkShaderEntry(entry));
  const removed = entries.length - filtered.length;
  if (removed > 0) {
    console.log(`[ShaderApi] Filtered ${removed} junk/test shader entr${removed === 1 ? 'y' : 'ies'}`);
  }
  return filtered;
}

class ShaderApiService {
  private baseUrl: string;
  private cache: Map<string, any>;
  private cacheExpiry: number;
  private lastFetch: number;

  constructor(baseUrl: string = STORAGE_API_URL) {
    this.baseUrl = baseUrl;
    this.cache = new Map();
    this.cacheExpiry = 30 * 60 * 1000; // 30 minutes — shader lists rarely change
    this.lastFetch = 0;
  }

  /**
   * Get shader list from API (API-first with local fallback)
   * Enhanced to fetch individual shader metadata (params) if not in list
   */
  async getShaderList(includeParams: boolean = true): Promise<ApiShaderEntry[]> {
    const cacheKey = includeParams ? 'shaderListWithParams' : 'shaderList';
    const cached = this.cache.get(cacheKey);
    if (cached && Date.now() - this.lastFetch < this.cacheExpiry) {
      return cached;
    }

    try {
      const url = `${this.baseUrl}/api/shaders?all=true`;
      console.log(`[ShaderApi] Fetching from ${url}`);
      const response = await fetch(url);
      if (!response.ok) throw new Error(`API ${response.status}`);
      const responseData = await response.json();
      
      // Handle both array and wrapped response formats
      let data: ApiShaderEntry[];
      if (Array.isArray(responseData)) {
        data = responseData;
      } else if (responseData && typeof responseData === 'object' && Array.isArray(responseData.shaders)) {
        data = responseData.shaders;
      } else {
        throw new TypeError(`API response is not an array or wrapped array, received: ${typeof responseData}`);
      }
      
      console.log(`[ShaderApi] Received ${data.length} shaders from API`);
      
      data = filterShaderList(data);
      
      // Count shaders with real (non-0.5) params
      const withRealParams = data.filter(s => 
        s.params && s.params.length > 0 && s.params.some(p => p.default !== 0.5)
      ).length;
      console.log(`[ShaderApi] Shaders with real defaults: ${withRealParams}`);
      
      // Build URL pointing to the static .wgsl file (nginx serves /files/ with CORS headers)
      // Now uses the dedicated SHADER_FILES_BASE_URL so shader files can live on a
      // different domain from the API backend.
      data.forEach(s => {
        const wgslFilename = s.filename.replace(/\.json$/, '.wgsl');
        s.url = `${SHADER_FILES_BASE_URL.replace(/\/$/, '')}/shaders/${wgslFilename}`;
      });
      
      this.cache.set(cacheKey, data);
      this.lastFetch = Date.now();
      return data;
    } catch (error) {
      console.warn('[ShaderApi] API failed, falling back to local shader definitions:', error);
      // Fallback to local shader_coordinates.json + individual JSON definitions
      return this.loadLocalShadersWithParams();
    }
  }

  /**
   * Enrich shader list with params from individual JSON definitions
   * Fetches params in parallel for shaders that don't have them
   * Uses shader_coordinates.json to resolve category subdirectory paths
   */
  private async enrichShaderParams(shaders: ApiShaderEntry[]): Promise<void> {
    // Simplified: Skip enrichment - rely on API params or hardcoded defaults in App.tsx
    // The backend API now returns params, and App.tsx has SHADER_DEFAULTS for fine-tuning
    console.log(`[ShaderApi] Skipping enrichment - using API params + hardcoded defaults`);
    return;
  }

  /**
   * Load local shaders with params from pre-generated shader-lists JSON files.
   * These files (public/shader-lists/*.json) are generated by generate_shader_lists.js
   * during the prebuild/prestart step and include the full shader definitions with params.
   */
  private async loadLocalShadersWithParams(): Promise<ApiShaderEntry[]> {
    const SHADER_LIST_CATEGORIES = [
      'image', 'generative', 'distortion', 'simulation', 'visual-effects',
      'artistic', 'retro-glitch', 'geometric', 'lighting-effects',
      'liquid-effects', 'interactive-mouse', 'post-processing',
      'advanced-hybrid', 'hybrid',
    ];

    const allShaders: ApiShaderEntry[] = [];

    // Load all category files in parallel from public/shader-lists/
    const results = await Promise.allSettled(
      SHADER_LIST_CATEGORIES.map(async (category) => {
        const response = await fetch(`./shader-lists/${category}.json`);
        if (!response.ok) return [];
        const shaders: any[] = await response.json();
        return shaders.map((shader: any) => ({
          id: shader.id,
          name: shader.name || shader.id,
          filename: `${shader.id}.json`,
          type: 'shader',
          format: 'wgsl',
          description: shader.description || '',
          category: shader.category || category,  // Use shader's own category or the file category
          tags: shader.tags || [],
          url: shader.url ? resolveShaderUrl(shader.url) : resolveShaderUrl(`shaders/${shader.id}.wgsl`),
          requiresDeepWorkgroup: shader.requiresDeepWorkgroup === true,
          requiresHistoryRing: shader.requiresHistoryRing === true,
          requiresRgba32Float: inferRequiresRgba32Float({
            requiresRgba32Float: shader.requiresRgba32Float === true,
            category: shader.category || category,
            tags: shader.tags || [],
          }),
          params: (shader.params || []).map((p: any, idx: number) => ({
            id: p.id || p.name || `param${idx + 1}`,
            name: p.label || p.name || `Parameter ${idx + 1}`,
            default: p.default ?? 0.5,
            min: p.min ?? 0,
            max: p.max ?? 1,
            step: p.step ?? 0.01,
            labels: p.labels,
            mapping: p.mapping,
            audio: p.audio,
          })),
        } as ApiShaderEntry));
      })
    );

    for (const result of results) {
      if (result.status === 'fulfilled') {
        allShaders.push(...result.value);
      }
    }

    if (allShaders.length > 0) {
      console.log(`[ShaderApi] Loaded ${allShaders.length} shaders from local shader-lists (with params)`);
      const withParams = allShaders.filter(s => s.params && s.params.length > 0).length;
      console.log(`[ShaderApi] ${withParams} shaders have params`);
      return allShaders;
    }

    // Ultimate fallback: use shader_coordinates.json (no params, but at least shaders load)
    console.warn('[ShaderApi] No shader-lists found, falling back to shader_coordinates.json (no params)');
    try {
      const response = await fetch('./shader_coordinates.json');
      const coordMap = await response.json();
      return Object.entries(coordMap).map(([id, data]: [string, any]) => ({
        id,
        name: data.name || id,
        filename: `${id}.json`,
        type: 'shader',
        format: 'wgsl',
        description: data.reason,
        coordinate: data.coordinate,
        tags: data.tags || [],
        url: resolveShaderUrl(`shaders/${id}.wgsl`),
      } as ApiShaderEntry));
    } catch (error) {
      console.error('Failed to load local shaders:', error);
      return [];
    }
  }

  /**
   * Get shader code from API or local.
   * Backend: GET /api/shaders/{id}/code → { id, code, name }
   */
  async getShaderCode(shaderId: string): Promise<string> {
    const cached = this.cache.get(`code:${shaderId}`);
    if (cached) return cached;

    const code = await fetchShaderWgsl(shaderId);
    if (!code) throw new Error(`Failed to fetch shader code for ${shaderId}`);
    this.cache.set(`code:${shaderId}`, code);
    return code;
  }

  clearCache() {
    this.cache.clear();
    this.lastFetch = 0;
  }
}

// Singleton
let defaultService: ShaderApiService | null = null;
function getService(): ShaderApiService {
  if (!defaultService) defaultService = new ShaderApiService();
  return defaultService;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  NEW API Exports
// ═══════════════════════════════════════════════════════════════════════════════

export const ShaderApi = {
  getShaderList: () => getService().getShaderList(),
  getShaderCode: (id: string) => getService().getShaderCode(id),
  clearCache: () => getService().clearCache(),
};

// Type aliases for backward compatibility
export type ShaderEntry = ApiShaderEntry;

export default ShaderApi;
