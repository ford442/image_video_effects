/**
 * wgslSave.ts
 *
 * "Save as shader": a WGSL draft → the two files a catalog shader is made of,
 *
 *     public/shaders/<id>.wgsl                       (the draft, prelude-included)
 *     shader_definitions/<category>/<id>.json        (id, name, url, category, params)
 *
 * in the shapes `verify:shader-definitions`, `verify:wgsl-include` /
 * `verify:prelude-migration` and `verify:naga-wasm` accept. Saving writes both
 * into the repository folder the user picks (File System Access API), or
 * downloads them when the browser has no directory picker.
 *
 * Local only: a storage submit waits for the storage_manager upload-token receiver.
 */

import { GRAPH_LAB_RUNTIME_ID } from '../renderer/runtimeGraphs';
import { EXPORT_CATEGORIES, ID_PATTERN } from './graphExport';
import type { DiagnoseResult } from './wgslDiagnostics';
import type { WgslDraft } from './wgslDraft';
import { definitionParams, parseParamHeader } from './wgslParams';

export const WGSL_RUNTIME_PREFIX = 'graphlab-wgsl-';

const PRELUDE_INCLUDE_RE = /^[ \t]*#include[ \t]+"_prelude\.wgsl"[ \t]*$/m;
/** A pasted prelude binding: group 0, bindings 0–12 (13, the history ring, is declared by hand). */
const PASTED_BINDING_RE = /^[ \t]*@group\(\s*0\s*\)\s*@binding\(\s*(\d+)\s*\)/gm;
const PASTED_UNIFORMS_RE = /^[ \t]*struct[ \t]+Uniforms\b/m;

export interface SavedShaderFiles {
  id: string;
  wgsl: string;
  wgslPath: string;
  definition: Record<string, unknown>;
  json: string;
  jsonPath: string;
}

export type SaveBuildResult = { ok: true; files: SavedShaderFiles } | { ok: false; errors: string[] };

/** Strip line comments so a commented-out declaration does not count as pasted. */
const withoutLineComments = (s: string) => s.replace(/\/\/.*$/gm, '');

export function buildShaderFiles(
  draft: WgslDraft,
  context: {
    /** Catalog ids that already exist. */
    existingIds?: ReadonlySet<string>;
    /** The latest diagnose result; saving needs a clean one for this exact text. */
    diagnosis?: DiagnoseResult | null;
  } = {},
): SaveBuildResult {
  const errors: string[] = [];
  const id = draft.id.trim();

  if (!ID_PATTERN.test(id)) {
    errors.push('id must be lowercase letters, digits and hyphens, starting with a letter or digit');
  } else if (id === GRAPH_LAB_RUNTIME_ID || id.startsWith(WGSL_RUNTIME_PREFIX)) {
    errors.push(`id "${id}" is reserved for the Graph Lab's running drafts`);
  } else if (context.existingIds?.has(id)) {
    errors.push(`id "${id}" already exists in the catalog; pick another`);
  }
  if (!draft.name.trim()) errors.push('name is required');
  if (!(EXPORT_CATEGORIES as readonly string[]).includes(draft.category)) {
    errors.push(`category must be one of the shader_definitions folders: ${EXPORT_CATEGORIES.join(', ')}`);
  }

  const code = withoutLineComments(draft.source);
  if (!PRELUDE_INCLUDE_RE.test(code)) {
    errors.push('the shader must #include "_prelude.wgsl" for its 13 bindings (CI rejects pasted headers)');
  }
  const pasted = [...code.matchAll(PASTED_BINDING_RE)].map((m) => Number(m[1])).filter((b) => b <= 12);
  if (pasted.length > 0) {
    errors.push(`@group(0) @binding(${pasted.join(', ')}) come from _prelude.wgsl; delete the pasted copy`);
  }
  if (PASTED_UNIFORMS_RE.test(code)) errors.push('struct Uniforms comes from _prelude.wgsl; delete the pasted copy');

  const diagnosis = context.diagnosis;
  if (!diagnosis || diagnosis.source !== draft.source) {
    errors.push('wait for the diagnostics of the current text');
  } else if (!diagnosis.ok) {
    errors.push(`fix the errors first: ${diagnosis.diagnostics.find((d) => d.severity === 'error')?.message ?? ''}`);
  }

  if (errors.length > 0) return { ok: false, errors };

  const { params } = parseParamHeader(draft.source);
  const definition: Record<string, unknown> = {
    id,
    name: draft.name.trim(),
    url: `shaders/${id}.wgsl`,
    category: draft.category,
    description: draft.description.trim() || 'Authored in the Graph Lab WGSL editor.',
    features: ['graph-lab'],
    tags: ['graph-lab'],
    ...(params.length > 0 ? { params: definitionParams(params) } : {}),
  };
  const wgsl = draft.source.endsWith('\n') ? draft.source : `${draft.source}\n`;
  return {
    ok: true,
    files: {
      id,
      wgsl,
      wgslPath: `public/shaders/${id}.wgsl`,
      definition,
      json: `${JSON.stringify(definition, null, 2)}\n`,
      jsonPath: `shader_definitions/${draft.category}/${id}.json`,
    },
  };
}

