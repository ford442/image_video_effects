import projectFileSchema from '../../contracts/project_file.json';
import { SHARED_CHAIN_VERSION } from '../layerChainShare';
import { PROJECT_FILE_SCHEMA_VERSION, type ProjectFileV1 } from './types';
import { validateProjectFile } from './validate';

function validationErrors(raw: unknown): string[] {
  const result = validateProjectFile(raw);
  if (result.ok) throw new Error('Expected project validation to fail');
  return result.errors;
}

const minimalProject = (): ProjectFileV1 => ({
  schemaVersion: 1,
  app: { name: 'pixelocity', version: '0.1.0' },
  createdAt: '2026-10-11T00:00:00.000Z',
  chain: { v: 1, slots: [] },
  activeSlot: 0,
  source: { kind: 'none' },
  render: {},
});

describe('project file v1 validation', () => {
  it('keeps the JSON contract version aligned with code and SharedChain', () => {
    expect(projectFileSchema.properties.schemaVersion.const).toBe(PROJECT_FILE_SCHEMA_VERSION);
    expect(projectFileSchema.$defs.sharedChain.properties.v.const).toBe(SHARED_CHAIN_VERSION);
    expect(projectFileSchema.additionalProperties).toBe(false);
  });

  it('accepts a minimal valid v1 project', () => {
    expect(validateProjectFile(minimalProject())).toEqual({ ok: true, project: minimalProject() });
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
