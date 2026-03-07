/**
 * Shader API Service
 * Handles shader CRUD operations and Shadertoy imports
 */

const API_BASE = process.env.REACT_APP_API_BASE_URL || 'http://localhost:7860';

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
