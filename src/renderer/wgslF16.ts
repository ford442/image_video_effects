/**
 * wgslF16.ts
 *
 * The `shader-f16` variant path (#1512 Part A). A shader opts in with a
 * `// @requires f16` header line and writes its half-precision math against
 * the `hf` / `hf2` / `hf3` / `hf4` aliases from `#include "_half.wgsl"`:
 *
 *     // @requires f16
 *     #include "_prelude.wgsl"
 *     #include "_half.wgsl"
 *
 * As shipped, those aliases are f32, so the file is plain f32 WGSL: it compiles
 * on every device and passes the naga gates (whose validator has no FLOAT16
 * capability). On a device with `shader-f16` the host rewrites only the alias
 * declarations to f16 and prepends `enable f16;` — the half variant. Abstract
 * float literals (`0.5`, no suffix) fit both, so the body needs no edits.
 *
 * Fallback: without the feature, or when the half variant fails to compile,
 * the source is used unchanged (f32).
 */

/** Whole-line header that opts a shader into the half variant. */
export const REQUIRES_F16_RE = /^[ \t]*\/\/[ \t]*@requires[ \t]+f16\b.*$/m;

/** The alias declarations `_half.wgsl` owns: `alias hf = f32;` … `alias hf4 = vec4<f32>;`. */
const HALF_ALIAS_RE = /^([ \t]*alias[ \t]+(hf[234]?)[ \t]*=[ \t]*)(f32|vec([234])<f32>|vec([234])f)([ \t]*;)/gm;

export function requiresF16(wgsl: string): boolean {
  return REQUIRES_F16_RE.test(wgsl);
}

/** True when the source already starts (after comments / blank lines) with `enable f16;`. */
function hasEnableF16(wgsl: string): boolean {
  return /^\s*(?:\/\/[^\n]*\n\s*)*enable[ \t]+f16[ \t]*;/.test(wgsl) || /^[ \t]*enable[ \t]+f16[ \t]*;/m.test(wgsl);
}

/**
 * The half variant of an opted-in shader: alias declarations retargeted to f16
 * and `enable f16;` first. Returns the source unchanged when it did not opt in.
 */
export function toF16Variant(wgsl: string): string {
  if (!requiresF16(wgsl)) return wgsl;
  const retargeted = wgsl.replace(HALF_ALIAS_RE, (_m, head: string, _name: string, type: string, n1?: string, n2?: string, tail?: string) => {
    const n = n1 ?? n2;
    const half = type === 'f32' ? 'f16' : `vec${n}<f16>`;
    return `${head}${half}${tail ?? ';'}`;
  });
  return hasEnableF16(retargeted) ? retargeted : `enable f16;\n${retargeted}`;
}

export type F16Choice = 'f16' | 'f32' | 'not-requested';

/** Which variant to compile first for a shader on a device. */
export function chooseF16Variant(wgsl: string, deviceHasShaderF16: boolean): { source: string; variant: F16Choice } {
  if (!requiresF16(wgsl)) return { source: wgsl, variant: 'not-requested' };
  return deviceHasShaderF16 ? { source: toF16Variant(wgsl), variant: 'f16' } : { source: wgsl, variant: 'f32' };
}
