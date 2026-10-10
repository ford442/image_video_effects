import { buildEntryCatalog, entryStem, searchEntries } from './entryCatalog';

const SHADERS = [
  { id: 'plasma', name: 'Plasma', url: 'shaders/plasma.wgsl', category: 'generative' },
  { id: 'kinetic-tiles', name: 'Kinetic Tiles', url: 'shaders/kinetic_tiles.wgsl', category: 'geometric' },
  { id: 'wave-tank', name: 'Wave Tank', url: 'shaders/wave-step.wgsl', category: 'simulation' },
  { id: 'remote', name: 'Remote', url: 'https://cdn.example/p/remote.wgsl?v=2', category: 'image' },
];

describe('entryStem', () => {
  it('takes the file stem of relative, absolute and query-string urls', () => {
    expect(entryStem('shaders/kinetic_tiles.wgsl')).toBe('kinetic_tiles');
    expect(entryStem('https://cdn.example/p/remote.wgsl?v=2#x')).toBe('remote');
    expect(entryStem('plain')).toBe('plain');
  });
});

describe('buildEntryCatalog', () => {
  const catalog = buildEntryCatalog(SHADERS, {
    graphs: { 'wave-tank': { nodes: [{ entry: 'wave-step' }, { entry: 'wave-inject' }, { entry: 'wave-render' }] } },
    chains: { 'quantum-foam-pass1': { nextShader: 'quantum-foam-pass2' }, 'quantum-foam-pass2': { nextShader: null } },
  });

  it('uses file stems, not catalog ids, as entries', () => {
    expect(catalog.knownEntries.has('kinetic_tiles')).toBe(true);
    expect(catalog.knownEntries.has('kinetic-tiles')).toBe(false);
    expect(catalog.byEntry.get('kinetic_tiles')).toMatchObject({ source: 'catalog', catalogId: 'kinetic-tiles' });
    expect(catalog.byEntry.get('remote')).toMatchObject({ catalogId: 'remote' });
  });

  it('adds graph secondaries and chain passes that the catalog lists omit', () => {
    expect(catalog.byEntry.get('wave-inject')).toMatchObject({ source: 'graph-entry' });
    expect(catalog.byEntry.get('wave-inject')?.catalogId).toBeUndefined();
    expect(catalog.byEntry.get('quantum-foam-pass2')).toMatchObject({ source: 'chain-pass' });
  });

  it('prefers the catalog record when a stem is both', () => {
    expect(catalog.byEntry.get('wave-step')).toMatchObject({ source: 'catalog', catalogId: 'wave-tank' });
  });

  it('tracks catalog ids separately (they are what the lists would hide)', () => {
    expect(catalog.catalogIds.has('wave-tank')).toBe(true);
    expect(catalog.catalogIds.has('wave-step')).toBe(false);
  });

  it('is sorted and de-duplicated', () => {
    const entries = catalog.options.map((o) => o.entry);
    expect(entries).toEqual([...entries].sort((a, b) => a.localeCompare(b)));
    expect(new Set(entries).size).toBe(entries.length);
  });
});

describe('searchEntries', () => {
  const catalog = buildEntryCatalog(SHADERS, { graphs: {}, chains: {} });

  it('ANDs tokens over stem and label, prefix matches first', () => {
    expect(searchEntries(catalog, 'tiles kinetic').map((o) => o.entry)).toEqual(['kinetic_tiles']);
    expect(searchEntries(catalog, 'a').map((o) => o.entry)).toEqual(expect.arrayContaining(['plasma']));
    expect(searchEntries(catalog, 'zzz')).toEqual([]);
  });

  it('caps the result list', () => {
    expect(searchEntries(catalog, '', 2)).toHaveLength(2);
  });
});
