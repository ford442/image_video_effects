/**
 * GraphRunner.ts
 *
 * Intra-frame multipass graph executor with texture handoff between passes.
 * Tier C: enables same-frame pass-to-pass reads (unlike linear multipassRegistry).
 */

import { MultipassGraph, MultipassGraphNode, validateGraph } from './multipassGraph';

export interface GraphRunnerContext {
  device: GPUDevice;
  pipelineLayout: GPUPipelineLayout;
  getPipeline: (shaderId: string) => GPUComputePipeline | undefined;
  getWorkgroupSize: (shaderId: string) => { x: number; y: number };
  createBindGroupForPass: (readTex: GPUTexture, writeTex: GPUTexture) => GPUBindGroup;
  textures: {
    readTex: GPUTexture;
    writeTex: GPUTexture;
    dataTexA: GPUTexture;
    dataTexB: GPUTexture;
    dataTexC: GPUTexture;
  };
  scaledW: number;
  scaledH: number;
}

function resolveTexture(
  role: 'read' | 'write' | 'dataA' | 'dataB' | 'dataC',
  textures: GraphRunnerContext['textures'],
): GPUTexture {
  switch (role) {
    case 'read': return textures.readTex;
    case 'write': return textures.writeTex;
    case 'dataA': return textures.dataTexA;
    case 'dataB': return textures.dataTexB;
    case 'dataC': return textures.dataTexC;
  }
}

export class GraphRunner {
  runGraph(encoder: GPUCommandEncoder, graph: MultipassGraph, ctx: GraphRunnerContext): void {
    const errors = validateGraph(graph);
    if (errors.length > 0) {
      console.warn('[GraphRunner] Invalid graph:', errors);
      return;
    }

    for (const node of graph.nodes) {
      this.runNode(encoder, node, ctx);
    }
  }

  private runNode(
    encoder: GPUCommandEncoder,
    node: MultipassGraphNode,
    ctx: GraphRunnerContext,
  ): void {
    if (node.type === 'pass') {
      this.dispatchPass(encoder, node.shaderId, node.readTexture, node.writeTexture, ctx);
      return;
    }

    if (node.type === 'pingPong') {
      for (let i = 0; i < node.iterations; i++) {
        const read = i % 2 === 0 ? 'dataA' : 'dataB';
        const write = i % 2 === 0 ? 'dataB' : 'dataA';
        this.dispatchPass(encoder, node.shaderId, read, write, ctx);
      }
      return;
    }

    if (node.type === 'loop') {
      for (let i = 0; i < node.iterations; i++) {
        for (const child of node.body) {
          this.runNode(encoder, child, ctx);
        }
      }
    }
  }

  private dispatchPass(
    encoder: GPUCommandEncoder,
    shaderId: string,
    readRole: 'read' | 'dataA' | 'dataB' | 'dataC',
    writeRole: 'write' | 'dataA' | 'dataB',
    ctx: GraphRunnerContext,
  ): void {
    const pipeline = ctx.getPipeline(shaderId);
    if (!pipeline) {
      console.warn(`[GraphRunner] Pipeline missing for "${shaderId}"`);
      return;
    }

    const readTex = resolveTexture(readRole, ctx.textures);
    const writeTex = resolveTexture(writeRole, ctx.textures);
    const bindGroup = ctx.createBindGroupForPass(readTex, writeTex);
    const wg = ctx.getWorkgroupSize(shaderId);

    const pass = encoder.beginComputePass({ label: `graph-${shaderId}` });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(
      Math.ceil(ctx.scaledW / wg.x),
      Math.ceil(ctx.scaledH / wg.y),
      1,
    );
    pass.end();
  }
}

export const graphRunner = new GraphRunner();
