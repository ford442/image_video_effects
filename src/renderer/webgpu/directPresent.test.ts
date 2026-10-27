import { readdirSync } from 'fs';
import { DIRECT_PRESENT_FORMAT, directPresentBlocker, makeDirectPresentFrame, toDirectPresentVariant, type DirectPresentInputs } from './directPresent';
import type { FrameSlotDispatchPlan, SlotDispatchPlan } from './slotDispatch';
import type { ComputeOp } from './framePlan';
import { readExpandedShader, SHADER_DIR } from '../../test-utils/shaderSource';
import { loadRealNaga } from '../../test-utils/nagaWasmNode';

const SHADER = `@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let c = vec4<f32>(f32(gid.x) / 64.0, 0.5, min(1.0, 2.0), 1.0);
  if (gid.x > 4u) {
    textureStore(writeTexture, vec2<i32>(gid.xy), c);
    return;
  }
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(select(0.0, 1.0, gid.x < 2u), c.gb, 1.0));
}
`;

function slotPlan(overrides: Partial<SlotDispatchPlan> = {}): SlotDispatchPlan {
  return {
    slot: { shaderId: 'fx', enabled: true, mode: 'chained' },
    slotIndex: 0,
    program: { kind: 'chain', shaderIds: ['fx'] },
    writesDataA: false,
    writesDataB: false,
    ...overrides,
  };
}

function inputs(overrides: Partial<DirectPresentInputs> = {}, plan: Partial<FrameSlotDispatchPlan> = {}): DirectPresentInputs {
  return {
    storageReady: true,
    enabled: true,
    plan: {
      enabledCount: 1,
      parallel: [],
      chained: [slotPlan()],
      anyReadsDataC: false,
      anyUsesHistory: false,
      anyUsesSimRing: false,
      ...plan,
    },
    scaledW: 640,
    scaledH: 360,
    canvasW: 640,
    canvasH: 360,
    inputSource: 'image',
    captureHold: false,
    ...overrides,
  };
}

describe('direct-to-swapchain present (#1512)', () => {
  it('retypes binding 2 and encodes every stored value', () => {
    const variant = toDirectPresentVariant(SHADER);
    expect(variant).not.toBeNull();
    expect(variant).toContain(`var writeTexture: texture_storage_2d<${DIRECT_PRESENT_FORMAT}, write>`);
    expect(variant).not.toContain('rgba32float');
    expect(variant).toContain('textureStore(writeTexture, vec2<i32>(gid.xy), px_direct_present_encode(c))');
    expect(variant).toContain(
      'px_direct_present_encode(vec4<f32>(select(0.0, 1.0, gid.x < 2u), c.gb, 1.0))',
    );
    expect(variant?.match(/px_direct_present_encode\(/g)).toHaveLength(3); // 2 calls + the definition
  });

  it('refuses shaders it cannot rewrite', () => {
    expect(toDirectPresentVariant('fn main() {}')).toBeNull();
    // Declared but never stored: nothing would reach the swapchain.
    expect(toDirectPresentVariant('@group(0) @binding(2) var o: texture_storage_2d<rgba16float, write>;\nfn main() {}')).toBeNull();
    // Unbalanced store call.
    expect(toDirectPresentVariant('@group(0) @binding(2) var o: texture_storage_2d<rgba32float, write>;\nfn main() { textureStore(o, vec2<i32>(0, 0)')).toBeNull();
  });

  it('variants of catalog shaders still validate', async () => {
    const naga = await loadRealNaga();
    const ids = readdirSync(SHADER_DIR)
      .filter((f) => f.endsWith('.wgsl') && !f.startsWith('_'))
      .map((f) => f.slice(0, -5))
      .sort()
      .slice(0, 40);
    let checked = 0;
    for (const id of ids) {
      const source = await readExpandedShader(id);
      if (!source || !naga.validate(source).ok) continue;
      const variant = toDirectPresentVariant(source);
      if (!variant) continue;
      expect(naga.validate(variant), id).toMatchObject({ ok: true });
      checked++;
    }
    expect(checked).toBeGreaterThan(20);
  });

  it('presents directly only when the result matches the blit', () => {
    expect(directPresentBlocker(inputs())).toBeNull();
    expect(directPresentBlocker(inputs({ storageReady: false }))).toBe('storage-unavailable');
    expect(directPresentBlocker(inputs({ enabled: false }))).toBe('disabled');
    expect(directPresentBlocker(inputs({}, { enabledCount: 2, chained: [slotPlan(), slotPlan({ slotIndex: 1 })] })))
      .toBe('not-single-pass');
    expect(directPresentBlocker(inputs({}, { chained: [], parallel: [slotPlan()] }))).toBe('not-single-pass');
    expect(directPresentBlocker(inputs({}, { chained: [slotPlan({ program: { kind: 'chain', shaderIds: ['a', 'b'] } })] })))
      .toBe('not-single-pass');
    const blended = slotPlan({
      slot: {
        shaderId: 'fx',
        enabled: true,
        mode: 'chained',
        layer: { output: 'blend', blend: 'screen', opacity: 0.5, mask: { source: 'none' } },
      },
    });
    expect(directPresentBlocker(inputs({}, { chained: [blended] }))).toBe('composited');
    expect(directPresentBlocker(inputs({ scaledW: 320, scaledH: 180 }))).toBe('resampled');
    expect(directPresentBlocker(inputs({ inputSource: 'generative' }))).toBe('generative-flip');
    expect(directPresentBlocker(inputs({}, { anyUsesHistory: true }))).toBe('history-ring');
    expect(directPresentBlocker(inputs({ captureHold: true }))).toBe('capture');
  });

  it('overrides only the slot shader compute op', () => {
    const pipeline = {} as GPUComputePipeline;
    const bindGroup = {} as GPUBindGroup;
    const frame = makeDirectPresentFrame('fx', pipeline, bindGroup);
    expect(frame.override({ entry: 'fx' } as ComputeOp)).toEqual({ pipeline, bindGroup });
    expect(frame.override({ entry: 'other' } as ComputeOp)).toBeNull();
  });
});
