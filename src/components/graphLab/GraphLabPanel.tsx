import React, { RefObject, useRef, useState } from 'react';
import {
  addNode,
  duplicateNodeAt,
  moveNode,
  removeNodeAt,
  setMaxPasses,
  setMeta,
  setNodeEntry,
  setNodeId,
  setRepeat,
  setScalable,
  toggleRole,
} from '../../graphLab/graphDraft';
import type { RendererManager } from '../../renderer/RendererManager';
import type { ShaderEntry } from '../../renderer/types';
import { AnalysisTabs } from './AnalysisTabs';
import { EntryPicker } from './EntryPicker';
import { ExportPanel } from './ExportPanel';
import { NodeInspector } from './NodeInspector';
import { NodeList } from './NodeList';
import { useGraphLab } from './useGraphLab';
import './graphLab.css';

export interface GraphLabPanelProps {
  rendererRef: RefObject<RendererManager | null>;
  availableModes: ShaderEntry[];
  activeSlot: number;
  onClose: () => void;
  setStatus?: (status: string) => void;
}

/**
 * Experimental Tier C graph workspace (docs/GRAPH_LAB.md). Everything it shows
 * comes from the renderer's own validator / planner / frame executor; it adds
 * no graph schema and no bindings. Lazy chunk "graph-lab".
 */
