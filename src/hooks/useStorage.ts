// ═══════════════════════════════════════════════════════════════════════════════
//  useStorage.ts
//  React hook for VPS Storage API integration
//  Provides state management for save/load operations with UI feedback
// ═══════════════════════════════════════════════════════════════════════════════

import { useState, useEffect, useCallback, useRef } from 'react';
import {
  StorageService,
  StorageSaveResponse,
  ShaderItem,
  ImageItem,
  VideoItem,
  StorageOperation,
  getStorageService,
} from '../services/StorageService';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

export interface StorageState {
  // Connection state
  isConnected: boolean;
  isCheckingConnection: boolean;
  connectionError?: string;
  
  // Data lists
  shaders: ShaderItem[];
  images: ImageItem[];
  videos: VideoItem[];
  audio: VideoItem[];
  
  // Loading states
  isLoadingShaders: boolean;
  isLoadingImages: boolean;
  isLoadingVideos: boolean;
  
  // Operations
  operations: StorageOperation[];
  activeOperations: StorageOperation[];
  
  // Errors
  lastError?: string;
}

export interface ToastNotification {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  duration?: number;
}

export interface UseStorageReturn extends StorageState {
  // Actions
  refreshShaders: () => Promise<void>;
  refreshImages: () => Promise<void>;
  refreshVideos: () => Promise<void>;
  refreshAll: () => Promise<void>;
  
  // Save operations
  saveShader: (name: string, wgslCode: string, metadata?: Partial<ShaderItem>) => Promise<StorageSaveResponse>;
  saveEffectConfig: (name: string, config: any) => Promise<StorageSaveResponse>;
  saveOutput: (name: string, imageData: string, metadata?: Record<string, any>) => Promise<StorageSaveResponse>;
  
  // Load operations
  loadShader: (filename: string) => Promise<any>;
  loadEffectConfig: (filename: string) => Promise<any>;
  
  // Rating
  rateShader: (shaderId: string, rating: number, notes?: string) => Promise<any>;
  
  // Utility
  checkConnection: () => Promise<boolean>;
  clearError: () => void;
  dismissToast: (id: string) => void;
  clearCompleted: () => void;
  
