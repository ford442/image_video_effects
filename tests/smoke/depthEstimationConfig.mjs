/**
 * Shared depth-estimation smoke configuration.
 * Production model used by src/App.tsx loadDepthModel().
 */
export const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';
export const DEPTH_PIPELINE_TASK = 'depth-estimation';

/**
 * Validate depth pipeline output shape/range (matches App.tsx consumption).
 * Does NOT validate WebGPU — CPU/WASM tier only documents tensor contract.
 */
export function assertDepthOutput(output, label = 'depth') {
  if (!output || !output.predicted_depth) {
    throw new Error(`${label}: missing predicted_depth`);
  }
  const { data, dims } = output.predicted_depth;
  if (!dims || dims.length < 2) {
    throw new Error(`${label}: predicted_depth.dims must be at least 2-D, got ${JSON.stringify(dims)}`);
  }
  if (!data || typeof data.length !== 'number' || data.length === 0) {
    throw new Error(`${label}: predicted_depth.data empty`);
  }
  let finite = 0;
  let nonNegative = 0;
  for (let i = 0; i < Math.min(data.length, 4096); i++) {
    const v = data[i];
    if (Number.isFinite(v)) finite++;
    if (v >= 0) nonNegative++;
  }
  if (finite === 0) {
    throw new Error(`${label}: no finite depth values in sample`);
  }
  if (nonNegative === 0) {
    throw new Error(`${label}: depth values should be non-negative in sample`);
  }
  return { dims, dataLength: data.length };
}
