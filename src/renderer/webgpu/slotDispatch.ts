/**
 * slotDispatch.ts
 *
 * Multi-slot planning: which slots run, as a linear chain or a Tier C graph,
 * and what they read/write. Encoding lives in framePlan.ts: dispatchFrameSlots
 * compiles this plan into the frame-plan IR and executes it.
 */

import { analyzeGraphBindingUsage, graphRunner } from '../GraphRunner';
import { resolveMultipassChain } from '../multipassRegistry';
import {
  cappedDispatches,
  ExpandedDispatch,
  MultipassGraphDef,
  graphUsesSimRing,
  resolveGraphForShader,
} from '../multipassGraph';
import type { WebGPUFrameState } from './frameState';
import { compileFramePlan, executeFramePlan, FramePlan } from './framePlan';
import { profilePass } from './WebGPUTiming';
import { ShaderSlot } from './webgpuConstants';

export { getFeedbackCopyOrder } from './framePlan';
export type { FeedbackCopySource } from './framePlan';

export type SlotDispatchProgram =
  | { kind: 'graph'; graph: MultipassGraphDef }
  | { kind: 'chain'; shaderIds: string[] };

export interface SlotDispatchPlan {
  slot: ShaderSlot;
  /** Physical slot index (0..PHYSICAL_SLOT_LIMIT-1). */
  slotIndex: number;
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
  /** Any enabled slot touches the group-1 sim ring → upload simParams this frame. */
  anyUsesSimRing: boolean;
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
  return cappedDispatches(graph, maxPassesPerFrame);
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

export function buildFrameSlotDispatchPlan(state: WebGPUFrameState): FrameSlotDispatchPlan {
  let anyReadsDataC = false;
  let anyUsesHistory = false;
  let anyUsesSimRing = false;

  const plans = state.slots
    .map((slot, slotIndex) => ({ slot, slotIndex }))
    .filter(({ slot }) => slot.enabled && slot.shaderId && state.hasPipeline(slot.shaderId))
    .map(({ slot, slotIndex }): SlotDispatchPlan => {
      const program = resolveSlotDispatchProgram(slot.shaderId!);
      let writesDataA = false;
      let writesDataB = false;

      if (program.kind === 'graph') {
        const usage = analyzeGraphBindingUsage(program.graph);
        writesDataA = usage.writesDataA;
        writesDataB = usage.writesDataB;
        anyReadsDataC = anyReadsDataC || usage.readsDataC;
        anyUsesSimRing = anyUsesSimRing || graphUsesSimRing(program.graph);
        for (const node of program.graph.nodes) {
          anyUsesHistory = anyUsesHistory || state.getBindingUsage(node.entry).usesHistory;
          anyUsesSimRing = anyUsesSimRing || state.usesSimRing(node.entry);
        }
      } else {
        for (const shaderId of program.shaderIds) {
          const usage = state.getBindingUsage(shaderId);
          writesDataA = writesDataA || usage.writesDataA;
          writesDataB = writesDataB || usage.writesDataB;
          anyReadsDataC = anyReadsDataC || usage.readsDataC;
          anyUsesHistory = anyUsesHistory || usage.usesHistory;
          anyUsesSimRing = anyUsesSimRing || state.usesSimRing(shaderId);
        }
      }

      return { slot, slotIndex, program, writesDataA, writesDataB };
    });

  return {
    enabledCount: plans.length,
    parallel: plans.filter((plan) => plan.slot.mode === 'parallel'),
    chained: plans.filter((plan) => plan.slot.mode === 'chained'),
    anyReadsDataC,
    anyUsesHistory,
    anyUsesSimRing,
  };
}

/** Compile the slot plan into the frame-plan IR (no GPU work). */
export function compileSlotPlan(state: WebGPUFrameState, plan: FrameSlotDispatchPlan): FramePlan {
  return compileFramePlan(plan, {
    getPipeline: state.getPipeline,
    getWorkgroupSize: state.getWorkgroupSize,
    usesSimRing: state.usesSimRing,
    simRing: state.getSimRing(),
    maxPassesPerFrame: state.maxPassesPerFrame,
    framePassBudget: state.framePassBudget,
  });
}

export function dispatchFrameSlots(
  state: WebGPUFrameState,
  encoder: GPUCommandEncoder,
  plan: FrameSlotDispatchPlan,
  beforeSlot?: (encoder: GPUCommandEncoder, slot: ShaderSlot) => void,
): FrameSlotDispatchResult {
  logDispatchPlan(state, plan.parallel, plan.chained);
  if (plan.anyUsesSimRing) state.writeSimRingParams();

  const framePlan = compileSlotPlan(state, plan);
  const timing = state.timestampRuntime;

  const result = executeFramePlan(
    encoder,
    framePlan,
    {
      textures: {
        readTex: state.readTex,
        writeTex: state.writeTex,
        dataTexA: state.dataTexA,
        dataTexB: state.dataTexB,
        dataTexC: state.dataTexC,
      },
      computeBindGroup: state.computeBindGroup,
      simRing: state.getSimRing(),
      scaledW: state.scaledW,
      scaledH: state.scaledH,
    },
    {
      beforeSlot,
      timestampWrites: timing.supportsTimestampQuery
        ? (op) =>
            profilePass(timing, {
              kind: 'compute',
              label: op.label,
              mode: op.mode,
              slot: op.slotIndex,
              shaderId: op.shaderId,
              entry: op.entry,
              nodeId: op.nodeId,
              scale: 1,
            })
        : undefined,
    },
  );

  state.blitReadTex = framePlan.output === 'writeTex' ? state.writeTex : state.readTex;
  if (framePlan.graphReports.length > 0) {
    graphRunner.lastReport = framePlan.graphReports[framePlan.graphReports.length - 1];
  }
  return result;
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
