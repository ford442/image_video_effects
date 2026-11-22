// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Ghost
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring,
//            per-channel-temporal-offset, noise-displacement,
//            vignette-falloff, chromatic-ghost
//  Complexity: Medium
//  Upgraded: 2026-10-30 (prev 2026-10-04), 2026-11-22
//  Ideas: blue comet-tail integration; motion-gated displacement; fractional G delay; leading red; disagreement fringe; highlight-weighted comet (tube comet-tailing); held-pointer time focus
//  A packing: display RGBA
//  Rescue (2026-11-22): the ring holds this shader's own presented output (BINDING_CONTRACT: "copy
//         presented color into historyTexture"), so HEAD's G/B gain (blend x luma boost ~ 1.0) and
//         its whole-picture vignette compounded every frame: a static photo went black with a cyan
//         blob at the centre. Now: vignette scoped to the ghost deviation, boost = bounded lift on
//         moving pixels, tube-lag discharge leak so no ghost can latch, disagreement fringe compares
//         luma (HEAD compared G against B). `upgraded-rgba` dropped: no ACES, bounded passthrough.
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
//  Pointer: holding the button pulls G/B into register inside a round lens at the cursor.
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

// ── Trail falloff (vignette on the ghost only) ───────────────────
// Rescue: HEAD multiplied the WHOLE output by a (reversed-edge) smoothstep and the result was
// re-read from the ring, so the picture compounded to black. This weight scales only the ghost
// deviation: 1 near the centre, ~0.15 at the corners; the live photo is never darkened.
fn trailFalloff(uv: vec2<f32>, strength: f32) -> f32 {
  let d = length(uv - vec2<f32>(0.5));
  return 1.0 - 0.85 * smoothstep(0.72 - strength * 1.2, 0.72, d);
}

// Rescue: luma boost as a bounded lift (soft ceiling at 1, only on moving pixels) instead of a
// channel gain, so the ring feedback loop gain stays below 1 for every slider value.
fn liftCh(x: f32, lift: f32) -> f32 {
  let xc = clamp(x, 0.0, 1.0);
  return clamp(x + lift * xc * (1.0 - xc), 0.0, max(x, 1.0));
}

// Idea 1 helper — tube comet-tailing: a tap's weight grows with its own luma, so highlights
// dominate the comet and dark objects leave faint ones.
fn tapWeight(c: vec4<f32>) -> f32 {
  let l = clamp(rgbToLuma(c.rgb), 0.0, 1.0);
  return 1.0 + 3.0 * l * l;
}

// ── Displace UV by evolving FBM ──────────────────────────────────
fn displacedUV(uv: vec2<f32>, time: f32, strength: f32, seed: f32) -> vec2<f32> {
  let n1 = fbm(uv * 10.0 + vec2<f32>(seed, time * 0.2), 3);
  let n2 = fbm(uv * 10.0 + vec2<f32>(time * 0.15, seed + 31.0), 3);
  return uv + (vec2<f32>(n1, n2) - 0.5) * strength;
}

