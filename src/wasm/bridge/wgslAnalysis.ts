/**
 * The one static WGSL analysis both backends use: the dispatch size of the entry
 * point and which optional feedback bindings a shader touches. The TS renderer
 * reads it through src/renderer/ShaderCompilation.ts; the WASM bridge sends the
 * result with loadShader, so C++ never parses WGSL (it only refuses a surviving
 * #include). Dependency-free on purpose: the bridge is emitted module by module.
 */
import { SHADER_USAGE_BINDINGS, SHADER_USAGE_BITS, WORKGROUP_UNPARSED_FALLBACK } from './_contracts.js';

export interface WorkgroupSize {
  x: number;
  y: number;
}

/** Which optional per-frame copies a shader needs (binding_table.json shaderUsageFlags). */
export interface ShaderBindingUsage {
  writesDataA: boolean;
  writesDataB: boolean;
  readsDataC: boolean;
  usesHistory: boolean;
  writesDepth: boolean;
}

/** Drop // and (nested) /* *\/ comments so a commented-out attribute never wins. */
export function stripWgslComments(wgsl: string): string {
  let out = '';
  let depth = 0;
  for (let i = 0; i < wgsl.length; i++) {
    const c = wgsl[i];
    const n = wgsl[i + 1];
    if (depth > 0) {
      if (c === '/' && n === '*') { depth++; i++; }
      else if (c === '*' && n === '/') { depth--; i++; }
      else if (c === '\n') out += '\n';
      continue;
    }
    if (c === '/' && n === '*') { depth = 1; i++; continue; }
    if (c === '/' && n === '/') {
      while (i < wgsl.length && wgsl[i] !== '\n') i++;
      out += '\n';
      continue;
    }
    out += c;
  }
  return out;
}

const INT_LITERAL = /^(0[xX][0-9a-fA-F]+|\d+)[iu]?$/;
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;

/**
 * Resolve one @workgroup_size argument: an integer literal (with an optional
 * i/u suffix) or a module-scope `const` / `override` with an integer
 * initializer, followed through other constants. Anything else (arithmetic,
 * an override with no initializer) is unresolved.
 */
function resolveWorkgroupDim(expr: string, src: string, depth = 0): number | null {
  const e = expr.trim().replace(/^\((.*)\)$/, '$1').trim();
  if (INT_LITERAL.test(e)) {
    const n = Number.parseInt(e.replace(/[iu]$/, ''), e.startsWith('0x') || e.startsWith('0X') ? 16 : 10);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  if (!IDENT.test(e) || depth > 8) return null;
  const decl = new RegExp(`\\b(?:const|override)\\s+${e}\\s*(?::\\s*[A-Za-z0-9_<>]+\\s*)?=\\s*([^;]+);`).exec(src);
  return decl ? resolveWorkgroupDim(decl[1]!, src, depth + 1) : null;
}

/**
 * @workgroup_size of `entryPoint` (the only entry the renderers dispatch is
 * `main`; a 1D helper kernel declared first must not win), else of the first
 * compute entry. A missing y is 1. Returns null when nothing resolves to
 * positive integers.
 */
export function resolveWorkgroupSize(wgslSource: string, entryPoint = 'main'): WorkgroupSize | null {
  const src = stripWgslComments(wgslSource);
  const attr = /@workgroup_size\s*\(([^)]*)\)\s*(?:@[A-Za-z_]\w*(?:\s*\([^)]*\))?\s*)*fn\s+([A-Za-z_]\w*)/g;
  let chosen: string | null = null;
  let first: string | null = null;
  let m: RegExpExecArray | null;
  while ((m = attr.exec(src)) !== null) {
    first ??= m[1]!;
    if (m[2] === entryPoint) {
      chosen = m[1]!;
      break;
    }
  }
  const args = chosen ?? first;
  if (args === null) return null;
  const parts = args.split(',').map((p) => p.trim()).filter((p) => p.length > 0);
  if (parts.length === 0 || parts.length > 3) return null;
  const x = resolveWorkgroupDim(parts[0]!, src);
  const y = parts.length > 1 ? resolveWorkgroupDim(parts[1]!, src) : 1;
  return x !== null && y !== null ? { x, y } : null;
}

/** resolveWorkgroupSize, or the contract fallback (workgroup_dispatch.json unparsedFallback). */
export function parseWorkgroupSize(
  wgslSource: string,
  entryPoint = 'main',
  fallback: WorkgroupSize = WORKGROUP_UNPARSED_FALLBACK,
): WorkgroupSize {
  return resolveWorkgroupSize(wgslSource, entryPoint) ?? { x: fallback.x, y: fallback.y };
}

function bindingVarName(wgsl: string, binding: number): string | null {
  const m = wgsl.match(
    new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)\\s*var(?:<[^>]*>)?\\s+([A-Za-z_][A-Za-z0-9_]*)`),
  );
  return m?.[1] ?? null;
}

function usedBeyondDeclaration(wgsl: string, binding: number): boolean {
  const hasBinding = new RegExp(`@group\\(0\\)\\s*@binding\\(${binding}\\)`).test(wgsl);
  if (!hasBinding) return false;
  const name = bindingVarName(wgsl, binding);
  // Declared but unparseable name: assume used (conservative).
  if (!name) return true;
  const refs = wgsl.match(new RegExp(`\\b${name}\\b`, 'g'));
  return (refs?.length ?? 0) > 1;
}

/**
 * Statically determine which feedback resources a shader uses, by variable
 * name bound at each binding slot (names may be aliased, so the declaration
 * is parsed rather than assuming canonical names). Errs on the side of
 * "used" whenever the source is ambiguous.
 */
export function analyzeShaderBindings(wgsl: string): ShaderBindingUsage {
  return {
    writesDataA: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDataA),
    writesDataB: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDataB),
    readsDataC: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.readsDataC),
    usesHistory: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.usesHistory),
    writesDepth: usedBeyondDeclaration(wgsl, SHADER_USAGE_BINDINGS.writesDepth),
  };
}

/** loadShader's bindingUsage argument. */
export function shaderUsageBits(usage: ShaderBindingUsage): number {
  let bits = 0;
  for (const key of Object.keys(SHADER_USAGE_BITS) as (keyof typeof SHADER_USAGE_BITS)[]) {
    if (usage[key]) bits |= SHADER_USAGE_BITS[key];
  }
  return bits;
}
