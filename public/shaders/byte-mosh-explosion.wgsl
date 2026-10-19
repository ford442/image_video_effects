// ═══════════════════════════════════════════════════════════════════
//  Byte Mosh Explosion — Batch 62
//  Bitwise corruption + chromatic prism: spring cursor, held boost,
//  capped ripples, audio-reactive error rate, ACES + semantic alpha.
//  Upgraded: 2026-10-19
//  Ideas: resync propagation (byte slips smear forward to the next resync
//         marker); decoder error concealment from exact C; Cauchy prism
//  A packing: ACES display RGBA (HEAD wrote blue byte/error/glow/alpha that
//  nothing read; C is now read as colour for concealment)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash11(p: f32) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 * (p3 + 33.33);
  return fract(p3 * (p3 + p3));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

const MAX_CHANNEL_VALUE: f32 = 255.0;

// Idea 3: Cauchy prism. n(λ) = A + B/λ² at 650/550/450 nm, relative to green:
// B/λ² = 2.367, 3.306, 4.938 µm⁻² → (−0.939, 0, +1.632), rescaled to HEAD's
// total spread of 2. Blue bends ~1.7× more than red instead of −1/0/+1.
const CAUCHY_R: f32 = -0.730;
const CAUCHY_B: f32 = 1.270;
// Idea 1: a slice of 4 blocks ends in a resync marker.
const RESYNC_BLOCKS: u32 = 4u;

fn floatToU32(x: f32) -> u32 {
  return u32(clamp(x, 0.0, 1.0) * MAX_CHANNEL_VALUE);
}

fn u32ToFloat(x: u32) -> f32 {
  return f32(x & 0xFFu) / MAX_CHANNEL_VALUE;
}

fn packRGBA(r: f32, g: f32, b: f32, a: f32) -> u32 {
  return (floatToU32(a) << 24u) | (floatToU32(r) << 16u) | (floatToU32(g) << 8u) | floatToU32(b);
}

fn unpackRGBA(packed: u32) -> vec4<f32> {
  return vec4<f32>(
    f32((packed >> 16u) & 0xFFu) / 255.0,
    f32((packed >> 8u) & 0xFFu) / 255.0,
    f32(packed & 0xFFu) / 255.0,
    f32((packed >> 24u) & 0xFFu) / 255.0
  );
}

fn rotateLeft(x: u32, n: u32) -> u32 {
  return (x << n) | (x >> (32u - n));
}

