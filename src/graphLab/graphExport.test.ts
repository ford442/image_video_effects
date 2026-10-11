/**
 * @jest-environment node
 */
import * as fs from 'fs';
import * as path from 'path';
import { createWaveTankGraph } from '../renderer/multipassGraph';
import { GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';
import { buildEntryCatalog } from './entryCatalog';
import {
  addNode,
  draftFromDefinition,
  draftFromRegistryGraph,
  forkDraft,
  GraphDraft,
  newDraft,
  setMeta,
  setRepeat,
} from './graphDraft';
import { EXPORT_CATEGORIES, exportGraphDefinition } from './graphExport';

const REPO = path.resolve(__dirname, '..', '..');
const DEFS = path.join(REPO, 'shader_definitions');

const fork = (): GraphDraft => forkDraft(draftFromRegistryGraph('wave-tank', createWaveTankGraph()), 'wave-lab', 'Wave Lab');

function ok(draft: GraphDraft, context = {}) {
  const res = exportGraphDefinition(draft, context);
  if (!res.ok) throw new Error(res.errors.join('; '));
  return res;
}

/** The blocking errors of an export that must have been refused. */
function refused(draft: GraphDraft, context = {}): string[] {
  const res = exportGraphDefinition(draft, context);
  if (res.ok) throw new Error('expected the export to be refused');
  return res.errors;
}

function graphDefinitionFiles(): Array<{ file: string; json: Record<string, unknown> }> {
  const out: Array<{ file: string; json: Record<string, unknown> }> = [];
  for (const dir of fs.readdirSync(DEFS, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    for (const f of fs.readdirSync(path.join(DEFS, dir.name))) {
      if (!f.endsWith('.json')) continue;
      const file = path.join(DEFS, dir.name, f);
      let json: unknown;
      try {
        json = JSON.parse(fs.readFileSync(file, 'utf-8'));
      } catch {
        continue;
      }
      const def = Array.isArray(json) ? json[0] : json;
      if (def && typeof def === 'object' && (def as { multipass?: { graph?: unknown } }).multipass?.graph) {
        out.push({ file: path.relative(REPO, file), json: def as Record<string, unknown> });
      }
    }
  }
  return out;
}

describe('exportGraphDefinition', () => {
  it('writes the catalog shape: id, name, root url, multipass.graph', () => {
    const res = ok(fork());
    expect(res.path).toBe('shader_definitions/simulation/wave-lab.json');
    expect(res.definition).toMatchObject({ id: 'wave-lab', name: 'Wave Lab', multipass: { graph: createWaveTankGraph() } });
    expect(JSON.parse(res.json)).toEqual(res.definition);
    expect(res.json.endsWith('\n')).toBe(true);
  });

  it('roots the definition at the first node entry for a new graph', () => {
    let d = newDraft({ id: 'fresh', name: 'Fresh' });
    d = addNode(d, 'wave-step');
    d = addNode(d, 'wave-render');
    const res = ok(d);
    expect(res.definition.url).toBe('shaders/wave-step.wgsl');
    expect(res.definition).toMatchObject({
      description: expect.any(String),
      features: ['simulation', 'multi-pass', 'graph-runner'],
      requiresRgba32Float: true,
    });
  });

  it('keeps an imported root url while it still names a node entry, else falls back to the first', () => {
    const d = forkDraft(draftFromRegistryGraph('wave-tank', createWaveTankGraph(), { id: 'wave-tank', url: 'shaders/wave-inject.wgsl' }), 'x', 'X');
    expect(ok(d).definition.url).toBe('shaders/wave-inject.wgsl');
    const stale = { ...d, envelope: { ...d.envelope, url: 'shaders/gone.wgsl' } };
    expect(ok(stale).definition.url).toBe('shaders/wave-step.wgsl');
  });

  it('refuses a graph the planner would refuse, with the planner’s own messages', () => {
    const d = { ...fork(), graph: { maxPassesPerFrame: 2, nodes: createWaveTankGraph().nodes } };
    expect(refused(d)).toContain('graph exceeds maxPassesPerFrame: 5 > 2');
  });

  it('refuses unknown entries when the catalog is loaded, and skips the check when it is not', () => {
    const entries = buildEntryCatalog([], { graphs: { g: { nodes: [{ entry: 'wave-step' }] } }, chains: {} });
    expect(refused(fork(), { entries }).some((e) => e.includes('unknown entry "wave-inject"'))).toBe(true);
    expect(exportGraphDefinition(fork()).ok).toBe(true);
  });

  describe('id / name / category', () => {
    it.each(['Wave Lab', 'wave_lab', '-wave', '', 'wave lab'])('rejects the id %p', (id) => {
      const res = exportGraphDefinition(setMeta(fork(), { id }));
      expect(res.ok).toBe(false);
    });

    it('rejects the reserved runtime id', () => {
      expect(refused(setMeta(fork(), { id: GRAPH_LAB_RUNTIME_ID })).join(' ')).toContain('reserved');
    });

    it('rejects an id that is already in the catalog, but lets a draft replace its own source', () => {
      const clash = exportGraphDefinition(setMeta(fork(), { id: 'plasma' }), { existingIds: new Set(['plasma']) });
      expect(clash.ok).toBe(false);
      const registryClash = exportGraphDefinition(setMeta(fork(), { id: 'ripple-tank' }));
      expect(registryClash.ok).toBe(false);
      const own = draftFromRegistryGraph('wave-tank', createWaveTankGraph());
      const res = ok(own, { existingIds: new Set(['wave-tank']) });
      expect(res.notes.map((n) => n.code)).toContain('replaces-existing');
    });

    it('requires a name and a real category folder', () => {
      expect(exportGraphDefinition(setMeta(fork(), { name: '  ' })).ok).toBe(false);
      expect(exportGraphDefinition(setMeta(fork(), { category: 'misc' })).ok).toBe(false);
      expect(ok(setMeta(fork(), { category: 'artistic' })).path).toBe('shader_definitions/artistic/wave-lab.json');
    });

    it('lists exactly the shader_definitions folders', () => {
      const dirs = fs.readdirSync(DEFS, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).sort();
      expect([...EXPORT_CATEGORIES].sort()).toEqual(dirs);
    });
  });

  describe('notes', () => {
    it('warns that catalog shaders used as entries drop out of the lists', () => {
      const entries = buildEntryCatalog(
        [{ id: 'wave-inject', name: 'Wave Inject', url: 'shaders/wave-inject.wgsl' }],
        { graphs: { 'wave-tank': createWaveTankGraph() }, chains: {} },
      );
      const notes = ok(fork(), { entries }).notes;
      const hidden = notes.filter((n) => n.code === 'hides-catalog-entry');
      expect(hidden).toHaveLength(1);
      expect(hidden[0]?.message).toContain('"wave-inject"');
      expect(notes.map((n) => n.code)).toContain('drift-baseline');
    });

    it('does not warn for the entry that is the graph’s own id', () => {
      const entries = buildEntryCatalog([{ id: 'wave-step', name: 'Step', url: 'shaders/wave-step.wgsl' }], {
        graphs: { 'wave-tank': createWaveTankGraph() },
        chains: {},
      });
      const d = setMeta(fork(), { id: 'wave-step' });
      // The id exists in the fake catalog on purpose: the draft stands in for that shader.
      expect(ok({ ...d, sourceId: 'wave-step' }, { entries }).notes.some((n) => n.code === 'hides-catalog-entry' && n.message.includes('"wave-step"'))).toBe(false);
    });

    it('mentions missing params, and exports sim-ring fields untouched', () => {
      expect(ok(fork()).notes.map((n) => n.code)).toContain('no-params');
      const dla = draftFromDefinition(JSON.parse(fs.readFileSync(path.join(DEFS, 'artistic', 'dla-crystals.json'), 'utf-8')));
      if (!dla.ok) throw new Error(dla.error);
      const res = ok(dla.draft);
      expect(res.notes.map((n) => n.code)).toContain('sim-ring-untouched');
      expect(res.definition.simRing).toBeDefined();
    });
  });

  it('exports what was edited, not what was imported', () => {
    const res = ok(setRepeat(fork(), 0, 5));
    const nodes = (res.definition.multipass as { graph: { nodes: Array<{ id: string; repeat?: number }> } }).graph.nodes;
    expect(nodes[0]).toMatchObject({ id: 'step', repeat: 5 });
    expect(JSON.stringify(createWaveTankGraph())).toContain('"repeat":3');
  });

  describe('round trip over the shipped graph definitions', () => {
    const files = graphDefinitionFiles();

    it('finds the shipped Tier C definitions', () => {
      expect(files.length).toBeGreaterThanOrEqual(14);
    });

    it.each(files.map((f) => [f.file, f.json] as const))('%s re-exports unchanged', (_file, json) => {
      const imported = draftFromDefinition(json);
      if (!imported.ok) throw new Error(imported.error);
      const res = ok(imported.draft);
      expect(res.definition).toEqual(json);
    });
  });
});
