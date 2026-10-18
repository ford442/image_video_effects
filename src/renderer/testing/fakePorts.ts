/**
 * fakePorts.ts — an in-memory, asynchronous postMessage pair for Jest, so
 * the real render-worker host and client can talk without a Worker or
 * MessageChannel (jsdom lacks the latter). Messages are delivered on a
 * macrotask and passed by reference (VideoFrame / bitmap fakes survive).
 */

type Listener = (event: MessageEvent) => void;

export class FakePort {
  peer: FakePort | null = null;
  readonly sent: unknown[] = [];
  terminated = false;
  private readonly listeners: Record<string, Listener[]> = {};

  postMessage(message: unknown): void {
    if (this.terminated) return;
    this.sent.push(message);
    const peer = this.peer;
    setTimeout(() => peer?.dispatch('message', { data: message } as MessageEvent), 0);
  }

  addEventListener(type: string, listener: Listener): void {
    (this.listeners[type] ??= []).push(listener);
  }

  dispatch(type: string, event: MessageEvent): void {
    if (this.terminated) return;
    for (const l of this.listeners[type] ?? []) l(event);
  }

  terminate(): void {
    this.terminated = true;
  }
}

export function createPortPair(): [FakePort, FakePort] {
  const a = new FakePort();
  const b = new FakePort();
  a.peer = b;
  b.peer = a;
  return [a, b];
}

/** Let queued port deliveries and promise continuations run. */
export async function flushPorts(rounds = 4): Promise<void> {
  for (let i = 0; i < rounds; i++) {
    await new Promise((r) => setTimeout(r, 0));
  }
}
