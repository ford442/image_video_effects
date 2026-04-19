// ═══════════════════════════════════════════════════════════════════
//  liquid-jelly-fluid
//  Category: advanced-hybrid
//  Features: liquid-jelly, fluid-simulation, elastic-bounce, subsurface-scattering
//  Complexity: Very High
//  Chunks From: liquid-jelly.wgsl, alpha-fluid-simulation-paint.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Elastic jelly meets Navier-Stokes fluid simulation. The jelly
//  body is advected by a velocity field while preserving elastic
//  ripple bounce and subsurface scattering glow.
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

// ═══ CHUNK: hsv2rgb (from alpha-fluid-simulation-paint.wgsl) ═══
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let h = hsv.x * 6.0;
  let s = hsv.y;
  let v = hsv.z;
  let c = v * s;
  let x = c * (1.0 - abs(h - floor(h / 2.0) * 2.0 - 1.0));
  let m = v - c;
  var rgb: vec3<f32>;
  if (h < 1.0) { rgb = vec3(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
  else { rgb = vec3(c, 0.0, x); }
  return rgb + vec3(m);
}

// ═══ CHUNK: schlickFresnel (from liquid-jelly.wgsl) ═══
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;
  let ps = 1.0 / resolution;
  let dt = 0.016;

  let viscosityParam = u.zoom_params.x;
  let dyeIntensity = u.zoom_params.y;
  let vorticityStrength = u.zoom_params.z;
  let elasticity = u.zoom_params.w;

  let center_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let fg_factor = 1.0 - smoothstep(0.8, 0.95, center_depth);

  // === FLUID SIMULATION (from alpha-fluid-simulation-paint) ===
  let prevState = textureLoad(dataTextureC, coord, 0);
  var vel = prevState.rg;
  var pressure = prevState.b;
  var density = prevState.a;

  let maxVel = 0.5;
  vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

  // Advection
  let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
  let advected = textureSampleLevel(dataTextureC, u_sampler, backtraceUV, 0.0);
  vel = advected.rg;
  density = advected.a;

  // Diffusion
  let fluidViscosity = viscosityParam * 0.001 + 0.0001;
  let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  vel += fluidViscosity * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

  // Pressure projection
  let pL = left.b;
  let pR = right.b;
  let pD = down.b;
  let pU = up.b;
  let divergence = ((pR - pL) / (2.0 * ps.x) + (pU - pD) / (2.0 * ps.y));
  pressure = (pL + pR + pD + pU - divergence * ps.x * ps.x * 4.0) * 0.25;
  pressure = clamp(pressure, -2.0, 2.0);
  vel -= vec2<f32>((pR - pL) / (2.0 * ps.x), (pU - pD) / (2.0 * ps.y)) * 0.5;
  vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

  // Vorticity confinement
  let vortL = left.rg.y;
  let vortR = right.rg.y;
  let vortD = down.rg.x;
  let vortU = up.rg.x;
  let curl = (vortR - vortL) - (vortU - vortD);
  vel += vec2<f32>(abs(curl) * sign(curl) * vorticityStrength * 0.005) * vec2<f32>(1.0, -1.0);
  vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

  // === ELASTIC JELLY BOUNCE (from liquid-jelly) ===
  var displacement = vec2<f32>(0.0);
  var shadow_accum = 0.0;
  var totalWobble = 0.0;

  if (fg_factor > 0.0) {
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
      let rippleData = u.ripples[i];
      let timeSinceClick = currentTime - rippleData.z;
      if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
        let direction_vec = uv - rippleData.xy;
        let dist = length(direction_vec);
        let bounce_freq = 8.0;
        let decay = 2.0;
        let amplitude = 0.05 * elasticity;
        let radius = 0.15;
        let bounce = sin(timeSinceClick * bounce_freq) * exp(-timeSinceClick * decay);
        let shape = smoothstep(radius * 1.5, 0.0, dist);
        displacement += direction_vec * bounce * shape * amplitude * 10.0;
        let edge = smoothstep(0.0, radius, dist) * smoothstep(radius, 0.0, dist);
        shadow_accum += edge * abs(bounce) * 2.0;
        totalWobble += abs(bounce) * shape;
      }
    }
  }

  // Add elastic displacement to fluid velocity
  vel += displacement * fg_factor * 2.0;
  vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

  // Mouse force
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
  let mouseForce = normalize(uv - mousePos + vec2<f32>(0.0001)) * mouseInfluence * -0.3 * mouseDown;
  vel += mouseForce * dt * 15.0;

  // Ripple dye injection
  let rippleCount2 = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount2; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleDist = length(uv - ripple.xy);
    let age = currentTime - ripple.z;
    if (age < 2.0 && rippleDist < 0.08) {
      let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
      density += inject * 0.5;
      let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
      vel += dir * inject * 0.1;
    }
  }

  // Decay
  let decayRate = mix(0.990, 0.999, viscosityParam);
  density *= decayRate;
  density = clamp(density, 0.0, 5.0);

  // Store simulation state
  textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, density));

  // === VISUALIZATION ===
  let speed = length(vel);
  let hue = atan2(vel.y, vel.x) / 6.283185307 + 0.5;
  let sat = smoothstep(0.0, 0.02, speed) * 0.8;
  let val = density * dyeIntensity * 1.5 + 0.15;
  let fluidColor = hsv2rgb(vec3<f32>(hue, sat, min(val, 1.0)));

  // Sample displaced image for jelly overlay
  let finalDisplacement = displacement * fg_factor;
  let displacedUV = uv - finalDisplacement;
  let clampedUV = clamp(displacedUV, vec2(0.0), vec2(1.0));
  var baseColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0).rgb;

  // Subsurface scattering
  let scatterColor = vec3<f32>(1.0, 0.9, 0.7);
  let jellyThickness = length(finalDisplacement) * 5.0 + 0.2;
  let absorption = exp(-jellyThickness * 1.5);
  let scattered = mix(scatterColor, baseColor, absorption);
  let shadowed = scattered * (1.0 - shadow_accum * 0.4);
  let highlight = vec3<f32>(0.1, 0.15, 0.2) * totalWobble;
  let jellyColor = shadowed + highlight;

  // Blend fluid visualization with jelly
  let blendFactor = smoothstep(0.0, 0.3, density) * fg_factor;
  let finalColor = mix(jellyColor, fluidColor, blendFactor);

  // Alpha
  let normal = normalize(vec3<f32>(
    -finalDisplacement.x * 10.0,
    -finalDisplacement.y * 10.0,
    1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  let F0 = 0.04;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  let scattering = exp(-jellyThickness * 2.0) * (1.0 - smoothstep(0.0, 0.5, totalWobble) * 0.3);
  let baseAlpha = mix(0.5, 0.9, scattering);
  let alpha = baseAlpha * (1.0 - fresnel * 0.3) * fg_factor;

  let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let finalAlpha = mix(alpha * 0.8, alpha, center_depth) * mix(0.9, 1.0, luma);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