// ── History ring read (#1307) ────────────────────────────────────
// Every ring read goes through here. Ages clamp to the oldest layer the ring
// actually holds; age 0 is the live frame — which is all a 1-layer ring has
// (the host never writes a 1-layer ring, so its layer 0 is stale). On an
// 8-layer ring this is the same layer lookup as before. Mirrors
// temporal-slit-scan.wgsl frameAt.
fn frameAt(uv: vec2<f32>, head: u32, depth: u32, age: u32, current: vec4<f32>) -> vec4<f32> {
  let a = min(age, depth - 1u);
  if (a == 0u) { return current; }
  let layer = (head + depth - a) % depth;
  return textureSampleLevel(historyTexture, u_sampler, uv, i32(layer), 0.0);
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
  // count (renderer/webgpu/frame.ts). A hardcoded ring depth of 8 asked
  // for layers that do not exist on a 4- or 1-layer device and WGSL
  // clamped them to the last layer: scrambled frame order, silently.
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let maxAge = histDepth - 1u;
  // ── Idea 2: held-pointer time focus ─────────────────────────────
  // While the button is held, the G/B delays collapse toward age 0 (the live frame) inside a
  // round lens at the cursor: the operator pulls a subject into register while the rest of the
  // frame keeps its rainbow lag. A spatially varying version of the two delay params; idle = 0,
  // so the default picture is unchanged.
  let held = step(0.5, u.zoom_config.w);
  let pd = (uv - u.zoom_config.yz) * vec2<f32>(res.x / res.y, 1.0);
  let lens = held * exp(-dot(pd, pd) * 18.0);
  // Idea 3 (shipped) — fractional delay: G crossfades between neighbouring ring ages so the
  // slider glides instead of stepping (floor matches HEAD's integer age).
  let ageGF = mix(1.0 + zp.x * 7.0, 0.0, lens);
  let ageG = min(u32(ageGF), maxAge);
  let ageG2 = min(ageG + 1u, maxAge);
  let ageGFrac = fract(ageGF);
  let ageB = min(u32(mix(f32(1u + u32(zp.y * 7.0)), 0.0, lens) + 0.5), maxAge);
  let blendAmt   = clamp(zp.z * (1.0 + bass * 0.4), 0.0, 1.0);
  let displaceBase = zp.w * 0.04 * (1.0 + bass * 0.6 + treble * 0.3);
  let lumaBoost  = 1.0 + zp.w * (1.0 + mids * 0.5);

  let historyHead = u32(extraBuffer[4]);

  // Current frame for R
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  // Idea 2 — motion-gated displacement: only pixels that changed since the newest ring
  // frame wobble, so static areas stay clean and moving edges shimmer.
  let recent = frameAt(uv, historyHead, histDepth, 1u, current);
  let motion = smoothstep(0.03, 0.2, length(recent.rgb - current.rgb));
  let displace = displaceBase * (0.15 + 0.85 * motion) * (1.0 - 0.8 * lens);

  // G channel: delayed frame with slight temporal angular drift
  let dispG = displacedUV(uv, time, displace * 0.6, 12.0);
  // ── Idea 1: leading red ─────────────────────────────────────────
  // Red is sampled opposite the green displacement, and only where the
  // motion gate is already open, so static areas keep the live red.
  let leadUV = clamp(uv - (dispG - uv) * 0.65, vec2<f32>(0.0), vec2<f32>(1.0));
  let leadFrame = textureSampleLevel(readTexture, u_sampler, leadUV, 0.0);
  let histG = mix(
    frameAt(dispG, historyHead, histDepth, ageG, current),
    frameAt(dispG, historyHead, histDepth, ageG2, current),
    ageGFrac);

  // B channel: older frame with larger noise displacement and opposite drift
  let dispB = displacedUV(uv, time, displace, 94.0);
  // Idea 1 (shipped) — comet-tail integration: B averages every ring frame from the G age out to
  // the B age (weighted toward the oldest), turning the blue copy into a continuous streak.
  // ── Idea 1: highlight-weighted comet (tube comet-tailing) ───────
  // Each tap is weighted by its own luma (tapWeight): a tube camera's charge lag is signal
  // dependent, so a bright highlight leaves a long, strong comet while a dark object leaves a
  // faint one. Same taps as before; normalised by the summed weights, so an evenly lit tail
  // averages exactly as it did.
  let tailStart = min(ageG, ageB);
  let oldestTap = frameAt(dispB, historyHead, histDepth, ageB, current);
  let oldestW = 2.0 * tapWeight(oldestTap);
  var tailSum = oldestTap * oldestW;
  var tailW = oldestW;
  for (var a: u32 = tailStart; a < ageB; a = a + 1u) {
    let tap = frameAt(dispB, historyHead, histDepth, a, current);
    let tw = tapWeight(tap);
    tailSum += tap * tw;
    tailW += tw;
  }
  let histB = tailSum / tailW;
  // ── Idea 2 (shipped): disagreement fringe ───────────────────────
  // Where the green delay and the blue comet disagree, a neutral rim
  // marks the edge of the ghost. Rescue: compare LUMA of the two delayed frames — HEAD compared
  // histG.g with histB.b (two different channels), which on a static coloured photo read the
  // photo's own g-b chroma and desaturated the whole frame by up to 45%.
  let disagree = smoothstep(0.04, 0.28, abs(rgbToLuma(histG.rgb) - rgbToLuma(histB.rgb)));

  // Rescue — tube-lag discharge: the ring holds this shader's own output, so the delayed
  // channels leak toward the live pixel each loop. leak = 1 - 0.96/boost keeps the loop gain
  // (1-leak)*boost below 1 for every slider value, so no ghost can latch or run away; the
  // luma boost trades comet vividness for comet length.
  let leak = clamp(1.0 - 0.96 / lumaBoost, 0.12, 0.7);
  let lift = (lumaBoost - 1.0) * motion;
  let lagG = liftCh(mix(histG.g, current.g, leak), lift);
  let lagB = liftCh(mix(histB.b, current.b, leak), lift);

  // Assemble RGB ghost with per-channel temporal offset (R live + leading red)
  let ghostRGB = vec3<f32>(
    mix(current.r, leadFrame.r, motion * (1.0 - lens)),
    lagG,
    lagB,
  );

  // The trail falloff scales only the ghost deviation, so the live photo is never darkened.
  let trail = trailFalloff(uv, 0.35 + zp.w * 0.25);
  let output = current.rgb + (ghostRGB - current.rgb) * (blendAmt * trail);
  let ghostSpread = length(output - current.rgb);

  let fringed = mix(output, vec3<f32>(rgbToLuma(output)), disagree * 0.45);

  // Preserve input alpha, boosted by ghost energy
  let alpha = clamp(current.a * 0.5 + ghostSpread * 3.0 + disagree * 0.25 + bass * 0.1, 0.0, 1.0);
  let finalOut = vec4<f32>(fringed, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
