// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus Interactive — Batch 56 cursor+main merge
//  Six-blade iris geometry, multi-tap blur, zone-plate caustics, oil-slick
//  runners/packets, held squeeze/pinch, click iris shells, display history in A
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

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let held = select(0.0, 1.0, mouseDown > 0.5);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let prev = textureLoad(dataTextureC, pixel, 0);

  let strength = u.zoom_params.x * 0.05 * (1.0 + held * 0.2 + audio.x * 0.35);
  let blurAmt = u.zoom_params.y;
  let focusRad = u.zoom_params.z * (1.0 - held * 0.12);
  let hardness = u.zoom_params.w * 5.0 + 1.0;

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  var amount = smoothstep(focusRad, focusRad + 0.5, dist);
  amount = pow(amount, 1.0 / hardness);

  let dir = select(vec2<f32>(0.0), distVec / max(dist, 1e-5), dist > 1e-5);
  let squeeze = held * exp(-dist * 8.0) * (0.015 + strength * 0.4);

  var irisShell = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    irisShell += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.36) * 65.0);
  }

  let ang = atan2(distVec.y, distVec.x) + time * (0.35 + audio.y * 0.4);
  let blades = abs(sin(ang * 6.0));
  let irisBlade = smoothstep(0.12, 0.0, abs(dist - focusRad)) * (0.35 + blades * 0.65);
  let runner = smoothstep(0.05, 0.0, abs(fract(dist * 6.0 - time * (2.0 + audio.x)) - 0.5));
  let packets = smoothstep(0.09, 0.0, abs(fract(dist * 12.0 - time * (2.0 + audio.x * 1.8)) - 0.5));
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(dist * 5.0 - time * 0.35) + vec3<f32>(0.0, 0.33, 0.67)));
  let slick = hsv2rgb(vec3<f32>(fract(ang / TAU + time * 0.1 + audio.z * 0.2), 0.7, 1.0));
  let caustic = sin(dist * (35.0 + focusRad * 90.0) - time * (1.0 + audio.y * 4.0)) * amount;

  let rOffset = dir * (amount * strength + squeeze + irisShell * 0.008);
  let bOffset = -dir * (amount * strength + squeeze + irisShell * 0.008);
  let blurRadius = blurAmt * amount * (0.002 + audio.x * 0.006);
  let tangent = vec2<f32>(-dir.y, dir.x);

  let r = (
    textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r +
    textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r +
    textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r
  ) / 3.0;
  let g = (
    textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g +
    textureSampleLevel(readTexture, u_sampler, clamp(uv + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g +
    textureSampleLevel(readTexture, u_sampler, clamp(uv - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g
  ) / 3.0;
  let b = (
    textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b +
    textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset + tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b +
    textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset - tangent * blurRadius, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  ) / 3.0;

  let vig = 1.0 - amount * 0.3;
  var color = vec3<f32>(r, g, b) * vig;
  color = mix(color, color * slick * 1.25, 0.2 + blurAmt * 0.2);
  color += oilSlick * runner * amount * 0.10;
  color += slick * (irisBlade * 0.35 + packets * 0.18 + irisShell * 0.20 + held * 0.06);
  color += (0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + caustic * 4.0 + time))
    * (abs(caustic) * 0.08 + irisShell * 0.16);

  if (mouseDown > 0.5) {
    let ring = abs(dist - focusRad);
    if (ring < 0.005) {
      color += vec3<f32>(0.5, 0.5, 0.5);
    }
  }

  color = mix(color, prev.rgb * 0.90, 0.14 * amount + 0.06);

  let blurThickness = amount * 5.0 + blurAmt * 2.0;
  let alphaR = calculateChannelAlpha(blurThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(blurThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(blurThickness, WAVELENGTH_BLUE);
  let finalAlpha = clamp(
    dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + irisShell * 0.06,
    0.0,
    1.0
  );
  let finalColor = vec3<f32>(color.r * alphaR, color.g * alphaG, color.b * alphaB);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthOut = clamp(depth + irisBlade * 0.06 + irisShell * 0.04, 0.0, 1.0);
  let finalPixel = vec4<f32>(finalColor, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
