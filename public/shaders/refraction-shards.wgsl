// ═══════════════════════════════════════════════════════════════════
//  Refraction Shards
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06, 2026-11-09
//  Ideas: per-shard tilt -> Snell deflection with Cauchy-weighted dispersion (§12.2F Snell vector refraction + Cauchy dispersion: steeper shards deflect and fringe harder, blue bends most); Beer-Lambert slab tint (§12.2F Beer-Lambert: per-shard thickness, path 1/cos(theta_t) from the same Snell result, thick/steep shards go sea-green). Rescued: the cursor spring lived in extraBuffer[133..138] (zeroed every frame, single-writer race) so it was a raw cursor — now two A texels; dead plasmaBuffer[3]/[7] bins removed; roughness wobble keyed per shard instead of per pixel-grid cell; red/blue dispersion order matched to glass; inherited-C clamp.
//  A packing: HDR (pre-ACES) trail RGB + semantic alpha; C is read back as that HDR history, ACES only on writeTexture (HEAD's old "ACES display RGBA" line was wrong). Texels (0,0) = (spring pos.xy, spring vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible; their trail is read from the texel below).
//  Motion: crystalline shard facet drift + traveling fracture wavefronts
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ShardSize, y=Refraction, z=Roughness, w=PrismEffect

const SENT: f32 = 0.7371;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let q = vec2<f32>(
    sin(dot(p, vec2<f32>(127.1, 311.7))),
    sin(dot(p, vec2<f32>(269.5, 183.3)))
  ) * 43758.5453;
  return fract(q);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.50, 0.50, 0.52) +
         vec3<f32>(0.46, 0.42, 0.48) *
         cos(6.28318 * (vec3<f32>(1.0, 0.72, 0.53) * t + vec3<f32>(0.02, 0.32, 0.62)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Sprung cursor, persisted in two A texels ────────────────────────
  // HEAD kept the spring in extraBuffer[133..138], which is re-uploaded zeroed every frame and was
  // written by one thread only: every other thread saw the raw cursor. Texel (0,0) = (pos.xy,
  // vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT); every thread integrates the same
  // critically damped step (omega 14) from the stored state; fract(time) stays exact on f16.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var spring = select(mouse, st0.xy, stateOk);
  var sVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let sdt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  let omega = 14.0;
  sVel += ((mouse - spring) * (omega * omega) - sVel * (2.0 * omega)) * sdt;
  sVel = clamp(sVel, vec2<f32>(-4.0), vec2<f32>(4.0));
  spring += sVel * sdt;
  // f16 rest-snap: a spring stored in rgba16float stalls short of the cursor with residual velocity.
  let settled = all(abs(mouse - spring) < vec2<f32>(0.004)) && length(sVel) < 0.06;
  spring = select(spring, mouse, settled);
  sVel = select(sVel, vec2<f32>(0.0), settled);

  // Four saved controls preserved
  let shardScale = mix(5.0, 28.0, u.zoom_params.x);
  let refraction = mix(0.01, 0.14, u.zoom_params.y) * (1.0 + bass * 0.4);
  let roughness = u.zoom_params.z * 0.04;
  let prism = mix(0.005, 0.05, u.zoom_params.w) * (1.0 + treble * 0.65);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.65, 1.4, depth);

  // Capped click ripple fracture wavefronts
  var rippleFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let front = exp(-abs(d - age * 0.44) * 34.0) * exp(-age * 1.5);
      rippleFront += front;
    }
  }

  // Continuous smooth facet drift (no frame-quantized hash jumps)
  let p = uv * shardScale;
  let cell = floor(p);
  let local = fract(p);

  var bestDist = 10.0;
  var secondDist = 10.0;
  var bestDelta = vec2<f32>(0.0);
  var cellSeed = vec2<f32>(0.0);

  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let neighbor = vec2<f32>(f32(i), f32(j));
      let h = hash22(cell + neighbor);
      // Smooth sinusoidal orbital drift per shard
      let drift = vec2<f32>(sin(time * 0.6 + h.x * 6.28), cos(time * 0.5 + h.y * 6.28)) * 0.15;
      let point = neighbor + h * 0.7 + 0.15 + drift;
      let delta = point - local;
      let d = dot(delta, delta);
      if (d < bestDist) {
        secondDist = bestDist;
        bestDist = d;
        bestDelta = delta;
        cellSeed = h;
      } else if (d < secondDist) {
        secondDist = d;
      }
    }
  }

  // Shard facet edge
  let bestD = sqrt(bestDist);
  let facetEdge = sqrt(secondDist) - bestD;
  let edgeLine = 1.0 - smoothstep(0.01, 0.08, facetEdge);

  // Proximity to smoothed cursor
  let toSpring = (uv - spring) * aspectVec;
  let distSpring = length(toSpring);
  let mouseInteraction = smoothstep(0.50, 0.02, distSpring) * select(1.0, 1.5, held);

  // Normal deflection direction from shard geometry and pointer (unchanged)
  let shardNormal = safeNormalize(bestDelta + toSpring * (0.35 + rippleFront * 0.6));

  // ── Idea 1: per-shard tilt -> Snell deflection (§12.2F Snell vector refraction) ──
  // HEAD's unit normal gave every pixel the same deflection magnitude. A real glass facet has a
  // TILT: the pixel's distance to its shard point is the cone slope (flat apex, steep rim) and
  // cellSeed gives each shard its own base tilt. refract() of a ray along -z against that tilted
  // normal (glass n = 1.5) yields the deflection; the gain is normalised to 1 at tilt 0.55 rad so
  // the Refraction slider keeps its meaning and the mean picture its strength.
  let slope = smoothstep(0.0, 0.5, bestD);
  let tilt = (0.30 + 0.45 * cellSeed.y) * mix(0.7, 1.2, slope);
  // refract(vec3(0,0,-1), n = (sin t, 0, cos t), eta = 1/1.5) expands to
  //   sT = sin t; cT = cos t; kk = sqrt(1 - sT^2 / 2.25); tx = (kk - cT / 1.5) * sT;
  //   cosT = 2/3 + kk*cT - (2/3)*cT^2; gain = tx / cosT / 0.19655.
  // Evaluated per pixel it is sin + 3 sqrt + a divide, so over the tilt range this shader reaches
  // (0.21..0.88 rad) it is replaced by cubic fits of the same two quantities (max rel. error 0.25%
  // for the gain, 0.01% for cosT; fitted offline against the closed form).
  let snellGain = ((0.71636 * tilt - 0.36508) * tilt + 1.83126) * tilt - 0.01635;
  let cosT = ((-0.06235 * tilt - 0.00011) * tilt - 0.0192) * tilt + 1.00224;

  // Roughness wobble keyed by SHARD (HEAD keyed it by pixel-grid cell, which stamped a square grid
  // of offset blocks across the shards at high roughness).
  let wobble = (hash22(cellSeed * 91.7 + vec2<f32>(3.1, 7.7)) - vec2<f32>(0.5)) * roughness;
  let totalOffset = (shardNormal * refraction * snellGain + wobble) * (1.0 + mouseInteraction * 0.7 + rippleFront * 0.8) * depthFactor;

  let centerUV = clamp(uv + totalOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  // Cauchy 3-band spectral dispersion — n(lambda) = A + B/lambda^2 at 650/550/450 nm splits R:G:B
  // as -0.73 : 0 : +1.27 (blue bends most along the deflection, red least; mean |split| = HEAD's
  // 1.2), and the split scales with the shard's own deflection gain (steeper shard, harder fringe).
  let dispVec = shardNormal * prism * snellGain;
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(centerUV - dispVec * 0.876, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let gSample = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0).g;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + dispVec * 1.524, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  var color = vec3<f32>(rSample, gSample, bSample);

  // ── Idea 2: Beer-Lambert slab tint (§12.2F Beer-Lambert) ───────────
  // Each shard is a slab of its own thickness; the ray crosses it along 1/cos(theta_t) (theta_t
  // from the Snell result above), so thick and steep shards absorb more. Soda-lime-ish sigma
  // (red strongest, green weakest) = sea-green; the thinnest shards stay clear (path offset 0.4).
  let slab = mix(0.4, 1.6, cellSeed.x) / cosT;
  color = color * exp(-vec3<f32>(0.16, 0.04, 0.10) * 1.25 * max(slab - 0.4, 0.0));

  // Prismatic iridescent facet edge glint
  let glintPalette = palette(cellSeed.x * 2.0 + time * 0.2 + mids * 0.4 + rippleFront);
  let facetGlint = pow(edgeLine, 2.0) * (0.4 + treble * 0.8);
  color += glintPalette * facetGlint * 1.3;

  // Specular flare at cursor
  color += vec3<f32>(1.0, 0.95, 0.8) * mouseInteraction * edgeLine * (0.4 + bass * 0.5);

  // Exact previous frame history load from dataTextureC for crystal persistence (HDR trail);
  // the two state texels hold spring state in C, not trail, so they read the texel below as their
  // history (reading 0 there made them 6-26% darker than their neighbours); an inherited C from
  // another shader is clamped.
  let isStateTexel = coord.y == 0 && coord.x <= 1;
  let histRaw = textureLoad(dataTextureC, select(coord, vec2<i32>(coord.x, 1), isStateTexel), 0);
  let hist = vec4<f32>(clamp(histRaw.rgb, vec3<f32>(0.0), vec3<f32>(4.0)), histRaw.a);
  let feedbackWeight = mix(0.06, 0.26, clamp(mouseInteraction * 0.5 + rippleFront * 0.4, 0.0, 1.0));
  var hdr = mix(color, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(max(hdr, vec3<f32>(0.0)));
  let semanticAlpha = clamp(0.78 + edgeLine * 0.2 + mouseInteraction * 0.15 + rippleFront * 0.2, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  var aOut = vec4<f32>(hdr, semanticAlpha);
  if (coord.y == 0 && coord.x == 0) { aOut = vec4<f32>(spring, sVel); }
  if (coord.y == 0 && coord.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, aOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.25 + (1.0 - edgeLine) * 0.65, 0.4), 0.0, 1.0), 0.0, 0.0, 0.0));
}
