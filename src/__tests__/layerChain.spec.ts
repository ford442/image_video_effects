/**
 * layerChain.spec.ts
 *
 * Regression harness for multi-slot shader stacking stability.
 * Validates slot orchestration, bind-group compatibility, and texture flow
 * for stacks of varying depth (N = 1, 2, 3, 5) across all 14 categories.
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';
import {
  orchestrateSlots,
  isFrameValid,
  PHYSICAL_SLOT_LIMIT,
  ShaderSlot,
  SlotOrchestration,
} from '../renderer/slotOrchestrator';

// ── Helpers ──────────────────────────────────────────────────────────────────

const SHADER_DIR = resolve(__dirname, '../../public/shaders');

function loadWgsl(id: string): string | null {
  try {
    return readFileSync(resolve(SHADER_DIR, `${id}.wgsl`), 'utf-8');
  } catch {
    return null;
  }
}

function makeSlot(index: number, shaderId: string, mode: 'chained' | 'parallel' = 'chained'): ShaderSlot {
  return { shaderId, enabled: true, mode };
}

function expectValidPlan(plan: SlotOrchestration) {
  expect(plan.errors).toEqual([]);
  expect(plan.valid).toBe(true);
  expect(isFrameValid(plan)).toBe(true);
}

// ── Category Representatives ─────────────────────────────────────────────────
// One shader from each of the 14 categories in shader_definitions/

const CATEGORY_REPS: Record<string, string> = {
  'advanced-hybrid': 'audio-voronoi-displacement',
  artistic: 'ambient-liquid',
  distortion: 'black-hole',
  generative: 'atmos_volumetric_fog',
  geometric: 'adaptive-mosaic',
  hybrid: 'hybrid-chromatic-liquid',
  image: 'aerogel-smoke',
  'interactive-mouse': 'anamorphic-flare',
  'lighting-effects': 'aurora-rift-2-pass1',
  'liquid-effects': 'glass-wipes',
  'post-processing': 'pp-bloom',
  'retro-glitch': 'ascii-flow',
  simulation: 'aero-chromatics',
  'visual-effects': 'ascii-shockwave',
};

// ── Bind-Group Validation Tests ──────────────────────────────────────────────

describe('Bind-group validation', () => {
  test.each(Object.entries(CATEGORY_REPS))(
    'category "%s" representative "%s" has compatible bind group',
    (_category, shaderId) => {
      const wgsl = loadWgsl(shaderId);
      expect(wgsl).not.toBeNull();

      const plan = orchestrateSlots(
        [makeSlot(0, shaderId)],
        (id) => (id === shaderId ? wgsl : null)
      );

      const shaderResult = plan.validationResults.find((r) => r.shaderId === shaderId);
      expect(shaderResult).toBeDefined();
      // Some representatives may have warnings (e.g. extended bindings) but should not have hard errors
      expect(shaderResult!.errors).toEqual([]);
    }
  );

  test('detects missing bindings in an incomplete shader', () => {
    const badWgsl = `
      @group(0) @binding(0) var u_sampler: sampler;
      @group(0) @binding(1) var readTexture: texture_2d<f32>;
      @group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
      @group(0) @binding(3) var<uniform> u: Uniforms;
      struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50> };
      @compute @workgroup_size(16, 16, 1)
      fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {}
    `;

    const plan = orchestrateSlots(
      [makeSlot(0, 'bad-shader')],
      () => badWgsl
    );

    expect(plan.valid).toBe(false);
    expect(plan.errors).toEqual([]);
    const bad = plan.validationResults.find((r) => r.shaderId === 'bad-shader')!;
    expect(bad.errors.length).toBeGreaterThan(0);
    expect(bad.errors.some((e) => e.includes('Missing binding'))).toBe(true);
  });
});

// ── N-Slot Stack Tests ───────────────────────────────────────────────────────

describe('N-slot stacks', () => {
  test('N=1: single chained slot dispatches and copies correctly', () => {
    const id = CATEGORY_REPS['image'];
    const wgsl = loadWgsl(id)!;

    const plan = orchestrateSlots(
      [makeSlot(0, id, 'chained')],
      () => wgsl
    );

    expectValidPlan(plan);
    expect(plan.dispatches).toHaveLength(1);
    expect(plan.dispatches[0].shaderId).toBe(id);
    expect(plan.dispatches[0].mode).toBe('chained');

    // Should copy writeTex→readTex after the slot
    const writeToRead = plan.copies.filter((c) => c.from === 'writeTex' && c.to === 'readTex');
    expect(writeToRead.length).toBeGreaterThanOrEqual(1);

    // Should copy data textures for feedback
    expect(plan.copies.some((c) => c.from === 'dataTexA' && c.to === 'dataTexC')).toBe(true);
    expect(plan.copies.some((c) => c.from === 'dataTexB' && c.to === 'dataTexC')).toBe(true);
  });

  test('N=2: chained slots dispatch in order with inter-slot copies', () => {
    const id1 = CATEGORY_REPS['image'];
    const id2 = CATEGORY_REPS['distortion'];
    const wgsl1 = loadWgsl(id1)!;
    const wgsl2 = loadWgsl(id2)!;
    const wgslMap: Record<string, string> = { [id1]: wgsl1, [id2]: wgsl2 };

    const plan = orchestrateSlots(
      [makeSlot(0, id1, 'chained'), makeSlot(1, id2, 'chained')],
      (sid) => wgslMap[sid] ?? null
    );

    expectValidPlan(plan);
    expect(plan.dispatches.map((d) => d.shaderId)).toEqual([id1, id2]);

    // After each chained slot there should be a writeTex→readTex copy
    const writeToReadCopies = plan.copies.filter((c) => c.from === 'writeTex' && c.to === 'readTex');
    expect(writeToReadCopies.length).toBe(2);
  });

  test('N=3: mixed parallel + chained produces correct copy plan', () => {
    const parallelId = CATEGORY_REPS['generative'];
    const chainedId1 = CATEGORY_REPS['liquid-effects'];
    const chainedId2 = CATEGORY_REPS['visual-effects'];
    const wgslMap: Record<string, string> = {
      [parallelId]: loadWgsl(parallelId)!,
      [chainedId1]: loadWgsl(chainedId1)!,
      [chainedId2]: loadWgsl(chainedId2)!,
    };

    const plan = orchestrateSlots(
      [
        makeSlot(0, parallelId, 'parallel'),
        makeSlot(1, chainedId1, 'chained'),
        makeSlot(2, chainedId2, 'chained'),
      ],
      (sid) => wgslMap[sid] ?? null
    );

    expectValidPlan(plan);

    // Parallel first, then chained
    expect(plan.dispatches[0].mode).toBe('parallel');
    expect(plan.dispatches[0].shaderId).toBe(parallelId);
    expect(plan.dispatches[1].mode).toBe('chained');
    expect(plan.dispatches[2].mode).toBe('chained');

    // Must have a copy after parallel slots finish
    const parallelCopyIndex = plan.copies.findIndex(
      (c) => c.reason.includes('parallel final')
    );
    expect(parallelCopyIndex).toBeGreaterThanOrEqual(0);

    // Must contain a writeTex→readTex copy after chained slots (fixes blit desync)
    expect(plan.copies.some((c) => c.from === 'writeTex' && c.to === 'readTex')).toBe(true);
  });

  test('N=5: orchestrator flags physical slot limit but still produces plan', () => {
    const ids = Object.values(CATEGORY_REPS).slice(0, 5);
    const wgslMap: Record<string, string> = {};
    for (const id of ids) {
      wgslMap[id] = loadWgsl(id)!;
    }

    const plan = orchestrateSlots(
      ids.map((id, idx) => makeSlot(idx, id, 'chained')),
      (sid) => wgslMap[sid] ?? null
    );

    // Plan is produced but flagged as invalid due to slot limit
    expect(plan.errors.some((e) => e.includes('exceeds physical renderer limit'))).toBe(true);
    expect(plan.valid).toBe(false);

    // Still dispatches all 5 (theoretical)
    expect(plan.dispatches).toHaveLength(5);
  });
});

// ── Multipass Chain Tests ────────────────────────────────────────────────────

describe('Multipass chains', () => {
  test('aurora-rift pass1/2 expands into 2 dispatches for one slot', () => {
    const pass1 = 'aurora-rift-pass1';
    const pass2 = 'aurora-rift-pass2';
    const wgslMap: Record<string, string> = {
      [pass1]: loadWgsl(pass1)!,
      [pass2]: loadWgsl(pass2)!,
    };

    const plan = orchestrateSlots(
      [makeSlot(0, pass1, 'chained')],
      (sid) => wgslMap[sid] ?? null
    );

    expectValidPlan(plan);
    expect(plan.dispatches).toHaveLength(2);
    expect(plan.dispatches[0].shaderId).toBe(pass1);
    expect(plan.dispatches[0].passIndex).toBe(0);
    expect(plan.dispatches[1].shaderId).toBe(pass2);
    expect(plan.dispatches[1].passIndex).toBe(1);
  });

  test('quantum-foam expands into 3 dispatches', () => {
    const ids = ['quantum-foam-pass1', 'quantum-foam-pass2', 'quantum-foam-pass3'];
    const wgslMap: Record<string, string> = {};
    for (const id of ids) {
      wgslMap[id] = loadWgsl(id)!;
    }

    const plan = orchestrateSlots(
      [makeSlot(0, ids[0], 'chained')],
      (sid) => wgslMap[sid] ?? null
    );

    expectValidPlan(plan);
    expect(plan.dispatches).toHaveLength(3);
    expect(plan.dispatches.map((d) => d.shaderId)).toEqual(ids);
  });
});

// ── Parallel Overwrite Warning ───────────────────────────────────────────────

describe('Parallel slot warnings', () => {
  test('warns when multiple parallel slots overwrite writeTex', () => {
    const id1 = CATEGORY_REPS['generative'];
    const id2 = CATEGORY_REPS['artistic'];
    const wgslMap: Record<string, string> = {
      [id1]: loadWgsl(id1)!,
      [id2]: loadWgsl(id2)!,
    };

    const plan = orchestrateSlots(
      [makeSlot(0, id1, 'parallel'), makeSlot(1, id2, 'parallel')],
      (sid) => wgslMap[sid] ?? null
    );

    expect(plan.warnings.some((w) => w.includes('only the last slot'))).toBe(true);
  });
});

// ── Texture Format & Dimension Assertions ────────────────────────────────────

describe('Texture format assertions (via copy plan)', () => {
  test('all copies target known texture names', () => {
    const ids = Object.values(CATEGORY_REPS).slice(0, 3);
    const wgslMap: Record<string, string> = {};
    for (const id of ids) {
      wgslMap[id] = loadWgsl(id)!;
    }

    const plan = orchestrateSlots(
      ids.map((id, idx) => makeSlot(idx, id, 'chained')),
      (sid) => wgslMap[sid] ?? null
    );

    for (const copy of plan.copies) {
      expect(['writeTex', 'dataTexA', 'dataTexB']).toContain(copy.from);
      expect(['readTex', 'dataTexC']).toContain(copy.to);
    }
  });
});
