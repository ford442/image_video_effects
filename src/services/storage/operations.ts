/**
 * In-memory operation tracking for UI feedback.
 */

import type { StorageOperation, StorageOperationType } from './types';

export class OperationTracker {
  private callbacks = new Set<(ops: StorageOperation[]) => void>();
  private operations: StorageOperation[] = [];
  private readonly maxOperations: number;

  constructor(maxOperations = 50) {
    this.maxOperations = maxOperations;
  }

  add(op: Omit<StorageOperation, 'id' | 'timestamp'>): string {
    const operation: StorageOperation = {
      ...op,
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`,
      timestamp: Date.now(),
    };
    this.operations = [operation, ...this.operations].slice(0, this.maxOperations);
    this.notify();
    return operation.id;
  }

  update(id: string, updates: Partial<StorageOperation>): void {
    this.operations = this.operations.map(op =>
      op.id === id ? { ...op, ...updates } : op
    );
    this.notify();
  }

  wrap<T>(
    type: StorageOperationType,
    itemName: string | undefined,
    startMessage: string,
    fn: () => Promise<T>
  ): Promise<T> {
    const opId = this.add({
      type,
      status: 'in_progress',
      itemName,
      message: startMessage,
    });

    return fn()
      .then(result => {
        this.update(opId, { status: 'completed', message: startMessage.replace('...', ' successfully') });
        return result;
      })
      .catch(error => {
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        this.update(opId, {
          status: 'error',
          message: itemName ? `${itemName}: ${errorMessage}` : errorMessage,
        });
        throw error;
      });
  }

  subscribe(callback: (ops: StorageOperation[]) => void): () => void {
    this.callbacks.add(callback);
    callback([...this.operations]);
    return () => {
      this.callbacks.delete(callback);
    };
  }

  getOperations(): StorageOperation[] {
    return [...this.operations];
  }

  clearCompleted(): void {
    this.operations = this.operations.filter(
      op => op.status === 'pending' || op.status === 'in_progress'
    );
    this.notify();
  }

  pendingCount(): number {
    return this.operations.filter(
      op => op.status === 'pending' || op.status === 'in_progress'
    ).length;
  }

  private notify(): void {
    const snapshot = [...this.operations];
    this.callbacks.forEach(cb => cb(snapshot));
  }
}
