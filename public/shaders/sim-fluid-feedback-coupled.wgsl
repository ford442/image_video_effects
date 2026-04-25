// ═══════════════════════════════════════════════════════════════════
//  sim-fluid-feedback-coupled
//  Category: simulation
//  Features: simulation, mouse-driven, fluid-coupling, temporal, multi-technique
//  Complexity: Very High
//  Chunks From: sim-fluid-feedback-field (curl noise, velocity advection,
//               density advection, glow composite), mouse-fluid-coupling
//               (mouse stirring, vortex force, specular highlights)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Single-pass coupled fluid: Navier-Stokes velocity advection + density
//  transport combined with mouse-steerable viscous fluid coupling.
//  Mouse drags fluid creating vortex streets; click ripples inject
//  bursts. Fluid thickness determines color absorption and blur.
//  Uses dataTextureC for temporal velocity feedback, dataTextureA
//  for storing next frame state.
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

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// ═══ CHUNK: curlNoise (from sim-fluid-feedback-field) ═══
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let eps = 0.01;
  let n1 = noise(p + vec2<f32>(eps, 0.0));
  let n2 = noise(p - vec2<f32>(eps, 0.0));
  let n3 = noise(p + vec2<f32>(0.0, eps));
  let n4 = noise(p - vec2<f32>(0.0, eps));
  return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

fn sampleVelocity(tex: texture_2d<f32>, uv: vec2<f32>) -> vec2<f32> {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, uv: vec2<f32>) -> f32 {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).a;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);

  // Parameters
  let viscosity = mix(0.88, 0.995, u.zoom_params.x);
  let turbulence = u.zoom_params.y * 2.5;
  let fadeRate = mix(0.92, 0.998, u.zoom_params.z);
  let glowAmount = mix(0.3, 1.8, u.zoom_params.w);

  let mouseRadius = mix(0.03, 0.15, 0.5);
  let colorShift = 0.6;
  let vortexStrength = 1.5;

  // Mouse state
  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0) for next frame
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // ═══ FEEDBACK FIELD VELOCITY ═══
  // Read previous velocity and density from dataTextureC
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  // Advect velocity (semi-Lagrangian backtrace)
  let backUV = uv - prevVel * px * 2.5;
  var vel = sampleVelocity(dataTextureC, clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0))) * viscosity;

  // Advect density
  let densBackUV = uv - prevVel * px * 3.0;
  var dens = sampleDensity(dataTextureC, clamp(densBackUV, vec2<f32>(0.0), vec2<f32>(1.0))) * fadeRate;

  // Curl noise base turbulence (from feedback field)
  let curl = curlNoise(uv * 5.0 + time * 0.1);
  vel += curl * turbulence * 0.015;

  // ═══ MOUSE FLUID COUPLING ═══
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  // Mouse velocity as body force
  vel = vel + mouseVel * influence * 0.5;

  // Vortex force: perpendicular to mouse motion
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  // Click ripples = fluid injection points
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

  // Mouse density injection (colorful source)
  let hue = fract(time * 0.1);
  let sourceColor = vec3<f32>(
    0.5 + 0.5 * cos(hue * 6.28),
    0.5 + 0.5 * cos(hue * 6.28 + 2.09),
    0.5 + 0.5 * cos(hue * 6.28 + 4.18)
  );
  dens += length(mouseVel) * influence * 2.0;

  // Damping at edges
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;

  // Clamp to prevent explosion
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 3.0);

  // ═══ COMPOSITE WITH IMAGE ═══
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Blur and color shift based on fluid thickness
  let blurAmount = dens * colorShift * 0.015;
  let blurUV = uv + vel * blurAmount * 5.0;
  let blurredColor = textureSampleLevel(readTexture, u_sampler, clamp(blurUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  // Color absorption: thicker fluid = warmer tint
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * colorShift * 0.3);
  let tinted = blurredColor * fluidTint;

  // Glow approximation (radial samples)
  var glow = vec3<f32>(0.0);
  let glowSamples = 8;
  for (var g = 0; g < glowSamples; g++) {
    let angle = f32(g) * 6.28318 / f32(glowSamples);
    let radius = 0.015 * (1.0 + f32(g % 3) * 0.5);
    let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
    let gUV = clamp(uv + vel * 0.05 + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    glow += textureSampleLevel(readTexture, u_sampler, gUV, 0.0).rgb;
  }
  glow = glow / f32(glowSamples) * glowAmount * dens;

  // Specular highlight on fluid surface near mouse
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;

  // Combine: base + density color + glow + specular
  let densityColor = sourceColor * dens * 0.4;
  var color = mix(baseColor, tinted, min(dens * 0.3, 0.7));
  color += densityColor;
  color += glow;
  color += vec3<f32>(0.9, 0.95, 1.0) * specular;

  // Color grading - boost saturation
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(luma), color, 1.3);

  // Store velocity (RG) and density (A) for next frame
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, id, vec4<f32>(vel, vorticity, dens));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.7, 1.0, dens * 0.3);

  textureStore(writeTexture, id, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(2.0)), alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - dens * 0.15), 0.0, 0.0, 0.0));
}
