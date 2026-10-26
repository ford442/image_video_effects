import { buildVjSetExport } from '../vjSetExport';
import { expandSharedChain, type SharedChain } from '../layerChainShare';
import { DEFAULT_SLOT_OUTPUT } from '../../renderer/slotOutput';
import { migrateProjectFile } from './migrate';
import { validateProjectFile } from './validate';
import type { ProjectFileV1 } from './types';

const chain: SharedChain = {
  v: 1,
  slots: [{ shaderId: 'demo', params: { zoomParam1: 0.25 } }],
};
const fixedNow = () => new Date('2026-10-11T00:00:00.000Z');

describe('project file migration', () => {
  it('lifts a bare SharedChain into the current version', () => {
    const migrated = migrateProjectFile(chain, fixedNow);
    expect(migrated.project).toMatchObject({
      schemaVersion: 2,
      createdAt: '2026-10-11T00:00:00.000Z',
      chain,
      activeSlot: 0,
      source: { kind: 'none' },
      render: {},
    });
    expect(validateProjectFile(migrated.project).ok).toBe(true);
  });

  it('lifts a bare VJ set export and preserves mappings/timeline payload', () => {
    const payload = buildVjSetExport('Legacy', chain, {
      bindings: [{
        trigger: { source: 'key', id: 'KeyA' },
        action: { type: 'randomizeAll' },
      }],
      timeline: {
        hz: 20,
        durationMs: 100,
        events: [{ t: 0, slot: 0, kind: 'shader', value: 'demo' }],
      },
    });
    payload.savedAt = Date.parse('2026-10-10T12:00:00.000Z');

    const migrated = migrateProjectFile(payload, fixedNow);
    expect(migrated.project?.chain).toEqual(chain);
    expect(migrated.project?.audio?.mappings).toEqual(payload.bindings);
    expect(migrated.project?.timeline).toEqual(payload);
    expect(migrated.project?.createdAt).toBe('2026-10-10T12:00:00.000Z');
    expect(validateProjectFile(migrated.project).ok).toBe(true);
  });

  it('migrates a v1 project to v2: same session, every slot a replace layer (#1512)', () => {
    const v1: ProjectFileV1 = {
      schemaVersion: 1,
      app: { name: 'pixelocity', version: '0.1.0' },
      createdAt: '2026-10-11T00:00:00.000Z',
      chain: { v: 1, slots: [
        { shaderId: 'demo', params: { zoomParam1: 0.25 } },
        { shaderId: 'over', mode: 'parallel', enabled: false },
      ] },
      activeSlot: 1,
      source: { kind: 'image', ref: 'https://example.com/a.png' },
      render: { quality: 'balanced' },
      audio: { mappings: [{ trigger: { source: 'key', id: 'KeyA' }, action: { type: 'randomizeAll' } }] },
    };
    const migrated = migrateProjectFile(JSON.parse(JSON.stringify(v1)));
    expect(migrated.reason).toBeUndefined();
    expect(migrated.project).toEqual({ ...v1, schemaVersion: 2 });
    const validated = validateProjectFile(migrated.project);
    expect(validated.ok).toBe(true);
    if (!validated.ok) return;
    expect(validated.project.schemaVersion).toBe(2);
    expect(expandSharedChain(validated.project.chain).slotOutputs).toEqual([
      { ...DEFAULT_SLOT_OUTPUT },
      { ...DEFAULT_SLOT_OUTPUT },
    ]);
    // A v1 file never had compositor keys; any that appear are not trusted.
    const smuggled = migrateProjectFile({ ...v1, chain: { v: 1, slots: [{ shaderId: 'demo', b: 'add', o: 0.1 }] } });
    expect(smuggled.project?.chain.slots[0]).toEqual({ shaderId: 'demo' });
  });

  it('returns null with a reason for an unknown project version', () => {
    const migrated = migrateProjectFile({ schemaVersion: 99 });
    expect(migrated.project).toBeNull();
    expect(migrated.reason).toContain('99');
  });
});
