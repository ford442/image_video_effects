import { RefObject, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RendererManager } from '../../renderer/RendererManager';
import { GRAPH_REGISTRY } from '../../renderer/multipassRegistry';
import { GRAPH_LAB_RUNTIME_ID } from '../../renderer/runtimeGraphs';
import type { ShaderEntry } from '../../renderer/types';
import { buildEntryCatalog, EntryCatalog } from '../../graphLab/entryCatalog';
import { analyzeGraph, GraphAnalysis } from '../../graphLab/graphAnalysis';
import {
  draftFromDefinition,
  draftFromRegistryGraph,
  forkDraft,
  GraphDraft,
  newDraft,
  simRingRequest,
} from '../../graphLab/graphDraft';
import { exportGraphDefinition, ExportResult } from '../../graphLab/graphExport';
import { LiveReading, readLive, runDraft, stopDraft } from '../../graphLab/runDraft';

export const DRAFT_STORAGE_KEY = 'graphlab.draft.v1';
/** Flagship the Lab opens on when nothing is stored, so the first view is a graph that runs. */
export const SEED_GRAPH_ID = 'wave-tank';
const LIVE_POLL_MS = 500;
const HOT_RUN_DEBOUNCE_MS = 150;

export interface UseGraphLabArgs {
  rendererRef: RefObject<RendererManager | null>;
  availableModes: ShaderEntry[];
  activeSlot: number;
  setStatus?: (status: string) => void;
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
  return forkDraft(draftFromRegistryGraph(id, graph, entry), `${id}-lab`, `${entry?.name ?? id} (lab)`);
}

function loadStoredDraft(availableModes: ShaderEntry[]): GraphDraft {
  try {
    const raw = window.localStorage.getItem(DRAFT_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as GraphDraft;
      if (parsed && typeof parsed.id === 'string' && Array.isArray(parsed.graph?.nodes)) {
        return { ...newDraft(), ...parsed };
      }
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

export function useGraphLab({ rendererRef, availableModes, activeSlot, setStatus }: UseGraphLabArgs) {
  const [draft, setDraftState] = useState<GraphDraft>(() => loadStoredDraft(availableModes));
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
  const simRingKey = simRing ? String(simRing.stateCount) : '';
  const armedSimRingRef = useRef<string | null>(null);

  const setDraft = useCallback((next: GraphDraft | ((prev: GraphDraft) => GraphDraft)) => {
    setDraftState((prev) => {
      const value = typeof next === 'function' ? next(prev) : next;
      storeDraft(value);
      return value;
    });
  }, []);

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
