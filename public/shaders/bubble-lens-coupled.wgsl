// ═══════════════════════════════════════════════════════════════════
//  Bubble Lens Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, lens-distortion, temporal
//  Complexity: High
//  Chunks From: bubble-lens.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-9
// ═══════════════════════════════════════════════════════════════════
//  A magnifying bubble lens warped by fluid dynamics. Mouse movement
//  drags a viscous fluid that distorts the lens boundary and creates
//  vortices inside the bubble. Fluid density adds color absorption.
//  Click ripples create fluid bursts that ripple the lens surface.
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
  zoom_params: vec4<f32>,  // x=Radius, y=Magnification, z=FilmThickness, w=Viscosity
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

// Schlick Fresnel (from bubble-lens.wgsl)
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Parameters
  let bubbleRadius = u.zoom_params.x * 0.3 + 0.1;
  let magnification = u.zoom_params.y * 2.0 + 1.0;
  let filmThickness = u.zoom_params.z * 2.0 + 0.5;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // ── Fluid Simulation (from mouse-fluid-coupling) ──
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = sampleVelocity(dataTextureC, backUV);
  let advectedDens = sampleDensity(dataTextureC, backUV);

  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let mouseRadius = mix(0.03, 0.15, u.zoom_params.w);
  let influence = smoothstep(mouseRadius, 0.0, dist);

  vel = vel + mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  let vortexStrength = 2.0;
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  // Click ripples = fluid injection
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

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  // ── Bubble Lens Logic (from bubble-lens) ──
  // Fluid deforms the bubble boundary
  let fluidDeform = length(vel) * 0.05;
  let deformedRadius = bubbleRadius + fluidDeform * sin(atan2(toMouse.y, toMouse.x) * 3.0 + time * 2.0);

  // IOR from fluid density
  let ior = 1.3 + dens * 0.2;
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

  var finalColor: vec3<f32>;
  var warpedUV = uv;
  var baseAlpha: f32 = 1.0;

  if (dist < deformedRadius) {
    // Inside bubble - lens magnification + fluid distortion
    let factor = dist / deformedRadius;
    let lensStrength = (1.0 - factor * factor) * (magnification - 1.0);
    let direction = normalize(toMouse);

    // Displace towards center for magnifying effect
    let displacement = direction * lensStrength * deformedRadius * (1.0 - factor);
    // Add fluid velocity distortion inside bubble
    let fluidWarp = vel * dens * 0.02 * (1.0 - factor);
    warpedUV = uv - displacement / vec2<f32>(aspect, 1.0) + fluidWarp;
    warpedUV = clamp(warpedUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

    // Thin film interference colors
    let phase = filmThickness * 10.0 * (1.0 - factor) + dens * 2.0;
    let interference = vec3<f32>(
      0.5 + 0.5 * cos(phase),
      0.5 + 0.5 * cos(phase + 2.09),
      0.5 + 0.5 * cos(phase + 4.18)
    );

    // Fresnel at edges
    let viewDir = vec2<f32>(0.0, 0.0) - toMouse;
    let cosTheta = dot(normalize(viewDir), vec2<f32>(0.0, 1.0));
    let fresnel = schlickFresnel(abs(cosTheta), F0);

    finalColor = mix(sample.rgb, sample.rgb * interference * 1.2, fresnel * 0.5);
    baseAlpha = sample.a;

    // Fluid color absorption: thicker fluid = warmer tint
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
    finalColor = finalColor * fluidTint;

    // Specular highlight on fluid surface
    let specNoise = hash12(uv * 300.0 + time * 2.0);
    let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
    finalColor = finalColor + vec3<f32>(0.9, 0.95, 1.0) * specular;

    // Add highlight
    let highlight = pow(max(0.0, 1.0 - dist / deformedRadius), 3.0) * fresnel;
    finalColor = finalColor + vec3<f32>(highlight);

    // Alpha = physical transmittance * fluid density
    let absorption = exp(-filmThickness * 0.5);
    let alpha = mix(absorption, 1.0, fresnel) * mix(0.5, 1.0, dens * 0.3);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, clamp(alpha, 0.0, 1.0)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, warpedUV, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  } else {
    // Outside bubble - slight fluid distortion
    let outsideWarp = uv + vel * dens * 0.005;
    let sample = textureSampleLevel(readTexture, u_sampler, outsideWarp, 0.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), sample);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  }
}
