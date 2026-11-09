// ═══════════════════════════════════════════════════════════════════
//  Digital Decay RGBA
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: seam-born rot; bit-depth erosion; macroblock chroma bleed
//  A packing: raw 4-species RD state (A, B, C, D)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn hash11(p: f32) -> f32 {
  var v = fract(p * 0.1031);
  v = fract(v + dot(vec2<f32>(v, v), vec2<f32>(v, v) + 33.33));
  return fract(v * v * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  var v = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  v = fract(v + dot(v, v.yzx + 33.33));
  return fract((v.x + v.y) * v.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectralRD(a: f32, b: f32, c: f32, d: f32, t: f32) -> vec3<f32> {
  let colA = vec3<f32>(0.05, 0.35, 1.0) * a;
  let colB = vec3<f32>(1.0, 0.15, 0.45) * b;
  let colC = vec3<f32>(0.1, 1.0, 0.4) * c;
  let colD = vec3<f32>(1.0, 0.75, 0.1) * d;
  let base = colA + colB + colC + colD;
  let hue = vec3<f32>(
    0.5 + 0.5 * cos(6.28318 * (t + 0.0)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.33)),
    0.5 + 0.5 * cos(6.28318 * (t + 0.67))
  );
  return base * (0.7 + hue * 0.3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let dims = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let intensity = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.2);
  let rawBlock = clamp(u.zoom_params.y, 0.0, 1.0);
  let corruptionSpeed = clamp(u.zoom_params.z, 0.0, 1.0) * 5.0 * (1.0 + mids * 0.3);
  let feed = mix(0.02, 0.06, u.zoom_params.w);

  // HEAD rescue: the extraBuffer[133..138] spring is zeroed every frame, which
  // pinned the held burst to (0,0). Use the live pointer.
  let smoothMouse = mouse;

  let depth = textureLoad(readDepthTexture, coord, 0).r;

  let blockSizePx = floor(mix(5.0, 150.0, rawBlock));
  let blockUV = vec2<i32>(i32(floor(uv.x * resolution.x / blockSizePx)), i32(floor(uv.y * resolution.y / blockSizePx)));
  let id = f32((blockUV.x * 73856093) ^ (blockUV.y * 19349663));
  let blockHashTime = floor(time * corruptionSpeed * hash11(id + 1.0));
  let blockHash = hash21(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) + blockHashTime);

  var glitchUV = uv;
  let signalStrength = 0.55 + 0.45 * sin(time * corruptionSpeed * 0.2);
  var corruptionAmount = (1.0 - signalStrength) * intensity * 2.0;

  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let mouseAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
  let mouseDist = length(uvAspect - mouseAspect);
  let mouseBurst = smoothstep(0.18, 0.0, mouseDist) * select(0.0, 1.0, held);
  corruptionAmount = clamp(corruptionAmount + mouseBurst * 0.6, 0.0, 2.0);

  var rippleBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      rippleBurst += smoothstep(0.12, 0.0, length(uvAspect - rAspect)) * (1.0 - age);
    }
  }
  corruptionAmount = clamp(corruptionAmount + rippleBurst * 0.5, 0.0, 2.0);

  if (blockHash < (corruptionAmount * 0.5)) {
    let disp = (hash22(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) * 99.0 + blockHashTime) - 0.5) * 0.4;
    glitchUV = clamp(glitchUV + disp, vec2<f32>(0.0), vec2<f32>(1.0));
  }

  let pixelHash = hash21(uv * 500.0 + time * corruptionSpeed);
  if (blockHash < (corruptionAmount * 0.2)) {
    glitchUV += (vec2<f32>(pixelHash, hash21(uv * 600.0)) - 0.5) * vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y) * 20.0;
    glitchUV = clamp(glitchUV, vec2<f32>(0.0), vec2<f32>(1.0));
  }

  let aberrationOffset = (hash22(uv + time * 0.1) - 0.5) * 0.012 * corruptionAmount;
  let r = textureSampleLevel(readTexture, u_sampler, glitchUV + aberrationOffset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, glitchUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, glitchUV - aberrationOffset, 0.0).b;
  var decayColor = vec3<f32>(r, g, b);

  // Idea 3 — macroblock chroma bleed: corrupted blocks carry one chroma sample
  // from the block centre (4:2:0-style); luma stays per pixel.
  let blockCorrupt = blockHash < corruptionAmount * 0.5;
  if (blockCorrupt) {
    let centreUV = clamp((vec2<f32>(blockUV) + 0.5) * blockSizePx / resolution + (glitchUV - uv), vec2<f32>(0.0), vec2<f32>(1.0));
    let cc = textureSampleLevel(readTexture, u_sampler, centreUV, 0.0).rgb;
    let wY = vec3<f32>(0.299, 0.587, 0.114);
    decayColor = clamp(cc - vec3<f32>(dot(cc, wY)) + vec3<f32>(dot(decayColor, wY)), vec3<f32>(0.0), vec3<f32>(1.0));
  }

  let scanLine = sin(uv.y * resolution.y * 1.5 + time) * 0.04 * corruptionAmount;
  decayColor -= scanLine;
  let noise = (hash11(dot(uv, vec2<f32>(12.9898, 78.233)) + time) - 0.5) * 0.15 * corruptionAmount;
  decayColor += noise;
  decayColor = clamp(decayColor, vec3<f32>(0.0), vec3<f32>(1.0));

  let state = textureLoad(dataTextureC, coord, 0);
  var A = state.r;
  var B = state.g;
  var C = state.b;
  var D = state.a;

  if (time < 0.1) {
    A = 1.0; B = 0.0; C = 1.0; D = 0.0;
    let centerDist = length(uv - vec2<f32>(0.5));
    if (centerDist < 0.05) { B = 0.5; D = 0.3; }
  }

  if (corruptionAmount > 0.3 && blockHash < corruptionAmount * 0.3) {
    B += corruptionAmount * 0.2;
    D += corruptionAmount * 0.1;
  }
  // Idea 1 — seam-born rot: corrupted blocks inject B/D along their borders,
  // so the decay organism grows out of the macroblock seams.
  if (blockCorrupt) {
    let inBlock = fract(uv * resolution / blockSizePx);
    let seamPx = min(min(inBlock.x, 1.0 - inBlock.x), min(inBlock.y, 1.0 - inBlock.y)) * blockSizePx;
    let seam = smoothstep(2.0, 0.0, seamPx);
    B += seam * (0.08 + corruptionAmount * 0.12);
    D += seam * hash21(vec2<f32>(blockUV) + 7.0) * 0.06;
  }

  let left = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let right = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let down = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1)), 0);
  let up = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0);

  let lapA = left.r + right.r + down.r + up.r - 4.0 * A;
  let lapB = left.g + right.g + down.g + up.g - 4.0 * B;
  let lapC = left.b + right.b + down.b + up.b - 4.0 * C;
  let lapD = left.a + right.a + down.a + up.a - 4.0 * D;

  let kill = mix(0.04, 0.07, intensity);
  let diffA = 0.8; let diffB = 0.3; let diffC = 0.7; let diffD = 0.25;
  let crossInhibit = intensity * 0.3;
  let dt = 0.8;

  let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
  let dB = diffB * lapB + A * B * B - (feed + kill) * B;
  let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
  let dD = diffD * lapD + C * D * D - (feed + kill) * D;

  A = clamp(A + dA * dt, 0.0, 1.0);
  B = clamp(B + dB * dt, 0.0, 1.0);
  C = clamp(C + dC * dt, 0.0, 1.0);
  D = clamp(D + dD * dt, 0.0, 1.0);

  let mouseInfluence = smoothstep(0.12, 0.0, mouseDist) * select(0.0, 1.0, held || u.zoom_config.w > 0.0);
  B += mouseInfluence * 0.35 + rippleBurst * 0.2;
  D += mouseInfluence * 0.25 + treble * 0.05 * mouseInfluence;
  B = clamp(B, 0.0, 1.0);
  D = clamp(D, 0.0, 1.0);

  textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

  // Idea 2 — bit-depth erosion: where the rot species are dense the picture
  // loses colour precision (8 bits → 2 bits), before the RD tint is mixed in.
  let rot = clamp((B + D) * 1.6, 0.0, 1.0);
  let levels = exp2(mix(8.0, 2.0, rot));
  decayColor = mix(decayColor, floor(decayColor * levels + 0.5) / levels, step(0.02, rot));

  let rdColor = spectralRD(A, B, C, D, time * 0.05 + bass * 0.1);
  var finalColor = mix(decayColor, rdColor, intensity * 0.65);
  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.08));
  let alpha = clamp(0.5 + (A + C) * 0.25 + corruptionAmount * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
