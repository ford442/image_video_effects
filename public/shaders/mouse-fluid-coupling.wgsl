// ═══════════════════════════════════════════════════════════════════
//  mouse-fluid-coupling
//  Category: interactive-mouse
//  Features: mouse-driven, fluid-simulation, temporal
//  Complexity: High
//  Chunks From: chunk-library.md (hash12)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  The mouse drags a viscous fluid over the image. Fluid thickness
//  determines color absorption and blur. Vortex streets form from
//  fast movement. Uses dataTextureC for velocity history.
//  Alpha channel stores fluid density/thickness.
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

  let viscosity = mix(0.92, 0.99, u.zoom_params.x);
  let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let vortexStrength = u.zoom_params.w * 2.0;

  // Mouse state
  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Pixel size for finite differences
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
  let influence = smoothstep(mouseRadius, 0.0, dist);

  // Add mouse velocity as body force
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
      // Radial outward burst
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

  // Visual output: blur and color shift based on fluid thickness
  let blurAmount = dens * colorShift * 0.02;
  let blurUV = uv + vel * blurAmount * 5.0;

  let baseColor = textureSampleLevel(readTexture, u_sampler, blurUV, 0.0).rgb;

  // Color absorption: thicker fluid = warmer tint
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * colorShift);
  let tinted = baseColor * fluidTint;

  // Specular highlight on fluid surface near mouse
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  let outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular;

  // Store velocity (RG) and density (A) for next frame
  // B is unused but store vorticity approximation
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  // Alpha = fluid density/thickness
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, dens));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
