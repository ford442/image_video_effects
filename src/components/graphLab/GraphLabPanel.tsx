import { lazy, ReactElement, RefObject, Suspense, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import {
  addNode,
  duplicateNodeAt,
  editableRoles,
  moveNode,
  NodeRoles,
  removeNodeAt,
  resetLayout,
  setMaxPasses,
  setMeta,
  setNodeDispatch,
  setNodeEntry,
  setNodeId,
  setNodePosition,
  setRepeat,
  setScalable,
  setSimRing,
  toggleRole,
} from '../../graphLab/graphDraft';
import type { EntryPorts, PortInference } from '../../graphLab/portInference';
import { graphUsesSimRing, GraphRole } from '../../renderer/multipassGraph';
import type { RendererManager } from '../../renderer/RendererManager';
import type { ShaderEntry } from '../../renderer/types';
import { AnalysisTabs } from './AnalysisTabs';
import { EntryPicker } from './EntryPicker';
import { ExportPanel } from './ExportPanel';
import { NodeInspector } from './NodeInspector';
import { NodeList } from './NodeList';
import { SimRingSection } from './SimRingSection';
import { useGraphLab } from './useGraphLab';
import './graphLab.css';

// React Flow is its own chunk inside the lazy Lab: the list view and analysis work without it.
const GraphCanvas = lazy(() => import(/* webpackChunkName: "graph-lab-canvas" */ './GraphCanvas'));
/** React Flow measures nodes with ResizeObserver; without it (jsdom) the Lab is list-only. */
const CANVAS_SUPPORTED = typeof ResizeObserver !== 'undefined';

/** The roles a new node gets from its WGSL: a `simState` writer with a 1-D workgroup dispatches over the ring. */
function rolesFromPorts(p: EntryPorts): NodeRoles | undefined {
  if (p.status === 'error' || p.reads.length + p.writes.length === 0) return undefined;
  const [, y = 1, z = 1] = p.workgroupSize ?? [];
  const simDispatch = p.writes.includes('simState') && y === 1 && z === 1;
  return { reads: p.reads, writes: p.writes, dispatch: simDispatch ? 'simState' : undefined };
}

/**
 * The expanded canvas is fixed to the viewport. The panel's backdrop-filter makes it
 * the containing block of fixed descendants, so the expanded canvas lives on <body>.
 */
const portalIf = (wide: boolean, el: ReactElement) => (wide ? createPortal(el, document.body) : el);

const isEditableTarget = (t: EventTarget | null) =>
  t instanceof HTMLElement && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));

export interface GraphLabPanelProps {
  rendererRef: RefObject<RendererManager | null>;
  availableModes: ShaderEntry[];
  activeSlot: number;
  onClose: () => void;
  setStatus?: (status: string) => void;
  /** Test seam (useGraphLab). */
  portInference?: PortInference;
}

/**
 * Experimental Tier C graph workspace (docs/GRAPH_LAB.md). Everything it shows
 * comes from the renderer's own validator / planner / frame executor; it adds
 * no graph schema and no bindings. Lazy chunk "graph-lab".
 */
