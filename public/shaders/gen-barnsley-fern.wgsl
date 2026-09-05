// ═══════════════════════════════════════════════════════════════════
//  Barnsley Fern IFS — Batch 61 (fast motion / psychedelic / mouse spring)
//  Combined techniques: Barnsley IFS + Voronoi displacement +
//                       SDF vignette mask + audio-driven palette +
//                       domain-warped FBM + chromatic aberration +
//                       temporal feedback echo
//  Category: generative
//  Complexity: High
//  Updated: 2026-07-08
// ═══════════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash, value noise & fBM ───────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453123;
  return fract(vec2<f32>(n, n * 1.618));
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  return p + strength * vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
}

// ── Voronoi displacement ──────────────────────────────────────────
fn voronoi(p: vec2<f32>) -> vec2<f32> {
  let i = floor(p); let f = fract(p);
  var md = 8.0; var md2 = 8.0; var cell = vec2<f32>(0.0);
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let g = vec2<f32>(f32(x), f32(y));
      let h = hash22(i + g);
      let d = length(g + h - f);
      if d < md {
        md2 = md; md = d; cell = i + g + h;
      } else if d < md2 {
        md2 = d;
      }
    }
  }
  return vec2<f32>(md, md2 - md);
}

// ── Quasi-random Halton sequence ──────────────────────────────────
fn halton(i: u32, base: u32) -> f32 {
  var f = 1.0; var r = 0.0; var idx = i;
  loop { if (idx == 0u) { break; } f = f / f32(base); r += f * f32(idx % base); idx /= base; }
  return r;
}

// ── Color helpers ─────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let a = atan2(uv.y - 0.5, uv.x - 0.5);
  let s = vec2<f32>(cos(a), sin(a)) * strength;
  return vec3<f32>(color.r * (1.0 + s.x * 0.8), color.g, color.b * (1.0 - s.y * 0.5));
}

fn audioPalette(fy: f32, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
  let forest = vec3<f32>(0.02, 0.18, 0.04);
  let emerald = vec3<f32>(0.05, 0.65, 0.18);
  let lime = vec3<f32>(0.45, 0.95, 0.12);
  let gold = vec3<f32>(0.85, 0.75, 0.15);
  let magenta = vec3<f32>(0.95, 0.12, 0.72);
  let cyan = vec3<f32>(0.12, 0.92, 1.0);
  var c: vec3<f32>;
  if fy < 0.3 { c = mix(forest, emerald, fy / 0.3); }
  else if fy < 0.7 { c = mix(emerald, lime, (fy - 0.3) / 0.4); }
  else { c = mix(lime, gold, (fy - 0.7) / 0.3); }
  let shift = clamp(bass * 0.35 + treble * 0.25, 0.0, 1.0);
  c = mix(c, magenta, shift * 0.45);
  c = mix(c, cyan, mids * 0.28);
  return c;
}

// ── Inverse IFS transforms ────────────────────────────────────────
fn barnsleyInv(p: vec2<f32>, idx: i32) -> vec2<f32> {
  if idx == 0 { return vec2<f32>(0.0, p.y / 0.16); }
  if idx == 1 { let dy = p.y - 1.6; return vec2<f32>((0.85 * p.x - 0.04 * dy) / 0.7241, (0.04 * p.x + 0.85 * dy) / 0.7241); }
  if idx == 2 { let dy = p.y - 1.6; return vec2<f32>((0.22 * p.x + 0.26 * dy) / 0.1038, (-0.23 * p.x + 0.2 * dy) / 0.1038); }
  let dy = p.y - 0.44; return vec2<f32>((-0.24 * p.x + 0.28 * dy) / 0.1088, (0.26 * p.x + 0.15 * dy) / 0.1088);
}

