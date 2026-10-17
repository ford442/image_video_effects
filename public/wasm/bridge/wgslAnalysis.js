// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { SHADER_USAGE_BINDINGS, SHADER_USAGE_BITS, WORKGROUP_UNPARSED_FALLBACK } from "./_contracts.js";
function stripWgslComments(wgsl) {
  let out = "";
  let depth = 0;
  for (let i = 0; i < wgsl.length; i++) {
    const c = wgsl[i];
    const n = wgsl[i + 1];
    if (depth > 0) {
      if (c === "/" && n === "*") {
        depth++;
        i++;
      } else if (c === "*" && n === "/") {
        depth--;
        i++;
      } else if (c === "\n") out += "\n";
      continue;
    }
    if (c === "/" && n === "*") {
      depth = 1;
      i++;
      continue;
    }
    if (c === "/" && n === "/") {
      while (i < wgsl.length && wgsl[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    out += c;
  }
  return out;
}
const INT_LITERAL = /^(0[xX][0-9a-fA-F]+|\d+)[iu]?$/;
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;
function resolveWorkgroupDim(expr, src, depth = 0) {
  const e = expr.trim().replace(/^\((.*)\)$/, "$1").trim();
  if (INT_LITERAL.test(e)) {
    const n = Number.parseInt(e.replace(/[iu]$/, ""), e.startsWith("0x") || e.startsWith("0X") ? 16 : 10);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  if (!IDENT.test(e) || depth > 8) return null;
  const decl = new RegExp(`\\b(?:const|override)\\s+${e}\\s*(?::\\s*[A-Za-z0-9_<>]+\\s*)?=\\s*([^;]+);`).exec(src);
  return decl ? resolveWorkgroupDim(decl[1], src, depth + 1) : null;
}
function resolveWorkgroupSize(wgslSource, entryPoint = "main") {
  const src = stripWgslComments(wgslSource);
  const attr = /@workgroup_size\s*\(([^)]*)\)\s*(?:@[A-Za-z_]\w*(?:\s*\([^)]*\))?\s*)*fn\s+([A-Za-z_]\w*)/g;
  let chosen = null;
  let first = null;
  let m;
  while ((m = attr.exec(src)) !== null) {
    first ??= m[1];
    if (m[2] === entryPoint) {
      chosen = m[1];
      break;
    }
  }
  const args = chosen ?? first;
  if (args === null) return null;
  const parts = args.split(",").map((p) => p.trim()).filter((p) => p.length > 0);
  if (parts.length === 0 || parts.length > 3) return null;
  const x = resolveWorkgroupDim(parts[0], src);
  const y = parts.length > 1 ? resolveWorkgroupDim(parts[1], src) : 1;
  return x !== null && y !== null ? { x, y } : null;
}
function parseWorkgroupSize(wgslSource, entryPoint = "main", fallback = WORKGROUP_UNPARSED_FALLBACK) {
  return resolveWorkgroupSize(wgslSource, entryPoint) ?? { x: fallback.x, y: fallback.y };
}
function bindingVarName(wgsl, binding) {
  const m = wgsl.match(
    new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)\\s*var(?:<[^>]*>)?\\s+([A-Za-z_][A-Za-z0-9_]*)`)
  );
  return m?.[1] ?? null;
}
function usedBeyondDeclaration(wgsl, binding) {
  const hasBinding = new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)`).test(wgsl);
  if (!hasBinding) return false;
  const name = bindingVarName(wgsl, binding);
  if (!name) return true;
  const refs = wgsl.match(new RegExp(`\\b${name}\\b`, "g"));
  return (refs?.length ?? 0) > 1;
}
function analyzeShaderBindings(wgsl) {
  return {
    writesDataA: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDataA),
    writesDataB: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDataB),
    readsDataC: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.readsDataC),
    usesHistory: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.usesHistory),
    writesDepth: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDepth)
  };
}
function shaderUsageBits(usage) {
  let bits = 0;
  for (const key of Object.keys(SHADER_USAGE_BITS)) {
    if (usage[key]) bits |= SHADER_USAGE_BITS[key];
  }
  return bits;
}
export {
  analyzeShaderBindings,
  parseWorkgroupSize,
  resolveWorkgroupSize,
  shaderUsageBits,
  stripWgslComments
};
