// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus Interactive — Batch 56
//  Focus runners, oil-slick aberration, held drag, bounded click iris fronts
// ═══════════════════════════════════════════════════════════════════════════════

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
const WAVELENGTH_RED: f32 = 650.0;
const WAVELENGTH_GREEN: f32 = 550.0;
const WAVELENGTH_BLUE: f32 = 450.0;

fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
  let lambda_norm = (800.0 - wavelength) / 400.0;
  let absorption = mix(0.3, 1.0, lambda_norm);
  return exp(-thickness * absorption);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let strength = u.zoom_params.x * 0.05 * (1.0 + held * 0.2);
  let blurAmt = u.zoom_params.y;
  let focusRad = u.zoom_params.z;
  let hardness = u.zoom_params.w * 5.0 + 1.0;

  let center = mouse;
  let distVec = (uv - center) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  var amount = smoothstep(focusRad, focusRad + 0.5, dist);
  amount = pow(amount, 1.0 / hardness);

  let runner = smoothstep(0.05, 0.0, abs(fract(dist * 6.0 - time * (2.0 + bass)) - 0.5));
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(dist * 5.0 - time * 0.35) + vec3<f32>(0.0, 0.33, 0.67)));

  var dir = normalize(distVec + vec2<f32>(0.0001, 0.0));
  let rOffset = dir * amount * strength;
  let bOffset = -dir * amount * strength;

  let r = textureSampleLevel(readTexture, u_sampler, uv + rOffset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, uv + bOffset, 0.0).b;
  var color = vec3<f32>(r, g, b) * (1.0 - amount * 0.3);
  color += oilSlick * runner * amount * 0.12;

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      let d = length(uv - rp.xy);
      clickRing = max(clickRing, exp(-abs(d - focusRad - age * 0.2) * 80.0) * (1.0 - age / 1.5));
    }
  }
  color += oilSlick * clickRing * 0.2;
  color = mix(color, prev.rgb * 0.94, 0.08 * amount);

  let blurThickness = amount * 5.0 + blurAmt * 2.0;
  let alphaR = calculateChannelAlpha(blurThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(blurThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(blurThickness, WAVELENGTH_BLUE);
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
  let finalColor = vec3<f32>(color.r * alphaR, color.g * alphaG, color.b * alphaB);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let finalPixel = vec4<f32>(finalColor, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
