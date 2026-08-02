/**
 * Contract test: src/contracts/uniforms_layout.json is the source of truth for the
 * WGSL `Uniforms` struct. UNIFORM_OFFSETS / UNIFORM_BUFFER_LAYOUT must not drift from it.
 * Cross-backend + docs drift is enforced separately by `npm run verify:uniforms` in CI.
 */

import contract from '../contracts/uniforms_layout.json';
import { UNIFORM_OFFSETS, UNIFORM_FLOATS, MAX_RIPPLES, createUniformBufferView } from './UniformBuffer';
import { UNIFORM_BUFFER_LAYOUT } from './types';

type OffsetKey = keyof typeof UNIFORM_OFFSETS;

const field = (name: string) => {
  const f = contract.fields.find((x) => x.name === name);
  if (!f) throw new Error(`contract missing field ${name}`);
  return f;
};

describe('uniforms layout contract (shared JSON)', () => {
  it('exports the expected contract version', () => {
    expect(contract.version).toBe(1);
  });

  it('matches UNIFORM_OFFSETS for every documented component', () => {
    for (const f of contract.fields) {
      for (const comp of f.components) {
        const key = (comp as { tsOffsetKey?: string }).tsOffsetKey;
        if (!key) continue;
        expect(UNIFORM_OFFSETS[key as OffsetKey]).toBe(f.name === 'ripples' ? f.offset : comp.offset);
      }
    }
    expect(UNIFORM_OFFSETS.ripple_stride).toBe(field('ripples').strideBytes);
  });

  it('matches UNIFORM_BUFFER_LAYOUT offsets and size', () => {
    expect(UNIFORM_BUFFER_LAYOUT.CONFIG_OFFSET).toBe(field('config').offset);
    expect(UNIFORM_BUFFER_LAYOUT.ZOOM_CONFIG_OFFSET).toBe(field('zoom_config').offset);
    expect(UNIFORM_BUFFER_LAYOUT.ZOOM_PARAMS_OFFSET).toBe(field('zoom_params').offset);
    expect(UNIFORM_BUFFER_LAYOUT.RIPPLES_OFFSET).toBe(field('ripples').offset);
    expect(UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE).toBe(contract.totalSizeBytes);
    expect(UNIFORM_BUFFER_LAYOUT.MAX_RIPPLES).toBe(contract.maxRipples);
    expect(MAX_RIPPLES).toBe(contract.maxRipples);
    expect(UNIFORM_FLOATS).toBe(contract.floatCount);
    expect(UNIFORM_FLOATS * 4).toBe(contract.totalSizeBytes);
  });

  it('documents config.y as rippleCount, never delta time', () => {
    const cfg = field('config');
    expect(cfg.components.map((c) => c.meaning)).toEqual([
      'time',
      'rippleCount',
      'resolutionWidth',
      'resolutionHeight',
    ]);

    const view = createUniformBufferView();
    view.setConfig(12.5, 3, 1920, 1080);
    const data = view.data;
    expect(data[UNIFORM_OFFSETS.config_time / 4]).toBeCloseTo(12.5);
    expect(data[UNIFORM_OFFSETS.config_rippleCount / 4]).toBe(3);
    expect(data[UNIFORM_OFFSETS.config_resW / 4]).toBe(1920);
    expect(data[UNIFORM_OFFSETS.config_resH / 4]).toBe(1080);
  });

  it('writes zoom_config as [time, mouseX, mouseY, mouseDown] with top-down Y', () => {
    expect(field('zoom_config').components.map((c) => c.meaning)).toEqual([
      'time',
      'mouseX',
      'mouseY',
      'mouseDown',
    ]);

    const view = createUniformBufferView();
    view.setZoomConfig(1, 0.25, 0.75, 1);
    const data = view.data;
    expect(data[UNIFORM_OFFSETS.zoom_mouseX / 4]).toBeCloseTo(0.25);
    // No flip: the value written is the value the shader reads.
    expect(data[UNIFORM_OFFSETS.zoom_mouseY / 4]).toBeCloseTo(0.75);
    expect(data[UNIFORM_OFFSETS.zoom_mouseDown / 4]).toBe(1);
  });

  it('packs ripples at the documented stride with zero padding', () => {
    const view = createUniformBufferView();
    view.setRipple(2, 0.1, 0.2, 5);
    const base = (UNIFORM_OFFSETS.ripples_start + 2 * UNIFORM_OFFSETS.ripple_stride) / 4;
    expect(view.data[base]).toBeCloseTo(0.1);
    expect(view.data[base + 1]).toBeCloseTo(0.2);
    expect(view.data[base + 2]).toBe(5);
    expect(view.data[base + 3]).toBe(0);
  });
});
