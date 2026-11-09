/**
 * portInference.ts
 *
 * What an entry's WGSL actually binds, read from naga's IR (tools/naga_wasm
 * `wgsl_reflect`) instead of guessed from the graph. The Lab uses it to:
 *   - know which entries declare `@group(1)` (only those get the sim ring);
 *   - show each node's ports — the roles its WGSL really reads and writes;
 *   - warn when a node's graph roles and its WGSL disagree.
 *
 * Reflection runs on the include-expanded source (the `#include` expander lives
 * at the fetch seam, fetchShaderWgsl), so `_prelude.wgsl` bindings count.
 */

import type { GraphNodeDef, GraphRole } from '../renderer/multipassGraph';
import type { NagaBinding, NagaReflection } from '../utils/nagaWasm';

/** naga `GlobalUse` bits. */
const USE_READ = 1;
const USE_WRITE = 2;
const USE_QUERY = 4;
const USE_ATOMIC = 8;

/** Group-0 bindings with a graph role (docs/MULTIPASS_GRAPH.md "Texture roles"). */
const GROUP0_ROLES: Record<number, { role: GraphRole; side: 'reads' | 'writes' }> = {
  1: { role: 'read', side: 'reads' },
  2: { role: 'color', side: 'writes' },
  7: { role: 'dataA', side: 'writes' },
  8: { role: 'dataB', side: 'writes' },
  9: { role: 'dataC', side: 'reads' },
};
/** The history ring (binding 13, texture_2d_array). */
const HISTORY_BINDING = 13;
/** bind_group1.json */
const SIM_GROUP = 1;
const SIM_STATE_BINDING = 0;
const SIM_INDEX_BINDING = 1;
/** bind_group1.json `spatialHash`: the optional simHash binding. */
const SIM_HASH_BINDING = 3;

export type PortStatus =
  /** Reflected and validated: `reads` / `writes` are what the entry points use. */
  | 'ok'
  /** Parsed but naga does not validate it: ports are what the module declares. */
  | 'unvalidated'
  /** No source, or naga cannot parse it. */
  | 'error';

export interface EntryPorts {
  entry: string;
  status: PortStatus;
  /** naga's first error line when status is not 'ok'. */
  message?: string;
  /** Any `@group(1)` binding is declared — the only entries the renderer arms the sim ring for. */
  declaresSimRing: boolean;
  /** Roles the WGSL reads / writes (used bindings; declared ones when unvalidated). */
  reads: GraphRole[];
  writes: GraphRole[];
  /** Binds the history ring (binding 13). */
  usesHistory: boolean;
  /** `[group, binding]` the entry points use (declared when unvalidated), sorted. */
  bindings: Array<[number, number]>;
  workgroupSize?: [number, number, number];
}

function firstLine(message: string | undefined): string | undefined {
  return message
    ?.split('\n')
    .find((l) => l.startsWith('error:'))
    ?.replace(/^error:\s*/, '')
    .trim();
}

/** Default use flags of a declared (not proven used) binding. */
function declaredFlags(b: NagaBinding): number {
  if (b.resource === 'storage_texture') return b.access === 'read' ? USE_READ : b.access === 'write' ? USE_WRITE : USE_READ | USE_WRITE;
  if (b.resource === 'storage') return b.access === 'read' ? USE_READ : USE_READ | USE_WRITE;
  return USE_READ;
}

/** Ports of one entry from a naga reflection (pure; see createPortInference for loading). */
export function portsFromReflection(entry: string, r: NagaReflection): EntryPorts {
  if (!r.ok) {
    return {
      entry,
      status: 'error',
      message: firstLine(r.message) ?? 'naga could not parse this entry',
      declaresSimRing: false,
      reads: [],
      writes: [],
      usesHistory: false,
      bindings: [],
    };
  }
  const declared = r.bindings ?? [];
  const validated = r.valid === true && (r.entryPoints ?? []).every((ep) => Array.isArray(ep.uses));

  // Union of every entry point's uses (a graph entry dispatches `main`, but a file may hold more).
  const flags = new Map<string, number>();
  if (validated) {
    for (const ep of r.entryPoints ?? []) {
      for (const [g, b, bits] of ep.uses ?? []) flags.set(`${g}.${b}`, (flags.get(`${g}.${b}`) ?? 0) | bits);
    }
  } else {
    for (const b of declared) flags.set(`${b.group}.${b.binding}`, declaredFlags(b));
  }

  const reads = new Set<GraphRole>();
  const writes = new Set<GraphRole>();
  for (const [key, bits] of flags) {
    const [g, b] = key.split('.').map(Number) as [number, number];
    const group0 = g === 0 ? GROUP0_ROLES[b] : undefined;
    if (group0) {
      (group0.side === 'reads' ? reads : writes).add(group0.role);
    } else if (g === SIM_GROUP && b === SIM_STATE_BINDING) {
      if (bits & (USE_READ | USE_ATOMIC | USE_QUERY)) reads.add('simState');
      if (bits & (USE_WRITE | USE_ATOMIC)) writes.add('simState');
    } else if (g === SIM_GROUP && b === SIM_INDEX_BINDING) {
      reads.add('simIndex');
    } else if (g === SIM_GROUP && b === SIM_HASH_BINDING) {
      // The planner owns the writes (the scatter pass); a node only ever reads the chain.
      reads.add('simHash');
    }
  }

  const bindings = [...flags.keys()]
    .map((k) => k.split('.').map(Number) as [number, number])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const ep = r.entryPoints?.find((e) => e.name === 'main') ?? r.entryPoints?.[0];
  return {
    entry,
    status: validated ? 'ok' : 'unvalidated',
    message: validated ? undefined : 'naga does not validate this entry; ports are what it declares',
    declaresSimRing: declared.some((b) => b.group === SIM_GROUP),
    reads: [...reads],
    writes: [...writes],
    usesHistory: flags.has(`0.${HISTORY_BINDING}`),
    bindings,
    workgroupSize: ep?.workgroupSize,
  };
}

