/**
 * slotOrchestrator.ts
 *
 * Pure, testable logic for multi-slot shader dispatch ordering and
 * texture-copy planning. Mirrors the behavior of WebGPURenderer.renderFrame()
 * but with no WebGPU dependencies.
 */

import { validateBindGroup } from './bindGroupValidator';
import { resolveMultipassChain } from './multipassRegistry';

export type SlotMode = 'chained' | 'parallel';

export interface ShaderSlot {
  shaderId: string | null;
  enabled: boolean;
  mode: SlotMode;
}

export interface SlotDispatch {
  /** Original slot index */
  slotIndex: number;
  /** Shader being dispatched */
  shaderId: string;
  /** Slot mode for this dispatch */
  mode: SlotMode;
  /** Pass index within a multipass chain (0-based) */
  passIndex: number;
  /** Total passes in this chain */
  totalPasses: number;
}

export interface CopyOperation {
  from: 'writeTex' | 'dataTexA' | 'dataTexB';
  to: 'readTex' | 'dataTexC';
  /** Reason for the copy, for debugging */
  reason: string;
}

export interface SlotOrchestration {
  /** Ordered list of shader dispatches */
  dispatches: SlotDispatch[];
  /** Ordered list of copy operations */
  copies: CopyOperation[];
  /** Overall validity */
  valid: boolean;
  /** Per-shader validation results */
  validationResults: Array<{
    shaderId: string;
    valid: boolean;
    errors: string[];
  }>;
  /** Orchestration-level errors (e.g. slot limit exceeded) */
  errors: string[];
  /** Warnings */
  warnings: string[];
}

/** Maximum physical slots supported by the current renderer */
export const PHYSICAL_SLOT_LIMIT = 3;

/**
 * Build a dispatch + copy plan for the given slot configuration.
 *
 * @param slots         Array of shader slots (may be any length for testing)
 * @param wgslResolver  Function that returns WGSL source for a shader ID
 * @param hasPipeline   Function that returns whether a shader pipeline is cached
 */
export function orchestrateSlots(
  slots: ShaderSlot[],
  wgslResolver: (shaderId: string) => string | null,
  hasPipeline: (shaderId: string) => boolean = () => true
): SlotOrchestration {
  const result: SlotOrchestration = {
    dispatches: [],
    copies: [],
    valid: true,
    validationResults: [],
    errors: [],
    warnings: [],
  };

  // Slot limit check
  if (slots.length > PHYSICAL_SLOT_LIMIT) {
    result.errors.push(
      `Slot count ${slots.length} exceeds physical renderer limit of ${PHYSICAL_SLOT_LIMIT}`
    );
    result.valid = false;
  }

  // Filter enabled slots with resolved pipelines
  const enabled = slots
    .map((s, idx) => ({ ...s, index: idx }))
    .filter(
      (s) => s.enabled && s.shaderId && hasPipeline(s.shaderId)
    );

  const parallelSlots = enabled.filter((s) => s.mode === 'parallel');
  const chainedSlots = enabled.filter((s) => s.mode === 'chained');

  // ── Validate every shader that will run ──
  const seenShaders = new Set<string>();
  for (const slot of enabled) {
    const chain = resolveMultipassChain(slot.shaderId!);
    for (const shaderId of chain) {
      if (seenShaders.has(shaderId)) continue;
      seenShaders.add(shaderId);

      const wgsl = wgslResolver(shaderId);
      if (!wgsl) {
        result.validationResults.push({
          shaderId,
          valid: false,
          errors: ['WGSL source not available'],
        });
        result.valid = false;
        continue;
      }

      const v = validateBindGroup(shaderId, wgsl);
      result.validationResults.push({
        shaderId,
        valid: v.valid,
        errors: v.errors,
      });
      if (!v.valid) {
        result.valid = false;
      }
    }
  }

  // ── Build dispatch plan ──

  // 1. Parallel slots
  for (const slot of parallelSlots) {
    const chain = resolveMultipassChain(slot.shaderId!);
    for (let p = 0; p < chain.length; p++) {
      result.dispatches.push({
        slotIndex: slot.index,
        shaderId: chain[p],
        mode: 'parallel',
        passIndex: p,
        totalPasses: chain.length,
      });
    }
  }

  // Copy parallel result to readTex for chained slots
  if (parallelSlots.length > 0) {
    result.copies.push({
      from: 'writeTex',
      to: 'readTex',
      reason: 'parallel final → readTex for chained consumption',
    });
  }

  // 2. Chained slots
  for (let i = 0; i < chainedSlots.length; i++) {
    const slot = chainedSlots[i];
    const chain = resolveMultipassChain(slot.shaderId!);
    for (let p = 0; p < chain.length; p++) {
      result.dispatches.push({
        slotIndex: slot.index,
        shaderId: chain[p],
        mode: 'chained',
        passIndex: p,
        totalPasses: chain.length,
      });
    }

    // Always copy writeTex→readTex after each chained slot (matches renderer fix)
    result.copies.push({
      from: 'writeTex',
      to: 'readTex',
      reason: `chained slot ${slot.index} output → readTex`,
    });

    // Data texture feedback copies
    result.copies.push({
      from: 'dataTexA',
      to: 'dataTexC',
      reason: 'feedback: dataTexA → dataTexC',
    });
    result.copies.push({
      from: 'dataTexB',
      to: 'dataTexC',
      reason: 'feedback: dataTexB → dataTexC',
    });
  }

  // Warn if parallel slots overwrite each other
  if (parallelSlots.length > 1) {
    result.warnings.push(
      `${parallelSlots.length} parallel slots all write to writeTex; only the last slot's output survives`
    );
  }

  return result;
}

/**
 * Check whether a given orchestration produces a valid final frame.
 * A frame is valid if the blit texture (readTex) receives the last
 * dispatched shader's output.
 */
export function isFrameValid(plan: SlotOrchestration): boolean {
  if (!plan.valid) return false;
  if (plan.dispatches.length === 0) return true; // no-op frame is valid

  // The frame is valid if there is at least one copy from writeTex to readTex,
  // ensuring the final rendered output reaches the blit source texture.
  return plan.copies.some((c) => c.from === 'writeTex' && c.to === 'readTex');
}
