// Spectral Bleed & Confinement — Batch 58D canonical feedback upgrade
// A owns exact display RGBA afterglow; B is intentionally unwritten.

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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let e = 0.02;
  let dx = valueNoise(p + vec2<f32>(e, 0.0)) - valueNoise(p - vec2<f32>(e, 0.0));
  let dy = valueNoise(p + vec2<f32>(0.0, e)) - valueNoise(p - vec2<f32>(0.0, e));
  return normalize(vec2<f32>(dy, -dx) + vec2<f32>(0.0001));
}

fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }

fn edgeMagnitude(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
  let x = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb) -
          luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  let y = luma(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb) -
          luma(textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
  return length(vec2<f32>(x, y));
}

fn channelTap(uv: vec2<f32>, dir: vec2<f32>, radius: f32, channel: u32) -> f32 {
  var sum = 0.0; var weights = 0.0;
  for (var i = 1; i <= 6; i++) {
    let f = f32(i) / 6.0; let w = 1.0 - f * 0.7;
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(uv + dir * radius * f, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    sum += select(select(sample.b, sample.g, channel == 1u), sample.r, channel == 0u) * w; weights += w;
  }
  return sum / max(weights, 0.001);
}

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
  let uv = (vec2<f32>(pixel) + 0.5) / res; let texel = 1.0 / res; let time = u.config.x;
  let dims = vec2<i32>(textureDimensions(dataTextureC));
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  // Saved mapping: bleed radius, confinement, curl speed, edge threshold.
  let bleedRadius = (u.zoom_params.x * 0.025 + 0.004) * (1.0 + bass * 0.5);
  let confinement = (u.zoom_params.y * 2.0 + 0.5) * (1.0 + mids * 0.2);
  let curlSpeed = u.zoom_params.z * 0.4 + 0.05;
  let edgeThreshold = u.zoom_params.w * 0.3 + 0.02;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var springPos = rawMouse; var springVel = vec2<f32>(0.0); var lastTime = time; var initialized = false;
  if (hasSpring) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]); springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    lastTime = extraBuffer[137]; initialized = extraBuffer[138] > 0.5;
  }
  if (!initialized) { springPos = rawMouse; springVel = vec2<f32>(0.0); }
  let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), initialized);
  let omega = 9.0; let decay = exp(-omega * dt); let delta = springPos - rawMouse; let temp = (springVel + omega * delta) * dt;
  springVel = (springVel - omega * temp) * decay; springPos = rawMouse + (delta + temp) * decay;
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = springPos.x; extraBuffer[134] = springPos.y; extraBuffer[135] = springVel.x; extraBuffer[136] = springVel.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  let pointerDist = length((uv - springPos) * aspectVec);
  let focus = exp(-pointerDist * 5.0) * select(0.45, 1.0, u.zoom_config.w > 0.5);
  var frontEnergy = 0.0; var frontWarp = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age < 0.0 || age > 2.4) { continue; }
    let deltaR = (uv - ripple.xy) * aspectVec; let dist = length(deltaR);
    let front = exp(-pow((dist - age * 0.18) * 22.0, 2.0)) * (1.0 - age / 2.4);
    frontEnergy += front;
    frontWarp += deltaR / max(dist, 0.001) * front * 0.012;
  }

  let curl = curlNoise(uv * 3.0 + vec2<f32>(time * curlSpeed, -time * curlSpeed * 0.7));
  let angle = atan2(curl.y, curl.x) + focus * 0.8 + frontEnergy * 0.25;
  let dirR = vec2<f32>(cos(angle), sin(angle));
  let dirG = vec2<f32>(cos(angle + TAU / 3.0), sin(angle + TAU / 3.0));
  let dirB = vec2<f32>(cos(angle + 2.0 * TAU / 3.0), sin(angle + 2.0 * TAU / 3.0));
  let warpedUv = clamp(uv + frontWarp, vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let edge = smoothstep(edgeThreshold * 0.5, edgeThreshold, edgeMagnitude(uv, texel));
  let bleed = vec3<f32>(channelTap(warpedUv, dirR, bleedRadius * (1.0 + focus), 0u),
                        channelTap(warpedUv, dirG, bleedRadius * (1.0 + focus), 1u),
                        channelTap(warpedUv, dirB, bleedRadius * (1.0 + focus), 2u)) * edge;
  let confine = exp(-vec3<f32>(bleed.g * bleed.b, bleed.b * bleed.r, bleed.r * bleed.g) * confinement);
  var hdr = source.rgb + bleed * confine * (0.65 + vec3<f32>(bass, mids, treble) * 0.45);
  hdr += vec3<f32>(1.0, 0.35, 0.12) * frontEnergy * edge * 0.35;

  let historyUv = clamp(uv - curl * bleedRadius * 0.6 - frontWarp * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let previous = textureLoad(dataTextureC, historyCoord(historyUv, dims), 0);
  let afterglow = clamp(edge * 0.18 + frontEnergy * 0.28 + treble * 0.04, 0.0, 0.58);
  hdr = mix(hdr, previous.rgb * 0.955, afterglow);
  let effectEnergy = clamp(edge * u.zoom_params.x + focus * 0.25 + frontEnergy * 0.4 + previous.a * afterglow, 0.0, 1.0);
  let alpha = clamp(source.a + (1.0 - source.a) * effectEnergy, 0.0, 1.0);
  let display = vec4<f32>(acesToneMap(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(dataTextureA, pixel, display); textureStore(writeTexture, pixel, display);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
