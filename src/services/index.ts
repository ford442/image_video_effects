// ═══════════════════════════════════════════════════════════════════════════════
//  Services Index
//  Central export for all service modules
// ═══════════════════════════════════════════════════════════════════════════════

// Storage Service (VPS Integration)
export {
  StorageService,
  storageAPI,
  getStorageService,
  createStorageService,
  resetStorageService,
} from './StorageService';

export type {
  StorageSaveOptions,
  StorageSaveResponse,
  ShaderItem,
  ImageItem,
  VideoItem,
  RatingUpdate,
  StorageStatus,
  StorageOperation,
  StorageOperationType,
} from './StorageService';

// Shader API (Legacy HuggingFace Space)
export {
  glslToWgsl,
  convertGlslToWgsl,
  isTintAvailable,
  extractShaderId,
  wrapShadertoyGlsl,
  importFromShadertoy,
  listShaders,
  getShader,
  uploadShader,
  updateShaderMetadata,
  getRendererStatus,
  convertShader,
} from './shaderApi';

export type {
  ShaderMetadata,
  ShaderImportResult,
  ShaderContent,
  RendererStatus,
} from './shaderApi';

// Shader Rating Integration
export {
  ShaderRatingService,
  CoordinateMenuBuilder,
  useShaderRatings,
} from './ShaderRatingIntegration';

export type {
  MenuGroup,
  EnrichedShader,
} from './ShaderRatingIntegration';

// Content Loader
export {
  fetchContentManifest,
} from './contentLoader';

export type { LoadedContent } from './contentLoader';

// Shader Catalog (canonical metadata + search)
export {
  buildCatalog,
  searchCatalog,
} from './shaderCatalog';

export type {
  CatalogShader,
  CatalogParam,
} from './shaderCatalog';
