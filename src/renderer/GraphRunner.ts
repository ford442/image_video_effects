/**
 * GraphRunner.ts
 *
 * Intra-frame multipass graph executor with texture handoff between passes.
 * Tier C: enables same-frame pass-to-pass reads (unlike linear multipassRegistry).
 *
 * Since #1314 a graph is not executed on its own inside the frame: its nodes
 * compile into the frame plan (webgpu/framePlan.ts) next to linear slots, and
 * one executor encodes the whole frame. `runGraph` remains as the stand-alone
 * entry (tests, tools) built on the same compile + execute path.
 */

import { expandGraph, MultipassGraphDef } from './multipassGraph';
import {
  compileGraphOps,
  executeFramePlan,
  FrameOp,
  FramePlanContext,
} from './webgpu/framePlan';

export interface GraphRoleBindings {
  read: GPUTexture;
  color: GPUTexture;
  dataA: GPUTexture;
  dataB: GPUTexture;
  dataC: GPUTexture;
}

export interface GraphRunReport {
  shaderId: string | null;
  requested: number;
  executed: number;
  truncated: number;
  cap: number;
  errors: string[];
}

/** Group-1 sim ring handed to the graph (src/contracts/bind_group1.json). */
export interface GraphSimRingBindings {
  bindGroup: GPUBindGroup;
  stateBuffer: GPUBuffer;
  indexBuffer: GPUBuffer;
  /** Allocated vec4 elements (post OOM ladder). */
  stateCount: number;
  /** stateCount × 16 bytes. */
  byteSize: number;
}

export interface GraphRunnerContext {
  device: GPUDevice;
  pipelineLayout: GPUPipelineLayout;
  getPipeline: (shaderId: string) => GPUComputePipeline | undefined;
  getWorkgroupSize: (shaderId: string) => { x: number; y: number };
  createBindGroupForRoles: (roles: GraphRoleBindings) => GPUBindGroup;
  /**
   * Bind group already built for `textures` (the renderer's cached compute
   * group). When present no group is created; roles never change inside a
   * run, so every pass of the graph binds the same group.
   */
  bindGroup?: GPUBindGroup;
  textures: GraphRoleBindings;
  scaledW: number;
  scaledH: number;
  maxPassesPerFrame: number;
  shaderId?: string;
  /** True when the entry's pipeline was built against the group-1 layout. */
  usesSimRing?: (shaderId: string) => boolean;
  /** Armed sim ring, or null/undefined when none is allocated. */
  simRing?: GraphSimRingBindings | null;
  /**
   * Optional: return timestampWrites for the Nth compute dispatch in this graph run
   * (0-based among successfully encoded compute passes). Interior passes may return undefined.
   */
  getTimestampWrites?: (
    dispatchIndex: number,
    dispatchCount: number,
  ) => GPUComputePassTimestampWrites | undefined;
}

export class GraphRunner {
  lastReport: GraphRunReport | null = null;

  runGraph(encoder: GPUCommandEncoder, graph: MultipassGraphDef, ctx: GraphRunnerContext): GraphRunReport {
    // Resolve each pipeline once (callers may count getPipeline side effects).
    const resolved = new Map<string, GPUComputePipeline | undefined>();
    const planCtx: FramePlanContext = {
      getPipeline: (id) => {
        if (!resolved.has(id)) resolved.set(id, ctx.getPipeline(id));
        return resolved.get(id);
      },
      getWorkgroupSize: ctx.getWorkgroupSize,
      usesSimRing: (id) => !!ctx.usesSimRing?.(id),
      simRing: ctx.simRing ?? null,
      maxPassesPerFrame: ctx.maxPassesPerFrame,
      framePassBudget: Number.POSITIVE_INFINITY,
    };
    const ops: FrameOp[] = [];
    const report = compileGraphOps(
      ops,
      graph,
      0,
      ctx.shaderId ?? null,
      'chained',
      ctx.maxPassesPerFrame,
      planCtx,
    );
    this.lastReport = report;
    if (report.errors.length > 0) return report;

    const getTimestampWrites = ctx.getTimestampWrites;
    executeFramePlan(
      encoder,
      {
        ops,
        computeCount: report.executed,
        output: 'writeTex',
        graphReports: [report],
      },
      {
        textures: {
          readTex: ctx.textures.read,
          writeTex: ctx.textures.color,
          dataTexA: ctx.textures.dataA,
          dataTexB: ctx.textures.dataB,
          dataTexC: ctx.textures.dataC,
        },
        computeBindGroup: ctx.bindGroup ?? ctx.createBindGroupForRoles(ctx.textures),
        simRing: ctx.simRing ?? null,
        scaledW: ctx.scaledW,
        scaledH: ctx.scaledH,
      },
      {
        timestampWrites: getTimestampWrites
          ? (_op, index, count) => getTimestampWrites(index, count)
          : undefined,
      },
    );
    return report;
  }
}

export const graphRunner = new GraphRunner();

export interface GraphBindingUsage {
  writesDataA: boolean;
  writesDataB: boolean;
  readsDataC: boolean;
}

const graphUsage = new WeakMap<MultipassGraphDef, GraphBindingUsage>();

/** Summarize graph binding usage for frame feedback gating (memoized per graph def). */
export function analyzeGraphBindingUsage(graph: MultipassGraphDef): GraphBindingUsage {
  const cached = graphUsage.get(graph);
  if (cached) return cached;
  const expanded = expandGraph(graph);
  const usage = {
    writesDataA: expanded.some((d) => d.writes.includes('dataA')),
    writesDataB: expanded.some((d) => d.writes.includes('dataB')),
    readsDataC: expanded.some((d) => d.reads.includes('dataC')),
  };
  graphUsage.set(graph, usage);
  return usage;
}
