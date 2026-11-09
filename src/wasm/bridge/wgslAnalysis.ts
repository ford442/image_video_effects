/**
 * The one static WGSL analysis both backends use: the dispatch size of the
 * entry point and which optional feedback bindings a shader touches.
 *
 * The TS renderer reads it through src/renderer/ShaderCompilation.ts. The WASM
 * bridge sends the result with loadShader/reloadShader (workgroupX, workgroupY,
 * usageBits), so C++ no longer keeps its own copy of these heuristics; it only
 * refuses a surviving #include.
 *
 * Dependency-free on purpose: the bridge is emitted module by module
 * (scripts/emit-wasm-bridge.mjs) without bundling.
 */
import {
  SHADER_USAGE_BINDINGS,
  SHADER_USAGE_BITS,
  WORKGROUP_UNPARSED_FALLBACK,
  type ShaderUsageFlag,
} from './_contracts.js';

export interface WorkgroupSize {
  x: number;
  y: number;
}

/** Which optional per-frame copies a shader needs (bind_group0.json shaderUsageFlags). */
export type ShaderBindingUsage = Record<ShaderUsageFlag, boolean>;

const USAGE_FLAGS = Object.keys(SHADER_USAGE_BITS) as ShaderUsageFlag[];

/** Usage assumed for a shader that was never analyzed: every copy runs. */
export const CONSERVATIVE_BINDING_USAGE: Readonly<ShaderBindingUsage> = Object.freeze(
  Object.fromEntries(USAGE_FLAGS.map((f) => [f, true])) as ShaderBindingUsage,
);

/**
 * Resolve @workgroup_size for `entryPoint`. The renderers only dispatch `main`,
 * so a 1D helper kernel declared earlier (`@workgroup_size(64, 1, 1) fn
 * update_boids`) must not win. Falls back to the first compute entry point,
 * then to any @workgroup_size after @compute, then to the contract fallback.
 * `parsed` is false only in the last case.
 */
export function resolveWorkgroupSize(
  wgslSource: string,
  entryPoint = 'main',
): WorkgroupSize & { parsed: boolean } {
  const entryRe =
    /@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)[^)]*\)\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)/g;
  let first: RegExpExecArray | null = null;
  let m: RegExpExecArray | null;
  while ((m = entryRe.exec(wgslSource)) !== null) {
    if (!first) first = m;
    if (m[3] === entryPoint) return { x: Number(m[1]), y: Number(m[2]), parsed: true };
  }
  if (first) return { x: Number(first[1]), y: Number(first[2]), parsed: true };

  const computeIdx = wgslSource.indexOf('@compute');
  if (computeIdx !== -1) {
    const m2 = wgslSource.slice(computeIdx).match(/@workgroup_size\(\s*(\d+)\s*,\s*(\d+)/);
    if (m2) return { x: Number(m2[1]), y: Number(m2[2]), parsed: true };
  }
  return { x: WORKGROUP_UNPARSED_FALLBACK.x, y: WORKGROUP_UNPARSED_FALLBACK.y, parsed: false };
}

function bindingVarName(wgsl: string, binding: number): string | null {
  const m = wgsl.match(
    new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)\\s*var(?:<[^>]*>)?\\s+([A-Za-z_][A-Za-z0-9_]*)`),
  );
  return m?.[1] ?? null;
}

function usedBeyondDeclaration(wgsl: string, binding: number): boolean {
  if (!new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)`).test(wgsl)) return false;
  const name = bindingVarName(wgsl, binding);
  // Declared but the name did not parse: assume used (conservative).
  if (!name) return true;
  return (wgsl.match(new RegExp(`\\b${name}\\b`, 'g'))?.length ?? 0) > 1;
}

/**
 * Which feedback resources a shader uses, found by the variable name bound at
 * each slot (names may be aliased, so the declaration is parsed rather than
 * assuming canonical names). Errs towards "used" when the source is ambiguous.
 */
export function analyzeShaderBindings(wgsl: string): ShaderBindingUsage {
  return Object.fromEntries(
    USAGE_FLAGS.map((f) => [f, usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS[f])]),
  ) as ShaderBindingUsage;
}

/** Pack a usage record into loadShader's usageBits. */
export function packUsageBits(usage: ShaderBindingUsage): number {
  let bits = 0;
  for (const f of USAGE_FLAGS) if (usage[f]) bits |= SHADER_USAGE_BITS[f];
  return bits;
}

/** Inverse of packUsageBits (unknown bits are ignored). */
export function unpackUsageBits(bits: number): ShaderBindingUsage {
  return Object.fromEntries(USAGE_FLAGS.map((f) => [f, (bits & SHADER_USAGE_BITS[f]) !== 0])) as ShaderBindingUsage;
}
