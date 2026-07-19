/**
 * multipassGraph.ts
 *
 * Graph builder + validator for Tier C multipass simulations.
 * Extends linear multipassRegistry chains with ping-pong and loop nodes.
 */

import { isMultipassStart } from './multipassRegistry';

export type GraphNodeType = 'pass' | 'pingPong' | 'loop';

export interface GraphPassNode {
  type: 'pass';
  id: string;
  shaderId: string;
  readTexture: 'read' | 'dataA' | 'dataB' | 'dataC';
  writeTexture: 'write' | 'dataA' | 'dataB';
}

export interface GraphPingPongNode {
  type: 'pingPong';
  id: string;
  shaderId: string;
  iterations: number;
  bufferA: 'dataA';
  bufferB: 'dataB';
}

export interface GraphLoopNode {
  type: 'loop';
  id: string;
  body: MultipassGraphNode[];
  iterations: number;
}

export type MultipassGraphNode = GraphPassNode | GraphPingPongNode | GraphLoopNode;

export interface MultipassGraph {
  id: string;
  nodes: MultipassGraphNode[];
}

export function validateGraph(graph: MultipassGraph): string[] {
  const errors: string[] = [];
  if (!graph.id) errors.push('graph.id is required');
  if (graph.nodes.length === 0) errors.push('graph must have at least one node');

  for (const node of graph.nodes) {
    if (node.type === 'pass' && !node.shaderId) {
      errors.push(`pass node ${node.id}: shaderId required`);
    }
    if (node.type === 'pingPong') {
      if (node.iterations < 1 || node.iterations > 64) {
        errors.push(`pingPong node ${node.id}: iterations must be 1–64`);
      }
    }
    if (node.type === 'loop') {
      if (node.iterations < 1) errors.push(`loop node ${node.id}: iterations must be >= 1`);
      errors.push(...validateGraph({ id: `${graph.id}:${node.id}`, nodes: node.body }));
    }
  }
  return errors;
}

/** Demo graph: 3-pass chain with same-frame handoff (quantum-foam multipass). */
export function createRippleTankGraph(): MultipassGraph {
  return {
    id: 'quantum-foam-graph',
    nodes: [
      {
        type: 'pass',
        id: 'integrate',
        shaderId: 'quantum-foam-pass1',
        readTexture: 'dataC',
        writeTexture: 'dataA',
      },
      {
        type: 'pass',
        id: 'composite',
        shaderId: 'quantum-foam-pass2',
        readTexture: 'dataA',
        writeTexture: 'dataB',
      },
      {
        type: 'pass',
        id: 'render',
        shaderId: 'quantum-foam-pass3',
        readTexture: 'dataB',
        writeTexture: 'write',
      },
    ],
  };
}

/** Shaders that use Tier C graph runner (same-frame texture handoff). */
const GRAPH_BY_START_SHADER: Record<string, () => MultipassGraph> = {
  'quantum-foam-pass1': createRippleTankGraph,
};

/** Resolve a graph for multipass starters that need intra-frame handoff. */
export function resolveGraphForShader(shaderId: string): MultipassGraph | null {
  if (!isMultipassStart(shaderId)) return null;
  const factory = GRAPH_BY_START_SHADER[shaderId];
  return factory ? factory() : null;
}
