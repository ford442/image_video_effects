import { EntryCatalog } from '../../graphLab/entryCatalog';
import { RoleSide } from '../../graphLab/graphDraft';
import { GraphDispatchDomain, GraphNodeDef, GraphRole, MAX_REPEAT, NODE_SCALE_LEVELS } from '../../renderer/multipassGraph';
import type { EntryPorts } from '../../graphLab/portInference';
import { EntryPicker } from './EntryPicker';

/** Binding each role maps to (docs/MULTIPASS_GRAPH.md "Texture roles"). */
const ROLE_HELP: Record<string, string> = {
  read: 'Source image (binding 1)',
  color: 'Display output (binding 2)',
  dataA: 'Simulation storage A (binding 7)',
  dataB: 'Simulation storage B (binding 8)',
  dataC: 'Previous frame / handoff copy (binding 9)',
  simState: 'Sim ring agent state (@group(1) binding 0)',
  simIndex: 'Read-only simState snapshot (@group(1) binding 1, written by the barrier)',
};

const SCALE_CHOICES = (NODE_SCALE_LEVELS as readonly number[]).filter((n) => n < 1);

export interface NodeInspectorProps {
  node: GraphNodeDef | undefined;
  index: number;
  catalog: EntryCatalog | null;
  /** Roles offered per side (graphDraft.editableRoles: texture roles, plus sim roles while the ring is on). */
  readRoles: readonly GraphRole[];
  writeRoles: readonly GraphRole[];
  /** The draft uses the sim ring, so a node may dispatch over simState. */
  simRing: boolean;
  /** What the entry's WGSL binds (naga reflection); undefined while it is being read. */
  ports?: EntryPorts;
  /** Where the node's roles and its WGSL disagree (portInference.portWarnings). */
  warnings?: string[];
  onId: (id: string) => void;
  onEntry: (entry: string) => void;
  onToggleRole: (side: RoleSide, role: GraphRole) => void;
  onRepeat: (repeat: number) => void;
  onScalable: (scalable: boolean, minScale?: number) => void;
  onDispatch: (domain: GraphDispatchDomain) => void;
}

function RoleToggles({
  side,
  node,
  roles,
  onToggle,
}: {
  side: RoleSide;
  node: GraphNodeDef;
  roles: readonly string[];
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

function PortSummary({ ports }: { ports: EntryPorts | undefined }) {
  if (!ports) return <small className="graph-lab__muted">reading the WGSL…</small>;
  if (ports.status === 'error') return <small className="graph-lab__error">{ports.message}</small>;
  const list = (roles: readonly string[]) => (roles.length ? roles.join(', ') : 'nothing');
  return (
    <small>
      reads {list(ports.reads)} · writes {list(ports.writes)}
      {ports.declaresSimRing && (
        <>
          {' '}
          · declares <code>@group(1)</code>
        </>
      )}
      {ports.usesHistory && ' · history ring'}
      {ports.workgroupSize && ` · workgroup ${ports.workgroupSize.join('×')}`}
      {ports.status === 'unvalidated' && ` (${ports.message})`}
    </small>
  );
}

export function NodeInspector({
  node,
  index,
  catalog,
  readRoles,
  writeRoles,
  simRing,
  ports,
  warnings = [],
  onId,
  onEntry,
  onToggleRole,
  onRepeat,
  onScalable,
  onDispatch,
}: NodeInspectorProps) {
  if (!node) return <p className="graph-lab__empty">Select a node to edit it.</p>;
  const repeat = node.repeat ?? 1;
  const domain = node.dispatch ?? 'pixels';
  return (
    <div className="graph-lab__inspector" data-testid="graph-lab-inspector" aria-label={`Node ${index + 1} settings`}>
      <label className="graph-lab__field">
        <span>Node id</span>
        <input type="text" value={node.id} data-testid="node-id" onChange={(e) => onId(e.target.value)} />
      </label>

      <div className="graph-lab__field">
        <span>Shader entry</span>
        <EntryPicker catalog={catalog} value={node.entry} onPick={onEntry} />
      </div>

      <div className="graph-lab__field" data-testid="node-ports">
        <span>WGSL ports</span>
        <PortSummary ports={ports} />
      </div>
      {warnings.length > 0 && (
        <ul className="graph-lab__port-warnings" data-testid="node-port-warnings">
          {warnings.map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      )}

      <div className="graph-lab__field">
        <span>Reads</span>
        <RoleToggles side="reads" node={node} roles={readRoles} onToggle={onToggleRole} />
      </div>
      <div className="graph-lab__field">
        <span>Writes</span>
        <RoleToggles side="writes" node={node} roles={writeRoles} onToggle={onToggleRole} />
      </div>

      {(simRing || domain === 'simState') && (
        <label className="graph-lab__field graph-lab__field--inline">
          <span>Dispatch</span>
          <select
            value={domain}
            data-testid="node-dispatch"
            onChange={(e) => onDispatch(e.target.value as GraphDispatchDomain)}
          >
            <option value="pixels">pixels</option>
            <option value="simState">simState</option>
          </select>
          <small>
            {domain === 'simState'
              ? 'One invocation per ring element: ceil(stateCount / 64) × 1 workgroups.'
              : 'One invocation per pixel of the working size.'}
          </small>
        </label>
      )}

      <label className="graph-lab__field graph-lab__field--inline">
        <span>Repeat</span>
        <input
          type="number"
          min={1}
          max={MAX_REPEAT}
          step={1}
          value={repeat}
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
            disabled={domain === 'simState'}
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
