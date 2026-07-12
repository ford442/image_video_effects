/**
 * Compact storage controls for the main Controls panel.
 * Opens StoragePanel in a modal for browsing.
 */

import React, { useState, useCallback } from 'react';
import { useStorage } from '../../hooks/useStorage';
import { StoragePanel } from './StoragePanel';
import {
  ShaderItem,
  ImageItem,
  VideoItem,
  EffectConfigRecord,
} from '../../services/storage';
import type { SlotParams } from '../../renderer/types';
import './StorageControls.css';

interface StorageControlsPanelProps {
  currentModes?: string[];
  slotParams?: SlotParams[];
  inputSource?: string;
  currentImageUrl?: string;
  activeGenerativeShader?: string;
  onLoadShader?: (shader: ShaderItem, code: string) => void;
  onLoadImage?: (url: string) => void;
  onLoadVideo?: (url: string) => void;
  onLoadEffectConfig?: (config: EffectConfigRecord) => void;
  currentWgslCode?: string;
  currentShaderName?: string;
}

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
    if (name.trim()) onSave(name.trim());
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
            <button type="button" onClick={onClose} disabled={isSaving}>Cancel</button>
            <button type="submit" disabled={!name.trim() || isSaving}>
              {isSaving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export const StorageControlsPanel: React.FC<StorageControlsPanelProps> = ({
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

  const handleSaveShader = useCallback(async (name: string) => {
    if (!currentWgslCode) return;
    setIsSaving(true);
    try {
      await storage.saveShader(name, currentWgslCode, { author: 'Pixelocity User', tags: ['custom'] });
      setShowSaveDialog(false);
    } finally {
      setIsSaving(false);
    }
  }, [currentWgslCode, storage]);

  const handleSelectShader = useCallback(async (shader: ShaderItem) => {
    try {
      const shaderData = await storage.loadShader(shader.filename);
      onLoadShader?.(shader, shaderData.content || '');
      setShowBrowser(false);
    } catch (error) {
      console.error('Failed to load shader:', error);
    }
  }, [storage, onLoadShader]);

  const handleSelectImage = useCallback((image: ImageItem) => {
    onLoadImage?.(image.url);
    setShowBrowser(false);
  }, [onLoadImage]);

  const handleSelectVideo = useCallback((video: VideoItem) => {
    onLoadVideo?.(video.url);
    setShowBrowser(false);
  }, [onLoadVideo]);

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
      <div className="storage-controls-header">
        <h4>💾 VPS Storage</h4>
        {getStatusIndicator()}
      </div>

      {!storage.isConnected && !storage.isCheckingConnection && (
        <div className="connection-warning">
          <span>⚠️ Not connected to VPS</span>
          <button onClick={storage.checkConnection}>Retry</button>
        </div>
      )}

      <div className="storage-buttons">
        <button className="storage-btn primary" onClick={() => setShowBrowser(true)} disabled={!storage.isConnected}>
          <span>📂</span> Browse Storage
        </button>
        <button className="storage-btn" onClick={() => { setSaveDialogType('effect'); setShowSaveDialog(true); }} disabled={!storage.isConnected}>
          <span>💾</span> Save Effect
        </button>
        {currentWgslCode && (
          <button className="storage-btn" onClick={() => { setSaveDialogType('shader'); setShowSaveDialog(true); }} disabled={!storage.isConnected}>
            <span>🎨</span> Save Shader
          </button>
        )}
      </div>

      <div className="storage-stats">
        <div className="stat"><span className="stat-value">{storage.shaders.length}</span><span className="stat-label">Shaders</span></div>
        <div className="stat"><span className="stat-value">{storage.images.length}</span><span className="stat-label">Images</span></div>
        <div className="stat"><span className="stat-value">{storage.videos.length}</span><span className="stat-label">Videos</span></div>
      </div>

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

      {showBrowser && (
        <div className="browser-modal-overlay" onClick={() => setShowBrowser(false)}>
          <div className="browser-modal" onClick={e => e.stopPropagation()}>
            <button className="close-modal" onClick={() => setShowBrowser(false)}>×</button>
            <StoragePanel
              onSelectShader={handleSelectShader}
              onSelectImage={handleSelectImage}
              onSelectVideo={handleSelectVideo}
              onLoadEffectConfig={onLoadEffectConfig}
              initialTab="shaders"
            />
          </div>
        </div>
      )}

      <SaveDialog
        isOpen={showSaveDialog}
        onClose={() => setShowSaveDialog(false)}
        onSave={saveDialogType === 'effect' ? handleSaveEffect : handleSaveShader}
        title={saveDialogType === 'effect' ? 'Save Effect Configuration' : 'Save Shader'}
        defaultName={saveDialogType === 'effect' ? 'my-effect' : currentShaderName}
        isSaving={isSaving}
      />

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

export default StorageControlsPanel;
