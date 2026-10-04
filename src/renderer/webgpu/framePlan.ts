/**
 * framePlan.ts
 *
 * Frame-plan IR (#1314 WP-3). Every enabled slot — a linear chain or a Tier C
 * graph — compiles into one flat op list, and a single executor encodes it
 * into the frame encoder. A slot and a graph node are the same thing here: a
 * compute op with an entry, a slot, and a dispatch shape.
 *
 * Order reproduces the pre-IR dispatch exactly: parallel slots → writeTex→readTex
 * → feedback; then each chained slot followed by its copy + feedback.
 * docs/BINDING_CONTRACT.md freezes the feedback order (B → C, then A → C).
 */

import type { GraphRunReport, GraphSimRingBindings } from '../GraphRunner';
import {
  cappedDispatches,
  ExpandedDispatch,
  graphPlanErrors,
  graphRequestedPasses,
  MultipassGraphDef,
} from '../multipassGraph';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';
import type { SlotTimingMode } from './WebGPUTiming';
import type { ShaderSlot } from './webgpuConstants';

export type FeedbackCopySource = 'dataTexB' | 'dataTexA';

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

export type FrameTexture = 'readTex' | 'writeTex' | 'dataTexA' | 'dataTexB' | 'dataTexC';

export interface ComputeOp {
  kind: 'compute';
  label: string;
  mode: SlotTimingMode;
  slotIndex: number;
  /** The slot's shader id (graph root for graph nodes). */
  shaderId: string;
  /** Pipeline id actually dispatched (chain step or graph entry). */
  entry: string;
  pipeline: GPUComputePipeline;
  workgroup: { x: number; y: number };
  nodeId?: string;
  iteration?: number;
  dispatch: 'pixels' | 'simState';
  /** Bind the group-1 sim ring for this pass. */
  bindSimRing: boolean;
}

export type FrameOp =
  | ComputeOp
  /** Slot boundary: per-slot uniform patch + wall-clock attribution. */
  | { kind: 'slotStart'; slot: ShaderSlot; mode: SlotTimingMode }
  | { kind: 'copy'; from: FrameTexture; to: FrameTexture }
  /** Graph barrier: snapshot simState → simIndex (buffer twin of dataA → dataC). */
  | { kind: 'simBarrier' };

export interface FramePlan {
  ops: FrameOp[];
  computeCount: number;
  /** Texture the frame's final image lives in (present + history read it). */
  output: 'readTex' | 'writeTex';
  /** One report per graph slot, in encode order. */
  graphReports: GraphRunReport[];
}

export interface FramePlanContext {
  getPipeline(id: string): GPUComputePipeline | undefined;
  getWorkgroupSize(id: string): { x: number; y: number };
  usesSimRing(id: string): boolean;
  /** Armed sim ring, or null when none is allocated. */
  simRing: GraphSimRingBindings | null;
  /** Per-graph pass cap from the render-quality policy. */
  maxPassesPerFrame: number;
  /** Total compute passes allowed this frame across all slots (Infinity = no frame cap). */
  framePassBudget: number;
  warn?: (message: string) => void;
}

// Plans compile every frame: report each condition once, not 60× a second.
let warnedIds = new Set<string>();
let warnedGraphs = new WeakMap<MultipassGraphDef, Set<string>>();

function warnOnce(ctx: FramePlanContext, key: string, message: string): void {
  if (warnedIds.has(key)) return;
  warnedIds.add(key);
  (ctx.warn ?? console.warn)(message);
}

function warnOncePerGraph(ctx: FramePlanContext, graph: MultipassGraphDef, key: string, message: string): void {
  let keys = warnedGraphs.get(graph);
  if (!keys) {
    keys = new Set();
    warnedGraphs.set(graph, keys);
  }
  if (keys.has(key)) return;
  keys.add(key);
  (ctx.warn ?? console.warn)(message);
}

/** Test hook: forget which one-time warnings were emitted. */
export function resetFramePlanWarnings(): void {
  warnedIds = new Set();
  warnedGraphs = new WeakMap();
}

/**
 * Split the frame pass budget: linear chains are mandatory (truncating one
 * changes the image), so they are charged first; graphs then share what is
 * left in encode order, each still capped by the per-graph quality cap and
 * never below 1 (shrinkGraphToCap always keeps the color writer).
 */
export function allocateGraphCaps(
  programs: SlotDispatchPlan['program'][],
  maxPassesPerFrame: number,
  framePassBudget: number,
): number[] {
  let remaining = framePassBudget;
  for (const program of programs) {
    if (program.kind === 'chain') remaining -= program.shaderIds.length;
  }
  return programs.map((program) => {
    if (program.kind !== 'graph') return 0;
    const cap = Math.max(1, Math.min(maxPassesPerFrame, remaining));
    const passes = cappedDispatches(program.graph, cap).length;
    remaining -= passes;
    return cap;
  });
}

