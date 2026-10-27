/**
 * VPS Storage client — typed modules aligned with storage_manager/app.py
 */

export {
  StorageClient,
  StorageService,
  storageAPI,
  getStorageClient,
  createStorageClient,
  resetStorageClient,
} from './client';

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
} from './types';

export {
  StorageHttpError,
  encodeResourcePath,
  resolveStaticUrl,
  mapHttpError,
  assertOk,
  fetchJson,
  fetchText,
  unwrapListResponse,
  generateHmacSignature,
} from './http';

export { OperationTracker } from './operations';

export type { UploadFileType } from './webhook';
