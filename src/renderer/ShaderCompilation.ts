/**
 * ShaderCompilation.ts
 *
 * Shader compilation utilities for WebGPU renderer.
 * Handles workgroup size parsing, shader hashing, and compilation with fallback support.
 */

import workgroupDispatchContract from '../contracts/workgroup_dispatch.json';
import { validateBindGroup } from './bindGroupValidator';
import { reportError } from './ErrorHandling';
import type { InternalColorFormat } from '../config/formatPolicy';
import {
  pipelineCacheKey,
  rewriteWgslStorageFormats,
  rewriteWgslStorageFormatsChecked,
} from './wgslFormatRewrite';

/**
 * Simple hash function for WGSL source code
 * Used to detect when shader content changes for cache invalidation
 */
export function hashWgsl(code: string): string {
  let hash = 5381;
  for (let i = 0; i < code.length; i++) {
    hash = ((hash << 5) + hash + code.charCodeAt(i)) | 0;
  }
  return hash.toString(36) + ':' + code.length;
}

/**
 * Parse @workgroup_size(x, y) from WGSL source to determine dispatch dimensions.
 *
 * The renderer only ever dispatches a single entry point (`main`), so when a
 * shader declares multiple compute entry points this must return the
 * @workgroup_size belonging to that entry point — not the first one in the
 * file (a 1D helper kernel like `@workgroup_size(64, 1, 1) fn update_boids`
 * would otherwise corrupt the 2D dispatch of `main`). Falls back to the first
 * match if the requested entry point is not found, then to canonical 16×16 from
 * workgroup_dispatch.json.
 */
export function parseWorkgroupSize(
  wgslSource: string,
  entryPoint: string = 'main',
): { x: number; y: number } {
  // Per-entry-point scan: @compute @workgroup_size(x, y[, z]) fn <name>(
  const entryRe =
    /@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)[^)]*\)\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)/g;
  let firstMatch: RegExpExecArray | null = null;
  let m: RegExpExecArray | null;
  while ((m = entryRe.exec(wgslSource)) !== null) {
    if (!firstMatch) firstMatch = m;
    if (m[3] === entryPoint) {
      return { x: parseInt(m[1], 10), y: parseInt(m[2], 10) };
    }
  }
  if (firstMatch) {
    return { x: parseInt(firstMatch[1], 10), y: parseInt(firstMatch[2], 10) };
  }

  // Fallback: search for @workgroup_size anywhere after @compute
  const computeIdx = wgslSource.indexOf('@compute');
  if (computeIdx !== -1) {
    const afterCompute = wgslSource.slice(computeIdx);
    const match2 = afterCompute.match(/@workgroup_size\(\s*(\d+)\s*,\s*(\d+)/);
    if (match2) {
      return { x: parseInt(match2[1], 10), y: parseInt(match2[2], 10) };
    }
  }

  console.warn('[WebGPU] Could not parse workgroup_size from shader, defaulting to 16x16');
  return {
    x: workgroupDispatchContract.unparsedFallback.x,
    y: workgroupDispatchContract.unparsedFallback.y,
  };
}

/**
 * Which optional per-frame texture copies a shader actually needs.
 * Drives skipping of dataTexA/B→C feedback copies and the history-ring copy
 * in the render loop when the bound shader never touches those resources.
 */
export interface ShaderBindingUsage {
  writesDataA: boolean;
  writesDataB: boolean;
  readsDataC: boolean;
  usesHistory: boolean;
}

/** Conservative usage assumed when a shader's source was never analyzed. */
export const CONSERVATIVE_BINDING_USAGE: ShaderBindingUsage = {
  writesDataA: true,
  writesDataB: true,
  readsDataC: true,
  usesHistory: true,
};

function bindingVarName(wgsl: string, binding: number): string | null {
  const m = wgsl.match(
    new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)\\s*var(?:<[^>]*>)?\\s+([A-Za-z_][A-Za-z0-9_]*)`),
  );
  return m ? m[1] : null;
}

function usedBeyondDeclaration(wgsl: string, binding: number): boolean {
  const hasBinding = new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)`).test(wgsl);
  if (!hasBinding) return false;
  const name = bindingVarName(wgsl, binding);
  // Declared but unparseable name: assume used (conservative).
  if (!name) return true;
  const refs = wgsl.match(new RegExp(`\\b${name}\\b`, 'g'));
  return (refs?.length ?? 0) > 1;
}

/**
 * Statically determine which feedback resources a shader uses, by variable
 * name bound at each binding slot (names may be aliased, so the declaration
 * is parsed rather than assuming canonical names). Errs on the side of
 * "used" whenever the source is ambiguous.
 */
export function analyzeShaderBindings(wgsl: string): ShaderBindingUsage {
  return {
    writesDataA: usedBeyondDeclaration(wgsl, 7),
    writesDataB: usedBeyondDeclaration(wgsl, 8),
    readsDataC: usedBeyondDeclaration(wgsl, 9),
    usesHistory: usedBeyondDeclaration(wgsl, 13),
  };
}

/**
 * Fallback compute shader used when the requested shader fails to compile
 * Simple pass-through with slight red tint to indicate fallback mode
 */
