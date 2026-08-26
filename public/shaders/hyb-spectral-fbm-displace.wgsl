// ═══════════════════════════════════════════════════════════════════
//  hyb-spectral-fbm-displace — Batch 56
//  Spectral conveyor bands, interference runners, held warp, click fronts
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
  let q = vec2<f32>(
    fbm2(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
    fbm2(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
  );
  let r = vec2<f32>(
    fbm2(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
    fbm2(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
  );
  return uv + amount * r;
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = textureDimensions(writeTexture);
  if (any(pixel >= vec2<i32>(dims))) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  let fbmScale = mix(2.0, 24.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let warpAmt = mix(0.0, 0.35, clamp(u.zoom_params.y, 0.0, 1.0)) * (1.0 + held * 0.25);
  let spectralSpread = mix(0.0, 0.08, clamp(u.zoom_params.z, 0.0, 1.0));
  let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

  let mousePull = (mouse - uv) * held * 0.04;
  let warpedUV = domainWarp(uv + mousePull, time, fbmScale, warpAmt);
  let dispVec = warpedUV - uv;
  let spread = dispVec * spectralSpread * (1.0 + bass * 0.2);

  let rUV = clamp(uv + spread, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - spread, vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let g = src.g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  var displaced = vec3<f32>(r, g, b);

  let conveyor = smoothstep(0.05, 0.0, abs(fract(uv.x * 12.0 + time * (2.0 + mids)) - 0.5));
  let runner = smoothstep(0.06, 0.0, abs(fract(uv.y * 8.0 - time * (3.2 + treble * 0.5)) - 0.5));
  let waveT = clamp(fbm2(uv * fbmScale * 0.5 + vec2<f32>(time * 0.08), 4), 0.0, 1.0);
  let lambda = mix(440.0, 680.0, waveT + conveyor * 0.15);
  let tint = wavelengthToRGB(lambda);
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(uv.x * 3.0 + time * 0.4) + vec3<f32>(0.0, 0.33, 0.67)));
  displaced = displaced + oilSlick * (conveyor + runner) * 0.12;
  displaced = mix(displaced, displaced * tint * 1.8, 0.35);

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      let d = length(uv - rp.xy);
      clickRing = max(clickRing, exp(-abs(d - age * 0.35) * 48.0) * (1.0 - age / 1.5));
    }
  }
  displaced += tint * clickRing * 0.4;

  var outRGB = mix(src.rgb, displaced, effectMix);
  outRGB = mix(outRGB, prev.rgb * 0.9, 0.08 * effectMix);
  let alpha = src.a;
  let finalPixel = vec4<f32>(clamp(outRGB, vec3<f32>(0.0), vec3<f32>(1.0)), alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
