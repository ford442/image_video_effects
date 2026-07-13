/**
 * StorageService.ts — backward-compatible facade over src/services/storage/
 *
 * Canonical API: StorageClient from './storage'
 * @see docs/STORAGE_API.md
 */

export {
  StorageClient,
  StorageService,
  storageAPI,
  getStorageClient,
  getStorageService,
  createStorageClient,
  createStorageService,
  resetStorageClient,
  resetStorageService,
} from './storage';

export type {
  StorageSaveAction,
  StorageSaveOptions,
  StorageSaveResponse,
  ShaderItem,
  LoadShaderResult,
  ShaderListQuery,
  ImageItem,
  VideoItem,
  LibraryMetaItem,
  MediaType,
  RateShaderResponse,
  ShaderRatingInfo,
  RatingUpdate,
  EffectConfigPayload,
  EffectConfigRecord,
  VideoConfigPayload,
  StorageStatus,
  StorageOperationType,
  StorageOperation,
  HealthResponse,
  StorageClientConfig,
  StorageHttpError,
  UploadFileType,
} from './storage';

export {
  encodeResourcePath,
  resolveStaticUrl,
  mapHttpError,
  unwrapListResponse,
} from './storage';

export { StorageClient as default } from './storage';
