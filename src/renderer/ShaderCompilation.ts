/**
 * ShaderCompilation.ts
 *
 * Shader compilation utilities for WebGPU renderer.
 * Handles workgroup size parsing, shader hashing, and compilation with fallback support.
 */

import { validateBindGroup } from './bindGroupValidator';
import { reportError } from './ErrorHandling';

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
 * Parse @workgroup_size(x, y) from WGSL source to determine dispatch dimensions
 * Falls back to 8x8 if parsing fails
 */
export function parseWorkgroupSize(wgslSource: string): { x: number; y: number } {
  // Tolerant: allows whitespace/newlines/comments between @compute and @workgroup_size
  const match = wgslSource.match(/@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)/);
  if (match) {
    return { x: parseInt(match[1], 10), y: parseInt(match[2], 10) };
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

  console.warn('[WebGPU] Could not parse workgroup_size from shader, defaulting to 8x8');
  return { x: 8, y: 8 };
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
export function compileShader(
  device: GPUDevice,
  pipelineLayout: GPUPipelineLayout,
  id: string,
  wgsl: string,
  pipelines: Map<string, GPUComputePipeline>,
  pipelineHashes: Map<string, string>,
  workgroupSizes: Map<string, { x: number; y: number }>,
): boolean {
  // Fast path: shader already cached AND content unchanged
  const contentHash = hashWgsl(wgsl);
  if (pipelines.has(id) && pipelineHashes.get(id) === contentHash) {
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

  // Parse workgroup size from shader source
  const wgSize = parseWorkgroupSize(wgsl);

  // Try to compile the requested shader only if validation passed
  if (validation.valid) {
    try {
      const module = device.createShaderModule({ label: id, code: wgsl });

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
      pipelineHashes.set(id, contentHash);
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
      code: FALLBACK_WGSL,
    });
    const fallbackPipeline = device.createComputePipeline({
      label: `${id}-fallback`,
      layout: pipelineLayout,
      compute: { module: fallbackModule, entryPoint: 'main' },
    });
    pipelines.set(id, fallbackPipeline);
    workgroupSizes.set(id, parseWorkgroupSize(FALLBACK_WGSL));
    console.log(`[WebGPU] Using fallback shader for '${id}'`);
    return true;
  } catch (fallbackError) {
    console.error(`[WebGPU] Fallback shader also failed:`, fallbackError);
    return false;
  }
}
