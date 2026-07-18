import { useState, useEffect, useCallback, useRef } from 'react';
import {
  StorageClient,
  StorageSaveResponse,
  ShaderItem,
  ImageItem,
  VideoItem,
  StorageOperation,
  EffectConfigPayload,
  EffectConfigRecord,
  LoadShaderResult,
  RateShaderResponse,
  getStorageClient,
} from '../services/storage';

export interface StorageState {
  isConnected: boolean;
  isCheckingConnection: boolean;
  connectionError?: string;
  shaders: ShaderItem[];
  images: ImageItem[];
  videos: VideoItem[];
  audio: VideoItem[];
  isLoadingShaders: boolean;
  isLoadingImages: boolean;
  isLoadingVideos: boolean;
  operations: StorageOperation[];
  activeOperations: StorageOperation[];
  lastError?: string;
}

export interface ToastNotification {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  duration?: number;
}

export interface UseStorageReturn extends StorageState {
  refreshShaders: () => Promise<void>;
  refreshImages: () => Promise<void>;
  refreshVideos: () => Promise<void>;
  refreshAll: () => Promise<void>;
  saveShader: (name: string, wgslCode: string, metadata?: Partial<ShaderItem>) => Promise<StorageSaveResponse>;
  saveEffectConfig: (name: string, config: EffectConfigPayload) => Promise<StorageSaveResponse>;
  saveOutput: (name: string, imageData: string, metadata?: Record<string, unknown>) => Promise<StorageSaveResponse>;
  uploadFile: (file: File, type: 'image' | 'video' | 'audio' | 'shader') => Promise<StorageSaveResponse>;
  uploadFiles: (
    files: File[],
    type: 'image' | 'video' | 'audio' | 'shader',
    onProgress?: (completed: number, total: number) => void
  ) => Promise<StorageSaveResponse[]>;
  loadShader: (filename: string) => Promise<LoadShaderResult>;
  loadEffectConfig: (filename: string) => Promise<EffectConfigRecord>;
  rateShader: (shaderId: string, rating: number, notes?: string) => Promise<RateShaderResponse>;
  checkConnection: () => Promise<boolean>;
  clearError: () => void;
  dismissToast: (id: string) => void;
  clearCompleted: () => void;
  toasts: ToastNotification[];
}

