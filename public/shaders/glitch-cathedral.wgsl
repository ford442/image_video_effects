// ═══════════════════════════════════════════════════════════════════
//  Glitch Cathedral
//  Category: retro-glitch
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: Low-order 8×8 DCT reconstruction with Floyd-Steinberg feedback and Gibbs ringing shaping stained-glass compression ghosts.
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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn clamp_uv(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn clamp_coord(c: vec2<i32>, max_coord: vec2<i32>) -> vec2<i32> {
  return clamp(c, vec2<i32>(0, 0), max_coord);
}

fn dct_basis(u_idx: i32, v_idx: i32, x: f32, y: f32) -> f32 {
  return cos((2.0 * x + 1.0) * f32(u_idx) * PI / 16.0) * cos((2.0 * y + 1.0) * f32(v_idx) * PI / 16.0);
}

fn hue_shift(color: vec3<f32>, shift: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735026919);
  let cs = cos(shift);
  let sn = sin(shift);
  return color * cs + cross(k, color) * sn + k * dot(k, color) * (1.0 - cs);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= size.x || global_id.y >= size.y) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(f32(size.x), f32(size.y));
  let uv = (vec2<f32>(f32(global_id.x), f32(global_id.y)) + 0.5) / resolution;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let blockOriginU = (global_id.xy / 8u) * 8u;
  let blockOrigin = vec2<i32>(blockOriginU);
  let local = vec2<f32>(f32(global_id.x - blockOriginU.x), f32(global_id.y - blockOriginU.y));
  let blockId = vec2<f32>(f32(blockOriginU.x) / 8.0, f32(blockOriginU.y) / 8.0);

  let baseQ = mix(0.015, 0.22, clamp(u.zoom_params.x + bass * 0.55, 0.0, 1.0));
  let blockBand = fract(hash12(blockId * 0.37 + vec2<f32>(mids * 1.7, treble * 2.3)) + bass * 0.21);
  let blockQ = baseQ * mix(0.7, 1.9, blockBand);

  var c00 = vec3<f32>(0.0);
  var c01 = vec3<f32>(0.0);
  var c10 = vec3<f32>(0.0);
  var c11 = vec3<f32>(0.0);

  for (var sy: i32 = 0; sy < 4; sy = sy + 1) {
    for (var sx: i32 = 0; sx < 4; sx = sx + 1) {
      let sampleLocal = vec2<f32>(f32(sx) * 2.0 + 1.0, f32(sy) * 2.0 + 1.0);
      let sampleUV = (vec2<f32>(f32(blockOriginU.x), f32(blockOriginU.y)) + sampleLocal + 0.5) / resolution;
      let sampleColor = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV), 0.0).rgb;
      c00 = c00 + sampleColor * dct_basis(0, 0, sampleLocal.x, sampleLocal.y);
      c01 = c01 + sampleColor * dct_basis(0, 1, sampleLocal.x, sampleLocal.y);
      c10 = c10 + sampleColor * dct_basis(1, 0, sampleLocal.x, sampleLocal.y);
      c11 = c11 + sampleColor * dct_basis(1, 1, sampleLocal.x, sampleLocal.y);
    }
  }

  c00 = floor(c00 / blockQ + 0.5) * blockQ * 0.0625;
  c01 = floor(c01 / blockQ + 0.5) * blockQ * 0.0625;
  c10 = floor(c10 / blockQ + 0.5) * blockQ * 0.0625;
  c11 = floor(c11 / blockQ + 0.5) * blockQ * 0.0625;

  let b00 = dct_basis(0, 0, local.x, local.y);
  let b01 = dct_basis(0, 1, local.x, local.y);
  let b10 = dct_basis(1, 0, local.x, local.y);
  let b11 = dct_basis(1, 1, local.x, local.y);
  var reconstructed = c00 * b00 + c01 * b01 + c10 * b10 + c11 * b11;

  let source = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv), 0.0);
  let sourceDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp_uv(uv), 0.0).r;
  let right = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + vec2<f32>(1.0 / resolution.x, 0.0)), 0.0).rgb;
  let down = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + vec2<f32>(0.0, 1.0 / resolution.y)), 0.0).rgb;
  let sourceLuma = dot(source.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let edge = max(abs(dot(right, vec3<f32>(0.299, 0.587, 0.114)) - sourceLuma), abs(dot(down, vec3<f32>(0.299, 0.587, 0.114)) - sourceLuma));
  let ringing = sin((local.x + local.y) * PI) * 0.09 * smoothstep(0.08, 0.35, edge) * (0.3 + blockQ * 4.0);
  reconstructed = reconstructed + vec3<f32>(1.0, 0.9, 1.1) * ringing;

  let maxCoord = vec2<i32>(i32(size.x) - 1, i32(size.y) - 1);
  let eRight = textureLoad(dataTextureC, clamp_coord(coord + vec2<i32>(1, 0), maxCoord), 0).rgb * 2.0 - 1.0;
  let eDownLeft = textureLoad(dataTextureC, clamp_coord(coord + vec2<i32>(-1, 1), maxCoord), 0).rgb * 2.0 - 1.0;
  let eDown = textureLoad(dataTextureC, clamp_coord(coord + vec2<i32>(0, 1), maxCoord), 0).rgb * 2.0 - 1.0;
  let eDownRight = textureLoad(dataTextureC, clamp_coord(coord + vec2<i32>(1, 1), maxCoord), 0).rgb * 2.0 - 1.0;
  let fsError = eRight * (7.0 / 16.0) + eDownLeft * (3.0 / 16.0) + eDown * (5.0 / 16.0) + eDownRight * (1.0 / 16.0);
  reconstructed = reconstructed + fsError * 0.22;

  let stainedShift = (blockBand - 0.5) * 1.2 + treble * 0.15;
  reconstructed = hue_shift(reconstructed, stainedShift);
  reconstructed = reconstructed * vec3<f32>(1.15, 0.98, 0.84);

  let levels = mix(9.0, 3.0, clamp(blockQ * 3.0, 0.0, 1.0));
  let quantized = floor(clamp(reconstructed, vec3<f32>(0.0), vec3<f32>(1.0)) * levels + 0.5) / levels;

  let edgeDist = min(min(local.x, 7.0 - local.x), min(local.y, 7.0 - local.y));
  let leadLine = 1.0 - smoothstep(0.5, 1.6, edgeDist);
  let roseWindow = 0.5 + 0.5 * sin((blockId.x - blockId.y) * 0.4 + bass * 4.0);
  var finalRgb = mix(quantized, vec3<f32>(0.06, 0.05, 0.08), leadLine * (0.75 + 0.2 * roseWindow));
  finalRgb = mix(finalRgb, finalRgb * vec3<f32>(1.08, 0.92, 1.12), 0.25 * roseWindow);

  let quantError = clamp(reconstructed - quantized, vec3<f32>(-1.0), vec3<f32>(1.0));
  let alpha = clamp(source.a * (0.92 + 0.08 * sourceLuma), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(clamp(finalRgb, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, vec4<f32>(clamp(quantError * 0.5 + 0.5, vec3<f32>(0.0), vec3<f32>(1.0)), leadLine));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(sourceDepth * 0.88 + leadLine * 0.12 + edge * 0.09, 0.0, 1.0), 0.0, 0.0, 0.0));
}
