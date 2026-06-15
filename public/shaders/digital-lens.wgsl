// ═══════════════════════════════════════════════════════════════════
//  Digital Lens v3
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            barrel-distortion, chromatic-dispersion, anamorphic,
//            temporal-feedback, gravity-well
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-06-14
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Brown-Conrady lens distortion model
fn brownConrady(p: vec2<f32>, k1: f32, k2: f32, p1: f32, p2: f32) -> vec2<f32> {
  let r2 = dot(p, p);
  let r4 = r2 * r2;
  let radial = 1.0 + k1 * r2 + k2 * r4;
  let tangentialX = 2.0 * p1 * p.x * p.y + p2 * (r2 + 2.0 * p.x * p.x);
  let tangentialY = p1 * (r2 + 2.0 * p.y * p.y) + 2.0 * p2 * p.x * p.y;
  return vec2<f32>(p.x * radial + tangentialX, p.y * radial + tangentialY);
}

// Mouse acts as a gravitational attractor for the lens center
fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
  let d = wellPos - pos;
  let dist2 = dot(d, d) + 0.001;
  return normalize(d) * strength / dist2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspect = res.x / res.y;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  // ── Temporal audio envelope (bass_env) ───────────────────────────
  // Attack/release smoothing removes frame-by-frame strobe from raw bass.
  let attack = 0.8;
  let release = 0.15;
  let bassEnv = mix(prev.r, bass, select(release, attack, bass > prev.r));

  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  // ── Mouse interaction ────────────────────────────────────────────
  // Mouse position drives a gravity well that warps the lens center.
  // Mouse down triples well strength and adds a click burst.
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let gravityStrength = p4 * 0.08 * (1.0 + f32(mouseDown) * 2.0);
  let gravity = gravityWell(uv01, mouse, gravityStrength);
  let focusPoint = mouse + gravity * 0.15;

  // ── Lens parameters ──────────────────────────────────────────────
  let breathe = bassEnv * 0.35;
  let k1 = (p1 - 0.5) * 2.2 * (1.0 + breathe);
  let k2 = k1 * k1 * 0.5;
  let dispersion = p2 * 0.045 * (1.0 + mids * 0.8) * (0.5 + depth * 0.5);
  let anamorphicSqueeze = 0.2 + mids * 0.25;

  // ── Distortion in centered, aspect-corrected space ───────────────
  let center = vec2<f32>(0.5, 0.5);
  var p = (uv01 - center + gravity * 0.02) * vec2<f32>(aspect, 1.0);
  p.x = p.x * (1.0 + anamorphicSqueeze * 0.3);

  let distortedP = brownConrady(p, k1, k2, k1 * 0.05, k1 * 0.03);
  let sampleCenter = center + distortedP / vec2<f32>(aspect, 1.0) + (focusPoint - 0.5) * 0.06;

  // ── Chromatic aberration per RGB channel ─────────────────────────
  let r = length(p);
  let radial = select(vec2<f32>(0.0), p / max(r, 0.0001), r > 0.0001);
  let radialUV = radial / vec2<f32>(aspect, 1.0);

  let rDisp = dispersion * 1.4 * (1.0 + r * 1.5);
  let gDisp = dispersion * 0.7 * r;
  let bDisp = dispersion * 1.1 * (1.0 + r * 0.8);

  let rUV = clamp(sampleCenter + radialUV * rDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(sampleCenter + radialUV * gDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(sampleCenter - radialUV * bDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  // ── Film grain + treble sparkle ──────────────────────────────────
  let grain = hash22(uv01 * 800.0 + time * 60.0).x - 0.5;
  color += grain * 0.03 * (1.0 + treble * 0.6);

  // ── Click burst around mouse ─────────────────────────────────────
  let clickPulse = f32(mouseDown) * exp(-distance(uv01, mouse) * 8.0) * bassEnv;
  color += vec3<f32>(clickPulse * 0.25);

  // ── Vignette (Param3) ────────────────────────────────────────────
  let vignetteStrength = p3 * 0.8;
  let vignette = 1.0 - vignetteStrength * dot(uv01 - 0.5, uv01 - 0.5) * 2.0;
  color *= clamp(vignette, 0.0, 1.0);

  // ── ACES tone mapping ────────────────────────────────────────────
  color = acesToneMap(color * 1.1);

  // ── Temporal feedback trail ──────────────────────────────────────
  let decay = 0.96 - p4 * 0.03;
  color = mix(prev.gba * decay, color, 0.82 + bassEnv * 0.12);

  // Persist envelope in R and this frame's color in GBA for next frame.
  textureStore(dataTextureA, pixel, vec4<f32>(bassEnv, color));

  // ── Semantic alpha: interaction intensity ────────────────────────
  let distStrength = abs(k1) * 0.5 + 0.3;
  let chromSep = dispersion * 2.0;
  let alpha = clamp(distStrength * chromSep * (0.3 + depth * 0.7) * (0.7 + bassEnv * 0.5), 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