fn pickIFS(h: f32) -> i32 {
  var idx = 1;
  if h < 0.01 { idx = 0; } else if h < 0.86 { idx = 1; } else if h < 0.93 { idx = 2; } else { idx = 3; }
  return idx;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let pixel = vec2<i32>(gid.xy);
  if pixel.x >= i32(res.x) || pixel.y >= i32(res.y) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x * 2.4;
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let sdelta = springPos - rawMouse; let temp = (springVel + omega * sdelta) * dt;
  springVel = (springVel - omega * temp) * springDecay; springPos = rawMouse + (sdelta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }
  let mouse = springPos;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(1.0, 1.45, mouseDown);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scale = mix(0.7, 1.3, u.zoom_params.x);
  let caAmt = u.zoom_params.y * 0.08;
  let brightness = mix(0.8, 2.0, u.zoom_params.z);
  let feedback = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = uv * vec2<f32>(aspect * 5.0, 10.0) / scale;

  // Organic domain warp driven by bass + time
  let warp = domainWarp(p * 1.5 + vec2<f32>(time * 0.07, time * 0.05), 0.18 + bass * 0.08, 3);
  p = mix(p, warp, 0.35 + bass * 0.15);

  // Voronoi displacement on frond coordinates
  let voro = voronoi(p * 0.35 + vec2<f32>(time * 0.04, time * 0.03));
  p = p + (vec2<f32>(voro.y, voro.x) - 0.5) * 0.18 * (1.0 + treble + mids);

  // Mouse attracts frond tips (held-drag tightens)
  let mouseFern = (mouse - 0.5) * vec2<f32>(aspect * 5.0, 10.0) / scale;
  let tipFactor = smoothstep(0.0, 1.0, (p.y + 3.0) / 8.0);
  let pull = exp(-length(p - mouseFern) * 0.65) * tipFactor * 0.55 * held;
  p = mix(p, mouseFern, pull);

  // Quasi-random inverse IFS Monte-Carlo coverage
  let baseIdx = u32(gid.x) * 73u + u32(gid.y) * 131u + u32(time * 60.0);
  let numPaths = i32(mix(2.0, 5.0, depth + bass * 0.3));
  var density = 0.0;

  for (var path = 0; path < numPaths; path = path + 1) {
    var q = p; var valid = 1.0;
    for (var i = 0; i < 7; i = i + 1) {
      let h = halton(baseIdx + u32(path) * 7u + u32(i), 2u);
      var idx = pickIFS(h);
      if idx == 0 && abs(q.x) > 0.18 { idx = 1; }
      q = barnsleyInv(q, idx);
      let outside = q.x < -3.2 || q.x > 3.2 || q.y < -0.5 || q.y > 12.0;
      if outside { valid = 0.0; break; }
    }
    density += valid;
  }
  density /= f32(numPaths);

  // Multi-scale detail noise modulated by treble
  let detail = fbm(p * 6.0 + vec2<f32>(time * 0.1), 3) * (0.08 + treble * 0.12);
  density = saturate(density * (1.0 + detail) - detail * 0.3);

  // SDF vignette mask — preserves semantic alpha falloff at edges
  let vignette = 1.0 - smoothstep(0.35, 0.85, length(uv));
  density = density * vignette;

  // Natural + audio-driven fern palette by height
  let fy = clamp((p.y + 3.0) / 10.0, 0.0, 1.0);
  var color = audioPalette(fy, bass, mids, treble);

  // Sunlight filtering through fronds
  let sun = 0.3 + 0.7 * smoothstep(0.2, 0.9, density);
  color = color * sun * brightness;

  // Chromatic aberration on fern edges
  let edge = smoothstep(0.15, 0.75, density);
  color = genChromaticShift(color, uv01, caAmt * edge);

  color = acesToneMap(color * 1.8);

  // Temporal feedback echo
  color = mix(color, prev.rgb * 0.96, 0.03 + feedback * 0.08 + bass * 0.02);
  let geo = abs(fract(voro.y * 8.0 + time * 0.4) - 0.5);
  color += vec3<f32>(0.85, 0.15, 1.0) * (1.0 - smoothstep(0.0, 0.08, geo)) * 0.25 * (0.4 + treble);

  // Audio warms palette
  let warmth = bass * 0.15;
  color = vec3<f32>(color.r * (1.0 + warmth), color.g, color.b * (1.0 - warmth * 0.3));

  let photo = smoothstep(0.0, 0.4, color.g);
  let alpha = density * photo * (0.4 + depth * 0.6);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(density * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
}
