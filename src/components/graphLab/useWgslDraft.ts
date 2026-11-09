import { RefObject, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RendererManager } from '../../renderer/RendererManager';
import { loadNagaReflector, loadNagaValidator } from '../../utils/nagaWasm';
import { withBundledLibraries } from '../../wasm/bridge/wgslLibraries';
import type { WgslIncludeResolver } from '../../wasm/bridge/wgslInclude';
import { WgslDraftRunner, WgslRunnerHost } from '../../graphLab/runDraft';
import { buildCompletions, CompletionSpec } from '../../graphLab/wgslCompletions';
import {
  createDiagnosticScheduler,
  DiagnoseDeps,
  DiagnoseResult,
  diagnoseWgsl,
  DiagnosticScheduler,
} from '../../graphLab/wgslDiagnostics';
import { loadWgslDrafts, newWgslDraft, storeWgslDrafts, WgslDraft, WGSL_TEMPLATE } from '../../graphLab/wgslDraft';
import { DraftParam, parseParamHeader, slotParamValues } from '../../graphLab/wgslParams';
import { buildShaderFiles, saveShaderFiles, SaveBuildResult, SaveOutcome } from '../../graphLab/wgslSave';

const LIVE_POLL_MS = 500;

async function fetchLibrary(name: string): Promise<string | null> {
  try {
    const res = await fetch(`./shaders/${name}`);
    if (!res.ok || (res.headers.get('content-type') ?? '').includes('text/html')) return null;
    return await res.text();
  } catch {
    return null;
  }
}

let browserDeps: Promise<DiagnoseDeps> | null = null;

/** naga (lazy, committed artifact) + the bundled prelude + same-origin libraries, once per page. */
export function defaultDiagnoseDeps(): Promise<DiagnoseDeps> {
  browserDeps ??= (async () => {
    const [validator, reflector] = await Promise.all([loadNagaValidator(), loadNagaReflector()]);
    const cache = new Map<string, Promise<string | null>>();
    const resolve: WgslIncludeResolver = withBundledLibraries((name) => {
      let p = cache.get(name);
      if (!p) {
        p = fetchLibrary(name);
        cache.set(name, p);
      }
      return p;
    });
    const deps: DiagnoseDeps = { validate: (s) => validator.validate(s), reflect: (s) => reflector.reflect(s), resolve };
    return deps;
  })().catch((err) => {
    browserDeps = null;
    throw err;
  });
  return browserDeps;
}

export interface UseWgslDraftArgs {
  rendererRef: RefObject<RendererManager | WgslRunnerHost | null>;
  activeSlot: number;
  /** Catalog ids (Save refuses a clash). */
  existingIds?: ReadonlySet<string> | null;
  setStatus?: (status: string) => void;
  /** Called before a run binds `slot` (the Lab stops its graph draft there). */
  onBeforeRun?: (slot: number) => void;
  /** Test seam: naga + include resolution. */
  diagnoseDeps?: () => Promise<DiagnoseDeps>;
  /** Test seam: the save sink. */
  save?: (files: Extract<SaveBuildResult, { ok: true }>['files']) => Promise<SaveOutcome>;
}

export interface WgslRunning {
  slot: number;
  shaderId: string | null;
}

