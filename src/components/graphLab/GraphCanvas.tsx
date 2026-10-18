import { memo, useCallback, useEffect, useMemo, useState } from 'react';
import {
  applyNodeChanges,
  Background,
  Connection,
  Controls,
  Edge,
  Handle,
  MarkerType,
  Node,
  NodeChange,
  NodeProps,
  Position,
  ReactFlow,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { graphEdges, OUTPUT_NODE, SOURCE_NODE } from '../../graphLab/graphEdges';
import { GraphDraft, LAYOUT_COLUMN, resolvedLayout } from '../../graphLab/graphDraft';
import type { EntryPorts, PortWarning } from '../../graphLab/portInference';
import type { GraphRole } from '../../renderer/multipassGraph';

/** A role chip on a node: in the graph and the WGSL agrees, in the graph only, or offered by the WGSL. */
type PortState = 'on' | 'mismatch' | 'offered';

interface PortChip {
  role: GraphRole;
  state: PortState;
}

interface PassNodeData extends Record<string, unknown> {
  index: number;
  nodeId: string;
  entry: string;
  repeat: number;
  simDispatch: boolean;
  reads: PortChip[];
  writes: PortChip[];
  ports: EntryPorts | undefined;
  warnings: string[];
  /** Roles this node reads from its own earlier dispatch / previous frame (drawn as a tag, not a loop edge). */
  selfFeeds: string[];
}

interface EndNodeData extends Record<string, unknown> {
  label: string;
}

const PORT_TITLE: Record<PortState, string> = {
  on: 'in the graph',
  mismatch: 'in the graph, but the WGSL never binds it',
  offered: 'the WGSL binds it; click to add it to the graph',
};

function chips(graphRoles: readonly GraphRole[], inferred: readonly GraphRole[] | undefined, editable: readonly GraphRole[]): PortChip[] {
  const out: PortChip[] = graphRoles.map((role) => ({
    role,
    state: inferred && !inferred.includes(role) && role !== 'dataA' && role !== 'dataB' ? 'mismatch' : 'on',
  }));
  for (const role of inferred ?? []) {
    if (!graphRoles.includes(role) && editable.includes(role)) out.push({ role, state: 'offered' });
  }
  return out;
}

const PassNode = memo(function PassNode({ data, selected }: NodeProps<Node<PassNodeData>>) {
  const { ports } = data;
  return (
    <div
      className={`graph-canvas__node${selected ? ' is-selected' : ''}${data.warnings.length ? ' has-warning' : ''}`}
      data-testid={`canvas-node-${data.index}`}
      title={data.warnings.join('\n') || undefined}
    >
      <div className="graph-canvas__node-head">
        <span className="graph-canvas__order">{data.index + 1}</span>
        <strong>{data.nodeId}</strong>
        {data.repeat > 1 && <span className="graph-canvas__tag">×{data.repeat}</span>}
        {data.simDispatch && <span className="graph-canvas__tag">simState</span>}
      </div>
      <div className="graph-canvas__entry">{data.entry}</div>
      <div className="graph-canvas__ports">
        <div className="graph-canvas__side">
          {data.reads.map((p) => (
            <div key={p.role} className={`graph-canvas__port is-${p.state}`} title={`${p.role}: ${PORT_TITLE[p.state]}`}>
              <Handle type="target" position={Position.Left} id={`in-${p.role}`} />
              {p.role}
            </div>
          ))}
        </div>
        <div className="graph-canvas__side is-out">
          {data.writes.map((p) => (
            <div key={p.role} className={`graph-canvas__port is-${p.state}`} title={`${p.role}: ${PORT_TITLE[p.state]}`}>
              {p.role}
              <Handle type="source" position={Position.Right} id={`out-${p.role}`} />
            </div>
          ))}
        </div>
      </div>
      <div className="graph-canvas__foot">
        {ports === undefined && <span className="graph-canvas__muted">reading WGSL…</span>}
        {ports?.declaresSimRing && <span className="graph-canvas__tag is-sim">@group(1)</span>}
        {ports?.usesHistory && <span className="graph-canvas__tag">history</span>}
        {ports?.status === 'unvalidated' && <span className="graph-canvas__tag is-warn" title={ports.message}>declared only</span>}
        {ports?.status === 'error' && <span className="graph-canvas__tag is-warn" title={ports.message}>no ports</span>}
        {data.selfFeeds.map((f) => (
          <span key={f} className="graph-canvas__tag" title="Reads what it wrote: an earlier dispatch or the previous frame">
            ↺ {f}
          </span>
        ))}
        {data.warnings.length > 0 && <span className="graph-canvas__tag is-warn">⚠ {data.warnings.length}</span>}
      </div>
    </div>
  );
});

const EndNode = memo(function EndNode({ data, id }: NodeProps<Node<EndNodeData>>) {
  return (
    <div className="graph-canvas__end">
      {id === SOURCE_NODE ? (
        <Handle type="source" position={Position.Right} id="out-read" />
      ) : (
        <Handle type="target" position={Position.Left} id="in-color" />
      )}
      {data.label}
    </div>
  );
});

const NODE_TYPES = { pass: PassNode, end: EndNode };

export interface GraphCanvasProps {
  draft: GraphDraft;
  selected: number;
  ports: ReadonlyMap<string, EntryPorts>;
  warnings: readonly PortWarning[];
  /** Roles the editor lets a user toggle (graphDraft.editableRoles). */
  readRoles: readonly GraphRole[];
  writeRoles: readonly GraphRole[];
  onSelect: (index: number) => void;
  onMove: (nodeId: string, x: number, y: number) => void;
  onRemove: (indexes: number[]) => void;
  /** Ensure `from` writes `writeRole` and `to` reads `readRole` (a drawn edge). */
  onConnect: (from: number, writeRole: GraphRole, to: number, readRole: GraphRole) => void;
  /** Add one role the WGSL offers (a click on an `offered` chip). */
  onAddRole: (index: number, side: 'reads' | 'writes', role: GraphRole) => void;
}

const nodeIndex = (rfId: string): number => (rfId.startsWith('n') ? Number(rfId.slice(1)) : -1);

/**
 * The node canvas: positions are the draft's editor-only layout, edges are
 * derived from the planner's expansion (graphEdges.ts). Execution order is the
 * node list order, shown as the number on each node.
 */
export default function GraphCanvas(props: GraphCanvasProps) {
  const { draft, selected, ports, warnings, readRoles, writeRoles } = props;

  const allEdges = useMemo(() => graphEdges(draft.graph), [draft.graph]);

  const derived = useMemo((): Node[] => {
    const layout = resolvedLayout(draft);
    const selfFeeds = new Map<number, string[]>();
    for (const e of allEdges) {
      if (e.from === e.to && typeof e.from === 'number') selfFeeds.set(e.from, [...(selfFeeds.get(e.from) ?? []), e.role]);
    }
    const byNode = new Map<number, string[]>();
    for (const w of warnings) byNode.set(w.nodeIndex, [...(byNode.get(w.nodeIndex) ?? []), w.message]);
    const nodes: Node[] = draft.graph.nodes.map((n, index) => {
      const p = ports.get(n.entry);
      const known = p && p.status !== 'error';
      const data: PassNodeData = {
        index,
        nodeId: n.id,
        entry: n.entry,
        repeat: n.repeat ?? 1,
        simDispatch: n.dispatch === 'simState',
        reads: chips(n.reads ?? [], known ? p.reads : undefined, readRoles),
        writes: chips(n.writes ?? [], known ? p.writes : undefined, writeRoles),
        ports: p,
        warnings: byNode.get(index) ?? [],
        selfFeeds: selfFeeds.get(index) ?? [],
      };
      return { id: `n${index}`, type: 'pass', position: layout[index] ?? { x: 0, y: 0 }, data, selected: index === selected };
    });
    const ys = layout.map((p) => p.y);
    const midY = ys.length ? (Math.min(...ys) + Math.max(...ys)) / 2 : 0;
    const maxX = layout.reduce((m, p) => Math.max(m, p.x), 0);
    nodes.push(
      { id: SOURCE_NODE, type: 'end', position: { x: 0, y: midY }, data: { label: 'source image' }, draggable: false, selectable: false, deletable: false },
      { id: OUTPUT_NODE, type: 'end', position: { x: maxX + LAYOUT_COLUMN, y: midY }, data: { label: 'display' }, draggable: false, selectable: false, deletable: false },
    );
    return nodes;
  }, [draft, allEdges, ports, warnings, selected, readRoles, writeRoles]);

  // Local copy so a drag moves smoothly; the position is committed to the draft on drop.
  const [nodes, setNodes] = useState<Node[]>(derived);
  useEffect(() => setNodes(derived), [derived]);

  const edges = useMemo(
    (): Edge[] =>
      allEdges.filter((e) => e.from !== e.to).map((e) => {
        const from = e.from === SOURCE_NODE ? SOURCE_NODE : `n${e.from}`;
        const to = e.to === OUTPUT_NODE ? OUTPUT_NODE : `n${e.to}`;
        const sourceRole = e.via ? e.via.split(' → ')[0] : e.role;
        return {
          id: e.id,
          source: from,
          target: to,
          sourceHandle: `out-${sourceRole}`,
          targetHandle: `in-${e.role}`,
          label: e.via ?? (e.feedback ? `${e.role} (prev frame)` : undefined),
          animated: e.feedback,
          className: e.feedback ? 'is-feedback' : undefined,
          markerEnd: { type: MarkerType.ArrowClosed },
          deletable: false,
        };
      }),
    [allEdges],
  );

  const onNodesChange = useCallback((changes: NodeChange[]) => setNodes((ns) => applyNodeChanges(changes, ns)), []);

  const { onSelect, onMove, onRemove, onConnect, onAddRole } = props;

  const connect = useCallback(
    (c: Connection) => {
      const from = nodeIndex(c.source);
      const to = nodeIndex(c.target);
      if (c.source === SOURCE_NODE && to >= 0) return onAddRole(to, 'reads', 'read');
      if (c.target === OUTPUT_NODE && from >= 0) return onAddRole(from, 'writes', 'color');
      const writeRole = c.sourceHandle?.replace(/^out-/, '') as GraphRole | undefined;
      const readRole = c.targetHandle?.replace(/^in-/, '') as GraphRole | undefined;
      if (from < 0 || to < 0 || !writeRole || !readRole) return;
      onConnect(from, writeRole, to, readRole);
    },
    [onConnect, onAddRole],
  );

  return (
    <div className="graph-canvas" data-testid="graph-lab-canvas">
      <ReactFlow
        // Re-fit the view when a different graph is loaded or nodes come and go.
        key={`${draft.id}:${draft.graph.nodes.length}`}
        nodes={nodes}
        edges={edges}
        nodeTypes={NODE_TYPES}
        onNodesChange={onNodesChange}
        onNodeClick={(event, n) => {
          const index = nodeIndex(n.id);
          if (index < 0) return;
          // A click on an offered port chip adds that role instead of just selecting.
          const chip = (event.target as HTMLElement).closest('.graph-canvas__port.is-offered');
          const role = chip?.textContent?.trim() as GraphRole | undefined;
          if (chip && role) onAddRole(index, chip.closest('.is-out') ? 'writes' : 'reads', role);
          onSelect(index);
        }}
        onNodeDragStop={(_, n) => {
          const index = nodeIndex(n.id);
          const node = draft.graph.nodes[index];
          if (node) onMove(node.id, n.position.x, n.position.y);
        }}
        onNodesDelete={(deleted) => onRemove(deleted.map((n) => nodeIndex(n.id)).filter((i) => i >= 0))}
        onConnect={connect}
        isValidConnection={(c) => c.source !== SOURCE_NODE || c.targetHandle === 'in-read'}
        fitView
        minZoom={0.2}
        proOptions={{ hideAttribution: true }}
        colorMode="dark"
      >
        <Background gap={20} />
        <Controls showInteractive={false} />
      </ReactFlow>
    </div>
  );
}
