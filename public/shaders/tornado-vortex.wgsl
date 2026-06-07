// ═══════════════════════════════════════════════════════════════════
//  Tornado Vortex
//  Category: generative
//  Features: generative, audio-reactive, rankine-vortex, lagrangian-debris,
//            lightning-illumination, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let intensity = u.zoom_params.x;
  let spinSpeed = u.zoom_params.y * 5.0;
  let debrisAmt = u.zoom_params.z;
  let lightningAmt = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let dist = length(p);
  let angle = atan2(p.y, p.x);

  // Rankine vortex: viscous core + potential flow outside
  let coreRadius = 0.04 * (1.0 + mids * 0.5);
  let circulation = 0.15 * intensity * (1.0 + bass * 0.4);
  let vTheta = select(circulation / (6.28318530718 * dist), circulation * dist / (6.28318530718 * coreRadius * coreRadius), dist > coreRadius);
  let vRadial = -0.02 * intensity * smoothstep(0.3, 0.0, dist);
  let vVertical = 0.1 * intensity * smoothstep(-0.3, 0.4, uv.y) * smoothstep(0.0, 0.1, dist);

  var color = vec3<f32>(0.04, 0.06, 0.09);
  var debrisDensity = 0.0;
  var condensation = 0.0;

  // Funnel condensation with subsurface scattering
  let funnelWidth = coreRadius + (uv.y + 0.5) * 0.22 * (1.0 + mids * 0.4);
  let funnelDist = abs(dist - funnelWidth * (0.55 + sin(uv.y * 12.0 + time * 0.8) * 0.08 * intensity));
  condensation = smoothstep(0.045 * intensity, 0.0, funnelDist) * smoothstep(-0.5, 0.5, uv.y);
  let sss = condensation * condensation * vec3<f32>(0.35, 0.42, 0.48) * 0.6;

  // Spiral streaks from vorticity
  let spiralPhase = angle + vTheta * time * spinSpeed * 40.0 + uv.y * 18.0;
  let spiral = sin(spiralPhase) * 0.5 + 0.5;
  let spiralMask = condensation * spiral * (0.4 + mids * 0.4);
  color = color + vec3<f32>(0.35, 0.40, 0.45) * spiralMask;

  // Lagrangian debris advection
  let debrisCount = 24;
  for (var di = 0; di < debrisCount; di = di + 1) {
    let df = f32(di);
    let seed = hash21(vec2<f32>(df, 0.0));
    let dh = fract(df / f32(debrisCount) + time * 0.08 * (1.0 + bass) + seed * 0.3);
    let dAngle = df * 2.39996 + dh * 8.0 + time * spinSpeed * 0.25 + vTheta * 10.0;
    let dRadius = 0.015 + dh * funnelWidth * 1.1;
    let dPos = vec2<f32>(cos(dAngle), sin(dAngle)) * dRadius;
    let dd = length(p - dPos);
    let dSize = 0.0025 * (1.0 + debrisAmt) * (1.0 + depth * 0.5);
    let particle = smoothstep(dSize, 0.0, dd);
    let sizeFade = 1.0 - smoothstep(0.0, 0.35, dh);
    debrisDensity = debrisDensity + particle * sizeFade;
    color = color + vec3<f32>(0.55, 0.50, 0.45) * particle * debrisAmt * sizeFade;
  }

  // Mouse probe flung by vortex
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseWorld);
  let fling = smoothstep(0.12, 0.0, mouseDist) * vTheta * 3.0 * intensity;
  color = color + vec3<f32>(0.7, 0.65, 0.55) * fling;

  // Lightning flashes triggered by treble
  let flashTime = floor(time * (6.0 + treble * 8.0));
  let flash = hash31(vec3<f32>(flashTime, 0.0, 0.0));
  var lightning = step(1.0 - lightningAmt * 0.12 - treble * 0.08, flash) * smoothstep(0.35, 0.0, dist);
  let lightningBranch = sin(angle * 9.0 + flashTime * 3.7) * 0.5 + 0.5;
  lightning = lightning * (0.4 + lightningBranch * 0.6);
  color = color + vec3<f32>(0.92, 0.96, 1.0) * lightning * (1.0 + treble);

  // Ground dust
  let dust = hash21(uv * 55.0 + time * 0.4) * smoothstep(0.0, -0.25, uv.y) * 0.25 * intensity;
  color = color + vec3<f32>(0.38, 0.33, 0.28) * dust;

  // HDR bloom on electrical discharge
  color = color + vec3<f32>(0.5, 0.6, 0.7) * lightning * lightning * 0.4;

  // ACES tone mapping
  color = acesToneMap(color * 1.4);

  // Depth controls debris size perspective (already in dSize)
  let depthFade = 1.0 - depth * 0.2;
  color = color * depthFade;

  // Alpha: debris density * condensation_opacity * depth
  let condOpacity = condensation * 0.85 + spiralMask * 0.4;
  let alpha = clamp((debrisDensity * 0.3 + condOpacity) * (0.5 + depth * 0.5), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(condensation * 0.5 + debrisDensity * 0.2, 0.0, 0.0, 0.0));
}
