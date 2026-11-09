/**
 * wgslParams.ts
 *
 * The params header of a Graph Lab WGSL draft: comment pragmas, one per slider,
 *
 *     // @param speed 0 2 0.5 Flow speed
 *     // @param hue   0 1 0.1
 *
 * `name min max default [label…]`, in order, map to p1–p4 (`u.zoom_params.x…w`).
 * Comment pragmas rather than a WGSL `const` block: they need no naga round-trip,
 * cost nothing at runtime, and survive a shader that does not validate yet, so the
 * sliders keep working while the code is broken.
 *
 * The parsed params are the shader definition's `params` (shader_definition.schema.json
 * `param`), so "Save as shader" writes them as they are.
 */

/** zoom_params lanes in slider order (p1..p4). */
export const PARAM_LANES = ['x', 'y', 'z', 'w'] as const;
export const MAX_PARAMS = PARAM_LANES.length;

export interface DraftParam {
  id: string;
  name: string;
  min: number;
  max: number;
  default: number;
  step: number;
  /** `zoom_params.x` … `zoom_params.w`. */
  mapping: string;
  /** 1-based source line of the pragma. */
  line: number;
}

export interface ParamProblem {
  line: number;
  severity: 'error' | 'warning';
  message: string;
}

export interface ParamHeader {
  params: DraftParam[];
  problems: ParamProblem[];
}

const PRAGMA_RE = /^\s*\/\/\s*@param\b(.*)$/;
const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** `flowSpeed` / `flow_speed` → `Flow Speed`. */
export function humanizeParamName(name: string): string {
  const words = name
    .replace(/_+/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  return words.map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ') || name;
}

/** A slider step that gives ~100 positions, rounded to a power of ten. */
function stepFor(min: number, max: number): number {
  const span = max - min;
  if (!(span > 0)) return 0.01;
  return 10 ** Math.floor(Math.log10(span / 100));
}

/** Parses every `// @param` line of `source`. Pure; never throws. */
export function parseParamHeader(source: string): ParamHeader {
  const params: DraftParam[] = [];
  const problems: ParamProblem[] = [];
  const seen = new Set<string>();

  source.split('\n').forEach((text, i) => {
    const line = i + 1;
    const m = PRAGMA_RE.exec(text);
    if (!m) return;
    const parts = (m[1] ?? '').trim().split(/\s+/).filter(Boolean);
    const [name, minS, maxS, defS, ...label] = parts;
    const usage = 'expected `// @param name min max default [label]`';
    if (!name || defS === undefined) {
      problems.push({ line, severity: 'error', message: `@param: ${usage}` });
      return;
    }
    if (!NAME_RE.test(name)) {
      problems.push({ line, severity: 'error', message: `@param: "${name}" is not an identifier` });
      return;
    }
    const [min, max, def] = [minS, maxS, defS].map(Number) as [number, number, number];
    if (![min, max, def].every(Number.isFinite)) {
      problems.push({ line, severity: 'error', message: `@param ${name}: min, max and default must be numbers (${usage})` });
      return;
    }
    if (!(min < max)) {
      problems.push({ line, severity: 'error', message: `@param ${name}: min ${min} must be below max ${max}` });
      return;
    }
    if (def < min || def > max) {
      problems.push({ line, severity: 'error', message: `@param ${name}: default ${def} is outside [${min}, ${max}]` });
      return;
    }
    if (seen.has(name)) {
      problems.push({ line, severity: 'error', message: `@param ${name}: declared twice` });
      return;
    }
    if (params.length >= MAX_PARAMS) {
      problems.push({
        line,
        severity: 'error',
        message: `@param ${name}: only ${MAX_PARAMS} sliders exist (p1–p4 = u.zoom_params.xyzw)`,
      });
      return;
    }
    seen.add(name);
    const lane = PARAM_LANES[params.length] ?? 'x';
    params.push({
      id: name,
      name: label.length > 0 ? label.join(' ') : humanizeParamName(name),
      min,
      max,
      default: def,
      step: stepFor(min, max),
      mapping: `zoom_params.${lane}`,
      line,
    });
  });

  return { params, problems };
}

/** p1..p4 for `setSlotParams`: each param's value (or default), 0 for unused lanes. */
export function slotParamValues(params: readonly DraftParam[], values: Readonly<Record<string, number>> = {}): [number, number, number, number] {
  const out: [number, number, number, number] = [0, 0, 0, 0];
  params.slice(0, MAX_PARAMS).forEach((p, i) => {
    const v = values[p.id];
    out[i] = typeof v === 'number' && Number.isFinite(v) ? Math.min(p.max, Math.max(p.min, v)) : p.default;
  });
  return out;
}

/** The definition JSON's `params` (no editor-only fields). */
export function definitionParams(params: readonly DraftParam[]): Array<Record<string, unknown>> {
  return params.map((p) => ({
    id: p.id,
    name: p.name,
    default: p.default,
    min: p.min,
    max: p.max,
    step: p.step,
    mapping: p.mapping,
  }));
}
