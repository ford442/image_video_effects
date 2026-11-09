/**
 * runDraft.ts
 *
 * Runs a draft in the real renderer: the draft is registered as a runtime graph
 * (renderer/runtimeGraphs.ts) under one fixed id and bound to a slot, so it goes
 * through the same planner, pass budgets, truncation and color-writer rules as
 * any shipped graph — the Lab adds no execution path of its own.
 *
 * Sim-ring drafts send their `simRing` request with the graph. The ring itself is
 * armed only the way a shipped definition arms it: compiling an entry that
 * declares @group(1) runs SimRing.ensure with resolveSimRingRequest(entry). An
 * entry that never declares @group(1) keeps the group-0 pipeline and is never
 * bound to group 1, whatever the toggle says.
 */

import type { GraphRunReport } from '../renderer/GraphRunner';
import type { MultipassGraphDef } from '../renderer/multipassGraph';
import type { PassTiming } from '../renderer/passTimings';
import type { RendererManager } from '../renderer/RendererManager';
import { GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';
import { analyzeGraph } from './graphAnalysis';
import { GraphDraft, simRingRequest } from './graphDraft';

export type RunResult =
  | { ok: true; slot: number; entries: string[]; previousShaderId: string | null }
  | { ok: false; reason: 'invalid' | 'empty' | 'backend' | 'load-failed'; message: string };

export interface LiveReading {
  /** The planner's report for the running draft; null until it has compiled a frame. */
  report: GraphRunReport | null;
  /** Smoothed GPU ms per node for the running draft (empty until timestamps resolve). */
  passTimings: PassTiming[];
}

const entryUrl = (entry: string) => `shaders/${entry}.wgsl`;

/** A fresh object per run: the renderer memoises plans per graph object. */
export function cloneGraph(graph: MultipassGraphDef): MultipassGraphDef {
  return {
    maxPassesPerFrame: graph.maxPassesPerFrame,
    nodes: graph.nodes.map((n) => ({ ...n, reads: [...(n.reads ?? [])], writes: [...(n.writes ?? [])] })),
  };
}

export async function runDraft(
  manager: RendererManager,
  slot: number,
  draft: GraphDraft,
  options: {
    knownEntries?: Set<string>;
    previousShaderId?: string | null;
    /**
     * Recompile every entry of a sim-ring draft so its group-1 entries re-run
     * SimRing.ensure with the draft's request (and re-seed at frame 0). Set on
     * Run and when the requested size changes; plain edits keep the ring running.
     */
    rearmSimRing?: boolean;
  } = {},
): Promise<RunResult> {
  if (draft.graph.nodes.length === 0) {
    return { ok: false, reason: 'empty', message: 'Add at least one node to run the graph.' };
  }
  const analysis = analyzeGraph(draft.graph, options.knownEntries ? { knownEntries: options.knownEntries } : {});
  if (!analysis.valid) {
    return { ok: false, reason: 'invalid', message: analysis.errors[0]?.message ?? 'The graph has errors.' };
  }

  const previousShaderId =
    options.previousShaderId !== undefined
      ? options.previousShaderId
      : (manager.getSlotState(slot)?.shaderId ?? null);

  // Registered before loading: loadShader pulls every graph entry through hasGraph / getGraphEntryIds.
  const graph = cloneGraph(draft.graph);
  const simRing = simRingRequest(draft);
  if (!manager.setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, graph, simRing)) {
    return { ok: false, reason: 'backend', message: 'Graphs run on the TypeScript WebGPU renderer only.' };
  }

  const entries = Array.from(new Set(graph.nodes.map((n) => n.entry)));
  const recompile = !!simRing && !!options.rearmSimRing;
  // The root id needs a compiled pipeline (the planner gates slots on it); the first entry's WGSL serves.
  if (recompile || !manager.isShaderCached(GRAPH_LAB_RUNTIME_ID)) {
    const rootEntry = entries[0];
    if (!rootEntry) return { ok: false, reason: 'empty', message: 'The graph has no entries to compile.' };
    const ok = await manager.loadShader(GRAPH_LAB_RUNTIME_ID, entryUrl(rootEntry));
    if (!ok) return { ok: false, reason: 'load-failed', message: `Could not compile "${rootEntry}".` };
  }
  for (const entry of entries) {
    if (!recompile && manager.isShaderCached(entry)) continue;
    const ok = await manager.loadShader(entry, entryUrl(entry));
    if (!ok) return { ok: false, reason: 'load-failed', message: `Could not compile "${entry}".` };
  }

  manager.setSlotShader(slot, GRAPH_LAB_RUNTIME_ID);
  return { ok: true, slot, entries, previousShaderId };
}

/**
 * Drop the draft and put the slot back the way it was — unless the slot no longer
 * shows the draft (the user picked another shader meanwhile), which is left alone.
 */
