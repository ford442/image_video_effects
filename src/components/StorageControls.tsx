// ═══════════════════════════════════════════════════════════════════════════════
//  StorageControls.tsx
//  Storage management controls for integration into the main Controls panel
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useCallback } from 'react';
import { useStorage } from '../hooks/useStorage';
import { StorageBrowser } from './StorageBrowser';
import { ShaderItem, ImageItem, VideoItem } from '../services/StorageService';
import './StorageControls.css';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

interface StorageControlsProps {
  // Current state for saving
  currentModes?: string[];
  slotParams?: any[];
  inputSource?: string;
  currentImageUrl?: string;
  activeGenerativeShader?: string;
  
  // Callbacks for loading
  onLoadShader?: (shader: ShaderItem, code: string) => void;
  onLoadImage?: (url: string) => void;
  onLoadVideo?: (url: string) => void;
  onLoadEffectConfig?: (config: any) => void;
  
  // WGSL code for saving (if editing a shader)
  currentWgslCode?: string;
  currentShaderName?: string;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Save Dialog Component
// ═══════════════════════════════════════════════════════════════════════════════

interface SaveDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (name: string) => void;
  title: string;
  defaultName?: string;
  isSaving?: boolean;
}

const SaveDialog: React.FC<SaveDialogProps> = ({
  isOpen,
  onClose,
  onSave,
  title,
  defaultName = '',
  isSaving = false,
}) => {
  const [name, setName] = useState(defaultName);
  
  if (!isOpen) return null;
  
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (name.trim()) {
      onSave(name.trim());
    }
  };
  
  return (
    <div className="save-dialog-overlay" onClick={onClose}>
      <div className="save-dialog" onClick={e => e.stopPropagation()}>
        <h3>{title}</h3>
        <form onSubmit={handleSubmit}>
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="Enter name..."
            autoFocus
            disabled={isSaving}
          />
          <div className="dialog-buttons">
            <button type="button" onClick={onClose} disabled={isSaving}>
              Cancel
            </button>
            <button type="submit" disabled={!name.trim() || isSaving}>
              {isSaving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Main Storage Controls Component
// ═══════════════════════════════════════════════════════════════════════════════

export const StorageControls: React.FC<StorageControlsProps> = ({
  currentModes = ['none', 'none', 'none'],
  slotParams = [],
  inputSource = 'image',
  currentImageUrl,
  activeGenerativeShader,
  onLoadShader,
  onLoadImage,
  onLoadVideo,
  onLoadEffectConfig,
  currentWgslCode,
  currentShaderName = 'custom-shader',
}) => {
  const storage = useStorage();
  const [showBrowser, setShowBrowser] = useState(false);
  const [showSaveDialog, setShowSaveDialog] = useState(false);
  const [saveDialogType, setSaveDialogType] = useState<'effect' | 'shader'>('effect');
  const [isSaving, setIsSaving] = useState(false);
  
  // Handle save effect configuration
  const handleSaveEffect = useCallback(async (name: string) => {
    setIsSaving(true);
    try {
      await storage.saveEffectConfig(name, {
        modes: currentModes,
        slotParams,
        inputSource,
        currentImageUrl,
        activeGenerativeShader,
      });
      setShowSaveDialog(false);
    } finally {
      setIsSaving(false);
    }
  }, [currentModes, slotParams, inputSource, currentImageUrl, activeGenerativeShader, storage]);
  
  // Handle save shader
  const handleSaveShader = useCallback(async (name: string) => {
    if (!currentWgslCode) return;
    setIsSaving(true);
    try {
      await storage.saveShader(name, currentWgslCode, {
        author: 'Pixelocity User',
        tags: ['custom'],
      });
      setShowSaveDialog(false);
    } finally {
      setIsSaving(false);
    }
  }, [currentWgslCode, storage]);
  
  // Handle shader selection from browser
  const handleSelectShader = useCallback(async (shader: ShaderItem) => {
    try {
      const shaderData = await storage.loadShader(shader.filename);
      onLoadShader?.(shader, shaderData.content || shaderData.data?.wgsl_code || '');
      setShowBrowser(false);
    } catch (error) {
      console.error('Failed to load shader:', error);
    }
  }, [storage, onLoadShader]);
  
  // Handle image selection
  const handleSelectImage = useCallback((image: ImageItem) => {
    onLoadImage?.(image.url);
    setShowBrowser(false);
  }, [onLoadImage]);
  
  // Handle video selection
  const handleSelectVideo = useCallback((video: VideoItem) => {
    onLoadVideo?.(video.url);
    setShowBrowser(false);
  }, [onLoadVideo]);
  
  // Open save dialog for effect
  const openSaveEffectDialog = () => {
    setSaveDialogType('effect');
    setShowSaveDialog(true);
  };
  
  // Open save dialog for shader
  const openSaveShaderDialog = () => {
    if (!currentWgslCode) {
      alert('No shader code to save. Please create or edit a shader first.');
      return;
    }
    setSaveDialogType('shader');
    setShowSaveDialog(true);
  };
  
  // Status indicator
  const getStatusIndicator = () => {
    if (storage.isCheckingConnection) {
      return <span className="status-indicator checking" title="Checking connection...">⏳</span>;
    }
    if (storage.isConnected) {
      return <span className="status-indicator connected" title="Connected to VPS">✅</span>;
    }
    return <span className="status-indicator error" title="Not connected">❌</span>;
  };
  
  return (
    <div className="storage-controls">
      {/* Header */}
      <div className="storage-controls-header">
        <h4>💾 VPS Storage</h4>
        {getStatusIndicator()}
      </div>
      
      {/* Connection warning */}
      {!storage.isConnected && !storage.isCheckingConnection && (
        <div className="connection-warning">
          <span>⚠️ Not connected to VPS</span>
          <button onClick={storage.checkConnection}>Retry</button>
        </div>
      )}
      
      {/* Main buttons */}
      <div className="storage-buttons">
        <button 
          className="storage-btn primary"
          onClick={() => setShowBrowser(true)}
          disabled={!storage.isConnected}
        >
          <span>📂</span> Browse Storage
        </button>
        
        <button 
          className="storage-btn"
          onClick={openSaveEffectDialog}
          disabled={!storage.isConnected}
        >
          <span>💾</span> Save Effect
        </button>
        
        {currentWgslCode && (
          <button 
            className="storage-btn"
            onClick={openSaveShaderDialog}
            disabled={!storage.isConnected}
          >
            <span>🎨</span> Save Shader
          </button>
        )}
      </div>
      
      {/* Quick stats */}
      <div className="storage-stats">
        <div className="stat">
          <span className="stat-value">{storage.shaders.length}</span>
          <span className="stat-label">Shaders</span>
        </div>
        <div className="stat">
          <span className="stat-value">{storage.images.length}</span>
          <span className="stat-label">Images</span>
        </div>
        <div className="stat">
          <span className="stat-value">{storage.videos.length}</span>
          <span className="stat-label">Videos</span>
        </div>
      </div>
      
      {/* Active operations */}
      {storage.activeOperations.length > 0 && (
        <div className="active-operations">
          <h5>Active Operations</h5>
          {storage.activeOperations.map(op => (
            <div key={op.id} className={`operation ${op.status}`}>
              <span className="operation-spinner">🔄</span>
              <span className="operation-text">{op.message || op.type}</span>
            </div>
          ))}
        </div>
      )}
      
      {/* Storage Browser Modal */}
      {showBrowser && (
        <div className="browser-modal-overlay" onClick={() => setShowBrowser(false)}>
          <div className="browser-modal" onClick={e => e.stopPropagation()}>
            <button className="close-modal" onClick={() => setShowBrowser(false)}>
              ×
            </button>
            <StorageBrowser
              onSelectShader={handleSelectShader}
              onSelectImage={handleSelectImage}
              onSelectVideo={handleSelectVideo}
              onLoadEffectConfig={onLoadEffectConfig}
              initialTab="shaders"
            />
          </div>
        </div>
      )}
      
      {/* Save Dialog */}
      <SaveDialog
        isOpen={showSaveDialog}
        onClose={() => setShowSaveDialog(false)}
        onSave={saveDialogType === 'effect' ? handleSaveEffect : handleSaveShader}
        title={saveDialogType === 'effect' ? 'Save Effect Configuration' : 'Save Shader'}
        defaultName={saveDialogType === 'effect' ? 'my-effect' : currentShaderName}
        isSaving={isSaving}
      />
      
      {/* Toast notifications */}
      <div className="storage-toasts">
        {storage.toasts.map(toast => (
          <div key={toast.id} className={`toast ${toast.type}`}>
            <span>{toast.message}</span>
            <button onClick={() => storage.dismissToast(toast.id)}>×</button>
          </div>
        ))}
      </div>
    </div>
  );
};

export default StorageControls;
