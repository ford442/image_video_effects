// ═══════════════════════════════════════════════════════════════════
//  interactive-origami-coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, geometric
//  Complexity: High
//  Chunks From: interactive-origami.wgsl, mouse-fluid-coupling.wgsl
//  Created: 2026-04-18
//  By: Agent CB-25
// ═══════════════════════════════════════════════════════════════════
//  Folded paper creases react to mouse position while viscous fluid
//  drags across the surface, warping the folds. Fluid thickness
//  creates color absorption and vortex streets from fast movement.
//  Alpha stores fluid density.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let foldScale = mix(2.0, 20.0, u.zoom_params.x);
  let foldDepth = u.zoom_params.y * 0.05;
  let viscosity = mix(0.92, 0.99, u.zoom_params.z);
  let vortexStrength = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  // Store current mouse position at (0,0)
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let px = vec2<f32>(1.0) / resolution;

  // Read previous fluid state
  let prevVel = sampleVelocity(dataTextureC, uv);
  let prevDens = sampleDensity(dataTextureC, uv);

  // Advect velocity
  let backUV = uv - prevVel * px * 2.0;
  let advectedVel = sampleVelocity(dataTextureC, backUV);
  let advectedDens = sampleDensity(dataTextureC, backUV);

  // Apply viscosity
  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  // Mouse force
  let toMouse = (uv - mousePos) * aspectVec;
  let dist = length(toMouse);
  let influence = smoothstep(0.15, 0.0, dist);
  vel = vel + mouseVel * influence * 0.5;

  // Vortex
  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  // Click ripples
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * aspectVec;
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / aspectVec), rDist > 0.001);
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

  // Origami fold lines around mouse
  let angle1 = 0.5;
  let angle2 = 2.1;
  let angle3 = 4.0;
  let n1 = vec2<f32>(cos(angle1), sin(angle1));
  let n2 = vec2<f32>(cos(angle2), sin(angle2));
  let n3 = vec2<f32>(cos(angle3), sin(angle3));

  let d1 = dot((uv - mousePos) * aspectVec, n1);
  let d2 = dot((uv - mousePos) * aspectVec, n2);
  let d3 = dot((uv - mousePos) * aspectVec, n3);

  let wave1 = abs(sin(d1 * foldScale));
  let wave2 = abs(sin(d2 * foldScale * 0.7));
  let wave3 = abs(sin(d3 * foldScale * 1.3));
  let height = wave1 + wave2 + wave3;

  // Approximate gradient
  let delta = 0.01;
  let h_right = abs(sin((d1 + delta) * foldScale)) + abs(sin((d2 + delta) * foldScale * 0.7)) + abs(sin((d3 + delta) * foldScale * 1.3));
  let h_up = abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n1) * foldScale)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n2) * foldScale * 0.7)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n3) * foldScale * 1.3));
  let grad = vec2<f32>(h_right - height, h_up - height) / delta;

  // Combine fluid velocity with fold displacement
  let foldInfluence = smoothstep(0.8, 0.0, dist);
  let finalUV = uv - grad * foldDepth * foldInfluence + vel * 0.02;

  let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  // Lighting on folds
  let lightDir = normalize(vec2<f32>(-1.0, -1.0));
  let diffuse = dot(normalize(grad), lightDir);
  let ridge = pow(height / 3.0, 4.0);
  let lighting = (diffuse * 0.5 + ridge) * foldInfluence * 0.5;

  // Fluid color absorption
  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
  let tinted = baseColor * fluidTint;

  // Specular highlight
  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  let outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular + vec3<f32>(lighting);

  // Store fluid state
  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, dens));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
