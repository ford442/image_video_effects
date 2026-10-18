import { readFileSync } from 'fs';
import { resolve } from 'path';
import { loadRealNaga } from '../test-utils/nagaWasmNode';
import { expandWgslIncludes } from '../wasm/bridge/wgslInclude';
import type { NagaReflection } from '../utils/nagaWasm';
import { createPortInference, EntryPorts, portsFromReflection, portWarnings } from './portInference';

const SHADERS = resolve(__dirname, '../../public/shaders');
const readShader = (name: string) => readFileSync(resolve(SHADERS, name), 'utf8');
const expanded = (id: string) =>
  expandWgslIncludes(readShader(`${id}.wgsl`), async (name) => readShader(name), `${id}.wgsl`);

describe('portsFromReflection (real naga)', () => {
  it('detects @group(1) and the sim roles of a sim-ring walker from its WGSL', async () => {
    const naga = await loadRealNaga();
    const ports = portsFromReflection('dla-walkers', naga.reflect(await expanded('dla-walkers')));
    expect(ports.status).toBe('ok');
    expect(ports.declaresSimRing).toBe(true);
    expect(ports.reads).toEqual(expect.arrayContaining(['dataC', 'simState']));
    expect(ports.writes).toEqual(expect.arrayContaining(['dataA', 'simState']));
    expect(ports.writes).not.toContain('color');
    expect(ports.workgroupSize).toEqual([64, 1, 1]);
  });

  it('counts a group-1 declaration even when only simParams is bound', async () => {
    const naga = await loadRealNaga();
    const ports = portsFromReflection('dla-render', naga.reflect(await expanded('dla-render')));
    expect(ports.declaresSimRing).toBe(true);
    expect(ports.reads).not.toContain('simState');
    expect(ports.writes).toContain('color');
  });

  it('reports used bindings, not the 13 the prelude declares', async () => {
    const naga = await loadRealNaga();
    const r = naga.reflect(`
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let c = textureLoad(readTexture, vec2<i32>(gid.xy), 0);
  textureStore(writeTexture, vec2<i32>(gid.xy), c);
}`);
    const ports = portsFromReflection('x', r);
    expect(ports.reads).toEqual(['read']);
    expect(ports.writes).toEqual(['color']);
    expect(ports.bindings).toEqual([
      [0, 1],
      [0, 2],
    ]);
  });

  it('a parse error is an error status with naga’s message', async () => {
    const naga = await loadRealNaga();
    const ports = portsFromReflection('x', naga.reflect('fn main( {'));
    expect(ports.status).toBe('error');
    expect(ports.message).toBeTruthy();
  });
});

describe('portsFromReflection (unvalidated)', () => {
  it('falls back to the declared bindings', () => {
    const r: NagaReflection = {
      ok: true,
      valid: false,
      bindings: [
        { group: 0, binding: 9, name: 'dataTextureC', resource: 'texture', access: 'read', dim: '2d', arrayed: false },
        { group: 1, binding: 0, name: 'simState', resource: 'storage', access: 'read_write', dim: '', arrayed: false },
      ],
      entryPoints: [{ name: 'main', stage: 'compute', workgroupSize: [64, 1, 1] }],
    };
    const ports = portsFromReflection('x', r);
    expect(ports.status).toBe('unvalidated');
    expect(ports.reads).toEqual(expect.arrayContaining(['dataC', 'simState']));
    expect(ports.writes).toEqual(['simState']);
    expect(ports.declaresSimRing).toBe(true);
  });
});

const ok = (entry: string, over: Partial<EntryPorts> = {}): EntryPorts => ({
  entry,
  status: 'ok',
  declaresSimRing: false,
  reads: [],
  writes: [],
  usesHistory: false,
  bindings: [],
  ...over,
});

describe('portWarnings', () => {
  it('flags sim roles on an entry without @group(1), and roles the WGSL never binds', () => {
    const ports = new Map([
      ['plain', ok('plain', { reads: ['read'], writes: ['color'] })],
      ['walker', ok('walker', { declaresSimRing: true, reads: ['simState'], writes: ['simState'] })],
    ]);
    const warnings = portWarnings(
      [
        { id: 'a', entry: 'plain', reads: ['read', 'dataC'], writes: ['color', 'simState'] },
        { id: 'b', entry: 'walker', reads: ['simState'], writes: ['simState'], dispatch: 'simState' },
      ],
      ports,
    );
    expect(warnings.map((w) => [w.nodeIndex, w.message])).toEqual([
      [0, 'plain declares no @group(1): the renderer never binds the sim ring for it'],
      [0, 'reads dataC, but plain never samples it'],
      [0, 'writes simState, but plain never stores to it'],
    ]);
  });

  it('says nothing for entries not yet inferred', () => {
    expect(portWarnings([{ id: 'a', entry: 'x', reads: ['dataC'], writes: ['simState'] }], new Map())).toEqual([]);
  });
});

describe('createPortInference', () => {
  const reflection: NagaReflection = { ok: true, valid: true, bindings: [], entryPoints: [] };

  it('loads each entry once and caches it', async () => {
    const loadSource = vi.fn(async () => 'src');
    const reflect = vi.fn(() => reflection);
    const inf = createPortInference({ loadSource, reflect: async () => ({ reflect }) });
    const [a, b] = await Promise.all([inf.request('e'), inf.request('e')]);
    expect(a).toBe(b);
    expect(await inf.request('e')).toBe(a);
    expect(inf.get('e')).toBe(a);
    expect(loadSource).toHaveBeenCalledTimes(1);
    inf.invalidate('e');
    expect(inf.get('e')).toBeUndefined();
  });

  it('a missing source or a loader failure is an error status, not a rejection', async () => {
    const inf = createPortInference({
      loadSource: async (e) => (e === 'gone' ? null : 'src'),
      reflect: async () => {
        throw new Error('no wasm');
      },
    });
    expect((await inf.request('gone')).message).toMatch(/no WGSL/);
    expect((await inf.request('other')).message).toMatch(/no wasm/);
  });
});
