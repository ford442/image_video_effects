import { RefObject, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { loadNagaReflector } from '../../utils/nagaWasm';
import { fetchShaderWgsl } from '../../utils/fetchShaderWgsl';
import type { RendererManager } from '../../renderer/RendererManager';
import { GRAPH_REGISTRY, SIM_RING_REGISTRY } from '../../renderer/multipassRegistry';
import { GRAPH_LAB_RUNTIME_ID } from '../../renderer/runtimeGraphs';
import type { ShaderEntry } from '../../renderer/types';
import { buildEntryCatalog, EntryCatalog } from '../../graphLab/entryCatalog';
import { analyzeGraph, GraphAnalysis } from '../../graphLab/graphAnalysis';
import {
  canRedo,
  canUndo,
  createHistory,
  DraftHistory,
  pushHistory,
  redo as redoHistory,
  undo as undoHistory,
} from '../../graphLab/draftHistory';
import {
  draftFromDefinition,
  draftFromRegistryGraph,
  forkDraft,
  GraphDraft,
  newDraft,
  simRingRequest,
  upgradeDraft,
} from '../../graphLab/graphDraft';
import { createPortInference, EntryPorts, PortInference, portWarnings } from '../../graphLab/portInference';
import { exportGraphDefinition, ExportResult } from '../../graphLab/graphExport';
import { LiveReading, readLive, runDraft, stopDraft } from '../../graphLab/runDraft';

export const DRAFT_STORAGE_KEY = 'graphlab.draft.v2';
/** v1 drafts (no layout) are read once and upgraded. */
export const LEGACY_DRAFT_STORAGE_KEY = 'graphlab.draft.v1';
/** Flagship the Lab opens on when nothing is stored, so the first view is a graph that runs. */
export const SEED_GRAPH_ID = 'wave-tank';
const LIVE_POLL_MS = 500;
const HOT_RUN_DEBOUNCE_MS = 150;

export interface UseGraphLabArgs {
  rendererRef: RefObject<RendererManager | null>;
  availableModes: ShaderEntry[];
  activeSlot: number;
  setStatus?: (status: string) => void;
  /** Test seam; defaults to naga reflection of the same-origin, include-expanded WGSL. */
  portInference?: PortInference;
}

let browserPortInference: PortInference | null = null;

/** One cache per page: an entry's WGSL does not change while the app runs. */
function defaultPortInference(): PortInference {
  browserPortInference ??= createPortInference({
    loadSource: (entry) => fetchShaderWgsl(entry, undefined, { primaryOnly: true }),
    reflect: loadNagaReflector,
  });
  return browserPortInference;
}

/** How an edit is recorded: `coalesce` folds rapid edits with the same key into one undo step. */
export interface EditOptions {
  coalesce?: string;
}

export interface RunningState {
  slot: number;
  previousShaderId: string | null;
}

/** A working copy of a shipped graph under `<id>-lab` (export never silently replaces the original). */
function templateDraft(id: string, availableModes: ShaderEntry[]): GraphDraft | null {
  const graph = GRAPH_REGISTRY[id];
  if (!graph) return null;
  const entry = availableModes.find((m) => m.id === id);
  const draft = draftFromRegistryGraph(id, graph, entry);
  // The request ships with the definition: a flagship that needs the spatial hash must keep asking for it.
  const ring = SIM_RING_REGISTRY[id];
  const withRing = ring && draft.envelope.simRing === undefined ? { ...draft, envelope: { ...draft.envelope, simRing: { ...ring } } } : draft;
  return forkDraft(withRing, `${id}-lab`, `${entry?.name ?? id} (lab)`);
}

function loadStoredDraft(availableModes: ShaderEntry[]): GraphDraft {
  try {
    for (const key of [DRAFT_STORAGE_KEY, LEGACY_DRAFT_STORAGE_KEY]) {
      const raw = window.localStorage.getItem(key);
      const draft = raw ? upgradeDraft(JSON.parse(raw)) : null;
      if (draft) return draft;
    }
  } catch {
    // Missing / blocked / corrupt storage: start from the seed.
  }
  return templateDraft(SEED_GRAPH_ID, availableModes) ?? newDraft();
}

function storeDraft(draft: GraphDraft): void {
  try {
    window.localStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(draft));
  } catch {
    // Private window or quota: the draft simply is not remembered.
  }
}

