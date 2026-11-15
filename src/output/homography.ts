/**
 * homography.ts — four-corner pin math for stage outputs (projection mapping).
 *
 * A corner pin maps the unit square (program texture UV, Y-down) onto a quad
 * whose four corners the operator drags in output UV space. The present pass
 * needs the opposite direction — for each output pixel, which program UV it
 * shows — so the shader receives the inverse matrix.
 *
 * Corner order everywhere: top-left, top-right, bottom-right, bottom-left
 * (program UV (0,0), (1,0), (1,1), (0,1)).
 *
 * Closed form from Heckbert, "Fundamentals of Texture Mapping and Image
 * Warping" (1989), §2.2.3: square → quadrilateral without a linear solve.
 */

export type Vec2 = readonly [number, number];
export type Quad = readonly [Vec2, Vec2, Vec2, Vec2];
/** Row-major 3×3: [a b c; d e f; g h i]. */
export type Mat3 = readonly [number, number, number, number, number, number, number, number, number];

export const IDENTITY_QUAD: Quad = [[0, 0], [1, 0], [1, 1], [0, 1]];
export const IDENTITY_MAT3: Mat3 = [1, 0, 0, 0, 1, 0, 0, 0, 1];

const EPS = 1e-12;

/**
 * The projective map taking (0,0)→q[0], (1,0)→q[1], (1,1)→q[2], (0,1)→q[3].
 * Null when the quad is degenerate (three corners collinear in a way that
 * leaves no projective solution).
 */
export function squareToQuad(q: Quad): Mat3 | null {
  const [[x0, y0], [x1, y1], [x2, y2], [x3, y3]] = q;
  const dx3 = x0 - x1 + x2 - x3;
  const dy3 = y0 - y1 + y2 - y3;
  let g = 0;
  let h = 0;
  if (Math.abs(dx3) > EPS || Math.abs(dy3) > EPS) {
    const dx1 = x1 - x2;
    const dx2 = x3 - x2;
    const dy1 = y1 - y2;
    const dy2 = y3 - y2;
    const den = dx1 * dy2 - dx2 * dy1;
    if (Math.abs(den) < EPS) return null;
    g = (dx3 * dy2 - dx2 * dy3) / den;
    h = (dx1 * dy3 - dx3 * dy1) / den;
  }
  const m: Mat3 = [
    x1 - x0 + g * x1, x3 - x0 + h * x3, x0,
    y1 - y0 + g * y1, y3 - y0 + h * y3, y0,
    g, h, 1,
  ];
  return Math.abs(det3(m)) < EPS ? null : m;
}

export function det3(m: Mat3): number {
  const [a, b, c, d, e, f, g, h, i] = m;
  return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
}

export function invert3(m: Mat3): Mat3 | null {
  const [a, b, c, d, e, f, g, h, i] = m;
  const det = det3(m);
  if (Math.abs(det) < EPS) return null;
  const k = 1 / det;
  return [
    (e * i - f * h) * k, (c * h - b * i) * k, (b * f - c * e) * k,
    (f * g - d * i) * k, (a * i - c * g) * k, (c * d - a * f) * k,
    (d * h - e * g) * k, (b * g - a * h) * k, (a * e - b * d) * k,
  ];
}

/** Apply a homography to a point; null at (or behind) the line at infinity. */
export function applyMat3(m: Mat3, p: Vec2): Vec2 | null {
  const [a, b, c, d, e, f, g, h, i] = m;
  const w = g * p[0] + h * p[1] + i;
  if (Math.abs(w) < EPS) return null;
  return [(a * p[0] + b * p[1] + c) / w, (d * p[0] + e * p[1] + f) / w];
}

/**
 * Output UV → program UV for a corner pin (what the present pass evaluates per
 * pixel). Normalised so the bottom-right entry is positive: the shader treats
 * w <= 0 as "behind the projector" and shows black there.
 */
export function cornerPinInverse(q: Quad): Mat3 | null {
  const fwd = squareToQuad(q);
  if (!fwd) return null;
  const inv = invert3(fwd);
  if (!inv) return null;
  // Scale so that w > 0 inside the quad (w at the quad's centroid is positive).
  const cx = (q[0][0] + q[1][0] + q[2][0] + q[3][0]) / 4;
  const cy = (q[0][1] + q[1][1] + q[2][1] + q[3][1]) / 4;
  const w = inv[6] * cx + inv[7] * cy + inv[8];
  if (Math.abs(w) < EPS) return null;
  const s = 1 / w;
  return inv.map((v) => v * s) as unknown as Mat3;
}

/**
 * True when the quad is strictly convex with a consistent winding. Corner pins
 * of a real flat surface always are; a bow-tie (two corners swapped) is the
 * classic mis-drag and folds the picture over itself.
 */
export function isConvexQuad(q: Quad): boolean {
  let sign = 0;
  for (let i = 0; i < 4; i++) {
    const a = q[i] ?? q[0];
    const b = q[(i + 1) % 4] ?? q[0];
    const c = q[(i + 2) % 4] ?? q[0];
    const cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
    if (Math.abs(cross) < EPS) return false;
    const s = Math.sign(cross);
    if (sign === 0) sign = s;
    else if (s !== sign) return false;
  }
  return true;
}
