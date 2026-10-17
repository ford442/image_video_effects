/**
 * ShaderCompilation.ts
 *
 * Shader compilation utilities for WebGPU renderer.
 * Handles workgroup size parsing, shader hashing, and compilation with fallback support.
 */

import workgroupDispatchContract from '../contracts/workgroup_dispatch.json';
import {
  analyzeShaderBindings,
  resolveWorkgroupSize,
  type ShaderBindingUsage,
} from '../wasm/bridge/wgslAnalysis';
import { validateBindGroup } from './bindGroupValidator';
import { reportError } from './ErrorHandling';
import { withValidationScope } from './webgpu/validationScope';
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
 * workgroup_dispatch.json. Literals may carry an i/u suffix, a missing y is 1, and
 * module-scope `const` / `override` names resolve. The parser is shared with the
 * WASM bridge (src/wasm/bridge/wgslAnalysis.ts), which sends its result to C++.
 */
export function parseWorkgroupSize(
  wgslSource: string,
  entryPoint: string = 'main',
): { x: number; y: number } {
  const size = resolveWorkgroupSize(wgslSource, entryPoint);
  if (size) return size;
  console.warn('[WebGPU] Could not parse workgroup_size from shader, defaulting to 16x16');
  return {
    x: workgroupDispatchContract.unparsedFallback.x,
    y: workgroupDispatchContract.unparsedFallback.y,
  };
}

export type { ShaderBindingUsage };
/**
 * Which optional per-frame texture copies a shader actually needs (dataTexA/B→C
 * feedback, the history ring, depth write). Shared with the WASM bridge.
 */
export { analyzeShaderBindings };

/** Conservative usage assumed when a shader's source was never analyzed. */
export const CONSERVATIVE_BINDING_USAGE: ShaderBindingUsage = {
  writesDataA: true,
  writesDataB: true,
  readsDataC: true,
  usesHistory: true,
  writesDepth: true,
};

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

/**
 * Dawn / Chrome often returns a non-null invalid GPUComputePipeline on a
 * layout vs shader storage-format mismatch without throwing. Cache that object
 * and every frame SetPipeline+Submit logs GPUValidationError (#1205).
 * Capture Validation on create; never return an invalid pipeline.
 */
export async function createComputePipelineWithValidationScope(
  device: GPUDevice,
  descriptor: GPUComputePipelineDescriptor,
): Promise<{ pipeline: GPUComputePipeline | null; error: GPUError | Error | null }> {
  const result = await withValidationScope(device, () => device.createComputePipeline(descriptor));
  if (result.error) return { pipeline: null, error: result.error };
  if (result.threw || !result.value) {
    const e = result.thrown;
    return { pipeline: null, error: e instanceof Error ? e : new Error(String(e)) };
  }
  return { pipeline: result.value, error: null };
}

/**
 * Create a compute pipeline off the main thread when the device supports it
 * (createComputePipelineAsync compiles in the background and rejects with a
 * GPUPipelineError on validation failure — never yields an invalid pipeline).
 * Falls back to the synchronous create + validation error scope (#1205).
 */
export async function createComputePipelineChecked(
  device: GPUDevice,
  descriptor: GPUComputePipelineDescriptor,
): Promise<{ pipeline: GPUComputePipeline | null; error: GPUError | Error | null }> {
  if (typeof device.createComputePipelineAsync === 'function') {
    try {
      return { pipeline: await device.createComputePipelineAsync(descriptor), error: null };
    } catch (e) {
      return { pipeline: null, error: e instanceof Error ? e : new Error(String(e)) };
    }
  }
  return createComputePipelineWithValidationScope(device, descriptor);
}

export async function compileShader(
  device: GPUDevice,
  pipelineLayout: GPUPipelineLayout,
  id: string,
  wgsl: string,
  pipelines: Map<string, GPUComputePipeline>,
  pipelineHashes: Map<string, string>,
  workgroupSizes: Map<string, { x: number; y: number }>,
  colorFormat: InternalColorFormat = 'rgba32float',
): Promise<boolean> {
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

  const bannerSkip = (detail: string) => {
    reportError({
      type: 'shader-compile',
      message: `Shader "${id}" failed to compile. ${detail}`,
      recoverable: true,
    });
  };

  // Try to compile the requested shader only if validation passed
  if (validation.valid) {
    try {
      // Scoped so a broken module is reported here, not again through uncapturederror.
      const moduleResult = await withValidationScope(device, () =>
        device.createShaderModule({ label: id, code: compiledWgsl }),
      );
      const module = moduleResult.value;
      if (!module || moduleResult.threw || moduleResult.error) {
        throw moduleResult.error ?? moduleResult.thrown ?? new Error('createShaderModule failed');
      }

      if (typeof module.getCompilationInfo === 'function') {
        module.getCompilationInfo().then((info) => {
          const errors = info.messages.filter((m) => m.type === 'error');
          if (errors.length > 0) {
            console.warn(`[WebGPU] Shader '${id}' compilation warnings:`, errors);
          }
        }).catch(() => { /* device lost / test mocks */ });
      }

      const created = await createComputePipelineChecked(device, {
        label: id,
        layout: pipelineLayout,
        compute: { module, entryPoint: 'main' },
      });

      if (created.pipeline) {
        pipelines.set(id, created.pipeline);
        pipelineHashes.set(id, cacheKey);
        workgroupSizes.set(id, wgSize);
        return true;
      }

      console.warn(`[WebGPU] Shader compile failed (${id}):`, created.error);
      bannerSkip('Trying fallback pass-through shader.');
    } catch (e) {
      console.warn(`[WebGPU] Shader compile failed (${id}):`, e);
      bannerSkip('Trying fallback pass-through shader.');
    }
  }

  // Fallback only if its Validation scope is clean — never cache an invalid pipeline.
  try {
    const fallbackResult = await withValidationScope(device, () =>
      device.createShaderModule({ label: `${id}-fallback`, code: fallbackWgsl }),
    );
    const fallbackModule = fallbackResult.value;
    if (!fallbackModule || fallbackResult.threw || fallbackResult.error) {
      throw fallbackResult.error ?? fallbackResult.thrown ?? new Error('fallback createShaderModule failed');
    }
    const created = await createComputePipelineChecked(device, {
      label: `${id}-fallback`,
      layout: pipelineLayout,
      compute: { module: fallbackModule, entryPoint: 'main' },
    });
    if (created.pipeline) {
      pipelines.set(id, created.pipeline);
      pipelineHashes.set(id, cacheKey);
      workgroupSizes.set(id, parseWorkgroupSize(FALLBACK_WGSL, 'main'));
      console.log(`[WebGPU] Using fallback shader for '${id}'`);
      return true;
    }
    console.error(`[WebGPU] Fallback shader also failed:`, created.error);
    bannerSkip('Slot skipped — pipeline not submitted.');
    return false;
  } catch (fallbackError) {
    console.error(`[WebGPU] Fallback shader also failed:`, fallbackError);
    bannerSkip('Slot skipped — pipeline not submitted.');
    return false;
  }
}
