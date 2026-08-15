/**
 * StorageClient — typed facade over VPS storage_manager endpoints.
 */

import {
  API_BASE_URL,
  SHADER_FILES_BASE_URL,
  STATIC_NGINX_URL,
  STORAGE_VPS_URL,
  STORAGE_WEBHOOK_SECRET,
} from '../../config/appConfig';
import * as assets from './assets';
import { OperationTracker } from './operations';
import * as ratings from './ratings';
import * as shaders from './shaders';
import type {
  EffectConfigPayload,
  EffectConfigRecord,
  HealthResponse,
  ImageItem,
  LibraryMetaItem,
  LoadShaderResult,
  MediaType,
  RateShaderResponse,
  ShaderItem,
  ShaderListQuery,
  ShaderRatingInfo,
  StorageClientConfig,
  StorageOperation,
  StorageSaveOptions,
  StorageSaveResponse,
  StorageStatus,
  VideoConfigPayload,
  VideoItem,
} from './types';
import {
  fileUploadPayload,
  readFileAsBase64,
  saveEffectConfigPayload,
  saveOutputPayload,
  saveShaderPayload,
  saveVideoConfigPayload,
  uploadTexturePayload,
  webhookSave,
  type UploadFileType,
} from './webhook';
import { fetchJson } from './http';

export class StorageClient {
  private readonly config: StorageClientConfig;
  private readonly ops: OperationTracker;

  constructor(config?: Partial<StorageClientConfig>) {
    this.config = {
      webhookUrl: config?.webhookUrl ?? STORAGE_VPS_URL,
      staticUrl: config?.staticUrl ?? STATIC_NGINX_URL,
      secret: config?.secret ?? STORAGE_WEBHOOK_SECRET,
      apiUrl: config?.apiUrl ?? API_BASE_URL,
      shaderFilesBaseUrl: config?.shaderFilesBaseUrl ?? SHADER_FILES_BASE_URL,
    };
    this.ops = new OperationTracker();
  }

  // ── Operation tracking ─────────────────────────────────────────────────────

  subscribeToOperations(callback: (ops: StorageOperation[]) => void): () => void {
    return this.ops.subscribe(callback);
  }

  getOperations(): StorageOperation[] {
    return this.ops.getOperations();
  }

  clearCompletedOperations(): void {
    this.ops.clearCompleted();
  }

  // ── Webhook saves ──────────────────────────────────────────────────────────

  async save(options: StorageSaveOptions): Promise<StorageSaveResponse> {
    return this.ops.wrap('save', options.name, `Saving ${options.name}...`, () =>
      webhookSave(this.config, options)
    );
  }

  async saveShader(
    name: string,
    wgslCode: string,
    metadata: Partial<ShaderItem> = {}
  ): Promise<StorageSaveResponse> {
    return this.save(saveShaderPayload(name, wgslCode, metadata));
  }

  async saveEffectConfig(name: string, config: EffectConfigPayload): Promise<StorageSaveResponse> {
    return this.save(saveEffectConfigPayload(name, config));
  }

  async saveOutput(
    name: string,
    imageData: string,
    metadata: Record<string, unknown> = {}
  ): Promise<StorageSaveResponse> {
    return this.save(saveOutputPayload(name, imageData, metadata));
  }

  async saveVideoConfig(name: string, config: VideoConfigPayload): Promise<StorageSaveResponse> {
    return this.save(saveVideoConfigPayload(name, config));
  }

  async uploadTexture(
    name: string,
    textureData: string,
    metadata: Record<string, unknown> = {}
  ): Promise<StorageSaveResponse> {
    return this.save(uploadTexturePayload(name, textureData, metadata));
  }

  async uploadFile(
    file: File,
    type: UploadFileType,
    _onProgress?: (progress: number) => void
  ): Promise<StorageSaveResponse> {
    return this.ops.wrap('save', file.name, `Uploading ${file.name}...`, async () => {
      const base64Data = await readFileAsBase64(file);
      return webhookSave(this.config, fileUploadPayload(file, base64Data, type));
    });
  }

  async uploadFiles(
    files: File[],
    type: UploadFileType,
    onProgress?: (completed: number, total: number) => void
  ): Promise<StorageSaveResponse[]> {
    const results: StorageSaveResponse[] = [];
    for (let i = 0; i < files.length; i++) {
      try {
        results.push(await this.uploadFile(files[i], type));
        onProgress?.(i + 1, files.length);
      } catch (error) {
        console.error(`Failed to upload ${files[i].name}:`, error);
      }
    }
    return results;
  }

  // ── Loads ──────────────────────────────────────────────────────────────────

