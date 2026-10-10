/**
 * fakeGpu.ts
 *
 * Recording fake of the WebGPU device surface the renderer touches, for Jest.
 * Every command encoded through a fake encoder lands in `fake.ops` (in order),
 * tagged with the submit it belongs to, so tests can assert submit counts,
 * bind-group churn, pass labels, timestamp indices and copy order without a GPU.
 *
 * Lives outside __tests__/ on purpose: CRA treats every file there as a suite.
 */

export type FakeTimestampWrites = { begin?: number; end?: number };

export type FakeGpuOp =
  | { op: 'beginComputePass'; label?: string; timestampWrites?: FakeTimestampWrites }
  | { op: 'beginRenderPass'; label?: string; target?: string; timestampWrites?: FakeTimestampWrites }
  | { op: 'setPipeline'; label?: string }
  | { op: 'setBindGroup'; index: number; label?: string }
  | { op: 'dispatch'; x: number; y: number; z: number }
  | { op: 'draw'; count: number }
  | { op: 'endPass' }
  | { op: 'copyTextureToTexture'; from?: string; to?: string; size: number[] }
  | { op: 'copyBufferToBuffer'; from?: string; to?: string; size: number }
  | { op: 'copyTextureToBuffer'; from?: string; to?: string }
  | { op: 'clearBuffer'; buffer?: string }
  | { op: 'resolveQuerySet'; first: number; count: number };

export interface FakeGpuCounters {
  submits: number;
  commandBuffers: number;
  encoders: number;
  createBindGroup: number;
  createView: number;
  importExternalTexture: number;
  createComputePipeline: number;
  createComputePipelineAsync: number;
  createRenderPipeline: number;
  writeBuffer: number;
  writeTexture: number;
  mapAsync: number;
}

export interface FakeGpu {
  device: GPUDevice;
  /** Every encoded command, in encode order. */
  ops: FakeGpuOp[];
  /** Ops grouped per submitted command buffer (encoder label + ops). */
  submitted: Array<{ label?: string; ops: FakeGpuOp[] }>;
  counters: FakeGpuCounters;
  /** Labels of bind groups created, in order (unlabeled → '?'). */
  bindGroupLabels: string[];
  /** Zero all counters and op logs (keeps created resources alive). */
  reset(): void;
  texture(label: string, width?: number, height?: number, layers?: number): GPUTexture;
  buffer(label: string, size?: number): GPUBuffer;
}

type Labeled = { label?: string };

function labelOf(value: unknown): string | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const v = value as { label?: string; texture?: Labeled; buffer?: Labeled };
  return v.label ?? v.texture?.label ?? v.buffer?.label;
}

function timestampWritesOf(desc: unknown): FakeTimestampWrites | undefined {
  const tw = (desc as { timestampWrites?: { beginningOfPassWriteIndex?: number; endOfPassWriteIndex?: number } })
    ?.timestampWrites;
  if (!tw) return undefined;
  return { begin: tw.beginningOfPassWriteIndex, end: tw.endOfPassWriteIndex };
}

/** Install the WebGPU usage-flag globals Jest's jsdom lacks (idempotent). */
export function installGpuGlobals(): void {
  const g = globalThis as Record<string, unknown>;
  g.GPUBufferUsage ??= {
    MAP_READ: 1, MAP_WRITE: 2, COPY_SRC: 4, COPY_DST: 8, INDEX: 16,
    VERTEX: 32, UNIFORM: 64, STORAGE: 128, INDIRECT: 256, QUERY_RESOLVE: 512,
  };
  g.GPUTextureUsage ??= {
    COPY_SRC: 1, COPY_DST: 2, TEXTURE_BINDING: 4, STORAGE_BINDING: 8, RENDER_ATTACHMENT: 16,
  };
  g.GPUShaderStage ??= { VERTEX: 1, FRAGMENT: 2, COMPUTE: 4 };
  g.GPUMapMode ??= { READ: 1, WRITE: 2 };
}

