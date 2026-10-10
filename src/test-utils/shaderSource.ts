/**
 * Test helpers that read catalog shaders the way the runtime sees them: with
 * `#include` expanded. A shader that gets its bindings from _prelude.wgsl has
 * none in its raw text, so binding validation must run on the expanded source.
 *
 * Lives outside __tests__/ because CRA would otherwise run it as an empty suite.
 */
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import { expandWgslIncludes } from '../wasm/bridge/wgslInclude';

export const SHADER_DIR = resolve(__dirname, '../../public/shaders');

async function readLibrary(name: string): Promise<string | null> {
  const file = resolve(SHADER_DIR, name);
  return existsSync(file) ? readFileSync(file, 'utf8') : null;
}

/** Raw text of public/shaders/<id>.wgsl, or null when the file does not exist. */
export function readRawShader(id: string): string | null {
  const file = resolve(SHADER_DIR, `${id}.wgsl`);
  return existsSync(file) ? readFileSync(file, 'utf8') : null;
}

/** Expands `#include` in `source`, resolving libraries from public/shaders. */
export function expandShaderSource(source: string, entry = '<entry>'): Promise<string> {
  return expandWgslIncludes(source, readLibrary, entry);
}

/** public/shaders/<id>.wgsl with includes expanded, or null when the file does not exist. */
export async function readExpandedShader(id: string): Promise<string | null> {
  const raw = readRawShader(id);
  return raw === null ? null : expandShaderSource(raw, `${id}.wgsl`);
}