  // Toasts
  toasts: ToastNotification[];
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Hook Implementation
// ═══════════════════════════════════════════════════════════════════════════════

export function useStorage(customService?: StorageService): UseStorageReturn {
  const serviceRef = useRef<StorageService>(customService || getStorageService());
  
  // Connection state
  const [isConnected, setIsConnected] = useState(false);
  const [isCheckingConnection, setIsCheckingConnection] = useState(true);
  const [connectionError, setConnectionError] = useState<string | undefined>();
  
  // Data lists
  const [shaders, setShaders] = useState<ShaderItem[]>([]);
  const [images, setImages] = useState<ImageItem[]>([]);
  const [videos, setVideos] = useState<VideoItem[]>([]);
  const [audio, setAudio] = useState<VideoItem[]>([]);
  
  // Loading states
  const [isLoadingShaders, setIsLoadingShaders] = useState(false);
  const [isLoadingImages, setIsLoadingImages] = useState(false);
  const [isLoadingVideos, setIsLoadingVideos] = useState(false);
  
  // Operations
  const [operations, setOperations] = useState<StorageOperation[]>([]);
  const [toasts, setToasts] = useState<ToastNotification[]>([]);
  const [lastError, setLastError] = useState<string | undefined>();

  // Subscribe to operation updates
  useEffect(() => {
    const unsubscribe = serviceRef.current.subscribeToOperations((ops) => {
      setOperations(ops);
      
      // Create toasts for completed/error operations
      ops.forEach(op => {
        if (op.status === 'completed' || op.status === 'error') {
          const existingToast = toasts.find(t => t.id === op.id);
          if (!existingToast) {
            addToast({
              id: op.id,
              type: op.status === 'completed' ? 'success' : 'error',
              message: op.message || `${op.type} ${op.status}`,
              duration: 5000,
            });
          }
        }
      });
    });
    
    return unsubscribe;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [toasts]);

  // Check connection on mount
  useEffect(() => {
    checkConnection();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Toast helper
  const addToast = useCallback((toast: ToastNotification) => {
    setToasts(prev => [...prev, toast]);
    
    // Auto-dismiss
    if (toast.duration) {
      setTimeout(() => {
        dismissToast(toast.id);
      }, toast.duration);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const dismissToast = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Check connection
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Refresh shaders
  const refreshShaders = useCallback(async () => {
    setIsLoadingShaders(true);
    setLastError(undefined);
    
    try {
      const data = await serviceRef.current.listShaders();
      setShaders(data);
      addToast({
        id: `refresh-shaders-${Date.now()}`,
        type: 'success',
        message: `Loaded ${data.length} shaders`,
        duration: 3000,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load shaders';
      setLastError(errorMessage);
      addToast({
        id: `refresh-shaders-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
    } finally {
      setIsLoadingShaders(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Refresh images
  const refreshImages = useCallback(async () => {
    setIsLoadingImages(true);
    setLastError(undefined);
    
    try {
      const data = await serviceRef.current.listImages();
      setImages(data);
      addToast({
        id: `refresh-images-${Date.now()}`,
        type: 'success',
        message: `Loaded ${data.length} images`,
        duration: 3000,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load images';
      setLastError(errorMessage);
      addToast({
        id: `refresh-images-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
    } finally {
      setIsLoadingImages(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Refresh videos
  const refreshVideos = useCallback(async () => {
    setIsLoadingVideos(true);
    setLastError(undefined);
    
    try {
      const [videoData, audioData] = await Promise.all([
        serviceRef.current.listSongs('video'),
        serviceRef.current.listSongs('audio'),
      ]);
      
      setVideos(videoData as VideoItem[]);
      setAudio(audioData as VideoItem[]);
      
      addToast({
        id: `refresh-videos-${Date.now()}`,
        type: 'success',
        message: `Loaded ${videoData.length} videos, ${audioData.length} audio files`,
        duration: 3000,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load videos';
      setLastError(errorMessage);
      addToast({
        id: `refresh-videos-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
    } finally {
      setIsLoadingVideos(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Refresh all
  const refreshAll = useCallback(async () => {
    await Promise.all([
      refreshShaders(),
      refreshImages(),
      refreshVideos(),
    ]);
  }, [refreshShaders, refreshImages, refreshVideos]);

  // Save shader
  const saveShader = useCallback(async (
    name: string,
    wgslCode: string,
    metadata?: Partial<ShaderItem>
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.saveShader(name, wgslCode, metadata ?? {});
      
      // Refresh shader list after save
      await refreshShaders();
      
      addToast({
        id: `save-shader-${Date.now()}`,
        type: 'success',
        message: `Shader "${name}" saved successfully`,
        duration: 5000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save shader';
      setLastError(errorMessage);
      addToast({
        id: `save-shader-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshShaders]);

  // Save effect config
  const saveEffectConfig = useCallback(async (
    name: string,
    config: any
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.saveEffectConfig(name, config);
      
      addToast({
        id: `save-config-${Date.now()}`,
        type: 'success',
        message: `Effect configuration "${name}" saved successfully`,
        duration: 5000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save configuration';
      setLastError(errorMessage);
      addToast({
        id: `save-config-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Save output
  const saveOutput = useCallback(async (
    name: string,
    imageData: string,
    metadata?: Record<string, any>
  ): Promise<StorageSaveResponse> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.saveOutput(name, imageData, metadata);
      
      addToast({
        id: `save-output-${Date.now()}`,
        type: 'success',
        message: `Output "${name}" saved successfully`,
        duration: 5000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to save output';
      setLastError(errorMessage);
      addToast({
        id: `save-output-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Load shader
  const loadShader = useCallback(async (filename: string): Promise<any> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.loadShader(filename);
      
      addToast({
        id: `load-shader-${Date.now()}`,
        type: 'success',
        message: `Shader "${filename}" loaded`,
        duration: 3000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load shader';
      setLastError(errorMessage);
      addToast({
        id: `load-shader-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Load effect config
  const loadEffectConfig = useCallback(async (filename: string): Promise<any> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.loadEffectConfig(filename);
      
      addToast({
        id: `load-config-${Date.now()}`,
        type: 'success',
        message: `Configuration "${filename}" loaded`,
        duration: 3000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load configuration';
      setLastError(errorMessage);
      addToast({
        id: `load-config-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Rate shader
  const rateShader = useCallback(async (
    shaderId: string,
    rating: number,
    notes?: string
  ): Promise<any> => {
    setLastError(undefined);
    
    try {
      const result = await serviceRef.current.rateShader(shaderId, rating, notes);
      
      // Update local shader list
      setShaders(prev => prev.map(s => 
        s.id === shaderId ? { ...s, rating } : s
      ));
      
      addToast({
        id: `rate-shader-${Date.now()}`,
        type: 'success',
        message: `Rated shader ${rating} stars`,
        duration: 3000,
      });
      
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to rate shader';
      setLastError(errorMessage);
      addToast({
        id: `rate-shader-error-${Date.now()}`,
        type: 'error',
        message: errorMessage,
        duration: 5000,
      });
      throw error;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Clear error
  const clearError = useCallback(() => {
    setLastError(undefined);
    setConnectionError(undefined);
  }, []);

  // Clear completed operations
  const clearCompleted = useCallback(() => {
    serviceRef.current.clearCompletedOperations();
  }, []);

  // Computed values
  const activeOperations = operations.filter(op => 
    op.status === 'pending' || op.status === 'in_progress'
  );

  return {
    // State
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
    
    // Actions
    refreshShaders,
    refreshImages,
    refreshVideos,
    refreshAll,
    saveShader,
    saveEffectConfig,
    saveOutput,
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
