/**
 * generator.ts — the dedicated generative-source stage.
 *
 * In Generative input mode the picture the effect slots process is produced by a
 * generator shader, not an image or a video. The generator is NOT one of the effect
 * slots: it runs once per frame, before the slot chain, writes its picture into
 * `readTex`, and slot 0 reads it exactly as it would read an image. Every slot (and the
 * layer compositor, history ring, present and stage outputs) therefore sees an ordinary
 * source, and the user's effect stack (Liquid, …) is left alone.
 *
 * Feedback isolation: 462 of the 465 `gen-*` shaders write dataTextureA/B and 390 read
 * dataTextureC. Those textures are shared by the effect slots, so a generator running on
 * them would corrupt (and be corrupted by) a feedback effect. The stage owns a private
 * A/B/C triple and its own bind group; only readTex / writeTex / history / depth / the
 * uniform + audio buffers are shared with the slot chain.
 *
 * zoom_params: the generator's four sliders are patched into the uniform buffer (bytes
 * 32-47) before its pass and the global values are patched back afterwards, so a slot
 * without its own params still sees what it saw before the generator existed.
 */

import { getFeedbackCopyOrder } from './framePlan';
import type { WebGPUFrameState } from './frameState';

export type GeneratorParams = [number, number, number, number];

export const DEFAULT_GENERATOR_PARAMS: Readonly<GeneratorParams> = [0.5, 0.5, 0.5, 0.5];

/** Byte offset of zoom_params in the uniform buffer (see UniformBuffer.setZoomParams). */
const ZOOM_PARAMS_OFFSET = 32;
/** Same usage as the slots' dataTex A/B/C (resources.ts USAGE_STANDARD); read lazily, WebGPU globals may not exist at import. */
const stateUsage = (): GPUTextureUsageFlags =>
  GPUTextureUsage.TEXTURE_BINDING |
  GPUTextureUsage.STORAGE_BINDING |
  GPUTextureUsage.COPY_DST |
  GPUTextureUsage.COPY_SRC;

export type GeneratorSkipReason = 'compiling' | 'sim-ring';

export interface GeneratorStatus {
  shaderId: string | null;
  /** True when the generator ran in the last encoded frame. */
  ran: boolean;
  /** Why it did not run (only while `shaderId` is set and `ran` is false). */
  skipped: GeneratorSkipReason | null;
}

interface PrivateState {
  device: GPUDevice;
  width: number;
  height: number;
  format: GPUTextureFormat;
  a: GPUTexture;
  b: GPUTexture;
  c: GPUTexture;
}

export class GeneratorStage {
  private shaderId: string | null = null;
  private params: GeneratorParams = [...DEFAULT_GENERATOR_PARAMS] as GeneratorParams;

  private priv: PrivateState | null = null;
  private bindGroup: GPUBindGroup | null = null;
  /** Everything the bind group was built from; any change rebuilds it. */
  private bindKey: unknown[] = [];
  private paramsBuf: GPUBuffer | null = null;
  private paramsDevice: GPUDevice | null = null;
  private paramsData = new Float32Array(8);
  private warned = new Set<string>();
  private lastStatus: GeneratorStatus = { shaderId: null, ran: false, skipped: null };

  /** The id of the generator shader, or null when the stage is off. */
  getShader(): string | null {
    return this.shaderId;
  }

  /** Turn the stage on with `id`, or off with null/''. Takes effect next frame. */
  setShader(id: string | null): void {
    const next = id ? id : null;
    if (next === this.shaderId) return;
    this.shaderId = next;
    // A different generator must not inherit the last one's feedback state.
    this.clearState();
    this.lastStatus = { shaderId: next, ran: false, skipped: null };
  }

  getParams(): GeneratorParams {
    return [...this.params] as GeneratorParams;
  }

  setParams(p1: number, p2: number, p3: number, p4: number): void {
    this.params = [p1, p2, p3, p4].map((v) => (Number.isFinite(v) ? v : 0.5)) as GeneratorParams;
  }

  getStatus(): GeneratorStatus {
    return { ...this.lastStatus };
  }

  /** True when the stage should run for this frame (a generator is set and the source is generative). */
  isActive(state: Pick<WebGPUFrameState, 'inputSource'>): boolean {
    return this.shaderId !== null && state.inputSource === 'generative';
  }

