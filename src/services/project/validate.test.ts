import projectFileSchema from '../../contracts/project_file.json';
import { SHARED_CHAIN_VERSION } from '../layerChainShare';
import { PROJECT_FILE_SCHEMA_VERSION, type ProjectFile } from './types';
import { validateProjectFile } from './validate';

function validationErrors(raw: unknown): string[] {
  const result = validateProjectFile(raw);
  if (result.ok) throw new Error('Expected project validation to fail');
  return result.errors;
}

const minimalProject = (): ProjectFile => ({
  schemaVersion: 2,
  app: { name: 'pixelocity', version: '0.1.0' },
  createdAt: '2026-10-11T00:00:00.000Z',
  chain: { v: 1, slots: [] },
  activeSlot: 0,
  source: { kind: 'none' },
  render: {},
});

describe('project file v2 validation', () => {
  it('keeps the JSON contract version aligned with code and SharedChain', () => {
    expect(projectFileSchema.properties.schemaVersion.const).toBe(PROJECT_FILE_SCHEMA_VERSION);
    expect(projectFileSchema.$defs.sharedChain.properties.v.const).toBe(SHARED_CHAIN_VERSION);
    expect(projectFileSchema.additionalProperties).toBe(false);
  });

  it('accepts a minimal valid v2 project', () => {
    expect(validateProjectFile(minimalProject())).toEqual({ ok: true, project: minimalProject() });
  });

  it('accepts compositor fields on chain slots and rejects malformed ones (#1512)', () => {
    const layered = {
      ...minimalProject(),
      chain: { v: 1, slots: [
        { shaderId: 'base' },
        { shaderId: 'over', mode: 'parallel', b: 'screen', o: 0.5, m: '~slot2', f: 0.25, k: 0.4 },
        { shaderId: 'matte', mode: 'parallel', b: 'mask' },
      ] },
      audio: { mappings: [{ trigger: { source: 'midi-cc', id: '0:7' }, action: { type: 'setSlotOpacity', slot: 1 } }] },
    };
    const result = validateProjectFile(layered);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.project.chain.slots[1]).toEqual(layered.chain.slots[1]);

    const errors = validationErrors({
      ...minimalProject(),
      chain: { v: 1, slots: [{ shaderId: 'x', b: 'glow', o: 2, m: 'slot9' }] },
    }).join(' ');
    expect(errors).toContain('.b must be');
    expect(errors).toContain('.o must be');
    expect(errors).toContain('.m must be');
    expect(projectFileSchema.$defs.sharedChainSlot.properties.b.enum).toContain('depth-key');
  });

  it('rejects missing required fields with useful messages', () => {
    const raw = minimalProject() as unknown as Record<string, unknown>;
    delete raw.chain;
    delete raw.createdAt;
    expect(validationErrors(raw)).toEqual(expect.arrayContaining([
      expect.stringContaining('createdAt'),
      expect.stringContaining('chain'),
    ]));
  });

  it('rejects an extra top-level key', () => {
    expect(validationErrors({ ...minimalProject(), permission: 'granted' }))
      .toContain('project.permission is not allowed');
  });

  it('rejects malformed slots and unsafe media refs', () => {
    const errors = validationErrors({
      ...minimalProject(),
      chain: { v: 1, slots: [{ shaderId: 'known', params: { surprise: 1 } }] },
      source: { kind: 'image', ref: 'data:image/png;base64,AAAA' },
    });
    expect(errors.join(' ')).toContain('surprise');
    expect(errors.join(' ')).toContain('data/blob');
  });
});
