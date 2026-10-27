/**
 * graphEdges.ts
 *
 * Node-level edges for the Lab's canvas, derived from the planner's own
 * expansion (expandGraph) — the graph has no edge list; reads resolve to
 * whatever wrote that role last, and to the previous frame when nothing did.
 * Edges are therefore a view: they change when roles or node order change.
 */

import { expandGraph, GraphRole, MultipassGraphDef } from '../renderer/multipassGraph';

/** Pseudo-nodes at the ends of the graph. */
export const SOURCE_NODE = '__source';
export const OUTPUT_NODE = '__output';

export interface GraphEdge {
  /** Stable key: `${from}->${to}:${role}`. */
  id: string;
  /** Node index, or SOURCE_NODE / OUTPUT_NODE. */
  from: number | typeof SOURCE_NODE;
  to: number | typeof OUTPUT_NODE;
  /** The role carried (what the reader binds). */
  role: GraphRole;
  /** The data comes from the previous frame (the producer runs later in the frame, or the reader runs first). */
  feedback: boolean;
  /** A copy barrier sits on the edge, e.g. `dataA → dataC`. */
  via?: string;
}

/** The role whose writer feeds a read (dataC is a copy of dataA / dataB, simIndex of simState). */
type Producer = { index: number; role: GraphRole };

export function graphEdges(graph: MultipassGraphDef): GraphEdge[] {
  let dispatches;
  try {
    dispatches = expandGraph(graph);
  } catch {
    return [];
  }
  const indexOf = new Map<string, number>();
  graph.nodes.forEach((n, i) => {
    if (!indexOf.has(n.id)) indexOf.set(n.id, i);
  });

  // Last writer of each role at the end of the frame: what a read sees "from the previous frame".
  const frameEnd = new Map<GraphRole, number>();
  for (const d of dispatches) {
    const i = indexOf.get(d.nodeId);
    if (i !== undefined) for (const w of d.writes) frameEnd.set(w, i);
  }
  // dataC at the start of a frame: the last dataA→dataC / dataB→dataC copy source of the previous frame.
  let frameEndDataC: GraphRole = 'dataA';
  for (const d of dispatches) for (const c of d.copiesBefore) if (c.to === 'dataC') frameEndDataC = c.from;

  const lastWriter = new Map<GraphRole, number>();
  let dataC: Producer | 'previous' = 'previous';
  let dataCVia: string | undefined;
  const edges = new Map<string, GraphEdge>();
  const add = (e: Omit<GraphEdge, 'id'>) => {
    const id = `${e.from}->${e.to}:${e.role}`;
    if (!edges.has(id)) edges.set(id, { id, ...e });
  };

  for (const d of dispatches) {
    const to = indexOf.get(d.nodeId);
    if (to === undefined) continue;
    for (const c of d.copiesBefore) {
      if (c.to !== 'dataC') continue;
      const w = lastWriter.get(c.from);
      dataC = w !== undefined ? { index: w, role: c.from } : 'previous';
      dataCVia = `${c.from} → dataC`;
    }
    for (const role of d.reads) {
      if (role === 'read') {
        add({ from: SOURCE_NODE, to, role, feedback: false });
        continue;
      }
      if (role === 'color') continue;
      if (role === 'dataC') {
        if (dataC !== 'previous') {
          add({ from: dataC.index, to, role, feedback: false, via: dataCVia });
        } else {
          const prev = frameEnd.get(frameEndDataC);
          if (prev !== undefined) add({ from: prev, to, role, feedback: true, via: `${frameEndDataC} → dataC` });
        }
        continue;
      }
      const sourceRole: GraphRole = role === 'simIndex' ? 'simState' : role;
      const via = role === 'simIndex' ? 'simState → simIndex' : undefined;
      const w = lastWriter.get(sourceRole);
      if (w !== undefined) add({ from: w, to, role, feedback: false, via });
      else {
        const prev = frameEnd.get(sourceRole);
        if (prev !== undefined) add({ from: prev, to, role, feedback: true, via });
      }
    }
    for (const role of d.writes) {
      lastWriter.set(role, to);
      if (role === 'color') add({ from: to, to: OUTPUT_NODE, role, feedback: false });
    }
  }
  return [...edges.values()];
}
