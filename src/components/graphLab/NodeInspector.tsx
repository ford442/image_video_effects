import React from 'react';
import { EntryCatalog } from '../../graphLab/entryCatalog';
import { EDITABLE_READ_ROLES, EDITABLE_WRITE_ROLES, RoleSide } from '../../graphLab/graphDraft';
import { GraphNodeDef, GraphRole, MAX_REPEAT, NODE_SCALE_LEVELS } from '../../renderer/multipassGraph';
import { EntryPicker } from './EntryPicker';

/** Binding each role maps to (docs/MULTIPASS_GRAPH.md "Texture roles"). */
const ROLE_HELP: Record<string, string> = {
  read: 'Source image (binding 1)',
  color: 'Display output (binding 2)',
  dataA: 'Simulation storage A (binding 7)',
  dataB: 'Simulation storage B (binding 8)',
  dataC: 'Previous frame / handoff copy (binding 9)',
};

const SCALE_CHOICES = (NODE_SCALE_LEVELS as readonly number[]).filter((n) => n < 1);

export interface NodeInspectorProps {
  node: GraphNodeDef | undefined;
  index: number;
  readOnly: boolean;
  catalog: EntryCatalog | null;
  onId: (id: string) => void;
  onEntry: (entry: string) => void;
  onToggleRole: (side: RoleSide, role: GraphRole) => void;
  onRepeat: (repeat: number) => void;
  onScalable: (scalable: boolean, minScale?: number) => void;
}

function RoleToggles({
  side,
  node,
  roles,
  readOnly,
  onToggle,
}: {
  side: RoleSide;
  node: GraphNodeDef;
  roles: readonly string[];
  readOnly: boolean;
  onToggle: (side: RoleSide, role: GraphRole) => void;
}) {
  const current = node[side] ?? [];
  const preserved = current.filter((r) => !roles.includes(r));
  return (
    <div className="graph-lab__roles" role="group" aria-label={side === 'reads' ? 'Reads' : 'Writes'}>
      {roles.map((role) => {
        const on = current.includes(role as GraphRole);
        return (
          <button
            key={role}
            type="button"
            className={`graph-lab__role${on ? ' is-on' : ''}`}
            aria-pressed={on}
            disabled={readOnly}
            title={ROLE_HELP[role]}
            data-testid={`role-${side}-${role}`}
            onClick={() => onToggle(side, role as GraphRole)}
          >
            {role}
          </button>
        );
      })}
      {preserved.map((role) => (
        <span key={role} className="graph-lab__role is-fixed" title="Kept as imported; the Lab does not edit this role">
          {role}
        </span>
      ))}
    </div>
  );
}

export function NodeInspector({ node, index, readOnly, catalog, onId, onEntry, onToggleRole, onRepeat, onScalable }: NodeInspectorProps) {
  if (!node) return <p className="graph-lab__empty">Select a node to edit it.</p>;
  const repeat = node.repeat ?? 1;
  return (
    <div className="graph-lab__inspector" data-testid="graph-lab-inspector" aria-label={`Node ${index + 1} settings`}>
      <label className="graph-lab__field">
        <span>Node id</span>
        <input type="text" value={node.id} disabled={readOnly} data-testid="node-id" onChange={(e) => onId(e.target.value)} />
      </label>

      <div className="graph-lab__field">
        <span>Shader entry</span>
        <EntryPicker catalog={catalog} value={node.entry} disabled={readOnly} onPick={onEntry} />
      </div>

      <div className="graph-lab__field">
        <span>Reads</span>
        <RoleToggles side="reads" node={node} roles={EDITABLE_READ_ROLES} readOnly={readOnly} onToggle={onToggleRole} />
      </div>
      <div className="graph-lab__field">
        <span>Writes</span>
        <RoleToggles side="writes" node={node} roles={EDITABLE_WRITE_ROLES} readOnly={readOnly} onToggle={onToggleRole} />
      </div>

      <label className="graph-lab__field graph-lab__field--inline">
        <span>Repeat</span>
        <input
          type="number"
          min={1}
          max={MAX_REPEAT}
          step={1}
          value={repeat}
          disabled={readOnly}
          data-testid="node-repeat"
          onChange={(e) => onRepeat(Number(e.target.value))}
        />
        <small>1–{MAX_REPEAT} dispatches of this entry per frame</small>
      </label>

      <div className="graph-lab__field graph-lab__field--inline">
        <label>
          <input
            type="checkbox"
            checked={!!node.scalable}
            disabled={readOnly || node.dispatch === 'simState'}
            data-testid="node-scalable"
            onChange={(e) => onScalable(e.target.checked)}
          />{' '}
          Scalable
        </label>
        {node.scalable && (
          <label>
            min scale{' '}
            <select
              value={node.minScale ?? 0.5}
              disabled={readOnly}
              onChange={(e) => onScalable(true, Number(e.target.value))}
              aria-label="Lowest resolution scale"
            >
              {SCALE_CHOICES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </label>
        )}
        <small>Lets adaptive quality run this node below the working size (fields, blurs — not per-pixel sims).</small>
      </div>
    </div>
  );
}
