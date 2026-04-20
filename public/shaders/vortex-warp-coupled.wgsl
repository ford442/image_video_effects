// ═══════════════════════════════════════════════════════════════════
//  vortex-warp-coupled
//  Category: advanced-hybrid
//  Features: vortex-warp, fluid-simulation, mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: vortex-warp, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Vortex warp rotation coupled with viscous fluid dynamics.
//  The fluid velocity field drives additional vortex rotation,
//  creating coupled fluid-vortex dynamics. Fluid thickness modulates
//  warp strength, and vortices stir the fluid in return.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn sampleVelocity(tex: texture_2d<f32>, uv: vec2<f32>) -> vec2<f32> {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, uv: vec2<f32>) -> f32 {
  return textureSampleLevel(tex, u_sampler, uv, 0.0).a;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let strengthBase = (u.zoom_params.x - 0.5) * 10.0;
  let radius = u.zoom_params.y * 0.5 + 0.05;
  let twistBase = u.zoom_params.z * 10.0;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous fluid state
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  // Advect fluid
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = sampleVelocity(dataTextureC, backUV);
  let advectedDens = sampleDensity(dataTextureC, backUV);

  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  // Mouse force
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let distMouse = length(toMouse);
  let influence = smoothstep(radius, 0.0, distMouse);
  vel = vel + mouseVel * influence * 0.5;

  // Vortex force from fluid
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * mouseSpeed * 2.0;

  // Click ripples
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

  // ═══ COUPLED VORTEX WARP ═══
  // Fluid velocity adds to vortex rotation
  let fluidVortexStrength = length(vel) * 5.0;
  let strength = strengthBase + fluidVortexStrength * sign(strengthBase);
  let twist = twistBase + dens * 2.0;

  let diff = uv - mousePos;
  let diffAspect = diff * vec2<f32>(aspect, 1.0);
  let dist = length(diffAspect);

  var finalUV = uv;
  var distortionMag = 0.0;
  var percent = 0.0;

  if (dist < radius) {
    percent = (radius - dist) / radius;
    let weight = percent * percent;
    let theta = weight * strength;
    let spiralAngle = twist * weight * dist;
    let totalAngle = theta + spiralAngle;
    distortionMag = abs(strength) * percent * percent + abs(twist) * percent * dist * 0.1;

    let s = sin(totalAngle);
    let c = cos(totalAngle);
    let squareDiff = vec2<f32>(diff.x * aspect, diff.y);
    let rotatedSquareDiff = vec2<f32>(
      squareDiff.x * c - squareDiff.y * s,
      squareDiff.x * s + squareDiff.y * c
    );
    let rotatedDiff = vec2<f32>(rotatedSquareDiff.x / aspect, rotatedDiff.y);
    finalUV = mousePos + rotatedDiff;
  }

  // Sample with fluid blur
  let blurAmount = dens * 0.02;
  let blurUV = finalUV + vel * blurAmount * 5.0;
  let warpedSample = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0);

  // Color absorption
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
  let tinted = warpedSample.rgb * fluidTint;

  // Specular highlight
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  let outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular;

  // Pressure-based alpha
  let pressureAlpha = mix(0.9, 0.6, percent);
  let scatteringLoss = distortionMag * 0.3;
  let finalAlpha = clamp(warpedSample.a * pressureAlpha - scatteringLoss, 0.4, 1.0);

  // Store fluid state
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, finalAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthMod = 1.0 + distortionMag * 0.05;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