export default function GraphLabPanel({ rendererRef, availableModes, activeSlot, onClose, setStatus }: GraphLabPanelProps) {
  const lab = useGraphLab({ rendererRef, availableModes, activeSlot, setStatus });
  const { draft, setDraft, selected, analysis, readOnly, running, live, entries } = lab;
  const node = draft.graph.nodes[selected];
  const [pasted, setPasted] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  const runBlock = readOnly
    ? 'Sim-ring graphs are view-only in v1.'
    : draft.graph.nodes.length === 0
      ? 'Add a node first.'
      : !analysis.valid
        ? `Fix the errors first: ${analysis.errors[0]?.message ?? ''}`
        : lab.busy
          ? 'Compiling…'
          : null;

  const report = live?.report ?? null;

  return (
    <aside className="graph-lab" aria-label="Graph Lab" data-testid="graph-lab">
      <header className="graph-lab__header">
        <h2>
          Graph Lab <span className="graph-lab__badge">experimental</span>
        </h2>
        <button type="button" onClick={onClose} aria-label="Close Graph Lab" data-testid="graph-lab-close">
          ✕
        </button>
      </header>

      <div className="graph-lab__toolbar">
        {running ? (
          <button type="button" className="is-stop" onClick={lab.stop} data-testid="graph-lab-stop">
            ■ Stop
          </button>
        ) : (
          <button
            type="button"
            className="is-run"
            disabled={runBlock !== null}
            title={runBlock ?? `Run in slot ${activeSlot + 1}`}
            onClick={() => void lab.start()}
            data-testid="graph-lab-run"
          >
            ▶ Run in slot {activeSlot + 1}
          </button>
        )}
        <select
          value=""
          aria-label="Start from a shipped graph"
          data-testid="graph-lab-template"
          onChange={(e) => e.target.value && lab.loadTemplate(e.target.value)}
        >
          <option value="">Start from…</option>
          {lab.templates.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>
        <button type="button" onClick={lab.reset} data-testid="graph-lab-new">
          New
        </button>
        <button type="button" onClick={() => fileRef.current?.click()}>
          Import file…
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          hidden
          data-testid="graph-lab-file"
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = '';
            if (file) void file.text().then(lab.importText);
          }}
        />
      </div>

      <div className="graph-lab__status" aria-live="polite">
        {running && (
          <span className="graph-lab__live" data-testid="graph-lab-live-report">
            {report ? (
              <>
                live: <strong>{report.executed}</strong> / {report.requested} passes
                {report.truncated > 0 ? ` · ${report.truncated} truncated (cap ${report.cap})` : ''}
                {report.errors.length > 0 ? ` · ${report.errors.length} error(s)` : ''}
              </>
            ) : (
              'running — waiting for the first frame…'
            )}
          </span>
        )}
        {!running && runBlock && draft.graph.nodes.length > 0 && <span className="graph-lab__muted">{runBlock}</span>}
        {lab.runError && (
          <span className="graph-lab__error" role="alert" data-testid="graph-lab-run-error">
            {lab.runError}
          </span>
        )}
        {lab.notice && !lab.runError && <span className="graph-lab__muted">{lab.notice}</span>}
      </div>

      {readOnly && (
        <p className="graph-lab__banner" data-testid="graph-lab-readonly">
          This graph uses the sim ring (<code>simState</code> / <code>simIndex</code>). It is shown and validated, and exports
          unchanged, but cannot be edited or run in the Lab yet.
        </p>
      )}

      <section aria-labelledby="graph-lab-nodes-h">
        <h3 id="graph-lab-nodes-h" className="graph-lab__section">
          Nodes
          <label className="graph-lab__ceiling">
            pass ceiling{' '}
            <input
              type="number"
              min={1}
              value={draft.graph.maxPassesPerFrame}
              disabled={readOnly}
              data-testid="graph-lab-ceiling"
              onChange={(e) => setDraft((d) => setMaxPasses(d, Number(e.target.value)))}
            />
          </label>
        </h3>
        <NodeList
          nodes={draft.graph.nodes}
          selected={selected}
          readOnly={readOnly}
          diagnostics={analysis.diagnostics}
          onSelect={lab.setSelected}
          onMove={(from, to) => {
            setDraft((d) => moveNode(d, from, to));
            lab.setSelected(to);
          }}
          onDuplicate={(i) => {
            setDraft((d) => duplicateNodeAt(d, i));
            lab.setSelected(i + 1);
          }}
          onRemove={(i) => setDraft((d) => removeNodeAt(d, i))}
        />
        {!readOnly && (
          <div className="graph-lab__add">
            <span>Add node</span>
            <EntryPicker
              catalog={entries}
              onPick={(entry) => {
                setDraft((d) => addNode(d, entry));
                lab.setSelected(draft.graph.nodes.length);
              }}
            />
          </div>
        )}
      </section>

      <section aria-labelledby="graph-lab-inspector-h">
        <h3 id="graph-lab-inspector-h" className="graph-lab__section">
          Node settings
        </h3>
        <NodeInspector
          node={node}
          index={selected}
          readOnly={readOnly}
          catalog={entries}
          onId={(id) => setDraft((d) => setNodeId(d, selected, id))}
          onEntry={(entry) => setDraft((d) => setNodeEntry(d, selected, entry))}
          onToggleRole={(side, role) => setDraft((d) => toggleRole(d, selected, side, role))}
          onRepeat={(n) => setDraft((d) => setRepeat(d, selected, n))}
          onScalable={(on, min) => setDraft((d) => setScalable(d, selected, on, min))}
        />
      </section>

      <section aria-labelledby="graph-lab-analysis-h">
        <h3 id="graph-lab-analysis-h" className="graph-lab__section">
          Analysis
        </h3>
        <AnalysisTabs analysis={analysis} live={live} />
      </section>

      <section aria-labelledby="graph-lab-export-h">
        <h3 id="graph-lab-export-h" className="graph-lab__section">
          Export
        </h3>
        <ExportPanel draft={draft} result={lab.exportResult} onMeta={(meta) => setDraft((d) => setMeta(d, meta))} />
      </section>

      <details className="graph-lab__import">
        <summary>Import JSON</summary>
        <textarea
          value={pasted}
          rows={5}
          placeholder="Paste a shader definition (with multipass.graph) or a bare { maxPassesPerFrame, nodes } graph"
          aria-label="Graph JSON to import"
          data-testid="graph-lab-import-text"
          onChange={(e) => setPasted(e.target.value)}
        />
        <button
          type="button"
          disabled={!pasted.trim()}
          data-testid="graph-lab-import"
          onClick={() => {
            if (lab.importText(pasted)) setPasted('');
          }}
        >
          Import
        </button>
      </details>
    </aside>
  );
}
