import React from 'react';
import { DragDropUpload, UploadType } from '../../DragDropUpload';
import { StorageSaveResponse } from '../../../services/storage';

interface StorageUploadPanelProps {
  type: UploadType;
  disabled: boolean;
  onUpload: (
    files: File[],
    type: UploadType,
    onProgress?: (completed: number, total: number) => void,
  ) => Promise<StorageSaveResponse[]>;
}

/** Drag-and-drop upload surface — delegates all network I/O to StorageClient via useStorage. */
export const StorageUploadPanel: React.FC<StorageUploadPanelProps> = ({
  type,
  disabled,
  onUpload,
}) => (
  <DragDropUpload type={type} onUpload={onUpload} disabled={disabled} />
);
