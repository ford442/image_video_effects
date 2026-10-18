/**
 * nodeScaleAdvisor.ts
 *
 * Decides whether adaptive performance should shrink one expensive opt-in
 * graph node instead of the whole canvas (#1314 WP-4). Pure: fed with the
 * profiler's per-pass timings and the bound scalable nodes, returns a decision.
 *
 *  - Under target FPS: if the heaviest compute pass takes more than
 *    NODE_DEMOTE_SHARE of compute GPU time and is a scalable node above its
 *    floor, demote that node one step (0.25). Otherwise let the global
 *    resolution scale step down as before.
 *  - Above target FPS: undo node demotions first (most recent first), then
 *    let the global scale step up.
 */

import { computeGpuMs, heaviestComputePass, PassTiming } from './passTimings';

export const NODE_SCALE_STEP = 0.25;
/** Minimum share of compute GPU time before a single node is singled out. */
export const NODE_DEMOTE_SHARE = 0.35;

export interface ScalableNodeState {
  slot: number;
  nodeId: string;
  minScale: number;
  scale: number;
}

export type NodeScaleAdvice =
  | { kind: 'node'; slot: number; nodeId: string; scale: number }
  | { kind: 'global' };

export function adviseNodeDemotion(
  passes: readonly PassTiming[],
  nodes: readonly ScalableNodeState[],
): NodeScaleAdvice {
  const total = computeGpuMs(passes);
  const heaviest = heaviestComputePass(passes);
  if (!heaviest || total <= 0 || heaviest.gpuMs / total < NODE_DEMOTE_SHARE) return { kind: 'global' };
  const node = nodes.find((n) => n.slot === heaviest.slot && n.nodeId === heaviest.nodeId);
  if (!node || node.scale - NODE_SCALE_STEP < node.minScale - 1e-6) return { kind: 'global' };
  return { kind: 'node', slot: node.slot, nodeId: node.nodeId, scale: node.scale - NODE_SCALE_STEP };
}

/**
 * Promote demoted nodes before the global scale: the most recently demoted
 * one (per `demotionOrder`, else any) goes back up one step.
 */
export function adviseNodePromotion(
  nodes: readonly ScalableNodeState[],
  demotionOrder: readonly string[] = [],
): NodeScaleAdvice {
  const demoted = nodes.filter((n) => n.scale < 1);
  if (demoted.length === 0) return { kind: 'global' };
  const rank = (n: ScalableNodeState) => demotionOrder.lastIndexOf(`${n.slot}:${n.nodeId}`);
  const node = demoted.reduce((best, n) => (rank(n) > rank(best) ? n : best));
  return { kind: 'node', slot: node.slot, nodeId: node.nodeId, scale: Math.min(1, node.scale + NODE_SCALE_STEP) };
}
