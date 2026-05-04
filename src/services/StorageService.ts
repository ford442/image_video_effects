// ═══════════════════════════════════════════════════════════════════════════════
//  StorageService.ts
//  VPS Storage API Integration for Pixelocity
//  Handles saving/loading shaders, images, videos with HMAC SHA256 signatures
// ═══════════════════════════════════════════════════════════════════════════════

import { API_BASE_URL, STORAGE_VPS_URL, STORAGE_WEBHOOK_SECRET, STATIC_NGINX_URL } from '../config/appConfig';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

export interface StorageSaveOptions {
  action: 'save_shader' | 'save_metadata' | 'save_output' | 'save_video_config' | 'upload_texture';
  name: string;
  data: Record<string, any>;
}

export interface StorageSaveResponse {
  status: 'success' | 'error';
  message: string;
  files?: string[];
  remote_files?: string[];
  url?: string;
}

export interface ShaderItem {
  id: string;
  name: string;
  author: string;
  date: string;
  type: string;
  description: string;
  filename: string;
  tags: string[];
  /** Legacy `rating` field (kept for backward compat). Populated from `stars` when fetching. */
  rating: number | null;
  /** Aggregate star rating average (0–5). Comes from the backend's `stars` field. */
  stars?: number;
  /** Total number of ratings submitted. */
  rating_count?: number;
  /** Total play count. */
  play_count?: number;
  source: string;
  format: string;
  has_errors: boolean;
  thumbnail_url?: string;
  url?: string;
}

export interface ImageItem {
  url: string;
  description?: string;
  tags: string[];
  date?: string;
}

export interface VideoItem {
  id: string;
  title: string;
  artist: string;
  url: string;
  duration?: number;
  type: string;
}

export interface RatingUpdate {
  rating: number;
  notes?: string;
}

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

// ═══════════════════════════════════════════════════════════════════════════════
//  HMAC SHA256 Signature Generation (Web Crypto API)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Generate HMAC SHA256 signature for webhook authentication
 * Uses the browser's native Web Crypto API
 */
async function generateSignature(payload: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  
  // Import the secret key
  const keyData = encoder.encode(secret);
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  
  // Sign the payload
  const payloadData = encoder.encode(payload);
  const signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, payloadData);
  
  // Convert to hex string
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
  
  return `sha256=${signatureHex}`;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Storage Service Class
// ═══════════════════════════════════════════════════════════════════════════════

export class StorageService {
  private webhookUrl: string;
  private staticUrl: string;
  private secret: string;
  private apiUrl: string;
  private operationCallbacks: Set<(ops: StorageOperation[]) => void>;
  private operations: StorageOperation[];
  private maxOperations: number;

