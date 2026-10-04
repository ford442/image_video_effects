// ═══════════════════════════════════════════════════════════════════════════════
//  oscPacket.ts
//  Minimal OSC 1.0 decoder (messages + bundles). No dependencies, no Node APIs —
//  the browser only ever receives raw datagrams relayed over a WebSocket.
//  Spec: https://opensoundcontrol.stanford.edu/spec-1_0.html
// ═══════════════════════════════════════════════════════════════════════════════

export type OscArg = number | string | boolean | null | Uint8Array;

export interface OscMessage {
  address: string;
  args: OscArg[];
}

export class OscParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OscParseError';
  }
}

const MAX_BUNDLE_DEPTH = 8;

const pad4 = (n: number) => (n + 3) & ~3;

class Reader {
  private offset: number;
  constructor(private view: DataView, start: number, private end: number) {
    this.offset = start;
  }

  get done(): boolean {
    return this.offset >= this.end;
  }

  private need(bytes: number): void {
    if (this.offset + bytes > this.end) {
      throw new OscParseError(`truncated packet at byte ${this.offset} (need ${bytes})`);
    }
  }

  string(): string {
    let nul = this.offset;
    while (nul < this.end && this.view.getUint8(nul) !== 0) nul++;
    if (nul >= this.end) throw new OscParseError('unterminated OSC-string');
    let out = '';
    for (let i = this.offset; i < nul; i++) out += String.fromCharCode(this.view.getUint8(i));
    const next = this.offset + pad4(nul - this.offset + 1);
    if (next > this.end) throw new OscParseError('OSC-string padding past end of packet');
    this.offset = next;
    return decodeUtf8(out);
  }

  int32(): number {
    this.need(4);
    const v = this.view.getInt32(this.offset, false);
    this.offset += 4;
    return v;
  }

  float32(): number {
    this.need(4);
    const v = this.view.getFloat32(this.offset, false);
    this.offset += 4;
    return v;
  }

  float64(): number {
    this.need(8);
    const v = this.view.getFloat64(this.offset, false);
    this.offset += 8;
    return v;
  }

  int64(): number {
    this.need(8);
    const hi = this.view.getInt32(this.offset, false);
    const lo = this.view.getUint32(this.offset + 4, false);
    this.offset += 8;
    return hi * 2 ** 32 + lo;
  }

  blob(): Uint8Array {
    const size = this.int32();
    if (size < 0) throw new OscParseError('negative blob size');
    this.need(pad4(size));
    const bytes = new Uint8Array(this.view.buffer, this.view.byteOffset + this.offset, size).slice();
    this.offset += pad4(size);
    return bytes;
  }

  skip(bytes: number): void {
    this.need(bytes);
    this.offset += bytes;
  }

  get position(): number {
    return this.offset;
  }
}

