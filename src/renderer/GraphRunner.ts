/**
 * GraphRunner.ts
 *
 * Intra-frame multipass graph executor with texture handoff between passes.
 * Tier C: enables same-frame pass-to-pass reads (unlike linear multipassRegistry).
 */

import {
  BufferCopyBarrier,
  ExpandedDispatch,
  MultipassGraphDef,
  capGraphDispatches,
  countGraphPasses,
  expandGraph,
  graphUsesSimRing,
  trailingBufferCopies,
  validateGraph,
} from './multipassGraph';
import { CopyBarrier } from './multipassGraph';
import type { SimRingBindings } from './webgpu/simRing';

export interface GraphRoleBindings {
  read: GPUTexture;
  color: GPUTexture;
  dataA: GPUTexture;
  dataB: GPUTexture;
  dataC: GPUTexture;
}

export interface GraphSimRingReport {
  /** Live simState elements (after the OOM ladder); 0 when the ring is missing. */
  particles: number;
  /** The OOM ladder shrank the ring below its default capacity. */
  truncated: boolean;
  /** simState → simIndex barriers encoded this run (including the trailing publish). */
  bufferCopies: number;
}

export interface GraphRunReport {
  shaderId: string | null;
  requested: number;
  executed: number;
  truncated: number;
  cap: number;
  errors: string[];
  /** Null for graphs that never touch the group-1 sim ring. */
  simRing: GraphSimRingReport | null;
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
  /** Group-1 sim ring, when allocated (bind_group1.json). */
  simRing?: SimRingBindings | null;
  /** Whether an entry's pipeline was built on the two-group layout (must bind group 1). */
  usesSimRing?: (shaderId: string) => boolean;
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
): void {
  const fromTex = copy.from === 'dataA' ? ctx.textures.dataA : ctx.textures.dataB;
  encoder.copyTextureToTexture(
    { texture: fromTex },
    { texture: ctx.textures.dataC },
    [ctx.scaledW, ctx.scaledH, 1],
  );
}

function encodeBufferCopy(
  encoder: GPUCommandEncoder,
  ring: SimRingBindings,
  _copy: BufferCopyBarrier,
): void {
  encoder.copyBufferToBuffer(ring.stateBuf, 0, ring.indexBuf, 0, ring.copyBytes);
}

function nodeNeedsSimRing(dispatch: ExpandedDispatch): boolean {
  return (
    dispatch.dispatch === 'simState' ||
    dispatch.bufferReads.length > 0 ||
    dispatch.bufferWrites.length > 0
  );
}

function emptyReport(partial: Partial<GraphRunReport>): GraphRunReport {
  return {
    shaderId: partial.shaderId ?? null,
    requested: partial.requested ?? 0,
    executed: partial.executed ?? 0,
    truncated: partial.truncated ?? 0,
    cap: partial.cap ?? 0,
    errors: partial.errors ?? [],
    simRing: partial.simRing ?? null,
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
    const ring = ctx.simRing ?? null;
    const runErrors: string[] = [];
    const dispatchCount = prepared.filter(
      (p) => !!p.pipeline && (ring || !this.needsRing(p.dispatch, ctx)),
    ).length;
    let encodedIndex = 0;
    let bufferCopies = 0;

    for (const { dispatch, pipeline } of prepared) {
      const outcome = this.runDispatch(encoder, dispatch, pipeline, ctx, encodedIndex, dispatchCount);
      bufferCopies += outcome.bufferCopies;
      if (outcome.error) runErrors.push(outcome.error);
      if (outcome.encoded) encodedIndex++;
    }

    if (ring) {
      for (const copy of trailingBufferCopies(expanded)) {
        encodeBufferCopy(encoder, ring, copy);
        bufferCopies++;
      }
    }

    const report = emptyReport({
      shaderId,
      requested,
      executed: encodedIndex,
      truncated,
      cap,
      errors: runErrors,
      simRing: graphUsesSimRing(graph)
        ? {
            particles: ring?.stateCount ?? 0,
            truncated: ring?.truncated ?? false,
            bufferCopies,
          }
        : null,
    });
    this.lastReport = report;
    return report;
  }

  private needsRing(dispatch: ExpandedDispatch, ctx: GraphRunnerContext): boolean {
    return nodeNeedsSimRing(dispatch) || (ctx.usesSimRing?.(dispatch.entry) ?? false);
  }

  private runDispatch(
    encoder: GPUCommandEncoder,
    dispatch: ExpandedDispatch,
    pipeline: GPUComputePipeline | undefined,
    ctx: GraphRunnerContext,
    dispatchIndex: number,
    dispatchCount: number,
  ): { encoded: boolean; bufferCopies: number; error?: string } {
    for (const copy of dispatch.copiesBefore) {
      encodeCopy(encoder, ctx, copy);
    }

    const ring = ctx.simRing ?? null;
    let bufferCopies = 0;
    if (ring) {
      for (const copy of dispatch.bufferCopiesBefore) {
        encodeBufferCopy(encoder, ring, copy);
        bufferCopies++;
      }
    }

    if (!pipeline) {
      console.warn(`[GraphRunner] Pipeline missing for "${dispatch.entry}"`);
      return { encoded: false, bufferCopies };
    }

    if (!ring && this.needsRing(dispatch, ctx)) {
      const error = `node ${dispatch.nodeId}: sim ring not allocated — "${dispatch.entry}" skipped`;
      console.warn(`[GraphRunner] ${error}`);
      return { encoded: false, bufferCopies, error };
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
    if (ring && ctx.usesSimRing?.(dispatch.entry)) {
      pass.setBindGroup(1, ring.bindGroup);
    }
    if (dispatch.dispatch === 'simState' && ring) {
      pass.dispatchWorkgroups(Math.max(1, Math.ceil(ring.stateCount / wg.x)), 1, 1);
    } else {
      pass.dispatchWorkgroups(
        Math.ceil(ctx.scaledW / wg.x),
        Math.ceil(ctx.scaledH / wg.y),
        1,
      );
    }
    pass.end();
    return { encoded: true, bufferCopies };
  }
}

export const graphRunner = new GraphRunner();

/** Summarize graph binding usage for frame feedback gating. */
export function analyzeGraphBindingUsage(graph: MultipassGraphDef): {
  writesDataA: boolean;
  writesDataB: boolean;
  readsDataC: boolean;
  usesSimRing: boolean;
} {
  const expanded = expandGraph(graph);
  return {
    writesDataA: expanded.some((d) => d.writes.includes('dataA')),
    writesDataB: expanded.some((d) => d.writes.includes('dataB')),
    readsDataC: expanded.some((d) => d.reads.includes('dataC')),
    usesSimRing: graphUsesSimRing(graph),
  };
}
