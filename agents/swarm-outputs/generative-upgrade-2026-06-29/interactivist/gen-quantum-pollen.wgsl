// ═══════════════════════════════════════════════════════════════════
//  Quantum Pollen — Interactivist Upgrade
//  Category: generative
//  Features: procedural, audio-reactive, mouse-gravity, click-burst,
//            video-luma-spawn, depth-aware, temporal-feedback,
//            motion-advection, chromatic-aberration, aces-tone-map
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-29
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

// ── Math & hash ───────────────────────────────────────────────────
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hashf(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i++) {
    sum += amp * valueNoise(p * freq);
    freq *= 2.0;
    amp *= 0.5;
  }
  return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
  return p + strength * q;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
  let hue = fract(t);
  let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
  let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
  let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
  let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
  return mix(vec3<f32>(value), smoothRgb * value, saturation);
}

fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
  let safeColor = max(color, vec3<f32>(0.0));
  let lum = dot(safeColor, vec3<f32>(0.2126, 0.7152, 0.0722));
  let glowMask = smoothstep(0.22, 1.0, lum);
  let chroma = normalize(safeColor + vec3<f32>(0.001)) * max(lum, 0.18);
  let bloom = (safeColor * safeColor + chroma) * glowMask * max(intensity, 0.0);
  return safeColor + bloom;
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let angle = atan2(uv.y - 0.5, uv.x - 0.5);
  let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
  return vec3<f32>(
    color.r * (1.0 + shift.x * 0.8),
    color.g,
    color.b * (1.0 - shift.y * 0.5)
  );
}

// ── Particle core ─────────────────────────────────────────────────
fn particleLayer(uv: vec2<f32>, time: f32, scale: f32, drift: vec2<f32>, phase: f32) -> vec3<f32> {
  let gridUV = uv * scale + drift * time + phase;
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let rnd = hash22(cell);
  let center = rnd - 0.5;
  let d = length(local - center * 0.7);
  let core = exp(-d * d * 34.0);
  let halo = exp(-d * d * 8.0);
  return vec3<f32>(core, halo, rnd.x);
}

