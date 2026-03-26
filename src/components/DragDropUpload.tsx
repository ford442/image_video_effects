// ═══════════════════════════════════════════════════════════════════════════════
//  DragDropUpload.tsx
//  Drag-and-drop file upload component with gold glass styling
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useCallback } from 'react';
import { StorageSaveResponse } from '../services/StorageService';
import './DragDropUpload.css';

export type UploadType = 'image' | 'video' | 'audio' | 'shader';

interface DragDropUploadProps {
  type: UploadType;
  onUpload: (files: File[], type: UploadType, onProgress?: (completed: number, total: number) => void) => Promise<StorageSaveResponse[]>;
  accept?: string;
  multiple?: boolean;
  disabled?: boolean;
}

export const DragDropUpload: React.FC<DragDropUploadProps> = ({
  type,
  onUpload,
  accept,
  multiple = true,
  disabled = false,
}) => {
  const [isDragging, setIsDragging] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState({ completed: 0, total: 0 });

  // Determine accepted file types based on upload type
  const getAcceptTypes = (): string => {
    if (accept) return accept;
    
    switch (type) {
      case 'image':
        return 'image/*,.png,.jpg,.jpeg,.webp,.gif';
      case 'video':
        return 'video/*,.mp4,.webm,.mov,.avi';
      case 'audio':
        return 'audio/*,.mp3,.wav,.flac,.ogg';
      case 'shader':
        return '.wgsl,.glsl,.json';
      default:
        return '*';
    }
  };

  // Get label based on type
  const getTypeLabel = (): string => {
    switch (type) {
      case 'image': return 'images';
      case 'video': return 'videos';
      case 'audio': return 'audio files';
      case 'shader': return 'shaders';
      default: return 'files';
    }
  };

  // Handle drag enter
  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);

  // Handle drag leave
  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);

  // Handle drag over
  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  }, []);

  // Handle drop
  const handleDrop = useCallback(async (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (disabled || isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    if (files.length === 0) return;

    // Filter files by type if needed
    const acceptedFiles = filterFilesByType(files, type);
    if (acceptedFiles.length === 0) {
      alert(`Please drop valid ${getTypeLabel()} files.`);
      return;
    }

    await uploadFiles(acceptedFiles);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [disabled, isUploading, type, getTypeLabel]);

  // Handle file input change
  const handleFileInput = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length === 0) return;

    await uploadFiles(files);
    
    // Reset input
    e.target.value = '';
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Filter files by type
  const filterFilesByType = useCallback((files: File[], uploadType: UploadType): File[] => {
    const typeMap: Record<UploadType, string[]> = {
      image: ['image/'],
      video: ['video/'],
      audio: ['audio/'],
      shader: ['application/json', 'text/plain', 'application/octet-stream'],
    };

    const allowedTypes = typeMap[uploadType];
    if (!allowedTypes) return files;

    return files.filter(file => {
      // Check MIME type
      const mimeMatch = allowedTypes.some(type => 
        file.type.startsWith(type) || file.type === type
      );
      
      // Also check extension for shaders
      if (uploadType === 'shader') {
        const ext = file.name.split('.').pop()?.toLowerCase();
        if (ext === 'wgsl' || ext === 'glsl' || ext === 'json') return true;
      }
      
      return mimeMatch;
    });
  }, []);

  // Upload files
  const uploadFiles = useCallback(async (files: File[]) => {
    setIsUploading(true);
    setUploadProgress({ completed: 0, total: files.length });

    try {
      await onUpload(files, type, (completed, total) => {
        setUploadProgress({ completed, total });
      });
    } catch (error) {
      console.error('Upload error:', error);
    } finally {
      setIsUploading(false);
      setUploadProgress({ completed: 0, total: 0 });
    }
  }, [onUpload, type]);

  return (
    <div
      className={`drag-drop-zone ${isDragging ? 'dragging' : ''} ${isUploading ? 'uploading' : ''} ${disabled ? 'disabled' : ''}`}
      onDragEnter={handleDragEnter}
      onDragLeave={handleDragLeave}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      <input
        type="file"
        id={`file-upload-${type}`}
        className="file-input"
        accept={getAcceptTypes()}
        multiple={multiple}
        onChange={handleFileInput}
        disabled={disabled || isUploading}
      />
      
      <label htmlFor={`file-upload-${type}`} className="upload-label">
        {isUploading ? (
          <div className="upload-progress">
            <div className="spinner" />
            <span className="progress-text">
              Uploading {uploadProgress.completed} of {uploadProgress.total}...
            </span>
            <div className="progress-bar">
              <div 
                className="progress-fill"
                style={{ 
                  width: `${uploadProgress.total > 0 ? (uploadProgress.completed / uploadProgress.total) * 100 : 0}%` 
                }}
              />
            </div>
          </div>
        ) : (
          <>
            <div className="upload-icon">
              {isDragging ? '↙' : '↑'}
            </div>
            <div className="upload-text">
              {isDragging ? (
                <span>Drop {getTypeLabel()} here</span>
              ) : (
                <>
                  <span className="primary-text">Drag & drop {getTypeLabel()} here</span>
                  <span className="secondary-text">or click to browse</span>
                </>
              )}
            </div>
            <div className="upload-formats">
              Supported: {getAcceptTypes().replace(/\*\/?/g, '').replace(/,/g, ', ')}
            </div>
          </>
        )}
      </label>
    </div>
  );
};

export default DragDropUpload;
