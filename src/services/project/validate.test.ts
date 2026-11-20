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
  schemaVersion: 3,
  app: { name: 'pixelocity', version: '0.1.0' },
  createdAt: '2026-10-11T00:00:00.000Z',
  chain: { v: 1, slots: [] },
  activeSlot: 0,
  source: { kind: 'none' },
  render: {},
  modulation: [],
});

describe('project file v3 validation', () => {
  it('keeps the JSON contract version aligned with code and SharedChain', () => {
    expect(projectFileSchema.properties.schemaVersion.const).toBe(PROJECT_FILE_SCHEMA_VERSION);
    expect(projectFileSchema.$defs.sharedChain.properties.v.const).toBe(SHARED_CHAIN_VERSION);
    expect(projectFileSchema.additionalProperties).toBe(false);
  });

  it('accepts a minimal valid v3 project', () => {
    expect(validateProjectFile(minimalProject())).toEqual({ ok: true, project: minimalProject() });
  });

  it('rejects a v1 envelope (migrate first) and an unknown version', () => {
    expect(validationErrors({ ...minimalProject(), schemaVersion: 1 })).toContain('project.schemaVersion must be 3');
    expect(validationErrors({ ...minimalProject(), schemaVersion: 2 })).toContain('project.schemaVersion must be 3');
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

  it('accepts modulation routes and rejects malformed ones (#1513)', () => {
    const project: ProjectFile = {
      ...minimalProject(),
      modulation: [
        { id: 'a', source: { kind: 'lfo', shape: 'sine', unit: 'beats', rate: 4 }, target: { slot: 0, param: 'p1' }, depth: 0.5, offset: 0, curve: 'smooth' },
        { id: 'b', source: { kind: 'sequencer', steps: Array(16).fill(0.5), stepBeats: 0.25 }, target: { slot: 2, param: 'opacity' }, depth: -1, offset: 0.2, curve: 'linear' },
      ],
    };
    expect(validateProjectFile(project)).toEqual({ ok: true, project });
    const errors = validationErrors({
      ...minimalProject(),
      modulation: [
        { ...project.modulation[0], target: { slot: 9, param: 'p1' } },
        { ...project.modulation[0], curve: 'cubic' },
        project.modulation[1],
        project.modulation[1],
      ],
    }).join(' ');
    expect(errors).toContain('modulation[0].target.slot');
    expect(errors).toContain('modulation[1].curve');
    expect(errors).toContain('duplicate');
    const raw = minimalProject() as unknown as Record<string, unknown>;
    delete raw.modulation;
    expect(validationErrors(raw)).toContain('project.modulation must be an array');
  });

  it('accepts the #1401 timeline additions: every SlotParams key, source events, keyframes', () => {
    const timeline = {
      exportVersion: 1,
      name: 'Set',
      savedAt: 1,
      chain: { v: 1, slots: [] },
      chainString: 'x',
      timeline: {
        hz: 20,
        durationMs: 2000,
        events: [
          { t: 0, slot: 0, kind: 'source', value: { type: 'video', url: 'https://cdn.example/v.mp4', seekSec: 4 } },
          { t: 0, slot: 1, kind: 'param', key: 'depthThreshold', value: 0.4 },
        ],
        keyframes: [{ t: 1000, slot: 1, key: 'zoomParam3', value: 0.9, ease: 'easeInOut' }],
      },
    };
    const result = validateProjectFile({ ...minimalProject(), timeline });
    expect(result.ok).toBe(true);
    expect(result.ok && result.project.timeline?.timeline?.keyframes).toHaveLength(1);
    expect(result.ok && result.project.timeline?.timeline?.events[0]).toMatchObject({ kind: 'source' });

    const keyframesOnly = { ...timeline, timeline: { ...timeline.timeline, events: [] } };
    expect(validateProjectFile({ ...minimalProject(), timeline: keyframesOnly }).ok).toBe(true);

    const bad = {
      ...timeline,
      timeline: {
        ...timeline.timeline,
        events: [{ t: 0, slot: 0, kind: 'source', value: { type: 'image', url: 'blob:https://app/1' } }],
        keyframes: [{ t: 0, slot: 0, key: 'zoomParam1', value: 1, ease: 'bounce' }],
      },
    };
    const errors = validationErrors({ ...minimalProject(), timeline: bad }).join(' ');
    expect(errors).toContain('no data:/blob: URLs');
    expect(errors).toContain('keyframes[0]');
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
