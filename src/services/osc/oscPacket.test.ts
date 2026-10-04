import { decodeOscPacket, encodeOscBundle, encodeOscMessage, OscParseError } from './oscPacket';

const bytes = (...parts: Array<string | number[]>) => {
  const out: number[] = [];
  for (const p of parts) {
    if (typeof p === 'string') for (const c of p) out.push(c.charCodeAt(0));
    else out.push(...p);
  }
  return Uint8Array.from(out);
};

describe('decodeOscPacket', () => {
  it('decodes a hand-built float message', () => {
    // "/a\0\0" ",f\0\0" 0x3F000000 (0.5)
    const pkt = bytes('/a', [0, 0], ',f', [0, 0], [0x3f, 0, 0, 0]);
    expect(decodeOscPacket(pkt)).toEqual([{ address: '/a', args: [0.5] }]);
  });

  it('handles 4-byte string padding at exact boundaries', () => {
    // "/abc" is 4 chars → needs a full 4 bytes of NUL padding
    const pkt = bytes('/abc', [0, 0, 0, 0], ',i', [0, 0], [0xff, 0xff, 0xff, 0xfe]);
    expect(decodeOscPacket(pkt)).toEqual([{ address: '/abc', args: [-2] }]);
  });

  it('round-trips f / i / s / T / F / N', () => {
    const enc = encodeOscMessage('/pixelocity/x', [0.25, 7, 'neon-grid', true, false, null], [false, true]);
    expect(enc.byteLength % 4).toBe(0);
    expect(decodeOscPacket(enc)).toEqual([
      { address: '/pixelocity/x', args: [0.25, 7, 'neon-grid', true, false, null] },
    ]);
  });

  it('decodes a blob and a double', () => {
    const pkt = bytes('/b', [0, 0], ',bd', [0], [0, 0, 0, 3], [1, 2, 3, 0], [0x3f, 0xf0, 0, 0, 0, 0, 0, 0]);
    const [msg] = decodeOscPacket(pkt);
    expect(Array.from(msg.args[0] as Uint8Array)).toEqual([1, 2, 3]);
    expect(msg.args[1]).toBe(1);
  });

  it('flattens nested bundles in order', () => {
    const inner = encodeOscBundle([encodeOscMessage('/two', [2])]);
    const outer = encodeOscBundle([encodeOscMessage('/one', [1]), inner, encodeOscMessage('/three', ['3'])]);
    expect(decodeOscPacket(outer).map(m => m.address)).toEqual(['/one', '/two', '/three']);
  });

  it('accepts a DataView/typed array offset into a larger buffer', () => {
    const msg = encodeOscMessage('/o', [1]);
    const big = new Uint8Array(msg.byteLength + 8);
    big.set(msg, 4);
    expect(decodeOscPacket(big.subarray(4, 4 + msg.byteLength))[0].address).toBe('/o');
  });

  it.each([
    ['empty', new Uint8Array(0)],
    ['not multiple of 4', bytes('/a', [0])],
    ['unterminated string', bytes('/abc')],
    ['truncated float', bytes('/a', [0, 0], ',f', [0, 0])],
    ['bad address', bytes('xx', [0, 0], ',', [0, 0, 0])],
    ['unknown tag', bytes('/a', [0, 0], ',q', [0, 0])],
    ['bundle element overruns', Uint8Array.from([...encodeOscBundle([]), 0, 0, 0, 64])],
  ])('throws OscParseError on %s', (_label, pkt) => {
    expect(() => decodeOscPacket(pkt)).toThrow(OscParseError);
  });

  it('rejects absurd bundle nesting', () => {
    let pkt = encodeOscMessage('/deep', []);
    for (let i = 0; i < 10; i++) pkt = encodeOscBundle([pkt]);
    expect(() => decodeOscPacket(pkt)).toThrow(/too deep/);
  });
});
