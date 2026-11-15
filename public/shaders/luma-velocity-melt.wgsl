// ═══════════════════════════════════════════════════════════════════
//  Luma Velocity Melt — exact-load HDR display-history advection.
//  Category: liquid-effects
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: drip pinch-off into beaded columns; depth-ledge pooling; Marangoni thermocapillary spread (native); rivulet meander (native)
//  A packing: untonemapped HDR RGB + semantic alpha; B intentionally unwritten.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> { return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Tuning for the 2026-11-15 ideas. Zero a gain to get the 2026-09 look back exactly.
const MARANGONI_GAIN: f32 = 0.9;   // lateral spread speed per unit of temperature step, in melt-speed units
const MARANGONI_UV: f32 = 0.02;    // half-width (uv of image height) of the temperature stencil — resolution independent
const MEANDER_AMP: f32 = 0.016;    // rivulet sway amplitude (uv), scaled by melt speed
const MEANDER_FOLLOW: f32 = 1.0;   // how much the stream follows the wandering centre line

fn hotRamp(uv: vec2<f32>, threshold: f32) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  return smoothstep(threshold - 0.12, threshold + 0.12, dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // These saved controls have non-normalized ranges and are used directly.
  let meltSpeed = max(u.zoom_params.x, 0.0); let heat = max(u.zoom_params.y, 0.0);
  let persistence = clamp(u.zoom_params.z, 0.5, 0.999); let threshold = u.zoom_params.w;
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLuma = dot(source.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let hot = smoothstep(threshold - 0.12, threshold + 0.12, sourceLuma) * (1.0 + heat * 0.18 + bass * 0.45);
  let nX = noise2(uv * vec2<f32>(8.0, 14.0) + vec2<f32>(time * 0.12, -time * 0.08));
  let nY = noise2(uv.yx * vec2<f32>(11.0, 7.0) + vec2<f32>(4.2, time * 0.1));
  var flow = vec2<f32>((nX - 0.5) * meltSpeed * (1.8 + mids), meltSpeed * hot * (1.0 + (1.0 - depth) * 0.5));

  // ── Idea 1: drip pinch-off ────────────────────────────────────────
  // Melting material does not slide as a sheet: it necks into columns and
  // beads into drops. Each ~7px column gets its own bead phase travelling
  // down it; the vertical flow slows at the beads (so content piles into
  // them) and speeds through the necks, while a lateral pull toward the
  // column centre narrows the stream. Only where the source is hot.
  let dripW = 7.0 / res.x;

  // ── Idea 4: rivulet meander (native) ──────────────────────────────
  // A real rivulet wanders; it does not run down a ruler-straight line. HEAD measured
  // colLocal from a fixed vertical grid. The centre line of each group of columns now
  // sways with y (two slow sines whose phase is a smooth function of x, so neighbouring
  // columns wander together and no seam appears), and the stream follows its own centre
  // line (see the lateral-flow block below). Amplitude grows with melt speed.
  let meanderGroup = uv.x / (dripW * 5.0);
  let meanderPh1 = 6.2831853 * noise2(vec2<f32>(meanderGroup, 0.37));
  let meanderPh2 = 6.2831853 * noise2(vec2<f32>(meanderGroup + 17.3, 5.11));
  let meanderA = MEANDER_AMP * min(0.6 + meltSpeed * 60.0, 1.5);
  let meanderArg1 = uv.y * 50.0 + meanderPh1 + time * 0.35;
  let meanderArg2 = uv.y * 118.0 + meanderPh2 - time * 0.5;
  let meanderOffset = meanderA * (0.65 * sin(meanderArg1) + 0.35 * sin(meanderArg2));
  let meanderSlope = meanderA * (0.65 * 50.0 * cos(meanderArg1) + 0.35 * 118.0 * cos(meanderArg2));
  let columnX = uv.x - meanderOffset;
  let dripCol = floor(columnX / dripW);
  let colSeed = hash21(vec2<f32>(dripCol, 3.17));
  let colLocal = fract(columnX / dripW) - 0.5;
  // Idea 1 (cont.): beads and pinch, now measured against the wandering column.
  let beadPhase = uv.y * (7.0 + colSeed * 5.0) - time * (0.25 + meltSpeed * 30.0) - colSeed;
  let bead = 0.5 + 0.5 * cos(beadPhase * 6.2831853);
  let pinch = clamp(hot, 0.0, 1.0);
  flow.y *= mix(1.0, 0.3 + 1.4 * bead, pinch * 0.8);
  flow.x -= colLocal * dripW * pinch * (0.15 + meltSpeed * 12.0);

  // ── Idea 2: depth-ledge pooling ───────────────────────────────────
  // The melt already reads scene depth. Where depth steps sharply directly
  // below this pixel there is a ledge in the scene: the drip stops there,
  // pools, and spills a little sideways along the edge — wax running down
  // a real 3-D surface instead of down a flat photograph.
  let depthBelow = textureLoad(readDepthTexture, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
  let ledge = smoothstep(0.02, 0.12, abs(depthBelow - depth)) * pinch;
  flow.y *= 1.0 - ledge * 0.85;
  flow.x += (nY - 0.5) * ledge * meltSpeed * 3.0;

  // ── Idea 3: Marangoni thermocapillary spread (native) ─────────────
  // Surface tension falls as temperature rises, so a hot film pulls material from hot
  // (low sigma) toward cold (high sigma): a hot region does not only fall, it SPREADS
  // sideways at its rim. `hot` is already a temperature field but HEAD only used its
  // value at the pixel; four taps of the same luma ramp give its gradient. The flow is
  // down-gradient, strongest at the boundary of the bright region, mostly sideways
  // (the y part is damped so the melt does not climb against gravity), and scales with
  // the saved melt speed so Melt Speed = 0 still means no motion.
  let marDy = MARANGONI_UV;                    // the same pixel distance on both axes
  let marDx = MARANGONI_UV * res.y / res.x;
  let marGrad = vec2<f32>(
    hotRamp(uv + vec2<f32>(marDx, 0.0), threshold) - hotRamp(uv - vec2<f32>(marDx, 0.0), threshold),
    hotRamp(uv + vec2<f32>(0.0, marDy), threshold) - hotRamp(uv - vec2<f32>(0.0, marDy), threshold));
  flow -= marGrad * vec2<f32>(1.0, 0.4) * meltSpeed * MARANGONI_GAIN * (1.0 + heat * 0.1);

  // Idea 4 (cont.): the stream follows its wandering centre line — lateral velocity is the
  // centre line's slope times the (bead/ledge-modulated) fall speed.
  flow.x += meanderSlope * flow.y * pinch * MEANDER_FOLLOW;

  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 75.0); let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist, mouseDist > 0.001);
  flow += tangent / aspectVec * mouseMask * held * (meltSpeed * 4.0 + 0.004);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let delta = (uv - ripple.xy) * aspectVec; let dist = length(delta);
      let ringArg = (dist - age * 0.2) * 42.0;   // squared, not pow(x, 2.0): the base is negative inside the front
      let ring = exp(-ringArg * ringArg) * exp(-age * 1.2);
      let dir = select(vec2<f32>(0.0), delta / dist, dist > 0.001);
      flow += dir / aspectVec * ring * (0.008 + meltSpeed * 2.2); clickEnergy += ring;
    }
  }
  let historyUV = clamp(uv - flow, vec2<f32>(0.001), vec2<f32>(0.999));
  let history = textureLoad(dataTextureC, historyCoord(historyUV, dims), 0);
  let chroma = (0.001 + meltSpeed * 0.7 + treble * 0.002) * normalize(vec2<f32>(flow.x + 0.0001, flow.y + 0.0001));
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(uv + chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(uv - chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let injected = vec4<f32>(sourceR.r, source.g, sourceB.b, max(source.a, max(sourceR.a, sourceB.a)));
  // HEAD only held history where the flow was fast. Beads and ledges are
  // exactly where the flow is slowed on purpose, so they hold history too —
  // that is what makes material pile into drops and pool on the edge.
  let pileHold = max(ledge * 0.9, pinch * bead * 0.6);
  let historyWeight = clamp(persistence * history.a * max(smoothstep(0.001, 0.02, length(flow)), pileHold), 0.0, 0.999);
  var hdr = mix(injected.rgb, history.rgb * (0.992 + bass * 0.004), historyWeight);
  hdr += vec3<f32>(1.0, 0.24, 0.04) * hot * heat * 0.045 + vec3<f32>(0.18, 0.4, 1.0) * clickEnergy * mids * 0.08;
  let alpha = clamp(max(injected.a, history.a * persistence) + hot * 0.04 + clickEnergy * 0.05, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(min(hdr, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(hdr), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + length(flow) * 0.8 + hot * 0.02, 0.0, 1.0), 0.0, 0.0, 0.0));
}