export function stopDraft(manager: RendererManager, slot: number, previousShaderId: string | null): void {
  if (manager.getSlotState(slot)?.shaderId === GRAPH_LAB_RUNTIME_ID) {
    manager.setSlotShader(slot, previousShaderId ?? '');
  }
  manager.setRuntimeGraph(GRAPH_LAB_RUNTIME_ID, null);
}

/** Live planner report and per-node GPU time for the running draft. */
export function readLive(manager: RendererManager): LiveReading {
  const report = manager.getDiagnostics().webgpu?.graph ?? null;
  const mine = report && report.shaderId === GRAPH_LAB_RUNTIME_ID ? report : null;
  const passTimings = manager
    .getPassTimings()
    .filter((t) => t.kind === 'compute' && t.shaderId === GRAPH_LAB_RUNTIME_ID);
  return { report: mine, passTimings };
}

// ── Inline WGSL drafts ─────────────────────────────────────────────────────

/** What the WGSL runner needs from the renderer (RendererManager satisfies it). */
export type WgslRunnerHost = Pick<RendererManager, 'loadShader' | 'setSlotShader' | 'getSlotState' | 'setSlotParams'>;

export type WgslSwapResult =
  | { ok: true; shaderId: string }
  /** `superseded`: a newer text arrived while this one compiled; it was never bound. */
  | { ok: false; reason: 'compile' | 'superseded' | 'stopped'; message: string };

/**
 * Runtime ids of a slot's draft. Two per slot, used in turn: the next text compiles
 * under the id that is not bound, so the slot keeps rendering the last good pipeline
 * until the new one has compiled, and a failed compile never touches it.
 */
export function wgslRuntimeIds(slot: number): [string, string] {
  return [`graphlab-wgsl-${slot}-a`, `graphlab-wgsl-${slot}-b`];
}

export const isWgslRuntimeId = (id: string | null | undefined): boolean => !!id && id.startsWith('graphlab-wgsl-');

/**
 * Hot-swaps one slot's WGSL draft. `submit` takes the include-expanded module of a
 * text that already passed naga; only the latest submitted text is compiled (older
 * queued ones are skipped) and bound. Nothing is bound before a compile succeeds,
 * so starting never shows a black frame and an edit that fails keeps the old one.
 */
export class WgslDraftRunner {
  private bound: string | null = null;
  private latest = 0;
  private chain: Promise<unknown> = Promise.resolve();
  private stopped = false;
  private readonly ids: [string, string];

  constructor(
    private readonly host: WgslRunnerHost,
    readonly slot: number,
    readonly previousShaderId: string | null,
    private readonly makeUrl: (wgsl: string) => { url: string; release(): void } = blobUrl,
  ) {
    this.ids = wgslRuntimeIds(slot);
  }

  /** The runtime id currently bound to the slot (null until the first good compile). */
  get shaderId(): string | null {
    return this.bound;
  }

  submit(expandedWgsl: string): Promise<WgslSwapResult> {
    const mine = ++this.latest;
    const job = this.chain.then(() => this.swap(expandedWgsl, mine));
    this.chain = job.catch(() => undefined);
    return job;
  }

  private async swap(wgsl: string, mine: number): Promise<WgslSwapResult> {
    if (this.stopped) return { ok: false, reason: 'stopped', message: 'The draft was stopped.' };
    if (mine !== this.latest) return { ok: false, reason: 'superseded', message: 'A newer edit replaced this one.' };
    const target = this.bound === this.ids[0] ? this.ids[1] : this.ids[0];
    const { url, release } = this.makeUrl(wgsl);
    let ok = false;
    try {
      ok = await this.host.loadShader(target, url);
    } finally {
      release();
    }
    if (this.stopped) return { ok: false, reason: 'stopped', message: 'The draft was stopped.' };
    if (!ok) {
      return {
        ok: false,
        reason: 'compile',
        message: this.bound
          ? 'The GPU rejected this version; the last good one keeps running.'
          : 'The GPU rejected this shader.',
      };
    }
    // A newer text compiled meanwhile is still queued; binding this one first is fine (it is good).
    this.host.setSlotShader(this.slot, target);
    this.bound = target;
    return { ok: true, shaderId: target };
  }

  setParams(values: readonly [number, number, number, number]): void {
    if (this.stopped) return;
    this.host.setSlotParams(this.slot, values[0], values[1], values[2], values[3]);
  }

  /** Still the slot's shader? (false once the user picked another one). */
  isBound(): boolean {
    const current = this.host.getSlotState(this.slot)?.shaderId ?? null;
    return !!this.bound && current === this.bound;
  }

  /** Put the slot back, unless someone else already took it. */
  stop(): void {
    this.stopped = true;
    if (this.isBound()) this.host.setSlotShader(this.slot, this.previousShaderId ?? '');
    this.bound = null;
  }
}

function blobUrl(wgsl: string): { url: string; release(): void } {
  const url = URL.createObjectURL(new Blob([wgsl], { type: 'text/plain' }));
  return { url, release: () => URL.revokeObjectURL(url) };
}