/** OSC strings are nominally ASCII; tolerate UTF-8 shader ids. */
function decodeUtf8(latin1: string): string {
  if (!/[\x80-\xff]/.test(latin1)) return latin1;
  try {
    const bytes = Uint8Array.from(latin1, (c) => c.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  } catch {
    return latin1;
  }
}

function decodeMessage(view: DataView, start: number, end: number): OscMessage {
  const r = new Reader(view, start, end);
  const address = r.string();
  if (!address.startsWith('/')) throw new OscParseError(`bad address "${address}"`);
  if (r.done) return { address, args: [] }; // tolerate missing type-tag string (old senders)
  const tags = r.string();
  if (!tags.startsWith(',')) throw new OscParseError(`bad type-tag string "${tags}"`);

  const args: OscArg[] = [];
  for (const tag of tags.slice(1)) {
    switch (tag) {
      case 'i': args.push(r.int32()); break;
      case 'f': args.push(r.float32()); break;
      case 'd': args.push(r.float64()); break;
      case 'h': args.push(r.int64()); break;
      case 't': r.skip(8); args.push(null); break; // timetag arg: not meaningful here
      case 's':
      case 'S': args.push(r.string()); break;
      case 'b': args.push(r.blob()); break;
      case 'T': args.push(true); break;
      case 'F': args.push(false); break;
      case 'N': args.push(null); break;
      case 'I': args.push(null); break; // Impulse
      case 'c': args.push(String.fromCharCode(r.int32())); break;
      case 'r': args.push(r.int32() >>> 0); break; // RGBA as uint32
      case 'm': args.push(r.int32() >>> 0); break; // MIDI 4-byte
      case '[':
      case ']': break; // array delimiters: flatten
      default:
        throw new OscParseError(`unsupported type tag "${tag}"`);
    }
  }
  return { address, args };
}

function decodeAt(view: DataView, start: number, end: number, depth: number, out: OscMessage[]): void {
  if (end - start < 4 || (end - start) % 4 !== 0) {
    throw new OscParseError(`packet size ${end - start} is not a positive multiple of 4`);
  }
  // '#bundle\0'
  if (view.getUint8(start) === 0x23) {
    if (depth >= MAX_BUNDLE_DEPTH) throw new OscParseError('bundle nesting too deep');
    const r = new Reader(view, start, end);
    if (r.string() !== '#bundle') throw new OscParseError('bad bundle header');
    r.skip(8); // timetag — Pixelocity applies everything immediately
    while (!r.done) {
      const size = r.int32();
      const elemStart = r.position;
      if (size <= 0 || elemStart + size > end) throw new OscParseError('bad bundle element size');
      decodeAt(view, elemStart, elemStart + size, depth + 1, out);
      r.skip(size);
    }
    return;
  }
  out.push(decodeMessage(view, start, end));
}

/** Decode one OSC packet (message or bundle) into a flat list of messages. */
export function decodeOscPacket(data: ArrayBuffer | ArrayBufferView): OscMessage[] {
  const view = data instanceof ArrayBuffer
    ? new DataView(data)
    : new DataView(data.buffer, data.byteOffset, data.byteLength);
  const out: OscMessage[] = [];
  decodeAt(view, 0, view.byteLength, 0, out);
  return out;
}

// ─── Encoder (tests, loopback, and future "send" support) ──────────────────────

function utf8Bytes(s: string): number[] {
  const out: number[] = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0)!;
    if (cp < 0x80) out.push(cp);
    else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
    else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
  }
  return out;
}

function encodeString(s: string): number[] {
  const bytes = utf8Bytes(s);
  bytes.push(0);
  while (bytes.length % 4) bytes.push(0);
  return bytes;
}

/** Encode a single message. Numbers become `f` unless `ints` marks them as `i`. */
export function encodeOscMessage(address: string, args: Array<number | string | boolean | null> = [], ints: boolean[] = []): Uint8Array {
  let tags = ',';
  const body: number[] = [];
  const dv = new DataView(new ArrayBuffer(4));
  args.forEach((a, i) => {
    if (typeof a === 'number') {
      if (ints[i]) { tags += 'i'; dv.setInt32(0, a, false); } else { tags += 'f'; dv.setFloat32(0, a, false); }
      body.push(...new Uint8Array(dv.buffer));
    } else if (typeof a === 'string') {
      tags += 's';
      body.push(...encodeString(a));
    } else if (a === true) tags += 'T';
    else if (a === false) tags += 'F';
    else tags += 'N';
  });
  return Uint8Array.from([...encodeString(address), ...encodeString(tags), ...body]);
}

/** Encode a bundle (immediate timetag) wrapping already-encoded elements. */
export function encodeOscBundle(elements: Uint8Array[]): Uint8Array {
  const out: number[] = [...encodeString('#bundle'), 0, 0, 0, 0, 0, 0, 0, 1];
  const dv = new DataView(new ArrayBuffer(4));
  for (const el of elements) {
    dv.setInt32(0, el.byteLength, false);
    out.push(...new Uint8Array(dv.buffer), ...el);
  }
  return Uint8Array.from(out);
}
