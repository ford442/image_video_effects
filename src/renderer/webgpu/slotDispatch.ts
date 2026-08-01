/**
 * slotDispatch.ts
 *
 * Multi-slot planning and GPU dispatch, including GraphRunner handoff,
 * quality caps, feedback copy ordering, and compute timestamp phases.
 */

import { analyzeGraphBindingUsage, graphRunner } from '../GraphRunner';
import { resolveMultipassChain } from '../multipassRegistry';
import {
  ExpandedDispatch,
  MultipassGraphDef,
  expandGraph,
  resolveGraphForShader,
} from '../multipassGraph';
import type { WebGPUFrameState } from './frameState';
import { pickComputeTimestampWrites, SlotTimingMode } from './WebGPUTiming';
import { ShaderSlot } from './webgpuConstants';

export type FeedbackCopySource = 'dataTexB' | 'dataTexA';

export type SlotDispatchProgram =
  | { kind: 'graph'; graph: MultipassGraphDef }
  | { kind: 'chain'; shaderIds: string[] };

export interface SlotDispatchPlan {
  slot: ShaderSlot;
  program: SlotDispatchProgram;
  writesDataA: boolean;
  writesDataB: boolean;
}

export interface FrameSlotDispatchPlan {
  enabledCount: number;
  parallel: SlotDispatchPlan[];
  chained: SlotDispatchPlan[];
  anyReadsDataC: boolean;
  anyUsesHistory: boolean;
}

export interface FrameSlotDispatchResult {
  wallStart: number;
  wallParallel: number;
  wallChained: number;
}

/** Resolve the GraphRunner gate once per slot; all other slots use the linear chain. */
export function resolveSlotDispatchProgram(shaderId: string): SlotDispatchProgram {
  const graph = resolveGraphForShader(shaderId);
  return graph
    ? { kind: 'graph', graph }
    : { kind: 'chain', shaderIds: resolveMultipassChain(shaderId) };
}

/** Apply the graph's declared ceiling and the active render-quality pass budget. */
export function getCappedGraphDispatches(
  graph: MultipassGraphDef,
  maxPassesPerFrame: number,
): ExpandedDispatch[] {
  const cap = Math.min(graph.maxPassesPerFrame, maxPassesPerFrame);
  return expandGraph(graph).slice(0, cap);
}

/** Count passes that will actually encode, for accurate last-compute timestamps. */
export function countSlotComputePasses(
  program: SlotDispatchProgram,
  maxPassesPerFrame: number,
  hasPipeline: (shaderId: string) => boolean,
): number {
  if (program.kind === 'graph') {
    return getCappedGraphDispatches(program.graph, maxPassesPerFrame)
      .filter((dispatch) => hasPipeline(dispatch.entry)).length;
  }
  return program.shaderIds.filter(hasPipeline).length;
}

/**
 * Feedback contract: secondary/detail B copies first; primary simulation state A
 * copies last and therefore wins when both buffers were written.
 */
export function getFeedbackCopyOrder(
  readsDataC: boolean,
  writesDataA: boolean,
  writesDataB: boolean,
): FeedbackCopySource[] {
  if (!readsDataC) return [];
  const copies: FeedbackCopySource[] = [];
  if (writesDataB) copies.push('dataTexB');
  if (writesDataA) copies.push('dataTexA');
  return copies;
}

export function buildFrameSlotDispatchPlan(state: WebGPUFrameState): FrameSlotDispatchPlan {
  let anyReadsDataC = false;
  let anyUsesHistory = false;

  const plans = state.slots
    .filter((slot) => slot.enabled && slot.shaderId && state.hasPipeline(slot.shaderId))
    .map((slot): SlotDispatchPlan => {
      const program = resolveSlotDispatchProgram(slot.shaderId!);
      let writesDataA = false;
      let writesDataB = false;

      if (program.kind === 'graph') {
        const usage = analyzeGraphBindingUsage(program.graph);
        writesDataA = usage.writesDataA;
        writesDataB = usage.writesDataB;
        anyReadsDataC = anyReadsDataC || usage.readsDataC;
        for (const node of program.graph.nodes) {
          anyUsesHistory = anyUsesHistory || state.getBindingUsage(node.entry).usesHistory;
        }
      } else {
        for (const shaderId of program.shaderIds) {
          const usage = state.getBindingUsage(shaderId);
          writesDataA = writesDataA || usage.writesDataA;
          writesDataB = writesDataB || usage.writesDataB;
          anyReadsDataC = anyReadsDataC || usage.readsDataC;
          anyUsesHistory = anyUsesHistory || usage.usesHistory;
        }
      }

      return { slot, program, writesDataA, writesDataB };
    });

  return {
    enabledCount: plans.length,
    parallel: plans.filter((plan) => plan.slot.mode === 'parallel'),
    chained: plans.filter((plan) => plan.slot.mode === 'chained'),
    anyReadsDataC,
    anyUsesHistory,
  };
}

