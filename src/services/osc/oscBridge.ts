// ═══════════════════════════════════════════════════════════════════════════════
//  oscBridge.ts  (lazy "osc" chunk)
//  Browsers have no UDP: a local relay (storage_manager /osc/ws) forwards raw OSC
//  datagrams as binary WebSocket frames; we decode + route them here.
// ═══════════════════════════════════════════════════════════════════════════════

import { decodeOscPacket, OscMessage, OscParseError } from './oscPacket';
import { dispatchOscMessage, OscAction, OscActionsHandle } from './oscRouter';

export { decodeOscPacket, encodeOscMessage, encodeOscBundle } from './oscPacket';
export { routeOscMessage, dispatchOscMessage } from './oscRouter';
export type { OscActionsHandle, OscAction } from './oscRouter';

export type OscBridgeStatus = 'connecting' | 'open' | 'closed' | 'error';

export interface OscBridgeOptions {
  url: string;
  /** Read on every message so callers can swap handlers without reconnecting. */
  getHandle: () => OscActionsHandle;
  onStatus?: (status: OscBridgeStatus, detail?: string) => void;
  onMessage?: (msg: OscMessage, action: OscAction | null) => void;
  /** Injectable for tests. */
  WebSocketImpl?: typeof WebSocket;
  minBackoffMs?: number;
  maxBackoffMs?: number;
}

export class OscBridge {
  private ws: WebSocket | null = null;
  private stopped = true;
  private backoff: number;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(private opts: OscBridgeOptions) {
    this.backoff = opts.minBackoffMs ?? 500;
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
    const ws = this.ws;
    this.ws = null;
    if (ws) {
      ws.onopen = ws.onclose = ws.onerror = ws.onmessage = null;
      try { ws.close(); } catch { /* already closed */ }
    }
    this.opts.onStatus?.('closed');
  }

  /** Feed one raw packet (also used by tests / loopback). */
  handlePacket(data: ArrayBuffer | ArrayBufferView): void {
    let messages: OscMessage[];
    try {
      messages = decodeOscPacket(data);
    } catch (err) {
      if (err instanceof OscParseError) {
        console.warn('[OSC] dropped malformed packet:', err.message);
        return;
      }
      throw err;
    }
    const handle = this.opts.getHandle();
    for (const msg of messages) {
      const action = dispatchOscMessage(msg, handle);
      this.opts.onMessage?.(msg, action);
    }
  }

  private connect(): void {
    const Impl = this.opts.WebSocketImpl ?? (typeof WebSocket !== 'undefined' ? WebSocket : undefined);
    if (!Impl) {
      this.opts.onStatus?.('error', 'WebSocket unavailable');
      return;
    }
    this.opts.onStatus?.('connecting');
    let ws: WebSocket;
    try {
      ws = new Impl(this.opts.url);
    } catch (err) {
      this.opts.onStatus?.('error', String(err));
      this.scheduleReconnect();
      return;
    }
    ws.binaryType = 'arraybuffer';
    this.ws = ws;
    ws.onopen = () => {
      this.backoff = this.opts.minBackoffMs ?? 500;
      this.opts.onStatus?.('open');
    };
    ws.onmessage = (ev: MessageEvent) => {
      if (ev.data instanceof ArrayBuffer) this.handlePacket(ev.data);
    };
    ws.onerror = () => this.opts.onStatus?.('error', 'relay unreachable');
    ws.onclose = () => {
      if (this.ws === ws) this.ws = null;
      if (this.stopped) return;
      this.opts.onStatus?.('closed');
      this.scheduleReconnect();
    };
  }

  private scheduleReconnect(): void {
    if (this.stopped) return;
    const delay = this.backoff;
    this.backoff = Math.min(this.opts.maxBackoffMs ?? 10_000, this.backoff * 2);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      if (!this.stopped) this.connect();
    }, delay);
  }
}
