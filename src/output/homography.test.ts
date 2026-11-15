import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import type { NagaValidator } from '../utils/nagaWasm';
import {
  applyMat3,
  cornerPinInverse,
  IDENTITY_QUAD,
  invert3,
  isConvexQuad,
  squareToQuad,
  type Mat3,
  type Quad,
  type Vec2,
} from './homography';

const close = (a: Vec2 | null, b: Vec2) => {
  expect(a).not.toBeNull();
  expect(a?.[0]).toBeCloseTo(b[0], 9);
  expect(a?.[1]).toBeCloseTo(b[1], 9);
};

const SQUARE: Quad = IDENTITY_QUAD;
const KEYSTONE: Quad = [[0.1, 0.05], [0.92, 0.0], [1.0, 0.97], [0.02, 0.88]];
const TRAPEZOID: Quad = [[0.3, 0.1], [0.7, 0.1], [1, 0.9], [0, 0.9]];

describe('squareToQuad', () => {
  it('is the identity for the unit square', () => {
    const m = squareToQuad(SQUARE);
    expect(m).not.toBeNull();
    for (const p of [[0.25, 0.75], [0.5, 0.5], [1, 0]] as Vec2[]) close(applyMat3(m as Mat3, p), p);
  });

  it.each([['keystone', KEYSTONE], ['trapezoid', TRAPEZOID], ['affine', [[0.1, 0.1], [0.6, 0.2], [0.7, 0.7], [0.2, 0.6]] as Quad]])(
    'maps the unit square corners onto the %s quad',
    (_name, q) => {
      const m = squareToQuad(q as Quad);
      expect(m).not.toBeNull();
      const src: Vec2[] = [[0, 0], [1, 0], [1, 1], [0, 1]];
      src.forEach((p, i) => close(applyMat3(m as Mat3, p), (q as Quad)[i] as Vec2));
    },
  );

  it('keeps straight lines straight (projective, not bilinear)', () => {
    const m = squareToQuad(TRAPEZOID) as Mat3;
    const a = applyMat3(m, [0, 0.5]) as Vec2;
    const b = applyMat3(m, [1, 0.5]) as Vec2;
    const mid = applyMat3(m, [0.5, 0.5]) as Vec2;
    // mid lies on segment a–b
    const cross = (b[0] - a[0]) * (mid[1] - a[1]) - (b[1] - a[1]) * (mid[0] - a[0]);
    expect(Math.abs(cross)).toBeLessThan(1e-9);
    // …but not at its midpoint: perspective foreshortening.
    expect(mid[1]).not.toBeCloseTo((a[1] + b[1]) / 2 + 0.05, 3);
  });

  it('returns null for a collapsed quad', () => {
    expect(squareToQuad([[0, 0], [1, 0], [2, 0], [3, 0]])).toBeNull();
    expect(squareToQuad([[0.5, 0.5], [0.5, 0.5], [0.5, 0.5], [0.5, 0.5]])).toBeNull();
  });
});

describe('cornerPinInverse', () => {
  it('maps the output-space corners back to program UV', () => {
    const inv = cornerPinInverse(KEYSTONE) as Mat3;
    expect(inv).not.toBeNull();
    close(applyMat3(inv, KEYSTONE[0]), [0, 0]);
    close(applyMat3(inv, KEYSTONE[1]), [1, 0]);
    close(applyMat3(inv, KEYSTONE[2]), [1, 1]);
    close(applyMat3(inv, KEYSTONE[3]), [0, 1]);
  });

  it('has w > 0 everywhere inside the quad (the shader blacks out w <= 0)', () => {
    const inv = cornerPinInverse(TRAPEZOID) as Mat3;
    for (let i = 0; i <= 10; i++) {
      for (let j = 0; j <= 10; j++) {
        const fwd = squareToQuad(TRAPEZOID) as Mat3;
        const p = applyMat3(fwd, [i / 10, j / 10]) as Vec2;
        const w = inv[6] * p[0] + inv[7] * p[1] + inv[8];
        expect(w).toBeGreaterThan(0);
      }
    }
  });

  it('round-trips through invert3', () => {
    const m = squareToQuad(KEYSTONE) as Mat3;
    const back = invert3(invert3(m) as Mat3) as Mat3;
    m.forEach((v, i) => expect(back[i]).toBeCloseTo(v, 9));
  });
});

describe('isConvexQuad', () => {
  it('accepts real surfaces and rejects a bow-tie', () => {
    expect(isConvexQuad(SQUARE)).toBe(true);
    expect(isConvexQuad(KEYSTONE)).toBe(true);
    // Swap TR and BR: the classic mis-drag.
    expect(isConvexQuad([[0, 0], [1, 1], [1, 0], [0, 1]])).toBe(false);
    // A dart (one corner pushed inside).
    expect(isConvexQuad([[0, 0], [1, 0], [0.3, 0.3], [0, 1]])).toBe(false);
  });
});

describe('_output/corner_pin.wgsl', () => {
  let naga: NagaValidator;
  const ROOT = path.resolve(__dirname, '../..');
  beforeAll(async () => {
    const loader = (await import(pathToFileURL(path.join(ROOT, 'public/wasm/naga_wasm.js')).href)) as {
      createNagaValidator(o: { bytes: BufferSource }): Promise<NagaValidator>;
    };
    naga = await loader.createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, 'public/wasm/naga_wasm.wasm')) });
  });

  it('validates under naga', () => {
    const src = fs.readFileSync(path.join(ROOT, 'public/shaders/_output/corner_pin.wgsl'), 'utf8');
    const r = naga.validate(src);
    expect(r.ok, r.message).toBe(true);
  });

  it('declares the 80-byte OutputParams packOutputUniform writes', () => {
    const src = fs.readFileSync(path.join(ROOT, 'public/shaders/_output/corner_pin.wgsl'), 'utf8');
    const body = /struct OutputParams \{([\s\S]*?)\};/.exec(src)?.[1] ?? '';
    expect(body.match(/vec4<f32>/g)?.length).toBe(5);
  });
});