function compileChain(
  ops: FrameOp[],
  slotPlan: SlotDispatchPlan,
  shaderIds: string[],
  mode: SlotTimingMode,
  ctx: FramePlanContext,
): void {
  for (const shaderId of shaderIds) {
    const pipeline = ctx.getPipeline(shaderId);
    if (!pipeline) {
      warnOnce(ctx, `missing:${shaderId}`, `[WebGPURenderer] Pipeline missing for multipass step "${shaderId}"`);
      continue;
    }
    const bindSimRing = ctx.usesSimRing(shaderId);
    if (bindSimRing && !ctx.simRing) {
      warnOnce(ctx, `ring:${shaderId}`, `[WebGPURenderer] "${shaderId}" needs the sim ring but none is armed — skipped`);
      continue;
    }
    ops.push({
      kind: 'compute',
      label: `${mode}-${shaderId}`,
      mode,
      slotIndex: slotPlan.slotIndex,
      shaderId: slotPlan.slot.shaderId ?? shaderId,
      entry: shaderId,
      pipeline,
      workgroup: ctx.getWorkgroupSize(shaderId),
      dispatch: 'pixels',
      bindSimRing,
    });
  }
}

/** Compile one Tier C graph into ops (barriers + compute) and its run report. */
export function compileGraphOps(
  ops: FrameOp[],
  graph: MultipassGraphDef,
  slotIndex: number,
  shaderId: string | null,
  mode: SlotTimingMode,
  cap: number,
  ctx: FramePlanContext,
): GraphRunReport {
  const errors = graphPlanErrors(graph);
  const requested = graphRequestedPasses(graph);
  if (errors.length > 0) {
    warnOncePerGraph(ctx, graph, 'invalid', `[GraphRunner] Invalid graph: ${errors.join('; ')}`);
    return {
      shaderId,
      requested,
      executed: 0,
      truncated: 0,
      cap: Math.min(graph.maxPassesPerFrame || 0, cap),
      errors,
    };
  }

  const effectiveCap = Math.min(graph.maxPassesPerFrame, cap);
  const expanded: ExpandedDispatch[] = cappedDispatches(graph, cap);
  const truncated = Math.max(0, requested - expanded.length);
  if (truncated > 0) {
    warnOncePerGraph(
      ctx,
      graph,
      `cap:${effectiveCap}`,
      `[GraphRunner] Pass cap ${effectiveCap} — truncated ${truncated} dispatch(es) (kept color write)`,
    );
  }

  let executed = 0;
  for (const dispatch of expanded) {
    for (const copy of dispatch.copiesBefore) {
      if (copy.from === 'simState') {
        if (ctx.simRing) ops.push({ kind: 'simBarrier' });
      } else {
        ops.push({ kind: 'copy', from: copy.from === 'dataA' ? 'dataTexA' : 'dataTexB', to: 'dataTexC' });
      }
    }
    const pipeline = ctx.getPipeline(dispatch.entry);
    if (!pipeline) {
      warnOnce(ctx, `missing:${dispatch.entry}`, `[GraphRunner] Pipeline missing for "${dispatch.entry}"`);
      continue;
    }
    const needsRing = ctx.usesSimRing(dispatch.entry) || dispatch.dispatch === 'simState';
    if (needsRing && (!ctx.simRing || ctx.simRing.stateCount === 0)) {
      warnOnce(ctx, `ring:${dispatch.entry}`, `[GraphRunner] "${dispatch.entry}" needs the sim ring but none is armed — skipped`);
      continue;
    }
    ops.push({
      kind: 'compute',
      label: `graph-${dispatch.nodeId}-${dispatch.iteration}-${dispatch.entry}`,
      mode,
      slotIndex,
      shaderId: shaderId ?? dispatch.entry,
      entry: dispatch.entry,
      pipeline,
      workgroup: ctx.getWorkgroupSize(dispatch.entry),
      nodeId: dispatch.nodeId,
      iteration: dispatch.iteration,
      dispatch: dispatch.dispatch,
      bindSimRing: needsRing && ctx.usesSimRing(dispatch.entry),
    });
    executed++;
  }

  return { shaderId, requested, executed, truncated, cap: effectiveCap, errors: [] };
}

function pushFeedback(ops: FrameOp[], sources: FeedbackCopySource[]): void {
  for (const from of sources) ops.push({ kind: 'copy', from, to: 'dataTexC' });
}

