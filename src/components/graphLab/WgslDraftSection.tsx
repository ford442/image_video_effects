import { lazy, Suspense, useEffect } from 'react';
import { EXPORT_CATEGORIES } from '../../graphLab/graphExport';
import type { ExportCategory } from '../../graphLab/wgslDraft';
import { useWgslDraft, UseWgslDraftArgs } from './useWgslDraft';

// CodeMirror is its own chunk inside the lazy Lab.
const WgslEditor = lazy(() => import(/* webpackChunkName: "graph-lab-editor" */ './editor/WgslEditor'));

export interface WgslDraftSectionProps extends UseWgslDraftArgs {
  /** Lets the panel stop this draft before its graph draft takes the slot. */
  registerStop?: (stop: (() => void) | null) => void;
}

/**
 * The slot's inline WGSL draft (docs/GRAPH_LAB.md "WGSL editor"): CodeMirror with
 * naga diagnostics, `// @param` sliders, hot-swap into the slot on every clean
 * validate, and "Save as shader".
 */
export function WgslDraftSection({ registerStop, ...args }: WgslDraftSectionProps) {
  const w = useWgslDraft(args);
  const { draft, running } = w;
  const live = running?.slot === args.activeSlot;
  const firstError = w.diagnostics.find((d) => d.severity === 'error');

  useEffect(() => {
    registerStop?.(w.stop);
    return () => registerStop?.(null);
  }, [registerStop, w.stop]);

  const runBlock = w.busy
    ? 'Compiling…'
    : w.diagnosis && !w.diagnosis.ok
      ? `Fix the errors first: ${firstError?.message ?? ''}`
      : !w.diagnosis
        ? 'Validating…'
        : null;

  return (
    <div className="graph-lab__wgsl" data-testid="graph-lab-wgsl">
      <div className="graph-lab__toolbar">
        {running ? (
          <button type="button" className="is-stop" onClick={w.stop} data-testid="graph-lab-wgsl-stop">
            ■ Stop (slot {running.slot + 1})
          </button>
        ) : (
          <button
            type="button"
            className="is-run"
            disabled={runBlock !== null}
            title={runBlock ?? `Run in slot ${args.activeSlot + 1}; clean edits then apply live`}
            onClick={() => void w.start()}
            data-testid="graph-lab-wgsl-run"
          >
            ▶ Run WGSL in slot {args.activeSlot + 1}
          </button>
        )}
        <button type="button" onClick={w.resetSource} title="Replace the text with the starter shader">
          Template
        </button>
        <span className="graph-lab__muted">draft of slot {args.activeSlot + 1}</span>
      </div>

      <div className="graph-lab__wgsl-status" aria-live="polite" data-testid="graph-lab-wgsl-status">
        {w.toolError ? (
          <span className="graph-lab__error" role="alert">
            {w.toolError}
          </span>
        ) : firstError ? (
          <span className="graph-lab__error" role="alert" data-testid="graph-lab-wgsl-error">
            L{firstError.line}:{firstError.column} — {firstError.message.split('\n')[0]}
            {live ? ' · the last good version keeps running' : ''}
          </span>
        ) : w.validating ? (
          <span className="graph-lab__muted">validating…</span>
        ) : (
          <span className="graph-lab__ok" data-testid="graph-lab-wgsl-valid">
            ✓ naga: valid{live ? ' · live' : ''}
          </span>
        )}
        {w.swapError && (
          <span className="graph-lab__error" role="alert" data-testid="graph-lab-wgsl-swap-error">
            {w.swapError}
          </span>
        )}
      </div>

      <Suspense fallback={<div className="graph-lab__muted">Loading editor…</div>}>
        <WgslEditor
          value={draft.source}
          onChange={w.setSource}
          diagnostics={w.diagnostics}
          completions={w.completions}
          label={`WGSL draft of slot ${args.activeSlot + 1}`}
        />
      </Suspense>

      {w.params.length > 0 && (
        <div className="graph-lab__wgsl-params" data-testid="graph-lab-wgsl-params">
          {w.params.map((p, i) => (
            <label key={p.id} title={`${p.id} → u.${p.mapping} (p${i + 1})`}>
              <span>
                p{i + 1} {p.name}
              </span>
              <input
                type="range"
                min={p.min}
                max={p.max}
                step={p.step}
                value={w.values[i] ?? p.default}
                onChange={(e) => w.setParam(p.id, Number(e.target.value))}
                data-testid={`graph-lab-wgsl-param-${p.id}`}
              />
              <output>{(w.values[i] ?? p.default).toFixed(2)}</output>
            </label>
          ))}
        </div>
      )}

      <details className="graph-lab__wgsl-save">
        <summary>Save as shader</summary>
        <div className="graph-lab__meta">
          <label>
            id
            <input value={draft.id} onChange={(e) => w.update({ id: e.target.value })} data-testid="graph-lab-wgsl-id" />
          </label>
          <label>
            name
            <input value={draft.name} onChange={(e) => w.update({ name: e.target.value })} />
          </label>
          <label>
            category
            <select value={draft.category} onChange={(e) => w.update({ category: e.target.value as ExportCategory })}>
              {EXPORT_CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
          <label>
            description
            <input value={draft.description} onChange={(e) => w.update({ description: e.target.value })} />
          </label>
        </div>
        {w.saveBuild.ok ? (
          <p className="graph-lab__muted">
            Writes <code>{w.saveBuild.files.wgslPath}</code> and <code>{w.saveBuild.files.jsonPath}</code>. Pick the
            repository folder (or get two downloads where the browser has no folder picker).
          </p>
        ) : (
          <ul className="graph-lab__errors" data-testid="graph-lab-wgsl-save-errors">
            {w.saveBuild.errors.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        )}
        <button type="button" disabled={!w.saveBuild.ok} onClick={() => void w.saveAsShader()} data-testid="graph-lab-wgsl-save">
          Save as shader…
        </button>
        {w.saveState && (
          <p className={w.saveState.ok ? 'graph-lab__muted' : 'graph-lab__error'} data-testid="graph-lab-wgsl-save-result">
            {w.saveState.message}
          </p>
        )}
      </details>
    </div>
  );
}
