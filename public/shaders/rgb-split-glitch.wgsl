// ═══════════════════════════════════════════════════════════════════
//  RGB Split Glitch
//  Category: image
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: High
//  Scientific: YUV 4:2:0 chroma subsampling with delayed chroma planes, Nyquist alias fold-back, MPEG-style block ringing, and mouse-driven color bleed
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

const PI: f32 = 3.14159265359;

fn clampUV(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let len2 = dot(v, v);
  if (len2 < 1e-8) {
    return vec2<f32>(0.0, 0.0);
  }
  return v * inverseSqrt(len2);
}

fn rgbToYCbCr(rgb: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    dot(rgb, vec3<f32>(0.299, 0.587, 0.114)),
    dot(rgb, vec3<f32>(-0.169, -0.331, 0.500)),
    dot(rgb, vec3<f32>(0.500, -0.419, -0.081))
  );
}

fn yCbCrToRgb(yuv: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    yuv.x + 1.402 * yuv.z,
    yuv.x - 0.344136 * yuv.y - 0.714136 * yuv.z,
    yuv.x + 1.772 * yuv.y
  );
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123;
  return fract(h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let coord = vec2<f32>(global_id.xy);
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let glitch = 0.10 + 1.80 * clamp(u.zoom_params.x, 0.0, 1.0) + 1.20 * bass;
  let temporalOffset = clamp(u.zoom_params.y, 0.0, 1.0);
  let aliasSeverity = clamp(u.zoom_params.z, 0.0, 1.0);
  let radius = 0.08 + 0.35 * clamp(u.zoom_params.w, 0.0, 1.0);

  let baseRgb = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let baseYuv = rgbToYCbCr(baseRgb);

  let chromaCoord = floor(coord / 2.0) * 2.0 + vec2<f32>(0.5, 0.5);
  let chromaUV = clampUV(chromaCoord / resolution);
  let blockRgb = textureSampleLevel(readTexture, u_sampler, chromaUV, 0.0).rgb;
  let blockYuv = rgbToYCbCr(blockRgb);

  let previous = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let cbDelayed1 = previous.g;
  let crDelayed1 = previous.b;
  let crDelayed2 = previous.a;

  var y = baseYuv.x;
  var cb = mix(blockYuv.y, cbDelayed1, clamp(0.30 + 0.45 * temporalOffset + 0.15 * bass, 0.0, 1.0));
  var cr = mix(blockYuv.z, crDelayed2, clamp(0.45 + 0.45 * temporalOffset, 0.0, 1.0));

  let leftY = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv - vec2<f32>(texel.x, 0.0)), 0.0).rgb).x;
  let rightY = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv + vec2<f32>(texel.x, 0.0)), 0.0).rgb).x;
  let upY = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv - vec2<f32>(0.0, texel.y)), 0.0).rgb).x;
  let downY = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv + vec2<f32>(0.0, texel.y)), 0.0).rgb).x;
  let diagA = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv + vec2<f32>(texel.x, texel.y)), 0.0).rgb).x;
  let diagB = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv + vec2<f32>(-texel.x, texel.y)), 0.0).rgb).x;

  let freqMeasure = abs(rightY - leftY) + abs(downY - upY) + abs(diagA - diagB);
  let aliasStrength = smoothstep(0.15, 0.70, freqMeasure * (1.0 + glitch));
  let herringbone = sin((uv.x + uv.y) * resolution.x * (0.28 + 1.3 * aliasSeverity) + time * (6.0 + 12.0 * treble)) *
                    sin((uv.x - uv.y) * resolution.y * (0.24 + 1.4 * aliasSeverity) - time * 4.0);
  cb += herringbone * aliasStrength * (0.02 + 0.08 * aliasSeverity + 0.05 * bass);
  cr -= herringbone * aliasStrength * (0.03 + 0.10 * aliasSeverity + 0.04 * bass);
  y += herringbone * aliasStrength * 0.04;

  let blockCenterUV = clampUV((floor(coord / 8.0) * 8.0 + vec2<f32>(4.0, 4.0)) / resolution);
  let blockCenterY = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, blockCenterUV, 0.0).rgb).x;
  let blockFrac = abs(fract((coord + 0.5) / 8.0) - 0.5);
  let boundary = exp(-min(blockFrac.x, blockFrac.y) * 28.0);
  let ringing = cos(blockFrac.x * PI * 2.0) * cos(blockFrac.y * PI * 2.0) * boundary * (blockCenterY - y) * (0.10 + 0.18 * glitch);
  y += ringing;

  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseDelta = (uv - mouse) * aspectVec;
  let bleed = mouseDown * smoothstep(radius, 0.0, length(mouseDelta));
  let bleedDirection = safeNormalize(mouseDelta + vec2<f32>(0.001, 0.0));
  let bleedSample = rgbToYCbCr(textureSampleLevel(readTexture, u_sampler, clampUV(uv + bleedDirection * 0.015 * glitch), 0.0).rgb);
  cb = mix(cb, bleedSample.y, bleed * 0.85);
  cr = mix(cr, bleedSample.z, bleed * 0.85);
  y = mix(y, mix(y, baseYuv.x, 0.6), bleed * 0.5);

  cb += (hash12(coord + time) - 0.5) * 0.02 * glitch;
  cr += (hash12(coord.yx - time) - 0.5) * 0.02 * glitch;

  let reconstructed = clamp(yCbCrToRgb(vec3<f32>(y, cb, cr)), vec3<f32>(0.0), vec3<f32>(1.0));
  let digitalDamage = clamp(aliasStrength * (0.25 + 0.45 * glitch) + boundary * 0.15 + bleed * 0.25, 0.0, 1.0);
  let finalColor = clamp(mix(baseRgb, reconstructed, clamp(0.58 + digitalDamage, 0.0, 1.0)), vec3<f32>(0.0), vec3<f32>(1.0));

  let depthSample = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.82 + 0.10 * digitalDamage + 0.04 * bass, 0.0, 1.0);
  let depthProxy = clamp(depthSample * 0.40 + aliasStrength * 0.35 + digitalDamage * 0.35, 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(y, blockYuv.y, blockYuv.z, crDelayed1));
  textureStore(dataTextureB, global_id.xy, vec4<f32>(aliasStrength, boundary, bleed, digitalDamage));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depthProxy, 0.0, 0.0, 1.0));
}
