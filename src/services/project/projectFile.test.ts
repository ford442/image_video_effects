import type { SharedChain } from '../layerChainShare';
import { buildProjectFile, serializeProjectFile } from './exportProject';
import { createProjectApplyPlan, parseProjectFile } from './importProject';
import type { ProjectFile } from './types';

function parsedProject(serialized: string): { project: ProjectFile; migrationReason?: string } {
  const parsed = parseProjectFile(serialized);
  if (!parsed.ok) throw new Error(parsed.errors.join('; '));
  return parsed;
}

const chain: SharedChain = {
  v: 1,
  slots: [
    { shaderId: 'known-a', params: { zoomParam1: 0.2 }, enabled: false, mode: 'parallel' },
    { shaderId: null },
    { shaderId: 'known-b', params: { ambient: 0.8 } },
  ],
};

describe('project file export/import', () => {
  it('round-trips every supported project field', () => {
    const project = buildProjectFile({
      chain,
      activeSlot: 2,
      source: { kind: 'video', ref: 'videos/demo.mp4' },
      quality: 'balanced',
      audioMappings: [{
        trigger: { source: 'midi-cc', id: 'ch1/cc7' },
        action: { type: 'setSlotParam', slot: 2, param: 'zoomParam1' },
      }],
      createdAt: '2026-10-11T00:00:00.000Z',
      appVersion: 'test-version',
    });

    const parsed = parseProjectFile(serializeProjectFile(project));
    expect(parsed.ok).toBe(true);
    expect(parsedProject(serializeProjectFile(project)).project).toEqual(project);
  });

  it('turns an unknown shader into an empty slot and reports it', () => {
    const project = buildProjectFile({
      chain,
      activeSlot: 0,
      source: { kind: 'none' },
    });
    const plan = createProjectApplyPlan(project, {
      knownShaderIds: new Set(['known-a']),
    });

    expect(plan.chain.slots[0]).toEqual(chain.slots[0]);
    expect(plan.chain.slots[2]).toEqual({ shaderId: null });
    expect(plan.warnings.join(' ')).toContain('known-b');
  });

  it('turns unavailable media into none with a relink warning', () => {
    const project = buildProjectFile({
      chain,
      activeSlot: 0,
      source: { kind: 'video', ref: 'missing-video' },
    });
    const plan = createProjectApplyPlan(project, {
      knownShaderIds: new Set(['known-a', 'known-b']),
      isMediaRefAvailable: () => false,
    });

    expect(plan.source).toEqual({ kind: 'none' });
    expect(plan.warnings.join(' ')).toMatch(/relink/i);
  });

  it('never serializes permission state, device handles, or media bytes', () => {
    const stateWithRuntimeOnlyValues = {
      chain,
      activeSlot: 0,
      source: {
        kind: 'image',
        ref: 'data:image/png;base64,MediaStream-permission',
        permission: 'granted',
        deviceHandle: { label: 'MediaStream' },
      },
      permission: 'granted',
    } as any;

    const serialized = serializeProjectFile(buildProjectFile(stateWithRuntimeOnlyValues));
    expect(serialized).not.toContain('MediaStream');
    expect(serialized).not.toContain('permission');
    expect(serialized).not.toContain('data:');
    expect(JSON.parse(serialized).source).toEqual({ kind: 'none' });
  });

  it('parses legacy exports before producing an apply plan', () => {
    const parsed = parsedProject(JSON.stringify(chain));
    expect(parsed.migrationReason).toMatch(/legacy/i);
    expect(createProjectApplyPlan(parsed.project, { knownShaderIds: new Set(['known-a', 'known-b']) }).chain).toEqual(chain);
  });
});