export function useGraphLab({ rendererRef, availableModes, activeSlot, setStatus, portInference }: UseGraphLabArgs) {
  const [history, setHistory] = useState<DraftHistory<GraphDraft>>(() => createHistory(loadStoredDraft(availableModes)));
  const draft = history.present;
  const [selected, setSelected] = useState(0);
  const [running, setRunning] = useState<RunningState | null>(null);
  const [runError, setRunError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [live, setLive] = useState<LiveReading | null>(null);
  const runningRef = useRef<RunningState | null>(null);
  runningRef.current = running;

  const entries: EntryCatalog | null = useMemo(
    () => (availableModes.length > 0 ? buildEntryCatalog(availableModes) : null),
    [availableModes],
  );
  const analysis: GraphAnalysis = useMemo(
    () => analyzeGraph(draft.graph, entries ? { knownEntries: entries.knownEntries } : {}),
    [draft.graph, entries],
  );
  const exportResult: ExportResult = useMemo(
    () => exportGraphDefinition(draft, { entries }),
    [draft, entries],
  );
  const simRing = simRingRequest(draft);
  // Identity of the ring request: a change re-arms the ring, plain graph edits do not.
  // The hash is part of the ring's allocation, so toggling it re-arms exactly like a size change.
  const simRingKey = simRing ? `${simRing.stateCount}${simRing.spatialHash ? ':hash' : ''}` : '';
  const armedSimRingRef = useRef<string | null>(null);

  const setDraft = useCallback(
    (next: GraphDraft | ((prev: GraphDraft) => GraphDraft), opts: EditOptions = {}) => {
      setHistory((h) => pushHistory(h, typeof next === 'function' ? next(h.present) : next, opts));
    },
    [],
  );
  const undo = useCallback(() => setHistory(undoHistory), []);
  const redo = useCallback(() => setHistory(redoHistory), []);

  // Every present (edit, undo, redo) is the autosaved draft.
  useEffect(() => storeDraft(draft), [draft]);

  // ── Port inference: what each entry's WGSL binds (naga reflection). ──
  const inference = useMemo(() => portInference ?? defaultPortInference(), [portInference]);
  const [ports, setPorts] = useState<ReadonlyMap<string, EntryPorts>>(() => new Map());
  const entryKey = useMemo(() => [...new Set(draft.graph.nodes.map((n) => n.entry))].sort().join('\n'), [draft.graph]);
  useEffect(() => {
    let cancelled = false;
    const wanted = entryKey ? entryKey.split('\n') : [];
    for (const entry of wanted) {
      void inference.request(entry).then((p) => {
        if (cancelled) return;
        setPorts((prev) => (prev.get(entry) === p ? prev : new Map(prev).set(entry, p)));
      });
    }
    return () => {
      cancelled = true;
    };
  }, [entryKey, inference]);
  const warnings = useMemo(() => portWarnings(draft.graph.nodes, ports), [draft.graph.nodes, ports]);

  /** Ports of `entry`, inferring them if needed (resolves to an `error` status rather than rejecting). */
  const inferPorts = useCallback((entry: string) => inference.request(entry), [inference]);

  // Keep the selection inside the node list as nodes come and go.
  useEffect(() => {
    setSelected((s) => Math.max(0, Math.min(s, draft.graph.nodes.length - 1)));
  }, [draft.graph.nodes.length]);

  const start = useCallback(async (): Promise<boolean> => {
    const manager = rendererRef.current;
    if (!manager) {
      setRunError('The renderer is not ready yet.');
      return false;
    }
    setBusy(true);
    const result = await runDraft(manager, activeSlot, draft, {
      knownEntries: entries?.knownEntries,
      previousShaderId: runningRef.current?.previousShaderId,
      rearmSimRing: true,
    });
    setBusy(false);
    armedSimRingRef.current = simRingKey;
    if (!result.ok) {
      setRunError(result.message);
      return false;
    }
    setRunError(null);
    setRunning({ slot: result.slot, previousShaderId: result.previousShaderId });
    setStatus?.(`Graph Lab is running "${draft.name}" in slot ${result.slot + 1}`);
    return true;
  }, [rendererRef, activeSlot, draft, entries, setStatus, simRingKey]);

  const stop = useCallback(() => {
    const manager = rendererRef.current;
    const current = runningRef.current;
    if (manager && current) stopDraft(manager, current.slot, current.previousShaderId);
    setRunning(null);
    setLive(null);
  }, [rendererRef]);

  // Edits while running are applied live, as long as the graph still validates.
  useEffect(() => {
    if (!runningRef.current || !analysis.valid) return undefined;
    const manager = rendererRef.current;
    if (!manager) return undefined;
    const current = runningRef.current;
    const rearmSimRing = armedSimRingRef.current !== simRingKey;
    const timer = setTimeout(() => {
      armedSimRingRef.current = simRingKey;
      void runDraft(manager, current.slot, draft, {
        knownEntries: entries?.knownEntries,
        previousShaderId: current.previousShaderId,
        rearmSimRing,
      }).then((r) => setRunError(r.ok ? null : r.message));
    }, HOT_RUN_DEBOUNCE_MS);
    return () => clearTimeout(timer);
    // Re-run on graph identity (every edit makes a new graph object) and on the ring request.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft.graph, simRingKey]);

  // Live planner report + per-node GPU time while the draft is bound to a slot.
  useEffect(() => {
    if (!running) return undefined;
    const tick = () => {
      const manager = rendererRef.current;
      if (!manager) return;
      // Someone else took the slot (picked another shader, backend rebuilt): we are no longer running.
      if (manager.getSlotState(running.slot)?.shaderId !== GRAPH_LAB_RUNTIME_ID) {
        setRunning(null);
        setLive(null);
        return;
      }
      setLive(readLive(manager));
    };
    tick();
    const id = setInterval(tick, LIVE_POLL_MS);
    return () => clearInterval(id);
  }, [running, rendererRef]);

  // Closing the Lab puts the slot back.
  useEffect(
    () => () => {
      const manager = rendererRef.current;
      const current = runningRef.current;
      if (manager && current) stopDraft(manager, current.slot, current.previousShaderId);
    },
    [rendererRef],
  );

  const templates = useMemo(
    () =>
      Object.keys(GRAPH_REGISTRY)
        .sort()
        .map((id) => ({ id, name: availableModes.find((m) => m.id === id)?.name ?? id })),
    [availableModes],
  );

  const loadTemplate = useCallback(
    (id: string) => {
      const template = templateDraft(id, availableModes);
      if (!template) return;
      setDraft(template);
      setSelected(0);
      setNotice(`Started from "${id}". Export saves it under "${id}-lab".`);
    },
    [availableModes, setDraft],
  );

  const importText = useCallback(
    (text: string) => {
      try {
        const res = draftFromDefinition(JSON.parse(text));
        if (!res.ok) {
          setNotice(null);
          setRunError(res.error);
          return false;
        }
        setDraft(res.draft);
        setSelected(0);
        setRunError(null);
        setNotice(`Imported "${res.draft.id}".`);
        return true;
      } catch (err) {
        setRunError(`That file is not valid JSON: ${(err as Error).message}`);
        return false;
      }
    },
    [setDraft],
  );

  const reset = useCallback(() => {
    setDraft(newDraft());
    setSelected(0);
    setRunError(null);
    setNotice(null);
  }, [setDraft]);

  return {
    draft,
    setDraft,
    undo,
    redo,
    canUndo: canUndo(history),
    canRedo: canRedo(history),
    ports,
    warnings,
    inferPorts,
    selected,
    setSelected,
    entries,
    analysis,
    exportResult,
    simRing,
    running,
    runError,
    notice,
    busy,
    live,
    templates,
    start,
    stop,
    loadTemplate,
    importText,
    reset,
  };
}
