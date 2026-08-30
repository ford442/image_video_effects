// ═══════════════════════════════════════════════════════════════════
//  Solarize Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: domain-warp conveyor + solarize threshold wavefront
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

const TAU: f32 = 6.28318530718;

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = fract(p * vec2<f32>(0.1031, 0.1030));
  return fract((h + 33.19) * vec2<f32>(43758.5453, 22578.1459));
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * (sin(pp.x * 2.7 + pp.y * 1.3) * cos(pp.x * 1.1 - pp.y * 3.2));
    pp = pp * 2.1 + vec2<f32>(100.0, 37.0);
    a = a * 0.48;
  }
  return v;
}

fn sabattier(tone: vec3<f32>, threshold: f32, strength: f32) -> vec3<f32> {
  let luma = dot(tone, vec3<f32>(0.299, 0.587, 0.114));
  let edge = abs(luma - threshold);
  let invertMask = smoothstep(0.0, 0.12, edge) * step(threshold, luma);
  var outc = mix(tone, 1.0 - tone, invertMask * strength);
  let mackie = smoothstep(0.08, 0.0, edge) * strength * 0.55;
  return outc + vec3<f32>(0.85, 0.90, 0.75) * mackie;
}

fn satBoost(rgb: vec3<f32>, amount: f32) -> vec3<f32> {
  let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  return luma + (rgb - vec3<f32>(luma)) * (1.0 + amount);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let aspect = dims.x / max(dims.y, 1.0);
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binLo = plasmaBuffer[2].x;
  let binHi = plasmaBuffer[6].z;

  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 8.5;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.2), vec2<f32>(2.2));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  let twistStrength = u.zoom_params.x * 4.5;
  let solarizeThreshold = mix(0.15, 0.85, u.zoom_params.y);
  let effectRadius = mix(0.08, 0.80, u.zoom_params.z);
  let effectIntensity = mix(0.05, 1.0, u.zoom_params.w);

  let centered = (uv - spring) * vec2<f32>(aspect, 1.0);
  let dist = length(centered);
  let influence = 1.0 - smoothstep(0.0, effectRadius, dist);

  let conveyor = fbm(uv * 3.2 + vec2<f32>(time * 0.55, time * -0.31) + mids * 0.4);
  let flowAng = conveyor * TAU + time * (1.4 + bass * 0.8);
  let flow = vec2<f32>(cos(flowAng), sin(flowAng)) * influence * (0.035 + u.zoom_params.x * 0.02);

  var front = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.8;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    let wave = exp(-abs(rd - age * 0.42) * 16.0) * exp(-age * 1.15);
    front = front + select(0.0, wave, alive);
  }

  let holdGain = select(1.0, 1.35, held);
  let bassOsc = sin(time * 1.8 + dist * 6.0) * bass * 0.16;
  let threshold = clamp(solarizeThreshold + bassOsc * influence + front * 0.22, 0.05, 0.95);

  let warpNoise = fbm(uv * 3.0 + time * 0.25 + mids * 0.5);
  let warpAngle = twistStrength * influence * holdGain * (1.0 + bass * 0.7)
    + warpNoise * 0.35
    + sin(time * 2.0 + dist * 18.0) * 0.15;
  let s = sin(warpAngle);
  let c = cos(warpAngle);
  let rotated = vec2<f32>(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
  let warpedUV = clamp(rotated / vec2<f32>(aspect, 1.0) + spring + flow, vec2<f32>(0.0), vec2<f32>(1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let layerUV = clamp(warpedUV + vec2<f32>(depth * 0.04 * influence), vec2<f32>(0.0), vec2<f32>(1.0));
  let source = textureSampleLevel(readTexture, u_sampler, layerUV, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let solarized = sabattier(source.rgb, threshold, effectIntensity);

  let shadowTint = mix(vec3<f32>(0.95, 0.42, 0.15), vec3<f32>(0.12, 0.62, 0.92), 0.5 + 0.5 * sin(time * 0.6 + dist * 14.0 + binLo));
  let highlightTint = mix(vec3<f32>(1.0, 0.78, 0.35), vec3<f32>(0.55, 0.88, 1.0), 0.5 + 0.5 * cos(time * 0.4 + dist * 10.0 + binHi));
  let luma = dot(solarized, vec3<f32>(0.299, 0.587, 0.114));
  let splitTone = mix(shadowTint * solarized, highlightTint * solarized, smoothstep(0.35, 0.65, luma));
  let grain = hash22(uv * dims + vec2<f32>(sin(time * 7.3), cos(time * 5.1))).x - 0.5;

  var hdr = mix(solarized, splitTone, influence * 0.45) + grain * 0.018;
  hdr = satBoost(hdr, 0.22 + treble * 0.18);
  hdr = mix(hdr, hist.rgb, 0.16 * (1.0 - influence));
  hdr = hdr + vec3<f32>(0.95, 0.72, 0.28) * front * 0.28;
  let rgb = acesFilm(hdr * 1.1);

  let edgeDensity = smoothstep(0.0, 0.12, abs(luma - threshold));
  let alpha = clamp(effectIntensity * edgeDensity * (0.35 + depth) + front * 0.3 + influence * 0.2, 0.12, 0.97);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.20 + influence * 0.72, 0.22), 0.0, 1.0), 0.0, 0.0, 0.0));
}
