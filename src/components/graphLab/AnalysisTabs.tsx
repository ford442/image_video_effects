import React, { useState } from 'react';
import type { GraphAnalysis } from '../../graphLab/graphAnalysis';
import type { LiveReading } from '../../graphLab/runDraft';

type Tab = 'diagnostics' | 'dependencies' | 'cost';

export interface AnalysisTabsProps {
  analysis: GraphAnalysis;
  /** Live planner report / GPU times while the draft runs. */
  live: LiveReading | null;
}

const fmtMs = (ms: number) => (ms < 0.01 ? '<0.01' : ms.toFixed(2));

/**
 * A `repeat` node reports the same dependency error once per iteration; show the
 * first and say how many iterations it repeats on.
 */
function groupDiagnostics(diagnostics: GraphAnalysis['diagnostics']) {
  const groups = new Map<string, { diagnostic: GraphAnalysis['diagnostics'][number]; count: number }>();
  for (const d of diagnostics) {
    const key = `${d.severity}|${d.code}|${d.nodeId ?? ''}|${d.role ?? ''}`;
    const hit = groups.get(key);
    if (hit) hit.count += 1;
    else groups.set(key, { diagnostic: d, count: 1 });
  }
  return Array.from(groups.values());
}

function Diagnostics({ analysis }: { analysis: GraphAnalysis }) {
  if (analysis.diagnostics.length === 0) {
    return (
      <p className="graph-lab__ok" data-testid="graph-lab-diagnostics-clear">
        No errors or warnings. The frame planner will encode this graph.
      </p>
    );
  }
  return (
    <ul className="graph-lab__diagnostics" data-testid="graph-lab-diagnostics">
      {groupDiagnostics(analysis.diagnostics).map(({ diagnostic: d, count }, i) => (
        <li key={`${d.code}-${i}`} className={`is-${d.severity}`} data-testid="graph-lab-diagnostic" data-code={d.code}>
          <span className="graph-lab__tag">{d.code}</span>
          <span>
            {d.message}
            {count > 1 ? <span className="graph-lab__muted"> (and on {count - 1} more iteration{count === 2 ? '' : 's'})</span> : null}
          </span>
        </li>
      ))}
    </ul>
  );
}

