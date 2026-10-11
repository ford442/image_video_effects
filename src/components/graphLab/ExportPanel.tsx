import React, { useState } from 'react';
import { GraphDraft } from '../../graphLab/graphDraft';
import { EXPORT_CATEGORIES, ExportResult } from '../../graphLab/graphExport';

export interface ExportPanelProps {
  draft: GraphDraft;
  result: ExportResult;
  onMeta: (meta: Partial<Pick<GraphDraft, 'id' | 'name' | 'category'>>) => void;
}

function downloadText(filename: string, text: string): void {
  const blob = new Blob([text], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function ExportPanel({ draft, result, onMeta }: ExportPanelProps) {
  const [copyState, setCopyState] = useState<'idle' | 'copied' | 'failed'>('idle');

  const copy = async () => {
    if (!result.ok) return;
    try {
      await navigator.clipboard.writeText(result.json);
      setCopyState('copied');
    } catch {
      setCopyState('failed');
    }
    setTimeout(() => setCopyState('idle'), 2000);
  };

  return (
    <div className="graph-lab__export" data-testid="graph-lab-export">
      <div className="graph-lab__meta">
        <label className="graph-lab__field">
          <span>Shader id</span>
          <input type="text" value={draft.id} data-testid="export-id" onChange={(e) => onMeta({ id: e.target.value })} />
        </label>
        <label className="graph-lab__field">
          <span>Name</span>
          <input type="text" value={draft.name} data-testid="export-name" onChange={(e) => onMeta({ name: e.target.value })} />
        </label>
        <label className="graph-lab__field">
          <span>Category folder</span>
          <select value={draft.category} data-testid="export-category" onChange={(e) => onMeta({ category: e.target.value })}>
            {EXPORT_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
      </div>

      {!result.ok && result.errors.length > 0 && (
        <div className="graph-lab__blockers" role="alert" data-testid="export-blockers">
          <strong>Export is blocked:</strong>
          <ul>
            {result.errors.map((e, i) => (
              <li key={i}>{e}</li>
            ))}
          </ul>
        </div>
      )}
      {!result.ok && result.errors.length === 0 && <p className="graph-lab__empty">Add a node to export.</p>}

      {result.notes.length > 0 && (
        <ul className="graph-lab__notes" data-testid="export-notes">
          {result.notes.map((n) => (
            <li key={n.code + n.message} data-code={n.code}>
              {n.message}
            </li>
          ))}
        </ul>
      )}

      <div className="graph-lab__export-actions">
        <button
          type="button"
          disabled={!result.ok}
          data-testid="export-download"
          onClick={() => result.ok && downloadText(`${draft.id}.json`, result.json)}
        >
          Download {draft.id}.json
        </button>
        <button type="button" disabled={!result.ok} data-testid="export-copy" onClick={() => void copy()}>
          {copyState === 'copied' ? 'Copied ✓' : copyState === 'failed' ? 'Copy failed' : 'Copy JSON'}
        </button>
      </div>

      {result.ok && (
        <>
          <p className="graph-lab__muted">
            Save as <code>{result.path}</code>, then run <code>node scripts/buildMultipassRegistry.js</code> (also part of{' '}
            <code>npm start</code> / <code>npm run build</code>).
          </p>
          <details>
            <summary>Preview definition</summary>
            <pre className="graph-lab__json" data-testid="export-json">
              {result.json}
            </pre>
          </details>
        </>
      )}
    </div>
  );
}