export function createFakeGpu(options: { externalTexture?: boolean } = {}): FakeGpu {
  installGpuGlobals();

  const counters: FakeGpuCounters = {
    submits: 0, commandBuffers: 0, encoders: 0, createBindGroup: 0, createView: 0,
    importExternalTexture: 0, createComputePipeline: 0, createComputePipelineAsync: 0,
    createRenderPipeline: 0, writeBuffer: 0, writeTexture: 0, mapAsync: 0,
  };
  const ops: FakeGpuOp[] = [];
  const submitted: FakeGpu['submitted'] = [];
  const bindGroupLabels: string[] = [];

  const texture = (label: string, width = 64, height = 64, layers = 1): GPUTexture => ({
    label,
    width,
    height,
    depthOrArrayLayers: layers,
    createView: () => {
      counters.createView++;
      return { label: `${label}:view`, texture: { label } };
    },
    destroy: () => {},
  }) as unknown as GPUTexture;

  const buffer = (label: string, size = 256): GPUBuffer => ({
    label,
    size,
    mapAsync: () => {
      counters.mapAsync++;
      return Promise.resolve();
    },
    getMappedRange: () => new ArrayBuffer(size),
    unmap: () => {},
    destroy: () => {},
  }) as unknown as GPUBuffer;

  const passFor = (push: (op: FakeGpuOp) => void) => ({
    setPipeline: (p: unknown) => push({ op: 'setPipeline', label: labelOf(p) }),
    setBindGroup: (index: number, bg: unknown) => push({ op: 'setBindGroup', index, label: labelOf(bg) }),
    dispatchWorkgroups: (x: number, y = 1, z = 1) => push({ op: 'dispatch', x, y, z }),
    draw: (count: number) => push({ op: 'draw', count }),
    end: () => push({ op: 'endPass' }),
  });

  const createCommandEncoder = (desc?: Labeled): GPUCommandEncoder => {
    counters.encoders++;
    const log: FakeGpuOp[] = [];
    const push = (op: FakeGpuOp) => {
      log.push(op);
      ops.push(op);
    };
    const pass = passFor(push);
    return {
      label: desc?.label,
      beginComputePass: (d?: unknown) => {
        push({ op: 'beginComputePass', label: labelOf(d), timestampWrites: timestampWritesOf(d) });
        return pass;
      },
      beginRenderPass: (d: { label?: string; colorAttachments?: Array<{ view?: unknown }> }) => {
        const view = d.colorAttachments?.[0]?.view as { texture?: Labeled } | undefined;
        push({
          op: 'beginRenderPass',
          label: d.label,
          target: view?.texture?.label,
          timestampWrites: timestampWritesOf(d),
        });
        return pass;
      },
      copyTextureToTexture: (src: { texture: Labeled }, dst: { texture: Labeled }, size: number[]) =>
        push({ op: 'copyTextureToTexture', from: src.texture?.label, to: dst.texture?.label, size: [...size] }),
      copyBufferToBuffer: (src: Labeled, _so: number, dst: Labeled, _do: number, size: number) =>
        push({ op: 'copyBufferToBuffer', from: src?.label, to: dst?.label, size }),
      copyTextureToBuffer: (src: { texture: Labeled }, dst: { buffer: Labeled }) =>
        push({ op: 'copyTextureToBuffer', from: src.texture?.label, to: dst.buffer?.label }),
      clearBuffer: (b: Labeled) => push({ op: 'clearBuffer', buffer: b?.label }),
      resolveQuerySet: (_qs: unknown, first: number, count: number) =>
        push({ op: 'resolveQuerySet', first, count }),
      finish: () => ({ label: desc?.label, ops: log }),
    } as unknown as GPUCommandEncoder;
  };

  const queue = {
    submit: (buffers: Array<{ label?: string; ops: FakeGpuOp[] }>) => {
      counters.submits++;
      for (const cb of buffers) {
        counters.commandBuffers++;
        submitted.push({ label: cb.label, ops: cb.ops });
      }
    },
    writeBuffer: () => { counters.writeBuffer++; },
    writeTexture: () => { counters.writeTexture++; },
    copyExternalImageToTexture: () => {},
    onSubmittedWorkDone: () => Promise.resolve(),
  };

  const device = {
    label: 'fake-device',
    features: new Set<string>(['timestamp-query']),
    limits: { maxComputeWorkgroupsPerDimension: 65535 },
    queue,
    lost: new Promise(() => {}),
    createCommandEncoder,
    createBindGroup: (desc: Labeled) => {
      counters.createBindGroup++;
      bindGroupLabels.push(desc?.label ?? '?');
      return { label: desc?.label ?? 'bindGroup' };
    },
    createBindGroupLayout: (desc: Labeled) => ({ label: desc?.label ?? 'bgl' }),
    createPipelineLayout: (desc: Labeled) => ({ label: desc?.label ?? 'pl' }),
    createShaderModule: (desc: Labeled) => ({
      label: desc?.label ?? 'module',
      getCompilationInfo: () => Promise.resolve({ messages: [] }),
    }),
    createComputePipeline: (desc: Labeled) => {
      counters.createComputePipeline++;
      return { label: desc?.label ?? 'computePipeline', getBindGroupLayout: () => ({}) };
    },
    createComputePipelineAsync: (desc: Labeled) => {
      counters.createComputePipelineAsync++;
      return Promise.resolve({ label: desc?.label ?? 'computePipeline', getBindGroupLayout: () => ({}) });
    },
    createRenderPipeline: (desc: Labeled) => {
      counters.createRenderPipeline++;
      return { label: desc?.label ?? 'renderPipeline' };
    },
    createSampler: (desc: Labeled) => ({ label: desc?.label ?? 'sampler' }),
    createTexture: (desc: { label?: string; size: number[] | { width: number; height: number } }) => {
      const size = Array.isArray(desc.size) ? desc.size : [desc.size.width, desc.size.height];
      return texture(desc.label ?? 'texture', size[0], size[1] ?? 1, size[2] ?? 1);
    },
    createBuffer: (desc: { label?: string; size: number }) => buffer(desc.label ?? 'buffer', desc.size),
    createQuerySet: (desc: { label?: string; count: number }) => ({
      label: desc.label ?? 'querySet',
      count: desc.count,
      destroy: () => {},
    }),
    pushErrorScope: () => {},
    popErrorScope: () => Promise.resolve(null),
    addEventListener: () => {},
    removeEventListener: () => {},
    destroy: () => {},
    ...(options.externalTexture === false
      ? {}
      : {
          importExternalTexture: (desc: { source?: Labeled }) => {
            counters.importExternalTexture++;
            return { label: `external:${desc?.source?.label ?? 'video'}` };
          },
        }),
  } as unknown as GPUDevice;

  return {
    device,
    ops,
    submitted,
    counters,
    bindGroupLabels,
    reset() {
      ops.length = 0;
      submitted.length = 0;
      bindGroupLabels.length = 0;
      (Object.keys(counters) as Array<keyof FakeGpuCounters>).forEach((k) => {
        counters[k] = 0;
      });
    },
    texture,
    buffer,
  };
}

