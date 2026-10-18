/**
 * @vitest-environment node
 */
import { CICP_PRIMARIES_DISPLAY_P3, CICP_TRANSFER_SRGB, tagWebmDisplayP3 } from './webmColour';

/** Matroska Colour element exactly as webm-muxer 5.1.4 lays it out: 55B0 + 4-byte size, 4 one-byte uints. */
function colourBytes(primaries = 6, transfer = 6): number[] {
  return [
    0x55, 0xb0, 0x10, 0x00, 0x00, 0x10,
    0x55, 0xb1, 0x81, 6, // MatrixCoefficients
    0x55, 0xba, 0x81, transfer, // TransferCharacteristics
    0x55, 0xbb, 0x81, primaries, // Primaries
    0x55, 0xb9, 0x81, 1, // Range
  ];
}

function withColour(colour: number[], pad = 300): ArrayBuffer {
  const bytes = new Uint8Array([...new Array(pad).fill(0xec), ...colour, 0x1f, 0x43, 0xb6, 0x75]);
  return bytes.buffer;
}

describe('tagWebmDisplayP3', () => {
  it('rewrites primaries and transfer in place and leaves matrix/range alone', () => {
    const buf = withColour(colourBytes());
    const before = new Uint8Array(buf.slice(0));
    expect(tagWebmDisplayP3(buf)).toBe(true);
    const after = new Uint8Array(buf);
    const diff = [...after].map((b, i) => (b === before[i] ? -1 : i)).filter((i) => i >= 0);
    expect(diff).toHaveLength(2);
    expect(after[300 + 13]).toBe(CICP_TRANSFER_SRGB);
    expect(after[300 + 17]).toBe(CICP_PRIMARIES_DISPLAY_P3);
    expect(after[300 + 9]).toBe(6);
    expect(after[300 + 21]).toBe(1);
    expect(after.length).toBe(before.length);
  });

  it('is idempotent', () => {
    const buf = withColour(colourBytes(CICP_PRIMARIES_DISPLAY_P3, CICP_TRANSFER_SRGB));
    const before = new Uint8Array(buf.slice(0));
    expect(tagWebmDisplayP3(buf)).toBe(true);
    expect(new Uint8Array(buf)).toEqual(before);
  });

  it('returns false and changes nothing when there is no Colour element', () => {
    const buf = new Uint8Array(512).fill(0x20).buffer;
    const before = new Uint8Array(buf.slice(0));
    expect(tagWebmDisplayP3(buf)).toBe(false);
    expect(new Uint8Array(buf)).toEqual(before);
  });

  it('returns false for a Colour element without the primaries/transfer children', () => {
    const buf = withColour([0x55, 0xb0, 0x84, 0x55, 0xb1, 0x81, 6]);
    const before = new Uint8Array(buf.slice(0));
    expect(tagWebmDisplayP3(buf)).toBe(false);
    expect(new Uint8Array(buf)).toEqual(before);
  });

  it('patches the bytes the real muxer writes', async () => {
    const { Muxer, ArrayBufferTarget } = await vi.importActual<typeof import('webm-muxer')>('webm-muxer');
    class FakeChunk {
      type = 'key';
      timestamp = 0;
      duration = 33_333;
      byteLength = 20;
      copyTo(d: Uint8Array) { d.fill(0); }
    }
    (global as Record<string, unknown>).EncodedVideoChunk = FakeChunk;
    const muxer = new Muxer({
      target: new ArrayBufferTarget(),
      video: { codec: 'V_VP9', width: 64, height: 64, frameRate: 30 },
      firstTimestampBehavior: 'offset',
    });
    muxer.addVideoChunk(new FakeChunk() as unknown as EncodedVideoChunk, {
      decoderConfig: {
        codec: 'vp09.00.10.08',
        colorSpace: { matrix: 'smpte170m', primaries: 'smpte170m', transfer: 'smpte170m', fullRange: false },
      },
    });
    muxer.finalize();
    const buf: ArrayBuffer = muxer.target.buffer;
    expect(tagWebmDisplayP3(buf)).toBe(true);
    const bytes = new Uint8Array(buf);
    let at = -1;
    for (let i = 0; i < bytes.length - 1; i++) if (bytes[i] === 0x55 && bytes[i + 1] === 0xb0) { at = i; break; }
    expect([...bytes.slice(at + 6, at + 22)]).toEqual([
      0x55, 0xb1, 0x81, 6,
      0x55, 0xba, 0x81, CICP_TRANSFER_SRGB,
      0x55, 0xbb, 0x81, CICP_PRIMARIES_DISPLAY_P3,
      0x55, 0xb9, 0x81, 1,
    ]);
  });
});
