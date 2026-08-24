/**
 * Format-tier bench matrix (#1008 follow-up).
 *
 * Five workload shapes that stress the tier decision differently:
 *   1. simple generative     — pure ALU, little bandwidth; tier should barely matter
 *   2. feedback fluid        — FP32-required; must stay rgba32float on every tier
 *   3. ripple-tank graph     — Tier C multipass; exercises maxPassesPerFrame
 *   4. multi-slot chain      — 3 chained slots; balanced/battery cap slots to 2/1
 *   5. history-ring temporal — binding 13 ring; 8 extra layers of bandwidth
 *
 * See docs/FORMAT_TIERS.md and reports/format-tier-bench-TEMPLATE.md.
 */
import type { ParityShaderCase } from './parityMatrix';

export type TierWorkloadKind =
  | 'simple-generative'
  | 'feedback-fluid'
  | 'graph-multipass'
  | 'multi-slot-chain'
  | 'history-ring';

export interface TierShaderCase extends ParityShaderCase {
  /** Catalog metadata the app would pass to loadShader (drives the FP32 pin). */
  meta?: {
    requiresRgba32Float?: boolean;
    requiresHistoryRing?: boolean;
    requiresDeepWorkgroup?: boolean;
  };
}

export interface FormatTierCase {
  /** Stable key used in the report table. */
  key: string;
  kind: TierWorkloadKind;
  /** Shaders to load, in slot order. Slot 0 first. */
  shaders: TierShaderCase[];
  /** True when the case is expected to hold storage at rgba32float on every tier. */
  expectsFp32Pin: boolean;
  /** Graph id when the case drives a Tier C multipass graph. */
  graphId?: string;
  notes: string;
}

const shader = (
  id: string,
  slot = 0,
  testState?: ParityShaderCase['testState'],
  extra?: { url?: string; meta?: TierShaderCase['meta'] },
): TierShaderCase => ({
  id,
  // Graph roots point at their first pass — mirror the catalog `url` exactly.
  url: extra?.url ?? `./shaders/${id}.wgsl`,
  category: 'generative',
  slot,
  testState,
  meta: extra?.meta,
});

export const FORMAT_TIER_MATRIX: FormatTierCase[] = [
  {
    key: 'simple-generative',
    kind: 'simple-generative',
    shaders: [shader('plasma', 0, { time: 4.0, mouseX: 0.5, mouseY: 0.5 })],
    expectsFp32Pin: false,
    notes: 'ALU-bound baseline. Large tier deltas here mean the bottleneck is not bandwidth.',
  },
  {
    key: 'feedback-fluid',
    kind: 'feedback-fluid',
    shaders: [
      shader('sim-fluid-feedback-coupled', 0, { time: 2.5, mouseX: 0.55, mouseY: 0.45 }, {
        // Catalog JSON / allowlist — not inferred from a generic "fluid" tag.
        meta: { requiresRgba32Float: true },
      }),
    ],
    expectsFp32Pin: true,
    notes: 'requiresRgba32Float — must report colorFormat=rgba32float and fp32Pinned on non-ultra tiers.',
  },
  {
    key: 'ripple-tank-graph',
    kind: 'graph-multipass',
    shaders: [
      shader('ripple-tank', 0, { time: 3.0, mouseX: 0.5, mouseY: 0.5 }, {
        url: './shaders/ripple-tank-step.wgsl',
        meta: { requiresRgba32Float: true },
      }),
    ],
    expectsFp32Pin: true,
    graphId: 'ripple-tank',
    notes:
      'Tier C graph (7 dispatches expanded). Battery caps at 4/frame — expect a GraphRunner '
      + 'pass-cap warning. Catalog marks it requiresRgba32Float, so FP32 stays pinned.',
  },
  {
    key: 'multi-slot-chain',
    kind: 'multi-slot-chain',
    shaders: [
      shader('plasma', 0, { time: 4.0, mouseX: 0.5, mouseY: 0.5 }),
      shader('liquid', 1, { time: 2.0, mouseX: 0.65, mouseY: 0.35 }),
      shader('cyber-ripples', 2, { time: 1.8, mouseX: 0.6, mouseY: 0.4, bass: 0.7 }),
    ],
    expectsFp32Pin: false,
    notes: 'Slot cap is part of the tier: ultra 3, balanced 2, battery 1 — slots 1/2 may be refused.',
  },
  {
    key: 'history-ring-temporal',
    kind: 'history-ring',
    shaders: [
      shader('temporal-phosphor-burn', 0, { time: 3.5, mouseX: 0.5, mouseY: 0.5 }, {
        meta: { requiresHistoryRing: true },
      }),
    ],
    expectsFp32Pin: false,
    notes: 'Binding 13 ring (8 layers). Highest bandwidth win expected from FP16.',
  },
];

/** Tiers measured, in report order. `auto` is excluded — it is hardware-dependent. */
export const TIER_SWEEP = ['ultra', 'balanced', 'battery'] as const;
export type SweptTier = (typeof TIER_SWEEP)[number];
