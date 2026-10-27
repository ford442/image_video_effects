import { buildVjSetExport } from '../vjSetExport';
import type { SharedChain } from '../layerChainShare';
import { migrateProjectFile, migrateV1ToV2 } from './migrate';
import { parseProjectFile } from './importProject';
import type { ProjectFileV1 } from './types';
import { validateProjectFile } from './validate';

const chain: SharedChain = {
  v: 1,
  slots: [{ shaderId: 'demo', params: { zoomParam1: 0.25 } }],
};
const fixedNow = () => new Date('2026-10-11T00:00:00.000Z');

describe('project file migration', () => {
  it('lifts a bare SharedChain into the current version', () => {
    const migrated = migrateProjectFile(chain, fixedNow);
    expect(migrated.migratedFrom).toBe(0);
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

  it('returns null with a reason for an unknown project version', () => {
    const migrated = migrateProjectFile({ schemaVersion: 99 });
    expect(migrated.project).toBeNull();
    expect(migrated.reason).toContain('99');
  });

  it('migrates a v1 project to v2: every slot becomes a replace layer (#1512)', () => {
    const v1: ProjectFileV1 = {
      schemaVersion: 1,
      app: { name: 'pixelocity', version: '0.1.0' },
      createdAt: '2026-10-11T00:00:00.000Z',
      chain: { v: 1, slots: [{ shaderId: 'demo', mode: 'parallel', params: { zoomParam1: 0.25 } }, { shaderId: null }] },
      activeSlot: 1,
      source: { kind: 'generative', generativeShaderId: 'gen-orb' },
      render: { quality: 'balanced' },
      audio: { mappings: [{ trigger: { source: 'key', id: 'KeyA' }, action: { type: 'randomizeAll' } }] },
    };
    const migrated = migrateProjectFile(JSON.parse(JSON.stringify(v1)));
    expect(migrated.migratedFrom).toBe(1);
    expect(migrated.project).toEqual({ ...v1, schemaVersion: 2 });
    expect(migrateV1ToV2(v1)).toEqual({ ...v1, schemaVersion: 2 });
    expect(validateProjectFile(migrated.project).ok).toBe(true);

    const parsed = parseProjectFile(JSON.stringify(v1));
    expect(parsed.ok && parsed.migrationReason).toBe('Upgraded project schema v1 to v2');
    expect(parsed.ok && parsed.project.chain.slots[0]).toEqual(v1.chain.slots[0]);
  });

  it('passes a current v2 project through untouched', () => {
    const v2 = { schemaVersion: 2, chain: { v: 1, slots: [{ shaderId: 'a', b: 'add' }] } };
    const migrated = migrateProjectFile(v2);
    expect(migrated.project).toBe(v2);
    expect(migrated.migratedFrom).toBeUndefined();
  });
});
