// Luminance Wind — exact-history advection with layered curl gusts.
// A/C stores raw HDR trail RGB plus semantic alpha; writeTexture is ACES display.
// B and extraBuffer are intentionally unused.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
  let e = 0.035;
  let nx0 = valueNoise(p - vec2<f32>(e, 0.0) + vec2<f32>(time * 0.13, -time * 0.09));
  let nx1 = valueNoise(p + vec2<f32>(e, 0.0) + vec2<f32>(time * 0.13, -time * 0.09));
  let ny0 = valueNoise(p - vec2<f32>(0.0, e) + vec2<f32>(time * 0.13, -time * 0.09));
  let ny1 = valueNoise(p + vec2<f32>(0.0, e) + vec2<f32>(time * 0.13, -time * 0.09));
  return vec2<f32>((ny1 - ny0) / (2.0 * e), -(nx1 - nx0) / (2.0 * e));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let windSpeed = 0.001 + u.zoom_params.x * 0.045;
  let trailDecay = mix(0.78, 0.985, clamp(u.zoom_params.y, 0.0, 1.0));
  let threshold = clamp(u.zoom_params.z, 0.0, 1.0);
  let turbulence = 0.05 + u.zoom_params.w * 1.4;
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let currentLuma = dot(current.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let depthLayer = mix(0.48, 1.52, depth);

  let joystick = (mouse - 0.5) * aspectVec;
  let heldDirection = joystick / max(length(joystick), 0.0001);
  let baseDirection = select(vec2<f32>(1.0, 0.08 * sin(time * 0.35)), heldDirection, held);
  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let localJet = smoothstep(0.48, 0.0, pointerDist) * select(0.15, 1.0, held);
  let curlLarge = curlNoise(uv * 2.7, time * 0.55);
  let curlFine = curlNoise(uv * 7.3 + vec2<f32>(3.1, -1.7), -time * 0.82);
  let layeredCurl = normalize(curlLarge + curlFine * (0.42 + treble * 0.18) + vec2<f32>(0.0001));

  var gustFront = 0.0;
  var gustDirection = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let delta = (uv - ripple.xy) * aspectVec;
      let dist = length(delta);
      let front = age * (0.30 + bass * 0.11);
      let pulse = sin((dist - front) * 62.0) * exp(-abs(dist - front) * 25.0) * exp(-age * 1.0);
      gustFront += pulse;
      gustDirection += delta / max(dist, 0.0001) * pulse;
    }
  }

  let lumaGate = smoothstep(threshold - 0.08, threshold + 0.08, currentLuma);
  let audioGust = 1.0 + bass * 0.85 + mids * 0.25;
  let wind = normalize(baseDirection + layeredCurl * turbulence * (0.28 + mids * 0.18) +
                       gustDirection * (0.38 + bass * 0.35) + vec2<f32>(0.0001));
  let localSpeed = windSpeed * lumaGate * depthLayer * audioGust * (1.0 + localJet * 1.25 + abs(gustFront) * 0.5);
  let sourceUV = clamp(uv - wind / aspectVec * localSpeed, vec2<f32>(0.0), vec2<f32>(1.0));
  let chroma = wind / aspectVec * localSpeed * (0.12 + treble * 0.30);
  let historyR = historyAt(sourceUV - chroma, resolution);
  let historyG = historyAt(sourceUV, resolution);
  let historyB = historyAt(sourceUV + chroma, resolution);
  let rawHistory = vec3<f32>(historyR.r, historyG.g, historyB.b);
  let historyAlpha = max(historyR.a, max(historyG.a, historyB.a));

  let injection = clamp(0.07 + lumaGate * 0.15 + mids * 0.035 + localJet * 0.08, 0.05, 0.34);
  var rawHDR = rawHistory * trailDecay + current.rgb * injection;
  rawHDR += current.rgb * abs(gustFront) * (0.07 + bass * 0.12);
  rawHDR += vec3<f32>(0.10, 0.42, 0.78) * length(layeredCurl) * lumaGate * treble * 0.025;
  rawHDR = clamp(rawHDR, vec3<f32>(0.0), vec3<f32>(8.0));
  let rawAlpha = clamp(historyAlpha * trailDecay + current.a * injection +
                       localSpeed * 5.0 + abs(gustFront) * 0.08, 0.0, 1.0);
  let rawState = vec4<f32>(rawHDR, rawAlpha);
  let display = vec4<f32>(aces(rawHDR), rawAlpha);

  textureStore(dataTextureA, coord, rawState);
  textureStore(writeTexture, coord, display);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
