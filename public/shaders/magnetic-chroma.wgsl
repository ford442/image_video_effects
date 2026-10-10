// ═══════════════════════════════════════════════════════════════════
//  Magnetic Chroma
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: per-channel RK2 field-line smear; compass hue (field angle → hue wheel); true N/S pole pair around the cursor
//  A packing: raw field record (fieldStrength, influence, chromaticSep, alpha) — HEAD packing kept; C is not read
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Half-separation of the N/S pole pair, aspect space (set once per invocation)
var<private> gPoleOffset: vec2<f32> = vec2<f32>(0.05, 0.0);

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let fw = f * f * (3.0 - 2.0 * f);
  let n = mix(
    mix(hash22(i + vec2<f32>(0.0, 0.0)).x, hash22(i + vec2<f32>(1.0, 0.0)).x, fw.x),
    mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, fw.x),
    fw.y
  );
  return n;
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let v = max(c.r, max(c.g, c.b));
  let minc = min(c.r, min(c.g, c.b));
  let s = select(0.0, (v - minc) / v, v > 0.0);
  let d = v - minc;
  var h = 0.0;
  if (d <= 1e-6) {
    // Floor fix: greys have no hue — HEAD divided by d = 0 here (NaN)
    h = 0.0;
  } else if (c.r == v) {
    h = (c.g - c.b) / d;
  } else if (c.g == v) {
    h = (c.b - c.r) / d + 2.0;
  } else {
    h = (c.r - c.g) / d + 4.0;
  }
  return vec3<f32>(fract(h / 6.0), s, v);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let h = c.x * 6.0;
  let i = floor(h);
  let f = h - i;
  let p = c.z * (1.0 - c.y);
  let q = c.z * (1.0 - f * c.y);
  let t = c.z * (1.0 - (1.0 - f) * c.y);
  if (i == 0.0) { return vec3<f32>(c.z, t, p); }
  if (i == 1.0) { return vec3<f32>(q, c.z, p); }
  if (i == 2.0) { return vec3<f32>(p, c.z, t); }
  if (i == 3.0) { return vec3<f32>(p, q, c.z); }
  if (i == 4.0) { return vec3<f32>(t, p, c.z); }
  return vec3<f32>(c.z, p, q);
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Monopole term of HEAD's field (aspect space): radial push with a soft core
fn pole_term(da: vec2<f32>) -> vec2<f32> {
  let dist = length(da);
  let radial = da / max(dist, 0.0001);
  return radial * (1.0 / (dist * dist + 0.01));
}

// Idea 3: true N/S dipole. HEAD's radial pinch is now the north pole and a
// mirrored south pole sits on the other side of the cursor along a slowly
// turning axis, so the old tangential "dipole" swirl is replaced by real arcs
// that leave N and land on S.
fn magnetic_field(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> vec2<f32> {
  let d = uv - mouse;
  let da = vec2<f32>(d.x * aspect, d.y);
  let fN = pole_term(da - gPoleOffset);
  let fS = pole_term(da + gPoleOffset);
  let field = (fN - fS) * 0.6 * strength;
  return vec2<f32>(field.x / aspect, field.y);
}

fn rk2_advect(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32, dt: f32) -> vec2<f32> {
  let k1 = magnetic_field(uv, mouse, aspect, strength);
  let k2 = magnetic_field(uv + k1 * dt * 0.5, mouse, aspect, strength);
  return uv + k2 * dt;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let fieldStrength = u.zoom_params.x * (1.0 + bass * 0.6);
  let radius = u.zoom_params.y * 0.5 + 0.02;
  let chromatic = u.zoom_params.z * 0.04;
  let falloff = clamp(u.zoom_params.w, 0.0, 0.99);

  let d = uv - mouse;
  let da = vec2<f32>(d.x * aspect, d.y);
  let dist = length(da);
  let influence = 1.0 - smoothstep(radius * (1.0 - falloff), radius, dist);
  let highField = smoothstep(0.3, 0.0, dist) * fieldStrength;

  // Idea 3: pole pair straddles the cursor; axis turns slowly with time
  let poleAngle = time * 0.15;
  let poleHalf = max(radius * 0.4, 0.03);
  gPoleOffset = vec2<f32>(cos(poleAngle), sin(poleAngle)) * poleHalf;

  let dt = 0.003 * (1.0 + treble * 0.5);
  let sepR = chromatic * (1.0 + depth * 0.5);
  let sepG = chromatic * 0.5;
  let sepB = -chromatic * (1.0 + mids * 0.3);

  // Idea 1: per-channel field-line advection. Each channel starts at its own
  // chromatic offset and walks 4 RK2 sub-steps along its own streamline; the
  // samples are accumulated (later steps weighted up) so the channel smears
  // along the field line. A small per-channel step factor (driven by the
  // chromatic slider) lets the three streamlines diverge like dispersion.
  var starts = mat3x2<f32>(uv + vec2<f32>(sepR, 0.0), uv + vec2<f32>(sepG, 0.0), uv + vec2<f32>(sepB, 0.0));
  var smear = vec3<f32>(0.0);
  for (var ch: i32 = 0; ch < 3; ch = ch + 1) {
    let dtc = dt * 0.4 * (1.0 + chromatic * 8.0 * f32(ch));
    var p = starts[ch];
    var acc = 0.0;
    var wsum = 0.0;
    for (var k: i32 = 0; k < 4; k = k + 1) {
      p = clamp(rk2_advect(p, mouse, aspect, fieldStrength, dtc), vec2<f32>(0.001), vec2<f32>(0.999));
      let w = f32(k + 1);
      let s = textureSampleLevel(readTexture, u_sampler, p, 0.0);
      acc = acc + w * select(select(s.b, s.g, ch == 1), s.r, ch == 0);
      wsum = wsum + w;
    }
    smear[ch] = acc / wsum;
  }
  var baseColor = smear;

  let hsv = rgb2hsv(baseColor);
  let hueWarp = hsv.x + influence * fieldStrength * 0.25 + bass * 0.08;
  let satBoost = clamp(hsv.y * (1.0 + highField * 0.4), 0.0, 1.0);
  baseColor = hsv2rgb(vec3<f32>(fract(hueWarp), satBoost, hsv.z));

  // Idea 2: compass hue — like a magnetometer map, hue encodes the local field
  // angle. Blended in RGB (hsv2rgb is continuous across the wrap) so there is
  // no seam where atan2 jumps.
  let fHere = magnetic_field(uv, mouse, aspect, 1.0);
  let fAng = atan2(fHere.y, fHere.x * aspect);
  let compassRGB = hsv2rgb(vec3<f32>(fract(fAng / 6.2831853 + bass * 0.08), max(satBoost, 0.35), hsv.z));
  let compassW = clamp(influence * fieldStrength * 0.6, 0.0, 1.0);
  baseColor = mix(baseColor, compassRGB, compassW);

  let neon = vec3<f32>(0.15, 0.85 + treble * 0.15, 1.0) * highField * (0.25 + bass * 0.12);
  let bloom = vec3<f32>(1.0, 0.3 + mids * 0.2, 0.7) * influence * fieldStrength * 0.18;
  let finalColor = aces_tone_map(max(baseColor + neon + bloom, vec3<f32>(0.0)));

  let chromaticSep = abs(sepR) + abs(sepB);
  // Semantic coverage: the photo covers the frame; the field region is fully opaque
  let alpha = mix(0.8, 1.0, clamp(influence + highField + fieldStrength * chromaticSep * depth, 0.0, 1.0));
  let outDepth = clamp(depth + influence * 0.04 + highField * 0.03, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(fieldStrength, influence, chromaticSep, alpha));
}
