import React from 'react';
import type { GraphDiagnostic, GraphNodeDef } from '../../renderer/multipassGraph';

export interface NodeListProps {
  nodes: readonly GraphNodeDef[];
  selected: number;
  readOnly: boolean;
  diagnostics: readonly GraphDiagnostic[];
  onSelect: (index: number) => void;
  onMove: (from: number, to: number) => void;
  onDuplicate: (index: number) => void;
  onRemove: (index: number) => void;
}

/** Nodes in execution order (the array order IS the order the passes run in). */
export function NodeList({ nodes, selected, readOnly, diagnostics, onSelect, onMove, onDuplicate, onRemove }: NodeListProps) {
  if (nodes.length === 0) {
    return (
      <p className="graph-lab__empty" data-testid="graph-lab-no-nodes">
        No nodes yet. Search for a shader entry below to add the first pass.
      </p>
    );
  }
  return (
    <ol className="graph-lab__nodes" aria-label="Graph nodes in execution order" data-testid="graph-lab-nodes">
      {nodes.map((node, index) => {
        const nodeErrors = diagnostics.filter((d) => d.severity === 'error' && d.nodeId === node.id).length;
        const repeat = node.repeat ?? 1;
        return (
          <li
            key={`${index}-${node.id}`}
            className={`graph-lab__node${index === selected ? ' is-selected' : ''}${nodeErrors > 0 ? ' has-error' : ''}`}
            data-testid={`graph-lab-node-${index}`}
          >
            <button
              type="button"
              className="graph-lab__node-main"
              aria-pressed={index === selected}
              data-testid={`graph-lab-node-select-${index}`}
              onClick={() => onSelect(index)}
            >
              <span className="graph-lab__node-index">{index + 1}</span>
              <span className="graph-lab__node-title">
                <strong>{node.id || '(no id)'}</strong>
                <code>{node.entry || '(no entry)'}</code>
              </span>
              {repeat > 1 && <span className="graph-lab__chip graph-lab__chip--repeat">×{repeat}</span>}
              {node.scalable && <span className="graph-lab__chip">scalable</span>}
              <span className="graph-lab__node-io">
                {(node.reads ?? []).join(', ') || '—'} <span aria-hidden="true">→</span> {(node.writes ?? []).join(', ') || '—'}
              </span>
              {nodeErrors > 0 && (
                <span className="graph-lab__chip graph-lab__chip--error" title="This node has validation errors">
                  {nodeErrors} error{nodeErrors === 1 ? '' : 's'}
                </span>
              )}
            </button>
            {!readOnly && (
              <span className="graph-lab__node-actions">
                <button type="button" aria-label={`Move ${node.id} up`} disabled={index === 0} onClick={() => onMove(index, index - 1)}>
                  ↑
                </button>
                <button
                  type="button"
                  aria-label={`Move ${node.id} down`}
                  disabled={index === nodes.length - 1}
                  onClick={() => onMove(index, index + 1)}
                >
                  ↓
                </button>
                <button type="button" aria-label={`Duplicate ${node.id}`} onClick={() => onDuplicate(index)}>
                  ⧉
                </button>
                <button type="button" aria-label={`Remove ${node.id}`} onClick={() => onRemove(index)}>
                  ✕
                </button>
              </span>
            )}
          </li>
        );
      })}
    </ol>
  );
}
