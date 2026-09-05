// ═══════════════════════════════════════════════════════════════════
//  Zoom Burst
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: radial speed lines + rotational shear streaks
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

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn filmGrain(uv: vec2<f32>, t: f32) -> f32 {
  return (fract(sin(dot(uv + vec2<f32>(sin(t), cos(t * 0.7)), vec2<f32>(127.1, 311.7))) * 43758.5453) - 0.5) * 0.03;
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
  let binA = plasmaBuffer[2].z;
  let binB = plasmaBuffer[7].y;

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
      let omega = 12.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-3.5), vec2<f32>(3.5));
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

  let burstLength = mix(0.01, 0.30, u.zoom_params.x) * (1.0 + bass * 0.65);
  let quality = i32(mix(8.0, 22.0, u.zoom_params.y));
  let spin = (u.zoom_params.z - 0.5) * 2.8;
  let chroma = mix(0.0, 0.045, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthStreak = mix(0.4, 1.6, depth);
  let hold = select(1.0, 1.35, held);
  let adj = (uv - spring) * vec2<f32>(aspect, 1.0);
  let dist = length(adj);
  let dir = adj / max(dist, 1e-4);
  let aspectVec = vec2<f32>(aspect, 1.0);

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 1.6;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.85) * 12.0) * exp(-age * 1.7), alive);
  }

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let srcLum = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var accum = vec3<f32>(0.0);
  var weightSum = 0.0;
  for (var i: i32 = 0; i < quality; i = i + 1) {
    let t = f32(i) / max(f32(quality - 1), 1.0);
    let radius = pow(t, 1.7) * burstLength * depthStreak * hold * (1.0 + dist * 2.0 + click * 0.8);
    let shear = rotate(dir, spin * t + sin(time * 2.2 + dist * 9.0) * 0.18 * t);
    let stepVec = shear * radius;
    let sampleUV = clamp(uv - stepVec / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0));
    let split = dir * chroma * t * (1.0 + dist * 2.0);
    let rch = sampleColor(sampleUV + split / aspectVec).r;
    let gch = sampleColor(sampleUV).g;
    let bch = sampleColor(sampleUV - split / aspectVec).b;
    let rayAngle = abs(sin(atan2(dir.y, dir.x) * 4.0 + time * 0.6));
    let w = mix(1.0, 0.22, t) * (1.0 + rayAngle * 0.55) * (1.0 + bass * 0.4);
    accum = accum + vec3<f32>(rch, gch, bch) * w;
    weightSum = weightSum + w;
  }

  let burst = accum / max(weightSum, 1e-4);
  let lum = dot(burst, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = max(lum - 0.50, 0.0) * 0.6;
  let speedLine = pow(max(0.0, sin(atan2(dir.y, dir.x) * 8.0 - time * (4.0 + bass * 2.0)) * 0.5 + 0.5), 10.0)
    * exp(-dist * 2.2) * (0.22 + treble * 0.15 + binA * 0.08);
  let tint = mix(vec3<f32>(0.10, 0.8, 1.0), vec3<f32>(1.0, 0.50, 0.70), 0.5 + 0.5 * sin(time * 0.8 + binB));

  var hdr = mix(src.rgb, burst + bloom, 0.82);
  hdr = hdr + tint * speedLine + tint * click * 0.28 + exp(-dist * 5.0) * 0.16 * (1.0 + bass);
  hdr = mix(hdr, hist.rgb, 0.12);
  hdr = hdr + filmGrain(uv, time);
  let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
  hdr = luma + (hdr - vec3<f32>(luma)) * (1.18 + chroma * 4.0);
  let rgb = acesToneMap(hdr * mix(1.0, 0.78, smoothstep(0.3, 0.9, dist)));

  let intensity = clamp(length(burst) * 0.45 + speedLine * 0.6 + click * 0.3 + srcLum * 0.1, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, intensity);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.2 + intensity * 0.55, 0.2), 0.0, 1.0), 0.0, 0.0, 0.0));
}
