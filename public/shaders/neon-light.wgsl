// ═══════════════════════════════════════════════════════════════════
//  Neon Light
//  Category: lighting-effects
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, blackbody-emission, fresnel-edges
//  Complexity: High
//  Scientific: Planck-inspired blackbody edge emission with Sobel depth normals and Schlick Fresnel heating.
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn luminance(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn sampleColor(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 15000.0);
  let tt = t / 100.0;
  var r = 1.0;
  var g = 1.0;
  var b = 1.0;

  if (t <= 6600.0) {
    r = 1.0;
    g = 0.39008157 * log(tt) - 0.63184144;
    if (t < 2000.0) {
      b = 0.0;
    } else {
      b = 0.54320679 * log(max(tt - 10.0, 0.01)) - 1.19625408;
    }
  } else {
    r = 1.29293618 * pow(tt - 60.0, -0.1332047592);
    g = 1.12989086 * pow(tt - 60.0, -0.0755148492);
    b = 1.0;
  }

  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  let m = clamp(1.0 - cosTheta, 0.0, 1.0);
  let m2 = m * m;
  let m5 = m2 * m2 * m;
  return F0 + (1.0 - F0) * m5;
}

fn sobelLuma(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  let tl = luminance(sampleColor(uv + vec2<f32>(-texel.x, -texel.y)).rgb);
  let  t = luminance(sampleColor(uv + vec2<f32>(0.0, -texel.y)).rgb);
  let tr = luminance(sampleColor(uv + vec2<f32>(texel.x, -texel.y)).rgb);
  let  l = luminance(sampleColor(uv + vec2<f32>(-texel.x, 0.0)).rgb);
  let  r = luminance(sampleColor(uv + vec2<f32>(texel.x, 0.0)).rgb);
  let bl = luminance(sampleColor(uv + vec2<f32>(-texel.x, texel.y)).rgb);
  let  b = luminance(sampleColor(uv + vec2<f32>(0.0, texel.y)).rgb);
  let br = luminance(sampleColor(uv + vec2<f32>(texel.x, texel.y)).rgb);

  let gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
  let gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
  return vec2<f32>(gx, gy);
}

fn sobelDepth(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  let tl = sampleDepth(uv + vec2<f32>(-texel.x, -texel.y));
  let  t = sampleDepth(uv + vec2<f32>(0.0, -texel.y));
  let tr = sampleDepth(uv + vec2<f32>(texel.x, -texel.y));
  let  l = sampleDepth(uv + vec2<f32>(-texel.x, 0.0));
  let  r = sampleDepth(uv + vec2<f32>(texel.x, 0.0));
  let bl = sampleDepth(uv + vec2<f32>(-texel.x, texel.y));
  let  b = sampleDepth(uv + vec2<f32>(0.0, texel.y));
  let br = sampleDepth(uv + vec2<f32>(texel.x, texel.y));

  let gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
  let gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
  return vec2<f32>(gx, gy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let base = sampleColor(uv);
  let depth = sampleDepth(uv);
  let colorGrad = sobelLuma(uv, texel);
  let depthGrad = sobelDepth(uv, texel * 1.5);

  let edgeMetric = length(colorGrad) * 0.9 + length(depthGrad) * 2.0;
  let edgeStrength = smoothstep(0.05, 0.55, edgeMetric);

  let normal = normalize(vec3<f32>(-depthGrad.x * 3.0, -depthGrad.y * 3.0, 1.0));
  let fresnel = schlickFresnel(clamp(dot(normal, vec3<f32>(0.0, 0.0, 1.0)), 0.0, 1.0), 0.04 + 0.08 * u.zoom_params.y);

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouseDelta = vec2<f32>((uv.x - mousePos.x) * aspect, uv.y - mousePos.y);
  let mouseHot = exp(-dot(mouseDelta, mouseDelta) * mix(14.0, 84.0, u.zoom_params.w)) * (0.35 + 0.65 * u.zoom_config.w);

  let bassPulse = 1.0 + bass * 0.75 + 0.08 * sin(time * 12.0 + length(mouseDelta) * 28.0);
  let baseTemp = mix(800.0, 12000.0, u.zoom_params.x);
  let deltaTemp = mix(1400.0, 6800.0, u.zoom_params.y);
  let temperature = baseTemp
    + edgeStrength * deltaTemp * bassPulse
    + mouseHot * (2600.0 + 3400.0 * mids)
    + bass * 1800.0;

  let spectral = blackbodyRGB(temperature);
  let fogSpectral = blackbodyRGB(baseTemp * 0.45 + 1200.0 + mouseHot * 2200.0);
  let edgeGain = mix(0.9, 4.5, u.zoom_params.z);
  let fogAmount = u.zoom_params.w * (0.08 + 0.22 * (1.0 - depth)) + mouseHot * 0.12;

  let emission = spectral * edgeStrength * edgeGain * (0.35 + 1.65 * fresnel);
  let hotSpot = spectral * mouseHot * (0.08 + 0.24 * u.zoom_params.z);
  let fog = fogSpectral * fogAmount * (0.45 + 0.55 * mids);

  let finalColor = base.rgb * (1.0 - 0.18 * edgeStrength) + fog + emission + hotSpot;
  let alpha = clamp(max(base.a, 0.6) + edgeStrength * 0.12 + fogAmount * 0.2, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>((temperature - 800.0) / 11200.0, edgeStrength, fresnel, mouseHot));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