export function dispatchFrameSlots(
  state: WebGPUFrameState,
  encoder: GPUCommandEncoder,
  plan: FrameSlotDispatchPlan,
): FrameSlotDispatchResult {
  const { parallel, chained } = plan;
  const singleChained = plan.enabledCount === 1 && chained.length === 1;
  state.blitReadTex = state.readTex;

  state.timestampRuntime.tracker.reset();
  const wallStart = performance.now();
  let wallParallel = 0;
  let wallChained = 0;

  const orderedPlans = [...parallel, ...chained];
  const totalComputePasses = orderedPlans.reduce(
    (sum, slotPlan) => sum + countSlotComputePasses(
      slotPlan.program,
      state.maxPassesPerFrame,
      state.hasPipeline,
    ),
    0,
  );
  let computePassIndex = 0;
  const nextPassMeta = (mode: SlotTimingMode): { isLast: boolean; mode: SlotTimingMode } => {
    const isLast = computePassIndex === totalComputePasses - 1;
    computePassIndex++;
    return { isLast, mode };
  };

  logDispatchPlan(state, parallel, chained);

  for (const slotPlan of parallel) {
    const slotStart = performance.now();
    dispatchSlot(state, encoder, slotPlan, 'parallel', nextPassMeta);
    wallParallel += performance.now() - slotStart;
  }

  if (parallel.length > 0) {
    copyTexture(state, encoder, state.writeTex, state.readTex);
    encodeFeedbackCopies(
      state,
      encoder,
      getFeedbackCopyOrder(
        plan.anyReadsDataC,
        parallel.some((slotPlan) => slotPlan.writesDataA),
        parallel.some((slotPlan) => slotPlan.writesDataB),
      ),
    );
  }

  for (const slotPlan of chained) {
    const slotStart = performance.now();
    dispatchSlot(state, encoder, slotPlan, 'chained', nextPassMeta);
    wallChained += performance.now() - slotStart;

    if (singleChained) {
      state.blitReadTex = state.writeTex;
    } else {
      copyTexture(state, encoder, state.writeTex, state.readTex);
    }

    encodeFeedbackCopies(
      state,
      encoder,
      getFeedbackCopyOrder(
        plan.anyReadsDataC,
        slotPlan.writesDataA,
        slotPlan.writesDataB,
      ),
    );
  }

  return { wallStart, wallParallel, wallChained };
}

function dispatchSlot(
  state: WebGPUFrameState,
  encoder: GPUCommandEncoder,
  plan: SlotDispatchPlan,
  mode: SlotTimingMode,
  nextPassMeta: (mode: SlotTimingMode) => { isLast: boolean; mode: SlotTimingMode },
): void {
  if (!plan.slot.shaderId || !state.device) return;

  const timing = state.timestampRuntime;
  const querySet =
    timing.supportsTimestampQuery && timing.querySet ? timing.querySet : null;

  if (plan.program.kind === 'graph') {
    const textures = state.getTextureSet();
    graphRunner.runGraph(encoder, plan.program.graph, {
      device: state.device,
      pipelineLayout: state.pipelineLayout,
      getPipeline: state.getPipeline,
      getWorkgroupSize: state.getWorkgroupSize,
      createBindGroupForRoles: state.createBindGroupForRoles,
      textures: {
        read: textures.readTex,
        color: textures.writeTex,
        dataA: textures.dataTexA,
        dataB: textures.dataTexB,
        dataC: textures.dataTexC,
      },
      scaledW: state.scaledW,
      scaledH: state.scaledH,
      maxPassesPerFrame: state.maxPassesPerFrame,
      getTimestampWrites: querySet
        ? () => {
            const { isLast } = nextPassMeta(mode);
            return pickComputeTimestampWrites(timing.tracker, querySet, mode, isLast);
          }
        : undefined,
    });
    return;
  }

  for (const shaderId of plan.program.shaderIds) {
    const pipeline = state.getPipeline(shaderId);
    if (!pipeline) {
      console.warn(`[WebGPURenderer] Pipeline missing for multipass step "${shaderId}"`);
      continue;
    }
    const wg = state.getWorkgroupSize(shaderId);
    const { isLast } = nextPassMeta(mode);
    const timestampWrites = querySet
      ? pickComputeTimestampWrites(timing.tracker, querySet, mode, isLast)
      : undefined;
    const pass = encoder.beginComputePass(
      timestampWrites
        ? { label: `${mode}-${shaderId}`, timestampWrites }
        : { label: `${mode}-${shaderId}` },
    );
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, state.computeBindGroup);
    pass.dispatchWorkgroups(
      Math.ceil(state.scaledW / wg.x),
      Math.ceil(state.scaledH / wg.y),
      1,
    );
    pass.end();
  }
}

function encodeFeedbackCopies(
  state: WebGPUFrameState,
  encoder: GPUCommandEncoder,
  sources: FeedbackCopySource[],
): void {
  for (const source of sources) {
    copyTexture(state, encoder, state[source], state.dataTexC);
  }
}

function copyTexture(
  state: WebGPUFrameState,
  encoder: GPUCommandEncoder,
  from: GPUTexture,
  to: GPUTexture,
): void {
  encoder.copyTextureToTexture(
    { texture: from },
    { texture: to },
    [state.scaledW, state.scaledH, 1],
  );
}

function logDispatchPlan(
  state: WebGPUFrameState,
  parallel: SlotDispatchPlan[],
  chained: SlotDispatchPlan[],
): void {
  if (process.env.NODE_ENV !== 'development' || state.frameCount % 60 !== 0) return;
  console.log(
    `[WebGPURenderer] Parallel slots: ${parallel.length}, Chained slots: ${chained.length}`,
  );
  if (chained.length > 0) {
    console.log(
      '[WebGPURenderer] Chained slot order:',
      chained.map((slotPlan) => slotPlan.slot.shaderId),
    );
  }
}
