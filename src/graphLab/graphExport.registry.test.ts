/**
 * @jest-environment node
 *
 * The acceptance check for "exported definitions are consumed by the existing
 * registry/build path without hand-translating": write an export into a scratch
 * shader_definitions tree and run the real generator over it.
 */
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { createWaveTankGraph } from '../renderer/multipassGraph';
import { addNode, forkDraft, draftFromRegistryGraph, newDraft, setRepeat } from './graphDraft';
import { exportGraphDefinition } from './graphExport';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { buildRegistry } = require('../../scripts/buildMultipassRegistry.js') as {
  buildRegistry: (o: { defsDir: string; outFile: string; write?: boolean }) => {
    registry: Record<string, unknown>;
    graphRegistry: Record<string, unknown>;
    simRingRegistry: Record<string, unknown>;
    source: string;
  };
};

let tmp: string;
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'graph-lab-defs-'));
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function install(json: string, relPath: string) {
  // `shader_definitions/<category>/<id>.json` → <tmp>/<category>/<id>.json
  const target = path.join(tmp, relPath.replace(/^shader_definitions\//, ''));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, json);
}

const build = () => buildRegistry({ defsDir: tmp, outFile: path.join(tmp, 'registry.ts'), write: false });

describe('exported definitions through scripts/buildMultipassRegistry.js', () => {
  it('lands in GRAPH_REGISTRY exactly as authored', () => {
    const draft = setRepeat(forkDraft(draftFromRegistryGraph('wave-tank', createWaveTankGraph()), 'wave-lab', 'Wave Lab'), 0, 4);
    const res = exportGraphDefinition(draft);
    if (!res.ok) throw new Error(res.errors.join('; '));
    install(res.json, res.path);

    const built = build();
    expect(Object.keys(built.graphRegistry)).toEqual(['wave-lab']);
    expect(built.graphRegistry['wave-lab']).toEqual(draft.graph);
    expect(built.source).toContain('"wave-lab"');
  });

  it('works for a graph authored from scratch', () => {
    let draft = newDraft({ id: 'fresh-graph', name: 'Fresh' });
    draft = addNode(draft, 'wave-step');
    draft = addNode(draft, 'wave-render');
    const res = exportGraphDefinition(draft);
    if (!res.ok) throw new Error(res.errors.join('; '));
    install(res.json, res.path);
    expect(build().graphRegistry['fresh-graph']).toEqual(draft.graph);
  });

  it('does not touch the Tier B chain or sim-ring tables', () => {
    const res = exportGraphDefinition(forkDraft(draftFromRegistryGraph('wave-tank', createWaveTankGraph()), 'wave-lab', 'Wave Lab'));
    if (!res.ok) throw new Error(res.errors.join('; '));
    install(res.json, res.path);
    const built = build();
    expect(built.registry).toEqual({});
    expect(built.simRingRegistry).toEqual({});
  });

  it('emits the runtime-overlay resolvers the Lab depends on', () => {
    const { source } = build();
    expect(source).toContain("import { getRuntimeGraph } from './runtimeGraphs';");
    expect(source).toContain('return getRuntimeGraph(shaderId) ?? GRAPH_REGISTRY[shaderId] ?? null;');
    expect(source).toContain('return resolveGraphForShader(shaderId) !== null;');
  });

  it('keeps the committed resolver block in sync with the generator template', () => {
    const committed = fs.readFileSync(path.resolve(__dirname, '..', 'renderer', 'multipassRegistry.ts'), 'utf-8');
    const generated = buildRegistry({
      defsDir: path.resolve(__dirname, '..', '..', 'shader_definitions'),
      outFile: path.join(tmp, 'registry.ts'),
      write: false,
    }).source;
    // The resolver block (what this feature changed) must match; the data tables are covered by the audit.
    const block = (s: string) => s.slice(s.indexOf('/**\n * Resolve the Tier C graph'), s.indexOf('/**\n * Requested sim-ring'));
    expect(block(committed)).toBe(block(generated));
    expect(block(committed)).toContain('getRuntimeGraph');
  });
});
