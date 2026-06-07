// ═══════════════════════════════════════════════════════════════════
//  Lenia on Video
//  Category: simulation
//  Features: simulation, temporal, video-driven, cellular-automata,
//             audio-reactive, mouse-driven, lenia, continuous-ca
//  Complexity: High
//  Created: 2026-05-23
//  By: Copilot
//
//  Continuous Lenia cellular automaton (Bert Wang-Chak Chan, 2019)
//  whose *food field* and *growth parameters* are continuously driven
//  by the live video feed:
//
//    • Video luminance  → seeds initial cell state at startup
//    • Video hue/chroma → modulates the Lenia growth center (μ)
//    • Video saturation → modulates growth width (σ)
//    • Bass audio       → periodic injection of fresh cells from video
//    • Mouse click      → spawns a burst of Lenia cells at cursor
//    • Mouse hold       → clears cells near cursor
//
//  The CA state persists in dataTextureC (ping-pong via dataTextureA),
//  and the visual output composites the Lenia cells over the source
//  video using a neon bioluminescent color map.
//
//  zoom_params layout:
//    x = kernel radius  (0→tight r=4, 1→wide r=12, default 0.4)
//    y = video coupling (0→fully autonomous, 1→strongly video-driven, default 0.5)
//    z = glow intensity (0→dim, 1→bright, default 0.6)
//    w = composite mix  (0→video only, 1→CA only, default 0.5)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=kernelRadius, y=videoCoupling, z=glowIntensity, w=compositeMix
  ripples: array<vec4<f32>, 50>,
};

// ── Lenia bell-curve growth / kernel functions ────────────────────────────────
fn leniaBell(x: f32, mu: f32, sigma: f32) -> f32 {
  let d = (x - mu) / (sigma + 0.0001);
  return exp(-d * d * 0.5);
}

// Smooth-ring kernel: peaks at r = radius*0.5 with width radius*0.15
fn leniaKernel(r: f32, radius: f32) -> f32 {
  if (r >= radius) { return 0.0; }
  let peak = radius * 0.5;
  let width = radius * 0.15;
  return leniaBell(r, peak, width);
}

// Growth function: 2·bell(n, mu, sigma) - 1  maps to [-1, +1]
fn leniaGrowth(n: f32, mu: f32, sigma: f32) -> f32 {
  return leniaBell(n, mu, sigma) * 2.0 - 1.0;
}

// Pseudo-random for video-seeding
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// RGB → HSV helper (returns hue in [0,1])
fn rgbHue(c: vec3<f32>) -> f32 {
  let M = max(max(c.r, c.g), c.b);
  let m = min(min(c.r, c.g), c.b);
  let d = M - m;
  if (d < 0.001) { return 0.0; }
  var h = 0.0;
  if (M == c.r)      { h = (c.g - c.b) / d;       }
  else if (M == c.g) { h = 2.0 + (c.b - c.r) / d; }
  else               { h = 4.0 + (c.r - c.g) / d; }
  return fract(h / 6.0);
}

fn rgbSat(c: vec3<f32>) -> f32 {
  let M = max(max(c.r, c.g), c.b);
  let m = min(min(c.r, c.g), c.b);
  return select(0.0, (M - m) / M, M > 0.001);
}

