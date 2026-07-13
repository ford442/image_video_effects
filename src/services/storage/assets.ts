/**
 * Asset listing — images, video, audio via /api/songs and library index.
 */

import { fetchJson, resolveStaticUrl, unwrapListResponse } from './http';
import type {
  ImageItem,
  LibraryMetaItem,
  MediaType,
  StorageClientConfig,
  VideoItem,
} from './types';

function withImageUrls(items: LibraryMetaItem[], apiUrl: string): ImageItem[] {
  return items.map(item => ({
    id: item.id,
    name: item.name,
    type: item.type,
    description: item.description,
    tags: item.tags ?? [],
    date: item.date,
    url: `${apiUrl}/api/images/${encodeURIComponent(item.id)}`,
  }));
}

function metaToVideoItem(item: LibraryMetaItem, apiUrl: string): VideoItem {
  return {
    id: item.id,
    title: item.name,
    artist: item.author ?? 'Unknown',
    url: `${apiUrl}/api/songs/${encodeURIComponent(item.id)}`,
    type: item.type,
  };
}

/** List images via GET /api/songs?type=image (canonical per storage_manager). */
export async function listImages(config: StorageClientConfig): Promise<ImageItem[]> {
  const responseData = await fetchJson<LibraryMetaItem[] | { images: LibraryMetaItem[] }>(
    `${config.apiUrl}/api/songs?type=image`
  );
  const items = unwrapListResponse(responseData, 'images');
  return withImageUrls(items, config.apiUrl);
}

/** List media from the unified library endpoint. */
export async function listSongs(
  config: StorageClientConfig,
  type?: MediaType
): Promise<LibraryMetaItem[]> {
  const url = type
    ? `${config.apiUrl}/api/songs?type=${encodeURIComponent(type)}`
    : `${config.apiUrl}/api/songs`;
  return fetchJson<LibraryMetaItem[]>(url);
}

export async function listVideos(config: StorageClientConfig): Promise<VideoItem[]> {
  const items = await listSongs(config, 'video');
  return items.map(item => metaToVideoItem(item, config.apiUrl));
}

export async function listAudio(config: StorageClientConfig): Promise<VideoItem[]> {
  const items = await listSongs(config, 'audio');
  return items.map(item => metaToVideoItem(item, config.apiUrl));
}

export async function listLibrary(config: StorageClientConfig): Promise<LibraryMetaItem[]> {
  return listSongs(config);
}

export async function loadJson<T>(config: StorageClientConfig, path: string): Promise<T> {
  const url = resolveStaticUrl(config.staticUrl, path);
  return fetchJson<T>(url, {
    method: 'GET',
    headers: { Accept: 'application/json' },
  });
}
