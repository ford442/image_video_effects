import { buildVjSetExport } from '../vjSetExport';
import type { SharedChain } from '../layerChainShare';
import { migrateProjectFile } from './migrate';
import { validateProjectFile } from './validate';

const chain: SharedChain = {
  v: 1,
  slots: [{ shaderId: 'demo', params: { zoomParam1: 0.25 } }],
};
const fixedNow = () => new Date('2026-10-11T00:00:00.000Z');

describe('project file migration', () => {
  it('lifts a bare SharedChain into v1', () => {
    const migrated = migrateProjectFile(chain, fixedNow);
    expect(migrated.project).toMatchObject({
      schemaVersion: 1,
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
});
