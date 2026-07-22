/**
 * Shader listing and loading against storage_manager /api/shaders endpoints.
 */

import { SHADER_FILES_BASE_URL } from '../../config/appConfig';
import {
  encodeResourcePath,
  fetchJson,
  fetchText,
  resolveStaticUrl,
  unwrapListResponse,
} from './http';
import type {
  EffectConfigRecord,
  LoadShaderResult,
  ShaderItem,
  ShaderListQuery,
  StorageClientConfig,
} from './types';

function shaderStem(filename: string): string {
  return filename.replace(/\.json$/, '');
}

function attachShaderUrls(shaders: ShaderItem[], shaderFilesBaseUrl: string): ShaderItem[] {
  const base = shaderFilesBaseUrl.replace(/\/$/, '');
  return shaders.map(shader => {
    const wgslFilename = shader.filename.replace(/\.json$/, '.wgsl');
    const normalized: ShaderItem = { ...shader };
    normalized.url = `${base}/shaders/${wgslFilename}`;
    // Live API uses `rating`; some clients still read `stars`.
    if (normalized.rating === null || normalized.rating === undefined) {
      normalized.rating = normalized.stars ?? null;
    }
    if (normalized.stars === undefined || normalized.stars === null) {
      normalized.stars = typeof normalized.rating === 'number' ? normalized.rating : undefined;
    }
    return normalized;
  });
}

function buildShaderListUrl(apiUrl: string, query?: ShaderListQuery): string {
  const params = new URLSearchParams();
  if (query?.category) params.set('category', query.category);
  if (query?.minStars !== undefined) params.set('min_stars', String(query.minStars));
  if (query?.sortBy) params.set('sort_by', query.sortBy);
  const qs = params.toString();
  return `${apiUrl}/api/shaders${qs ? `?${qs}` : ''}`;
}

export async function listShaders(
  config: StorageClientConfig,
  query?: ShaderListQuery
): Promise<ShaderItem[]> {
  const responseData = await fetchJson<ShaderItem[] | { shaders: ShaderItem[] }>(
    buildShaderListUrl(config.apiUrl, query)
  );
  const shaders = unwrapListResponse(responseData, 'shaders');
  return attachShaderUrls(shaders, config.shaderFilesBaseUrl);
}

export async function listShadersWithErrors(config: StorageClientConfig): Promise<ShaderItem[]> {
  const shaders = await listShaders(config);
  return shaders.filter(s => s.has_errors === true || (s.stars ?? 0) === 0);
}

export async function getShaderMeta(config: StorageClientConfig, shaderId: string): Promise<ShaderItem> {
  const encoded = encodeResourcePath(shaderId.replace(/\.json$/, ''));
  const item = await fetchJson<ShaderItem>(`${config.apiUrl}/api/shaders/${encoded}`);
  return attachShaderUrls([item], config.shaderFilesBaseUrl)[0];
}

export async function loadShader(
  config: StorageClientConfig,
  filename: string
): Promise<LoadShaderResult> {
  const stem = shaderStem(filename);
  const encoded = encodeResourcePath(stem);

  try {
    const result = await fetchJson<LoadShaderResult>(`${config.apiUrl}/api/shaders/${encoded}`);
    return result;
  } catch {
    // Fallback: static metadata JSON + CDN WGSL
    const data = await fetchJson<ShaderItem>(
      resolveStaticUrl(config.staticUrl, `image-effects/shaders/${filename}`)
    );

    let content = '';
    if (data.filename) {
      try {
        const wgslFilename = data.filename.replace(/\.json$/, '.wgsl');
        const wgslBase = config.shaderFilesBaseUrl || SHADER_FILES_BASE_URL;
        content = await fetchText(
          `${wgslBase.replace(/\/$/, '')}/shaders/${wgslFilename}`
        );
      } catch {
        // Caller handles empty content
      }
    }

    return {
      id: stem,
      content,
      type: data.format || 'wgsl',
      data,
    };
  }
}

export async function loadShaderWgsl(config: StorageClientConfig, shaderId: string): Promise<string> {
  const encoded = encodeResourcePath(shaderId.replace(/\.json$/, ''));
  return fetchText(`${config.apiUrl}/api/shaders/${encoded}/wgsl`, {
    headers: { Accept: 'text/plain' },
  });
}

export async function loadEffectConfig(
  config: StorageClientConfig,
  filename: string
): Promise<EffectConfigRecord> {
  return fetchJson<EffectConfigRecord>(
    resolveStaticUrl(config.staticUrl, `image-effects/metadata/${filename}`)
  );
}
