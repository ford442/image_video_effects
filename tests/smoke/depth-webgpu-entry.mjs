/**
 * Browser entry for Playwright WebGPU depth smoke.
 * Bundled by tests/depth-estimation.webgpu.spec.ts via esbuild.
 */
import { pipeline, env, RawImage } from '@xenova/transformers';
import { assertDepthOutput, DEPTH_MODEL_ID, DEPTH_PIPELINE_TASK } from './depthEstimationConfig.mjs';

export async function runDepthWebgpuSmoke(imageUrl) {
  env.backends.onnx.wasm.numThreads = 1;
  env.useBrowserCache = true;

  const estimator = await pipeline(DEPTH_PIPELINE_TASK, DEPTH_MODEL_ID, {
    device: 'webgpu',
  });

  const image = await RawImage.fromURL(imageUrl);
  const output = await estimator(image);
  return assertDepthOutput(output, 'webgpu-smoke');
}