export function useWgslDraft({
  rendererRef,
  activeSlot,
  existingIds,
  setStatus,
  onBeforeRun,
  diagnoseDeps = defaultDiagnoseDeps,
  save = saveShaderFiles,
}: UseWgslDraftArgs) {
  const [drafts, setDrafts] = useState(() => loadWgslDrafts());
  const draft: WgslDraft = drafts[activeSlot] ?? newWgslDraft(activeSlot);
  const [diagnosis, setDiagnosis] = useState<DiagnoseResult | null>(null);
  const [toolError, setToolError] = useState<string | null>(null);
  const [swapError, setSwapError] = useState<string | null>(null);
  const [running, setRunning] = useState<WgslRunning | null>(null);
  const [busy, setBusy] = useState(false);
  const [values, setValues] = useState<Record<string, number>>({});
  const [saveState, setSaveState] = useState<{ ok: boolean; message: string } | null>(null);

  const runnerRef = useRef<WgslDraftRunner | null>(null);
  const activeSlotRef = useRef(activeSlot);
  activeSlotRef.current = activeSlot;
  const sourceRef = useRef(draft.source);
  sourceRef.current = draft.source;
  const depsRef = useRef(diagnoseDeps);
  depsRef.current = diagnoseDeps;

  useEffect(() => storeWgslDrafts(drafts), [drafts]);

  // A clean validate of the slot's current text goes straight to the running pipeline.
  const hotSwap = useCallback((result: DiagnoseResult) => {
    const runner = runnerRef.current;
    if (!runner || runner.slot !== activeSlotRef.current || !result.ok || !result.expanded) return;
    if (result.source !== sourceRef.current) return;
    void runner.submit(result.expanded.text).then((r) => {
      if (r.ok) {
        setSwapError(null);
        setRunning({ slot: runner.slot, shaderId: r.shaderId });
      } else if (r.reason === 'compile') {
        setSwapError(r.message);
      }
    });
  }, []);

  const schedulerRef = useRef<DiagnosticScheduler | null>(null);
  if (!schedulerRef.current) {
    schedulerRef.current = createDiagnosticScheduler({
      diagnose: async (source) => diagnoseWgsl(source, await depsRef.current()),
      onResult: (result) => {
        setToolError(null);
        setDiagnosis(result);
        hotSwap(result);
      },
      onError: (err) => setToolError(`naga could not load, so the draft is not validated: ${err.message}`),
    });
  }
  const scheduler = schedulerRef.current;
  useEffect(() => () => scheduler.dispose(), [scheduler]);

  useEffect(() => {
    scheduler.schedule(draft.source);
  }, [draft.source, scheduler]);

  const header = useMemo(() => parseParamHeader(draft.source), [draft.source]);
  const params: DraftParam[] = header.params;
  const completions: CompletionSpec[] = useMemo(
    () => buildCompletions(diagnosis?.expanded?.libraries, params),
    [diagnosis?.expanded?.libraries, params],
  );

  const update = useCallback(
    (patch: Partial<Omit<WgslDraft, 'version'>>) =>
      setDrafts((all) => ({ ...all, [activeSlot]: { ...(all[activeSlot] ?? newWgslDraft(activeSlot)), ...patch } })),
    [activeSlot],
  );
  const setSource = useCallback((source: string) => update({ source }), [update]);
  const resetSource = useCallback(() => update({ source: WGSL_TEMPLATE }), [update]);

  // Sliders → p1..p4 of the running slot (also when the header's defaults change).
  const slotValues = slotParamValues(params, values);
  const slotValuesKey = slotValues.join(',');
  useEffect(() => {
    const runner = runnerRef.current;
    if (runner && running) runner.setParams(slotValues);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slotValuesKey, running]);
  const setParam = useCallback((id: string, value: number) => setValues((v) => ({ ...v, [id]: value })), []);

  const stop = useCallback(() => {
    runnerRef.current?.stop();
    runnerRef.current = null;
    setRunning(null);
    setSwapError(null);
  }, []);

  const start = useCallback(async (): Promise<boolean> => {
    const host = rendererRef.current;
    if (!host) {
      setSwapError('The renderer is not ready yet.');
      return false;
    }
    const result = diagnosis && diagnosis.source === draft.source ? diagnosis : await scheduler.flush(draft.source);
    if (!result.ok || !result.expanded) {
      setSwapError(`Fix the errors first: ${result.diagnostics.find((d) => d.severity === 'error')?.message ?? ''}`);
      return false;
    }
    stop();
    onBeforeRun?.(activeSlot);
    const previous = host.getSlotState(activeSlot)?.shaderId ?? null;
    const runner = new WgslDraftRunner(host, activeSlot, previous);
    setBusy(true);
    const r = await runner.submit(result.expanded.text);
    setBusy(false);
    if (!r.ok) {
      runner.stop();
      setSwapError(r.message);
      return false;
    }
    runnerRef.current = runner;
    runner.setParams(slotValues);
    setSwapError(null);
    setRunning({ slot: activeSlot, shaderId: r.shaderId });
    setStatus?.(`Graph Lab is running the WGSL draft "${draft.name}" in slot ${activeSlot + 1}`);
    return true;
  }, [rendererRef, diagnosis, draft, scheduler, stop, onBeforeRun, activeSlot, slotValues, setStatus]);

  // Someone else took the slot: we are no longer running (and do not put anything back).
  useEffect(() => {
    if (!running) return undefined;
    const id = setInterval(() => {
      const runner = runnerRef.current;
      if (runner && !runner.isBound()) {
        runnerRef.current = null;
        setRunning(null);
      }
    }, LIVE_POLL_MS);
    return () => clearInterval(id);
  }, [running]);

  // Closing the Lab puts the slot back.
  useEffect(() => () => runnerRef.current?.stop(), []);

  const saveBuild = useMemo(
    () => buildShaderFiles(draft, { existingIds: existingIds ?? undefined, diagnosis }),
    [draft, existingIds, diagnosis],
  );
  const saveAsShader = useCallback(async () => {
    if (!saveBuild.ok) {
      setSaveState({ ok: false, message: saveBuild.errors[0] ?? 'cannot save' });
      return;
    }
    const outcome = await save(saveBuild.files);
    setSaveState(
      outcome.ok
        ? {
            ok: true,
            message:
              outcome.via === 'directory'
                ? `Saved ${outcome.paths.join(' and ')}.`
                : `Downloaded ${saveBuild.files.id}.wgsl and ${saveBuild.files.id}.json: move them to ${outcome.paths.join(' and ')}.`,
          }
        : { ok: !!outcome.cancelled, message: outcome.message },
    );
  }, [saveBuild, save]);

  const current = diagnosis && diagnosis.source === draft.source ? diagnosis : null;
  return {
    draft,
    update,
    setSource,
    resetSource,
    diagnosis: current,
    /** The latest diagnostics, possibly of a slightly older text (kept on screen while typing). */
    diagnostics: diagnosis?.diagnostics ?? [],
    validating: !current && !toolError,
    toolError,
    swapError,
    completions,
    params,
    values: slotValues,
    setParam,
    running,
    busy,
    start,
    stop,
    saveBuild,
    saveAsShader,
    saveState,
  };
}
