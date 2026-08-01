/**
 * Human-readable WASM init failure descriptions.
 *
 * The C++ renderer reports how far `initWasmRenderer` got as a stage number
 * (see `INIT_STAGE_NAMES` in the bridge / `WebGPURenderer::InitStage` in C++).
 * A bare "init failed" hides the most useful fact: a run that reached Surface and
 * stopped is a very different bug from one that never got an adapter. Tier B triage
 * (WASM_BACKEND_POLICY.md) depends on telling those apart from a user's console paste.
 */

/** Ordered init stages; index is the stage number reported by C++. */
export const WASM_INIT_STAGES = [
  'None',
  'Instance',
  'Adapter',
  'Device',
  'Surface',
  'Resources',
  'BindGroups',
  'Pipeline',
  'Ready',
] as const;

export const WASM_INIT_READY_STAGE = WASM_INIT_STAGES.indexOf('Ready');

export interface WasmInitDiagnosticsInput {
  failedStage?: number;
  failedStageName?: string;
  lastInitError?: string;
  adapterInfo?: string;
  hasModule?: boolean;
  lastLoadError?: string | null;
}

export interface WasmInitFailureDescription {
  /** Single-line summary for console / error reporting. */
  message: string;
  /** Stage number reached (0 when nothing ran). */
  stage: number;
  stageName: string;
  /** True when init got past Device but did not reach Ready — a partial bring-up. */
  partial: boolean;
  /** True when no adapter was ever acquired (the cloud-VM / driver-blocked case). */
  noAdapter: boolean;
  /** Stages that completed before the failure. */
  reached: string[];
  /** Suggested next step for whoever reads the console. */
  hint: string;
}

function stageName(input: WasmInitDiagnosticsInput, stage: number): string {
  if (input.failedStageName && input.failedStageName !== 'None') return input.failedStageName;
  return WASM_INIT_STAGES[stage] ?? `Stage${stage}`;
}

/**
 * Describe a failed `initWasmRenderer` call. Pure — safe to unit test without a GPU.
 */
export function describeWasmInitFailure(
  input: WasmInitDiagnosticsInput = {},
  attempt = 1,
  maxAttempts = 1,
): WasmInitFailureDescription {
  const stage = Math.max(0, Math.min(input.failedStage ?? 0, WASM_INIT_READY_STAGE));
  const name = stageName(input, stage);
  const adapter = (input.adapterInfo ?? '').trim();
  const noAdapter = adapter.length === 0;
  // Device acquired but pipeline never came up: surface/resources/bind-group/pipeline stage.
  const partial = stage >= WASM_INIT_STAGES.indexOf('Surface') && stage < WASM_INIT_READY_STAGE;
  const reached = WASM_INIT_STAGES.slice(1, Math.max(stage, 1));

  let hint: string;
  if (input.hasModule === false) {
    hint =
      'WASM module never loaded — check public/wasm/ artifacts are present and served '
      + '(npm run wasm:validate).';
  } else if (stage <= WASM_INIT_STAGES.indexOf('Adapter') && noAdapter) {
    hint =
      'No WebGPU adapter was acquired. Expected in cloud/headless VMs; on real hardware check '
      + 'chrome://gpu and driver support. This is the Tier B evidence blocker — a run without an '
      + 'adapter proves nothing about WASM performance.';
  } else if (partial) {
    hint =
      `Partial bring-up: reached ${name} with a working device. This is a WASM-side bug, not a `
      + 'missing GPU — capture the C++ console log and file it as a parity bug (Tier B: P1).';
  } else {
    hint = 'Falling back to the TypeScript WebGPU renderer; the app stays usable.';
  }

  const parts = [
    `WASM init failed at stage ${stage}/${WASM_INIT_READY_STAGE} (${name})`,
    `attempt ${attempt}/${maxAttempts}`,
  ];
  if (input.lastInitError) parts.push(`error: ${input.lastInitError}`);
  if (input.lastLoadError) parts.push(`load error: ${input.lastLoadError}`);
  parts.push(`adapter: ${adapter || 'none acquired'}`);
  if (reached.length > 0) parts.push(`reached: ${reached.join(' → ')}`);

  return {
    message: `${parts.join(' · ')}. ${hint}`,
    stage,
    stageName: name,
    partial,
    noAdapter,
    reached: [...reached],
    hint,
  };
}

/** Compact one-line status for the debug panel / diagnostics readout. */
export function summarizeWasmInitState(input: WasmInitDiagnosticsInput & { initialized?: boolean }): string {
  if (input.initialized) {
    return `ready · adapter: ${input.adapterInfo?.trim() || 'unreported'}`;
  }
  const d = describeWasmInitFailure(input);
  return `${d.partial ? 'partial' : 'failed'} at ${d.stageName} · adapter: ${
    input.adapterInfo?.trim() || 'none acquired'
  }`;
}
