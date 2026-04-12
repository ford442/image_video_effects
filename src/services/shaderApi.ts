/**
 * Shader API Service
 * Handles shader CRUD operations and Shadertoy imports
 */

import { STORAGE_API_URL, API_BASE_URL } from '../config/appConfig';

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
  rating: number | null;
  source: 'shadertoy' | 'upload' | 'created';
  original_id?: string;
  format?: 'glsl' | 'wgsl';
  converted?: boolean;
  glsl_code?: string;
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

/**
 * Convert Shadertoy's mainImage to a WGSL compute shader
 * This is a simplified conversion - full conversion requires TintWASM
 */
export function wrapShadertoyGlsl(glslCode: string, uniforms: string = ''): string {
  return `
// Auto-generated WGSL wrapper for Shadertoy shader
// Original GLSL is preserved in comments for reference

struct Uniforms {
  resolution: vec2<f32>,
  time: f32,
  mouse: vec4<f32>,
  frame: i32,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Shadertoy compatibility functions
fn iResolution() -> vec2<f32> { return u.resolution; }
fn iTime() -> f32 { return u.time; }
fn iMouse() -> vec4<f32> { return u.mouse; }
fn iFrame() -> i32 { return u.frame; }

// Sample from previous frame (for buffers)
fn iChannel0(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, uv, 0.0);
}

${uniforms}

// Converted mainImage function will be inserted here
// Original GLSL:
/*
${glslCode.substring(0, 2000)}
*/

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let uv = vec2<f32>(id.xy) / u.resolution;
  var fragColor: vec4<f32>;
  var fragCoord = vec2<f32>(id.xy);
  
  // mainImage(fragColor, fragCoord) equivalent:
  // TODO: Insert converted WGSL code here
  
  fragColor = vec4<f32>(uv, 0.5 + 0.5 * sin(u.time), 1.0);
  
  textureStore(writeTexture, vec2<i32>(id.xy), fragColor);
}
`;
}

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
 * Get a shader by ID
 */
export async function getShader(shaderId: string): Promise<ShaderContent> {
  const res = await fetch(`${API_BASE}/api/shaders/${shaderId}`);
  if (!res.ok) throw new Error('Shader not found');
  return res.json();
}

/**
 * Upload a shader file
 */
export async function uploadShader(
  file: File,
  name: string,
  author: string,
  description: string = '',
  tags: string = ''
): Promise<ShaderImportResult> {
  const form = new FormData();
  form.append('file', file);
  form.append('name', name);
  form.append('author', author);
  form.append('description', description);
  form.append('tags', tags);
  
  const res = await fetch(`${API_BASE}/api/shaders`, {
    method: 'POST',
    body: form,
  });
  
  if (!res.ok) throw new Error('Upload failed');
  return res.json();
}

/**
 * Update shader metadata
 */
export async function updateShaderMetadata(
  shaderId: string,
  updates: Partial<Pick<ShaderMetadata, 'name' | 'description' | 'tags' | 'rating'>>
): Promise<{ success: boolean; id: string }> {
  const form = new FormData();
  if (updates.name) form.append('name', updates.name);
  if (updates.description) form.append('description', updates.description);
  if (updates.tags) form.append('tags', Array.isArray(updates.tags) ? updates.tags.join(',') : updates.tags);
  if (updates.rating !== undefined && updates.rating !== null) form.append('rating', updates.rating.toString());
  
  const res = await fetch(`${API_BASE}/api/shaders/${shaderId}`, {
    method: 'PUT',
    body: form,
  });
  
  if (!res.ok) throw new Error('Update failed');
  return res.json();
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
  params?: ShaderParam[];  // Shader parameter definitions for UI sliders
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
      const url = `${this.baseUrl}/api/shaders${includeParams ? '?include_params=true' : ''}`;
      console.log(`[ShaderApi] Fetching from ${url}`);
      const response = await fetch(url);
      if (!response.ok) throw new Error(`API ${response.status}`);
      const data: ApiShaderEntry[] = await response.json();
      
      console.log(`[ShaderApi] Received ${data.length} shaders from API`);
      
      // Count shaders with real (non-0.5) params
      const withRealParams = data.filter(s => 
        s.params && s.params.length > 0 && s.params.some(p => p.default !== 0.5)
      ).length;
      console.log(`[ShaderApi] Shaders with real defaults: ${withRealParams}`);
      
      // Build URL pointing to the static .wgsl file (nginx serves /files/ with CORS headers)
      data.forEach(s => {
        const wgslFilename = s.filename.replace(/\.json$/, '.wgsl');
        s.url = `${this.baseUrl}/files/image-effects/shaders/${wgslFilename}`;
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
          url: shader.url ? `./${shader.url}` : `./shaders/${shader.id}.wgsl`,
          params: (shader.params || []).map((p: any, idx: number) => ({
            id: p.id || p.name || `param${idx + 1}`,
            name: p.label || p.name || `Parameter ${idx + 1}`,
            default: p.default ?? 0.5,
            min: p.min ?? 0,
            max: p.max ?? 1,
            step: p.step ?? 0.01,
            labels: p.labels,
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
        url: `./shaders/${id}.wgsl`,
      } as ApiShaderEntry));
    } catch (error) {
      console.error('Failed to load local shaders:', error);
      return [];
    }
  }

  /**
   * Get shader code from API or local
   */
  async getShaderCode(shaderId: string): Promise<string> {
    const cached = this.cache.get(`code:${shaderId}`);
    if (cached) return cached;

    try {
      const response = await fetch(`${this.baseUrl}/api/shaders/${shaderId}/wgsl`);
      if (!response.ok) throw new Error('API error');
      const code = await response.text();
      this.cache.set(`code:${shaderId}`, code);
      return code;
    } catch (error) {
      const response = await fetch(`./shaders/${shaderId}.wgsl`);
      return await response.text();
    }
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