fn prismDisplace(uv: vec2<f32>, mousePos: vec2<f32>, wavelengthOffset: f32, strength: f32) -> vec2<f32> {
  let toMouse = uv - mousePos;
  let dist = length(toMouse);
  let prismAngle = atan2(toMouse.y, toMouse.x);
  let deflection = wavelengthOffset * strength / max(dist, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  return uv + perpendicular * deflection;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }

  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let aspect = f32(size.x) / f32(size.y);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = u.zoom_config.w > 0.5;

  let operationMix = u.zoom_params.x;
  let bitShift = u32(mix(0.0, 8.0, u.zoom_params.y));
  let errorRate = mix(0.0, 0.5, u.zoom_params.z) * (1.0 + bass * 0.25);
  let prismStrength = mix(0.02, 0.12, u.zoom_params.w) * select(1.0, 1.35, held);

  let blockSize = max(1.0, mix(1.0, 64.0, u.zoom_params.y));
  let blockCoord = vec2<u32>(u32(floor(f32(coord.x) / blockSize)), u32(floor(f32(coord.y) / blockSize)));
  let blockNoise = hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) + vec2<f32>(floor(time * 2.0)));
  let pixelNoise = hash21(uv * 1000.0 + vec2<f32>(time));
  let bandBin = (blockCoord.x + blockCoord.y) % 8u + 1u;
  let fftBlock = plasmaBuffer[bandBin].x;
  let effectiveError = errorRate * (0.85 + fftBlock * 0.3 + operationMix * 0.15);

  let mousePos = u.zoom_config.yz;
  var smoothMouse = mousePos;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mousePos;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mousePos - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }
  let mouseDown = select(u.zoom_config.w, 1.0, held);

  // ═══ CHROMATIC EXPLOSION SAMPLING ═══
  let rUV = prismDisplace(uv, smoothMouse, CAUCHY_R, prismStrength);
  let gUV = prismDisplace(uv, smoothMouse, 0.0, prismStrength);
  let bUV = prismDisplace(uv, smoothMouse, CAUCHY_B, prismStrength);

  // Ripple chromatic shockwaves
  let rippleCount = min(u32(u.config.y), 50u);
  var rOffset = vec2<f32>(0.0);
  var gOffset = vec2<f32>(0.0);
  var bOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let rWave = sin(rDist * 30.0 - elapsed * 10.0 - 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let bWave = sin(rDist * 30.0 - elapsed * 10.0 + 0.5) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rOffset = rOffset + dir * rWave * 0.03;
      gOffset = gOffset + dir * wave * 0.03;
      bOffset = bOffset + dir * bWave * 0.03;
    }
  }

  let intensity = 1.0 + mouseDown * 1.5;
  let r = textureSampleLevel(readTexture, u_sampler, rUV + rOffset * intensity, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, gUV + gOffset * intensity, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, bUV + bOffset * intensity, 0.0).b;

  var sourceColor = vec4<f32>(r, g, b, 1.0);
  let depth = textureLoad(readDepthTexture, vec2<i32>(coord), 0).r;

  var packedColor = packRGBA(sourceColor.r, sourceColor.g, sourceColor.b, sourceColor.a);

  if (blockNoise < effectiveError) {
    let opSelector = fract(blockNoise * 7.0);
    if (opSelector < 0.15) {
      let xorPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 123.0) * 4294967295.0);
      packedColor = packedColor ^ xorPattern;
    } else if (opSelector < 0.3) {
      let andMask = 0xF0F0F0F0u << bitShift;
      packedColor = packedColor & andMask;
    } else if (opSelector < 0.45) {
      let orPattern = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 456.0) * 4294967295.0) & 0x7F7F7F7Fu;
      packedColor = packedColor | orPattern;
    } else if (opSelector < 0.6) {
      packedColor = packedColor << bitShift;
    } else if (opSelector < 0.75) {
      packedColor = packedColor >> bitShift;
    } else if (opSelector < 0.9) {
      let rotAmount = u32(hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 789.0) * 32.0);
      packedColor = rotateLeft(packedColor, rotAmount);
    } else {
      let a = (packedColor >> 24u) & 0xFFu;
      let r_ch = (packedColor >> 16u) & 0xFFu;
      let g_ch = (packedColor >> 8u) & 0xFFu;
      let b_ch = packedColor & 0xFFu;
      let swapType = u32(time * 3.0) % 8u;
      if (swapType == 0u) { packedColor = (a << 24u) | (g_ch << 16u) | (r_ch << 8u) | b_ch; }
      else if (swapType == 1u) { packedColor = (r_ch << 24u) | (a << 16u) | (g_ch << 8u) | b_ch; }
      else if (swapType == 2u) { packedColor = (b_ch << 24u) | (r_ch << 16u) | (a << 8u) | g_ch; }
      else if (swapType == 3u) { packedColor = (g_ch << 24u) | (b_ch << 16u) | (r_ch << 8u) | a; }
      else if (swapType == 4u) { packedColor = (a << 24u) | (b_ch << 16u) | (g_ch << 8u) | r_ch; }
      else if (swapType == 5u) { packedColor = (a << 24u) | (r_ch << 16u) | (b_ch << 8u) | g_ch; }
      else if (swapType == 6u) { packedColor = (g_ch << 24u) | (a << 16u) | (b_ch << 8u) | r_ch; }
    }
  }

  // ── Idea 1: resync propagation. A corrupted word desynchronises the decoder
  // until the next resync marker, so a block up to 3 blocks to the left in the
  // same slice smears forward as a byte slip (word rotated by 8 bits:
  // R←G←B←A), decaying with distance. Rolled per scanline, like a decoder
  // losing sync mid-row.
  let timeSlot = floor(time * 2.0);
  let sliceStart = (blockCoord.x / RESYNC_BLOCKS) * RESYNC_BLOCKS;
  var slip = 0.0;
  for (var k = 1u; k <= 3u; k = k + 1u) {
    if (blockCoord.x >= sliceStart + k) {
      let upstreamBlock = vec2<f32>(f32(blockCoord.x - k), f32(blockCoord.y));
      let upstreamNoise = hash21(upstreamBlock + vec2<f32>(timeSlot));
      if (upstreamNoise < effectiveError) {
        slip = max(slip, exp(-f32(k) * 0.7));
      }
    }
  }
  let slipRoll = hash21(vec2<f32>(f32(blockCoord.x) * 1.37, f32(coord.y)) + vec2<f32>(timeSlot * 0.61));
  if (blockNoise >= effectiveError && slipRoll < slip * 0.85) {
    packedColor = rotateLeft(packedColor, 8u);
  }

  if (pixelNoise < effectiveError * 0.3) {
    let flipMask = u32(pixelNoise * 4294967295.0) & (0xFFu << (bitShift * 4u));
    packedColor = packedColor ^ flipMask;
  }

  // Mouse glitch zone
  let mouseDist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = 0.15 * select(1.0, 1.4, held);
  if (mouseDist < mouseInfluence) {
    let strength = 1.0 - mouseDist / mouseInfluence;
    let mouseGlitch = u32(strength * 255.0);
    let distPattern = u32(mouseDist * 1000.0) * 0x11111111u;
    packedColor = packedColor ^ (distPattern & ((mouseGlitch << 24u) | (mouseGlitch << 16u) | (mouseGlitch << 8u) | mouseGlitch));
  }

  // Ripple bit rotations
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 1.5) {
        let dist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        let ring = abs(dist - rippleAge * 0.3);
        if (ring < 0.02) {
          let rippleStrength = (1.0 - rippleAge / 1.5);
          let rippleShift = u32(rippleStrength * 8.0);
          packedColor = rotateLeft(packedColor, rippleShift);
        }
      }
    }
  }

  var finalColor = unpackRGBA(packedColor);
  let scanline = sin(uv.y * f32(size.y) * 3.14159) * 0.1 + 0.9;

  if (blockNoise < effectiveError) {
    let flicker = hash11(time * 100.0 + f32(coord.x)) * 0.2 + 0.8;
    finalColor = vec4<f32>(finalColor.rgb * flicker * scanline, finalColor.a * (0.7 + flicker * 0.3));
  }

  // Spectral glow near mouse
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor = vec4<f32>(finalColor.rgb + vec3<f32>(0.5, 0.3, 0.8) * glow, finalColor.a);

  // WGSL has no swizzle assignment: HEAD's `finalColor.rgb = …` failed Naga.
  let alpha = clamp(finalColor.a + glow * 0.15 + bass * 0.05, 0.0, 1.0);
  finalColor = vec4<f32>(acesToneMap(finalColor.rgb * (0.96 + mids * 0.05)), alpha);
  finalColor = clamp(finalColor, vec4<f32>(0.0), vec4<f32>(1.0));

  // ── Idea 2: decoder error concealment. A share of corrupted blocks are not
  // decoded at all: the decoder repeats the previous frame's block (exact C,
  // already ACES display), so stale tiles hold for the 0.5 s slot.
  let concealRoll = hash21(vec2<f32>(f32(blockCoord.x), f32(blockCoord.y)) * 3.17 + vec2<f32>(timeSlot + 7.0));
  let conceal = blockNoise < effectiveError && concealRoll < 0.3 + operationMix * 0.2;
  let prevDecoded = textureLoad(dataTextureC, vec2<i32>(coord), 0);
  finalColor = select(finalColor, vec4<f32>(prevDecoded.rgb, max(prevDecoded.a, 0.6)), conceal);

  textureStore(writeTexture, vec2<i32>(coord), finalColor);
  textureStore(dataTextureA, vec2<i32>(coord), finalColor);
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
