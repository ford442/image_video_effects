// Storage Service (VPS Integration) — see docs/STORAGE_API.md
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
  StorageSaveOptions,
  StorageSaveResponse,
  ShaderItem,
  LoadShaderResult,
  ImageItem,
  VideoItem,
  EffectConfigPayload,
  EffectConfigRecord,
  RateShaderResponse,
  ShaderRatingInfo,
  RatingUpdate,
  StorageStatus,
  StorageOperation,
  StorageOperationType,
} from './storage';