export function useStorage(customClient?: StorageClient): UseStorageReturn {
  const serviceRef = useRef<StorageClient>(customClient || getStorageClient());

  const [isConnected, setIsConnected] = useState(false);
  const [isCheckingConnection, setIsCheckingConnection] = useState(true);
  const [connectionError, setConnectionError] = useState<string | undefined>();
  const [shaders, setShaders] = useState<ShaderItem[]>([]);
  const [images, setImages] = useState<ImageItem[]>([]);
  const [videos, setVideos] = useState<VideoItem[]>([]);
  const [audio, setAudio] = useState<VideoItem[]>([]);
  const [isLoadingShaders, setIsLoadingShaders] = useState(false);
  const [isLoadingImages, setIsLoadingImages] = useState(false);
  const [isLoadingVideos, setIsLoadingVideos] = useState(false);
  const [operations, setOperations] = useState<StorageOperation[]>([]);
  const [toasts, setToasts] = useState<ToastNotification[]>([]);
  const [lastError, setLastError] = useState<string | undefined>();

  const dismissToast = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  const addToast = useCallback((toast: ToastNotification) => {
    setToasts(prev => [...prev, toast]);
    if (toast.duration) {
      setTimeout(() => dismissToast(toast.id), toast.duration);
    }
  }, [dismissToast]);

  useEffect(() => {
    const unsubscribe = serviceRef.current.subscribeToOperations((ops) => {
      setOperations(ops);
      ops.forEach(op => {
        if (op.status === 'completed' || op.status === 'error') {
          setToasts(prev => {
            if (prev.some(t => t.id === op.id)) return prev;
            const next = [...prev, {
              id: op.id,
              type: op.status === 'completed' ? 'success' as const : 'error' as const,
              message: op.message || `${op.type} ${op.status}`,
              duration: 5000,
            }];
            return next;
          });
        }
      });
    });
    return unsubscribe;
  }, []);

  useEffect(() => {
    checkConnection();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const checkConnection = useCallback(async (): Promise<boolean> => {
    setIsCheckingConnection(true);
    setConnectionError(undefined);
    try {
      await serviceRef.current.checkHealth();
      setIsConnected(true);
      setConnectionError(undefined);
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Connection failed';
      setIsConnected(false);
      setConnectionError(errorMessage);
      setLastError(errorMessage);
      return false;
    } finally {
      setIsCheckingConnection(false);
    }
  }, []);

  const refreshShaders = useCallback(async () => {
    setIsLoadingShaders(true);
    setLastError(undefined);
    try {
      const data = await serviceRef.current.listShaders();
      setShaders(data);
      addToast({ id: `refresh-shaders-${Date.now()}`, type: 'success', message: `Loaded ${data.length} shaders`, duration: 3000 });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load shaders';
      setLastError(errorMessage);
      addToast({ id: `refresh-shaders-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
    } finally {
      setIsLoadingShaders(false);
    }
  }, [addToast]);

  const refreshImages = useCallback(async () => {
    setIsLoadingImages(true);
    setLastError(undefined);
    try {
      const data = await serviceRef.current.listImages();
      setImages(data);
      addToast({ id: `refresh-images-${Date.now()}`, type: 'success', message: `Loaded ${data.length} images`, duration: 3000 });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load images';
      setLastError(errorMessage);
      addToast({ id: `refresh-images-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
    } finally {
      setIsLoadingImages(false);
    }
  }, [addToast]);

  const refreshVideos = useCallback(async () => {
    setIsLoadingVideos(true);
    setLastError(undefined);
    try {
      const [videoData, audioData] = await Promise.all([
        serviceRef.current.listVideos(),
        serviceRef.current.listAudio(),
      ]);
      setVideos(videoData);
      setAudio(audioData);
      addToast({
        id: `refresh-videos-${Date.now()}`,
        type: 'success',
        message: `Loaded ${videoData.length} videos, ${audioData.length} audio files`,
        duration: 3000,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load videos';
      setLastError(errorMessage);
      addToast({ id: `refresh-videos-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
    } finally {
      setIsLoadingVideos(false);
    }
  }, [addToast]);

  const refreshAll = useCallback(async () => {
    await Promise.all([refreshShaders(), refreshImages(), refreshVideos()]);
  }, [refreshShaders, refreshImages, refreshVideos]);

  const saveShader = useCallback(async (
    name: string,
    wgslCode: string,
    metadata?: Partial<ShaderItem>
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.saveShader(name, wgslCode, metadata ?? {});
      await refreshShaders();
      addToast({ id: `save-shader-${Date.now()}`, type: 'success', message: `Shader "${name}" saved successfully`, duration: 5000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save shader';
      setLastError(errorMessage);
      addToast({ id: `save-shader-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [refreshShaders, addToast]);

  const saveEffectConfig = useCallback(async (
    name: string,
    config: EffectConfigPayload
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.saveEffectConfig(name, config);
      addToast({ id: `save-config-${Date.now()}`, type: 'success', message: `Effect configuration "${name}" saved successfully`, duration: 5000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save configuration';
      setLastError(errorMessage);
      addToast({ id: `save-config-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [addToast]);

  const saveOutput = useCallback(async (
    name: string,
    imageData: string,
    metadata?: Record<string, unknown>
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.saveOutput(name, imageData, metadata);
      addToast({ id: `save-output-${Date.now()}`, type: 'success', message: `Output "${name}" saved successfully`, duration: 5000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save output';
      setLastError(errorMessage);
      addToast({ id: `save-output-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [addToast]);

  const loadShader = useCallback(async (filename: string): Promise<LoadShaderResult> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.loadShader(filename);
      addToast({ id: `load-shader-${Date.now()}`, type: 'success', message: `Shader "${filename}" loaded`, duration: 3000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load shader';
      setLastError(errorMessage);
      addToast({ id: `load-shader-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [addToast]);

  const loadEffectConfig = useCallback(async (filename: string): Promise<EffectConfigRecord> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.loadEffectConfig(filename);
      addToast({ id: `load-config-${Date.now()}`, type: 'success', message: `Configuration "${filename}" loaded`, duration: 3000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load configuration';
      setLastError(errorMessage);
      addToast({ id: `load-config-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [addToast]);

  const rateShader = useCallback(async (
    shaderId: string,
    rating: number,
    notes?: string
  ): Promise<RateShaderResponse> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.rateShader(shaderId, rating, notes);
      setShaders(prev => prev.map(s =>
        s.id === shaderId ? { ...s, rating: result.stars, stars: result.stars, rating_count: result.rating_count } : s
      ));
      addToast({ id: `rate-shader-${Date.now()}`, type: 'success', message: `Rated shader ${rating} stars`, duration: 3000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to rate shader';
      setLastError(errorMessage);
      addToast({ id: `rate-shader-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [addToast]);

  const uploadFile = useCallback(async (
    file: File,
    type: 'image' | 'video' | 'audio' | 'shader'
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    try {
      const result = await serviceRef.current.uploadFile(file, type);
      if (type === 'image') await refreshImages();
      if (type === 'video') await refreshVideos();
      if (type === 'shader') await refreshShaders();
      addToast({ id: `upload-${Date.now()}`, type: 'success', message: `Uploaded "${file.name}" successfully`, duration: 5000 });
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : `Failed to upload ${file.name}`;
      setLastError(errorMessage);
      addToast({ id: `upload-error-${Date.now()}`, type: 'error', message: errorMessage, duration: 5000 });
      throw error;
    }
  }, [refreshImages, refreshVideos, refreshShaders, addToast]);

  const uploadFiles = useCallback(async (
    files: File[],
    type: 'image' | 'video' | 'audio' | 'shader',
    onProgress?: (completed: number, total: number) => void
  ): Promise<StorageSaveResponse[]> => {
    setLastError(undefined);
    const results = await serviceRef.current.uploadFiles(files, type, onProgress);
    const successCount = results.length;
    if (successCount > 0) {
      if (type === 'image') await refreshImages();
      if (type === 'video') await refreshVideos();
      if (type === 'shader') await refreshShaders();
      addToast({ id: `upload-batch-${Date.now()}`, type: 'success', message: `Uploaded ${successCount} of ${files.length} files`, duration: 5000 });
    }
    if (successCount < files.length) {
      addToast({ id: `upload-batch-warning-${Date.now()}`, type: 'warning', message: `${files.length - successCount} files failed to upload`, duration: 5000 });
    }
    return results;
  }, [refreshImages, refreshVideos, refreshShaders, addToast]);

  const clearError = useCallback(() => {
    setLastError(undefined);
    setConnectionError(undefined);
  }, []);

  const clearCompleted = useCallback(() => {
    serviceRef.current.clearCompletedOperations();
  }, []);

  const activeOperations = operations.filter(op =>
    op.status === 'pending' || op.status === 'in_progress'
  );

  return {
    isConnected,
    isCheckingConnection,
    connectionError,
    shaders,
    images,
    videos,
    audio,
    isLoadingShaders,
    isLoadingImages,
    isLoadingVideos,
    operations,
    activeOperations,
    lastError,
    toasts,
    refreshShaders,
    refreshImages,
    refreshVideos,
    refreshAll,
    saveShader,
    saveEffectConfig,
    saveOutput,
    uploadFile,
    uploadFiles,
    loadShader,
    loadEffectConfig,
    rateShader,
    checkConnection,
    clearError,
    dismissToast,
    clearCompleted,
  };
}

export default useStorage;
