// ═══════════════════════════════════════════════════════════════════
//  Liquid Jelly (Upgraded Batch 51)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-08-15
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

fn fresnelSchlick(cosTheta: f32, f0: f32) -> f32 {
  return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  return clamp((color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Viscoelastic Kelvin-Voigt harmonic modal oscillation
fn viscoelasticModalFlow(p: vec2<f32>, time: f32, elast: f32, damp: f32) -> vec2<f32> {
  let omega1 = 2.4 + elast * 0.8;
  let omega2 = 3.2 + elast * 1.1;
  let k1 = 4.0;
  let k2 = 6.0;
  let dispX = sin(p.y * k1 + time * omega1) * cos(p.x * k2 - time * omega2 * 0.7);
  let dispY = cos(p.x * k1 - time * omega1 * 0.85) * sin(p.y * k2 + time * omega2);
  return vec2<f32>(dispX, dispY) * (0.0035 / (1.0 + damp * 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let texel = 1.0 / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let damping = mix(0.8, 3.8, u.zoom_params.x);
  let elasticity = mix(2.5, 14.0, u.zoom_params.y);
  let wobbleStrength = mix(0.006, 0.075, u.zoom_params.z);
  let tintShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let foreground = 1.0 - smoothstep(0.72, 0.98, centerDepth);

  // Dual continuous motion: Primary viscoelastic standing mode + Secondary gelatin shear
  let pAspect = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let modalFlow = viscoelasticModalFlow(pAspect, time, elasticity, damping) * foreground;
  let gelatinShear = vec2<f32>(
    sin(pAspect.y * 11.0 + time * (1.2 + audio.x * 2.0)),
    cos(pAspect.x * 10.0 - time * (1.0 + audio.y * 1.5))
  ) * (0.0018 / (1.0 + damping * 0.3)) * foreground;

  var displacement = modalFlow + gelatinShear;
  var wobbleEnergy = 0.0;
  var edgeEnergy = 0.0;

  // Interactive pointer drag / spring mass tether
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w;
  let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let mouseDist = max(length(mouseDelta), 0.001);
  let tetherEnvelope = exp(-mouseDist * mix(7.0, 3.2, u.zoom_params.z));
  let tetherPhase = sin(time * elasticity * 1.2 - mouseDist * 14.0);
  let tetherForce = (mouseDelta / mouseDist) * tetherPhase * tetherEnvelope * (0.012 + wobbleStrength * 0.4) * (1.0 + isMouseDown * 2.5);
  displacement += vec2<f32>(tetherForce.x / aspect, tetherForce.y) * foreground;
  wobbleEnergy += tetherEnvelope * abs(tetherPhase);

  // 50-ripple shockwaves with Kelvin-Voigt damped response
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rip = u.ripples[i];
    let age = time - rip.z;
    if (age > 0.0 && age < 3.8) {
      let rDelta = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
      let rDist = max(length(rDelta), 0.0001);
      let rDir = rDelta / rDist;
      let spring = sin(age * (elasticity + audio.x * 5.0) - rDist * 18.0) * exp(-age * damping);
      let shape = exp(-rDist * mix(16.0, 4.5, u.zoom_params.z));
      let local = spring * shape;

      displacement += vec2<f32>(rDir.x / aspect, rDir.y) * local * wobbleStrength * (1.0 + audio.x * 0.65) * foreground;
      wobbleEnergy += abs(local);
      edgeEnergy += abs(spring) * pow(clamp(1.0 - abs(rDist - 0.15) * 7.5, 0.0, 1.0), 3.0);
    }
  }

  // Optical refraction and subsurface scattering
  let displacedUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // Exact-load temporal state feedback from dataTextureC
  let histCoord = clamp(vec2<i32>(floor((uv + displacement * 0.25) * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
  let history = textureLoad(dataTextureC, histCoord, 0);

  // 2.5D surface normal & Fresnel rim
  let normal = normalize(vec3<f32>(-displacement.x * 28.0, -displacement.y * 28.0, 1.0));
  let fresnel = fresnelSchlick(max(normal.z, 0.0), 0.045);

  let thickness = clamp(0.12 + length(displacement) * 22.0 + wobbleEnergy * 0.12, 0.0, 1.8);
  let warmTint = vec3<f32>(1.0, 0.42, 0.22);
  let coolTint = vec3<f32>(0.16, 0.62, 1.0);
  let scatterTint = mix(warmTint, coolTint, tintShift);
  let absorption = exp(-thickness * vec3<f32>(1.6, 1.05, 0.6));

  var rgb = mix(scatterTint, baseColor.rgb, absorption) + scatterTint * edgeEnergy * (0.14 + audio.y * 0.35) + fresnel * vec3<f32>(0.15, 0.22, 0.3);

  let trailMix = clamp((0.08 + u.zoom_params.x * 0.18) * history.a, 0.05, 0.32);
  rgb = mix(rgb, history.rgb, trailMix);
  rgb = acesToneMapping(rgb);

  let alpha = clamp(baseColor.a * foreground * (0.75 + thickness * 0.18) + edgeEnergy * 0.15 + fresnel * 0.12, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outputColor);
  textureStore(dataTextureA, coord, outputColor);

  let outDepth = clamp(centerDepth + length(displacement) * 0.25 - wobbleEnergy * 0.05, 0.0, 1.0);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
