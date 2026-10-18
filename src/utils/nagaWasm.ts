/**
 * Browser-side access to the naga WGSL validator (tools/naga_wasm).
 *
 * The artifact is ~800 KB, so it is loaded from /wasm/naga_wasm.wasm on first
 * use and never enters the webpack bundle — the loader is imported with
 * `webpackIgnore` so webpack never bundles it. Keep it that way or
 * `npm run verify:bundle-size` will regress.
 *
 * Validation is GPU-less: no requestAdapter, no requestDevice, no GPUDevice.
 * That is the point — it lets ShaderValidator report a broken shader on a
 * machine where WebGPU is unavailable, and keeps the one-device rule intact.
 *
 * Contract: src/contracts/wgsl_validation.json
 * CI equivalent: npm run verify:naga-wasm
 */

export interface NagaDiagnostic {
  ok: boolean;
  kind?: 'parse' | 'validate' | 'encoding' | 'write';
  /** Full rendered diagnostic, including the source excerpt and a caret line. */
  message?: string;
  /** 1-based line; 0 when naga could not place the error. */
  line?: number;
  /** 1-based column. */
  pos?: number;
}

export interface NagaValidator {
  validate(wgsl: string): NagaDiagnostic;
}

/** naga's GLSL 450 front-end + WGSL writer (the Shadertoy import). */
export interface NagaGlslResult extends NagaDiagnostic {
  /** The translated module when `ok`. */
  wgsl?: string;
}

export interface NagaGlslConverter {
  glslToWgsl(glsl: string, stage?: 'vertex' | 'fragment' | 'compute'): NagaGlslResult;
}

/** One `@group/@binding` global, as naga's IR sees it. */
export interface NagaBinding {
  group: number;
  binding: number;
  name: string;
  resource: 'texture' | 'depth_texture' | 'storage_texture' | 'sampler' | 'uniform' | 'storage' | 'other';
  access: 'read' | 'write' | 'read_write';
  /** '1d' | '2d' | '3d' | 'cube'; '' for non-textures. */
  dim: string;
  arrayed: boolean;
}

export interface NagaEntryPoint {
  name: string;
  stage: string;
  workgroupSize: [number, number, number];
  /**
   * `[group, binding, flags]` for each binding the entry point reaches (flags: naga
   * `GlobalUse` bits, 1 read / 2 write / 4 query / 8 atomic). Absent when the module does not validate.
   */
  uses?: Array<[number, number, number]>;
}

/** Resource reflection (Graph Lab port inference). `ok: false` is a parse error. */
export interface NagaReflection extends NagaDiagnostic {
  valid?: boolean;
  bindings?: NagaBinding[];
  entryPoints?: NagaEntryPoint[];
}

export interface NagaReflector {
  reflect(wgsl: string): NagaReflection;
}

type NagaInstance = NagaValidator & NagaGlslConverter & NagaReflector;

interface NagaWasmModule {
  createNagaValidator(options?: { bytes?: BufferSource; url?: string }): Promise<NagaInstance>;
}

const LOADER_URL = '/wasm/naga_wasm.js';

let cached: Promise<NagaInstance> | null = null;

/**
 * Resolves to a memoized validator. Concurrent callers share one instantiation;
 * a failed load is not cached, so a transient fetch error can be retried.
 */
export function loadNagaValidator(): Promise<NagaValidator> {
  return loadNagaInstance();
}

/** Same memoized instance as loadNagaValidator — one wasm module serves both. */
export function loadNagaGlslConverter(): Promise<NagaGlslConverter> {
  return loadNagaInstance();
}

/** Same memoized instance; needs an artifact built with `wgsl_reflect`. */
export function loadNagaReflector(): Promise<NagaReflector> {
  return loadNagaInstance();
}

function loadNagaInstance(): Promise<NagaInstance> {
  if (!cached) {
    cached = (async () => {
      const mod: NagaWasmModule = await import(/* webpackIgnore: true */ /* @vite-ignore */ LOADER_URL);
      return mod.createNagaValidator();
    })().catch((err) => {
      cached = null;
      throw err;
    });
  }
  return cached;
}

/** Test seam: drops the memoized instance. */
export function resetNagaValidatorForTests(): void {
  cached = null;
}

/**
 * Formats a diagnostic the way ShaderValidator renders GPU compilation errors,
 * so both paths read the same in the results table.
 */
export function formatNagaError(diag: NagaDiagnostic): string {
  const headline =
    diag.message
      ?.split('\n')
      .find((l) => l.startsWith('error:'))
      ?.replace(/^error:\s*/, '')
      .trim() ?? 'naga rejected this shader';
  return diag.line ? `L${diag.line}:${diag.pos ?? 0} — ${headline}` : headline;
}
