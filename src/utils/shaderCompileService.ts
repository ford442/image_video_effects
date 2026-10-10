/**
 * shaderCompileService.ts
 *
 * "Compile this WGSL and tell me what the GPU said" for dev tools
 * (ShaderScanner). With the renderer on the page that is the adopted
 * GPUDevice; with the render worker (#1314) there is no page device, so the
 * worker proxy registers an RPC-backed compiler instead. Never creates a
 * second GPUDevice.
 */

import { getAdoptedRendererDevice, getAdoptedSupportsSubgroups } from './adoptedGpuDevice';
import { compileCheckWgsl } from '../renderer/webgpu/compileCheck';

export interface CompileMessageLike {
  type: GPUCompilationMessageType;
  lineNum: number;
  linePos: number;
  message: string;
}

export interface ShaderCompileService {
  supportsSubgroups: boolean;
  compile(id: string, code: string): Promise<CompileMessageLike[]>;
}

let registered: ShaderCompileService | null = null;

/** Register a compiler (the render-worker proxy); returns an unregister function. */
export function registerShaderCompileService(service: ShaderCompileService): () => void {
  registered = service;
  return () => {
    if (registered === service) registered = null;
  };
}

/** The active compiler: the registered one, else the adopted page device, else null. */
export function getShaderCompileService(): ShaderCompileService | null {
  if (registered) return registered;
  const device = getAdoptedRendererDevice();
  if (!device) return null;
  return {
    supportsSubgroups:
      getAdoptedSupportsSubgroups() ||
      device.features.has('subgroups') ||
      device.features.has('chromium-experimental-subgroups' as GPUFeatureName),
    compile: (id, code) => compileCheckWgsl(device, id, code),
  };
}