// ── Main compute pass ─────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let mn = min(res.x, res.y);
  let uv = (vec2<f32>(pixel) - res * 0.5) / mn;

  let time = u.config.x;
  let mouse_uv = u.zoom_config.yz;
  let mouse_down = u.zoom_config.w > 0.5;

  let p1 = u.zoom_params.x; // swarm density
  let p2 = u.zoom_params.y; // morph / drift speed
  let p3 = u.zoom_params.z; // bloom / glow
  let p4 = u.zoom_params.w; // feedback trail

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  // Mouse in aspect-corrected UV space
  let mouse = (mouse_uv - 0.5) * vec2<f32>(res.x / mn, res.y / mn);
  let toMouse = mouse - uv;
  let distMouse = length(toMouse);

  // Gravity well + click burst
  let gravity = (toMouse / max(distMouse, 0.001)) * (0.03 + bass * 0.04) / (1.0 + distMouse * 3.0);
  let burstDir = uv / max(length(uv), 0.001);
  let burst = select(0.0, 1.0, mouse_down) * burstDir * 0.18 * (1.0 + bass);

  // Audio-driven morph field
  let driftBase = vec2<f32>(0.05, -0.15) * mix(0.4, 1.4, p2);
  let vortex = vec2<f32>(-uv.y, uv.x) * (0.05 + bass * 0.16);
  let audioWander = vec2<f32>(
    sin(time * 0.35 + mids * 4.0) * 0.05,
    cos(time * 0.28 + bass * 3.0) * 0.05
  );
  let totalDrift = driftBase + vortex + gravity + audioWander + burst;

  // Organic domain warp for emergent flow
  let warpScale = 1.5 + p1 * 3.5 + bass * 0.5;
  let warpStrength = 0.35 + mids * 0.25;
  let warpUV = domainWarp(uv * warpScale, warpStrength, 3);

  // Luma-keyed spawn from incoming video / readTexture
  let videoUV = clamp(uv01 + totalDrift * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
  let videoSample = textureSampleLevel(readTexture, u_sampler, videoUV, 0.0);
  let videoLuma = luma(videoSample.rgb);
  let spawnMask = smoothstep(0.42, 0.82, videoLuma) * (0.25 + treble * 0.45);

  // Pollen layers with audio-scaled radii
  let swarmDensity = mix(8.0, 82.0, p1);
  let morphSpeed = mix(0.35, 1.7, p2) + mids * 0.35;
  let coreSharp = 34.0 + treble * 10.0;
  let haloSoft = 7.0 + bass * 4.0;

  let l0 = particleLayer(warpUV, time, swarmDensity * 0.42, totalDrift, 0.0);
  let l1 = particleLayer(warpUV + vec2<f32>(0.31, 0.19), time * 1.13, swarmDensity, totalDrift * 1.25, morphSpeed * 0.7);
  let l2 = particleLayer(warpUV + vec2<f32>(0.57, 0.43), time * 1.31, swarmDensity * 1.55, totalDrift * 1.7, morphSpeed * 1.4);

  let core = l0.x + l1.x + l2.x;
  let haze = l0.y * 0.6 + l1.y * 0.85 + l2.y;

  // Treble sparkle
  let sparklePhase = time * (7.0 + treble * 32.0) + (l0.z + l1.z + l2.z) * 12.0;
  let sparkle = 0.5 + 0.5 * sin(sparklePhase);

  // Layered pollen color
  var color = vec3<f32>(0.0);
  color += psychedelicPalette(time * 0.046 + l0.z * 0.28) * l0.x * (1.0 + treble * 0.35);
  color += psychedelicPalette(time * 0.063 + l1.z * 0.37 + 0.31) * l1.x * (1.0 + mids * 0.28);
  color += psychedelicPalette(time * 0.079 + l2.z * 0.45 + 0.67) * l2.x * (1.0 + bass * 0.22);
  color += vec3<f32>(0.08, 0.16, 0.12) * haze * 0.35;

  // Bass pulse scales overall brightness; mids tint motion
  let pulse = 1.0 + bass * 0.65 + mids * 0.25;
  color *= pulse * (0.78 + sparkle * 0.52);

  // Video spawn bloom
  color += videoSample.rgb * spawnMask * 0.45 * (1.0 + bass);

  // Motion-vector advection + temporal accumulation feedback
  let advectUV = clamp(uv01 - totalDrift * 0.008 * (1.0 + p4 * 2.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let advect = textureSampleLevel(dataTextureC, u_sampler, advectUV, 0.0);
  let decay = 0.92 - p4 * 0.07;
  let trailMix = 0.13 + bass * 0.05;
  var feedback = mix(advect.rgb * decay, color, trailMix);

  // Click burst injects fresh energy
  let reset = select(0.0, 1.0, mouse_down);
  feedback = mix(feedback, color * (1.25 + bass * 0.6), reset);

  // Blend feedback into current frame for visible trails
  color = mix(color, feedback, 0.35 + p4 * 0.35);

  // Bloom glow
  color = neonGlow(color, 0.28 + p3 * 0.55 + bass * 0.22);

  // Chromatic aberration driven by bass + depth
  let caStr = 0.0025 * (1.0 + bass) + depth * 0.001;
  color = genChromaticShift(color, uv01, caStr, time);

  // Tone map
  color = acesToneMap(color * (0.88 + mids * 0.18));

  // Semantic alpha: presence modulated by depth
  let presence = sat(core * 0.85 + haze * 0.28 + spawnMask * 0.35);
  var alpha = sat(presence * (1.05 - depth * 0.35)) * (0.72 + bass * 0.12);
  alpha = clamp(alpha, 0.15, 0.95);

  // Store ping-pong feedback state
  textureStore(dataTextureA, pixel, vec4<f32>(feedback, prev.a * 0.96 + 0.04));

  // Final outputs
  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(sat(0.78 - presence * 0.42 + depth * 0.15), 0.0, 0.0, 1.0));
}
