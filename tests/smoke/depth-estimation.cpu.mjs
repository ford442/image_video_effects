#!/usr/bin/env node
/**
 * Depth estimation CPU/WASM smoke (standalone Node).
 *
 * Forces single-thread ONNX on CPU backend — validates JS/tensor contract only, NOT WebGPU.
 * Exercises the production model: Xenova/dpt-hybrid-midas
 *
 * Usage: node tests/smoke/depth-estimation.cpu.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pipeline, env, RawImage } from '@xenova/transformers';
import { assertDepthOutput, DEPTH_MODEL_ID, DEPTH_PIPELINE_TASK } from './depthEstimationConfig.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = path.join(__dirname, 'fixtures', 'sample-rgb.png');

async function main() {
  if (!fs.existsSync(FIXTURE)) {
    throw new Error(`Missing fixture: ${FIXTURE}`);
  }

  // Node ORT WASM: single thread avoids onnxruntime threading bugs in CI/VM.
  env.backends.onnx.wasm.numThreads = 1;
  env.useBrowserCache = false;
  env.useFSCache = true;

  console.log(`[depth-cpu-smoke] Loading ${DEPTH_PIPELINE_TASK} / ${DEPTH_MODEL_ID} (device=cpu)...`);
  const estimator = await pipeline(DEPTH_PIPELINE_TASK, DEPTH_MODEL_ID, {
    device: 'cpu',
  });

  const image = await RawImage.read(FIXTURE);
  console.log('[depth-cpu-smoke] Running inference...');
  const output = await estimator(image);
  const stats = assertDepthOutput(output, 'cpu-smoke');
  console.log(
    `[depth-cpu-smoke] OK dims=${JSON.stringify(stats.dims)} len=${stats.dataLength} ` +
      '(WASM-CPU tier — does not prove WebGPU path)'
  );
}

main().catch((err) => {
  console.error('[depth-cpu-smoke] FAILED:', err);
  process.exit(1);
});
