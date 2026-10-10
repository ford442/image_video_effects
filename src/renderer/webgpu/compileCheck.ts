/**
 * Compile-check WGSL on an existing device without leaking validation errors to
 * `uncapturederror` (#1395). One implementation for the renderer's compileCheck
 * RPC, the shader compile service fallback, and ShaderValidator.
 */

import { withValidationScope } from './validationScope';

export interface CompileCheckMessage {
  type: GPUCompilationMessageType;
  lineNum: number;
  linePos: number;
  message: string;
}

export interface CompileCheckOptions {
  /**
   * When set and the module has no errors, also build a `main` compute pipeline
   * against this layout, so "compiles but does not fit the bind group" is reported.
   */
  layout?: GPUPipelineLayout;
  entryPoint?: string;
}

function messageFromError(message: string): CompileCheckMessage {
  return { type: 'error', lineNum: 0, linePos: 0, message };
}

export async function compileCheckWgsl(
  device: GPUDevice,
  id: string,
  code: string,
  options: CompileCheckOptions = {},
): Promise<CompileCheckMessage[]> {
  let module: GPUShaderModule | undefined;
  const scoped = await withValidationScope(device, () => {
    module = device.createShaderModule({ label: id, code });
    return module.getCompilationInfo();
  });
  if (scoped.threw && !scoped.value) {
    const e = scoped.thrown;
    return [messageFromError(e instanceof Error ? e.message : String(e))];
  }
  const messages: CompileCheckMessage[] = (scoped.value?.messages ?? []).map((m) => ({
    type: m.type,
    lineNum: m.lineNum,
    linePos: m.linePos,
    message: m.message,
  }));
  const hasError = messages.some((m) => m.type === 'error');
  // A module error is already in `messages`; only report the scope error when it adds something.
  if (scoped.error && !hasError) messages.push(messageFromError(scoped.error.message));
  if (hasError || scoped.error || !options.layout || !module) return messages;

  const layout = options.layout;
  const shaderModule = module;
  const pipeline = await withValidationScope(device, () => {
    const descriptor: GPUComputePipelineDescriptor = {
      label: `${id}-compile-check`,
      layout,
      compute: { module: shaderModule, entryPoint: options.entryPoint ?? 'main' },
    };
    return typeof device.createComputePipelineAsync === 'function'
      ? device.createComputePipelineAsync(descriptor)
      : device.createComputePipeline(descriptor);
  });
  const failure = pipeline.error?.message
    ?? (pipeline.threw ? String((pipeline.thrown as Error | undefined)?.message ?? pipeline.thrown) : null);
  if (failure) messages.push(messageFromError(`pipeline layout: ${failure}`));
  return messages;
}