export const FALLBACK_WGSL = /* wgsl */ `
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(textureDimensions(readTexture));
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    let fallbackColor = vec4<f32>(
        min(color.r * 1.1, 1.0),
        color.g * 0.9,
        color.b * 0.9,
        color.a
    );
    
    textureStore(writeTexture, global_id.xy, fallbackColor);
}
`;

/**
 * Compiles a compute shader with validation and fallback support
 * @param device GPU device for compilation
 * @param pipelineLayout Bind group layout for the compute pipeline
 * @param id Shader identifier
 * @param wgsl WGSL source code
 * @param pipelines Cache map for compiled pipelines
 * @param pipelineHashes Cache map for shader content hashes
 * @param workgroupSizes Cache map for parsed workgroup sizes
 * @returns true if compilation succeeded, false otherwise
 */
export interface FormatRewriteWarning {
  shaderId: string;
  colorFormat: InternalColorFormat;
  missed: string[];
}

const formatRewriteWarnings = new Map<string, FormatRewriteWarning>();

function recordFormatRewriteWarning(warning: FormatRewriteWarning): void {
  formatRewriteWarnings.set(`${warning.shaderId}:${warning.colorFormat}`, warning);
}

/** Storage-format rewrite misses seen so far (diagnostics / HUD / benches). */
export function getFormatRewriteWarnings(): FormatRewriteWarning[] {
  return Array.from(formatRewriteWarnings.values());
}

export function clearFormatRewriteWarnings(): void {
  formatRewriteWarnings.clear();
}

export function compileShader(
  device: GPUDevice,
  pipelineLayout: GPUPipelineLayout,
  id: string,
  wgsl: string,
  pipelines: Map<string, GPUComputePipeline>,
  pipelineHashes: Map<string, string>,
  workgroupSizes: Map<string, { x: number; y: number }>,
  colorFormat: InternalColorFormat = 'rgba32float',
): boolean {
  const cacheKey = pipelineCacheKey(wgsl, colorFormat);
  // Fast path: shader already cached AND content unchanged
  if (pipelines.has(id) && pipelineHashes.get(id) === cacheKey) {
    return true;
  }

  // Validate bind-group compatibility BEFORE attempting pipeline creation
  const validation = validateBindGroup(id, wgsl);
  if (!validation.valid) {
    console.warn(
      `[WebGPU] Shader "${id}" failed bind-group validation (${validation.errors.length} errors). ` +
        `Using fallback pass-through shader.`
    );
    // Skip directly to fallback below
  }

  // Fail soft: a storage declaration the rewrite could not reach would make the pipeline
  // disagree with the host-allocated textures. Compile the partially rewritten source
  // (strictly closer to the allocated formats than the original) and record the miss so
  // it surfaces in diagnostics instead of as an opaque pipeline error.
  const rewrite = rewriteWgslStorageFormatsChecked(wgsl, colorFormat);
  if (rewrite.missed.length > 0) {
    recordFormatRewriteWarning({
      shaderId: id,
      colorFormat,
      missed: rewrite.missed,
    });
    console.warn(
      `[WebGPU] Shader "${id}": ${rewrite.missed.length} storage declaration(s) not rewritten ` +
        `to ${colorFormat} (${rewrite.missed.join(', ')}). Pipeline may mismatch allocated textures.`,
    );
  }
  const compiledWgsl = rewrite.wgsl;
  const fallbackWgsl = rewriteWgslStorageFormats(FALLBACK_WGSL, colorFormat);

  // Parse workgroup size from shader source (entry point `main` — the only
  // entry point the renderer dispatches)
  const wgSize = parseWorkgroupSize(wgsl, 'main');

  // Try to compile the requested shader only if validation passed
  if (validation.valid) {
    try {
      const module = device.createShaderModule({ label: id, code: compiledWgsl });

      // Check for compilation errors using compilationInfo
      module.getCompilationInfo().then((info) => {
        const errors = info.messages.filter((m) => m.type === 'error');
        if (errors.length > 0) {
          console.warn(`[WebGPU] Shader '${id}' compilation warnings:`, errors);
        }
      });

      const pipeline = device.createComputePipeline({
        label: id,
        layout: pipelineLayout,
        compute: { module, entryPoint: 'main' },
      });

      pipelines.set(id, pipeline);
      pipelineHashes.set(id, cacheKey);
      workgroupSizes.set(id, wgSize);
      return true;
    } catch (e) {
      console.warn(`[WebGPU] Shader compile failed (${id}):`, e);

      reportError({
        type: 'shader-compile',
        message: `Shader "${id}" failed to compile. Using fallback pass-through shader.`,
        recoverable: true,
      });
    }
  }

  // Try to use fallback shader (reached on validation failure OR pipeline creation failure)
  try {
    const fallbackModule = device.createShaderModule({
      label: `${id}-fallback`,
      code: fallbackWgsl,
    });
    const fallbackPipeline = device.createComputePipeline({
      label: `${id}-fallback`,
      layout: pipelineLayout,
      compute: { module: fallbackModule, entryPoint: 'main' },
    });
    pipelines.set(id, fallbackPipeline);
    pipelineHashes.set(id, cacheKey);
    workgroupSizes.set(id, parseWorkgroupSize(FALLBACK_WGSL, 'main'));
    console.log(`[WebGPU] Using fallback shader for '${id}'`);
    return true;
  } catch (fallbackError) {
    console.error(`[WebGPU] Fallback shader also failed:`, fallbackError);
    return false;
  }
}
