// ═══════════════════════════════════════════════════════════════════
//  Chromatic Focus Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, chromatic, temporal
//  Complexity: High
//  Chunks From: chromatic-focus-interactive.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  Chromatic aberration DOF with fluid-coupled distortion. Mouse
//  movement stirs a viscous fluid that twists and blurs chromatic
//  channels. Click ripples inject fluid bursts. Focus point is
//  advected by fluid velocity.
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Blur, z=FocusRad, w=Viscosity
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from mouse-fluid-coupling.wgsl) ═══
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

  // Parameters
  let strength = u.zoom_params.x * 0.05;
  let blurAmt = u.zoom_params.y;
  let focusRad = u.zoom_params.z;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── Fluid Simulation (from mouse-fluid-coupling) ──
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous velocity and density from dataTextureC
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  // Advect velocity (semi-Lagrangian)
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = sampleVelocity(dataTextureC, backUV);
  let advectedDens = sampleDensity(dataTextureC, backUV);

  // Apply viscosity
  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  // Mouse force: stirring rod
  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let mouseRadius = mix(0.03, 0.15, u.zoom_params.w);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  // Add mouse velocity as body force
  vel = vel + mouseVel * influence * 0.5;

  // Vortex force: perpendicular to mouse motion
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  let vortexStrength = 2.0;
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

  // Damping at edges
  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;

  // Clamp to prevent explosion
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  // Store velocity (RG) and density (A) for next frame
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  // ── Chromatic Focus Logic (from chromatic-focus-interactive) ──
  // Focus point advected by fluid velocity
  var center = mousePos + vel * 0.02;
  let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
  let focusDist = length(distVec);

  // Blur amount enhanced by fluid density
  let fluidBlur = dens * blurAmt * 0.5;
  var amount = smoothstep(focusRad, focusRad + 0.5, focusDist);
  amount = pow(amount, 1.0 / (1.0 + fluidBlur * 5.0));
  amount = amount + fluidBlur;

  var dir = normalize(distVec);

  // Chromatic aberration twisted by fluid vorticity
  let twist = vorticity * 0.5;
  let cosT = cos(twist);
  let sinT = sin(twist);
  dir = vec2<f32>(dir.x * cosT - dir.y * sinT, dir.x * sinT + dir.y * cosT);

  let rOffset = dir * amount * strength * (1.0 + dens * 0.3);
  let bOffset = -dir * amount * strength * (1.0 + dens * 0.3);
  let gOffset = vec2<f32>(0.0);

  // Fluid-blurred sample offsets
  let blurVec = vel * dens * 0.01;
  let r = textureSampleLevel(readTexture, u_sampler, uv + rOffset + blurVec, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv + gOffset + blurVec * 0.5, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + bOffset - blurVec, 0.0).b;

  var color = vec3<f32>(r, g, b);

  // Vignette
  let vig = 1.0 - amount * 0.3;
  color = color * vig;

  // Show focus ring if clicking
  if (mouseDown > 0.5) {
    let ring = abs(focusDist - focusRad);
    if (ring < 0.005) {
      color = color + vec3<f32>(0.5, 0.5, 0.5);
    }
  }

  // Fluid tint: thicker fluid = warmer tint
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * blurAmt);
  color = color * fluidTint;

  // Specular highlight on fluid surface near mouse
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  color = color + vec3<f32>(0.9, 0.95, 1.0) * specular;

  // Wavelength-dependent alpha (from chromatic-focus-interactive)
  let blurThickness = amount * 5.0 + blurAmt * 2.0;
  let lambdaR = (800.0 - 650.0) / 400.0;
  let lambdaG = (800.0 - 550.0) / 400.0;
  let lambdaB = (800.0 - 450.0) / 400.0;
  let alphaR = exp(-blurThickness * mix(0.3, 1.0, lambdaR));
  let alphaG = exp(-blurThickness * mix(0.3, 1.0, lambdaG));
  let alphaB = exp(-blurThickness * mix(0.3, 1.0, lambdaB));
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);

  let finalColor = vec3<f32>(color.r * alphaR, color.g * alphaG, color.b * alphaB);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
