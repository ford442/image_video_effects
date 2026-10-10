import { compileCheckWgsl } from './compileCheck';
import { describeScopeFailure, scopeFailed, withErrorScope, withValidationScope } from './validationScope';

function scopedDevice(pops: Array<GPUError | null | Error>) {
  const stack: string[] = [];
  let i = 0;
  const device = {
    pushErrorScope: jest.fn((filter: string) => stack.push(filter)),
    popErrorScope: jest.fn(() => {
      stack.pop();
      const next = pops[Math.min(i++, pops.length - 1)];
      return next instanceof Error ? Promise.reject(next) : Promise.resolve(next ?? null);
    }),
  };
  return { device: device as unknown as GPUDevice & typeof device, stack };
}

const gpuError = (message: string) => ({ message }) as GPUError;

describe('withErrorScope', () => {
  it('returns the value and no error when the scope is clean', async () => {
    const { device, stack } = scopedDevice([null]);
    const r = await withValidationScope(device, () => 42);
    expect(r).toEqual({ value: 42, error: null, threw: false });
    expect(scopeFailed(r)).toBe(false);
    expect(stack).toEqual([]);
  });

  it('captures the scope error without throwing', async () => {
    const { device } = scopedDevice([gpuError('bad usage')]);
    const r = await withErrorScope(device, 'out-of-memory', () => 'tex');
    expect(device.pushErrorScope).toHaveBeenCalledWith('out-of-memory');
    expect(r.value).toBe('tex');
    expect(describeScopeFailure(r)).toBe('bad usage');
  });

  it('pops exactly once when fn throws', async () => {
    const { device, stack } = scopedDevice([null]);
    const r = await withValidationScope(device, () => {
      throw new Error('sync throw');
    });
    expect(r.threw).toBe(true);
    expect(describeScopeFailure(r)).toBe('sync throw');
    expect(device.popErrorScope).toHaveBeenCalledTimes(1);
    expect(stack).toEqual([]);
  });

  it('pops before awaiting an async fn, and reports its rejection', async () => {
    const { device } = scopedDevice([null]);
    let popsWhenAwaited = -1;
    const r = await withValidationScope(device, () => {
      return Promise.resolve().then(() => {
        popsWhenAwaited = device.popErrorScope.mock.calls.length;
        throw new Error('GPUPipelineError');
      });
    });
    expect(popsWhenAwaited).toBe(1);
    expect(r.threw).toBe(true);
    expect(describeScopeFailure(r)).toBe('GPUPipelineError');
  });

  it('treats a rejected pop (device lost) as a failure', async () => {
    const { device } = scopedDevice([new Error('device lost')]);
    const r = await withValidationScope(device, () => 1);
    expect(r.threw).toBe(true);
    expect(scopeFailed(r)).toBe(true);
  });

  it('works on devices without error scopes (reports throws only)', async () => {
    const device = {} as GPUDevice;
    expect(await withValidationScope(device, () => 'ok')).toEqual({ value: 'ok', error: null, threw: false });
    const r = await withValidationScope(device, () => {
      throw new Error('x');
    });
    expect(r.threw).toBe(true);
  });
});

describe('compileCheckWgsl', () => {
  function compileDevice(opts: { messages?: GPUCompilationMessage[]; pops?: Array<GPUError | null>; pipelineRejects?: string }) {
    const { device } = scopedDevice(opts.pops ?? [null]);
    return Object.assign(device, {
      createShaderModule: jest.fn(() => ({
        getCompilationInfo: async () => ({ messages: opts.messages ?? [] }),
      })),
      createComputePipelineAsync: jest.fn(async () => {
        if (opts.pipelineRejects) throw new Error(opts.pipelineRejects);
        return {};
      }),
    });
  }

  it('returns compilation messages and keeps the module error inside a scope', async () => {
    const device = compileDevice({
      messages: [{ type: 'error', lineNum: 3, linePos: 5, message: 'unresolved identifier' } as GPUCompilationMessage],
      pops: [gpuError('Invalid ShaderModule')],
    });
    const out = await compileCheckWgsl(device, 'broken', 'fn main() {}', { layout: {} as GPUPipelineLayout });
    expect(out).toEqual([{ type: 'error', lineNum: 3, linePos: 5, message: 'unresolved identifier' }]);
    expect(device.pushErrorScope).toHaveBeenCalledWith('validation');
    expect(device.createComputePipelineAsync).not.toHaveBeenCalled();
  });

  it('reports "compiles but fails layout" as an error message', async () => {
    const device = compileDevice({ pipelineRejects: 'binding 3 type mismatch' });
    const out = await compileCheckWgsl(device, 'mismatch', 'code', { layout: {} as GPUPipelineLayout });
    expect(out).toEqual([
      { type: 'error', lineNum: 0, linePos: 0, message: 'pipeline layout: binding 3 type mismatch' },
    ]);
  });

  it('skips the pipeline check without a layout', async () => {
    const device = compileDevice({});
    expect(await compileCheckWgsl(device, 'ok', 'code')).toEqual([]);
    expect(device.createComputePipelineAsync).not.toHaveBeenCalled();
  });
});
