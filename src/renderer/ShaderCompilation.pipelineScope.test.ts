/**
 * #1205: Dawn may return a non-null invalid compute pipeline on a storage-format
 * mismatch without throwing. compileShader must use a Validation error scope and
 * never cache that object (SetPipeline+Submit every frame).
 */

import {
  compileShader,
  createComputePipelineWithValidationScope,
  FALLBACK_WGSL,
} from './ShaderCompilation';
import { reportError, setRendererErrorHandler } from './ErrorHandling';
import type { RendererError } from './ErrorHandling';

const VALID_WGSL = /* wgsl */ `
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  textureStore(writeTexture, global_id.xy, vec4<f32>(0.0));
}
`;

function makeValidationError(message: string): GPUError {
  return { name: 'GPUValidationError', message } as GPUError;
}

function makeDevice(opts: {
  popSequence?: Array<GPUError | null>;
  createThrows?: boolean;
}): GPUDevice {
  const popSequence = opts.popSequence ?? [null];
  let popIdx = 0;
  const createComputePipeline = opts.createThrows
    ? jest.fn(() => {
        throw new Error('createComputePipeline threw');
      })
    : jest.fn(() => ({ label: 'pipeline' } as unknown as GPUComputePipeline));

  return {
    pushErrorScope: jest.fn(),
    popErrorScope: jest.fn(async () => {
      const v = popSequence[Math.min(popIdx, popSequence.length - 1)];
      popIdx += 1;
      return v;
    }),
    createComputePipeline,
    createShaderModule: jest.fn(() => ({
      getCompilationInfo: jest.fn(async () => ({ messages: [] })),
    })),
  } as unknown as GPUDevice;
}

describe('createComputePipelineWithValidationScope', () => {
  it('returns the pipeline when the Validation scope is clean', async () => {
    const device = makeDevice({ popSequence: [null] });
    const res = await createComputePipelineWithValidationScope(device, {
      layout: 'auto',
      compute: { module: {} as GPUShaderModule, entryPoint: 'main' },
    });
    expect(res.pipeline).not.toBeNull();
    expect(res.error).toBeNull();
    expect(device.pushErrorScope).toHaveBeenCalledWith('validation');
  });

  it('does not return a pipeline when the scope reports a GPUValidationError', async () => {
    const device = makeDevice({
      popSequence: [makeValidationError('RGBA32Float vs RGBA16Float')],
    });
    const res = await createComputePipelineWithValidationScope(device, {
      layout: 'auto',
      compute: { module: {} as GPUShaderModule, entryPoint: 'main' },
    });
    expect(res.pipeline).toBeNull();
    expect(res.error).toMatchObject({ name: 'GPUValidationError' });
  });

  it('does not return a pipeline when createComputePipeline throws', async () => {
    const device = makeDevice({ createThrows: true, popSequence: [null] });
    const res = await createComputePipelineWithValidationScope(device, {
      layout: 'auto',
      compute: { module: {} as GPUShaderModule, entryPoint: 'main' },
    });
    expect(res.pipeline).toBeNull();
    expect(res.error).toBeInstanceOf(Error);
  });
});

describe('compileShader validation-scope fail-soft', () => {
  let reported: RendererError[];

  beforeEach(() => {
    reported = [];
    setRendererErrorHandler((e) => {
      reported.push(e);
    });
    jest.spyOn(console, 'warn').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    setRendererErrorHandler((error) => {
      console.error(`[WebGPU Renderer] ${error.type}: ${error.message}`);
    });
    jest.restoreAllMocks();
  });

  it('does not cache an invalid pipeline; uses fallback when fallback scope is clean', async () => {
    const device = makeDevice({
      popSequence: [
        makeValidationError('layout RGBA32Float vs shader RGBA16Float'),
        null,
      ],
    });
    const pipelines = new Map<string, GPUComputePipeline>();
    const hashes = new Map<string, string>();
    const wgs = new Map<string, { x: number; y: number }>();
    const ok = await compileShader(
      device,
      {} as GPUPipelineLayout,
      'fractal-glass-distort',
      VALID_WGSL,
      pipelines,
      hashes,
      wgs,
      'rgba16float',
    );
    expect(ok).toBe(true);
    expect(pipelines.size).toBe(1);
    expect(device.createComputePipeline).toHaveBeenCalledTimes(2);
    expect(reported.some((e) => e.type === 'shader-compile')).toBe(true);
  });

  it('skips the slot when requested and fallback pipelines both fail Validation', async () => {
    const err = makeValidationError('invalid pipeline');
    const device = makeDevice({ popSequence: [err, err] });
    const pipelines = new Map<string, GPUComputePipeline>();
    const hashes = new Map<string, string>();
    const wgs = new Map<string, { x: number; y: number }>();
    const ok = await compileShader(
      device,
      {} as GPUPipelineLayout,
      'fractal-glass-distort',
      VALID_WGSL,
      pipelines,
      hashes,
      wgs,
      'rgba16float',
    );
    expect(ok).toBe(false);
    expect(pipelines.size).toBe(0);
    expect(reported.some((e) => e.type === 'shader-compile' && /skipped/i.test(e.message))).toBe(true);
  });

  it('still compiles FALLBACK_WGSL storage decls onto the allocated color format', () => {
    expect(FALLBACK_WGSL).toContain('rgba32float');
  });
});

describe('reportError banner wiring', () => {
  it('accepts shader-compile errors', () => {
    const seen: RendererError[] = [];
    setRendererErrorHandler((e) => {
      seen.push(e);
    });
    reportError({
      type: 'shader-compile',
      message: 'Slot skipped — pipeline not submitted.',
      recoverable: true,
    });
    expect(seen).toHaveLength(1);
    setRendererErrorHandler((error) => {
      console.error(`[WebGPU Renderer] ${error.type}: ${error.message}`);
    });
  });
});
