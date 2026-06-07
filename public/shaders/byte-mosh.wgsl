// ═══════════════════════════════════════════════════════════════════
//  Byte Mosh
//  Category: retro-glitch
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: Very High
//  Scientific: LFSR packet corruption over GF(2) with Gilbert-Elliott burst errors driving datamosh block-copy artifacts.
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

fn pack_rgb8(color: vec3<f32>) -> vec3<u32> {
  return vec3<u32>(round(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)) * 255.0));
}

fn unpack_rgb8(color: vec3<u32>) -> vec3<f32> {
  return vec3<f32>(color) / 255.0;
}

fn lfsr_step(state: u32) -> u32 {
  let s = max(state & 0xffffu, 1u);
  let feedback = ((s >> 0u) ^ (s >> 1u) ^ (s >> 3u) ^ (s >> 12u)) & 1u;
  return ((s >> 1u) | (feedback << 15u)) & 0xffffu;
}

fn lfsr_advance(state: u32, steps: u32) -> u32 {
  var s = max(state, 1u);
  for (var i: u32 = 0u; i < steps; i = i + 1u) {
    s = lfsr_step(s);
  }
  return s;
}

fn galois_mult(a: u32, b: u32) -> u32 {
  var aa = a & 0xffu;
  var bb = b & 0xffu;
  var result: u32 = 0u;
  for (var i: u32 = 0u; i < 8u; i = i + 1u) {
    if ((bb & 1u) != 0u) {
      result = result ^ aa;
    }
    let carry = aa & 0x80u;
    aa = (aa << 1u) & 0xffu;
    if (carry != 0u) {
      aa = aa ^ 0x1bu;
    }
    bb = bb >> 1u;
  }
  return result & 0xffu;
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
  let texel = 1.0 / resolution;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);

  let blockOriginU = (global_id.xy / 8u) * 8u;
  let blockOrigin = vec2<i32>(blockOriginU);
  let blockCenterUV = (vec2<f32>(f32(blockOriginU.x), f32(blockOriginU.y)) + vec2<f32>(4.0)) / resolution;
  let prevState = textureLoad(dataTextureC, blockOrigin, 0);

  var lfsr = max(u32(prevState.r * 65535.0 + 0.5), 1u);
  let prevMask = u32(prevState.g * 65535.0 + 0.5);
  let prevAge = prevState.b * 63.0;
  let prevMode = round(prevState.a * 3.0);

  let blockSeed = ((blockOriginU.x + 1u) * 257u) ^ ((blockOriginU.y + 1u) * 263u) ^ u32(time * 60.0 + 1.0);
  lfsr = lfsr_advance(lfsr ^ blockSeed, 3u);
  let rand0 = f32(lfsr & 0xffffu) / 65535.0;
  lfsr = lfsr_step(lfsr);
  let rand1 = f32(lfsr & 0xffffu) / 65535.0;
  lfsr = lfsr_step(lfsr);
  let rand2 = f32(lfsr & 0xffffu) / 65535.0;
  lfsr = lfsr_step(lfsr);

  var badState = prevMode > 0.5;
  let goodToBad = clamp(0.0001 + bass * bass * 0.18 + step(0.82, bass) * 0.035, 0.0001, 0.24);
  let badToGood = 0.1;
  if (badState) {
    badState = !(rand0 < badToGood);
  } else {
    badState = rand0 < goodToBad;
  }

  let errorProb = select(0.0001, 0.1, badState);
  let burstMask = select(0u, lfsr ^ (prevMask << 1u), rand1 < errorProb || badState);
  let blockTrigger = badState && (((lfsr ^ prevMask) & 0x003fu) == 0x002du || rand2 < bass * 0.12);
  let mode = select(select(0.0, 1.0, badState), 2.0, blockTrigger);
  let corruptionAge = select(0.0, min(prevAge + 1.0, 63.0), badState);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv), 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp_uv(uv), 0.0).r;

  let offsetPixels = vec2<f32>(
    f32(i32((lfsr >> 4u) & 31u) - 15) * (1.5 + bass * 8.0),
    f32(i32((lfsr >> 9u) & 15u) - 7) * (0.5 + mids * 2.0)
  );
  let mouseBias = (uv - mouse) * mouseDown * (8.0 + bass * 18.0);
  let offsetUV = (offsetPixels + mouseBias) * texel;
  let wrongFrameUV = clamp_uv(blockCenterUV + offsetUV);
  let wrongFrameColor = textureSampleLevel(readTexture, u_sampler, wrongFrameUV, 0.0);
  let smearColor = textureSampleLevel(readTexture, u_sampler, clamp_uv(uv + offsetUV), 0.0);

  var glitched = mix(sourceColor.rgb, smearColor.rgb, 0.25 + 0.45 * f32(badState));
  glitched = mix(glitched, wrongFrameColor.rgb, 0.75 * step(1.5, mode));

  var rgb8 = pack_rgb8(glitched);
  let maskR = galois_mult((burstMask >> 0u) & 0xffu, 0x1du ^ ((lfsr >> 3u) & 0xffu));
  let maskG = galois_mult((burstMask >> 5u) & 0xffu, 0x63u ^ ((lfsr >> 7u) & 0xffu));
  let maskB = galois_mult((burstMask >> 9u) & 0xffu, 0xa7u ^ ((lfsr >> 11u) & 0xffu));

  if (badState) {
    rgb8 = vec3<u32>(rgb8.x ^ maskR, rgb8.y ^ maskG, rgb8.z ^ maskB);
  }

  let leftBlock = textureLoad(dataTextureC, vec2<i32>(max(blockOrigin.x - 8, 0), blockOrigin.y), 0);
  let upBlock = textureLoad(dataTextureC, vec2<i32>(blockOrigin.x, max(blockOrigin.y - 8, 0)), 0);
  let boundary = clamp(
    abs(leftBlock.a - prevState.a) + abs(upBlock.a - prevState.a) + abs(leftBlock.g - prevState.g) + abs(upBlock.g - prevState.g),
    0.0,
    1.0
  );
  let rainbow = unpack_rgb8(vec3<u32>(
    galois_mult(rgb8.x ^ maskB, 0x53u),
    galois_mult(rgb8.y ^ maskR, 0xc7u),
    galois_mult(rgb8.z ^ maskG, 0x91u)
  ));

  var finalRgb = unpack_rgb8(rgb8);
  finalRgb = mix(finalRgb, rainbow, boundary * (0.3 + 0.35 * f32(badState)));

  let scanPhase = sin((uv.y * resolution.y + time * 24.0) * PI);
  let scanline = 0.92 + 0.08 * scanPhase;
  let edgeGlow = boundary * (0.18 + 0.35 * treble);
  finalRgb = finalRgb * scanline + rainbow * edgeGlow;

  let luma = dot(finalRgb, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(sourceColor.a * (0.88 + 0.12 * luma) + edgeGlow * 0.05, 0.0, 1.0);
  let stateOut = vec4<f32>(
    f32(lfsr & 0xffffu) / 65535.0,
    f32(burstMask & 0xffffu) / 65535.0,
    corruptionAge / 63.0,
    mode / 3.0
  );

  textureStore(writeTexture, coord, vec4<f32>(clamp(finalRgb, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, stateOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * 0.9 + boundary * 0.12 + f32(badState) * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}
