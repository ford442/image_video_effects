/**
 * Browser-side access to the naga WGSL validator (tools/naga_wasm).
 *
 * The artifact is ~800 KB, so it is loaded from /wasm/naga_wasm.wasm on first
 * use and never enters the webpack bundle — the loader is imported with
 * `webpackIgnore`, the same trick src/hooks/useWASM.ts uses for the renderer
 * bridge. Keep it that way or `npm run verify:bundle-size` will regress.
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
  kind?: 'parse' | 'validate' | 'encoding';
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

interface NagaWasmModule {
  createNagaValidator(options?: { bytes?: BufferSource; url?: string }): Promise<NagaValidator>;
}

const LOADER_URL = '/wasm/naga_wasm.js';

let cached: Promise<NagaValidator> | null = null;

/**
 * Resolves to a memoized validator. Concurrent callers share one instantiation;
 * a failed load is not cached, so a transient fetch error can be retried.
 */
export function loadNagaValidator(): Promise<NagaValidator> {
  if (!cached) {
    cached = (async () => {
      const mod: NagaWasmModule = await import(/* webpackIgnore: true */ LOADER_URL);
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
