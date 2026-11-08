/**
 * simRingArm.ts
 *
 * Arms the shared SimRing for one freshly compiled group-1 shader. Lives next
 * to the ring (not on WebGPURenderer) so the hash policy has one home: a shader
 * that declares simHash only loads when its definition asked for the hash, and
 * only a shader that declares it makes the ring allocate one.
 */

import type { WebGPUPipelineModule } from './pipeline';
import type { SimRing } from './simRing';

/**
 * @param requested   simRing.stateCount for this shader / graph (undefined → contract default)
 * @param askedForHash the definition set `simRing.spatialHash`
 * @returns false when the ring (or the hash it was asked for) could not be armed
 */
export async function armSimRingFor(
  device: GPUDevice,
  pipeline: WebGPUPipelineModule,
  ring: SimRing,
  id: string,
  requested: number | undefined,
  askedForHash: boolean,
): Promise<boolean> {
  const layout = pipeline.simRingBindGroupLayout;
  if (!layout) return false;

  if (!pipeline.shaderManager.usesSimHash(id)) {
    return ring.ensure(device, layout, requested);
  }
  if (!askedForHash) {
    console.warn(`[SimRing] "${id}" declares simHash but its definition does not set simRing.spatialHash`);
    return false;
  }
  const build = pipeline.getSimHashBuildResources();
  const hashLayout = pipeline.simRingHashBindGroupLayout;
  if (!build || !hashLayout) return false;
  const armed = await ring.ensure(device, layout, requested, {
    layout: hashLayout,
    buildLayout: build.bindGroupLayout,
  });
  return armed && ring.hashAllocated;
}
