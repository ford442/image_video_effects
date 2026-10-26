/**
 * wgslF16.ts
 *
 * The `shader-f16` variant path (#1512 capability tier 2). A shader opts in with a
 * `// @requires f16` header line and writes its half math in the aliases of
 * public/shaders/_half.wgsl (hf / hv2 / hv3 / hv4), which are f32 as written. On a
 * device granted `shader-f16` the renderer compiles the f16 variant: `enable f16;`
 * first, and those alias lines rewritten to f16 types. Anywhere else (no feature,
 * the WASM backend, naga and the catalog gates) the shader is the f32 fallback,
 * byte for byte.
 */

/** Whole-line header, anywhere before or among the shader's own lines. */
const REQUIRES_F16 = /^[ \t]*\/\/[ \t]*@requires[ \t]+f16\b/m;

/** The alias lines of _half.wgsl and their f16 spelling. */
export const F16_ALIASES: ReadonlyArray<readonly [RegExp, string]> = [
  [/^alias hf = f32;$/m, 'alias hf = f16;'],
  [/^alias hv2 = vec2<f32>;$/m, 'alias hv2 = vec2<f16>;'],
  [/^alias hv3 = vec3<f32>;$/m, 'alias hv3 = vec3<f16>;'],
  [/^alias hv4 = vec4<f32>;$/m, 'alias hv4 = vec4<f16>;'],
];

export function requiresF16(wgsl: string): boolean {
  return REQUIRES_F16.test(wgsl);
}

/**
 * The source to compile for this device: the f16 variant of an opted-in shader when
 * the device has `shader-f16`, otherwise the input unchanged. Expects includes to be
 * expanded already (the alias lines come from _half.wgsl).
 */
export function applyF16Variant(wgsl: string, deviceHasShaderF16: boolean): string {
  if (!deviceHasShaderF16 || !requiresF16(wgsl)) return wgsl;
  let out = wgsl;
  for (const [pattern, f16] of F16_ALIASES) out = out.replace(pattern, f16);
  // Directives come before every declaration; ours goes first, ahead of any `enable subgroups;`.
  return `enable f16;\n${out}`;
}