export interface PortWarning {
  nodeIndex: number;
  nodeId: string;
  message: string;
}

/**
 * Where a node's graph roles and its entry's WGSL disagree. Advisory only: the
 * planner's diagnostics stay the gate for Run / Export.
 */
export function portWarnings(nodes: readonly GraphNodeDef[], ports: ReadonlyMap<string, EntryPorts>): PortWarning[] {
  const out: PortWarning[] = [];
  nodes.forEach((node, nodeIndex) => {
    const p = ports.get(node.entry);
    if (!p) return;
    const warn = (message: string) => out.push({ nodeIndex, nodeId: node.id, message });
    if (p.status === 'error') {
      warn(`${node.entry}: ${p.message}`);
      return;
    }
    const usesSim = (node.reads ?? []).some((r) => r === 'simState' || r === 'simIndex' || r === 'simHash') ||
      (node.writes ?? []).includes('simState') ||
      node.dispatch === 'simState';
    if (usesSim && !p.declaresSimRing) {
      warn(`${node.entry} declares no @group(1): the renderer never binds the sim ring for it`);
    }
    if (p.status !== 'ok') return;
    for (const role of node.reads ?? []) {
      if (role === 'read' || role === 'dataC' || role === 'simState' || role === 'simIndex' || role === 'simHash') {
        if (!p.reads.includes(role)) warn(`reads ${role}, but ${node.entry} never samples it`);
      }
    }
    for (const role of node.writes ?? []) {
      if (!p.writes.includes(role)) warn(`writes ${role}, but ${node.entry} never stores to it`);
    }
  });
  return out;
}

export interface PortInferenceDeps {
  /** Include-expanded WGSL of an entry, or null when there is none. */
  loadSource: (entry: string) => Promise<string | null>;
  reflect: () => Promise<{ reflect(wgsl: string): NagaReflection }>;
}

export interface PortInference {
  /** Cached ports, or undefined while not (yet) inferred. */
  get(entry: string): EntryPorts | undefined;
  /** Infers once per entry; concurrent calls share the work. */
  request(entry: string): Promise<EntryPorts>;
  /** Drop one entry (e.g. its WGSL was edited) or all. */
  invalidate(entry?: string): void;
}

export function createPortInference(deps: PortInferenceDeps): PortInference {
  const done = new Map<string, EntryPorts>();
  const pending = new Map<string, Promise<EntryPorts>>();
  let generation = 0;

  const failed = (entry: string, message: string): EntryPorts => ({
    entry,
    status: 'error',
    message,
    declaresSimRing: false,
    reads: [],
    writes: [],
    usesHistory: false,
    bindings: [],
  });

  return {
    get: (entry) => done.get(entry),
    request(entry) {
      const cached = done.get(entry);
      if (cached) return Promise.resolve(cached);
      const inflight = pending.get(entry);
      if (inflight) return inflight;
      const gen = generation;
      const job = (async () => {
        try {
          const source = await deps.loadSource(entry);
          if (source === null) return failed(entry, `no WGSL found for "${entry}"`);
          const naga = await deps.reflect();
          return portsFromReflection(entry, naga.reflect(source));
        } catch (err) {
          return failed(entry, `port inference failed: ${(err as Error).message}`);
        }
      })().then((ports) => {
        if (gen === generation) {
          pending.delete(entry);
          done.set(entry, ports);
        }
        return ports;
      });
      pending.set(entry, job);
      return job;
    },
    invalidate(entry) {
      if (entry === undefined) {
        generation++;
        done.clear();
        pending.clear();
      } else {
        done.delete(entry);
        pending.delete(entry);
      }
    },
  };
}
