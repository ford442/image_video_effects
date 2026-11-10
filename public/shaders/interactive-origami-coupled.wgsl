// ═══════════════════════════════════════════════════════════════════
//  Interactive Origami Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, geometric, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: capillary pooling in crease valleys; Kármán street along a crease
//  A packing: raw (vx, vy, vorticity, density)
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadFluid(coord: vec2<i32>, maxCoord: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let foldScale = mix(2.0, 20.0, u.zoom_params.x);
  let foldDepth = u.zoom_params.y * 0.05;
  let viscosity = mix(0.92, 0.99, u.zoom_params.z);
  let vortexStrength = u.zoom_params.w * 2.0 * (1.0 + mids * 0.25);

  let mousePos = u.zoom_config.yz;
  let hasStash = arrayLength(&extraBuffer) > 138u;
  var prevMouse = mousePos;
  if (hasStash && extraBuffer[138] > 0.5) {
    prevMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (global_id.x == 0u && global_id.y == 0u && hasStash) {
    extraBuffer[133] = mousePos.x;
    extraBuffer[134] = mousePos.y;
    extraBuffer[138] = 1.0;
  }
  let mouseVel = (mousePos - prevMouse) * 60.0;
  let mouseSpeed = length(mouseVel);

  let px = vec2<f32>(1.0) / resolution;

  let prev = loadFluid(coord, maxCoord);
  let prevVel = prev.xy;
  let prevDens = prev.a;

  let backUV = uv - prevVel * px * 2.0;
  let backCoord = vec2<i32>(clamp(backUV, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution);
  let advected = loadFluid(backCoord, maxCoord);
  let advectedVel = advected.xy;
  let advectedDens = advected.a;

  var vel = advectedVel * viscosity;
  var dens = advectedDens * viscosity;

  let toMouse = (uv - mousePos) * aspectVec;
  let dist = length(toMouse);
  let influence = smoothstep(0.15, 0.0, dist);
  vel = vel + mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * aspectVec;
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let uvDir = rToMouse / aspectVec;
      let outward = select(vec2<f32>(0.0), uvDir / max(length(uvDir), 0.001), rDist > 0.001);
      vel = vel + outward * rInfluence * 0.3;
      dens = dens + rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
  vel = vel * edgeDamp;
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let n1 = vec2<f32>(cos(0.5), sin(0.5));
  let n2 = vec2<f32>(cos(2.1), sin(2.1));
  let n3 = vec2<f32>(cos(4.0), sin(4.0));

  let d1 = dot((uv - mousePos) * aspectVec, n1);
  let d2 = dot((uv - mousePos) * aspectVec, n2);
  let d3 = dot((uv - mousePos) * aspectVec, n3);

  let wave1 = abs(sin(d1 * foldScale));
  let wave2 = abs(sin(d2 * foldScale * 0.7));
  let wave3 = abs(sin(d3 * foldScale * 1.3));
  let height = wave1 + wave2 + wave3;

  let delta = 0.01;
  let h_right = abs(sin((d1 + delta) * foldScale)) + abs(sin((d2 + delta) * foldScale * 0.7)) + abs(sin((d3 + delta) * foldScale * 1.3));
  let h_up = abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n1) * foldScale)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n2) * foldScale * 0.7)) +
             abs(sin(dot(((uv + vec2<f32>(0.0, delta)) - mousePos) * aspectVec, n3) * foldScale * 1.3));
  let grad = vec2<f32>(h_right - height, h_up - height) / delta;

  let foldInfluence = smoothstep(0.8, 0.0, dist);

  // Idea 1 — capillary pooling: density settles into crease valleys
  let valley = 1.0 - clamp(height / 3.0, 0.0, 1.0);
  dens = dens + valley * foldInfluence * (0.018 + bass * 0.012);

  // Idea 2 — Kármán street along crease 1 when the pointer is moving
  let street = sin(d1 * foldScale * 2.2 + time * (4.0 + mouseSpeed * 10.0)) * sign(d1 + 0.0001);
  let creaseTangent = vec2<f32>(-n1.y, n1.x);
  vel = vel + creaseTangent * street * mouseSpeed * vortexStrength * 0.04 * foldInfluence * (0.6 + treble * 0.4);

  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let finalUV = clamp(uv - grad * foldDepth * foldInfluence + vel * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));

  let baseColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  let lightDir = vec2<f32>(-0.70710678, -0.70710678);
  let gLen = max(length(grad), 0.0001);
  let diffuse = dot(grad / gLen, lightDir);
  let ridge = pow(height / 3.0, 4.0);
  let lighting = (diffuse * 0.5 + ridge) * foldInfluence * 0.5;

  let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
  let tinted = baseColor * fluidTint;

  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  var outColor = tinted + vec3<f32>(0.9, 0.95, 1.0) * specular + vec3<f32>(lighting);
  outColor = acesToneMap(outColor);

  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, coord, vec4<f32>(vel, vorticity, dens));

  let alpha = clamp(0.22 + dens * 0.38 + foldInfluence * 0.25, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(outColor, alpha));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
