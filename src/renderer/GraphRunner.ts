/**
 * GraphRunner.ts
 *
 * Intra-frame multipass graph executor with texture handoff between passes.
 * Tier C: enables same-frame pass-to-pass reads (unlike linear multipassRegistry).
 */

import {
  ExpandedDispatch,
  MultipassGraphDef,
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

export class GraphRunner {
  runGraph(encoder: GPUCommandEncoder, graph: MultipassGraphDef, ctx: GraphRunnerContext): void {
    const errors = validateGraph(graph);
    if (errors.length > 0) {
      console.warn('[GraphRunner] Invalid graph:', errors);
      return;
    }

    const cap = Math.min(graph.maxPassesPerFrame, ctx.maxPassesPerFrame);
    let expanded = expandGraph(graph);

    if (expanded.length > cap) {
      console.warn(
        `[GraphRunner] Pass cap ${cap} — skipping ${expanded.length - cap} dispatch(es)`,
      );
      expanded = expanded.slice(0, cap);
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

    const bindGroup = ctx.createBindGroupForRoles(ctx.textures);
    const wg = ctx.getWorkgroupSize(dispatch.entry);

    const label = `graph-${dispatch.nodeId}-${dispatch.iteration}-${dispatch.entry}`;
    const timestampWrites = ctx.getTimestampWrites?.(dispatchIndex, dispatchCount);
    const pass = encoder.beginComputePass(
      timestampWrites ? { label, timestampWrites } : { label },
    );
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(
      Math.ceil(ctx.scaledW / wg.x),
      Math.ceil(ctx.scaledH / wg.y),
      1,
    );
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