// Neon bioluminescence color map
fn leniaColor(value: f32, hueShift: f32) -> vec3<f32> {
  let h = fract(hueShift + value * 0.4 + 0.55);  // cyan-green base
  let s = 0.7 + value * 0.3;
  let v = 0.2 + value * 0.8;
  // HSV → RGB (compact)
  let c  = v * s;
  let h6 = h * 6.0;
  let x  = c * (1.0 - abs(h6 % 2.0 - 1.0));
  let m  = v - c;
  var rgb: vec3<f32>;
  if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else               { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + m;
}

// ── Main ─────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv   = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixSz = 1.0 / res;
  let time  = u.config.x;

  let bass      = plasmaBuffer[0].x;
  let mids      = plasmaBuffer[0].y;
  let treble    = plasmaBuffer[0].z;
  let mouse     = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let kernelRadius  = 4.0 + u.zoom_params.x * 8.0;       // 4–12 pixels (normalised)
  let videoCoupling = u.zoom_params.y;
  let glowInt       = 0.5 + u.zoom_params.z * 1.5;
  let compositeMix  = u.zoom_params.w;

  // ── Sample video at this pixel ────────────────────────────────────────────
  let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let vidLuma  = dot(vidColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let vidHue   = rgbHue(vidColor.rgb);
  let vidSat   = rgbSat(vidColor.rgb);

  // Video-driven growth parameters
  let growthMu    = mix(0.15, 0.35, vidLuma * videoCoupling + 0.15 * (1.0 - videoCoupling));
  let growthSigma = mix(0.015, 0.06, vidSat  * videoCoupling + 0.04 * (1.0 - videoCoupling));

  // ── Read previous CA state from ping-pong buffer ──────────────────────────
  let prevState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

  // ── Lenia kernel convolution over a (2r+1)×(2r+1) window ─────────────────
  //    Kernel radius in UV space
  let rUV    = kernelRadius / min(res.x, res.y);
  let rPix   = i32(kernelRadius) + 1;
  var convAcc = 0.0;
  var kernSum = 0.0;

  for (var dy = -rPix; dy <= rPix; dy++) {
    for (var dx = -rPix; dx <= rPix; dx++) {
      let off    = vec2<f32>(f32(dx), f32(dy)) * pixSz;
      let p      = clamp(uv + off, vec2<f32>(0.0), vec2<f32>(1.0));
      let rNorm  = length(vec2<f32>(f32(dx), f32(dy))) / kernelRadius;
      let kw     = leniaKernel(rNorm, 1.0);
      let cellVal = textureSampleLevel(dataTextureC, u_sampler, p, 0.0).r;
      convAcc    += cellVal * kw;
      kernSum    += kw;
    }
  }

  let neighborhood = select(0.0, convAcc / kernSum, kernSum > 0.001);

  // ── Lenia growth update ──────────────────────────────────────────────────
  let dt = 0.1 + mids * 0.05;
  var newState = clamp(prevState + dt * leniaGrowth(neighborhood, growthMu, growthSigma), 0.0, 1.0);

  // ── Video-coupling injection: bass beat injects cells from bright video ───
  let beatPulse = step(0.6, bass);
  let seedThresh = 0.55 + (1.0 - videoCoupling) * 0.35;
  if (vidLuma > seedThresh && beatPulse > 0.5) {
    newState = mix(newState, vidLuma * 0.9, videoCoupling * 0.3);
  }

  // ── Mouse interaction ────────────────────────────────────────────────────
  let mDist = length(uv - mouse) * min(res.x, res.y);
  if (mouseDown > 0.5 && mDist < 20.0) {
    // Spawn burst of cells with noise
    let n = hash21(uv + vec2<f32>(time * 0.1));
    newState = mix(newState, 0.8 + n * 0.2, smoothstep(20.0, 0.0, mDist));
  } else if (mouseDown < -0.5 && mDist < 15.0) {
    // Clear cells on right-click hold (mouseDown encodes button via sign)
    newState = mix(newState, 0.0, smoothstep(15.0, 0.0, mDist));
  }

  // Store new CA state
  textureStore(dataTextureA, coord, vec4<f32>(newState, newState, newState, 1.0));

  // ── Colour mapping + glow ────────────────────────────────────────────────
  let hueShift  = vidHue * videoCoupling + time * 0.02;
  let caColor   = leniaColor(newState, hueShift) * newState * glowInt;

  // Additive glow bloom approximation: sample 4 neighbours
  var bloom = caColor;
  let bOff  = pixSz * 2.0;
  bloom += leniaColor(textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(bOff.x, 0.0), 0.0).r, hueShift) * 0.25;
  bloom += leniaColor(textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(bOff.x, 0.0), 0.0).r, hueShift) * 0.25;
  bloom += leniaColor(textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, bOff.y), 0.0).r, hueShift) * 0.25;
  bloom += leniaColor(textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, bOff.y), 0.0).r, hueShift) * 0.25;

  let caFinal = caColor + bloom * 0.15 * glowInt;

  // ── Composite CA over video ───────────────────────────────────────────────
  let output = mix(vidColor.rgb, caFinal, compositeMix * min(newState * 2.0 + 0.1, 1.0));
  let alpha   = clamp(newState * 1.5 + 0.3 + bass * 0.2, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, vec4<f32>(output, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
