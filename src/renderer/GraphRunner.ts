/**
 * GraphRunner.ts
 *
 * Intra-frame multipass graph executor with texture handoff between passes.
 * Tier C: enables same-frame pass-to-pass reads (unlike linear multipassRegistry).
 */

import {
  ExpandedDispatch,
  MultipassGraphDef,
  capGraphDispatches,
  countGraphPasses,
  expandGraph,
  validateGraph,
} from './multipassGraph';
import { CopyBarrier } from './multipassGraph';

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

function encodeCopy(
  encoder: GPUCommandEncoder,
  ctx: GraphRunnerContext,
  copy: CopyBarrier,
): boolean {
  if (copy.from === 'simState') {
    // Buffer twin of dataA → dataC: snapshot live agents for same-frame readers.
    const ring = ctx.simRing;
    if (!ring) return false;
    encoder.copyBufferToBuffer(ring.stateBuffer, 0, ring.indexBuffer, 0, ring.byteSize);
    return true;
  }
  const fromTex = copy.from === 'dataA' ? ctx.textures.dataA : ctx.textures.dataB;
  encoder.copyTextureToTexture(
    { texture: fromTex },
    { texture: ctx.textures.dataC },
    [ctx.scaledW, ctx.scaledH, 1],
  );
  return true;
}

function emptyReport(partial: Partial<GraphRunReport>): GraphRunReport {
  return {
    shaderId: partial.shaderId ?? null,
    requested: partial.requested ?? 0,
    executed: partial.executed ?? 0,
    truncated: partial.truncated ?? 0,
    cap: partial.cap ?? 0,
    errors: partial.errors ?? [],
  };
}

export class GraphRunner {
  lastReport: GraphRunReport | null = null;

  runGraph(encoder: GPUCommandEncoder, graph: MultipassGraphDef, ctx: GraphRunnerContext): GraphRunReport {
    const shaderId = ctx.shaderId ?? null;
    const errors = validateGraph(graph);
    if (errors.length > 0) {
      console.warn('[GraphRunner] Invalid graph:', errors);
      const report = emptyReport({
        shaderId,
        requested: countGraphPasses(graph),
        cap: Math.min(graph.maxPassesPerFrame || 0, ctx.maxPassesPerFrame),
        errors,
      });
      this.lastReport = report;
      return report;
    }

    const cap = Math.min(graph.maxPassesPerFrame, ctx.maxPassesPerFrame);
    const requested = countGraphPasses(graph);
    let expanded = capGraphDispatches(graph, ctx.maxPassesPerFrame);

    const truncated = Math.max(0, requested - expanded.length);
    if (truncated > 0) {
      console.warn(
        `[GraphRunner] Pass cap ${cap} — truncated ${truncated} dispatch(es) (kept color write)`,
      );
    }

    // Resolve pipelines once (avoids double getPipeline side effects in tests/callers).
    const prepared = expanded.map((dispatch) => ({
      dispatch,
      pipeline: ctx.getPipeline(dispatch.entry),
    }));
    const dispatchCount = prepared.filter((p) => !!p.pipeline).length;
    let encodedIndex = 0;

    for (const { dispatch, pipeline } of prepared) {
      if (this.runDispatch(encoder, dispatch, pipeline, ctx, encodedIndex, dispatchCount)) {
        encodedIndex++;
      }
    }

    const report = emptyReport({
      shaderId,
      requested,
      executed: encodedIndex,
      truncated,
      cap,
      errors: [],
    });
    this.lastReport = report;
    return report;
  }

  private runDispatch(
    encoder: GPUCommandEncoder,
    dispatch: ExpandedDispatch,
    pipeline: GPUComputePipeline | undefined,
    ctx: GraphRunnerContext,
    dispatchIndex: number,
    dispatchCount: number,
  ): boolean {
    for (const copy of dispatch.copiesBefore) {
      encodeCopy(encoder, ctx, copy);
    }

    if (!pipeline) {
      console.warn(`[GraphRunner] Pipeline missing for "${dispatch.entry}"`);
      return false;
    }

    const needsRing = !!ctx.usesSimRing?.(dispatch.entry) || dispatch.dispatch === 'simState';
    const ring = ctx.simRing;
    if (needsRing && (!ring || ring.stateCount === 0)) {
      console.warn(`[GraphRunner] "${dispatch.entry}" needs the sim ring but none is armed — skipped`);
      return false;
    }

    const bindGroup = ctx.createBindGroupForRoles(ctx.textures);
    const wg = ctx.getWorkgroupSize(dispatch.entry);

    const label = `graph-${dispatch.nodeId}-${dispatch.iteration}-${dispatch.entry}`;
    const timestampWrites = ctx.getTimestampWrites?.(dispatchIndex, dispatchCount);
    const pass = encoder.beginComputePass(
      timestampWrites ? { label, timestampWrites } : { label },
    );
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    if (needsRing && ring && ctx.usesSimRing?.(dispatch.entry)) {
      pass.setBindGroup(1, ring.bindGroup);
    }
    if (dispatch.dispatch === 'simState' && ring) {
      pass.dispatchWorkgroups(Math.ceil(ring.stateCount / Math.max(1, wg.x)), 1, 1);
    } else {
      pass.dispatchWorkgroups(
        Math.ceil(ctx.scaledW / wg.x),
        Math.ceil(ctx.scaledH / wg.y),
        1,
      );
    }
    pass.end();
    return true;
  }
}

export const graphRunner = new GraphRunner();

/** Summarize graph binding usage for frame feedback gating. */
export function analyzeGraphBindingUsage(graph: MultipassGraphDef): {
  writesDataA: boolean;
  writesDataB: boolean;
  readsDataC: boolean;
} {
  const expanded = expandGraph(graph);
  return {
    writesDataA: expanded.some((d) => d.writes.includes('dataA')),
    writesDataB: expanded.some((d) => d.writes.includes('dataB')),
    readsDataC: expanded.some((d) => d.reads.includes('dataC')),
  };
}
