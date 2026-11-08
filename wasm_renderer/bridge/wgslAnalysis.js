// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import {
  SHADER_USAGE_BINDINGS,
  SHADER_USAGE_BITS,
  WORKGROUP_UNPARSED_FALLBACK
} from "./_contracts.js";
const USAGE_FLAGS = Object.keys(SHADER_USAGE_BITS);
const CONSERVATIVE_BINDING_USAGE = Object.freeze(
  Object.fromEntries(USAGE_FLAGS.map((f) => [f, true]))
);
function resolveWorkgroupSize(wgslSource, entryPoint = "main") {
  const entryRe = /@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)[^)]*\)\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)/g;
  let first = null;
  let m;
  while ((m = entryRe.exec(wgslSource)) !== null) {
    if (!first) first = m;
    if (m[3] === entryPoint) return { x: Number(m[1]), y: Number(m[2]), parsed: true };
  }
  if (first) return { x: Number(first[1]), y: Number(first[2]), parsed: true };
  const computeIdx = wgslSource.indexOf("@compute");
  if (computeIdx !== -1) {
    const m2 = wgslSource.slice(computeIdx).match(/@workgroup_size\(\s*(\d+)\s*,\s*(\d+)/);
    if (m2) return { x: Number(m2[1]), y: Number(m2[2]), parsed: true };
  }
  return { x: WORKGROUP_UNPARSED_FALLBACK.x, y: WORKGROUP_UNPARSED_FALLBACK.y, parsed: false };
}
function bindingVarName(wgsl, binding) {
  const m = wgsl.match(
    new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)\\s*var(?:<[^>]*>)?\\s+([A-Za-z_][A-Za-z0-9_]*)`)
  );
  return m?.[1] ?? null;
}
function usedBeyondDeclaration(wgsl, binding) {
  if (!new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)`).test(wgsl)) return false;
  const name = bindingVarName(wgsl, binding);
  if (!name) return true;
  return (wgsl.match(new RegExp(`\\b${name}\\b`, "g"))?.length ?? 0) > 1;
}
function analyzeShaderBindings(wgsl) {
  return Object.fromEntries(
    USAGE_FLAGS.map((f) => [f, usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS[f])])
  );
}
function packUsageBits(usage) {
  let bits = 0;
  for (const f of USAGE_FLAGS) if (usage[f]) bits |= SHADER_USAGE_BITS[f];
  return bits;
}
function unpackUsageBits(bits) {
  return Object.fromEntries(USAGE_FLAGS.map((f) => [f, (bits & SHADER_USAGE_BITS[f]) !== 0]));
}
export {
  CONSERVATIVE_BINDING_USAGE,
  analyzeShaderBindings,
  packUsageBits,
  resolveWorkgroupSize,
  unpackUsageBits
};
