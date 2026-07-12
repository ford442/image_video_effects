/**
 * Typed contracts for the VPS Storage API client.
 * Aligned with storage_manager/app.py response shapes.
 */

import type { SlotParams } from '../../renderer/types';

// ── Webhook save ─────────────────────────────────────────────────────────────

export type StorageSaveAction =
  | 'save_shader'
  | 'save_metadata'
  | 'save_output'
  | 'save_video_config'
  | 'upload_texture'
  | 'upload_audio';

export interface StorageSaveOptions {
  action: StorageSaveAction;
  name: string;
  data: Record<string, unknown>;
}

export interface StorageSaveResponse {
  status: 'success' | 'error';
  message: string;
  files?: string[];
  remote_files?: string[];
  url?: string;
}

// ── Shaders ──────────────────────────────────────────────────────────────────

export interface ShaderItem {
  id: string;
  name: string;
  author: string;
  date: string;
  type: string;
  description: string;
  filename: string;
  tags: string[];
  /** Legacy field; populated from `stars` when fetching. */
  rating: number | null;
  stars?: number;
  rating_count?: number;
  play_count?: number;
  source?: string;
  format?: string;
  has_errors?: boolean;
  thumbnail_url?: string;
  url?: string;
  coordinate?: number | null;
  last_played?: string;
}

export interface LoadShaderResult {
  id: string;
  content: string;
  type: string;
  data: ShaderItem;
}

export interface ShaderListQuery {
  category?: string;
  minStars?: number;
  sortBy?: 'rating' | 'date' | 'name' | 'coordinate' | 'last_played';
}

// ── Assets (images, video, audio) ────────────────────────────────────────────

export interface ImageItem {
  id?: string;
  url: string;
  description?: string;
  tags: string[];
  date?: string;
  name?: string;
  type?: string;
}

export interface VideoItem {
  id: string;
  title: string;
  artist: string;
  url: string;
  duration?: number;
  type: string;
}

export interface LibraryMetaItem {
  id: string;
  name: string;
  author?: string;
  date?: string;
  type: string;
  description?: string;
  filename?: string;
  tags?: string[];
  updated_at?: string;
  thumbnail_url?: string;
  rating?: number | null;
  genre?: string;
}

export type MediaType = 'audio' | 'image' | 'video';

// ── Ratings ──────────────────────────────────────────────────────────────────

export interface RateShaderResponse {
  id: string;
  stars: number;
  rating_count: number;
  your_rating: number;
}

export interface ShaderRatingInfo {
  id: string;
  rating: number;
  notes?: string;
  date?: string;
  has_errors: boolean;
  rating_count?: number;
  play_count?: number;
}

export interface RatingUpdate {
  rating: number;
  notes?: string;
}

// ── Effect configs ───────────────────────────────────────────────────────────

export interface EffectConfigPayload {
  modes: string[];
  slotParams: SlotParams[];
  inputSource: string;
  currentImageUrl?: string;
  activeGenerativeShader?: string;
}

export interface EffectConfigRecord extends EffectConfigPayload {
  type: 'effect_config';
  name: string;
  saved_at: string;
}

export interface VideoConfigPayload {
  videoUrl: string;
  effects: string[];
  parameters: Record<string, number | string | boolean>;
}

// ── Operations & status ──────────────────────────────────────────────────────

export interface StorageStatus {
  connected: boolean;
  lastError?: string;
  pendingOperations: number;
}

export type StorageOperationType = 'save' | 'load' | 'list' | 'rate' | 'delete';

export interface StorageOperation {
  id: string;
  type: StorageOperationType;
  status: 'pending' | 'in_progress' | 'completed' | 'error';
  message?: string;
  timestamp: number;
  itemName?: string;
}

export interface HealthResponse {
  status: string;
  service: string;
}

export interface StorageClientConfig {
  webhookUrl: string;
  staticUrl: string;
  secret: string;
  apiUrl: string;
  shaderFilesBaseUrl: string;
}
