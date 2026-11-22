// ═══════════════════════════════════════════════════════════════════
//  Chrono Luma Slit Scan
//  Category: post-processing
//  Upgraded: 2026-10-04, 2026-11-15, 2026-11-22
//  Ideas: isochrone contour lines at integer-age seams; scan-runner windows onto the oldest frame; slit-travel smear; raised-cosine shutter; runner wake (scan-beam persistence); long-exposure integration
//  A packing: display RGBA
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a
//         hardcoded 8 — see HISTORY RING DEPTH below
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

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

  let uv   = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let held = step(0.5, u.zoom_config.w);
  let mouse = u.zoom_config.yz;

  let spreadBase = clamp(u.zoom_params.x * (1.0 + bass * 0.3), 0.0, 1.0);
  let spread = spreadBase * mix(1.0, 0.55, held * exp(-dot(uv - mouse, uv - mouse) * 8.0));
  let warpAmt    = u.zoom_params.y * 0.04 * (1.0 + mids * 0.5 + treble * 0.25);
  let lumaGamma  = 0.1 + u.zoom_params.z * 0.9;
  let origBlend  = u.zoom_params.w;

  let historyHead = u32(extraBuffer[4]);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma    = dot(current.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

  let slitBandH = pow(max(0.0, sin(uv.y * 48.0 - time * (14.0 + bass * 6.0))), 14.0);
  let slitBandV = pow(max(0.0, sin(uv.x * 52.0 - time * (18.0 + treble * 8.0))), 12.0);
  let scanRunner = slitBandH * 0.5 + slitBandV * 0.5;

  let lumaMapped = pow(clamp(luma, 0.0, 1.0), lumaGamma);
  let lumaAdjusted = clamp(lumaMapped + scanRunner * 0.08, 0.0, 1.0);

  // ── HISTORY RING DEPTH (floor fix, 2026-09-21) ───────────────────
  // The ring is at most 8 layers; after the VRAM probe the runtime may
  // allocate 8, 4 or 1, and it wraps its write head at the ALLOCATED
  // count (renderer/webgpu/frame.ts). A hardcoded ring depth of 8 asked
  // for layers that do not exist on a 4- or 1-layer device and WGSL
  // clamped them to the last layer: scrambled frame order, silently.
  // reach = oldest age this ring can actually supply (0 on a 1-layer ring).
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let reach   = histDepth - 1u;
  let maxAge  = 1u + u32(spread * f32(max(reach, 1u) - 1u));
  let ageLuma = 1.0 + (1.0 - lumaAdjusted) * f32(maxAge - 1u);
  // Idea 2 — runner time-windows: inside the sweeping scan bands the age jumps to the
  // oldest frame the ring holds, so the runners scan old time across the picture.
  let windowOpen = step(1.5, f32(reach));
  let bandGate = smoothstep(0.3, 0.75, scanRunner) * windowOpen;
  // ── Idea 1: runner wake (scan-beam persistence) ─────────────────
  // A scanning beam keeps a decaying trace behind it. Each runner's phase (the same phase that
  // drives slitBandH / slitBandV) gives d = 0 at the beam and d -> 1 just behind it (the runners
  // travel toward +y / +x); exp(-5 (1-d)) is a sharp leading edge on the side the runner has just
  // passed and an exponential tail back toward the luma age. The window onto the oldest frame
  // therefore drags a fading trail instead of a symmetric blip.
  let dH = fract((uv.y * 48.0 - time * (14.0 + bass * 6.0) - 1.5707963) / 6.2831853);
  let dV = fract((uv.x * 52.0 - time * (18.0 + treble * 8.0) - 1.5707963) / 6.2831853);
  let wake = exp(-5.0 * (1.0 - max(dH, dV)));
  let windowGate = max(bandGate, 0.6 * wake * windowOpen);
  let ageFlt  = mix(ageLuma, f32(max(reach, 1u)) - 0.001, windowGate);
  let age     = clamp(u32(ageFlt), 1u, max(reach, 1u));
  let ageFrac = fract(ageFlt);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  var warpOffset = vec2<f32>(0.0);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple  = u.ripples[i];
    let rDist   = length(uv - ripple.xy);
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let wave   = sin(rDist * 30.0 - elapsed * 8.0) * exp(-rDist * 6.0 - elapsed * 1.5);
      warpOffset = warpOffset + normalize(uv - ripple.xy + vec2<f32>(0.0001)) * wave * warpAmt;
    }
  }
  warpOffset = warpOffset + (depth - 0.5) * vec2<f32>(sin(time * 0.3), cos(time * 0.2)) * warpAmt * 0.5;

  let sampleUV  = clamp(uv + warpOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  // frameAt clamps both ages to `reach`; on a 1-layer ring both are the live frame.
  let frameA = frameAt(sampleUV, historyHead, histDepth, age, current);
  let frameB = frameAt(sampleUV, historyHead, histDepth, age + 1u, current);

  // ── Idea 4: raised-cosine shutter ──────────────────────────────
  // The two frames overlap like a slit exposure. Isochrones below still key off raw ageFrac.
  let shutter = 0.5 - 0.5 * cos(clamp(ageFrac, 0.0, 1.0) * 3.14159265);
  let slitShot = mix(frameA, frameB, shutter);
  // ── Idea 2: long-exposure integration ───────────────────────────
  // A slit exposes longer where the scene is darker, and a longer exposure integrates more of
  // what happened. Where the chosen age is deep (>= ~2 frames) the colour becomes the mean of
  // the frame at that age and a shallower one (about 0.6 of it), weighted by how deep the age
  // is, so dark regions show the blur of the span instead of one frozen frame.
  let ageM = max(1u, u32(f32(age) * 0.6));
  let tapM = frameAt(sampleUV, historyHead, histDepth, ageM, current);
  let expo = 0.8 * smoothstep(1.5, 5.0, ageLuma) * (1.0 - windowGate);
  let slitColor = mix(slitShot, (slitShot + tapM) * 0.5, expo);

  // ── Idea 3: slit-travel smear ──────────────────────────────────
  // A horizontal band travels in y, a vertical band in x. Two taps along that travel, same age.
  let travel = vec2<f32>(slitBandV, slitBandH);
  let travelLen = max(length(travel), 1e-4);
  let stepUv = travel / travelLen * (0.006 * spread);
  let smearA = frameAt(clamp(sampleUV - stepUv, vec2<f32>(0.0), vec2<f32>(1.0)), historyHead, histDepth, age, current);
  let smearB = frameAt(clamp(sampleUV + stepUv, vec2<f32>(0.0), vec2<f32>(1.0)), historyHead, histDepth, age, current);
  let smeared = mix(slitColor, (smearA + smearB) * 0.5, clamp(travelLen * 1.6, 0.0, 0.65) * spread);
  var output   = mix(smeared, current, origBlend);

  // Idea 1 — isochrones: thin contours where the luma-chosen age crosses a whole frame,
  // drawing the luma→time map as a topographic chart (absent on a 1–2 layer ring).
  let seamDist = min(ageFrac, 1.0 - ageFrac);
  let iso = (1.0 - smoothstep(0.0, 0.07, seamDist)) * step(2.5, f32(maxAge)) * (1.0 - windowGate) * (1.0 - origBlend);
  output = vec4<f32>(output.rgb * (1.0 - iso * 0.45) + vec3<f32>(0.10, 0.11, 0.13) * iso * (0.6 + treble * 0.4), output.a);
  let motionD  = length(slitColor.rgb - current.rgb);
  let alpha    = clamp(0.6 + motionD * 2.0 + bass * 0.2 + scanRunner * 0.1, 0.0, 1.0);
  let finalOut = vec4<f32>(output.rgb, alpha);

  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