  async loadJson<T>(path: string): Promise<T> {
    return this.ops.wrap('load', path, `Loading ${path}...`, () =>
      assets.loadJson<T>(this.config, path)
    );
  }

  async loadShader(filename: string): Promise<LoadShaderResult> {
    return this.ops.wrap('load', filename, `Loading shader ${filename}...`, () =>
      shaders.loadShader(this.config, filename)
    );
  }

  async loadEffectConfig(filename: string): Promise<EffectConfigRecord> {
    return shaders.loadEffectConfig(this.config, filename);
  }

  // ── Lists ──────────────────────────────────────────────────────────────────

  async listShaders(query?: ShaderListQuery): Promise<ShaderItem[]> {
    return this.ops.wrap('list', undefined, 'Listing shaders...', () =>
      shaders.listShaders(this.config, query)
    );
  }

  async listShadersWithErrors(): Promise<ShaderItem[]> {
    return shaders.listShadersWithErrors(this.config);
  }

  async listImages(): Promise<ImageItem[]> {
    return this.ops.wrap('list', undefined, 'Listing images...', () =>
      assets.listImages(this.config)
    );
  }

  async listSongs(type?: MediaType): Promise<LibraryMetaItem[]> {
    return this.ops.wrap('list', undefined, `Listing ${type || 'all'} media...`, () =>
      assets.listSongs(this.config, type)
    );
  }

  async listVideos(): Promise<VideoItem[]> {
    return assets.listVideos(this.config);
  }

  async listAudio(): Promise<VideoItem[]> {
    return assets.listAudio(this.config);
  }

  async listLibrary(): Promise<LibraryMetaItem[]> {
    return assets.listLibrary(this.config);
  }

  // ── Ratings ────────────────────────────────────────────────────────────────

  async rateShader(shaderId: string, stars: number, notes?: string): Promise<RateShaderResponse> {
    return this.ops.wrap('rate', shaderId, `Rating ${shaderId}...`, () =>
      ratings.rateShader(this.config, shaderId, stars, notes)
    );
  }

  async getShaderRating(shaderId: string): Promise<ShaderRatingInfo> {
    return ratings.getShaderRating(this.config, shaderId);
  }

  async recordShaderPlay(shaderId: string): Promise<{
    success: boolean;
    id: string;
    play_count: number;
    last_played: string;
  } | null> {
    return ratings.recordShaderPlay(this.config, shaderId);
  }

  // ── Health ─────────────────────────────────────────────────────────────────

  async checkHealth(): Promise<HealthResponse> {
    return fetchJson<HealthResponse>(`${this.config.apiUrl}/api/health`);
  }

  async getStatus(): Promise<StorageStatus> {
    try {
      await this.checkHealth();
      return {
        connected: true,
        pendingOperations: this.ops.pendingCount(),
      };
    } catch (error) {
      return {
        connected: false,
        lastError: error instanceof Error ? error.message : 'Unknown error',
        pendingOperations: this.ops.pendingCount(),
      };
    }
  }
}

// ── Singleton ────────────────────────────────────────────────────────────────

let defaultClient: StorageClient | null = null;

export function getStorageClient(): StorageClient {
  if (!defaultClient) {
    defaultClient = new StorageClient();
  }
  return defaultClient;
}

export function createStorageClient(config?: Partial<StorageClientConfig>): StorageClient {
  return new StorageClient(config);
}

export function resetStorageClient(): void {
  defaultClient = null;
}

/** Backward-compatible alias */
export { StorageClient as StorageService };

export const storageAPI = {
  save: (options: StorageSaveOptions) => getStorageClient().save(options),
  saveShader: (name: string, wgslCode: string, metadata?: Partial<ShaderItem>) =>
    getStorageClient().saveShader(name, wgslCode, metadata),
  saveEffectConfig: (name: string, config: EffectConfigPayload) =>
    getStorageClient().saveEffectConfig(name, config),
  loadJson: <T>(path: string) => getStorageClient().loadJson<T>(path),
  loadShader: (filename: string) => getStorageClient().loadShader(filename),
  listShaders: () => getStorageClient().listShaders(),
  listImages: () => getStorageClient().listImages(),
  listSongs: (type?: MediaType) => getStorageClient().listSongs(type),
  rateShader: (shaderId: string, rating: number, notes?: string) =>
    getStorageClient().rateShader(shaderId, rating, notes),
  getShaderRating: (shaderId: string) => getStorageClient().getShaderRating(shaderId),
  checkHealth: () => getStorageClient().checkHealth(),
  getStatus: () => getStorageClient().getStatus(),
  subscribeToOperations: (cb: (ops: StorageOperation[]) => void) =>
    getStorageClient().subscribeToOperations(cb),
};

export default StorageClient;