  /**
   * Encode the generator pass and leave its picture in `readTex`. Returns whether it ran.
   * Call after the input copy (which seeds readTex) and after the frame uniforms were written.
   */
  encode(state: WebGPUFrameState, encoder: GPUCommandEncoder): boolean {
    const id = this.shaderId;
    const device = state.device;
    if (!id || !device || state.inputSource !== 'generative') return this.report(false, null);
    if (!state.hasPipeline(id)) return this.report(false, 'compiling');
    if (state.usesSimRing(id)) return this.skip(id, 'sim-ring');

    const pipeline = state.getPipeline(id);
    if (!pipeline) return this.report(false, 'compiling');
    const res = this.ensure(state, device);
    const usage = state.getBindingUsage(id);
    const workgroup = state.getWorkgroupSize(id);
    const { priv, bindGroup, paramsBuf } = res;

    // Generator sliders → zoom_params for this pass; the global values go back after it.
    const data = this.paramsData;
    data.set(this.params, 0);
    for (let i = 0; i < 4; i++) data[4 + i] = state.zoomParams[i] ?? 0.5;
    device.queue.writeBuffer(paramsBuf, 0, data);
    encoder.copyBufferToBuffer(paramsBuf, 0, state.uniformBuf, ZOOM_PARAMS_OFFSET, 16);

    const pass = encoder.beginComputePass({ label: `generator:${id}` });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(
      Math.ceil(state.scaledW / Math.max(1, workgroup.x)),
      Math.ceil(state.scaledH / Math.max(1, workgroup.y)),
      1,
    );
    pass.end();

    encoder.copyBufferToBuffer(paramsBuf, 16, state.uniformBuf, ZOOM_PARAMS_OFFSET, 16);

    // The picture becomes the slot chain's input.
    const size: [number, number, number] = [state.scaledW, state.scaledH, 1];
    encoder.copyTextureToTexture({ texture: state.writeTex }, { texture: state.readTex }, size);

    // Feedback contract (framePlan.getFeedbackCopyOrder): A/B → C for the next frame, on the private triple.
    for (const from of getFeedbackCopyOrder(usage.readsDataC, usage.writesDataA, usage.writesDataB)) {
      encoder.copyTextureToTexture(
        { texture: from === 'dataTexA' ? priv.a : priv.b },
        { texture: priv.c },
        size,
      );
    }
    return this.report(true, null);
  }

  /** Free the private state and the params buffer (renderer teardown / device change). */
  destroy(): void {
    this.clearState();
    try {
      this.paramsBuf?.destroy();
    } catch {
      /* already invalid */
    }
    this.paramsBuf = null;
    this.paramsDevice = null;
  }

  private report(ran: boolean, skipped: GeneratorSkipReason | null): boolean {
    this.lastStatus = { shaderId: this.shaderId, ran, skipped };
    return ran;
  }

  private skip(id: string, reason: GeneratorSkipReason): boolean {
    const key = `${id}:${reason}`;
    if (!this.warned.has(key)) {
      this.warned.add(key);
      console.warn(`[Generator] ${id} cannot run as the generative source (${reason})`);
    }
    return this.report(false, reason);
  }

  private clearState(): void {
    for (const t of [this.priv?.a, this.priv?.b, this.priv?.c]) {
      try {
        t?.destroy();
      } catch {
        /* already invalid */
      }
    }
    this.priv = null;
    this.bindGroup = null;
    this.bindKey = [];
  }

  /** Private A/B/C + bind group + params buffer, rebuilt whenever the shared textures change. */
  private ensure(
    state: WebGPUFrameState,
    device: GPUDevice,
  ): { priv: PrivateState; bindGroup: GPUBindGroup; paramsBuf: GPUBuffer } {
    const width = state.scaledW;
    const height = state.scaledH;
    const format = state.readTex.format;

    let paramsBuf = this.paramsBuf;
    if (this.paramsDevice !== device || !paramsBuf) {
      try {
        paramsBuf?.destroy();
      } catch {
        /* belongs to a lost device */
      }
      paramsBuf = device.createBuffer({
        label: 'generatorParamsBuf',
        size: 32,
        usage: GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST,
      });
      this.paramsBuf = paramsBuf;
      this.paramsDevice = device;
    }

    let priv = this.priv;
    if (!priv || priv.device !== device || priv.width !== width || priv.height !== height || priv.format !== format) {
      this.clearState();
      const make = (label: string) =>
        device.createTexture({ label, size: [width, height], format, usage: stateUsage() });
      priv = {
        device, width, height, format,
        a: make('generatorDataA'),
        b: make('generatorDataB'),
        c: make('generatorDataC'),
      };
      this.priv = priv;
    }

    const set = state.getTextureSet();
    const key = [
      priv.a, priv.b, priv.c,
      state.readTex, state.writeTex, set.historyTex, set.depthRead, set.depthWrite,
      state.uniformBuf, state.extraBuf, state.plasmaBuf, state.bindGroupLayout,
    ];
    let bindGroup = this.bindGroup;
    if (!bindGroup || key.some((v, i) => v !== this.bindKey[i])) {
      bindGroup = state.createBindGroupForRoles({
        read: state.readTex,
        color: state.writeTex,
        dataA: priv.a,
        dataB: priv.b,
        dataC: priv.c,
      });
      this.bindGroup = bindGroup;
      this.bindKey = key;
    }
    return { priv, bindGroup, paramsBuf };
  }
}
