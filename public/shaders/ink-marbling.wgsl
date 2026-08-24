// Ink Marbling — Batch 68 persistent pigment/thickness simulation.
// A packs raw pigment.rgb and thickness; B is intentionally unwritten.
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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}
fn rot(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle); let c = cos(angle); return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}
fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.2831853 * (vec3<f32>(t) + vec3<f32>(0.0, 0.33, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let time = u.config.x;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // Saved slots: intensity, speed, scale, detail.
  let warpStrength = u.zoom_params.x * (0.018 + bass * 0.012);
  let flowSpeed = 0.15 + u.zoom_params.y * 0.85;
  let flowScale = mix(2.0, 10.0, u.zoom_params.z);
  let detail = mix(0.3, 1.0, u.zoom_params.w);

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var stirrer = rawMouse; var velocity = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { stirrer = vec2<f32>(extraBuffer[133], extraBuffer[134]); velocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { stirrer = rawMouse; velocity = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 8.0; let springDecay = exp(-omega * dt); let delta = stirrer - rawMouse; let temp = (velocity + omega * delta) * dt;
  velocity = (velocity - omega * temp) * springDecay; stirrer = rawMouse + (delta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = stirrer.x; extraBuffer[134] = stirrer.y; extraBuffer[135] = velocity.x; extraBuffer[136] = velocity.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }

  let p = uv * aspectVec; let centerDelta = p - stirrer * aspectVec; let centerDist = length(centerDelta);
  let swirlMask = smoothstep(0.45, 0.0, centerDist) * (0.25 + 0.75 * u.zoom_config.w);
  let swirlDir = select(vec2<f32>(0.0), vec2<f32>(-centerDelta.y, centerDelta.x) / centerDist, centerDist > 0.001) / aspectVec;
  let waveA = sin(p.yx * flowScale + vec2<f32>(time * flowSpeed, -time * flowSpeed * 0.7));
  let waveB = cos((p.xy + waveA * 0.3) * flowScale * 1.7 + mids * 3.0);
  var flow = (waveA + waveB * detail) * warpStrength * (1.0 + treble * 0.5);
  flow += swirlDir * swirlMask * (0.015 + length(velocity) * 0.08);

  var drop = 0.0; var dropColor = vec3<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 3.0) { continue; }
    let d = length((uv - ripple.xy) * aspectVec);
    let core = exp(-d * d * 90.0) * exp(-age * 1.1);
    let ring = exp(-pow((d - age * 0.09) * 35.0, 2.0)) * (1.0 - age / 3.0);
    drop += core + ring * 0.45;
    dropColor += palette(fract(ripple.z * 0.17 + f32(i) * 0.13)) * (core + ring * 0.25);
    let dir = select(vec2<f32>(0.0), (uv - ripple.xy) / max(d, 0.001), d > 0.001);
    flow += dir / aspectVec * ring * warpStrength * 1.5;
  }

  let advectedUV = clamp(uv - flow - velocity * swirlMask * 0.04, vec2<f32>(0.0), vec2<f32>(1.0));
  let advectedCoord = historyCoord(advectedUV, dims);
  let previous = textureLoad(dataTextureC, advectedCoord, 0);
  let prevL = textureLoad(dataTextureC, clamp(advectedCoord + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let prevR = textureLoad(dataTextureC, clamp(advectedCoord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let prevD = textureLoad(dataTextureC, clamp(advectedCoord + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let prevU = textureLoad(dataTextureC, clamp(advectedCoord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  // Viscosity-dependent pigment diffusion broadens marbled veins without
  // filtering the rgba32float state texture.
  let neighborState = (prevL + prevR + prevD + prevU) * 0.25;
  let diffusion = 0.008 + detail * 0.032 + mids * 0.004;
  let diffusedState = mix(previous, neighborState, diffusion);
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourcePigment = mix(source.rgb, palette(fract(time * 0.025 + dot(uv, vec2<f32>(0.7, 0.3)))), 0.35 + treble * 0.2);
  let injection = clamp(swirlMask * u.zoom_params.x * (0.08 + bass * 0.08) + drop, 0.0, 1.0);
  let retainedThickness = diffusedState.a * (0.988 - flowSpeed * 0.006);
  let thickness = clamp(max(retainedThickness, injection) + abs(waveA.x * waveB.y) * 0.002 * detail, 0.0, 1.0);
  let injectedPigment = select(sourcePigment, dropColor / max(drop, 0.001), drop > 0.001);
  let pigment = clamp(mix(diffusedState.rgb * 0.995, injectedPigment, injection), vec3<f32>(0.0), vec3<f32>(1.5));
  let state = vec4<f32>(pigment, thickness);
  textureStore(dataTextureA, pixel, state);

  let effectRgb = pigment * (0.5 + thickness * 0.9) + palette(fract(thickness + time * 0.02)) * thickness * 0.18;
  let alpha = clamp(source.a + (1.0 - source.a) * thickness, 0.0, 1.0);
  let displayRgb = acesToneMap(source.rgb * (1.0 - thickness * 0.72) + effectRgb * thickness);
  textureStore(writeTexture, pixel, vec4<f32>(displayRgb, alpha));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