  constructor(
    webhookUrl: string = STORAGE_VPS_URL,
    staticUrl: string = STATIC_NGINX_URL,
    secret: string = STORAGE_WEBHOOK_SECRET,
    apiUrl: string = API_BASE_URL
  ) {
    this.webhookUrl = webhookUrl;
    this.staticUrl = staticUrl;
    this.secret = secret;
    this.apiUrl = apiUrl;
    this.operationCallbacks = new Set();
    this.operations = [];
    this.maxOperations = 50;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Operation Tracking
  // ─────────────────────────────────────────────────────────────────────────────

  private addOperation(op: Omit<StorageOperation, 'id' | 'timestamp'>): string {
    const operation: StorageOperation = {
      ...op,
      id: `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      timestamp: Date.now(),
    };
    
    this.operations = [operation, ...this.operations].slice(0, this.maxOperations);
    this.notifyOperationChange();
    
    return operation.id;
  }

  private updateOperation(id: string, updates: Partial<StorageOperation>) {
    this.operations = this.operations.map(op =>
      op.id === id ? { ...op, ...updates } : op
    );
    this.notifyOperationChange();
  }

  private notifyOperationChange() {
    this.operationCallbacks.forEach(cb => cb([...this.operations]));
  }

  subscribeToOperations(callback: (ops: StorageOperation[]) => void): () => void {
    this.operationCallbacks.add(callback);
    callback([...this.operations]);
    
    return () => {
      this.operationCallbacks.delete(callback);
    };
  }

  getOperations(): StorageOperation[] {
    return [...this.operations];
  }

  clearCompletedOperations() {
    this.operations = this.operations.filter(op => 
      op.status === 'pending' || op.status === 'in_progress'
    );
    this.notifyOperationChange();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Core API Methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Save data to the VPS via webhook with HMAC signature
   */
  async save(options: StorageSaveOptions): Promise<StorageSaveResponse> {
    const opId = this.addOperation({
      type: 'save',
      status: 'in_progress',
      itemName: options.name,
      message: `Saving ${options.name}...`,
    });

    try {
      const payload = JSON.stringify({
        action: options.action,
        name: options.name,
        data: options.data,
        timestamp: new Date().toISOString(),
      });

      const signature = await generateSignature(payload, this.secret);

      const response = await fetch(`${this.webhookUrl}/image-effects`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Hub-Signature-256': signature,
        },
        body: payload,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`HTTP ${response.status}: ${errorText}`);
      }

      const result: StorageSaveResponse = await response.json();
      
      // Construct the static URL for the saved file
      if (result.files && result.files.length > 0) {
        const filePath = result.files[0];
        result.url = `${this.staticUrl}/${filePath}`;
      }

      this.updateOperation(opId, {
        status: 'completed',
        message: `Saved ${options.name} successfully`,
      });

      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to save ${options.name}: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * Save a shader with its metadata and WGSL code
   */
  async saveShader(
    name: string,
    wgslCode: string,
    metadata: Partial<ShaderItem> = {}
  ): Promise<StorageSaveResponse> {
    return this.save({
      action: 'save_shader',
      name,
      data: {
        name,
        wgsl_code: wgslCode,
        ...metadata,
        saved_at: new Date().toISOString(),
      },
    });
  }

  /**
   * Save current effect configuration (slots, params, etc.)
   */
  async saveEffectConfig(
    name: string,
    config: {
      modes: string[];
      slotParams: any[];
      inputSource: string;
      currentImageUrl?: string;
      activeGenerativeShader?: string;

    }
  ): Promise<StorageSaveResponse> {
    return this.save({
      action: 'save_metadata',
      name,
      data: {
        type: 'effect_config',
        name,
        ...config,
        saved_at: new Date().toISOString(),
      },
    });
  }

  /**
   * Save a rendered output image
   */
  async saveOutput(
    name: string,
    imageData: string, // base64 image data
    metadata?: Record<string, any>
  ): Promise<StorageSaveResponse> {
    return this.save({
      action: 'save_output',
      name,
      data: {
        image_data: imageData,
        ...metadata,
        saved_at: new Date().toISOString(),
      },
    });
  }

  /**
   * Save video configuration
   */
  async saveVideoConfig(
    name: string,
    config: {
      videoUrl: string;
      effects: string[];
      parameters: Record<string, any>;
    }
  ): Promise<StorageSaveResponse> {
    return this.save({
      action: 'save_video_config',
      name,
      data: {
        type: 'video_config',
        ...config,
        saved_at: new Date().toISOString(),
      },
    });
  }

  /**
   * Upload a texture file
   */
  async uploadTexture(
    name: string,
    textureData: string, // base64 image data
    metadata?: Record<string, any>
  ): Promise<StorageSaveResponse> {
    return this.save({
      action: 'upload_texture',
      name,
      data: {
        texture_data: textureData,
        ...metadata,
        saved_at: new Date().toISOString(),
      },
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Loading Methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Load a JSON file from the static Nginx server
   */
  async loadJson<T = any>(path: string): Promise<T> {
    const opId = this.addOperation({
      type: 'load',
      status: 'in_progress',
      itemName: path,
      message: `Loading ${path}...`,
    });

    try {
      const url = path.startsWith('http') ? path : `${this.staticUrl}/${path}`;
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();

      this.updateOperation(opId, {
        status: 'completed',
        message: `Loaded ${path} successfully`,
      });

      return data;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to load ${path}: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * Load a shader by its filename
   */
  async loadShader(filename: string): Promise<{
    id: string;
    content: string;
    type: string;
    data: ShaderItem;
  }> {
    const opId = this.addOperation({
      type: 'load',
      status: 'in_progress',
      itemName: filename,
      message: `Loading shader ${filename}...`,
    });

    try {
      // Try VPS API first
      const response = await fetch(`${this.apiUrl}/api/shaders/${filename.replace('.json', '')}`);
      
      if (!response.ok) {
        // Fallback to static URL
        const data = await this.loadJson(`image-effects/shaders/${filename}`);

        // Fetch actual WGSL content instead of returning stringified metadata
        let content = '';
        if (data.filename) {
          try {
            const wgslFilename = data.filename.replace(/\.json$/, '.wgsl');
            const wgslRes = await fetch(`${this.apiUrl}/files/image-effects/shaders/${wgslFilename}`);
            if (wgslRes.ok) content = await wgslRes.text();
          } catch { /* content stays empty, handled by caller */ }
        }

        this.updateOperation(opId, {
          status: 'completed',
          message: `Loaded shader ${filename}`,
        });

        return {
          id: filename.replace('.json', ''),
          content,
          type: data.format || 'wgsl',
          data,
        };
      }

      const result = await response.json();

      this.updateOperation(opId, {
        status: 'completed',
        message: `Loaded shader ${filename}`,
      });

      return result;
    } catch (error) {
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to load shader ${filename}`,
      });
      throw error;
    }
  }

  /**
   * Load effect configuration
   */
  async loadEffectConfig(filename: string): Promise<any> {
    return this.loadJson(`image-effects/metadata/${filename}`);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Listing Methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * List all available shaders
   */
  async listShaders(): Promise<ShaderItem[]> {
    const opId = this.addOperation({
      type: 'list',
      status: 'in_progress',
      message: 'Listing shaders...',
    });

    try {
      const response = await fetch(`${this.apiUrl}/api/shaders`);
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const shaders: ShaderItem[] = await response.json();
      
      // Add static URLs and normalise the `stars`→`rating` field
      shaders.forEach(shader => {
        shader.url = `${this.staticUrl}/image-effects/shaders/${shader.filename}`;
        // Backend returns `stars` (aggregate average); surface it as `rating` for compat
        if (shader.stars === undefined && (shader as any).stars !== undefined) {
          shader.stars = (shader as any).stars;
        }
        if (shader.rating === null || shader.rating === undefined) {
          shader.rating = shader.stars ?? null;
        }
      });

      this.updateOperation(opId, {
        status: 'completed',
        message: `Found ${shaders.length} shaders`,
      });

      return shaders;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to list shaders: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * List shaders with errors (0 star ratings)
   */
  async listShadersWithErrors(): Promise<ShaderItem[]> {
    const response = await fetch(`${this.apiUrl}/api/shaders/errors`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const shaders: ShaderItem[] = await response.json();
    shaders.forEach(shader => {
      shader.url = `${this.staticUrl}/image-effects/shaders/${shader.filename}`;
    });

    return shaders;
  }

  /**
   * List available images
   */
  async listImages(): Promise<ImageItem[]> {
    const opId = this.addOperation({
      type: 'list',
      status: 'in_progress',
      message: 'Listing images...',
    });

    try {
      const response = await fetch(`${this.apiUrl}/api/images`);
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const images: ImageItem[] = await response.json();

      this.updateOperation(opId, {
        status: 'completed',
        message: `Found ${images.length} images`,
      });

      return images;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to list images: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * List available songs/videos
   */
  async listSongs(type?: 'audio' | 'image' | 'video'): Promise<(VideoItem | ImageItem)[]> {
    const opId = this.addOperation({
      type: 'list',
      status: 'in_progress',
      message: `Listing ${type || 'all'} media...`,
    });

    try {
      const url = type 
        ? `${this.apiUrl}/api/songs?type=${type}`
        : `${this.apiUrl}/api/songs`;
      
      const response = await fetch(url);
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const items = await response.json();

      this.updateOperation(opId, {
        status: 'completed',
        message: `Found ${items.length} items`,
      });

      return items;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to list media: ${errorMessage}`,
      });

      throw error;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Rating Methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Rate a shader (1–5 stars).
   * Backend: POST /api/shaders/{id}/rate expects FormData with a `stars` field.
   */
  async rateShader(shaderId: string, rating: number, notes?: string): Promise<{
    success: boolean;
    id: string;
    rating: number;
    status: string;
    message: string;
  }> {
    const opId = this.addOperation({
      type: 'rate',
      status: 'in_progress',
      itemName: shaderId,
      message: `Rating ${shaderId}...`,
    });

    try {
      const form = new FormData();
      form.append('stars', String(rating));
      
      const response = await fetch(`${this.apiUrl}/api/shaders/${shaderId}/rate`, {
        method: 'POST',
        body: form,
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const result = await response.json();

      this.updateOperation(opId, {
        status: 'completed',
        message: `Rated ${shaderId}: ${rating} stars`,
      });

      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to rate ${shaderId}: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * Get rating for a specific shader
   */
  async getShaderRating(shaderId: string): Promise<{
    id: string;
    rating: number;
    notes?: string;
    date?: string;
    has_errors: boolean;
  }> {
    const response = await fetch(`${this.apiUrl}/api/shaders/${shaderId}/rating`);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    return response.json();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Health Check
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Check VPS connectivity
   */
  async checkHealth(): Promise<{ status: string; service: string }> {
    try {
      const response = await fetch(`${this.apiUrl}/health`, {
        method: 'GET',
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      return response.json();
    } catch (error) {
      throw new Error('VPS Storage API is unreachable');
    }
  }

  /**
   * Get full storage status
   */
  async getStatus(): Promise<StorageStatus> {
    try {
      await this.checkHealth();
      return {
        connected: true,
        pendingOperations: this.operations.filter(op => 
          op.status === 'pending' || op.status === 'in_progress'
        ).length,
      };
    } catch (error) {
      return {
        connected: false,
        lastError: error instanceof Error ? error.message : 'Unknown error',
        pendingOperations: this.operations.filter(op => 
          op.status === 'pending' || op.status === 'in_progress'
        ).length,
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  File Upload Methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Upload a file (image, video, audio) to the VPS via webhook
   */
  async uploadFile(
    file: File,
    type: 'image' | 'video' | 'audio' | 'shader',
    onProgress?: (progress: number) => void
  ): Promise<StorageSaveResponse> {
    const opId = this.addOperation({
      type: 'save',
      status: 'in_progress',
      itemName: file.name,
      message: `Uploading ${file.name}...`,
    });

    try {
      // Determine action based on file type
      let action: string;
      
      switch (type) {
        case 'image':
          action = 'upload_texture';
          break;
        case 'video':
          action = 'save_video_config';
          break;
        case 'audio':
          action = 'upload_audio';
          break;
        case 'shader':
          action = 'save_shader';
          break;
        default:
          throw new Error(`Unsupported file type: ${type}`);
      }

      // Read file as base64
      const base64Data = await this.readFileAsBase64(file);
      
      // Prepare payload
      const payload = JSON.stringify({
        action,
        name: file.name,
        data: {
          file_data: base64Data,
          file_name: file.name,
          file_type: file.type,
          file_size: file.size,
          upload_type: type,
          saved_at: new Date().toISOString(),
        },
        timestamp: new Date().toISOString(),
      });

      const signature = await generateSignature(payload, this.secret);

      const response = await fetch(`${this.webhookUrl}/image-effects`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Hub-Signature-256': signature,
        },
        body: payload,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`HTTP ${response.status}: ${errorText}`);
      }

      const result: StorageSaveResponse = await response.json();

      // Construct the static URL
      if (result.files && result.files.length > 0) {
        result.url = `${this.staticUrl}/${result.files[0]}`;
      }

      this.updateOperation(opId, {
        status: 'completed',
        message: `Uploaded ${file.name} successfully`,
      });

      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      
      this.updateOperation(opId, {
        status: 'error',
        message: `Failed to upload ${file.name}: ${errorMessage}`,
      });

      throw error;
    }
  }

  /**
   * Upload multiple files
   */
  async uploadFiles(
    files: File[],
    type: 'image' | 'video' | 'audio' | 'shader',
    onProgress?: (completed: number, total: number) => void
  ): Promise<StorageSaveResponse[]> {
    const results: StorageSaveResponse[] = [];
    
    for (let i = 0; i < files.length; i++) {
      try {
        const result = await this.uploadFile(files[i], type);
        results.push(result);
        onProgress?.(i + 1, files.length);
      } catch (error) {
        // Continue with other files even if one fails
        console.error(`Failed to upload ${files[i].name}:`, error);
      }
    }
    
    return results;
  }

  /**
   * Read file as base64 string
   */
  private readFileAsBase64(file: File): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const result = reader.result as string;
        // Remove data URL prefix (e.g., "data:image/png;base64,")
        const base64 = result.split(',')[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Singleton Instance
// ═══════════════════════════════════════════════════════════════════════════════

let defaultService: StorageService | null = null;

export function getStorageService(): StorageService {
  if (!defaultService) {
    defaultService = new StorageService();
  }
  return defaultService;
}

export function createStorageService(
  webhookUrl?: string,
  staticUrl?: string,
  secret?: string,
  apiUrl?: string
): StorageService {
  return new StorageService(webhookUrl, staticUrl, secret, apiUrl);
}

// Reset singleton (useful for testing)
export function resetStorageService(): void {
  defaultService = null;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Direct Export Functions (convenience)
// ═══════════════════════════════════════════════════════════════════════════════

export const storageAPI = {
  save: (options: StorageSaveOptions) => getStorageService().save(options),
  saveShader: (name: string, wgslCode: string, metadata?: Partial<ShaderItem>) => 
    getStorageService().saveShader(name, wgslCode, metadata),
  saveEffectConfig: (name: string, config: any) => 
    getStorageService().saveEffectConfig(name, config),
  loadJson: <T = any>(path: string) => getStorageService().loadJson<T>(path),
  loadShader: (filename: string) => getStorageService().loadShader(filename),
  listShaders: () => getStorageService().listShaders(),
  listImages: () => getStorageService().listImages(),
  listSongs: (type?: 'audio' | 'image' | 'video') => getStorageService().listSongs(type),
  rateShader: (shaderId: string, rating: number, notes?: string) => 
    getStorageService().rateShader(shaderId, rating, notes),
  getShaderRating: (shaderId: string) => getStorageService().getShaderRating(shaderId),
  checkHealth: () => getStorageService().checkHealth(),
  getStatus: () => getStorageService().getStatus(),
  subscribeToOperations: (cb: (ops: StorageOperation[]) => void) => 
    getStorageService().subscribeToOperations(cb),
};

export default StorageService;
