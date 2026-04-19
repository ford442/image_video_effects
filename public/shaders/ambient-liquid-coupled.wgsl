// ═══════════════════════════════════════════════════════════════════
//  ambient-liquid-coupled
//  Category: advanced-hybrid
//  Features: ambient-liquid, fluid-simulation, mouse-driven, temporal
//  Complexity: High
//  Chunks From: ambient-liquid.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Gentle ambient sine waves are driven by a real fluid velocity
//  field. The mouse drags viscous fluid that warps the image via
//  advected displacement, while ripple eddies create vortices.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let waveStrength = mix(0.005, 0.04, u.zoom_params.x);
  let fluidViscosity = mix(0.85, 0.99, u.zoom_params.y);
  let vortexStrength = u.zoom_params.z * 2.0;
  let brightSplit = u.zoom_params.w;

  // === FLUID VELOCITY FIELD (from mouse-fluid-coupling) ===
  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous velocity and density
  let prevVel = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).xy;
  let prevDens = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).a;

  // Advect velocity
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0).xy;
  let advectedDens = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0).a;

  var vel = advectedVel * fluidViscosity;
  var dens = advectedDens * fluidViscosity;

  // Mouse force
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let mouseRadius = mix(0.03, 0.15, 0.5);
  let influence = smoothstep(mouseRadius, 0.0, dist);
  vel = vel + mouseVel * influence * 0.5;

  // Vortex force
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  // Ripple injection
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  // Edge damping
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // Store velocity state
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  // === AMBIENT LIQUID WAVES (from ambient-liquid) ===
  let rate = 0.5;
  let waveTime = time * rate;
  let frequency = 15.0;

  // Fluid velocity warps the wave phase
  let wavePhase = vec2<f32>(vel.x * 5.0, vel.y * 5.0);

  var d1 = sin(uv.x * frequency + waveTime + wavePhase.x) * waveStrength;
  var d2 = cos(uv.y * frequency * 0.7 + waveTime + wavePhase.y) * waveStrength;

  // Mouse attractor
  let to_mouse = mousePos - uv;
  let dist_to_mouse = length(to_mouse);
  let mouse_influence = exp(-dist_to_mouse * 5.0) * 0.015;
  d1 += to_mouse.x * mouse_influence;
  d2 += to_mouse.y * mouse_influence;

  // Ripple eddies
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_pos = ripple.xy;
      let ripple_age = waveTime - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 4.0) {
        let to_ripple = uv - ripple_pos;
        let ripple_dist = length(to_ripple);
        let ripple_strength = sin(ripple_dist * 20.0 - ripple_age * 5.0) * exp(-ripple_age * 0.5) * 0.01;
        d1 += to_ripple.y * ripple_strength;
        d2 -= to_ripple.x * ripple_strength;
      }
    }
  }

  var displacedUV = uv + vec2<f32>(d1, d2);
  var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // Bright/dark split with fluid influence
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  if (luma > 0.75 && brightSplit > 0.0) {
    let bright_time = time * 0.65;
    let bd1 = sin(uv.x * frequency + bright_time) * waveStrength;
    let bd2 = cos(uv.y * frequency * 0.7 + bright_time) * waveStrength;
    let brightDisplacedUV = uv + vec2<f32>(bd1, bd2);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, brightDisplacedUV, 0.0), 0.25 * brightSplit);
  }

  if (luma < 0.25 && brightSplit > 0.0) {
    let dark_time = time * 0.45;
    let dd1 = sin(uv.x * frequency + dark_time) * waveStrength;
    let dd2 = cos(uv.y * frequency * 0.7 + dark_time) * waveStrength;
    let darkDisplacedUV = uv + vec2<f32>(dd1, dd2);
    color = mix(color, textureSampleLevel(readTexture, u_sampler, darkDisplacedUV, 0.0), 0.75 * brightSplit);
  }

  // Depth-aware alpha
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.7, 1.0, luma);
  let finalAlpha = mix(alpha * 0.8, alpha, depth);

  // Fluid tint: thicker fluid = slight warm tint
  let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.92, 0.82), dens * 0.3);
  let tintedColor = color.rgb * fluidTint;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tintedColor, finalAlpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