/** Compact op names for snapshot-style assertions (`pass:label`, `copy:a>b`, …). */
export function summarizeOps(ops: FakeGpuOp[]): string[] {
  const out: string[] = [];
  for (const o of ops) {
    switch (o.op) {
      case 'beginComputePass':
        out.push(`compute:${o.label ?? '?'}${o.timestampWrites ? ` ts(${o.timestampWrites.begin ?? '-'},${o.timestampWrites.end ?? '-'})` : ''}`);
        break;
      case 'beginRenderPass':
        out.push(`render:${o.label ?? '?'}>${o.target ?? '?'}${o.timestampWrites ? ` ts(${o.timestampWrites.begin ?? '-'},${o.timestampWrites.end ?? '-'})` : ''}`);
        break;
      case 'copyTextureToTexture':
        out.push(`copy:${o.from}>${o.to}`);
        break;
      case 'copyBufferToBuffer':
        out.push(`bufcopy:${o.from}>${o.to}`);
        break;
      case 'copyTextureToBuffer':
        out.push(`readback:${o.from}>${o.to}`);
        break;
      case 'resolveQuerySet':
        out.push(`resolve:${o.first}+${o.count}`);
        break;
      case 'clearBuffer':
        out.push(`clear:${o.buffer}`);
        break;
      default:
        break;
    }
  }
  return out;
}
