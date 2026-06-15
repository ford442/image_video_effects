// ═══════════════════════════════════════════════════════════════════
//  Tesseract Fold
//  Category: geometric
//  Features: mouse-driven, upgraded-rgba, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgraded: domain-warped FBM, polar kaleidoscope fold, compound 4D
//            rotation, radial chromatic aberration, ACES tone mapping,
//            treble-driven neon edge glow, semantic bloom alpha
// ═══════════════════════════════════════════════════════════════════

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ───────────────────────────────────────────────────────────────

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=4D Rotation Speed, y=Projection Scale, z=Edge Glow Width, w=Face Opacity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const INV_PI: f32 = 0.31830988618;

// ── Hashes & noise ─────────────────────────────────────────────
fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f); f *= 2.0; a *= 0.5;
  }
  return s;
}
fn organicDrift(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
  let safeScale = max(scale, 0.001);
  let p = uv * safeScale;
  let slow = vec2<f32>(time * 0.11, -time * 0.08);
  let q = vec2<f32>(fbm(p + slow, 3), fbm(p * 1.37 + vec2<f32>(5.2, 1.3) - slow.yx, 3));
  let r = vec2<f32>(fbm(p * 0.73 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
                    fbm(p * 0.91 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2));
  return ((q + r * 0.5) * 2.0 - vec2<f32>(1.5)) / safeScale;
}

// ── Geometry helpers ───────────────────────────────────────────
fn rot2(angle: f32) -> mat2x2<f32> {
  let c = cos(angle); let s = sin(angle);
  return mat2x2<f32>(c, -s, s, c);
}
fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
  let r = length(uv);
  var a = atan2(uv.y, uv.x);
  let seg = TAU / max(segs, 1.0);
  a = abs(fract(a / seg + 0.5) - 0.5) * seg;
  return vec2<f32>(cos(a), sin(a)) * r;
}

// ── Color tools ────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(TAU * (c * t + d));
}
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
  let safe = max(color, vec3<f32>(0.0));
  let lum = luma(safe);
  let mask = smoothstep(0.22, 1.0, lum);
  let chroma = normalize(safe + vec3<f32>(0.001)) * max(lum, 0.18);
  let bloom = (safe * safe + chroma) * mask * max(intensity, 0.0);
  return safe + bloom;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let aspect = res.x / res.y;
  var p = (uv01 - mouse) * vec2<f32>(aspect, 1.0);

  // Compound 4D-style rotation via layered 2D rotations
  let a1 = time * p1 * 0.7 + bass * 0.25;
  let a2 = time * p1 * 0.4 + treble * 0.35;
  p = rot2(a1) * p;
  p = rot2(a2) * (p + vec2<f32>(0.04 * sin(time * 0.7)));

  // Domain-warped organic drift
  let drift = organicDrift(p * 3.0, time, 2.0) * (0.04 + p3 * 0.08 + bass * 0.03);
  p += drift;

  // Polar kaleidoscope fold with audio-reactive segment count
  let segs = 4.0 + p1 * 8.0 + bass * 4.0;
  p = kaleido(p, segs);

  // Projection scale
  p *= mix(0.5, 2.5, p2);

  // Iterated branchless fold
  let folds = 4.0 + p1 * 6.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    p = abs(p);
    p = p - vec2<f32>(0.12 + p3 * 0.12);
    let ang = (TAU / max(folds, 1.0)) * (1.0 + 0.2 * sin(time + f32(i) * 1.7));
    p = rot2(ang) * p;
  }

  let sampleUv = clamp(mouse + p / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  // Radial chromatic aberration from the fold center
  let dir = normalize(p + vec2<f32>(0.0001));
  let ca = 0.004 * (1.0 + p3) + depth * 0.002 + treble * 0.002;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUv + dir * ca, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, sampleUv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUv - dir * ca * 0.7, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = pow(vec3<f32>(r, g, b), vec3<f32>(2.2));

  // Iridescent color grading
  let radius = length(p);
  let angle = atan2(p.y, p.x);
  let hue = (angle * INV_PI * 0.5 + 0.5) + radius * 0.6 + time * 0.05;
  let grade = palette(hue,
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(0.5, 0.5, 0.5),
                      vec3<f32>(1.0, 1.0, 0.8),
                      vec3<f32>(0.0, 0.15, 0.25));
  color = mix(color, color * grade * 2.0, 0.3 + mids * 0.2);

  // Atmospheric vignette around the mouse
  let vignette = exp(-radius * radius * (2.5 + p3 * 2.0));
  color = mix(color * 0.15, color, vignette);

  // Treble-driven edge glow at fold boundaries
  let segAngle = TAU / max(segs, 1.0);
  let edgeDist = abs(fract(angle / segAngle + 0.5) - 0.5) * 2.0;
  let edgeGlow = smoothstep(1.0 - p3 * 0.4, 1.0, edgeDist) * (0.6 + treble * 0.6);
  color = neonGlow(color, 0.25 + edgeGlow * 0.35);

  // Tone map and gamma encode
  color = pow(acesToneMap(color), vec3<f32>(1.0 / 2.2));

  // Semantic alpha: bloom weight modulated by opacity, edge, and depth
  let lum = luma(color);
  let bloom = pow(max(0.0, lum - 0.5), 2.0) * 3.0 * (1.0 + treble);
  let alpha = mix(p4 * (0.4 + bloom), 1.0, edgeGlow * 0.45);
  textureStore(writeTexture, pixel, vec4<f32>(color, clamp(alpha, 0.0, 1.0)));

  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
