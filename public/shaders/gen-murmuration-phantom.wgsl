// ═══════════════════════════════════════════════════════════════════
//  Murmuration Phantom
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: predator-triggered banking agitation waves (dark/light bands propagating through the flock as birds tilt wing-on vs edge-on); marginal-opacity self-regulation (flock optical depth saturates so ~30% of twilight sky transmits through the core)
//  A packing: ACES display RGBA in A (alpha = flock sky-coverage 1-T plus glint/scatter;
//    C.rgb read back as colour history, C.a inverted as approximate trail density)
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Flock Size, .y = Shape Morph, .z = Glint Intensity, .w = Cohesion
  ripples: array<vec4<f32>, 50>,
};

fn h2(p: vec2<f32>) -> f32 {
  let q = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract(dot(q, q + vec2<f32>(33.33)));
}

fn h3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  return fract(dot(q, q.yxz + vec3<f32>(33.33)));
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h2(i), h2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h2(i + vec2<f32>(0.0, 1.0)), h2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn n3(p: vec3<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(h3(i + vec3<f32>(0.0, 0.0, 0.0)), h3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
                 mix(h3(i + vec3<f32>(0.0, 1.0, 0.0)), h3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
             mix(mix(h3(i + vec3<f32>(0.0, 0.0, 1.0)), h3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
                 mix(h3(i + vec3<f32>(0.0, 1.0, 1.0)), h3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

fn fbm2(p: vec2<f32>) -> f32 {
  var f = 0.0; var a = 0.5; var x = p;
  for(var i = 0; i < 4; i++) { f += a * n2(x); x *= 2.03; a *= 0.5; }
  return f;
}

fn fbm3(p: vec3<f32>) -> f32 {
  var f = 0.0; var a = 0.5; var x = p;
  for(var i = 0; i < 4; i++) { f += a * n3(x); x *= 2.03; a *= 0.5; }
  return f;
}

fn pot(p: vec2<f32>, t: f32) -> f32 {
  return n3(vec3<f32>(p, t * 0.1)) + 0.5 * n3(vec3<f32>(p * 2.0, -t * 0.15)) + 0.25 * n3(vec3<f32>(p * 4.0, t * 0.2));
}

fn curl(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let ddx = (pot(p + vec2<f32>(e, 0.0), t) - pot(p - vec2<f32>(e, 0.0), t)) / (2.0 * e);
  let ddy = (pot(p + vec2<f32>(0.0, e), t) - pot(p - vec2<f32>(0.0, e), t)) / (2.0 * e);
  return vec2<f32>(ddy, -ddx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither (from AGENTS.md) ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}


// Marginal opacity: optical depth saturates toward TAU_MARGINAL (T ≈ 0.18..0.3
// at the core) instead of going fully black — starling flocks self-organise
// so light still passes through (Pearce et al. 2014).
const TAU_MARGINAL: f32 = 1.35;
const TAU_KNEE: f32 = 0.15;

fn flockOpticalDepth(d: f32, tauMax: f32) -> f32 {
  let dd = max(d, 0.0);
  return tauMax * dd / (dd + TAU_KNEE);
}

// Approximate inverse of coverage = 1 - exp(-flockOpticalDepth(d)) for feedback
fn densityFromCoverage(cov: f32, tauMax: f32) -> f32 {
  let tau = -log(max(1.0 - clamp(cov, 0.0, 0.999), 1e-3));
  let tn = min(tau / tauMax, 0.95);
  return TAU_KNEE * tn / (1.0 - tn);
}

// Banking agitation wave: birds tilting in sequence expose wings broadside
// (dark) or edge-on (light); the wave propagates outward from the predator.
fn bankingWave(distToPredator: f32, t: f32, agitation: f32) -> f32 {
  let front = sin(distToPredator * 18.0 - t * 6.0);
  let band = smoothstep(-0.2, 0.9, front);
  return mix(1.0, mix(0.35, 1.25, band), clamp(agitation, 0.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if(f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
  let coord = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;
  let t = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let flockSize = mix(0.3, 1.2, u.zoom_params.x);
  let shapeMorph = clamp(u.zoom_params.y + mids * 0.15, 0.0, 1.0);
  let glintIntensity = u.zoom_params.z;
  let cohesion = u.zoom_params.w;
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x / res.y, 1.0);
  var center = vec2<f32>(sin(t * 0.2) * 0.3, cos(t * 0.15) * 0.2);
  let mDist = length(uv - mouse);
  // Predator disturbance: hovering pushes the flock, holding is a stoop (stronger, wider)
  center += normalize(uv - mouse + vec2<f32>(0.001)) * exp(-mDist * mix(4.0, 2.5, held)) * (0.5 + held * 0.35);
  var scatter = 0.0;
  var waveSeed = 0.0;
  let rc = min(u32(u.config.y), 50u);
  for(var i = 0u; i < rc; i++) {
    let rp = u.ripples[i];
    let elapsed = t - rp.z;
    if(elapsed > 0.0 && elapsed < 2.0) {
      let rd = length(uv - (rp.xy - 0.5) * vec2<f32>(res.x / res.y, 1.0));
      scatter += exp(-rd * 8.0) * sin(elapsed * 10.0) * exp(-elapsed * 2.0);
      waveSeed = max(waveSeed, exp(-elapsed * 1.5));
    }
  }
  var p = (uv - center) / flockSize;
  let flow = curl(p, t) * 0.4;
  p += flow;
  p += curl(p * 1.7 + vec2<f32>(1.0), t * 0.8) * 0.2;
  let phi = 1.6180339887;
  let angle = atan2(p.y, p.x);
  let radius = length(p);
  let spiral = sin(angle * phi + radius * 8.0 - t * 0.5) * 0.5 + 0.5;
  let sphere = radius - 0.5;
  let torus = length(vec2<f32>(radius - 0.35, p.y * 0.3)) - 0.2;
  let wave = abs(p.y - sin(p.x * 4.0 + t * 0.3) * 0.25) - 0.12;
  let s1 = mix(sphere, torus, smoothstep(0.0, 0.33, shapeMorph));
  let s2 = mix(s1, wave, smoothstep(0.33, 0.66, shapeMorph));
  let shape = mix(s2, fbm2(p * 2.0 + t * 0.1) * 0.4 - 0.15, smoothstep(0.66, 1.0, shapeMorph));
  let mask = smoothstep(0.15, -0.05, shape) * spiral;
  let n1 = fbm3(vec3<f32>(p * 3.0, t * 0.2));
  let n2 = fbm3(vec3<f32>(p * 6.0 + flow * 3.0, t * 0.15));
  var density = (n1 * 0.7 + n2 * 0.3) * mask * cohesion * (1.0 + bass * 0.5);

  // ── Idea 1: banking agitation waves radiating from the predator ──
  // Always faintly present near the predator; a held stoop or a click drives full waves.
  let agitation = (0.25 + held * 0.75 + waveSeed * 0.6 + bass * 0.2) * exp(-mDist * 1.2) * smoothstep(0.0, 0.05, mask);
  let bank = bankingWave(mDist, t, agitation);
  density *= bank;

  let ex = 0.01;
  let dx = fbm3(vec3<f32>((p + vec2<f32>(ex, 0.0)) * 3.0, t * 0.2)) * mask -
           fbm3(vec3<f32>((p - vec2<f32>(ex, 0.0)) * 3.0, t * 0.2)) * mask;
  // Edge-on birds on the light side of a banking band catch the low sun
  let edge = abs(dx) * 25.0 * treble * glintIntensity * (1.0 + max(bank - 1.0, 0.0) * 2.0);
  let indigo = vec3<f32>(0.098, 0.098, 0.439);
  let violet = vec3<f32>(0.541, 0.169, 0.886);
  let sunset = vec3<f32>(1.0, 0.271, 0.0);
  let silver = vec3<f32>(0.753, 0.753, 0.753);
  var col = mix(indigo, violet, density * 2.0);
  col = mix(col, sunset, smoothstep(0.4, 0.9, density + edge * 0.5));
  col += silver * edge * (1.0 + treble);
  col += violet * smoothstep(0.3, 0.8, density) * 0.3;
  let shadow = 1.0 - smoothstep(0.0, 0.5, density);
  col = mix(col, col * vec3<f32>(0.6, 0.7, 1.0), shadow * 0.5);
  col += vec3<f32>(0.8, 0.7, 0.9) * scatter * 0.5;

  // ═══ trail-accumulation — exact load of previous A (display RGBA) ═══
  let tauMax = TAU_MARGINAL * mix(0.8, 1.4, cohesion);
  let prevTrail = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let prevDensity = densityFromCoverage(prevTrail.a, tauMax);
  let trailDecay = 0.93 - bass * 0.04;
  let trailDensity = max(density, prevDensity * trailDecay);
  col = mix(col, prevTrail.rgb * 0.92, 0.05 + bass * 0.01);

  // ── Idea 2: marginal opacity — sky transmits through the saturated flock ──
  let tau = flockOpticalDepth(trailDensity, tauMax);
  let transmit = exp(-tau);
  let skyY = uv.y / 0.5;
  let twilightSky = mix(sunset * 0.55 + violet * 0.15, indigo * 0.8, smoothstep(-1.0, 1.0, skyY));
  let silhouette = vec3<f32>(0.03, 0.025, 0.06);
  // Birds absorb (dark silhouettes); the transmitted fraction keeps sky glow alive in the core
  let flockLayer = mix(col, silhouette + twilightSky * transmit, (1.0 - transmit) * 0.45);
  col = mix(col, flockLayer, smoothstep(0.0, 0.1, trailDensity));

  let caStr = 0.003 * (1.0 + bass) + density * 0.001;
  col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

  var outCol = acesToneMap(huePreserveClamp(col * 1.2, 2.5));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;
  outCol = clamp(outCol, vec3<f32>(0.0), vec3<f32>(1.0));
  // Semantic alpha: flock sky-coverage (1 - T), plus glints and click scatter
  let coverage = 1.0 - transmit;
  let a = clamp(coverage + (edge * 0.8 + abs(scatter) * 0.3) * transmit, 0.0, 1.0);
  let finalColor = vec4<f32>(outCol, a);
  textureStore(writeTexture, coord, finalColor);
  textureStore(dataTextureA, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(density * 0.5, 0.0, 0.0, 0.0));
}
