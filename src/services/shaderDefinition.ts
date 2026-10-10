// Runtime reader for shader definitions as shipped in public/shader-lists/*.json.
// Types come from the schema (src/types/ShaderDefinition.ts); the full structural check runs at
// build time in scripts/validate_shader_definitions.mjs, so this only narrows what the app uses
// and applies slider defaults. It deliberately does not import ajv (main bundle budget).
import type { ShaderDefinition, ShaderDefinitionParam } from '../types/ShaderDefinition';

export type { ShaderDefinition, ShaderDefinitionParam };

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

const finite = (v: unknown, fallback: number): number =>
  typeof v === 'number' && Number.isFinite(v) ? v : fallback;

const str = (v: unknown): string | undefined => (typeof v === 'string' && v ? v : undefined);

/** One slider. Missing fields get the same defaults the sliders have always had. */
export function parseShaderParam(raw: unknown, index: number): ShaderDefinitionParam {
  const p = isRecord(raw) ? raw : {};
  const name = str(p.name);
  const param: ShaderDefinitionParam = {
    id: str(p.id) ?? name ?? `param${index + 1}`,
    name: name ?? `Parameter ${index + 1}`,
    default: finite(p.default, 0.5),
    min: finite(p.min, 0),
    max: finite(p.max, 1),
  };
  if (typeof p.step === 'number') param.step = p.step;
  if (Array.isArray(p.labels)) param.labels = p.labels.filter((l): l is string => typeof l === 'string');
  if (str(p.mapping)) param.mapping = p.mapping as string;
  if (typeof p.audio === 'string' || isRecord(p.audio)) param.audio = p.audio as ShaderDefinitionParam['audio'];
  if (str(p.description)) param.description = p.description as string;
  return param;
}

export function parseShaderParams(raw: unknown): ShaderDefinitionParam[] {
  return Array.isArray(raw) ? raw.map((p, i) => parseShaderParam(p, i)) : [];
}

/** One list entry, or null when it has no usable id. */
export function parseShaderDefinition(raw: unknown): ShaderDefinition | null {
  if (!isRecord(raw)) return null;
  const id = str(raw.id);
  if (!id) return null;
  return {
    ...(raw as unknown as ShaderDefinition),
    id,
    name: str(raw.name) ?? id,
    url: str(raw.url) ?? `shaders/${id}.wgsl`,
    params: parseShaderParams(raw.params),
  };
}
