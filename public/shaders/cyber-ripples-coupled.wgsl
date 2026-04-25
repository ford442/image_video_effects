// ═══════════════════════════════════════════════════════════════════
//  cyber-ripples-coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, digital-ripples, fluid-coupling, temporal
//  Complexity: High
//  Chunks From: cyber-ripples.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Digital ripples propagate through a viscous fluid field. The fluid
//  simulation drives ripple displacement — fast mouse movement creates
//  vortex streets that warp the quantized digital waves. Fluid density
//  determines chromatic aberration strength. Alpha stores fluid density.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let speed = u.zoom_params.x * 5.0 + 1.0;
  let viscosity = mix(0.92, 0.99, u.zoom_params.y);
  let aberration = u.zoom_params.z * 0.05;
  let frequency = u.zoom_params.w * 50.0 + 10.0;

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous fluid state
  let prevVel = textureSampleLevel(dataTextureC, u_sampler, uv).xy;
  let prevDens = textureSampleLevel(dataTextureC, u_sampler, uv).a;

  // Advect
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = textureSampleLevel(dataTextureC, u_sampler, backUV).xy;
  let advectedDens = textureSampleLevel(dataTextureC, u_sampler, backUV).a;

  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  // Mouse force
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mDist = length(toMouse);
  let mouseRadius = mix(0.03, 0.15, 0.5);
  let influence = smoothstep(mouseRadius, 0.0, mDist);
  vel = vel + mouseVel * influence * 0.5;

  // Vortex
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * mouseSpeed;

  // Ripple burst adds fluid
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

  // Digital Ripple (quantized) + fluid displacement
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uvCorrected, mouseCorrected);

  let quantizedDist = floor(dist * 20.0) / 20.0;
  let wave = sin(quantizedDist * frequency - time * speed);
  let strength = 1.0 / (dist * 5.0 + 0.5);
  let displacement = vec2<f32>(wave) * strength * 0.01 + vel * 0.05;

  var displacedUV = uv + displacement;

  // Chromatic aberration scaled by fluid density
  let effAberration = aberration * (1.0 + dens);
  let redUV = displacedUV + vec2<f32>(effAberration, 0.0);
  let blueUV = displacedUV - vec2<f32>(effAberration, 0.0);

  let r = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, blueUV, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Fluid tint
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.3);
  color = color * fluidTint;

  // Specular
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  color = color + vec3<f32>(0.9, 0.95, 1.0) * specular;

  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, dens));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
