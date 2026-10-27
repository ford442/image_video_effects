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

  it('rejects a v1 envelope (migrate first) and an unknown version', () => {
    expect(validationErrors({ ...minimalProject(), schemaVersion: 1 })).toContain('project.schemaVersion must be 2');
  });

  it('accepts compositor fields and render.hdr (#1512)', () => {
    const project: ProjectFile = {
      ...minimalProject(),
      chain: {
        v: 1,
        slots: [
          { shaderId: 'a', mode: 'parallel' },
          { shaderId: 'b', mode: 'parallel', b: 'screen', o: 0.5, m: '!s0~0.25', k: 0.3 },
          { shaderId: 'c', b: 'mask' },
        ],
      },
      render: { quality: 'ultra', hdr: { paperWhiteNits: 203, peakNits: 1000 } },
    };
    expect(validateProjectFile(project)).toEqual({ ok: true, project });
  });

  it('rejects malformed compositor fields and out-of-range HDR nits', () => {
    const errors = validationErrors({
      ...minimalProject(),
      chain: { v: 1, slots: [{ shaderId: 'a', b: 'lighten', o: 1.5, m: 's7', k: '0.2' }] },
      render: { hdr: { paperWhiteNits: 400, peakNits: 300 } },
    });
    const all = errors.join(' ');
    for (const field of ['.b ', '.o ', '.m ', '.k ', 'peakNits']) expect(all).toContain(field);
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
