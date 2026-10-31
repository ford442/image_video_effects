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
    { shaderId: 'known-b', params: { ambient: 0.8 }, mode: 'parallel', b: 'screen', o: 0.5, m: '!s0~0.25' },
  ],
};

describe('project file export/import', () => {
  it('round-trips every supported project field', () => {
    const project = buildProjectFile({
      chain,
      activeSlot: 2,
      source: { kind: 'video', ref: 'videos/demo.mp4' },
      quality: 'balanced',
      hdr: { paperWhiteNits: 240, peakNits: 1600 },
      audioMappings: [{
        trigger: { source: 'midi-cc', id: 'ch1/cc7' },
        action: { type: 'setSlotParam', slot: 2, param: 'zoomParam1' },
      }],
      modulation: [{
        id: 'lfo-1', source: { kind: 'lfo', shape: 'tri', unit: 'beats', rate: 2 },
        target: { slot: 2, param: 'opacity' }, depth: -0.5, offset: 0, curve: 'exp',
      }],
      createdAt: '2026-10-11T00:00:00.000Z',
      appVersion: 'test-version',
    });
    expect(project.schemaVersion).toBe(3);
    expect(project.modulation).toHaveLength(1);

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

  it('carries modulation routes into the plan and drops routes on emptied slots (#1513)', () => {
    const route = (id: string, slot: number) => ({
      id, source: { kind: 'audio' as const, band: 'bass' as const }, target: { slot, param: 'p1' as const }, depth: 1, offset: 0, curve: 'linear' as const,
    });
    const project = buildProjectFile({
      chain, activeSlot: 0, source: { kind: 'none' }, modulation: [route('keep', 0), route('unknown', 2), route('empty', 1)],
    });
    const plan = createProjectApplyPlan(project, { knownShaderIds: new Set(['known-a']) });
    expect(plan.modulation.map((r) => r.id)).toEqual(['keep']);
    expect(plan.warnings.join(' ')).toContain('"unknown"');
    expect(plan.warnings.join(' ')).toContain('"empty"');
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
    const planned = createProjectApplyPlan(parsed.project, { knownShaderIds: new Set(['known-a', 'known-b']) }).chain;
    expect(planned.slots).toHaveLength(6);
    expect(planned.slots.slice(0, chain.slots.length)).toEqual(chain.slots);
    expect(planned.slots.slice(chain.slots.length)).toEqual([
      { shaderId: null },
      { shaderId: null },
      { shaderId: null },
    ]);
  });
});
