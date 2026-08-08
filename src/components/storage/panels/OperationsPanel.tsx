import React from 'react';

export interface StorageOperationView {
  id: string;
  type: string;
  status: string;
  itemName?: string;
  message?: string;
  timestamp: number;
}

interface OperationsPanelProps {
  operations: StorageOperationView[];
  onClearCompleted: () => void;
}

export const OperationsPanel: React.FC<OperationsPanelProps> = ({
  operations,
  onClearCompleted,
}) => {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending': return '◷';
      case 'in_progress': return '↻';
      case 'completed': return '✓';
      case 'error': return '✕';
      default: return '?';
    }
  };

  const getStatusClass = (status: string) => {
    switch (status) {
      case 'pending': return 'pending';
      case 'in_progress': return 'in-progress';
      case 'completed': return 'completed';
      case 'error': return 'error';
      default: return '';
    }
  };

  const formatTime = (timestamp: number) => new Date(timestamp).toLocaleTimeString();

  return (
    <div className="operations-panel">
      <div className="operations-header">
        <h3>Recent Operations</h3>
        <button onClick={onClearCompleted} className="clear-btn">
          Clear Completed
        </button>
      </div>

      {operations.length === 0 ? (
        <div className="operations-empty">No recent operations</div>
      ) : (
        <div className="operations-list">
          {operations.map(op => (
            <div key={op.id} className={`operation-item ${getStatusClass(op.status)}`}>
              <span className="operation-icon">{getStatusIcon(op.status)}</span>
              <div className="operation-info">
                <span className="operation-type">{op.type}</span>
                {op.itemName && <span className="operation-item-name">{op.itemName}</span>}
                {op.message && <span className="operation-message">{op.message}</span>}
              </div>
              <span className="operation-time">{formatTime(op.timestamp)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
