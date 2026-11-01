/**
 * wgslDraft.ts
 *
 * Graph Lab's inline WGSL drafts: one per slot, autosaved to localStorage
 * (`graphlab.wgsl.v1`). They are not part of project files (Part A owns that
 * schema; drafts there are a follow-up once project files v3 land). Text undo /
 * redo is the editor's own history; the stored draft is the present text.
 */

import { EXPORT_CATEGORIES } from './graphExport';

export type ExportCategory = (typeof EXPORT_CATEGORIES)[number];

export interface WgslDraft {
  version: 1;
  /** Catalog id "Save as shader" writes (`<id>.wgsl`, `shader_definitions/<category>/<id>.json`). */
  id: string;
  name: string;
  category: ExportCategory;
  description: string;
  /** User WGSL, with its `#include` lines and `// @param` header. */
  source: string;
}

export const WGSL_DRAFTS_STORAGE_KEY = 'graphlab.wgsl.v1';
export const WGSL_DRAFT_VERSION = 1;

/** A module that validates, renders the input with a warp and uses all three params. */
export const WGSL_TEMPLATE = `// Graph Lab WGSL draft. Each "// @param name min max default [label]" line
// below is a slider, in order p1..p4 = u.zoom_params.x..w.
// @param speed 0 4 1 Speed
// @param warp 0 1 0.3 Warp
// @param tint 0 1 0.5 Warm tint
#include "_prelude.wgsl"

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let coord = vec2<i32>(gid.xy);
  if (any(coord >= vec2<i32>(dims))) {
    return;
  }

  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let t = u.config.x * u.zoom_params.x;
  let offset = vec2<f32>(sin(uv.y * 12.0 + t), cos(uv.x * 12.0 + t)) * 0.02 * u.zoom_params.y;
  let src = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
  let tint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.7, 0.45), u.zoom_params.z);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(src.rgb * tint, src.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
`;

export function newWgslDraft(slot: number, source: string = WGSL_TEMPLATE): WgslDraft {
  return {
    version: 1,
    id: `lab-shader-${slot + 1}`,
    name: `Lab shader ${slot + 1}`,
    category: 'image',
    description: '',
    source,
  };
}

const isCategory = (c: unknown): c is ExportCategory =>
  typeof c === 'string' && (EXPORT_CATEGORIES as readonly string[]).includes(c);

/** A stored draft, or null when it is not one (a newer version is refused, not truncated). */
export function upgradeWgslDraft(raw: unknown): WgslDraft | null {
  if (!raw || typeof raw !== 'object') return null;
  const d = raw as Record<string, unknown>;
  if (d.version !== WGSL_DRAFT_VERSION || typeof d.source !== 'string' || typeof d.id !== 'string') return null;
  return {
    version: 1,
    id: d.id,
    name: typeof d.name === 'string' ? d.name : d.id,
    category: isCategory(d.category) ? d.category : 'image',
    description: typeof d.description === 'string' ? d.description : '',
    source: d.source,
  };
}

export type WgslDraftsBySlot = Readonly<Record<number, WgslDraft>>;

export function loadWgslDrafts(storage: Pick<Storage, 'getItem'> | null = safeStorage()): WgslDraftsBySlot {
  try {
    const raw = storage?.getItem(WGSL_DRAFTS_STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as { version?: unknown; slots?: Record<string, unknown> };
    if (parsed.version !== WGSL_DRAFT_VERSION || !parsed.slots) return {};
    const out: Record<number, WgslDraft> = {};
    for (const [slot, value] of Object.entries(parsed.slots)) {
      const draft = upgradeWgslDraft(value);
      const index = Number(slot);
      if (draft && Number.isInteger(index) && index >= 0) out[index] = draft;
    }
    return out;
  } catch {
    return {};
  }
}

export function storeWgslDrafts(drafts: WgslDraftsBySlot, storage: Pick<Storage, 'setItem'> | null = safeStorage()): void {
  try {
    storage?.setItem(WGSL_DRAFTS_STORAGE_KEY, JSON.stringify({ version: WGSL_DRAFT_VERSION, slots: drafts }));
  } catch {
    // Private window or quota: the draft simply is not remembered.
  }
}

function safeStorage(): Storage | null {
  try {
    return typeof window !== 'undefined' ? window.localStorage : null;
  } catch {
    return null;
  }
}