function Dependencies({ analysis }: { analysis: GraphAnalysis }) {
  if (analysis.rows.length === 0) return <p className="graph-lab__empty">Nothing to run yet.</p>;
  return (
    <div className="graph-lab__scroll" data-testid="graph-lab-dependencies">
      <table className="graph-lab__table">
        <thead>
          <tr>
            <th>#</th>
            <th>Dispatch</th>
            <th>Reads ← from</th>
            <th>Writes</th>
            <th>Barriers before</th>
          </tr>
        </thead>
        <tbody>
          {analysis.rows.map((row) => (
            <tr key={row.index}>
              <td>{row.index + 1}</td>
              <td>
                <strong>{row.nodeId}</strong>
                {analysis.nodes.find((n) => n.nodeId === row.nodeId && n.passes > 1) ? ` #${row.iteration + 1}` : ''}
                <div className="graph-lab__muted">{row.entry}</div>
              </td>
              <td>
                {row.reads.length === 0 ? '—' : null}
                {row.reads.map((r) => (
                  <div key={r.role} className={r.from === 'nothing produces it' ? 'is-error' : undefined}>
                    <code>{r.role}</code> ← {r.from}
                  </div>
                ))}
              </td>
              <td>{row.writes.join(', ') || '—'}</td>
              <td>{row.barriers.join(', ') || '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Cost({ analysis, live }: AnalysisTabsProps) {
  const gpuMs = new Map<string, number>();
  for (const t of live?.passTimings ?? []) if (t.nodeId) gpuMs.set(t.nodeId, t.gpuMs);
  const totalMs = Array.from(gpuMs.values()).reduce((a, b) => a + b, 0);
  return (
    <div data-testid="graph-lab-cost">
      <p className="graph-lab__summary">
        <strong>{analysis.requested}</strong> pass{analysis.requested === 1 ? '' : 'es'} requested · graph ceiling{' '}
        <strong>{analysis.ceiling}</strong> · <strong>{analysis.barrierCount}</strong> copy barrier
        {analysis.barrierCount === 1 ? '' : 's'}
        {live && gpuMs.size > 0 ? (
          <>
            {' '}
            · <strong>{fmtMs(totalMs)} ms</strong> GPU
          </>
        ) : null}
      </p>
      <div className="graph-lab__scroll">
        <table className="graph-lab__table">
          <thead>
            <tr>
              <th>Node</th>
              <th>Passes</th>
              <th>Share</th>
              <th>Barriers</th>
              <th>Scalable</th>
              {live && <th>GPU ms</th>}
            </tr>
          </thead>
          <tbody>
            {analysis.nodes.map((n) => (
              <tr key={n.index}>
                <td>
                  <strong>{n.nodeId}</strong>
                  <div className="graph-lab__muted">{n.entry}</div>
                </td>
                <td>{n.passes}</td>
                <td>
                  <span className="graph-lab__bar" aria-hidden="true">
                    <span style={{ width: `${Math.round(n.share * 100)}%` }} />
                  </span>{' '}
                  {Math.round(n.share * 100)}%
                </td>
                <td>{n.barriers}</td>
                <td>{n.scalable ? 'yes' : '—'}</td>
                {live && <td>{gpuMs.has(n.nodeId) ? fmtMs(gpuMs.get(n.nodeId) as number) : '…'}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h4 className="graph-lab__subhead">Under each quality policy</h4>
      {analysis.caps.length === 0 ? (
        <p className="graph-lab__empty">Fix the errors to preview pass budgets.</p>
      ) : (
        <div className="graph-lab__scroll">
          <table className="graph-lab__table" data-testid="graph-lab-caps">
            <thead>
              <tr>
                <th>Policy</th>
                <th>Pass cap</th>
                <th>Runs</th>
                <th>Cut</th>
                <th>Display pass</th>
                <th>Frame budget</th>
              </tr>
            </thead>
            <tbody>
              {analysis.caps.map((c) => (
                <tr key={c.id} data-testid={`cap-${c.id}`} className={c.truncated > 0 ? 'is-warning' : undefined}>
                  <td>{c.label}</td>
                  <td>{c.effectiveCap}</td>
                  <td title={c.dispatches.join(' → ')}>{c.executed}</td>
                  <td>{c.truncated}</td>
                  <td>{c.keepsColorWriter === null ? 'none' : c.keepsColorWriter ? 'kept' : 'dropped'}</td>
                  <td>{c.frameBudget}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="graph-lab__muted">
        When over budget, iterative repeats shrink first and the last node that writes <code>color</code> is kept.
      </p>
    </div>
  );
}

export function AnalysisTabs({ analysis, live }: AnalysisTabsProps) {
  const [tab, setTab] = useState<Tab>('diagnostics');
  const errors = analysis.errors.length;
  const warnings = analysis.warnings.length;
  const tabs: Array<{ id: Tab; label: string }> = [
    { id: 'diagnostics', label: `Diagnostics${errors || warnings ? ` (${errors}⛔ ${warnings}⚠)` : ''}` },
    { id: 'dependencies', label: 'Dependencies' },
    { id: 'cost', label: 'Cost' },
  ];
  return (
    <div className="graph-lab__analysis">
      <div role="tablist" aria-label="Graph analysis" className="graph-lab__tabs">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            id={`graph-lab-tab-${t.id}`}
            aria-selected={tab === t.id}
            aria-controls={`graph-lab-panel-${t.id}`}
            data-testid={`graph-lab-tab-${t.id}`}
            className={tab === t.id ? 'is-active' : undefined}
            onClick={() => setTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div role="tabpanel" id={`graph-lab-panel-${tab}`} aria-labelledby={`graph-lab-tab-${tab}`}>
        {tab === 'diagnostics' && <Diagnostics analysis={analysis} />}
        {tab === 'dependencies' && <Dependencies analysis={analysis} />}
        {tab === 'cost' && <Cost analysis={analysis} live={live} />}
      </div>
    </div>
  );
}
