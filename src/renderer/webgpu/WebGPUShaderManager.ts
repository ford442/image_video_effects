/**
 * WebGPUShaderManager.ts
 *
 * Shader loading, compilation, and pipeline cache for the WebGPU renderer.
 */

import { compileShader } from '../ShaderCompilation';
import { resolveShaderUrl } from '../../utils/resolveShaderUrl';
import { fetchShaderWgsl } from '../../utils/fetchShaderWgsl';

export class WebGPUShaderManager {
  private pipelines = new Map<string, GPUComputePipeline>();
  private pipelineHashes = new Map<string, string>();
  private workgroupSizes = new Map<string, { x: number; y: number }>();

  getPipeline(id: string): GPUComputePipeline | undefined {
    return this.pipelines.get(id);
  }

  hasPipeline(id: string): boolean {
    return this.pipelines.has(id);
  }

  getWorkgroupSize(id: string): { x: number; y: number } {
    return this.workgroupSizes.get(id) || { x: 8, y: 8 };
  }

  getCacheStats(): { cachedCount: number; cachedIds: string[] } {
    return {
      cachedCount: this.pipelines.size,
      cachedIds: Array.from(this.pipelines.keys()),
    };
  }

  clear(): void {
    this.pipelines.clear();
    this.pipelineHashes.clear();
    this.workgroupSizes.clear();
  }

  compile(
    device: GPUDevice,
    pipelineLayout: GPUPipelineLayout,
    id: string,
    wgsl: string,
  ): boolean {
    return compileShader(
      device,
      pipelineLayout,
      id,
      wgsl,
      this.pipelines,
      this.pipelineHashes,
      this.workgroupSizes,
    );
  }

  async loadShader(
    device: GPUDevice | null,
    pipelineLayout: GPUPipelineLayout | null,
    supportsSubgroups: boolean,
    id: string,
    url: string,
  ): Promise<boolean> {
    if (!device || !pipelineLayout) return false;

    const resolvedUrl = resolveShaderUrl(url);

    if (supportsSubgroups && !id.endsWith('-sg') && resolvedUrl.endsWith('.wgsl')) {
      const sgUrl = resolvedUrl.replace(/\.wgsl$/, '-sg.wgsl');
      const sgWgsl = await fetchShaderWgsl(`${id}-sg`, sgUrl);
      if (sgWgsl) {
        const ok = this.compile(device, pipelineLayout, id, sgWgsl);
        if (ok) {
          if (process.env.NODE_ENV !== 'production') {
            console.log(`[WebGPU] "${id}": loaded subgroup variant (-sg.wgsl)`);
          }
          return true;
        }
      }
      if (process.env.NODE_ENV !== 'production') {
        console.log(`[WebGPU] "${id}": no -sg variant found, using base variant`);
      }
    }

    const wgsl = await fetchShaderWgsl(id, url);
    if (!wgsl) return false;
    return this.compile(device, pipelineLayout, id, wgsl);
  }

  async preloadShader(
    device: GPUDevice | null,
    pipelineLayout: GPUPipelineLayout | null,
    supportsSubgroups: boolean,
    id: string,
    url: string,
  ): Promise<boolean> {
    return this.loadShader(device, pipelineLayout, supportsSubgroups, id, url);
  }
}
