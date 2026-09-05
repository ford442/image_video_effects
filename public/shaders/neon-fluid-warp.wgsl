// ═══════════════════════════════════════════════════════════════════
//  Neon Fluid Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-08-30
//  A packing: ACES display RGBA
//  Motion: viscous curl jets + neon edge runners
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

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  return v * inverseSqrt(max(dot(v, v), 1e-6));
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.49, 0.53) + vec3<f32>(0.48, 0.42, 0.45)
    * cos(TAU * (vec3<f32>(1.0, 0.80, 0.55) * t + vec3<f32>(0.28, 0.18, 0.08)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
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
  let binA = plasmaBuffer[1].z;
  let binB = plasmaBuffer[5].x;

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
      let omega = 9.5;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-2.8), vec2<f32>(2.8));
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

  let warpStrength = u.zoom_params.x * 0.2;
  let radius = mix(0.06, 0.55, u.zoom_params.y);
  let glowIntensity = u.zoom_params.z;
  let liquidity = u.zoom_params.w * 0.5;

  var distVec = (uv - spring) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let force = smoothstep(radius, 0.0, dist);
  let hold = select(1.0, 1.45, held);

  let jetPhase = time * (2.4 + bass * 1.8) + dist * 18.0;
  let jet = vec2<f32>(-distVec.y, distVec.x) * inverseSqrt(max(dot(distVec, distVec), 1e-6))
    * sin(jetPhase) * force * liquidity * 0.045;
  let ripple = sin(dist * 20.0 - time * (5.0 + mids * 2.0)) * liquidity * 0.05;
  let displaceDir = safeNormalize(distVec);
  let offset = (-displaceDir * force * warpStrength * hold * (1.0 + ripple)) + jet;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    let alive = age > 0.0 && age < 2.2;
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    click = click + select(0.0, exp(-abs(rd - age * 0.6) * 15.0) * exp(-age * 1.3), alive);
  }

  let sampleUV = clamp(uv + offset + displaceDir * click * 0.03, vec2<f32>(0.0), vec2<f32>(1.0));
  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let hist = textureLoad(dataTextureC, coord, 0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;

  let edge = 1.0 - smoothstep(0.0, 0.11 + treble * 0.03, abs(dist - radius * 0.8));
  let runner = pow(max(0.0, sin(atan2(distVec.y, distVec.x) * 7.0 - time * (6.0 + bass * 3.0)) * 0.5 + 0.5), 6.0)
    * edge * (0.65 + binA * 0.3);
  let glowFactor = force * (1.0 - force) * 4.0;
  let caustic = pow(max(0.0, sin(dist * 42.0 - time * (5.0 + bass * 1.5)) * 0.5 + 0.5), 5.0) * force;
  let neon = palette(time * 0.09 + dist * 1.3 + mids * 0.25 + binB * 0.08);
  let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var hdr = color.rgb * (0.58 + force * 0.28);
  hdr = hdr + neon * glowFactor * glowIntensity * luma * (3.0 + bass);
  hdr = hdr + vec3<f32>(0.42, 0.75, 1.0) * edge * glowIntensity * (0.7 + treble);
  hdr = hdr + vec3<f32>(1.0, 0.82, 0.46) * (caustic * 0.45 + runner * 0.85 + click * 0.4);
  hdr = mix(hdr, hist.rgb, 0.14 * (1.0 - force));
  hdr = hdr * mix(1.0, 0.68, smoothstep(0.46, 1.0, length(uv - vec2<f32>(0.5)) * 1.414));

  let dither = (ign(vec2<f32>(gid.xy) + vec2<f32>(sin(time * 3.1), cos(time * 2.7)) * 11.0) - 0.5) / 255.0;
  let rgb = clamp(aces(hdr * 1.14) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
  let alpha = clamp(glowFactor * 0.35 + edge * 0.28 + runner * 0.25 + color.a * 0.35, 0.08, 0.98);
  let outCol = vec4<f32>(rgb, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
