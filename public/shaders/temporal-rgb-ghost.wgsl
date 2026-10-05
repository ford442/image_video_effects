// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Ghost
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring,
//            upgraded-rgba, per-channel-temporal-offset, noise-displacement,
//            vignette-falloff, chromatic-ghost
//  Complexity: Medium
//  Upgraded: 2026-10-04 (prev 2026-06-28)
//  Ideas: blue comet-tail integration over ring ages; motion-gated displacement; fractional G delay
//  A packing: display RGBA
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a
//         hardcoded 8 — see HISTORY RING DEPTH below
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
//
//  Per-channel temporal displacement with added per-channel angular drift,
//  FBM-driven ghost displacement, and vignette falloff.  R channel uses
//  the current frame, G samples a delayed frame with slight directional
//  offset, and B samples an even older frame displaced by evolving noise.
//  Moving objects leave rainbow comet tails that shimmer organically.
//
//  zoom_params layout:
//    x = G channel delay (0→age 1, 1→age 7, default 0.17→age 2)
//    y = B channel delay (0→age 1, 1→age 7, default 0.67→age 5)
//    z = ghost blend (0→original only, 1→ghost only, default 0.80)
//    w = luma boost / noise displacement (0→none, 1→strong)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=G-delay, y=B-delay, z=blend, w=displace
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

const PI: f32 = 3.14159265358979323846;

// ── Hash & Noise ─────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Vignette falloff ─────────────────────────────────────────────
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let d = length(uv - vec2<f32>(0.5));
  let v = smoothstep(0.5, 0.5 - strength, d);
  return color * v;
}

// ── Displace UV by evolving FBM ──────────────────────────────────
fn displacedUV(uv: vec2<f32>, time: f32, strength: f32, seed: f32) -> vec2<f32> {
  let n1 = fbm(uv * 10.0 + vec2<f32>(seed, time * 0.2), 3);
  let n2 = fbm(uv * 10.0 + vec2<f32>(time * 0.15, seed + 31.0), 3);
  return uv + (vec2<f32>(n1, n2) - 0.5) * strength;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Clamp params
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));

  // ── HISTORY RING DEPTH (floor fix, 2026-09-21) ───────────────────
  // The ring is at most 8 layers; after the VRAM probe the runtime may
  // allocate 8, 4 or 1, and it wraps its write head at the ALLOCATED
  // count (renderer/webgpu/frame.ts). A hardcoded HISTORY_DEPTH=8 asked
  // for layers that do not exist on a 4- or 1-layer device and WGSL
  // clamped them to the last layer: scrambled frame order, silently.
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let maxAge = histDepth - 1u;
  // Idea 3 — fractional delay: G crossfades between neighbouring ring ages so the
  // slider glides instead of stepping (floor matches HEAD's integer age).
  let ageGF = 1.0 + zp.x * 7.0;
  let ageG = min(u32(ageGF), maxAge);
  let ageG2 = min(ageG + 1u, maxAge);
  let ageGFrac = fract(ageGF);
  let ageB = min(1u + u32(zp.y * 7.0), maxAge);
  let blendAmt   = clamp(zp.z * (1.0 + bass * 0.4), 0.0, 1.0);
  let displaceBase = zp.w * 0.04 * (1.0 + bass * 0.6 + treble * 0.3);
  let lumaBoost  = 1.0 + zp.w * (1.0 + mids * 0.5);

  let historyHead = u32(extraBuffer[4]);

  // Current frame for R
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // Idea 2 — motion-gated displacement: only pixels that changed since the newest ring
  // frame wobble, so static areas stay clean and moving edges shimmer.
  let layerRecent = (historyHead + histDepth - min(1u, maxAge)) % histDepth;
  let recent = textureSampleLevel(historyTexture, u_sampler, uv, i32(layerRecent), 0.0);
  let motion = smoothstep(0.03, 0.2, length(recent.rgb - current.rgb));
  let displace = displaceBase * (0.15 + 0.85 * motion);

  // G channel: delayed frame with slight temporal angular drift
  let layerG = (historyHead + histDepth - ageG) % histDepth;
  let dispG = displacedUV(uv, time, displace * 0.6, 12.0);
  let layerG2 = (historyHead + histDepth - ageG2) % histDepth;
  let histG = mix(
    textureSampleLevel(historyTexture, u_sampler, dispG, i32(layerG), 0.0),
    textureSampleLevel(historyTexture, u_sampler, dispG, i32(layerG2), 0.0),
    ageGFrac);

  // B channel: older frame with larger noise displacement and opposite drift
  let layerB = (historyHead + histDepth - ageB) % histDepth;
  let dispB = displacedUV(uv, time, displace, 94.0);
  // Idea 1 — comet-tail integration: B averages every ring frame from the G age out to
  // the B age (weighted toward the oldest), turning the blue copy into a continuous streak.
  let tailStart = min(ageG, ageB);
  var tailSum = textureSampleLevel(historyTexture, u_sampler, dispB, i32(layerB), 0.0) * 2.0;
  var tailW = 2.0;
  for (var a: u32 = tailStart; a < ageB; a = a + 1u) {
    let la = (historyHead + histDepth - a) % histDepth;
    tailSum += textureSampleLevel(historyTexture, u_sampler, dispB, i32(la), 0.0);
    tailW += 1.0;
  }
  let histB = tailSum / tailW;

  // Assemble RGB ghost with per-channel temporal offset
  let ghost = vec4<f32>(
    current.r,
    histG.g * lumaBoost,
    histB.b * lumaBoost,
    clamp(blendAmt + bass * 0.15, 0.0, 1.0),
  );

  let output = mix(current.rgb, ghost.rgb, blendAmt);
  let ghostSpread = length(output - current.rgb);

  // Vignette darkens the chromatic ghost trails toward the corners
  let vignette = applyVignette(output, uv, 0.35 + zp.w * 0.25);

  // Preserve input alpha, boosted by ghost energy
  let alpha = clamp(current.a * 0.5 + ghostSpread * 3.0 + bass * 0.1, 0.0, 1.0);
  let finalOut = vec4<f32>(vignette, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
