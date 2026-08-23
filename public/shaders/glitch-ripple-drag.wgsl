// Glitch Ripple Drag — Batch 68 exact display-history upgrade.
// A owns semantic display RGBA; B is intentionally unwritten.
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; let pixel = vec2<i32>(gid.xy);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let dragStrength = u.zoom_params.x * 0.05 * (1.0 + bass * 0.8);
  let waveFreq = 10.0 + u.zoom_params.y * 40.0 + mids * 8.0;
  let persistence = 0.9 + u.zoom_params.z * 0.099;
  let glitchAmt = u.zoom_params.w * (1.0 + treble * 0.6);

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var origin = rawMouse; var velocity = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) { origin = vec2<f32>(extraBuffer[133], extraBuffer[134]); velocity = vec2<f32>(extraBuffer[135], extraBuffer[136]); lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5; }
  if (!initialized) { origin = rawMouse; velocity = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 11.0; let springDecay = exp(-omega * dt); let delta = origin - rawMouse; let temp = (velocity + omega * delta) * dt;
  velocity = (velocity - omega * temp) * springDecay; origin = rawMouse + (delta + temp) * springDecay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) { extraBuffer[133] = origin.x; extraBuffer[134] = origin.y; extraBuffer[135] = velocity.x; extraBuffer[136] = velocity.y; extraBuffer[137] = time; extraBuffer[138] = 1.0; }

  let deltaMouse = (uv - origin) * aspectVec; let mouseDist = length(deltaMouse);
  var direction = select(vec2<f32>(0.0), deltaMouse / mouseDist, mouseDist > 0.001);
  let angle = atan2(direction.y, direction.x);
  let quant = 3.14159265 / (4.0 + glitchAmt * 8.0);
  direction = mix(direction, vec2<f32>(cos(floor(angle / quant) * quant), sin(floor(angle / quant) * quant)), clamp(glitchAmt, 0.0, 1.0));
  let heldWave = smoothstep(0.62, 0.9, sin(mouseDist * waveFreq - time * (5.0 + mids * 2.0))) * smoothstep(0.9, 0.0, mouseDist) * (0.3 + 0.7 * u.zoom_config.w);
  var displacement = direction / aspectVec * dragStrength * heldWave + velocity * heldWave * 0.16;
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.2) { continue; }
    let deltaClick = (uv - ripple.xy) * aspectVec; let dist = length(deltaClick);
    let front = exp(-pow((dist - age * 0.34) * 32.0, 2.0)) * (1.0 - age / 2.2);
    let dir = select(vec2<f32>(0.0), deltaClick / dist, dist > 0.001);
    displacement += dir / aspectVec * front * dragStrength * 1.8;
    clickEnergy += front;
  }

  let historyUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let history = textureLoad(dataTextureC, historyCoord(historyUV, dims), 0);
  let redHistory = textureLoad(dataTextureC, historyCoord(clamp(historyUV + vec2<f32>(glitchAmt * 0.006, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), dims), 0).r;
  let blueHistory = textureLoad(dataTextureC, historyCoord(clamp(historyUV - vec2<f32>(glitchAmt * 0.006, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), dims), 0).b;
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let prior = select(source, history, history.a > 0.001);
  var trailRgb = mix(source.rgb, prior.rgb, persistence);
  trailRgb = mix(trailRgb, vec3<f32>(redHistory, trailRgb.g, blueHistory), clamp(glitchAmt * (heldWave + clickEnergy), 0.0, 1.0));
  let trailEnergy = clamp(length(trailRgb - source.rgb) + heldWave + clickEnergy * 0.6, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * trailEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(trailRgb, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