// ── Writing the files ────────────────────────────────────────────────────

/** The slice of the File System Access API used here (FileSystemDirectoryHandle). */
export interface DirectoryHandleLike {
  name: string;
  getDirectoryHandle(name: string, options?: { create?: boolean }): Promise<DirectoryHandleLike>;
  getFileHandle(
    name: string,
    options?: { create?: boolean },
  ): Promise<{ createWritable(): Promise<{ write(data: string): Promise<void>; close(): Promise<void> }> }>;
}

export type SaveOutcome =
  | { ok: true; via: 'directory'; paths: string[] }
  | { ok: true; via: 'download'; paths: string[] }
  | { ok: false; message: string; cancelled?: boolean };

const isNotFound = (err: unknown) => (err as { name?: string } | null)?.name === 'NotFoundError';

async function exists(dir: DirectoryHandleLike, parts: string[]): Promise<boolean> {
  let here = dir;
  try {
    for (const p of parts.slice(0, -1)) here = await here.getDirectoryHandle(p);
    await here.getFileHandle(parts[parts.length - 1] ?? '');
    return true;
  } catch (err) {
    if (isNotFound(err) || (err as { name?: string })?.name === 'TypeMismatchError') return false;
    throw err;
  }
}

async function writeAt(root: DirectoryHandleLike, path: string, text: string): Promise<void> {
  const parts = path.split('/');
  let dir = root;
  for (const p of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(p, { create: true });
  const file = await dir.getFileHandle(parts[parts.length - 1] ?? '', { create: true });
  const w = await file.createWritable();
  await w.write(text);
  await w.close();
}

/**
 * Writes both files under `root`, which must be the repository checkout (it has
 * `public/shaders/` and `shader_definitions/`). Refuses to overwrite.
 */
export async function writeShaderFiles(root: DirectoryHandleLike, files: SavedShaderFiles): Promise<SaveOutcome> {
  try {
    const looksLikeRepo = (await root.getDirectoryHandle('public').then((p) => p.getDirectoryHandle('shaders')).then(
      () => true,
      () => false,
    )) && (await root.getDirectoryHandle('shader_definitions').then(() => true, () => false));
    if (!looksLikeRepo) {
      return {
        ok: false,
        message: `"${root.name}" is not the repository root: pick the folder that holds public/shaders and shader_definitions`,
      };
    }
    for (const path of [files.wgslPath, files.jsonPath]) {
      if (await exists(root, path.split('/'))) return { ok: false, message: `${path} already exists; pick another id` };
    }
    await writeAt(root, files.wgslPath, files.wgsl);
    await writeAt(root, files.jsonPath, files.json);
    return { ok: true, via: 'directory', paths: [files.wgslPath, files.jsonPath] };
  } catch (err) {
    return { ok: false, message: `could not write the files: ${(err as Error).message}` };
  }
}

function download(name: string, text: string, type: string): void {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

type PickerWindow = Window & {
  showDirectoryPicker?: (opts?: { id?: string; mode?: 'read' | 'readwrite' }) => Promise<DirectoryHandleLike>;
};

/** Directory picker when the browser has one (Chromium), else two downloads. */
export async function saveShaderFiles(files: SavedShaderFiles, win: PickerWindow = window as PickerWindow): Promise<SaveOutcome> {
  if (typeof win.showDirectoryPicker === 'function') {
    let root: DirectoryHandleLike;
    try {
      root = await win.showDirectoryPicker({ id: 'pixelocity-repo', mode: 'readwrite' });
    } catch (err) {
      if ((err as { name?: string })?.name === 'AbortError') return { ok: false, message: 'Save cancelled.', cancelled: true };
      return { ok: false, message: `could not open the folder: ${(err as Error).message}` };
    }
    return writeShaderFiles(root, files);
  }
  download(`${files.id}.wgsl`, files.wgsl, 'text/plain');
  download(`${files.id}.json`, files.json, 'application/json');
  return { ok: true, via: 'download', paths: [files.wgslPath, files.jsonPath] };
}
