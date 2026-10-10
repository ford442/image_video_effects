/**
 * renderWorkerClient.ts
 *
 * Main-thread transport for the render worker (#1314 WP-1): handshake,
 * fire-and-forget commands, request/reply RPCs and event fan-out. Works over
 * anything with postMessage + message events, so tests can use a
 * MessageChannel port instead of a real Worker.
 */

import {
  RenderCommand,
  RenderEvent,
  RenderRpc,
  RenderRpcResults,
  RenderToWorker,
  RenderWorkerCaps,
  transferablesOf,
} from './protocol';

export interface WorkerLike {
  postMessage(message: unknown, transfer?: Transferable[]): void;
  addEventListener(type: 'message', listener: (event: MessageEvent) => void): void;
  addEventListener(type: 'error', listener: (event: Event) => void): void;
  terminate?(): void;
  close?(): void;
}

type RpcBody<K extends RenderRpc['type']> = Omit<Extract<RenderRpc, { type: K }>, 'requestId'>;

export interface RenderWorkerClient {
  readonly caps: RenderWorkerCaps;
  send(command: RenderCommand): void;
  rpc<K extends RenderRpc['type']>(body: RpcBody<K> & { type: K }, timeoutMs?: number): Promise<RenderRpcResults[K]>;
  onEvent(listener: (event: RenderEvent) => void): () => void;
  /**
   * The worker raised an uncaught error after the handshake. The client treats it as dead
   * (pending RPCs reject, sends are dropped), and so must its owner: the device went with it.
   */
  onDied(listener: (message: string) => void): () => void;
  terminate(): void;
}

export class RenderWorkerHandshakeError extends Error {}

/** Wait for the worker's `hello`, then return a connected client. */
export function connectRenderWorker(worker: WorkerLike, helloTimeoutMs = 3000): Promise<RenderWorkerClient> {
  const listeners = new Set<(event: RenderEvent) => void>();
  const diedListeners = new Set<(message: string) => void>();
  const pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
  let nextId = 1;
  let dead: Error | null = null;

  const failAll = (error: Error) => {
    dead = error;
    for (const { reject } of pending.values()) reject(error);
    pending.clear();
  };

  return new Promise<RenderWorkerClient>((resolve, reject) => {
    let caps: RenderWorkerCaps | null = null;
    const timer = setTimeout(() => {
      if (caps) return;
      failAll(new RenderWorkerHandshakeError('render worker did not say hello'));
      worker.terminate?.();
      reject(dead);
    }, helloTimeoutMs);

    worker.addEventListener('message', (event: MessageEvent) => {
      const data = event.data as RenderEvent;
      if (data.type === 'hello' && !caps) {
        caps = data.caps;
        clearTimeout(timer);
        resolve(client(data.caps));
        return;
      }
      if (dead) return;
      if (data.type === 'rpcResult') {
        const entry = pending.get(data.requestId);
        if (!entry) {
          // Late reply after a timeout: nobody owns a transferred VideoFrame, so close it.
          if (data.ok) closeIfVideoFrame(data.value);
          return;
        }
        pending.delete(data.requestId);
        if (data.ok) entry.resolve(data.value);
        else entry.reject(new Error(data.error));
        return;
      }
      for (const listener of listeners) listener(data);
    });
    worker.addEventListener('error', (event: Event) => {
      if (dead) return;
      const message = (event as ErrorEvent).message || 'render worker failed';
      failAll(new Error(message));
      if (!caps) {
        clearTimeout(timer);
        reject(new RenderWorkerHandshakeError(message));
        return;
      }
      for (const listener of Array.from(diedListeners)) listener(message);
    });
  });

  function post(message: RenderToWorker): void {
    worker.postMessage(message, transferablesOf(message));
  }

  function client(caps: RenderWorkerCaps): RenderWorkerClient {
    return {
      caps,
      send(command) {
        if (!dead) post(command);
      },
      rpc(body, timeoutMs = 60_000) {
        if (dead) return Promise.reject(dead);
        const requestId = nextId++;
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => {
            if (!pending.delete(requestId)) return;
            reject(new Error(`render worker RPC "${body.type}" timed out`));
          }, timeoutMs);
          pending.set(requestId, {
            resolve: (v) => {
              clearTimeout(timer);
              resolve(v as never);
            },
            reject: (e) => {
              clearTimeout(timer);
              reject(e);
            },
          });
          post({ ...body, requestId } as RenderRpc);
        });
      },
      onEvent(listener) {
        listeners.add(listener);
        return () => listeners.delete(listener);
      },
      onDied(listener) {
        diedListeners.add(listener);
        return () => diedListeners.delete(listener);
      },
      terminate() {
        failAll(new Error('render worker terminated'));
        listeners.clear();
        diedListeners.clear();
        worker.terminate?.();
        worker.close?.();
      },
    };
  }
}

function closeIfVideoFrame(value: unknown): void {
  if (typeof VideoFrame !== 'undefined' && value instanceof VideoFrame) value.close();
}
