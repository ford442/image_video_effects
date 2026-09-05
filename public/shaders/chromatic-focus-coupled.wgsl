// ═══════════════════════════════════════════════════════════════════
//  chromatic-focus-coupled — Fluid-Coupled Chromatic DOF
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fluid-simulation, chromatic-aberration, semantic-alpha, ACES
//  Complexity: High
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Blur, z=FocusRad, w=Viscosity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let strength = u.zoom_params.x * 0.06 * (1.0 + bass * 0.3);
  let blurAmt = u.zoom_params.y;
  let focusRad = u.zoom_params.z;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  // Exact fluid simulation state loaded from dataTextureC
  let prevFluid = textureLoad(dataTextureC, coord, 0);
  let prevVel = prevFluid.xy;
  let prevDens = prevFluid.a;

  let backCoord = clamp(coord - vec2<i32>(prevVel * 3.0), vec2<i32>(0), vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1));
  let advected = textureLoad(dataTextureC, backCoord, 0);
  var vel = advected.xy * viscosity;
  var dens = advected.a * viscosity;

  let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(toMouse);
  let mouseRadius = mix(0.04, 0.18, u.zoom_params.w);
  let influence = smoothstep(mouseRadius, 0.0, dist) * (0.6 + held * 0.4);

  let mouseVel = (rawMouse - mouse) * 40.0;
  vel += mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel += vortexDir * influence * 1.5;

  // Click ripple bursts
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
      vel += outward * rInfluence * 0.35;
      dens += rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  vel = vel * smoothstep(0.02, 0.08, edgeDist);
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let vorticity = vel.x - vel.y;
  textureStore(dataTextureA, coord, vec4<f32>(vel, vorticity, dens));

  // Chromatic focus calculation
  let center = mouse + vel * 0.02;
  let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
  let focusDist = length(distVec);

  let fluidBlur = dens * blurAmt * 0.5;
  var amount = smoothstep(focusRad, focusRad + 0.5, focusDist);
  amount = pow(amount, 1.0 / (1.0 + fluidBlur * 5.0)) + fluidBlur;

  var dir = normalize(distVec + vec2<f32>(1e-5));
  let twist = vorticity * 0.5 + mids * 0.3;
  let cosT = cos(twist);
  let sinT = sin(twist);
  dir = vec2<f32>(dir.x * cosT - dir.y * sinT, dir.x * sinT + dir.y * cosT);

  let rOffset = dir * amount * strength * (1.0 + dens * 0.3);
  let bOffset = -dir * amount * strength * (1.0 + dens * 0.3);
  let blurVec = vel * dens * 0.01;

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset + blurVec, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + blurVec * 0.5, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset - blurVec, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;

  var color = vec3<f32>(r, g, b);
  let vig = 1.0 - amount * 0.3;
  color *= vig;

  if (held > 0.5) {
    let ring = abs(focusDist - focusRad);
    if (ring < 0.006) {
      color += vec3<f32>(0.5, 0.6, 0.8);
    }
  }

  let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 0.6), dens * blurAmt);
  color *= fluidTint;

  let specNoise = hash12(uv * 300.0 + time * 2.0);
  let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
  color += vec3<f32>(0.9, 0.95, 1.0) * specular;

  let blurThickness = amount * 5.0 + blurAmt * 2.0;
  let alphaR = exp(-blurThickness * 0.5625);
  let alphaG = exp(-blurThickness * 0.7375);
  let alphaB = exp(-blurThickness * 0.9125);
  let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + held * 0.1, 0.1, 1.0);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