export default function GraphLabPanel({ rendererRef, availableModes, activeSlot, onClose, setStatus, portInference }: GraphLabPanelProps) {
  const lab = useGraphLab({ rendererRef, availableModes, activeSlot, setStatus, portInference });
  const { draft, setDraft, selected, analysis, simRing, running, live, entries, ports, warnings, undo, redo } = lab;
  const node = draft.graph.nodes[selected];
  const [pasted, setPasted] = useState('');
  const [canvasOpen, setCanvasOpen] = useState(CANVAS_SUPPORTED);
  const [canvasWide, setCanvasWide] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const readRoles = editableRoles(draft, 'reads');
  const writeRoles = editableRoles(draft, 'writes');
  const nodePorts = node ? ports.get(node.entry) : undefined;
  const simEntries = [...new Set(draft.graph.nodes.map((n) => n.entry))].filter((e) => ports.get(e)?.declaresSimRing);

  // Ctrl/Cmd+Z undo, Ctrl/Cmd+Shift+Z or Ctrl+Y redo — not while typing in a field (its own undo wins).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey) || isEditableTarget(e.target)) return;
      const key = e.key.toLowerCase();
      if (key === 'z' && !e.shiftKey) undo();
      else if ((key === 'z' && e.shiftKey) || key === 'y') redo();
      else return;
      e.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [undo, redo]);

  const addEntry = async (entry: string) => {
    const at = draft.graph.nodes.length;
    const roles = rolesFromPorts(await lab.inferPorts(entry));
    setDraft((d) => addNode(d, entry, d.graph.nodes.length, roles));
    lab.setSelected(at);
  };

  const ensureRole = (index: number, side: 'reads' | 'writes', role: GraphRole) =>
    setDraft((d) => ((d.graph.nodes[index]?.[side] ?? []).includes(role) ? d : toggleRole(d, index, side, role)));

  const runBlock =
    draft.graph.nodes.length === 0
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
        <button type="button" onClick={undo} disabled={!lab.canUndo} title="Undo (Ctrl+Z)" aria-label="Undo" data-testid="graph-lab-undo">
          ↶
        </button>
        <button type="button" onClick={redo} disabled={!lab.canRedo} title="Redo (Ctrl+Shift+Z)" aria-label="Redo" data-testid="graph-lab-redo">
          ↷
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

      <section aria-labelledby="graph-lab-nodes-h">
        <h3 id="graph-lab-nodes-h" className="graph-lab__section">
          Nodes
          <label className="graph-lab__ceiling">
            pass ceiling{' '}
            <input
              type="number"
              min={1}
              value={draft.graph.maxPassesPerFrame}
              data-testid="graph-lab-ceiling"
              onChange={(e) => setDraft((d) => setMaxPasses(d, Number(e.target.value)), { coalesce: 'ceiling' })}
            />
          </label>
        </h3>
        {CANVAS_SUPPORTED && (
          <div className="graph-lab__canvas-bar">
            <label>
              <input type="checkbox" checked={canvasOpen} onChange={(e) => setCanvasOpen(e.target.checked)} /> canvas
            </label>
            {canvasOpen && (
              <>
                <button type="button" onClick={() => setCanvasWide((w) => !w)} data-testid="graph-lab-canvas-wide">
                  {canvasWide ? 'Dock' : 'Expand'}
                </button>
                <button type="button" onClick={() => setDraft(resetLayout)} title="Forget node positions">
                  Auto layout
                </button>
              </>
            )}
          </div>
        )}
        {canvasOpen && portalIf(canvasWide,
          <div className={`graph-lab__canvas-wrap${canvasWide ? ' is-wide' : ''}`}>
            <Suspense fallback={<div className="graph-lab__muted">Loading canvas…</div>}>
              <GraphCanvas
                draft={draft}
                selected={selected}
                ports={ports}
                warnings={warnings}
                readRoles={readRoles}
                writeRoles={writeRoles}
                onSelect={lab.setSelected}
                onMove={(id, x, y) => setDraft((d) => setNodePosition(d, id, { x, y }))}
                onRemove={(indexes) =>
                  setDraft((d) => [...indexes].sort((a, b) => b - a).reduce((acc, i) => removeNodeAt(acc, i), d))
                }
                onConnect={(from, writeRole, to, readRole) =>
                  setDraft((d) => {
                    let next = d;
                    if (!(next.graph.nodes[from]?.writes ?? []).includes(writeRole)) next = toggleRole(next, from, 'writes', writeRole);
                    if (!(next.graph.nodes[to]?.reads ?? []).includes(readRole)) next = toggleRole(next, to, 'reads', readRole);
                    return next;
                  })
                }
                onAddRole={ensureRole}
              />
            </Suspense>
          </div>,
        )}
        <NodeList
          nodes={draft.graph.nodes}
          selected={selected}
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
        <div className="graph-lab__add">
          <span>Add node</span>
          <EntryPicker
            catalog={entries}
            onPick={(entry) => void addEntry(entry)}
          />
        </div>
      </section>

      <section aria-labelledby="graph-lab-inspector-h">
        <h3 id="graph-lab-inspector-h" className="graph-lab__section">
          Node settings
        </h3>
        <NodeInspector
          node={node}
          index={selected}
          catalog={entries}
          readRoles={readRoles}
          writeRoles={writeRoles}
          simRing={simRing !== null}
          ports={nodePorts}
          warnings={warnings.filter((w) => w.nodeIndex === selected).map((w) => w.message)}
          onId={(id) => setDraft((d) => setNodeId(d, selected, id), { coalesce: `id:${selected}` })}
          onEntry={(entry) => setDraft((d) => setNodeEntry(d, selected, entry))}
          onToggleRole={(side, role) => setDraft((d) => toggleRole(d, selected, side, role))}
          onRepeat={(n) => setDraft((d) => setRepeat(d, selected, n), { coalesce: `repeat:${selected}` })}
          onScalable={(on, min) => setDraft((d) => setScalable(d, selected, on, min))}
          onDispatch={(domain) => setDraft((d) => setNodeDispatch(d, selected, domain))}
        />
      </section>

      <section aria-labelledby="graph-lab-simring-h">
        <h3 id="graph-lab-simring-h" className="graph-lab__section">
          Sim ring
        </h3>
        <SimRingSection
          request={simRing}
          locked={graphUsesSimRing(draft.graph)}
          simEntries={simEntries}
          onToggle={(on) => setDraft((d) => setSimRing(d, on))}
          onStateCount={(n) => setDraft((d) => setSimRing(d, true, n))}
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
        <ExportPanel
          draft={draft}
          result={lab.exportResult}
          onMeta={(meta) => setDraft((d) => setMeta(d, meta), { coalesce: `meta:${Object.keys(meta).join(',')}` })}
        />
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
