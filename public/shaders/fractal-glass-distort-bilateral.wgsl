// ═══════════════════════════════════════════════════════════════════
//  fractal-glass-distort-bilateral — Recursive Glass & Bilateral Filter
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fractal-glass-distortion, bilateral-filter, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: fold caustics (Jacobian of the recursive warp → light concentrates along fold curves); Cauchy dispersion along the bend (§12.2F Cauchy dispersion, n(λ)=A+B/λ² applied to the displacement vector, on top of HEAD's flat R/B split); joint depth-range bilateral (RGB × depth range, resolution-aware tap spacing). Rescued: the scratch-buffer pivot spring never persisted → A-texel spring + eased click envelope; the bilateral result was discarded for R and B (and its sigma was sub-pixel) → it now reaches every channel; `time*(1+audio)` phase teleport → bounded audio offset; C ghost mixed in display space and clamped.
//  A packing: ACES display RGBA (unchanged). Texels (0,0) = (pivot.xy, pivot velocity.xy) and (1,0) = (fract(lastTime), heldEnv, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible); C is not read on them.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=RotationSpeed, y=Scale, z=RefractStrength, w=BilateralMix

const SENT: f32 = 0.7371;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// The 4-layer rotate/scale/sine recursion around the pivot (HEAD's maths, unchanged),
// factored out so Idea 1 can difference it. cs[i] = (cos, sin) of layer i's twist angle.
fn glassWarp(p0: vec2<f32>, pivot: vec2<f32>, cs: array<vec2<f32>, 4>, scaleBase: f32,
             refractStr: f32, phase: vec2<f32>) -> vec2<f32> {
  var total = vec2<f32>(0.0);
  var curr = p0;
  for (var i = 0; i < 4; i = i + 1) {
    let rel = curr - pivot;
    let c = cs[i].x;
    let s = cs[i].y;
    let rotated = vec2<f32>(rel.x * c - rel.y * s, rel.x * s + rel.y * c);
    let sineWarp = vec2<f32>(
      sin(rotated.y * 10.0 + phase.x),
      cos(rotated.x * 10.0 + phase.y)
    );
    total += sineWarp * refractStr / (f32(i) + 1.0);
    curr = rotated * scaleBase + pivot;
  }
  return total;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // ── Pivot spring + eased click envelope, persisted in two A texels ──────────
  // HEAD kept this critically damped spring in extraBuffer[133..138] (single writer at (0,0)),
  // which is re-uploaded zeroed every frame: the pivot was the raw cursor / (0,0) / a race, and
  // `held` popped the twist by 0.2 rad on click. Texel (0,0) = (pos.xy, vel.xy), texel (1,0) =
  // (fract(lastTime), heldEnv, 0, SENT). Every thread integrates the same step from the stored
  // state; the sentinel guards the first frame / an inherited C from the previous shader.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var mouse = select(rawMouse, st0.xy, stateOk);
  var mVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  var heldEnv = select(held, st1.y, stateOk);
  let sdt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  let omega = 6.4807; // sqrt(42): HEAD's stiffness, critically damped
  mVel += ((rawMouse - mouse) * (omega * omega) - mVel * (2.0 * omega)) * sdt;
  mouse += mVel * sdt;
  // f16 rest-snap: a spring stored in rgba16float stalls ~2e-3 short of the cursor with a
  // residual velocity that never decays; settle exactly once near and slow.
  let settled = all(abs(rawMouse - mouse) < vec2<f32>(0.004)) && length(mVel) < 0.06;
  mouse = select(mouse, rawMouse, settled);
  mVel = select(mVel, vec2<f32>(0.0), settled);
  heldEnv += (held - heldEnv) * (1.0 - exp(-12.0 * sdt));
  heldEnv = select(heldEnv, held, abs(held - heldEnv) < 0.004);

  // Exact parameter contracts
  let rot_speed = u.zoom_params.x * 3.14159265;
  let scale_base = mix(0.9, 1.3, u.zoom_params.y);
  let refract_str = mix(0.01, 0.07, u.zoom_params.z) * (1.0 + bass * 0.3);
  let bilateralMix = u.zoom_params.w;

  let p = (uv - 0.5) * aspectVec;
  let mouse_p = (mouse - 0.5) * aspectVec;

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleWarp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * aspectVec);
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleWarp += rDir * wave * 0.04;
    }
  }

  // Fractal glass distortion. The audio rides a bounded phase OFFSET: HEAD's
  // time*(1+audio) shifted the whole pattern by time·Δaudio (a teleport at t≫1).
  var cs: array<vec2<f32>, 4>;
  for (var i = 0; i < 4; i = i + 1) {
    let a = rot_speed * (f32(i) + 1.0) * 0.3 + heldEnv * 0.2;
    cs[i] = vec2<f32>(cos(a), sin(a));
  }
  let phase = vec2<f32>(time + mids * 0.6, time + treble * 0.6);
  let p0 = p + rippleWarp;
  let total_disp = glassWarp(p0, mouse_p, cs, scale_base, refract_str, phase);

  // ── Idea 1: fold caustics ─────────────────────────────────────────────────
  // The ray map x → x + d(x) of rippling glass degenerates (det J → 0) along fold curves:
  // transmitted light piles up into bright filaments there and thins out where the glass
  // stretches the image. J comes from two forward differences of the same recursion.
  let hJ = 0.004;
  let dX = (glassWarp(p0 + vec2<f32>(hJ, 0.0), mouse_p, cs, scale_base, refract_str, phase) - total_disp) / hJ;
  let dY = (glassWarp(p0 + vec2<f32>(0.0, hJ), mouse_p, cs, scale_base, refract_str, phase) - total_disp) / hJ;
  let detJ = (1.0 + dX.x) * (1.0 + dY.y) - dX.y * dY.x;
  let focus = clamp(1.0 / max(abs(detJ), 0.25), 0.5, 4.0);
  let causticGain = (1.0 + 0.40 * (focus - 1.0)) * 0.99;

  let final_p = p + total_disp;
  let distortedUV = clamp(final_p / aspectVec + 0.5, vec2<f32>(0.001), vec2<f32>(0.999));

  let distortedColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);
  let centreDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0).r;

  // ── Bilateral edge-preserving filtering ──────────────────────────────────
  let mouseDist = length((uv - mouse) * aspectVec);
  let mouseFactor = exp(-mouseDist * mouseDist * 8.0);
  let spatialSigmaBase = mix(0.1, 1.0, bilateralMix);
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);
  let finalSigma = max(spatialSigma, 0.02);

  // Sigma is in TAP units; the tap spacing is resolution-aware (1 px up to 256 p, 2.25 px at
  // 576 p) so the dream smoothing exists at any working size (HEAD: 0.55 px at the default).
  // The radius follows the sigma (rings whose weight is < ~2 % are not fetched).
  let tapStep = max(1.0, res.y / 256.0);
  let radius = select(select(0, 1, finalSigma > 0.30), 2, finalSigma > 0.72);
  let colorSigma = 0.2;
  // ── Idea 3: joint depth-range bilateral ──────────────────────────────────
  // The range weight is RGB range × depth range: a neighbour at another depth does not bleed
  // through the glass even when its colour matches (subject vs. similar background).
  let depthSigma = 0.12;
  let invS = 1.0 / (2.0 * finalSigma * finalSigma + 0.001);
  let invC = 1.0 / (2.0 * colorSigma * colorSigma);
  let invD = 1.0 / (2.0 * depthSigma * depthSigma);

  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  for (var dy = -radius; dy <= radius; dy = dy + 1) {
    for (var dx = -radius; dx <= radius; dx = dx + 1) {
      let off = vec2<f32>(f32(dx), f32(dy));
      let neighborUV = clamp(distortedUV + off * pixelSize * tapStep, vec2<f32>(0.001), vec2<f32>(0.999));
      let neighbor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
      let nDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, neighborUV, 0.0).r;
      let dc = neighbor - distortedColor.rgb;
      let dd = nDepth - centreDepth;
      let weight = exp(-dot(off, off) * invS - dot(dc, dc) * invC - dd * dd * invD);
      accumColor += neighbor * weight;
      accumWeight += weight;
    }
  }

  var filtered = distortedColor.rgb;
  if (accumWeight > 0.001) {
    filtered = mix(distortedColor.rgb, accumColor / accumWeight, bilateralMix);
  }

  // ── Idea 2: Cauchy dispersion along the bend (chromatic split) ─────────────
  // HEAD's flat horizontal R/B split (0.03·mix) is kept. On top, the real glass term:
  // each channel follows the bend scaled by n(λ)/n(550 nm), n = 1 + B/λ² (Cauchy, B exaggerated
  // so blue bends ≈1.2× and red ≈0.9× of green), so fringes also hug every ripple crest.
  let lam = vec3<f32>(0.650, 0.550, 0.450);
  let nCauchy = vec3<f32>(1.0) + 0.16 / (lam * lam);
  let cauchy = nCauchy / nCauchy.y;
  let dispUV = total_disp / aspectVec;
  let aberration = 0.03 * bilateralMix * (1.0 + treble * 0.4);
  let r_uv = clamp(distortedUV + vec2<f32>(aberration, 0.0) + dispUV * (cauchy.x - 1.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let b_uv = clamp(distortedUV - vec2<f32>(aberration, 0.0) + dispUV * (cauchy.z - 1.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let rawR = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
  let rawB = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;
  // The bilateral base reaches every channel; the raw R/B taps contribute only their fringe.
  var color = filtered + vec3<f32>(rawR - distortedColor.r, 0.0, rawB - distortedColor.b);
  color = max(color, vec3<f32>(0.0)) * causticGain;

  // Exact dataTextureC persistence, mixed in DISPLAY space (C holds ACES output); clamped so an
  // inherited C from the previous shader cannot flash; not read on the two state texels.
  let isState = global_id.y == 0u && global_id.x < 2u;
  let prevC = clamp(textureLoad(dataTextureC, pixel, 0).rgb, vec3<f32>(0.0), vec3<f32>(1.0));
  let finalRGB = mix(aces(color), prevC, select(0.07, 0.0, isState));

  let alpha = clamp(0.4 + length(total_disp) * 8.0 + heldEnv * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  var aOut = finalPixel;
  if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(mouse, mVel); }
  if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), heldEnv, 0.0, SENT); }

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, aOut);
  // Depth contract unchanged from HEAD: passthrough at the pixel's own uv (centreDepth is only the
  // bilateral range-weight centre).
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