/** Compile the frame's slot plan into the flat op list (pure: no GPU calls). */
export function compileFramePlan(plan: FrameSlotDispatchPlan, ctx: FramePlanContext): FramePlan {
  const ops: FrameOp[] = [];
  const graphReports: GraphRunReport[] = [];
  const ordered = [...plan.parallel, ...plan.chained];
  const caps = allocateGraphCaps(
    ordered.map((p) => p.program),
    ctx.maxPassesPerFrame,
    ctx.framePassBudget,
  );
  const singleChained = plan.enabledCount === 1 && plan.chained.length === 1;

  const compileSlot = (slotPlan: SlotDispatchPlan, mode: SlotTimingMode, index: number) => {
    ops.push({ kind: 'slotStart', slot: slotPlan.slot, mode });
    const program = slotPlan.program;
    if (program.kind === 'graph') {
      graphReports.push(compileGraphOps(
        ops, program.graph, slotPlan.slotIndex, slotPlan.slot.shaderId, mode, caps[index], ctx,
      ));
    } else {
      compileChain(ops, slotPlan, program.shaderIds, mode, ctx);
    }
  };

  plan.parallel.forEach((slotPlan, i) => compileSlot(slotPlan, 'parallel', i));
  if (plan.parallel.length > 0) {
    ops.push({ kind: 'copy', from: 'writeTex', to: 'readTex' });
    pushFeedback(ops, getFeedbackCopyOrder(
      plan.anyReadsDataC,
      plan.parallel.some((p) => p.writesDataA),
      plan.parallel.some((p) => p.writesDataB),
    ));
  }

  plan.chained.forEach((slotPlan, i) => {
    compileSlot(slotPlan, 'chained', plan.parallel.length + i);
    if (!singleChained) ops.push({ kind: 'copy', from: 'writeTex', to: 'readTex' });
    pushFeedback(ops, getFeedbackCopyOrder(plan.anyReadsDataC, slotPlan.writesDataA, slotPlan.writesDataB));
  });

  return {
    ops,
    computeCount: ops.reduce((n, op) => n + (op.kind === 'compute' ? 1 : 0), 0),
    output: singleChained ? 'writeTex' : 'readTex',
    graphReports,
  };
}

export interface FrameExecResources {
  textures: Record<FrameTexture, GPUTexture>;
  computeBindGroup: GPUBindGroup;
  simRing: GraphSimRingBindings | null;
  scaledW: number;
  scaledH: number;
}

export interface FrameExecHooks {
  /** Per-slot uniform patch (zoom_params → uniformBuf bytes 32-47). */
  beforeSlot?: (encoder: GPUCommandEncoder, slot: ShaderSlot) => void;
  /** timestampWrites for the `index`-th of `count` compute passes, if profiled. */
  timestampWrites?: (
    op: ComputeOp,
    index: number,
    count: number,
  ) => GPUComputePassTimestampWrites | undefined;
}

export interface FrameExecResult {
  wallStart: number;
  wallParallel: number;
  wallChained: number;
}

/** Encode a compiled plan into `encoder`. The only place slot / graph passes are encoded. */
export function executeFramePlan(
  encoder: GPUCommandEncoder,
  plan: FramePlan,
  res: FrameExecResources,
  hooks: FrameExecHooks = {},
): FrameExecResult {
  const wallStart = performance.now();
  const wall = { parallel: 0, chained: 0 };
  let segmentMode: SlotTimingMode | null = null;
  let segmentStart = 0;
  const closeSegment = () => {
    if (segmentMode) wall[segmentMode] += performance.now() - segmentStart;
    segmentMode = null;
  };
  let computeIndex = 0;

  for (const op of plan.ops) {
    switch (op.kind) {
      case 'slotStart':
        closeSegment();
        segmentMode = op.mode;
        segmentStart = performance.now();
        hooks.beforeSlot?.(encoder, op.slot);
        break;
      case 'copy':
        encoder.copyTextureToTexture(
          { texture: res.textures[op.from] },
          { texture: res.textures[op.to] },
          [res.scaledW, res.scaledH, 1],
        );
        break;
      case 'simBarrier': {
        const ring = res.simRing;
        if (ring) encoder.copyBufferToBuffer(ring.stateBuffer, 0, ring.indexBuffer, 0, ring.byteSize);
        break;
      }
      case 'compute': {
        const timestampWrites = hooks.timestampWrites?.(op, computeIndex, plan.computeCount);
        computeIndex++;
        const pass = encoder.beginComputePass(
          timestampWrites ? { label: op.label, timestampWrites } : { label: op.label },
        );
        pass.setPipeline(op.pipeline);
        pass.setBindGroup(0, res.computeBindGroup);
        const ring = res.simRing;
        if (op.bindSimRing && ring) pass.setBindGroup(1, ring.bindGroup);
        if (op.dispatch === 'simState' && ring) {
          pass.dispatchWorkgroups(Math.ceil(ring.stateCount / Math.max(1, op.workgroup.x)), 1, 1);
        } else {
          pass.dispatchWorkgroups(
            Math.ceil(res.scaledW / op.workgroup.x),
            Math.ceil(res.scaledH / op.workgroup.y),
            1,
          );
        }
        pass.end();
        break;
      }
      default:
        break;
    }
  }
  closeSegment();
  return { wallStart, wallParallel: wall.parallel, wallChained: wall.chained };
}
